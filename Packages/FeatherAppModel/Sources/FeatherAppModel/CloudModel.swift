import FeatherCore
import FeatherCrypto
import FeatherSync
import Foundation
import Observation

/// Where account secrets live and how the app talks to a server. Nothing here touches the network.
public struct CloudEnvironment {
    public var secrets: SecretStore
    public var keys: MasterKeyStore
    /// Built only when the app first needs the network.
    public var configuration: () -> URLSessionConfiguration
    public var deviceName: String
    /// Whether Feather Cloud has billing, from the build (false in 1.0.0).
    public var hostedBillingEnabled = CloudServer.hostedBillingEnabled

    /// The Keychain normally; memory for test hosts and other isolated runs, which must never touch real secrets.
    public static func live(isolated: Bool, deviceName: String = defaultDeviceName) -> CloudEnvironment {
        CloudEnvironment(secrets: isolated ? InMemorySecretStore() : KeychainSecretStore(),
                         keys: isolated ? InMemoryMasterKeyStore() : KeychainMasterKeyStore(),
                         configuration: { .ephemeral }, deviceName: deviceName)
    }

    /// The name the account's device list shows: this Mac's name. The iPhone app passes its own (Phase 12).
    public static var defaultDeviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        "iPhone"
        #endif
    }

    public static var memory: CloudEnvironment { live(isolated: true) }
}

public enum CloudState: Equatable {
    case signedOut
    case signedIn(SignedIn)

    public var signedIn: SignedIn? {
        if case .signedIn(let s) = self { return s }
        return nil
    }
}

/// What the app does around a sync pass: save pending edits first, refresh after a pull.
public struct CloudHooks: Sendable {
    public var beforeSync: @MainActor () async -> Void
    public var onPulled: @MainActor (Set<ULID>) async -> Void
}

/// Feather Cloud account and sync state. Views read it; it builds no client and makes no request until the user
/// starts the trial, signs in or connects a server, or a sign-in is stored from an earlier launch.
@MainActor @Observable
public final class CloudModel {
    public static let serverKey = "cloudServer"
    public static let accountKey = "cloudAccount"
    public static let libraryKey = "cloudLibrary"

    public let library: Library
    public let defaults: UserDefaults
    public var environment: CloudEnvironment
    public var hooks: CloudHooks

    public private(set) var state: CloudState = .signedOut
    public private(set) var status: SyncStatus = .idle(lastSynced: nil)
    public private(set) var server: CloudServer
    public private(set) var serverInfo: ServerInfo?
    public private(set) var conflicts: [SyncConflict] = []
    public private(set) var devices: [CloudDevice] = []
    public private(set) var plan: CloudPlan?

    /// The account sheet on the main window, if any.
    public enum Sheet: Identifiable {
        case onboarding(OnboardingFlow)
        case signIn(SignInFlow)
        public var id: String { switch self { case .onboarding: "onboarding"; case .signIn: "signIn" } }
    }
    public var sheet: Sheet?

    public func startTrial() { sheet = .onboarding(OnboardingFlow(cloud: self)) }
    public func showSignIn() {
        let flow = SignInFlow(cloud: self)
        flow.email = reauthEmail ?? ""
        sheet = .signIn(flow)
    }

    /// Set when the server ended the session (401): the email to sign in again with.
    public private(set) var reauthEmail: String?

    /// The server ended this Mac's session (revoked, or the password changed elsewhere): keep the email so the
    /// app asks to sign in again instead of offering a trial.
    public func serverSignedOut() async {
        let email = state.signedIn?.email ?? defaults.string(forKey: Self.accountKey)
        await forgetLocally()
        reauthEmail = email
    }

    private var account: AccountService?
    private var engine: SyncEngine?
    private var statusTask: Task<Void, Never>?

    public var hasAccountService: Bool { account != nil }
    /// Signed out on Feather Cloud with billing: Settings and the footer offer the free trial. Never on another
    /// server, even one with billing: the trial terms are Feather Cloud's.
    public var offersTrial: Bool { state == .signedOut && !isSelfHosted && billingEnabled && reauthEmail == nil }

    /// Whether this server has trials and plans. Signed in, the account says; signed out, the build says for
    /// Feather Cloud and GET /server for another server. Off means: no trial, subscribe or plan screens.
    public var billingEnabled: Bool {
        if let s = state.signedIn { return s.account.billingEnabled }
        return isSelfHosted ? (serverInfo?.billingEnabled ?? false) : environment.hostedBillingEnabled
    }

    /// The two buttons Settings › Sync offers when signed out.
    public var signedOutActions: [String] {
        [billingEnabled && !isSelfHosted ? "Start Free 14-Day Trial…" : isSelfHosted ? "Create Account…" : "Create Free Account…", "Sign In…"]
    }
    /// A server other than Feather Cloud: trial and plan details don't apply.
    public var isSelfHosted: Bool { server != .hosted }

    public init(library: Library, defaults: UserDefaults, environment: CloudEnvironment, hooks: CloudHooks) {
        self.library = library
        self.defaults = defaults
        self.environment = environment
        self.hooks = hooks
        server = defaults.string(forKey: Self.serverKey).flatMap { try? CloudServer(userInput: $0) } ?? .hosted
    }

    // MARK: Server

    public static func message(_ e: ServerURLError) -> String {
        switch e {
        case .invalid: "Enter the server's address."
        case .insecure: "Use an https:// address. Plain http works only for this Mac (localhost)."
        }
    }

    /// Checks a server (GET /server) and uses it. Returns a message to show, or nil.
    public func connect(serverInput: String) async -> String? {
        let candidate: CloudServer
        do { candidate = try CloudServer(userInput: serverInput) } catch { return Self.message(error) }
        do {
            let info = try await APIClient(server: candidate, configuration: environment.configuration(), token: { nil }).getServer()
            server = candidate
            serverInfo = info
            defaults.set(serverInput.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.serverKey)
            account = nil
            return nil
        } catch {
            return "Couldn't reach that server. Check the address and try again."
        }
    }

    public func useHostedServer() {
        server = .hosted
        serverInfo = nil
        defaults.removeObject(forKey: Self.serverKey)
        account = nil
    }

    public func accountService() -> AccountService {
        if let account, account.server == server { return account }
        let a = AccountService(server: server, secrets: environment.secrets, keys: environment.keys, configuration: environment.configuration())
        account = a
        return a
    }

    // MARK: Sign-in state

    /// At launch: picks up a sign-in stored by an earlier launch and starts syncing. Without one, does nothing.
    public func restoreAtLaunch() async {
        guard let email = defaults.string(forKey: Self.accountKey), let libraryID = defaults.string(forKey: Self.libraryKey) else { return }
        let a = accountService()
        guard await a.restore(email: email) else { return }
        let placeholder = CloudAccount(email: email, libraryID: libraryID,
                                       plan: CloudPlan(state: "active", reason: nil, trialEndsAt: nil, quotaBytes: 0, usedBytes: 0),
                                       billingEnabled: billingEnabled)
        state = .signedIn(SignedIn(email: email, server: server, deviceID: "", libraryID: libraryID, account: placeholder))
        startSync(libraryID: libraryID)
        Task { await refreshAccount() }
    }

    /// After signup, sign-in or recovery: remember the account and start syncing. `merge` marks every local item
    /// as new to the server (signing in with notes already on this Mac).
    public func didSignIn(_ s: SignedIn, merge: Bool) async {
        try? await library.resetSync(markAllDirty: merge)
        defaults.set(s.email, forKey: Self.accountKey)
        defaults.set(s.libraryID, forKey: Self.libraryKey)
        state = .signedIn(s)
        reauthEmail = nil
        plan = s.account.plan
        startSync(libraryID: s.libraryID)
    }

    /// Signs out: ends the session if the server answers, forgets the secrets either way, keeps every note.
    public func signOut() async {
        await engine?.stop()
        engine = nil
        statusTask?.cancel()
        await account?.signOut()
        await forgetLocally()
        reauthEmail = nil
    }

    private func forgetLocally() async {
        await engine?.stop()
        engine = nil
        statusTask?.cancel()
        statusTask = nil
        try? await library.resetSync(markAllDirty: false)
        defaults.removeObject(forKey: Self.accountKey)
        defaults.removeObject(forKey: Self.libraryKey)
        state = .signedOut
        status = .idle(lastSynced: nil)
        plan = nil
        devices = []
        conflicts = []
    }

    public func refreshAccount() async {
        guard let a = account else { return }
        if let acct = try? await a.account() {
            plan = acct.plan
            if case .signedIn(var s) = state { s.account = acct; state = .signedIn(s) }
        }
        devices = (try? await a.devices()) ?? devices
        conflicts = (try? await library.syncConflicts()) ?? conflicts
    }

    public func revoke(_ id: String) async {
        try? await account?.revoke(id)
        devices = (try? await account?.devices()) ?? devices
    }

    // MARK: Sync

    private func startSync(libraryID: String) {
        let e = SyncEngine(library: library, account: accountService(), libraryID: libraryID, deviceName: environment.deviceName)
        engine = e
        let hooks = self.hooks
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            for await s in await e.statusUpdates() { self?.status = s }
        }
        Task {
            await e.start(beforeSync: { await hooks.beforeSync() },
                          onPulled: { ids in await hooks.onPulled(ids) },
                          onSignedOut: { [weak self] in await self?.serverSignedOut() })
        }
    }

    public func syncNow() { Task { await engine?.syncNow() } }
    public func localChanged() { Task { await engine?.localChanged() } }
}
