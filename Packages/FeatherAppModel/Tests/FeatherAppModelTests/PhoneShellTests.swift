import FeatherCore
import FeatherEditorCore
import Foundation
import Testing
@testable import FeatherAppModel

/// Phase 12: what the iPhone and iPad shell needs from the shared model.
@MainActor @Suite struct PhoneShellTests {
    private func requireSendable<T: Sendable>(_: T.Type) {}

    @Test func valueTypesAreSendable() {
        requireSendable(EditorState.self)
        requireSendable(CloudState.self)
        requireSendable(EmptyState.self)
        requireSendable(ImportState.self)
        requireSendable(PasswordStrength.self)
        requireSendable(SyncStatusText.self)
        requireSendable(CloudBanner.self)
        requireSendable(Formatting.Confirmation.self)
        requireSendable(SignInFlow.Mode.self)
        requireSendable(BlockMenuState.self)
        requireSendable(EditorCommands.Edit.self)
        requireSendable(EditorCommands.Line.self)
        requireSendable(UndoTrash.self)
    }

    /// Creates a note with a title and body, in a notebook, and refreshes the model.
    @discardableResult
    private func note(_ m: AppModel, _ title: String, body: String = "", in notebook: ULID? = nil) async throws -> ULID {
        let n = try await m.library.createNote(title: title, body: body, notebookID: notebook)
        await m.refresh()
        return n.id
    }

    @Test func trashWithUndoOffersUndo() async throws {
        let m = try await makeModel()
        let a = try await note(m, "A")
        await m.trashWithUndo(a)
        #expect(m.undoTrash == UndoTrash(noteID: a, title: "A"))
        #expect(m.notes.isEmpty)
        await m.select(.trash)
        #expect(m.notes.map(\.id) == [a])
        await m.select(.all)
        await m.undoLastTrash()
        #expect(m.notes.map(\.id) == [a])
        #expect(m.undoTrash == nil)
    }

    @Test func undoRestoresOnlyTheLastTrashedNote() async throws {
        let m = try await makeModel()
        let a = try await note(m, "A")
        let b = try await note(m, "B")
        await m.trashWithUndo(a)
        await m.trashWithUndo(b)
        #expect(m.undoTrash?.noteID == b)
        await m.undoLastTrash()
        #expect(m.notes.map(\.id) == [b])
        await m.select(.trash)
        #expect(m.notes.map(\.id) == [a])
    }

    @Test func undoExpiresAfterWindow() async throws {
        let m = try await makeModel()
        let a = try await note(m, "A")
        let b = try await note(m, "B")
        m.undoWindow = .milliseconds(50)
        await m.trashWithUndo(a)
        try await Task.sleep(for: .milliseconds(200))
        #expect(m.undoTrash == nil)

        // A's timer must not clear B's offer.
        await m.restore(a)
        m.undoWindow = .milliseconds(200)
        await m.trashWithUndo(a)
        await m.trashWithUndo(b)
        try await Task.sleep(for: .milliseconds(120))
        #expect(m.undoTrash?.noteID == b)
    }

    @Test func dismissUndoClearsTheOffer() async throws {
        let m = try await makeModel()
        let a = try await note(m, "A")
        await m.trashWithUndo(a)
        m.dismissUndo()
        #expect(m.undoTrash == nil)
        await m.undoLastTrash()   // nothing to undo: the note stays in the Trash
        #expect(m.notes.isEmpty)
    }

    @Test func searchAllFromANotebookSearchesEverything() async throws {
        let m = try await makeModel()
        let travel = try #require(await m.createNotebook(name: "Travel", parent: nil))
        let personal = try #require(await m.createNotebook(name: "Personal", parent: nil))
        let groceries = try await note(m, "Groceries", body: "oat milk", in: personal.id)
        await m.select(.notebook(travel.id))
        await m.searchAll("milk")
        #expect(m.selection == .all)
        #expect(m.searchNotebookID == nil)
        #expect(m.searchHits?.map(\.note.id) == [groceries])
    }

    @Test func filterChipsListViewsAndTopLevelNotebooks() async throws {
        let m = try await makeModel()
        let personal = try #require(await m.createNotebook(name: "Personal", parent: nil))
        let projects = try #require(await m.createNotebook(name: "Projects", parent: nil))
        _ = await m.createNotebook(name: "Home", parent: projects.id)
        #expect(m.filterChips == [.all, .pinned, .notebook(personal.id), .notebook(projects.id)])
        await m.select(.trash)
        #expect(m.filterChips.isEmpty)
        await m.select(.recent)
        #expect(m.filterChips.isEmpty)
    }

    @Test func thumbnailFindsTheFirstImageAttachment() {
        let id = ULID.generate(at: 1_700_000_000_000)
        #expect(NoteThumbnail.imageID(inPreview: "Intro ![shield](feather://attachment/\(id)) more") == id)
        #expect(NoteThumbnail.imageID(inPreview: "See [file](feather://attachment/\(id))") == nil)
        #expect(NoteThumbnail.imageID(inPreview: "No images here") == nil)
        #expect(NoteThumbnail.letter("  groceries") == "G")
        #expect(NoteThumbnail.letter("") == "·")
        let other = ULID.generate(at: 1_700_000_000_001)
        #expect(NoteThumbnail.tint(id) == NoteThumbnail.tint(id))
        #expect((0...3).contains(NoteThumbnail.tint(id)) && (0...3).contains(NoteThumbnail.tint(other)))
    }

    @Test func exportSummaryNamesTheFolder() async throws {
        let m = try await makeModel()
        try await note(m, "One")
        let out = FileManager.default.temporaryDirectory.appending(path: "FNExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let one = try #require(await m.export(to: out, notebook: nil))
        #expect(Formatting.exportSummary(one) == "Exported 1 note to “\(one.root.lastPathComponent)”.")
        try await note(m, "Two")
        let two = try #require(await m.export(to: out, notebook: nil))
        #expect(Formatting.exportSummary(two) == "Exported 2 notes to “\(two.root.lastPathComponent)”.")
    }

    @Test func memoryEnvironmentHasADeviceName() {
        #expect(!CloudEnvironment.memory.deviceName.isEmpty)
        #expect(CloudEnvironment.live(isolated: true, deviceName: "iPad").deviceName == "iPad")
    }
}
