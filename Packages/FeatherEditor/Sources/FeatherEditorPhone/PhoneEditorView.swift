// The UIKit editor view: iOS only (the Mac's is FeatherEditor's EditorTextView).
#if os(iOS)
import FeatherEditorCore
import UIKit

/// The live-preview Markdown editor for iPhone and iPad. Its text storage always holds the note's exact Markdown;
/// everything visual is attributes (`MarkdownStyler`) and layout fragments (`DecoratedLayoutFragment`). A
/// hand-built TextKit 2 stack: never touch `layoutManager` (it would switch the view to TextKit 1 for good).
@MainActor
public final class PhoneEditorView: UITextView, @preconcurrency NSTextStorageDelegate, UITextViewDelegate {
    public var theme: EditorTheme = .standard { didSet { restyleAll() } }
    public var mode: EditorMode = .live {
        didSet { if oldValue != mode { modeDidChange() } }
    }
    /// A note in the Trash: shown, never changed.
    public var isReadOnly = false {
        didSet {
            isEditable = !isReadOnly
            titleView.isEditable = !isReadOnly
            if isReadOnly { _ = resignFirstResponder(); _ = titleView.resignFirstResponder() }
        }
    }
    /// Shows the meta line and title above the body (they scroll with the note).
    public var showsHeader = false { didSet { updateHeaderVisibility() } }
    /// The title's point size; nil uses the theme's first heading. iPad shows a larger title (34 pt in portrait,
    /// 38 pt in landscape, board tablet-main-ipados-landscape-light).
    public var titleSize: CGFloat? {
        didSet { if oldValue != titleSize { applyTitleFont() } }
    }
    /// Every change to the title.
    public var onTitleChange: (String) -> Void = { _ in }
    /// The body or the title took or lost focus.
    public var onFocusChange: (Bool) -> Void = { _ in }
    public let titleView = PhoneTitleView()
    /// The meta line's and title's frames in the body's content coordinates.
    var headerFrames = (meta: CGRect.zero, title: CGRect.zero)
    /// A title focus asked for before the editor had a window (a new note being pushed).
    var pendingTitleFocus: (() -> Void)?
    public let metaLabel = UILabel()
    /// Shown while the note body is empty.
    public var placeholder = "" { didSet { placeholderLabel.text = placeholder } }
    /// Every change to the text, with the whole new text (the model saves it).
    public var onTextChange: (String) -> Void = { _ in }
    /// Turns a `feather://attachment/…` URL into the file to draw or open.
    public var resolveAttachment: (String) -> URL? = { _ in nil }
    /// Imports pasted or picked files; returns one Markdown snippet per file.
    public var importFiles: ([URL]) async -> [String] = { _ in [] }
    /// Opens a link ("Open Link" in the edit menu, or a tap while the keyboard is down).
    public var openLink: (String) -> Void = { url in if let u = URL(string: url) { UIApplication.shared.open(u) } }
    /// Called when the formats at the caret change (the formatting bar's selected buttons).
    public var onActiveFormatsChange: (ActiveFormats) -> Void = { _ in }
    /// The pasteboard copy, cut and paste use (tests give their own).
    public var pasteboard: UIPasteboard = .general
    /// Asks for an attachment from Photos or Files (the formatting bar's Attach, the "/" menu's Image or file).
    public var attach: (AttachSource) -> Void = { _ in }
    /// The bar above the keyboard.
    public private(set) lazy var formattingBar = FormattingBar(editor: self) { [weak self] in self?.requestAttachment($0) }

    public let imageCache = ImageCache()
    static let placeholderImageHeight: CGFloat = 96

    let styling = EditorStyling(text: "")
    let layoutDelegate = PhoneLayoutDelegate()
    let contentStorage: NSTextContentStorage
    let placeholderLabel = UILabel()

    /// Characters restyled so far; tests use it to check styling stays local.
    public internal(set) var restyledCharacters = 0
    public var isFullyStyled: Bool { styling.isFullyStyled }
    /// The note's parse, kept current edit by edit.
    public var document: MarkdownDocument { styling.document }
    /// The formats at the caret.
    public private(set) var activeFormats = ActiveFormats()
    /// Bumped by every `load`, so work that finishes later can tell the note changed.
    public private(set) var loadGeneration = 0
    /// While an input method composes (marked text), restyling waits, or the composition breaks.
    var isComposing = false
    var pendingRestyle: NSRange?
    var isLoading = false
    var isRestyling = false
    private var chunkScheduled = false
    private var editFlushScheduled = false
    var changeUnreported = false
    private var changeReportScheduled = false
    /// The selection the editor last handled, to notice changes made behind its setters.
    var lastSelection = NSRange(location: 0, length: 0)
    var isAdjustingSelection = false
    /// The code block whose Copy button shows (the caret is in it), from its first content line to its end.
    var copyBlock: NSRange?

    // Undo: one history per note, grouped by Return and by a 1 s pause (as on the Mac).
    var noteUndo = NoteUndoManager()
    /// The text as of the last edit, so an undo step can hold what an edit replaced.
    var shadow = NSMutableString()
    /// Whether a typing undo step is open (UIKit may reset the manager behind the editor's back, so it is asked).
    var undoGroupOpen: Bool { noteUndo.groupingLevel > 0 && !noteUndo.isUndoing && !noteUndo.isRedoing }
    var idleUndoBreak: Timer?
    /// Where the last edit ended: a caret anywhere else starts a new undo step.
    var lastEditEnd: Int?

    // Attachments
    /// Ranges waiting for an async insertion (an attachment import), moved by every edit.
    var anchors: [Int: NSRange] = [:]
    var nextAnchorID = 0
    /// Pasted-image files whose import hasn't finished yet.
    var temporaryFiles: [URL] = []

    /// The attachment the person is picking (from the bar or the block menu): where it goes, and whether as a block.
    var pendingAttachment: (anchor: Anchor, asBlock: Bool)?

    // The "/" block menu
    /// Where the "/" that opened the menu is.
    var blockTrigger: Int?
    /// The menu is showing "Image or file"'s sources.
    var isAskingSource = false
    public internal(set) var blockMenuState = BlockMenuState(hiding: [.scan])
    var blockMenu: PhoneBlockMenu?
    /// The text's length when the "/" query was last read: a selection change at the same length is a caret move.
    var slashTextLength = 0

    // Taps
    lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))

    init() {
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        layoutManager.delegate = layoutDelegate
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit {
        idleUndoBreak?.invalidate()
        for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
    }

    public static func make() -> PhoneEditorView {
        let v = PhoneEditorView()
        v.applyNoSubstitutions()
        v.backgroundColor = .clear
        v.alwaysBounceVertical = true
        v.keyboardDismissMode = .interactive
        v.textContainer.widthTracksTextView = true
        v.textStorage.delegate = v
        v.delegate = v
        v.layoutDelegate.editor = v
        v.noteUndo.editor = v
        v.accessibilityIdentifier = "note-body"
        v.accessibilityLabel = "Note body"
        v.placeholderLabel.textColor = v.theme.textPlaceholder
        v.placeholderLabel.font = v.theme.body
        v.placeholderLabel.isAccessibilityElement = false
        v.addSubview(v.placeholderLabel)
        v.tapRecognizer.delegate = v
        v.addGestureRecognizer(v.tapRecognizer)
        v.typingAttributes = v.typingAttributesAtCaret()
        v.inputAccessoryView = v.formattingBar
        v.titleView.inputAccessoryView = nil
        v.setUpHeader()
        v.attachHeader()
        return v
    }

    /// Turns off every automatic change iOS can make to typed text: what the person types is what's stored.
    func applyNoSubstitutions() {
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        dataDetectorTypes = []
        allowsEditingTextAttributes = false
        if #available(iOS 18, *) { writingToolsBehavior = .none }
    }

    /// Shows `text` as a fresh note: its own undo history, styled from the top.
    public func load(_ text: String) {
        // end a composition without reporting it: the change callback already belongs to the new note
        isLoading = true
        endComposition()
        isLoading = false
        pendingRestyle = nil
        closeBlockMenu()
        closeUndoGroup()
        noteUndo = NoteUndoManager()
        noteUndo.editor = self
        loadGeneration += 1
        pendingTitleFocus = nil
        anchors.removeAll()
        pendingAttachment = nil
        lastEditEnd = nil
        isLoading = true
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: typingAttributesAtCaret()))
        shadow = NSMutableString(string: text)
        super.selectedRange = NSRange(location: 0, length: 0)
        lastSelection = NSRange(location: 0, length: 0)
        isLoading = false
        changeUnreported = false
        copyBlock = nil
        restyle(merging: styling.load(text: text, caret: 0))
        scheduleChunk()
        updatePlaceholder()
        updateActiveFormats()
    }

    public override var undoManager: UndoManager? { noteUndo }

    public override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { onFocusChange(true) }
        return took
    }

    public override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        if gave { onFocusChange(titleView.isFirstResponder) }
        return gave
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // after the push settles
        if pendingTitleFocus != nil { DispatchQueue.main.async { [weak self] in self?.retryTitleFocus() } }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if pendingTitleFocus != nil, window != nil { DispatchQueue.main.async { [weak self] in self?.retryTitleFocus() } }
        // The 560 pt reading measure, centred, with at least 16 pt each side.
        let width = bounds.width
        let measure = max(1, min(theme.measure, width - 32))
        let side = max(16, ((width - measure) / 2).rounded(.down))
        let top = layoutHeader(x: side, width: measure)
        let inset = UIEdgeInsets(top: top, left: side, bottom: 32, right: side)
        if textContainerInset != inset { textContainerInset = inset }
        let pad = textContainer.lineFragmentPadding
        placeholderLabel.frame = CGRect(x: side + pad, y: inset.top, width: max(1, measure - 2 * pad), height: theme.bodyLineHeight)
    }

    var measure: CGFloat { max(1, min(theme.measure, bounds.width - 32)) }

    func updatePlaceholder() {
        placeholderLabel.isHidden = textStorage.length > 0 || markedTextRange != nil || placeholder.isEmpty
    }

    // MARK: Styling

    func typingAttributesAtCaret() -> [NSAttributedString.Key: Any] {
        [.font: mode == .raw ? theme.monoRaw : theme.body, .foregroundColor: theme.textBody]
    }

    /// Restyles the whole note: the window around the caret now, the rest in background chunks.
    func restyleAll() {
        guard !isLoading else { return }
        let caret = selectedRange.location
        restyle(merging: styling.load(text: textStorage.string, caret: caret))
        scheduleChunk()
    }

    private func modeDidChange() {
        closeBlockMenu()
        accessibilityLabel = mode == .raw ? "Note body, Markdown" : "Note body"
        placeholderLabel.font = mode == .raw ? theme.monoRaw : theme.body
        restyleAll()
    }

    func scheduleChunk() {
        guard !styling.isFullyStyled, !chunkScheduled else { return }
        chunkScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            chunkScheduled = false
            if isComposing { scheduleChunkLater(); return }
            guard let chunk = styling.nextChunk() else { return }
            restyle(chunk)
            scheduleChunk()
        }
    }

    private func scheduleChunkLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.scheduleChunk() }
    }

    func restyle(_ range: NSRange) {
        guard !isRestyling, range.length > 0 || textStorage.length == 0 else { return }
        styling.styled(range)
        if isComposing {
            pendingRestyle = pendingRestyle.map { NSUnionRange($0, range) } ?? range
            return
        }
        isRestyling = true
        defer { isRestyling = false }
        restyledCharacters += range.length
        let text = textStorage.string
        let runs = MarkdownStyler.runs(text: text, document: styling.document, selection: selectedRange, mode: mode,
                                       theme: theme, in: range, imageHeight: { [unowned self] in imageHeight(for: $0) })
        textStorage.beginEditing()
        for run in runs where NSMaxRange(run.range) <= textStorage.length {
            textStorage.setAttributes(run.attributes.nsAttributes, range: run.range)
        }
        textStorage.endEditing()
        typingAttributes = typingAttributesAtCaret()
    }

    func restyle(merging ranges: [NSRange]) {
        styling.merged(ranges).forEach(restyle)
    }

    /// Restyles the region of edits not yet restyled, if any.
    func flushPendingEdit() {
        if let p = styling.takePendingEdit() { restyle(p) }
    }

    // MARK: Edits

    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                            range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isLoading, !isRestyling else { return }
        let old = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let inserted = (textStorage.string as NSString).substring(with: editedRange)
        let replaced = NSMaxRange(old) <= shadow.length ? shadow.substring(with: old) : ""
        shadow.replaceCharacters(in: old, with: inserted)
        registerUndo(range: editedRange, replaced: replaced)
        for (id, a) in anchors {   // keep pending insertion points on the same text
            if a.location >= NSMaxRange(old) {
                anchors[id] = NSRange(location: a.location + delta, length: a.length)
            } else if NSMaxRange(a) > old.location || a.location >= old.location {
                anchors[id] = NSRange(location: NSMaxRange(editedRange), length: 0)   // the edit touched it: after the edit
            }
        }
        styling.edit(range: old, replacementLength: editedRange.length, newText: textStorage.string)
        lastEditEnd = NSMaxRange(editedRange)
        changeUnreported = true
        // Restyle once the caret has moved too (the input call returning, the selection change, or the next turn),
        // so a keystroke styles its block once rather than twice.
        if !editFlushScheduled {
            editFlushScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                editFlushScheduled = false
                textDidChange()
            }
        }
    }

    /// After any change to the text: restyle what changed, report it, refresh what depends on the caret.
    func textDidChange() {
        flushPendingEdit()
        reportChange()
        updatePlaceholder()
        selectionMaybeChanged()
        blockMenuDidChangeText()
        restartIdleUndoBreak()
    }

    func reportChange() {
        guard changeUnreported, !isLoading else { return }
        changeUnreported = false
        onTextChange(textStorage.string)
    }

    // MARK: Selection

    public override var selectedTextRange: UITextRange? {
        get { super.selectedTextRange }
        set {
            guard !isAdjustingSelection, !isRestyling, !isLoading, let newValue else { super.selectedTextRange = newValue; return }
            let proposed = NSRange(location: offset(from: beginningOfDocument, to: newValue.start),
                                   length: offset(from: newValue.start, to: newValue.end))
            let adjusted = adjustedSelection(proposed, from: selectedRange)
            isAdjustingSelection = true
            if adjusted == proposed { super.selectedTextRange = newValue } else { super.selectedRange = adjusted }
            isAdjustingSelection = false
            selectionMaybeChanged()
        }
    }

    public override var selectedRange: NSRange {
        get { super.selectedRange }
        set {
            guard !isAdjustingSelection, !isRestyling, !isLoading else { super.selectedRange = newValue; return }
            isAdjustingSelection = true
            super.selectedRange = adjustedSelection(newValue, from: super.selectedRange)
            isAdjustingSelection = false
            selectionMaybeChanged()
        }
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        selectionMaybeChanged()
    }

    /// Keeps the caret out of hidden syntax.
    func adjustedSelection(_ proposed: NSRange, from old: NSRange) -> NSRange {
        guard markedTextRange == nil else { return proposed }
        let storage = textStorage
        return EditorSelection.adjusted(proposed, from: old, hidden: { i in
            i >= 0 && i < storage.length && storage.attribute(.featherHidden, at: i, effectiveRange: nil) as? Bool == true
        }, length: storage.length)
    }

    /// Restyles the blocks the selection left and entered, if it moved since last time.
    func selectionMaybeChanged() {
        guard !isLoading, !isRestyling else { return }
        let new = selectedRange
        guard new != lastSelection else { return }
        let old = lastSelection
        lastSelection = new
        if new.length > 0 || new.location != lastEditEnd { closeUndoGroup() }
        restyle(merging: styling.selectionChanged(from: old, to: new))
        updateCopyButton()
        updateActiveFormats()
        blockMenuDidChangeSelection()
    }

    func updateActiveFormats() {
        let formats = EditorCommands.activeFormats(document: styling.document, text: textStorage.string, selection: selectedRange)
        guard formats != activeFormats else { return }
        activeFormats = formats
        formattingBar.update(formats)
        onActiveFormatsChange(formats)
    }

    // MARK: Undo

    /// Records an edit as an undo step: `range` in the new text, `replaced` the text it took the place of.
    func registerUndo(range: NSRange, replaced: String) {
        // grouping and registering both need registration enabled; it's off the rest of the time
        noteUndo.registering {
            if !noteUndo.isUndoing, !noteUndo.isRedoing, noteUndo.groupingLevel == 0 { noteUndo.beginUndoGrouping() }
            noteUndo.registerUndo(withTarget: self, selector: #selector(revert(_:)), object: UndoStep(range: range, text: replaced))
        }
    }

    @objc func revert(_ step: UndoStep) {
        guard NSMaxRange(step.range) <= textStorage.length else { return }
        textStorage.replaceCharacters(in: step.range, with: NSAttributedString(string: step.text, attributes: typingAttributesAtCaret()))
        let caret = NSRange(location: step.range.location + (step.text as NSString).length, length: 0)
        super.selectedRange = caret
        lastEditEnd = nil
        textDidChange()
    }

    /// Ends the current undo step: the next edit starts a new one.
    func closeUndoGroup() {
        idleUndoBreak?.invalidate()
        guard undoGroupOpen else { return }
        noteUndo.registering {
            while noteUndo.groupingLevel > 0 { noteUndo.endUndoGrouping() }
        }
    }

    func restartIdleUndoBreak() {
        idleUndoBreak?.invalidate()
        guard undoGroupOpen else { return }
        idleUndoBreak = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUndoGroup() }
        }
    }
}

/// One undo step: put `text` back in place of `range`.
final class UndoStep: NSObject {
    let range: NSRange
    let text: String
    init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// The note's undo history. Only the editor registers or groups (its registration stays disabled otherwise), so
/// UIKit's own text undo never adds a second step for the same edit.
final class NoteUndoManager: UndoManager {
    weak var editor: PhoneEditorView?
    private var isOwned = false

    override init() {
        super.init()
        groupsByEvent = false
        levelsOfUndo = 200
        disableUndoRegistration()
    }

    func owned(_ body: () -> Void) {
        let was = isOwned
        isOwned = true
        body()
        isOwned = was
    }

    /// Runs `body` as the editor, with registration on (grouping needs it too), then puts it back as it was.
    func registering(_ body: () -> Void) {
        owned {
            let wasOff = !isUndoRegistrationEnabled
            if wasOff { enableUndoRegistration() }
            body()
            if wasOff { disableUndoRegistration() }
        }
    }

    override func beginUndoGrouping() {
        if isOwned || isUndoing || isRedoing { super.beginUndoGrouping() }
    }

    override func endUndoGrouping() {
        if isOwned || isUndoing || isRedoing { super.endUndoGrouping() }
    }

    /// UIKit may call this on any undo manager it finds; only the editor (or a new note) clears the history.
    override func removeAllActions() {
        if isOwned { super.removeAllActions() }
    }

    // Undo and redo open their own group for the steps the revert registers, which needs registration on.
    override func undo() {
        MainActor.assumeIsolated { editor?.endComposition(); editor?.closeUndoGroup() }
        guard groupingLevel == 0, super.canUndo else { return }
        registering { super.undo() }
    }

    override func redo() {
        MainActor.assumeIsolated { editor?.endComposition(); editor?.closeUndoGroup() }
        guard groupingLevel == 0, super.canRedo else { return }
        registering { super.redo() }
    }

    /// An open typing step counts (the editor opens a group only to register a step). Asking never closes it:
    /// the iPad keyboard's undo button asks after every keystroke.
    override var canUndo: Bool { groupingLevel > 0 || super.canUndo }
}
#endif
