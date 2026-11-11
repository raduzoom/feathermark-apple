import CoreTransferable
import FeatherAppModel
import FeatherCore
import SwiftUI
import UniformTypeIdentifiers

/// The note a row, menu or editor acts on.
struct NoteRef: Equatable {
    var id: ULID
    var title: String
    var pinned: Bool
    var isTrashed: Bool

    init(_ s: NoteSummary) { id = s.id; title = s.title; pinned = s.pinned; isTrashed = s.trashedAt != nil }
    init(_ e: EditorState) { id = e.id; title = e.title; pinned = e.pinned; isTrashed = e.isTrashed }
}

/// What a note action opens next.
enum NoteSheet: Identifiable {
    case tags(ULID), move(ULID), deleteConfirm(NoteRef)
    var id: String {
        switch self {
        case .tags(let id): "tags-\(id)"
        case .move(let id): "move-\(id)"
        case .deleteConfirm(let n): "delete-\(n.id)"
        }
    }
}

/// One source for the swipe actions, the long-press menu and the editor's ⋯ menu (board
/// mobile-note-actions-menu-ios-light).
@MainActor enum NoteActions {
    @ViewBuilder static func menu(_ summary: NoteSummary, model: AppModel, sheet: Binding<NoteSheet?>) -> some View {
        menu(NoteRef(summary), model: model, sheet: sheet)
    }

    @ViewBuilder static func menu(_ note: NoteRef, model: AppModel, sheet: Binding<NoteSheet?>) -> some View {
        if note.isTrashed {
            Button { Task { await model.restore(note.id) } } label: { Label("Restore Note", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { sheet.wrappedValue = .deleteConfirm(note) } label: {
                Label("Delete Permanently…", systemImage: "trash.slash")
            }
        } else {
            Button { Task { await model.togglePin(note.id) } } label: {
                Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "star.slash" : "star")
            }
            Button { sheet.wrappedValue = .tags(note.id) } label: { Label("Tags…", systemImage: "tag") }
            Button { sheet.wrappedValue = .move(note.id) } label: { Label("Move to Notebook…", systemImage: "folder") }
            ShareLink(item: NoteShare(id: note.id, library: model.library),
                      preview: SharePreview(Formatting.displayTitle(note.title))) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) { Task { await model.trashWithUndo(note.id) } } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }

    /// Swipe right: Pin (Restore in the Trash). A full swipe does it.
    @ViewBuilder static func leadingSwipe(_ summary: NoteSummary, model: AppModel) -> some View {
        if summary.trashedAt != nil {
            Button { Task { await model.restore(summary.id) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                .tint(Theme.accent)
        } else {
            Button { Task { await model.togglePin(summary.id) } } label: {
                Label(summary.pinned ? "Unpin" : "Pin", systemImage: summary.pinned ? "star.slash.fill" : "star.fill")
            }
            .tint(Theme.accent)
        }
    }

    /// Swipe left: Trash (a full swipe, no confirmation: Undo instead), Move, Tags. In the Trash: Delete Permanently….
    @ViewBuilder static func trailingSwipe(_ summary: NoteSummary, model: AppModel, sheet: Binding<NoteSheet?>) -> some View {
        if summary.trashedAt != nil {
            Button { sheet.wrappedValue = .deleteConfirm(NoteRef(summary)) } label: { Label("Delete", systemImage: "trash.slash") }
                .tint(Theme.destructive)
        } else {
            Button(role: .destructive) { Task { await model.trashWithUndo(summary.id) } } label: { Label("Trash", systemImage: "trash") }
                .tint(Theme.destructive)
            Button { sheet.wrappedValue = .move(summary.id) } label: { Label("Move", systemImage: "folder") }
                .tint(Theme.swipeMove)
            Button { sheet.wrappedValue = .tags(summary.id) } label: { Label("Tags", systemImage: "tag") }
                .tint(Theme.swipeTags)
        }
    }
}

extension View {
    /// Presents the Tags and Move sheets and the Delete Permanently confirmation for `sheet`.
    func noteSheets(model: AppModel, sheet: Binding<NoteSheet?>) -> some View {
        modifier(NoteSheetsModifier(model: model, sheet: sheet))
    }
}

private struct NoteSheetsModifier: ViewModifier {
    let model: AppModel
    @Binding var sheet: NoteSheet?

    private var pickerSheet: Binding<NoteSheet?> {
        Binding(get: { if case .deleteConfirm = sheet { nil } else { sheet } }, set: { sheet = $0 })
    }

    private var deleting: NoteRef? { if case .deleteConfirm(let n) = sheet { n } else { nil } }

    func body(content: Content) -> some View {
        let confirmation = Formatting.deletePermanentlyConfirmation(title: deleting?.title ?? "")
        content
            .sheet(item: pickerSheet) { item in
                switch item {
                case .tags(let id): TagsSheet(model: model, noteID: id)
                case .move(let id): MoveSheet(model: model, noteID: id)
                case .deleteConfirm: EmptyView()
                }
            }
            .alert(confirmation.title, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { sheet = nil } })) {
                Button(confirmation.button, role: .destructive) {
                    if let id = deleting?.id { Task { await model.deletePermanently(id) } }
                    sheet = nil
                }
                Button("Cancel", role: .cancel) { sheet = nil }
            } message: {
                Text(confirmation.message)
            }
    }
}

/// A note shared as plain Markdown text: its title as the first line, then its body. Read when shared.
struct NoteShare: Transferable {
    let id: ULID
    let library: Library

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .utf8PlainText) { share in
            guard let note = try await share.library.note(share.id) else { return Data() }
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return Data((title.isEmpty ? note.body : "\(title)\n\n\(note.body)").utf8)
        }
    }
}
