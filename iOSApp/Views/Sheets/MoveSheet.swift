import FeatherAppModel
import FeatherCore
import SwiftUI

/// A notebook picker: "No Notebook", then the tree, the current one ticked. Used by Move to Notebook… and,
/// with `excluding`, by moving a notebook (Task 8).
struct NotebookPicker: View {
    let model: AppModel
    let title: String
    let current: ULID?
    var excluding: ULID?
    let pick: (ULID?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row(nil, "No Notebook", depth: 0)
                ForEach(tree, id: \.0.id) { notebook, depth in row(notebook.id, notebook.name, depth: depth) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func row(_ id: ULID?, _ name: String, depth: Int) -> some View {
        Button {
            pick(id)
            dismiss()
        } label: {
            HStack {
                Image(systemName: id == nil ? "tray" : "folder").foregroundStyle(Theme.accent).frame(width: 24)
                    .accessibilityHidden(true)
                Text(name).foregroundStyle(Theme.ink)
                Spacer()
                if id == current { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.leading, CGFloat(depth) * Theme.s24)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("move-\(name)")
        .accessibilityAddTraits(id == current ? .isSelected : [])
    }

    /// Notebooks in tree order with their depth, leaving out `excluding` and everything under it.
    private var tree: [(Notebook, Int)] {
        let children = Dictionary(grouping: model.notebooks, by: \.parentID)
        var out: [(Notebook, Int)] = []
        func walk(_ parent: ULID?, _ depth: Int) {
            for nb in children[parent] ?? [] where nb.id != excluding {
                out.append((nb, depth))
                walk(nb.id, depth + 1)
            }
        }
        walk(nil, 0)
        return out
    }
}

/// Move to Notebook… for one note.
struct MoveSheet: View {
    let model: AppModel
    let noteID: ULID

    var body: some View {
        NotebookPicker(model: model, title: "Move to Notebook", current: model.notes.first { $0.id == noteID }?.notebookID
                       ?? model.editor.flatMap { $0.id == noteID ? $0.notebookID : nil }) { target in
            Task { await model.move(noteID, to: target) }
        }
    }
}
