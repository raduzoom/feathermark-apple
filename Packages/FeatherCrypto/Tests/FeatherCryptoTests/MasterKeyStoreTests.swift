import Foundation
import Testing
@testable import FeatherCrypto

/// A Keychain store with a service name of its own per run, so the real item is never touched.
func testKeychainStore() -> KeychainMasterKeyStore {
    KeychainMasterKeyStore(service: "app.feathermark.FeatherCryptoTests.\(UUID().uuidString)")
}

/// Whether this test host may use the Keychain. Package tests on the iOS simulator run without Keychain
/// entitlements, so `SecItemAdd` fails there with `errSecMissingEntitlement` (-34018).
enum KeychainProbe {
    /// Saves and deletes a throwaway master key through the real store; returns the Keychain's status.
    static func addAndDelete(service: String) -> OSStatus {
        let store = KeychainMasterKeyStore(service: service)
        do {
            try store.save(Data(repeating: 7, count: 32), account: "probe")
            try store.delete(account: "probe")
            return errSecSuccess
        } catch let KeychainError.status(status) {
            return status
        } catch {
            return errSecParam
        }
    }

    static let status = addAndDelete(service: "app.feathermark.FeatherCryptoTests.probe.\(UUID().uuidString)")
    static var available: Bool { status == errSecSuccess }
}

@Test func keychainTestsSkipOnlyForMissingEntitlement() throws {
    let status = KeychainProbe.addAndDelete(service: "app.feathermark.FeatherCryptoTests.\(UUID().uuidString)")
    #if os(iOS)
    #expect(status == errSecSuccess || status == errSecMissingEntitlement)
    #else
    #expect(status == errSecSuccess)
    #endif
}

/// The Keychain round trips; on iOS without a Keychain entitlement they show as skipped, never as passed.
@Suite(.enabled(if: KeychainProbe.available, "the Keychain needs an entitlement this test host lacks (errSecMissingEntitlement)"))
struct KeychainMasterKeyStoreTests {
    @Test func saveLoadDelete() throws { try MasterKeyStoreTests.checkSaveLoadDelete(testKeychainStore()) }
    @Test func saveTwiceReplaces() throws { try MasterKeyStoreTests.checkSaveTwiceReplaces(testKeychainStore()) }
}

@Suite struct MasterKeyStoreTests {
    @Test func saveLoadDelete() throws { try Self.checkSaveLoadDelete(InMemoryMasterKeyStore()) }
    @Test func saveTwiceReplaces() throws { try Self.checkSaveTwiceReplaces(InMemoryMasterKeyStore()) }

    static func checkSaveLoadDelete(_ store: any MasterKeyStore) throws {
        let key = MasterKey.generate()
        try store.save(key, account: "acct-1")
        defer { try? store.delete(account: "acct-1") }
        #expect(try store.load(account: "acct-1") == key)
        #expect(try store.load(account: "acct-2") == nil)
        try store.delete(account: "acct-1")
        #expect(try store.load(account: "acct-1") == nil)
        try store.delete(account: "acct-1")   // deleting nothing is fine (sign-out twice)
    }

    static func checkSaveTwiceReplaces(_ store: any MasterKeyStore) throws {   // Review Focus 5
        defer { try? store.delete(account: "a") }
        try store.save(Data(repeating: 1, count: 32), account: "a")
        try store.save(Data(repeating: 2, count: 32), account: "a")
        #expect(try store.load(account: "a") == Data(repeating: 2, count: 32))
    }

    @Test func onlyMasterKeysAreSaved() {
        #expect(throws: InvalidArgument.length(name: "masterKey", expected: 32, actual: 3)) {
            try InMemoryMasterKeyStore().save(Data([1, 2, 3]), account: "a")
        }
    }
}

// Identifiers carry the app's name, FeatherMark (2026-11-10), before any release.
@Test func keychainServiceUsesTheAppIdentifier() {
    #expect(KeychainMasterKeyStore().service == "app.feathermark.FeatherMark.master-key")
}
