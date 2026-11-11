// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import SwiftUI
import UIKit

/// Lets a SwiftUI screen reach the editor view it shows (to hand it picked files, or end editing).
@MainActor
public final class PhoneEditorHandle {
    public weak var view: PhoneEditorView?
    public init() {}

    /// Hands the picked files to the editor (none: the pick was cancelled).
    public func attachPicked(_ urls: [URL], cleaningUp: [URL]) {
        if let view { view.attachPicked(urls, cleaningUp: cleaningUp) } else { cleaningUp.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    /// Hides the keyboard, wherever the focus is (title or body).
    public func endEditing() { (view?.superview ?? view)?.endEditing(true) }
}

/// Holds the editor and its header (the title and meta line sit beside the body, following its scroll).
@MainActor
public final class PhoneEditorContainer: UIView {
    public let editor = PhoneEditorView.make()

    init() {
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(editor)
        editor.attachHeader()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if editor.frame != bounds { editor.frame = bounds }
    }
}

/// The live-preview editor for SwiftUI on iPhone and iPad: the title and meta line above the body, all in one
/// scroll. Load a different note by changing `noteID`. The same parameters as the Mac's `MarkdownEditor`, plus the
/// title, the attachment picker and focus.
public struct PhoneMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var title: String
    var meta: String
    var noteID: AnyHashable
    var mode: EditorMode
    var isEditable: Bool
    var placeholder: String
    var titlePlaceholder: String
    var resolveAttachment: (String) -> URL?
    var importFiles: ([URL]) async -> [String]
    var openLink: (String) -> Void
    var theme: EditorTheme
    var attach: (AttachSource) -> Void
    /// True asks for the title's focus (a new note); `titleTookFocus` says it happened.
    var wantsTitleFocus: Bool
    var titleTookFocus: () -> Void
    /// Whether the title or body is being edited (the keyboard is up for them).
    @Binding var isEditing: Bool
    var handle: PhoneEditorHandle?

    public init(text: Binding<String>, title: Binding<String>, meta: String, noteID: AnyHashable, mode: EditorMode, isEditable: Bool,
                placeholder: String = "Start writing…", titlePlaceholder: String = "Title",
                resolveAttachment: @escaping (String) -> URL? = { _ in nil },
                importFiles: @escaping ([URL]) async -> [String] = { _ in [] },
                openLink: @escaping (String) -> Void = { url in if let u = URL(string: url) { UIApplication.shared.open(u) } },
                theme: EditorTheme = .standard,
                attach: @escaping (AttachSource) -> Void = { _ in },
                wantsTitleFocus: Bool = false, titleTookFocus: @escaping () -> Void = {},
                isEditing: Binding<Bool> = .constant(false), handle: PhoneEditorHandle? = nil) {
        _text = text
        _title = title
        self.meta = meta
        self.noteID = noteID
        self.mode = mode
        self.isEditable = isEditable
        self.placeholder = placeholder
        self.titlePlaceholder = titlePlaceholder
        self.resolveAttachment = resolveAttachment
        self.importFiles = importFiles
        self.openLink = openLink
        self.theme = theme
        self.attach = attach
        self.wantsTitleFocus = wantsTitleFocus
        self.titleTookFocus = titleTookFocus
        _isEditing = isEditing
        self.handle = handle
    }

    @MainActor public final class Coordinator {
        var noteID: AnyHashable?
        var themeSet = false
        var onText: (String) -> Void = { _ in }
        var onTitle: (String) -> Void = { _ in }
        var onFocus: (Bool) -> Void = { _ in }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> PhoneEditorContainer {
        let container = PhoneEditorContainer()
        let view = container.editor
        view.showsHeader = true
        let coordinator = context.coordinator
        view.onTextChange = { coordinator.onText($0) }
        view.onTitleChange = { coordinator.onTitle($0) }
        view.onFocusChange = { focused in
            // never change SwiftUI state during its own update
            DispatchQueue.main.async { coordinator.onFocus(focused) }
        }
        return container
    }

    public func updateUIView(_ container: PhoneEditorContainer, context: Context) {
        let view = container.editor
        let c = context.coordinator
        c.onText = { text = $0 }
        c.onTitle = { title = $0 }
        c.onFocus = { focused in if isEditing != focused { isEditing = focused } }
        handle?.view = view
        // SwiftUI updates the editor on every change: setting the theme each time restyled the whole note per
        // keystroke. The theme is set once (it doesn't change while the editor shows).
        if !c.themeSet { c.themeSet = true; view.theme = theme }
        view.placeholder = placeholder
        view.titlePlaceholder = titlePlaceholder
        view.meta = meta
        view.isReadOnly = !isEditable
        view.openLink = openLink
        view.resolveAttachment = resolveAttachment
        view.importFiles = importFiles
        view.attach = attach
        if c.noteID != noteID {
            c.noteID = noteID
            view.load(text)
            view.title = title
            view.setContentOffset(.zero, animated: false)
        } else if !view.textStorage.string.utf8.elementsEqual(text.utf8) {
            view.load(text)   // changed outside the editor
        }
        if view.titleView.markedTextRange == nil { view.title = title }
        if view.mode != mode { view.mode = mode }
        if wantsTitleFocus, isEditable, view.pendingTitleFocus == nil {
            let done = titleTookFocus
            DispatchQueue.main.async { view.requestTitleFocus(then: done) }
        }
    }
}
#endif
