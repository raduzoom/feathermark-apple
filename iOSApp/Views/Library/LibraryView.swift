import FeatherAppModel
import FeatherCore
import SwiftUI

/// The library (board mobile-library-ios-light): views, notebooks, tags.
struct LibraryView: View {
    let model: AppModel
    let open: (SidebarItem) -> Void
    let openNote: (ULID) -> Void
    @Binding var showSettings: Bool
    /// The library's own search field: it searches every note and shows the results here, as Notes does.
    @State private var query = ""
    @State private var prompt: LibraryPrompt?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections } else { results }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let hits = model.searchHits, hits.isEmpty {
                EmptyStateView(title: "No notes match “\(query)”", message: "Try fewer words, or check the spelling.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlassBackground())
        .accessibilityIdentifier("library")
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search")
        .onChange(of: query) { _, text in
            Task { await model.searchAll(text) }
        }
        .onChange(of: model.isSearching) { _, searching in
            // The search ended elsewhere (the list's field on iPad): show the library again, not empty results.
            if !searching { query = "" }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { prompt = .newNotebook(parent: nil) } label: { Label("New Notebook…", systemImage: "folder.badge.plus") }
                } label: {
                    Label("Library actions", systemImage: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .libraryPrompts(model: model, prompt: $prompt)
    }

    @ViewBuilder private var results: some View {
        ForEach(model.searchHits ?? [], id: \.note.id) { hit in
            Button { openNote(hit.note.id) } label: { SearchResultRow(model: model, hit: hit) }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Theme.s4, leading: Theme.s16, bottom: Theme.s4, trailing: Theme.s16))
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            row(.all, "All Notes", symbol: "tray.full", count: model.counts.all)
            row(.recent, "Recent", symbol: "clock", count: nil)
            row(.pinned, "Pinned", symbol: "star", count: model.counts.pinned)
            row(.trash, "Trash", symbol: "trash", count: model.counts.trash)
        }
        if !model.notebooks.isEmpty {
            Section("Notebooks") {
                NotebookRows(model: model, open: open, isSelected: isSelected, prompt: $prompt)
            }
        }
        if !model.tags.isEmpty {
            Section("Tags") {
                TagChips(model: model, open: open, prompt: $prompt)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    /// Selection shows only where the list sits beside the library (iPad); on iPhone rows push.
    private func isSelected(_ item: SidebarItem) -> Bool { sizeClass == .regular && model.selection == item }

    private func row(_ item: SidebarItem, _ name: String, symbol: String, count: Int?) -> some View {
        LibraryRow(name: name, symbol: symbol, count: count, selected: isSelected(item)) { open(item) }
    }
}

/// One tappable library row: symbol, name, count, chevron. 44 pt tall at least.
struct LibraryRow: View {
    let name: String
    let symbol: String?
    let count: Int?
    var selected = false
    var indent: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s16) {
                Group {
                    if let symbol { Image(systemName: symbol).foregroundStyle(Theme.accent) } else { Color.clear }
                }
                .frame(width: 24)
                Text(name).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s8)
                if let count {
                    Text(count, format: .number).foregroundStyle(Theme.textSecondary).monospacedDigit()
                }
            }
            .padding(.leading, indent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Theme.accentTint : Theme.card)
        .accessibilityLabel(count.map { "\(name), \($0)" } ?? name)
        .accessibilityIdentifier("library-\(name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
