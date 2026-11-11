// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit
import UniformTypeIdentifiers

// MARK: - Taps: checkboxes, the code block's Copy button, links

extension PhoneEditorView: UIGestureRecognizerDelegate {
    enum TapTarget: Equatable {
        case checkbox(Int)
        case copyCode(Int)
        case link(String)
    }

    /// The smallest target a finger gets (44 pt).
    static let minimumTarget: CGFloat = 44

    /// What a tap at `point` (view coordinates) would act on; nil leaves it to the text view (caret placement).
    func tapTarget(at point: CGPoint) -> TapTarget? {
        guard let tlm = textLayoutManager else { return nil }
        let p = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        if let frag = tlm.textLayoutFragment(for: p) as? DecoratedLayoutFragment,
           let start = Optional(tlm.offset(from: tlm.documentRange.location, to: frag.rangeInElement.location)) {
            let local = CGPoint(x: p.x - frag.layoutFragmentFrame.minX, y: p.y - frag.layoutFragmentFrame.minY)
            if !isReadOnly, mode == .live, let box = frag.checkboxRect, Self.enlarged(box).contains(local) {
                return .checkbox(start)
            }
            if frag.showsCopyButton, let r = frag.copyButtonRect, Self.enlarged(r).contains(local) {
                return .copyCode(start)
            }
        }
        // a link opens on a tap only while the keyboard is down; with it up a tap places the caret
        if !isFirstResponder, mode == .live, let position = closestPosition(to: point) {
            let i = offset(from: beginningOfDocument, to: position)
            if let url = link(at: i) ?? link(at: i - 1) { return .link(url) }
        }
        return nil
    }

    static func enlarged(_ r: CGRect) -> CGRect {
        r.insetBy(dx: min(0, (r.width - minimumTarget) / 2), dy: min(0, (r.height - minimumTarget) / 2))
    }

    /// The link URL of the character at `i`, if any.
    public func link(at i: Int) -> String? {
        guard i >= 0, i < textStorage.length else { return nil }
        return textStorage.attribute(.featherLink, at: i, effectiveRange: nil) as? String
    }

    /// Acts on a tap at `point`; false when it's left to the text view.
    @discardableResult
    public func handleTap(at point: CGPoint) -> Bool {
        guard let target = tapTarget(at: point) else { return false }
        switch target {
        case .checkbox(let location): toggleCheckbox(at: location)
        case .copyCode(let location): copyCodeBlock(containing: location)
        case .link(let url): openLink(url)
        }
        return true
    }

    @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        handleTap(at: recognizer.location(in: self))
    }

    public override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === tapRecognizer else { return super.gestureRecognizerShouldBegin(recognizer) }
        return tapTarget(at: recognizer.location(in: self)) != nil
    }

    /// The text view's own single taps wait for this one to fail, so a checkbox tap never also moves the caret.
    public func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        recognizer === tapRecognizer && other.view === self && (other as? UITapGestureRecognizer)?.numberOfTapsRequired == 1
    }

    /// Toggles the checkbox of the list item containing `location`, as one undo step, leaving the caret where it was.
    public func toggleCheckbox(at location: Int) {
        guard !isReadOnly, let e = EditorCommands.toggleCheckbox(text: textStorage.string, document: styling.document, at: location) else { return }
        let keep = selectedRange
        apply(e)
        super.selectedRange = keep
        selectionMaybeChanged()
    }

    func copyCodeBlock(containing location: Int) {
        for b in styling.document.blocks where location >= b.range.location && location <= NSMaxRange(b.range) {
            if case .codeBlock(_, let content) = b.kind {
                // the code alone: no fences, no line break after the last line
                var code = (textStorage.string as NSString).substring(with: content)
                if code.hasSuffix("\r\n") { code.removeLast() } else if code.hasSuffix("\n") || code.hasSuffix("\r") { code.removeLast() }
                pasteboard.items = [[UTType.utf8PlainText.identifier: code]]
                return
            }
        }
    }

    /// The Copy button shows on the code block the caret is in (iOS has no hover).
    func updateCopyButton() {
        let caret = selectedRange.location
        // the button sits on the block's first content line, like the Mac's
        let block = styling.document.blocks.lazy.compactMap { b -> NSRange? in
            if case .codeBlock(_, let content) = b.kind, caret >= b.range.location, caret <= NSMaxRange(b.range) {
                return NSRange(location: content.location, length: NSMaxRange(b.range) - content.location)
            }
            return nil
        }.first
        guard block != copyBlock else { return }
        let old = copyBlock
        copyBlock = block
        // new fragments pick the flag up from the layout delegate
        for r in [old, block].compactMap({ $0 }) { invalidateFragments(in: r) }
    }

    func invalidateFragments(in range: NSRange) {
        guard let tlm = textLayoutManager, NSMaxRange(range) <= textStorage.length,
              let start = tlm.location(tlm.documentRange.location, offsetBy: range.location),
              let end = tlm.location(start, offsetBy: range.length),
              let r = NSTextRange(location: start, end: end) else { return }
        tlm.invalidateLayout(for: r)
        tlm.textViewportLayoutController.layoutViewport()
    }

    /// "Open Link" in the edit menu when the selection is on a link.
    public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard mode == .live, let url = link(at: range.location) ?? link(at: range.location - 1) else { return nil }
        let open = UIAction(title: "Open Link", image: UIImage(systemName: "safari")) { [weak self] _ in self?.openLink(url) }
        return UIMenu(children: [open] + suggestedActions)
    }
}
#endif
