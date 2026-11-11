import FeatherAppModel
import FeatherCore
import FeatherEditorPhone
import QuickLook
import SwiftUI

/// The open note (board mobile-editor-ios-light): the notebook and edited line, the serif title and the live
/// Markdown body in one scroll, the formatting bar above the keyboard. A note in the Trash shows read-only under the
/// Trash banner.
struct NoteEditorView: View {
    let model: AppModel
    let editor: EditorState
    @State private var sheet: NoteSheet?
    @State private var attachSource: AttachSource?
    @State private var isEditing = false
    @State private var handle = PhoneEditorHandle()
    @State private var preview: URL?

    var body: some View {
        PhoneMarkdownEditor(
            text: Binding(get: { editor.body }, set: { model.editBody($0) }),
            title: Binding(get: { editor.title }, set: { model.editTitle($0) }),
            meta: meta, noteID: editor.id, mode: model.editorMode, isEditable: !editor.isTrashed,
            resolveAttachment: { model.attachmentURL(for: $0) },
            importFiles: { await model.addAttachments(from: $0) },
            openLink: open,
            attach: { attachSource = $0 },
            wantsTitleFocus: model.titleWantsFocus, titleTookFocus: { model.titleTookFocus() },
            isEditing: $isEditing, handle: handle)
            .ignoresSafeArea(.container, edges: .bottom)
            .background(GlassBackground())
            .safeAreaInset(edge: .top, spacing: 0) {
                if editor.isTrashed { TrashBanner(model: model, editor: editor, sheet: $sheet) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .noteSheets(model: model, sheet: $sheet)
            .attachmentPicker(source: $attachSource) { urls in
                handle.attachPicked(urls, cleaningUp: AttachmentPicker.folders(of: urls))
            }
            .quickLookPreview($preview)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("note-editor")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { handle.endEditing() }
            }
        }
        if !editor.isTrashed {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.togglePin(editor.id) } } label: {
                    Image(systemName: editor.pinned ? "star.fill" : "star")
                        .foregroundStyle(editor.pinned ? Theme.accent : Theme.ink)
                }
                .accessibilityLabel(editor.pinned ? "Unpin" : "Pin")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                NoteActions.menu(NoteRef(editor), model: model, sheet: $sheet)
                if !editor.isTrashed {
                    Divider()
                    Toggle(isOn: Binding(get: { model.editorMode == .raw }, set: { _ in model.toggleEditorMode() })) {
                        Label("Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            } label: {
                Label("Note actions", systemImage: "ellipsis")
            }
        }
    }

    /// "Home · Edited today at 10:42".
    private var meta: String {
        let edited = Formatting.editedLine(editor.modified, now: Date())
        return editor.notebookID.flatMap(model.notebookName).map { "\($0) · \(edited)" } ?? edited
    }

    /// Web links open in the browser; an attachment opens in Quick Look.
    private func open(_ link: String) {
        if link.hasPrefix("feather://attachment/") {
            preview = model.attachmentURL(for: link)
        } else if let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            UIApplication.shared.open(url)
        }
    }
}

/// Above a trashed note (ui-copy "Trash"): restore it, or delete it for good.
struct TrashBanner: View {
    let model: AppModel
    let editor: EditorState
    @Binding var sheet: NoteSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            Text("This note is in the Trash")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("It's read-only. Restore it to edit.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.s16) {
                Button("Delete Permanently…", role: .destructive) { sheet = .deleteConfirm(NoteRef(editor)) }
                    .foregroundStyle(Theme.destructive)
                    .frame(minHeight: 44)
                Spacer()
                Button("Restore Note") { Task { await model.restore(editor.id) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primaryFill)
                    .foregroundStyle(Theme.onPrimary)
                    .frame(minHeight: 44)
            }
        }
        .padding(Theme.s16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal, Theme.s16)
        .padding(.top, Theme.s8)
    }
}
