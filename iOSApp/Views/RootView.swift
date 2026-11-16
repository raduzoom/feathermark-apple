import FeatherAppModel
import FeatherCore
import SwiftUI

/// Library, note list and note editor: side by side on iPad (landscape; in portrait the library slides in from the
/// sidebar button), a stack on iPhone. The model owns the selection; this view only decides which column shows
/// on iPhone.
struct RootView: View {
    let model: AppModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var showSettings = false
    /// The note this view pushed on iPhone. When the model's open note changes away from it (trashed, restored,
    /// deleted), the stack goes back to the list instead of showing another note in its place.
    @State private var pushedNoteID: ULID?
    /// The window's top safe area, where the iPad's glass panels start.
    @State private var panelTop: CGFloat = 0
    @State private var windowSize = CGSize.zero
    /// ⌘F: each bump focuses the list's search field.
    @State private var searchRequest = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad (not Slide Over or a narrow split screen): the columns sit side by side as glass panels.
    private var split: Bool { sizeClass == .regular }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            LibraryView(model: model, open: open, openNote: openNote, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(260)
        } content: {
            NoteListView(model: model, openNote: openNote, newNote: newNote, searchRequest: searchRequest)
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 320)
        } detail: {
            NoteDetailColumn(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.splitLayout, split)
        .environment(\.panelTop, panelTop)
        .environment(\.windowSize, windowSize)
        .padding(.horizontal, split ? Theme.panelGap / 2 : 0)
        .background {
            ZStack {
                if split { GlassBackground() }
                // The whole window, safe areas included (a reader that ignores them measures all of it).
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, size in windowSize = size }
                }
                .ignoresSafeArea()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { panelTop = $0 }
        .focusedSceneValue(\.featherCommands, FeatherCommandActions(
            newNote: newNote, search: search,
            toggleMarkdown: model.editor == nil ? nil : { model.toggleEditorMode() }))
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .onChange(of: model.selectedNoteID) { _, current in
            if compactColumn == .detail, let pushed = pushedNoteID, current != pushed { compactColumn = .content }
        }
        .alert(model.lastError ?? "", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        }
    }

    /// A library row: show that view's notes (and, on iPhone, push the list).
    private func open(_ item: SidebarItem) {
        Task { await model.select(item) }
        compactColumn = .content
    }

    /// A note row: open the note (and, on iPhone, push it).
    private func openNote(_ id: ULID) {
        pushedNoteID = id
        Task { await model.selectNote(id) }
        compactColumn = .detail
    }

    /// ⌘F: the list's search field (on iPhone width, the list shows first).
    private func search() {
        if compactColumn == .detail { compactColumn = .content }
        searchRequest += 1
    }

    /// New Note: a new note opens with its title focused (and, on iPhone, is pushed).
    private func newNote() {
        Task {
            await model.newNote()
            guard let id = model.selectedNoteID else { return }
            pushedNoteID = id
            compactColumn = .detail
        }
    }
}

/// The detail column: the open note, or a hint on iPad when none is open.
struct NoteDetailColumn: View {
    let model: AppModel

    var body: some View {
        if let editor = model.editor {
            NoteEditorView(model: model, editor: editor)
        } else {
            EmptyStateView(title: "No note open", message: "Select a note, or start a new one.")
                .columnBackground(.editor)
        }
    }
}
