import FeatherAppModel
import FeatherCore
import SwiftUI

/// The open note, read-only until Phase 13's editor: notebook and date, the serif title, the styled Markdown.
struct ReaderView: View {
    let model: AppModel
    let editor: EditorState
    @State private var sheet: NoteSheet?

    var body: some View {
        ReaderTextView(model: model, editor: editor, meta: meta)
            .ignoresSafeArea(.container, edges: .bottom)
            .background(GlassBackground())
            .safeAreaInset(edge: .top, spacing: 0) {
                if editor.isTrashed { TrashBanner(model: model, editor: editor, sheet: $sheet) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NoteActions.menu(NoteRef(editor), model: model, sheet: $sheet)
                    } label: {
                        Label("Note actions", systemImage: "ellipsis")
                    }
                }
            }
            .noteSheets(model: model, sheet: $sheet)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reader")
    }

    /// "Home · Edited today at 10:42".
    private var meta: String {
        let edited = Formatting.editedLine(editor.modified, now: Date())
        return editor.notebookID.flatMap(model.notebookName).map { "\($0) · \(edited)" } ?? edited
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
