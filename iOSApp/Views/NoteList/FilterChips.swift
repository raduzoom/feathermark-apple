import FeatherAppModel
import SwiftUI

/// All, Pinned and the top-level notebooks, under the list's title. The selected chip has the mint tint.
struct FilterChips: View {
    let model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.s8) {
                ForEach(model.filterChips, id: \.self) { item in
                    let name = self.name(item)
                    let selected = model.selection == item
                    Button { Task { await model.select(item) } } label: {
                        Text(name)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.accent : Theme.ink)
                            .padding(.horizontal, Theme.s16)
                            .frame(minHeight: 36)
                            .background(selected ? Theme.accentTint : Theme.raised, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityIdentifier("chip-\(name)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.s16)
        }
        .padding(.bottom, Theme.s4)
    }

    private func name(_ item: SidebarItem) -> String {
        switch item {
        case .all: "All"
        case .pinned: "Pinned"
        case .notebook(let id): model.notebookName(id) ?? "Notebook"
        default: model.selectionTitle
        }
    }
}
