import FeatherAppModel
import FeatherCore
import SwiftUI

/// The note list (boards mobile-note-list-ios-light and mobile-note-actions-swipe-ios-light).
struct NoteListView: View {
    let model: AppModel
    let openNote: (ULID) -> Void
    @State private var sheet: NoteSheet?
    @State private var confirmEmptyTrash = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: Binding(get: { model.searchText }, set: { model.typeSearch($0) }),
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.isSearching, let id = model.searchNotebookID, let name = model.notebookName(id) {
                    SearchScopeToken(name: name) { Task { await model.setSearchNotebook(nil) } }
                } else if !model.filterChips.isEmpty && !model.isSearching {
                    FilterChips(model: model)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .toolbar {
                if model.selection == .trash && model.counts.trash > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Empty Trash…", role: .destructive) { confirmEmptyTrash = true }
                    }
                }
            }
            .noteSheets(model: model, sheet: $sheet)
            .alert(emptyTrash.title, isPresented: $confirmEmptyTrash) {
                Button(emptyTrash.button, role: .destructive) { Task { await model.emptyTrash() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(emptyTrash.message)
            }
    }

    private var emptyTrash: Formatting.Confirmation { Formatting.emptyTrashConfirmation(count: model.counts.trash) }

    /// The boards call the whole library "All Notes".
    private var title: String { model.selection == .all ? "All Notes" : model.selectionTitle }

    @ViewBuilder private var content: some View {
        switch model.emptyState {
        case .firstLaunch:
            EmptyStateView(title: "A quiet place to write.",
                           message: "Your notes stay on this \(DeviceWord.current). No account, no network, nothing in the way.")
        case .emptyView:
            EmptyStateView(title: "Nothing here yet", message: "Notes you add here will show up in this list.")
        case .emptyTrash:
            EmptyStateView(title: "Trash is empty",
                           message: "Notes you delete wait here for \(model.trashRetentionDays) days before they're removed for good.")
        case .noSearchResults(let query, let limitedTo?):
            EmptyStateView(title: "No notes match “\(query)”",
                           message: "You're searching in \(limitedTo) only. Try all notebooks, or fewer words.",
                           action: ("Search All Notebooks", { Task { await model.setSearchNotebook(nil) } }))
        case .noSearchResults(let query, nil):
            EmptyStateView(title: "No notes match “\(query)”", message: "Try fewer words, or check the spelling.")
        default:
            list
        }
    }

    private var list: some View {
        List {
            if let hits = model.searchHits {
                ForEach(hits, id: \.note.id) { hit in
                    Button { openNote(hit.note.id) } label: { SearchResultRow(model: model, hit: hit) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: Theme.s4, leading: Theme.s16, bottom: Theme.s4, trailing: Theme.s16))
                        .contextMenu { NoteActions.menu(hit.note, model: model, sheet: $sheet) }
                }
            } else {
                rows
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("note-list")
    }

    @ViewBuilder private var rows: some View {
            ForEach(model.notes) { summary in
                Button { openNote(summary.id) } label: {
                    NoteRow(model: model, summary: summary, selected: sizeClass == .regular && model.selectedNoteID == summary.id)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Theme.s4, leading: Theme.s16, bottom: Theme.s4, trailing: Theme.s16))
                .swipeActions(edge: .leading, allowsFullSwipe: true) { NoteActions.leadingSwipe(summary, model: model) }
                .swipeActions(edge: .trailing, allowsFullSwipe: summary.trashedAt == nil) {
                    NoteActions.trailingSwipe(summary, model: model, sheet: $sheet)
                }
                .contextMenu { NoteActions.menu(summary, model: model, sheet: $sheet) }
            }
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: Theme.s8) {
            if let undo = model.undoTrash {
                UndoToast(offer: undo) { Task { await model.undoLastTrash() } }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !model.isSearching && model.selection != .trash && !model.notes.isEmpty {
                Text("\(model.notes.count) \(model.notes.count == 1 ? "note" : "notes") · on this \(DeviceWord.current) only")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .animation(.default, value: model.undoTrash)
    }
}

/// "In Travel ✕" above scoped search results: removing it searches every notebook.
struct SearchScopeToken: View {
    let name: String
    let remove: () -> Void

    var body: some View {
        HStack {
            Button(action: remove) {
                HStack(spacing: Theme.s8) {
                    Text("In \(name)")
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.s16)
                .frame(minHeight: 36)
                .background(Theme.accentTint, in: Capsule())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Searching in \(name). Search all notebooks")
            Spacer()
        }
        .padding(.horizontal, Theme.s16)
    }
}
