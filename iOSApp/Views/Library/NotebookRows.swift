import FeatherAppModel
import FeatherCore
import SwiftUI

/// The notebook tree: top-level notebooks, and sub-notebooks under a disclosure chevron.
struct NotebookRows: View {
    let model: AppModel
    let open: (SidebarItem) -> Void
    let isSelected: (SidebarItem) -> Bool
    @Binding var prompt: LibraryPrompt?
    /// Expanded notebook ids, comma-separated (kept per window across launches).
    @SceneStorage("expandedNotebooks") private var expandedStorage = ""

    private var children: [ULID?: [Notebook]] { Dictionary(grouping: model.notebooks, by: \.parentID) }

    var body: some View {
        ForEach(visible, id: \.notebook.id) { entry in
            NotebookRow(model: model, notebook: entry.notebook, depth: entry.depth,
                        hasChildren: !(children[entry.notebook.id] ?? []).isEmpty,
                        expanded: expanded.contains(entry.notebook.id.description),
                        selected: isSelected(.notebook(entry.notebook.id)),
                        toggle: { toggle(entry.notebook.id) }, open: { open(.notebook(entry.notebook.id)) })
            .contextMenu { LibraryMenus.notebook(entry.notebook, prompt: $prompt) }
        }
    }

    private var expanded: Set<String> { Set(expandedStorage.split(separator: ",").map(String.init)) }

    private func toggle(_ id: ULID) {
        var set = expanded
        if set.contains(id.description) { set.remove(id.description) } else { set.insert(id.description) }
        expandedStorage = set.sorted().joined(separator: ",")
    }

    /// Rows in tree order, children only under expanded parents.
    private var visible: [(notebook: Notebook, depth: Int)] {
        var out: [(Notebook, Int)] = []
        let children = children
        let expanded = expanded
        func walk(_ parent: ULID?, _ depth: Int) {
            for nb in children[parent] ?? [] {
                out.append((nb, depth))
                if expanded.contains(nb.id.description) { walk(nb.id, depth + 1) }
            }
        }
        walk(nil, 0)
        return out
    }
}

private struct NotebookRow: View {
    let model: AppModel
    let notebook: Notebook
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            LibraryRow(name: notebook.name, symbol: depth == 0 ? "folder" : nil,
                       count: model.counts.notebooks[notebook.id] ?? 0, selected: selected,
                       indent: CGFloat(depth) * Theme.s24, action: open)
            if hasChildren {
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide sub-notebooks of \(notebook.name)" : "Show sub-notebooks of \(notebook.name)")
            }
        }
        .listRowBackground(selected ? Theme.accentTint : Theme.card)
    }
}

/// Tags as wrapped capsules under the notebooks.
struct TagChips: View {
    let model: AppModel
    let open: (SidebarItem) -> Void
    @Binding var prompt: LibraryPrompt?

    var body: some View {
        FlowLayout(spacing: Theme.s8) {
            ForEach(model.tags) { tag in
                Button { open(.tag(tag.id)) } label: {
                    Text(tag.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.s16)
                        .frame(minHeight: 36)
                        .background(model.selection == .tag(tag.id) ? Theme.accentTint : Theme.raised, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { LibraryMenus.tag(tag, prompt: $prompt) }
                .accessibilityIdentifier("library-\(tag.name)")
            }
        }
        .padding(.vertical, Theme.s4)
    }
}

/// Lays children out left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
