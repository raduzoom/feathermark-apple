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
    @Environment(\.splitLayout) private var split

    var body: some View {
        Group {
            // iPad: flat rows in the system's floating glass sidebar (board tablet-main-ipados-landscape-light);
            // iPhone: inset cards.
            if split { list.listStyle(.sidebar) } else { list.listStyle(.insetGrouped) }
        }
        .overlay {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let hits = model.searchHits, hits.isEmpty {
                EmptyStateView(title: "No notes match “\(query)”", message: "Try fewer words, or check the spelling.")
            }
        }
        .scrollContentBackground(.hidden)
        .columnBackground(.library)
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

    private var list: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections } else { results }
        }
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
    private func isSelected(_ item: SidebarItem) -> Bool { split && model.selection == item }

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
            HStack(spacing: Theme.s16 - Theme.s4) {
                Group {
                    if let symbol { Image(systemName: symbol).foregroundStyle(Theme.accent) } else { Color.clear }
                }
                .frame(width: 24)
                Text(name)
                    .lineLimit(1)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Theme.accent : Theme.ink)
                Spacer(minLength: Theme.s8)
                if let count {
                    Text(count, format: .number).foregroundStyle(Theme.textSecondary).monospacedDigit()
                }
            }
            .padding(.leading, indent)
            .frame(minHeight: 44)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .libraryRowBackground(selected: selected)
        .accessibilityLabel(count.map { "\(name), \($0)" } ?? name)
        .accessibilityIdentifier("library-\(name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A library row's background: on iPhone an inset card (mint when selected); on iPad nothing, or a rounded mint tint
/// for the selected row, with no separators.
private struct LibraryRowBackground: ViewModifier {
    let selected: Bool
    @Environment(\.splitLayout) private var split

    func body(content: Content) -> some View {
        if split {
            content
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.accentTint : Color.clear)
                        .padding(.horizontal, Theme.s8))
                .listRowSeparator(.hidden)
        } else {
            content.listRowBackground(selected ? Theme.accentTint : Theme.card)
        }
    }
}

extension View {
    func libraryRowBackground(selected: Bool) -> some View { modifier(LibraryRowBackground(selected: selected)) }
}
