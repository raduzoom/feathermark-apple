import FeatherAppModel
import FeatherCore
import SwiftUI

/// Library, note list and note: side by side on iPad (landscape; in portrait the library slides in from the
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

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            LibraryView(model: model, open: open, openNote: openNote, showSettings: $showSettings)
        } content: {
            NoteListView(model: model, openNote: openNote)
        } detail: {
            NoteDetailColumn(model: model)
        }
        .navigationSplitViewStyle(.balanced)
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
}

/// The detail column: the open note, or a hint on iPad when none is open.
struct NoteDetailColumn: View {
    let model: AppModel

    var body: some View {
        if let editor = model.editor {
            ReaderView(model: model, editor: editor)
        } else {
            EmptyStateView(title: "No note open", message: "Select a note to read it.")
                .background(GlassBackground())
        }
    }
}
