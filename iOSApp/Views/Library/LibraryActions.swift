import FeatherAppModel
import FeatherCore
import SwiftUI

/// What a library action asks next: a name, a confirmation, or a parent notebook. No board covers these; they're
/// native alerts and sheets (recorded as builder's choices in the Phase 12 ledger).
enum LibraryPrompt: Identifiable {
    case newNotebook(parent: Notebook?)
    case renameNotebook(Notebook)
    case moveNotebook(Notebook)
    case deleteNotebook(Notebook)
    case renameTag(Tag)
    case deleteTag(Tag)

    /// Which kind of question it asks.
    enum Kind { case name, confirm, pickParent }
    var kind: Kind {
        switch self {
        case .newNotebook, .renameNotebook, .renameTag: .name
        case .deleteNotebook, .deleteTag: .confirm
        case .moveNotebook: .pickParent
        }
    }

    var id: String {
        switch self {
        case .newNotebook(let p): "new-\(p?.id.description ?? "root")"
        case .renameNotebook(let n): "rename-\(n.id)"
        case .moveNotebook(let n): "move-\(n.id)"
        case .deleteNotebook(let n): "delete-\(n.id)"
        case .renameTag(let t): "rename-tag-\(t.id)"
        case .deleteTag(let t): "delete-tag-\(t.id)"
        }
    }
}

/// The long-press menus of notebooks and tags.
@MainActor enum LibraryMenus {
    @ViewBuilder static func notebook(_ nb: Notebook, prompt: Binding<LibraryPrompt?>) -> some View {
        Button { prompt.wrappedValue = .newNotebook(parent: nb) } label: { Label("New Notebook Inside…", systemImage: "folder.badge.plus") }
        Button { prompt.wrappedValue = .renameNotebook(nb) } label: { Label("Rename…", systemImage: "pencil") }
        Button { prompt.wrappedValue = .moveNotebook(nb) } label: { Label("Move to…", systemImage: "folder") }
        Button(role: .destructive) { prompt.wrappedValue = .deleteNotebook(nb) } label: { Label("Delete Notebook…", systemImage: "trash") }
    }

    @ViewBuilder static func tag(_ tag: Tag, prompt: Binding<LibraryPrompt?>) -> some View {
        Button { prompt.wrappedValue = .renameTag(tag) } label: { Label("Rename…", systemImage: "pencil") }
        Button(role: .destructive) { prompt.wrappedValue = .deleteTag(tag) } label: { Label("Delete Tag…", systemImage: "trash") }
    }
}

extension View {
    /// Presents the alert or sheet for `prompt` and runs the model call it ends in.
    func libraryPrompts(model: AppModel, prompt: Binding<LibraryPrompt?>) -> some View {
        modifier(LibraryPromptsModifier(model: model, prompt: prompt))
    }
}

private struct LibraryPromptsModifier: ViewModifier {
    let model: AppModel
    @Binding var prompt: LibraryPrompt?
    @State private var name = ""

    private func shows(_ kind: LibraryPrompt.Kind) -> Binding<Bool> {
        Binding(get: { prompt?.kind == kind }, set: { if !$0 { prompt = nil } })
    }

    private var naming: (title: String, button: String)? {
        switch prompt {
        case .newNotebook(let parent?): ("New Notebook in “\(parent.name)”", "Create Notebook")
        case .newNotebook(nil): ("New Notebook", "Create Notebook")
        case .renameNotebook: ("Rename Notebook", "Rename")
        case .renameTag: ("Rename Tag", "Rename")
        default: nil
        }
    }

    private var confirmation: Formatting.Confirmation? {
        switch prompt {
        case .deleteNotebook(let nb):
            Formatting.deleteNotebookConfirmation(name: nb.name, subNotebooks: model.subNotebookCount(of: nb.id),
                                                  notes: model.counts.notebooks[nb.id] ?? 0)
        case .deleteTag(let tag):
            Formatting.Confirmation(title: "Delete tag “\(tag.name)”?", message: "Notes keep their text; only the tag is removed.",
                                    button: "Delete Tag")
        default: nil
        }
    }

    private var moving: Notebook? { if case .moveNotebook(let nb) = prompt { nb } else { nil } }

    func body(content: Content) -> some View {
        content
            .alert(naming?.title ?? "", isPresented: shows(.name)) {
                TextField("Name", text: $name)
                Button(naming?.button ?? "OK") { commitName() }
                Button("Cancel", role: .cancel) { prompt = nil }
            }
            .alert(confirmation?.title ?? "", isPresented: shows(.confirm)) {
                Button(confirmation?.button ?? "Delete", role: .destructive) { commitDelete() }
                Button("Cancel", role: .cancel) { prompt = nil }
            } message: {
                Text(confirmation?.message ?? "")
            }
            .sheet(isPresented: shows(.pickParent)) {
                if let nb = moving {
                    NotebookPicker(model: model, title: "Move “\(nb.name)” to", current: nb.parentID, excluding: nb.id) { parent in
                        Task { await model.moveNotebook(nb.id, to: parent) }
                    }
                }
            }
            .onChange(of: prompt?.id) {
                switch prompt {
                case .renameNotebook(let nb): name = nb.name
                case .renameTag(let tag): name = tag.name
                default: name = ""
                }
            }
    }

    private func commitName() {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = prompt
        prompt = nil
        Task {
            switch action {
            case .newNotebook(let parent): _ = await model.createNotebook(name: text, parent: parent?.id)
            case .renameNotebook(let nb): await model.renameNotebook(nb.id, to: text)
            case .renameTag(let tag): await model.renameTag(tag.id, to: text)
            default: break
            }
        }
    }

    private func commitDelete() {
        let action = prompt
        prompt = nil
        Task {
            switch action {
            case .deleteNotebook(let nb): await model.deleteNotebook(nb.id)
            case .deleteTag(let tag): await model.deleteTag(tag.id)
            default: break
            }
        }
    }
}
