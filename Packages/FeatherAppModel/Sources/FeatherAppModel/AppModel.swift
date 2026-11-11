import FeatherCore
import FeatherEditorCore
import FeatherSync
import Foundation
import UniformTypeIdentifiers
import Observation

/// The open note as the editor sees it.
public struct EditorState: Equatable, Sendable {
    public var id: ULID
    public var title: String
    public var body: String
    public var isTrashed: Bool
    public var notebookID: ULID?
    public var tagIDs: Set<ULID>
    public var pinned: Bool
    public var modified: Int64
    public var trashedAt: Int64?

    public init(_ note: Note) {
        id = note.id
        title = note.title
        body = note.body
        isTrashed = note.trashedAt != nil
        notebookID = note.notebookID
        tagIDs = note.tagIDs
        pinned = note.pinned
        modified = note.modified
        trashedAt = note.trashedAt
    }
}

/// The note a swipe just moved to the Trash, while its Undo is offered.
public struct UndoTrash: Equatable, Sendable {
    public var noteID: ULID
    public var title: String
    public init(noteID: ULID, title: String) {
        self.noteID = noteID
        self.title = title
    }
}

/// Owns the library and every piece of UI state. Views read it and call its methods; they hold no behaviour.
@MainActor @Observable
public final class AppModel {
    public static let retentionKey = "trashRetentionDays"
    public static let retentionChoices = [7, 14, 30, 60, 90]

    public let library: Library
    public let defaults: UserDefaults
    /// Opening URLs and the global shortcut (the Mac's, the iPhone's, or none in tests).
    public let platform: AppPlatform
    /// Feather Cloud account and sync (Phase 8).
    public private(set) var cloud: CloudModel!

    // Sidebar
    public private(set) var selection: SidebarItem = .all
    public private(set) var notebooks: [Notebook] = []
    public private(set) var tags: [Tag] = []
    public private(set) var counts = LibraryCounts(all: 0, pinned: 0, trash: 0, notebooks: [:])
    /// Tag ids of every tagged note (for the Tags menu of any row, open or not).
    public private(set) var tagsByNote: [ULID: Set<ULID>] = [:]

    // Note list and search
    public private(set) var notes: [NoteSummary] = []
    public private(set) var searchText = ""
    /// nil when not searching.
    public private(set) var searchHits: [SearchHit]?
    public private(set) var searchTagIDs: Set<ULID> = []
    public private(set) var searchNotebookID: ULID?

    // Editor
    public private(set) var selectedNoteID: ULID?
    public private(set) var editor: EditorState?

    public var lastError: String?
    /// Set by New Note: the title should take keyboard focus once it appears.
    public private(set) var titleWantsFocus = false
    public func titleTookFocus() { titleWantsFocus = false }
    /// Bumped by Find (⌘F) so the list's search field takes focus.
    public private(set) var searchFocusRequest = 0
    public func requestSearchFocus() { searchFocusRequest += 1 }

    /// Live preview or raw Markdown (⇧⌘M), remembered across launches.
    public var editorMode: EditorMode {
        didSet { defaults.set(editorMode.rawValue, forKey: Self.editorModeKey) }
    }
    public static let editorModeKey = "editorMode"
    /// Attachment files by id, for the editor (images, chips, ⌘-click).
    public private(set) var attachmentFiles: [ULID: URL] = [:]

    public var trashRetentionDays: Int {
        didSet { defaults.set(trashRetentionDays, forKey: Self.retentionKey) }
    }

    /// Tests only: delays the search for a given query, to provoke out-of-order results.
    public var searchDelay: (@Sendable (String) -> Duration)?
    /// How long after the last keystroke an edit is saved.
    public var saveDelay: Duration = .milliseconds(500)

    /// The unsaved edit: which note, and its title and body at the last keystroke.
    /// `save()` writes this snapshot, never whatever note `editor` shows by then.
    private struct PendingEdit { var id: ULID; var title: String; var body: String }
    private var pending: PendingEdit?
    /// Bumped by every keystroke, so an await that started before it can tell its data is stale.
    private var editVersion = 0
    private var saveTask: Task<Void, Never>?
    private var runningSave: Task<Void, Never>?
    private var searchGeneration = 0
    private var purgedThisLaunch = false

    private init(library: Library, defaults: UserDefaults, cloud environment: CloudEnvironment, platform: AppPlatform) {
        self.library = library
        self.defaults = defaults
        self.platform = platform
        let stored = defaults.integer(forKey: Self.retentionKey)
        trashRetentionDays = stored > 0 ? stored : 30
        editorMode = EditorMode(rawValue: defaults.string(forKey: Self.editorModeKey) ?? "") ?? .live
        quickNoteNotebookID = defaults.string(forKey: Self.quickNoteNotebookKey(library.id)).flatMap(ULID.init(string:))
        quickNoteShortcut = defaults.string(forKey: Self.quickNoteShortcutKey).flatMap(Shortcut.init(stored:)) ?? .quickNoteDefault
        cloud = CloudModel(library: library, defaults: defaults, environment: environment,
                           hooks: CloudHooks(beforeSync: { [weak self] in await self?.flush() },
                                             onPulled: { [weak self] ids in await self?.applyPulled(ids) }))
    }

    // MARK: Quick note

    /// Per library, so opening another library (a test host, a UI test) never touches this one's setting.
    public static func quickNoteNotebookKey(_ library: ULID) -> String { "quickNoteNotebook-\(library)" }
    public static let quickNoteShortcutKey = "quickNoteShortcut"

    /// Where quick notes and captures go; nil is "No Notebook" (the root).
    public var quickNoteNotebookID: ULID? {
        didSet { defaults.set(quickNoteNotebookID?.description, forKey: Self.quickNoteNotebookKey(library.id)) }
    }

    public var quickNoteShortcut: Shortcut {
        didSet { defaults.set(quickNoteShortcut.stored, forKey: Self.quickNoteShortcutKey) }
    }

    /// Set when the shortcut couldn't be registered (another app holds it).
    public private(set) var quickNoteShortcutError: String?
    /// The platform's registration of the shortcut; releasing it unregisters the shortcut.
    private var quickNoteRegistration: AnyObject?
    private var quickNoteAction: (() -> Void)?

    /// Sets a new shortcut and registers it with the same action.
    public func changeQuickNoteShortcut(_ shortcut: Shortcut) {
        quickNoteShortcut = shortcut
        if let quickNoteAction { registerQuickNoteShortcut(action: quickNoteAction) }
    }

    public var noteCount: Int { counts.all }

    // MARK: Import state (Phase 5; behaviour in Import/ImportModel.swift)

    public var importState: ImportState?
    public var showImportSource = false
    public var importTask: Task<Void, Never>?
    public var importStarted: Date?
    /// Tests only: a pause after each imported note, so a test can cancel mid-import.
    public var importNoteDelay: TimeInterval = 0

    /// Captures waiting to become notes (Services, Share extension). See FeatherCore `Inbox`.
    public var inbox: Inbox { Inbox(directory: library.directory.appending(path: "Inbox", directoryHint: .isDirectory)) }

    /// Turns every pending capture into a note in the quick-note notebook; returns how many were created.
    @discardableResult
    public func drainInbox() async -> Int {
        var created = 0
        await attempt { created = try await library.drain(inbox, into: quickNoteNotebookID).count }
        if created > 0 { await refresh() }
        return created
    }

    /// Registers the quick-note shortcut system-wide, replacing any earlier registration. Does nothing on a
    /// platform without global shortcuts.
    public func registerQuickNoteShortcut(action: @escaping () -> Void) {
        quickNoteAction = action
        quickNoteRegistration = nil
        guard let register = platform.registerQuickNoteShortcut else { return }
        do {
            quickNoteRegistration = try register(quickNoteShortcut, action)
            quickNoteShortcutError = nil
        } catch {
            quickNoteShortcutError = "This shortcut is used by another app."
        }
        if platform.isSystemShortcut(quickNoteShortcut) {
            quickNoteRegistration = nil
            quickNoteShortcutError = "macOS uses this shortcut."
        }
    }

    /// Saves a quick note: first line as the title, the rest as the body. Whitespace-only text saves nothing.
    public func saveQuickNote(text: String, notebookID: ULID?) async -> Note? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let item = InboxItem(id: ULID.generate(at: now), kind: .text, text: text, created: now)
        var note: Note?
        await attempt { note = try await library.capture(item, files: [], into: notebookID) }
        await refresh()
        return note
    }

    public func toggleEditorMode() { editorMode = editorMode == .live ? .raw : .live }

    /// The file behind a `feather://attachment/<id>` URL, if the library has it.
    public func attachmentURL(for featherURL: String) -> URL? {
        let prefix = "feather://attachment/"
        guard featherURL.lowercased().hasPrefix(prefix), let id = ULID(string: String(featherURL.dropFirst(prefix.count))) else { return nil }
        return attachmentFiles[id]
    }

    /// Adds dropped or pasted files as attachments; returns the Markdown to insert for each.
    public func addAttachments(from urls: [URL]) async -> [String] {
        var snippets: [String] = []
        for url in urls {
            await attempt {
                let a = try await library.addAttachment(contentsOf: url)
                let name = a.filename.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
                snippets.append("\(isImage ? "!" : "")[\(name)](feather://attachment/\(a.id))")
            }
        }
        await reloadAttachmentFiles()
        return snippets
    }

    private func reloadAttachmentFiles() async {
        await attempt {
            var files: [ULID: URL] = [:]
            for a in try await library.attachments() {
                if let url = try await library.attachmentFileURL(a.id) { files[a.id] = url }
            }
            attachmentFiles = files
        }
    }

    /// Opens a link from the editor: attachments in their default app, everything else in the browser.
    public func openLink(_ url: String) {
        if let file = attachmentURL(for: url) { platform.open(file) }
        else if let u = URL(string: url), u.scheme != nil { platform.open(u) }
    }

    /// `cloud` defaults to in-memory secrets and `platform` to none: only the app itself passes the Keychain
    /// and its platform's abilities.
    public static func open(at directory: URL, clock: LibraryClock = .system, defaults: UserDefaults = .standard,
                     cloud: CloudEnvironment = .memory, platform: AppPlatform = .none) throws -> AppModel {
        AppModel(library: try Library.open(at: directory, clock: clock), defaults: defaults, cloud: cloud, platform: platform)
    }

    // MARK: Derived

    public var isSearching: Bool { searchHits != nil }

    /// The ids the note list shows, in order.
    public var visibleIDs: [ULID] { searchHits.map { $0.map(\.note.id) } ?? notes.map(\.id) }

    public var emptyState: EmptyState? {
        if let hits = searchHits, hits.isEmpty {
            return .noSearchResults(query: searchText, limitedTo: searchNotebookID.flatMap(notebookName))
        }
        if visibleIDs.isEmpty {
            if counts.all == 0 && counts.trash == 0 && selection != .trash { return .firstLaunch }
            return selection == .trash ? .emptyTrash : .emptyView
        }
        return selectedNoteID == nil ? .noNoteSelected : nil
    }

    /// The note list's filter chips (iPhone and iPad): All, Pinned and the top-level notebooks. None in the Trash,
    /// Recent or a tag, where switching views from the list would be surprising.
    public var filterChips: [SidebarItem] {
        switch selection {
        case .trash, .recent, .tag: return []
        case .all, .pinned, .notebook: return [.all, .pinned] + notebooks.filter { $0.parentID == nil }.map { .notebook($0.id) }
        }
    }

    public func notebookName(_ id: ULID) -> String? { notebooks.first { $0.id == id }?.name }
    public func tagName(_ id: ULID) -> String? { tags.first { $0.id == id }?.name }

    public func subNotebookCount(of id: ULID) -> Int {
        let children = Dictionary(grouping: notebooks, by: \.parentID)
        func count(_ id: ULID) -> Int { (children[id] ?? []).reduce(0) { $0 + 1 + count($1.id) } }
        return count(id)
    }

    public var selectionTitle: String {
        switch selection {
        case .all: "My Notes"
        case .recent: "Recent"
        case .pinned: "Pinned"
        case .trash: "Trash"
        case .notebook(let id): notebookName(id) ?? "Notebook"
        case .tag(let id): tagName(id).map { "#\($0)" } ?? "Tag"
        }
    }

    // MARK: Loading

    /// Reloads everything. The first call per launch also empties expired Trash.
    public func load() async {
        await reloadAttachmentFiles()
        if !purgedThisLaunch {
            purgedThisLaunch = true
            await purgeExpiredTrash()
        }
        await refresh()
    }

    /// Hourly Trash purge while the app runs.
    public func startMaintenance() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard let self else { return }
                await self.purgeExpiredTrash()
                await self.refresh()
            }
        }
    }

    private func purgeExpiredTrash() async {
        await attempt { _ = try await library.purgeExpiredTrash(retentionDays: trashRetentionDays) }
    }

    /// Reloads sidebar data, the list (or search) and the editor, then fixes the selection.
    public func refresh(fromSync: Bool = false) async {
        if !fromSync { cloud.localChanged() }   // a local change: sync 2 s after the last one
        let before = visibleIDs
        await attempt {
            notebooks = try await library.notebooks()
            tags = try await library.tags()
            counts = try await library.counts()
            tagsByNote = try await library.noteTagIDs()
            if let q = quickNoteNotebookID, !notebooks.contains(where: { $0.id == q }) { quickNoteNotebookID = nil }
            if case .notebook(let id) = selection, !notebooks.contains(where: { $0.id == id }) { selection = .all }
            if case .tag(let id) = selection, !tags.contains(where: { $0.id == id }) { selection = .all }
            notes = try await library.notes(in: selection.scope)
        }
        if isSearching { await runSearch() }
        await fixSelection(previous: before)
    }

    /// Keeps the selection if it's still visible; otherwise picks the note that took its place, or the one before.
    private func fixSelection(previous: [ULID]) async {
        let visible = visibleIDs
        guard let id = selectedNoteID else { return }
        if visible.contains(id) {
            await reloadEditor()
            return
        }
        var replacement: ULID?
        if let index = previous.firstIndex(of: id), !visible.isEmpty {
            replacement = visible[min(index, visible.count - 1)]
        }
        await openNote(replacement)
    }

    /// Re-reads the open note, unless the person typed since (then their text wins).
    private func reloadEditor() async {
        guard let id = selectedNoteID, pending == nil else { return }
        let version = editVersion
        var fresh: Note?
        await attempt { fresh = try await library.note(id) }
        guard version == editVersion, pending == nil, selectedNoteID == id else { return }
        editor = fresh.map(EditorState.init)
    }

    /// Opens another note (or none). Any unsaved edit is saved first, to the note it belongs to.
    private func openNote(_ id: ULID?) async {
        await flush()
        selectedNoteID = id
        editor = nil
        guard let id else { return }
        var note: Note?
        await attempt { note = try await library.note(id) }
        guard selectedNoteID == id, editor == nil else { return }   // another open won meanwhile
        editor = note.map(EditorState.init)
    }

    /// After a pull. If it changed the note you're typing in (typed after the pre-sync save, so not yet saved),
    /// your text goes to a conflict copy, which stays open in front of you: neither version is overwritten.
    public func applyPulled(_ ids: Set<ULID>) async {
        if let p = pending, ids.contains(p.id), var mine = try? await library.note(p.id) {
            saveTask?.cancel()
            saveTask = nil
            pending = nil
            mine.title = p.title
            mine.body = p.body
            let title = ConflictRules.conflictTitle(p.title, device: cloud.environment.deviceName, at: Date())
            if let copy = try? await library.createConflictCopy(of: mine, title: title) {
                await refresh(fromSync: true)
                await selectNote(copy.id)
                cloud.localChanged()
                return
            }
        }
        await refresh(fromSync: true)
    }

    /// Settings › Sync conflicts › Show Note: shows the notebook or tag whose rename lost.
    public func showConflict(_ c: SyncConflict) async {
        switch c.type {
        case .notebook: await select(.notebook(c.itemID))
        case .tag: await select(.tag(c.itemID))
        case .note: await select(.all); await selectNote(c.itemID)
        case .attachment: break
        }
    }

    // MARK: Sidebar

    public func select(_ item: SidebarItem) async {
        await flush()
        selection = item
        clearSearchState()
        await refresh()
    }

    // MARK: Notes

    public func selectNote(_ id: ULID?) async {
        await flush()
        await openNote(id)
    }

    public func newNote() async {
        await flush()
        var notebookID: ULID?
        var tagIDs: Set<ULID> = []
        switch selection {
        case .notebook(let id): notebookID = id
        case .tag(let id): tagIDs = [id]
        case .trash, .pinned: selection = .all
        case .all, .recent: break
        }
        clearSearchState()
        var created: Note?
        await attempt { created = try await library.createNote(notebookID: notebookID, tagIDs: tagIDs) }
        await refresh()
        if let created {
            await openNote(created.id)
            titleWantsFocus = true
        }
    }

    public func editTitle(_ title: String) {
        guard var e = editor, !e.isTrashed, !e.title.utf8.elementsEqual(title.utf8) else { return }
        e.title = title
        editor = e
        markDirty(e)
    }

    public func editBody(_ body: String) {
        guard var e = editor, !e.isTrashed, !e.body.utf8.elementsEqual(body.utf8) else { return }
        e.body = body
        editor = e
        markDirty(e)
    }

    private func markDirty(_ e: EditorState) {
        pending = PendingEdit(id: e.id, title: e.title, body: e.body)
        editVersion += 1
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Saves a pending edit now, after any save already running. Called before anything that changes
    /// what the editor shows, and before quit.
    public func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await save()
    }

    private func save() async {
        if let running = runningSave { await running.value }   // ⌘Q must not return mid-write
        guard let p = pending else { return }
        pending = nil
        let write = Task { [library] in
            _ = try? await library.updateNote(p.id, title: p.title, body: p.body)
        }
        runningSave = write
        await write.value
        if runningSave == write { runningSave = nil }
        cloud.localChanged()
        await attempt {
            counts = try await library.counts()
            notes = try await library.notes(in: selection.scope)
        }
        if let saved = try? await library.note(p.id), var current = editor, current.id == p.id {
            current.modified = saved.modified
            editor = current
        }
    }

    public func togglePin(_ id: ULID) async {
        await change(id) { note in try await self.library.setPinned(id, !note.pinned) }
    }

    public func move(_ id: ULID, to notebookID: ULID?) async {
        await change(id) { _ in try await self.library.moveNote(id, to: notebookID) }
    }

    public func setTags(_ id: ULID, _ tagIDs: Set<ULID>) async {
        await change(id) { _ in try await self.library.setTags(id, tagIDs) }
    }

    /// Adds or removes one tag on any note.
    public func toggleTag(_ tagID: ULID, on noteID: ULID) async {
        await change(noteID) { note in
            let tags = note.tagIDs.contains(tagID) ? note.tagIDs.subtracting([tagID]) : note.tagIDs.union([tagID])
            try await self.library.setTags(noteID, tags)
        }
    }

    public func trash(_ id: ULID) async {
        await change(id) { _ in try await self.library.trashNote(id) }
    }

    // MARK: Trash with Undo (iPhone and iPad: a full swipe trashes with no confirmation)

    /// Offered after `trashWithUndo` until `undoWindow` passes, the offer is dismissed, or another note replaces it.
    public private(set) var undoTrash: UndoTrash?
    /// How long the Undo stays offered.
    public var undoWindow: Duration = .seconds(5)
    private var undoExpiry: Task<Void, Never>?

    /// Moves a note to the Trash and offers to undo it; a newer offer replaces an older one.
    public func trashWithUndo(_ id: ULID) async {
        let title = notes.first { $0.id == id }?.title ?? editor.flatMap { $0.id == id ? $0.title : nil } ?? ""
        await trash(id)
        let offer = UndoTrash(noteID: id, title: title)
        undoTrash = offer
        undoExpiry?.cancel()
        let window = undoWindow
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled, let self, self.undoTrash == offer else { return }
            self.undoTrash = nil
        }
    }

    /// Restores the note of the current offer, if any.
    public func undoLastTrash() async {
        guard let offer = undoTrash else { return }
        dismissUndo()
        await restore(offer.noteID)
    }

    public func dismissUndo() {
        undoExpiry?.cancel()
        undoExpiry = nil
        undoTrash = nil
    }

    public func restore(_ id: ULID) async {
        await change(id) { _ in try await self.library.restoreNote(id) }
    }

    public func deletePermanently(_ id: ULID) async {
        await change(id) { _ in try await self.library.deleteNotePermanently(id) }
    }

    public func emptyTrash() async {
        await flush()
        await attempt { _ = try await library.emptyTrash() }
        await refresh()
    }

    /// Saves pending edits, applies a library change to one note, then refreshes everything.
    private func change(_ id: ULID, _ body: (Note) async throws -> Void) async {
        await flush()
        await attempt {
            guard let note = try await library.note(id) else { return }
            try await body(note)
        }
        await refresh()
    }

    // MARK: Notebooks and tags

    public func createNotebook(name: String, parent: ULID?) async -> Notebook? {
        var created: Notebook?
        await attempt { created = try await library.createNotebook(name: name, parentID: parent) }
        await refresh()
        return created
    }

    public func renameNotebook(_ id: ULID, to name: String) async {
        await attempt { try await library.renameNotebook(id, to: name) }
        await refresh()
    }

    public func moveNotebook(_ id: ULID, to parent: ULID?) async {
        await attempt { try await library.moveNotebook(id, toParent: parent) }
        await refresh()
    }

    public func deleteNotebook(_ id: ULID) async {
        await flush()
        await attempt { try await library.deleteNotebook(id) }
        await refresh()
    }

    public func createTag(name: String) async -> Tag? {
        var created: Tag?
        await attempt(tagName: name) { created = try await library.createTag(name: name) }
        await refresh()
        return created
    }

    public func renameTag(_ id: ULID, to name: String) async {
        await attempt(tagName: name) { try await library.renameTag(id, to: name) }
        await refresh()
    }

    public func deleteTag(_ id: ULID) async {
        await flush()
        await attempt { try await library.deleteTag(id) }
        await refresh()
    }

    // MARK: Search

    public func setSearch(_ text: String) async {
        searchText = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let before = visibleIDs
            clearSearchState()
            await fixSelection(previous: before)
            return
        }
        if searchHits == nil {
            if case .notebook(let id) = selection { searchNotebookID = id }
            if case .tag(let id) = selection { searchTagIDs = [id] }
        }
        await runSearch()
    }

    /// For the search field binding: shows the text at once and searches in the background.
    public func typeSearch(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        Task { await setSearch(text) }
    }

    /// The library's search field: searches every note, whatever view was selected.
    public func searchAll(_ text: String) async {
        if selection != .all { await select(.all) }
        await setSearch(text)
    }

    public func setSearchNotebook(_ id: ULID?) async {
        searchNotebookID = id
        await runSearch()
    }

    public func toggleSearchTag(_ id: ULID) async {
        if searchTagIDs.contains(id) { searchTagIDs.remove(id) } else { searchTagIDs.insert(id) }
        await runSearch()
    }

    private func clearSearchState() {
        searchGeneration += 1   // a search still running must not apply its results after this
        searchText = ""
        searchHits = nil
        searchTagIDs = []
        searchNotebookID = nil
    }

    private func runSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let query = searchText
        let before = visibleIDs
        var hits: [SearchHit] = []
        let inTrash = selection == .trash
        await attempt { hits = try await library.search(query, notebookID: searchNotebookID, tagIDs: searchTagIDs, inTrash: inTrash) }
        if let delay = searchDelay?(query) { try? await Task.sleep(for: delay) }
        guard generation == searchGeneration else { return }   // a newer search started meanwhile
        searchHits = hits
        await fixSelection(previous: before)
    }

    // MARK: Import and export

    public func importMarkdownFolder(_ url: URL) async -> ImportReport? {
        await flush()
        var report: ImportReport?
        await attempt { report = try await library.importMarkdownFolder(from: url) }
        await refresh()
        return report
    }

    public func export(to url: URL, notebook: ULID?) async -> ExportReport? {
        await flush()
        var report: ExportReport?
        await attempt { report = try await library.exportMarkdown(to: url, notebookID: notebook) }
        return report
    }

    // MARK: Errors

    /// Runs `body`, showing a failure in `lastError`. Public for the platforms' own model extensions (Share hand-off).
    public func attempt(tagName: String? = nil, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch let error as LibraryError {
            lastError = Self.message(for: error, tagName: tagName)
        } catch {
            lastError = "Something went wrong: \(error.localizedDescription)"
        }
    }

    public static func message(for error: LibraryError, tagName: String?) -> String {
        switch error {
        case .duplicateTagName(let key): "A tag named “\(tagName ?? key)” already exists."
        case .notebookCycle: "A notebook can't go inside its own sub-notebook."
        case .invalidName: "Names can't be empty."
        case .notFound: "That item no longer exists."
        case .newerSchema: "This library was made by a newer FeatherMark. Update the app to open it."
        }
    }
}

