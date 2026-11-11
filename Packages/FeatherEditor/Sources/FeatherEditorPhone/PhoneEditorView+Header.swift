// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit

/// The note's title: serif display type, one paragraph (Return moves to the body; pasted line breaks become
/// spaces), every substitution off like the body.
@MainActor
public final class PhoneTitleView: UITextView, UITextViewDelegate {
    var onChange: (String) -> Void = { _ in }
    var onReturn: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }
    let placeholderLabel = UILabel()
    private var reported = ""

    init() {
        super.init(frame: .zero, textContainer: nil)
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        dataDetectorTypes = []
        if #available(iOS 18, *) { writingToolsBehavior = .none }
        returnKeyType = .next
        accessibilityIdentifier = "note-title"
        accessibilityLabel = "Title"
        delegate = self
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.numberOfLines = 0
        addSubview(placeholderLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var placeholder = "" { didSet { placeholderLabel.text = placeholder; updatePlaceholder() } }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty || markedTextRange != nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: placeholderLabel.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
    }

    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    public override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { onFocus(true) }
        return took
    }

    public override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        if gave { onFocus(false) }
        return gave
    }

    /// Return moves to the body; any other line break becomes a space.
    public override func insertText(_ text: String) {
        if text == "\n" || text == "\r" || text == "\r\n" {
            onReturn()
            return
        }
        super.insertText(Self.oneLine(text))
        changed()
    }

    public override func deleteBackward() {
        super.deleteBackward()
        changed()
    }

    public override func replace(_ range: UITextRange, withText text: String) {
        super.replace(range, withText: Self.oneLine(text))
        changed()
    }

    public override func paste(_ sender: Any?) {
        if let s = UIPasteboard.general.string { paste(text: s) } else { super.paste(sender) }
    }

    /// Pastes `text` as one line.
    func paste(text: String) {
        guard let range = selectedTextRange else { return }
        replace(range, withText: text)
    }

    public func textViewDidChange(_ textView: UITextView) { changed() }

    func changed() {
        if text.contains(where: \.isNewline) { text = Self.oneLine(text) }
        updatePlaceholder()
        guard text != reported else { return }
        reported = text
        onChange(text)
    }

    /// Sets the text without reporting it (a note loaded, a change from elsewhere).
    func show(_ title: String) {
        guard text != title else { return }
        text = title
        reported = title
        updatePlaceholder()
    }
}

// MARK: - The header: meta line and title, above the body

extension PhoneEditorView {
    /// The note's title (not reported back through `onTitleChange` when set here).
    public var title: String {
        get { titleView.text }
        set {
            guard titleView.text != newValue else { return }
            titleView.show(newValue)
            setNeedsLayout()
        }
    }

    /// The notebook and edited line above the title.
    public var meta: String {
        get { metaLabel.text ?? "" }
        set {
            guard metaLabel.text != newValue else { return }
            metaLabel.text = newValue
            setNeedsLayout()
        }
    }

    public var titlePlaceholder: String {
        get { titleView.placeholder }
        set { titleView.placeholder = newValue }
    }

    func setUpHeader() {
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = theme.textSecondary
        metaLabel.numberOfLines = 0
        titleView.font = theme.h1
        titleView.textColor = theme.textPrimary
        titleView.placeholderLabel.font = theme.h1
        titleView.placeholderLabel.textColor = theme.textPlaceholder
        titleView.onChange = { [weak self] title in
            guard let self else { return }
            setNeedsLayout()
            onTitleChange(title)
        }
        titleView.onReturn = { [weak self] in self?.focusBodyStart() }
        titleView.onFocus = { [weak self] focused in
            guard let self else { return }
            onFocusChange(focused || isFirstResponder)
        }
        updateHeaderVisibility()
    }

    func updateHeaderVisibility() {
        metaLabel.isHidden = !showsHeader
        titleView.isHidden = !showsHeader
        setNeedsLayout()
    }

    /// Puts the caret at the start of the body.
    func focusBodyStart() {
        _ = becomeFirstResponder()
        selectedRange = NSRange(location: 0, length: 0)
    }

    /// Focuses the title with the caret at its end (a new note). Returns false when it can't yet (not in a window).
    @discardableResult
    public func focusTitle() -> Bool {
        guard showsHeader, !isReadOnly, window != nil, titleView.becomeFirstResponder() else { return false }
        titleView.selectedRange = NSRange(location: (titleView.text as NSString).length, length: 0)
        return true
    }

    /// Focuses the title as soon as the editor is on screen (a new note is pushed before it has a window), then
    /// calls `done`.
    public func requestTitleFocus(then done: @escaping () -> Void) {
        if focusTitle() { done(); return }
        pendingTitleFocus = done
    }

    /// Runs a title focus that waited for a window.
    func retryTitleFocus() {
        guard let done = pendingTitleFocus, window != nil else { return }
        if focusTitle() {
            pendingTitleFocus = nil
            done()
        }
    }

    /// The header lives beside the body, in the editor's superview, not inside it: the body text view is one
    /// accessibility element, and a text view inside it would hide the title's focus (and list it twice). It follows
    /// the body's scroll offset, so it scrolls with the note.
    func attachHeader() {
        let host: UIView = superview ?? self
        for v in [metaLabel, titleView] as [UIView] where v.superview !== host {
            v.removeFromSuperview()
            if host === self { addSubview(v) } else { host.insertSubview(v, aboveSubview: self) }
        }
        host.clipsToBounds = host !== self || host.clipsToBounds
        positionHeader()
    }

    /// Places the meta line and title above the text, in content coordinates; returns where the body starts.
    func layoutHeader(x side: CGFloat, width measure: CGFloat) -> CGFloat {
        guard showsHeader else { return 8 }
        let pad = textContainer.lineFragmentPadding
        let x = side + pad, width = max(1, measure - 2 * pad)
        var y: CGFloat = 16
        if !meta.isEmpty {
            let h = metaLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            headerFrames.meta = CGRect(x: x, y: y, width: width, height: h)
            y = headerFrames.meta.maxY + 8
        } else {
            headerFrames.meta = CGRect(x: x, y: y, width: width, height: 0)
        }
        let h = max(theme.h1.lineHeight, titleView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        headerFrames.title = CGRect(x: x, y: y, width: width, height: h)
        positionHeader()
        return headerFrames.title.maxY + 16
    }

    /// Moves the header with the body's scroll.
    func positionHeader() {
        let inSelf = metaLabel.superview === self
        let dx = inSelf ? 0 : frame.minX - contentOffset.x
        let dy = inSelf ? 0 : frame.minY - contentOffset.y
        metaLabel.frame = headerFrames.meta.offsetBy(dx: dx, dy: dy)
        titleView.frame = headerFrames.title.offsetBy(dx: dx, dy: dy)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) { positionHeader() }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachHeader()
    }
}
#endif
