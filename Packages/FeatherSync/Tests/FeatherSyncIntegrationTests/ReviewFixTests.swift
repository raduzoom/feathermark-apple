// Two-device tests drive the local server and read its log with Process: macOS only.
#if os(macOS)
import FeatherCore
import FeatherCrypto
import Foundation
import Testing
@testable import FeatherSync

/// Regression tests for the Part A review (Phase 8).
@Suite struct ReviewFixTests {
    func pair() async throws -> (TestDevice, TestDevice, ULID) {
        let a = try TestDevice("Mac A"), b = try TestDevice("Mac B")
        let email = Harness.email()
        try await a.signUp(email)
        let note = try await a.library.createNote(title: "Groceries", body: "milk")
        try await a.sync()
        try await b.signIn(email)
        try await b.sync()
        return (a, b, note.id)
    }

    // C1: B's unpushed body edit against A's metadata change makes a conflict copy, never a silent loss
    @Test func bodyEditAgainstMetadataChangeKeepsText() async throws {
        let (a, b, id) = try await pair()
        try await a.library.setPinned(id, true)
        try await b.library.updateNote(id, body: "milk, bread")
        try await a.sync()
        try await b.sync()
        try await a.sync()
        for device in [a, b] {
            let bodies = Set(try await device.notes().map(\.body))
            #expect(bodies == ["milk", "milk, bread"], "\(device.name): \(bodies)")
        }
        #expect(try await b.library.dirtyItems().isEmpty)
    }

    // C1: a permanent delete that loses to a metadata edit brings the note back with its real body
    @Test func revivedNoteHasItsBody() async throws {
        let (a, b, id) = try await pair()
        try await a.library.setPinned(id, true)
        try await b.library.deleteNotePermanently(id)
        try await a.sync()
        try await b.sync()
        #expect(try await b.library.note(id)?.body == "milk")
    }

    // C2 (and Focus 5): an edit made after a push, before the pull, is pushed next time, with no conflict copy
    @Test func editBetweenPushAndPullIsPushedLater() async throws {
        let (a, b, id) = try await pair()
        try await a.library.updateNote(id, body: "v1")
        await a.engine.setTestHook { event, _ in
            if event == "afterPush" { try? await a.library.updateNote(id, body: "v2") }
        }
        try await a.sync()
        await a.engine.setTestHook(nil)
        try await a.sync()
        try await b.sync()
        #expect(try await b.library.note(id)?.body == "v2")
        let onA = try await a.notes(), onB = try await b.notes()
        #expect(onA.count == 1 && onB.count == 1)
    }

    // C3: typing while a pull applies the other device's change is kept as a conflict copy
    @Test func typingDuringPullIsKept() async throws {
        let (a, b, id) = try await pair()
        try await b.library.updateNote(id, body: "from B")
        try await b.sync()
        await a.engine.setTestHook { event, item in
            if event == "beforeApply", item == id { try? await a.library.updateNote(id, body: "A typed during pull") }
        }
        try await a.sync()
        await a.engine.setTestHook(nil)
        try await a.sync()
        try await b.sync()
        for device in [a, b] {
            let bodies = Set(try await device.notes().map(\.body))
            #expect(bodies == ["from B", "A typed during pull"], "\(device.name): \(bodies)")
        }
    }

    // I1: notes keep their notebook and tags on a new device even when those were renamed after the note
    @Test func referencesSurviveSeqOrder() async throws {
        let a = try TestDevice("Mac A"), b = try TestDevice("Mac B")
        let email = Harness.email()
        try await a.signUp(email)
        let nb = try await a.library.createNotebook(name: "Work", parentID: nil)
        let tag = try await a.library.createTag(name: "todo")
        let note = try await a.library.createNote(title: "Plan", body: "x", notebookID: nb.id, tagIDs: [tag.id])
        try await a.sync()
        try await a.library.renameNotebook(nb.id, to: "Office")
        try await a.library.renameTag(tag.id, to: "next")
        try await a.sync()
        try await b.signIn(email)
        try await b.sync()
        let onB = try #require(try await b.library.note(note.id))
        #expect(onB.notebookID == nb.id && onB.tagIDs == [tag.id])
        #expect(try await b.library.dirtyItems().isEmpty)
    }

    // I2: a blob the server no longer has is uploaded again instead of being rejected forever
    @Test func blobMissingIsReuploaded() async throws {
        let (a, b, id) = try await pair()
        _ = try Harness.sql("DELETE FROM blobs WHERE account_id = (SELECT id FROM accounts WHERE email_norm = '\(a.signedIn.email)')")
        try await a.library.setPinned(id, true)
        let first = try await a.sync()
        #expect(first.rejected[id.description] == "blob_missing")
        let second = try await a.sync()
        #expect(second.rejected.isEmpty)
        #expect(try await a.library.dirtyItems().isEmpty)
        try await b.sync()
        let onB = try await b.library.note(id)
        #expect(onB?.pinned == true && onB?.body == "milk")
    }

    // I3: two passes started together don't push the same changes twice
    @Test func concurrentPassesAreSerial() async throws {
        let (a, b, _) = try await pair()
        for i in 1...5 { _ = try await a.library.createNote(title: "N\(i)", body: "\(i)") }
        async let r1 = a.sync()
        async let r2 = a.sync()
        let (x, y) = try await (r1, r2)
        #expect(x.pushed + y.pushed == 5 && x.conflictCopies.isEmpty && y.conflictCopies.isEmpty)
        try await b.sync()
        #expect(try await b.notes().count == 6)
    }

    // I3: after a 401 ends the schedule, starting it again works
    @Test func scheduleRestartsAfterSignOut() async throws {
        let (a, _, _) = try await pair()
        let signedOut = Flag(), synced = Flag()
        let engine = a.engine!
        await a.account.forget()
        await engine.start(beforeSync: {}, onPulled: { _ in }, onSignedOut: { signedOut.set() })
        try await signedOut.wait()
        _ = try await a.account.signIn(email: a.signedIn.email, password: "correct horse battery", deviceName: "Mac A")   // same engine
        let updates = await engine.statusUpdates()
        let watcher = Task { for await s in updates { if case .idle(let d) = s, d != nil { synced.set(); return } } }
        await engine.start(beforeSync: {}, onPulled: { _ in }, onSignedOut: {})
        try await synced.wait()
        watcher.cancel()
        await engine.stop()
    }

    // Phase 20 finding: a note deferred for its notebook, re-applied after the pull, never rolls back a newer
    // version of itself that a later page brought
    @Test func deferredReapplyNeverRollsBack() async throws {
        let a = try TestDevice("Mac A"), b = try TestDevice("Mac B")
        let email = Harness.email()
        try await a.signUp(email)
        let nb = try await a.library.createNotebook(name: "Work", parentID: nil)
        let note = try await a.library.createNote(title: "v1", body: "x", notebookID: nb.id)
        try await a.sync()   // notebook, then note
        try await a.library.renameNotebook(nb.id, to: "Office")
        try await a.sync()   // the notebook moves after the note: B sees the note (v1) before its notebook
        try await b.signIn(email)
        await b.engine.setPullLimit(1)
        let pulls = Counter()
        await b.engine.setTestHook { event, _ in
            // between page 1 (the note at v1, deferred) and page 2, the note moves on to v2
            guard event == "beforePull", pulls.next() == 2 else { return }
            _ = try? await a.library.updateNote(note.id, title: "v2")
            _ = try? await a.sync()
        }
        try await b.sync()
        await b.engine.setTestHook(nil)
        let onB = try #require(try await b.library.note(note.id))
        #expect(onB.title == "v2" && onB.notebookID == nb.id)
        #expect(try await b.library.syncItem(note.id)?.serverVersion == 2)
        // later edits here still reach the server
        _ = try await b.library.updateNote(note.id, title: "v3 from B")
        let report = try await b.sync()
        #expect(report.rejected.isEmpty && report.conflictCopies.isEmpty)
        #expect(try await b.library.dirtyItems().isEmpty)
        try await a.sync()
        #expect(try await a.library.note(note.id)?.title == "v3 from B")
    }

    // Phase 20 finding: an item the pull couldn't store (typing at every try) keeps the cursor before it, so the
    // next pass gets it again, instead of the note never syncing again
    @Test func skippedItemKeepsCursor() async throws {
        let (a, b, id) = try await pair()
        let before = try await a.library.syncValue("pull_cursor")
        _ = try await b.library.updateNote(id, body: "from B")
        try await b.sync()
        let typist = Typist()
        await a.engine.setTestHook { event, item in await typist.type(event, item, id, a.library) }
        let first = try await a.sync()
        #expect(first.skipped > 0)
        #expect(try await a.library.syncValue("pull_cursor") == before)
        // the typing stops: the next pass lands it, with what was typed kept as a conflict copy
        typist.stop()
        let second = try await a.sync()
        #expect(second.skipped == 0 && second.conflictCopies.count == 1)
        await a.engine.setTestHook(nil)
        try await b.sync()
        for device in [a, b] {
            #expect(try await device.library.dirtyItems().isEmpty, "\(device.name)")
            #expect(try await device.library.note(id)?.body == "from B", "\(device.name)")
            let bodies = Set(try await device.notes().map(\.body))
            #expect(bodies == ["from B", "typed \(typist.keys)"], "\(device.name): \(bodies)")
        }
    }

    // Phase 20 finding: a scheduled pass that skipped an item never says "Synced" and comes again soon, not in
    // 5 minutes
    @Test func skippedPassIsRetriedSoon() async throws {
        let (a, b, id) = try await pair()
        _ = try await b.library.updateNote(id, body: "from B")
        try await b.sync()
        let typist = Typist(), passes = Counter(), synced = Flag(), sawSynced = Flag()
        let engine = a.engine!
        await engine.setTestHook { event, item in await typist.type(event, item, id, a.library) }
        let updates = await engine.statusUpdates()
        let watcher = Task {
            for await s in updates { if case .idle(let d) = s, d != nil { sawSynced.set(); synced.set() } }
        }
        let secondPass = Flag()
        await engine.start(beforeSync: {
            guard passes.next() == 2 else { return }
            #expect(!sawSynced.isSet, "a pass that skipped an item said Synced")
            typist.stop()
            secondPass.set()
        }, onPulled: { _ in }, onSignedOut: {})
        try await secondPass.wait(seconds: 15)
        try await synced.wait()
        watcher.cancel()
        await engine.stop()
        await engine.setTestHook(nil)
        #expect(try await a.library.dirtyItems().isEmpty)
        #expect(try await a.library.note(id)?.body == "from B")
    }
}

/// Types into one note at every remote write the engine is about to make, until stopped.
final class Typist: @unchecked Sendable {
    private let lock = NSLock()
    private var on = true
    private var count = 0
    var keys: Int { lock.withLock { count } }
    func stop() { lock.withLock { on = false } }
    func type(_ event: String, _ item: ULID?, _ id: ULID, _ library: Library) async {
        guard event == "beforeApply" || event == "beforeResolve", item == id else { return }
        let key: Int? = lock.withLock {
            guard on else { return nil }
            count += 1
            return count
        }
        guard let key else { return }
        _ = try? await library.updateNote(id, body: "typed \(key)")
    }
}

/// A thread-safe count.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}

/// A one-shot signal tests can wait on (with a timeout).
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isSet: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
    func wait(seconds: Double = 20) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !isSet {
            guard Date() < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
#endif
