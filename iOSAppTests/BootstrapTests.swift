import FeatherAppModel
import FeatherCore
import Foundation
import Testing
@testable import FeatherMarkiOS

/// Records every request any URL session tries to make, and lets none through.
final class RecordingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var urls: [URL] = []
    static let lock = NSLock()
    static var count: Int { lock.withLock { urls.count } }
    override class func canInit(with request: URLRequest) -> Bool {
        lock.withLock { urls.append(request.url!) }
        return false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
}

@MainActor @Suite struct BootstrapTests {
    @Test func appMakesNoRequestAtLaunch() async throws {   // Review Focus 4
        URLProtocol.registerClass(RecordingProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingProtocol.self) }
        let before = RecordingProtocol.count
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary", "-FeatherSeedDemo"])
        // The cloud builds its own sessions from this configuration: record those too.
        model.cloud.environment.configuration = {
            let c = URLSessionConfiguration.ephemeral
            c.protocolClasses = [RecordingProtocol.self] + (c.protocolClasses ?? [])
            return c
        }
        await AppBootstrap.launch(model)   // everything the app does at launch (AppLoader calls this)
        #expect(model.counts.all == 6)
        for item in [SidebarItem.recent, .pinned, .trash, .all] { await model.select(item) }
        for notebook in model.notebooks { await model.select(.notebook(notebook.id)) }
        for tag in model.tags { await model.select(.tag(tag.id)) }
        await model.searchAll("milk")
        try await Task.sleep(for: .milliseconds(300))
        #expect(RecordingProtocol.count == before)
        #expect(!model.cloud.hasAccountService)   // no API client, so no session at all
        #expect(model.cloud.state == .signedOut)
    }

    @Test func isolatedRunUsesIsolatedDefaults() async throws {
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary"])
        #expect(model.defaults != UserDefaults.standard)
        #expect(model.cloud.environment.deviceName == DeviceWord.current)
    }

    /// A fresh temporary library starts with fresh settings: a UI test that leaves Markdown mode on must not change
    /// the next run.
    @Test func temporaryLibraryStartsWithFreshSettings() async throws {
        let suite = try #require(UserDefaults(suiteName: AppBootstrap.isolatedDefaultsSuite))
        suite.set("raw", forKey: AppModel.editorModeKey)
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary"])
        #expect(model.editorMode == .live)
        #expect(suite.string(forKey: AppModel.editorModeKey) == nil)
    }

    @Test func seedNeedsAnIsolatedRun() async throws {
        // -FeatherSeedDemo on the real library would write demo notes into someone's notes: it must be ignored.
        #expect(!AppBootstrap.shouldSeed(arguments: ["app", "-FeatherSeedDemo"], environment: [:]))
        #expect(AppBootstrap.shouldSeed(arguments: ["app", "-FeatherTemporaryLibrary", "-FeatherSeedDemo"], environment: [:]))
    }
}
