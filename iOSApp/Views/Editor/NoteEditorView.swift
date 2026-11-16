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
    @State private var width: CGFloat = 0
    @Environment(\.splitLayout) private var split

    /// iPad with room for labels (landscape): Pin, Tags and Move spelled out, as on the Mac. Narrower (portrait):
    /// icons, with Tags and Move in ⋯ (ipad-adaptation-notes "Toolbar").
    private var labelled: Bool { split && width >= 540 }

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
            isEditing: $isEditing, handle: handle,
            titleSize: split ? (labelled ? 38 : 34) : nil)
            .ignoresSafeArea(.container, edges: .bottom)
            .columnBackground(.editor)
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { handle.endEditing() }
            }
        }
        if !editor.isTrashed {
            ToolbarItemGroup(placement: .topBarTrailing) {
                pinButton
                if labelled {
                    Button("Tags") { sheet = .tags(editor.id) }
                    Button("Move") { sheet = .move(editor.id) }
                }
                if split {
                    ShareLink(item: NoteShare(id: editor.id, library: model.library),
                              preview: SharePreview(Formatting.displayTitle(editor.title))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu { moreMenu } label: { Label("Note actions", systemImage: "ellipsis") }
        }
    }

    /// Pin: a star on iPhone and in iPad portrait; "Pin" or "Pinned" with the star in iPad landscape.
    @ViewBuilder private var pinButton: some View {
        Button { Task { await model.togglePin(editor.id) } } label: {
            if labelled {
                // An HStack, not a Label: a toolbar shows a Label's icon only.
                HStack(spacing: Theme.s4 + 2) {
                    Image(systemName: editor.pinned ? "star.fill" : "star")
                    Text(editor.pinned ? "Pinned" : "Pin")
                }
                .foregroundStyle(editor.pinned ? Theme.accent : Theme.ink)
            } else {
                Image(systemName: editor.pinned ? "star.fill" : "star")
                    .foregroundStyle(editor.pinned ? Theme.accent : Theme.ink)
            }
        }
        .accessibilityLabel(editor.pinned ? "Unpin" : "Pin")
    }

    /// ⋯: on iPhone every note action plus Markdown; on iPad only what the toolbar doesn't show already.
    @ViewBuilder private var moreMenu: some View {
        if editor.isTrashed || !split {
            NoteActions.menu(NoteRef(editor), model: model, sheet: $sheet)
        } else if !labelled {
            Button { sheet = .tags(editor.id) } label: { Label("Tags…", systemImage: "tag") }
            Button { sheet = .move(editor.id) } label: { Label("Move to Notebook…", systemImage: "folder") }
        }
        if !editor.isTrashed {
            Divider()
            Toggle(isOn: Binding(get: { model.editorMode == .raw }, set: { _ in model.toggleEditorMode() })) {
                Label("Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            if split {
                Divider()
                Button(role: .destructive) { Task { await model.trashWithUndo(editor.id) } } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
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
