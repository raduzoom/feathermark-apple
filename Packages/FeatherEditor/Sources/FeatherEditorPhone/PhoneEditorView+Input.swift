// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit
import UniformTypeIdentifiers

// MARK: - Commands, keys, input methods, pasteboard

extension PhoneEditorView {
    /// Applies a command's edit as one undo step.
    public func apply(_ edit: EditorCommands.Edit) {
        guard !isReadOnly, NSMaxRange(edit.range) <= textStorage.length else { return }
        endComposition()
        closeUndoGroup()
        textStorage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributesAtCaret()))
        closeUndoGroup()
        super.selectedRange = edit.selection
        lastEditEnd = nil
        textDidChange()
        scrollRangeToVisible(selectedRange)
    }

    /// Applies an edit that arrives later (an attachment import) as one undo step, leaving the person's selection on
    /// the same text and the view where it is. A caret still waiting at the edit's place moves past the insertion.
    func applyKeepingSelection(_ edit: EditorCommands.Edit) {
        guard !isReadOnly, NSMaxRange(edit.range) <= textStorage.length else { return }
        endComposition()
        let sel = selectedRange
        let delta = (edit.replacement as NSString).length - edit.range.length
        func moved(_ p: Int) -> Int {
            if p < edit.range.location { return p }
            if p >= NSMaxRange(edit.range) { return p + delta }
            return edit.range.location + (edit.replacement as NSString).length
        }
        let waiting = sel.length == 0 && sel.location == edit.range.location
        closeUndoGroup()
        textStorage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributesAtCaret()))
        closeUndoGroup()
        if waiting {
            super.selectedRange = edit.selection
        } else {
            let start = moved(sel.location), end = moved(NSMaxRange(sel))
            super.selectedRange = NSRange(location: start, length: max(0, end - start))
        }
        lastEditEnd = nil
        textDidChange()
    }

    /// Ends an input method's composition (committing what it has) before the text changes underneath it.
    func endComposition() {
        if markedTextRange != nil { unmarkText() }
        isComposing = false
    }

    /// Runs a command at the selection; false when it doesn't apply (default handling then).
    func command(_ c: (String, MarkdownDocument, NSRange) -> EditorCommands.Edit?) -> Bool {
        guard mode == .live, !isReadOnly, markedTextRange == nil, let e = c(textStorage.string, styling.document, selectedRange) else { return false }
        if e.range.length == 0, e.replacement.isEmpty { selectedRange = e.selection } // a guard that changes nothing
        else { apply(e) }
        return true
    }

    public override func insertText(_ text: String) {
        guard !isReadOnly else { return }
        if blockMenuHandlesInsert(text) { return }
        if text == "\n" {
            closeUndoGroup()
            if !command(EditorCommands.returnKey) { super.insertText(text) }
            closeUndoGroup()
        } else if text == "\t" {
            if !command(EditorCommands.tab) { super.insertText(text) }
        } else {
            super.insertText(text)
        }
        if isComposing, markedTextRange == nil { finishComposing() }
        textDidChange()
        blockMenuDidInsert(text)
    }

    public override func deleteBackward() {
        guard !isReadOnly else { return }
        if !command({ EditorCommands.codeFenceGuard(text: $0, document: $1, selection: $2, key: .backspace) }),
           !command(EditorCommands.backspaceAtItemStart) { super.deleteBackward() }
        textDidChange()
    }

    public override func replace(_ range: UITextRange, withText text: String) {
        guard !isReadOnly else { return }
        super.replace(range, withText: text)
        textDidChange()
    }

    /// Tab: indents a list item under the one above (four spaces in code).
    @objc public func indent() {
        if !command(EditorCommands.tab), !isReadOnly { insertText("\t") }
    }

    /// Shift-Tab: outdents a list item.
    @objc public func outdent() {
        _ = command(EditorCommands.backtab)
    }

    // Input methods: no restyling while composing, or the composition breaks.
    public override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        isComposing = true
        super.setMarkedText(markedText, selectedRange: selectedRange)
        // an input method cancels a composition by setting empty marked text
        if markedText?.isEmpty != false { unmarkText() }
        updatePlaceholder()
    }

    public override func unmarkText() {
        super.unmarkText()
        finishComposing()
        textDidChange()
    }

    func finishComposing() {
        guard isComposing else { return }
        isComposing = false
        // the restyles that waited happened around the caret: restyle the blocks there
        let around = pendingRestyle.map { NSUnionRange($0, selectedRange) } ?? selectedRange
        pendingRestyle = nil
        let pending = styling.takePendingEdit()
        restyle(merging: [styling.blockRanges(touching: around) ?? around] + [pending].compactMap { $0 })
    }

    // Copy and cut carry the Markdown source only, as plain text.
    public override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        pasteboard.items = [[UTType.utf8PlainText.identifier: (textStorage.string as NSString).substring(with: selectedRange)]]
    }

    public override func cut(_ sender: Any?) {
        guard selectedRange.length > 0, !isReadOnly else { return }
        copy(sender)
        apply(EditorCommands.Edit(range: selectedRange, replacement: "", selection: NSRange(location: selectedRange.location, length: 0)))
    }

    /// Text pastes as plain text; an image alone (no text with it) becomes an attachment.
    public override func paste(_ sender: Any?) {
        guard !isReadOnly else { return }
        if let text = pasteboard.string {
            insertPlainText(text)
            return
        }
        if let url = pasteboard.url, !url.isFileURL {
            insertPlainText(url.absoluteString)
            return
        }
        if let file = pastedImageFile() {
            importAndInsert([file], anchor: makeAnchor(), cleaningUp: [file], asBlock: false)
            return
        }
        super.paste(sender)
    }

    func insertPlainText(_ text: String) {
        guard let range = selectedTextRange else { return }
        closeUndoGroup()
        replace(range, withText: text)
        closeUndoGroup()
    }

    /// Writes a pasted image to a temporary file, in its own format when the pasteboard has PNG, JPEG or HEIC data.
    func pastedImageFile() -> URL? {
        let kinds: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.heic, "heic")]
        var data: Data?
        var ext = "png"
        for (type, e) in kinds {
            if let d = pasteboard.data(forPasteboardType: type.identifier) { data = d; ext = e; break }
        }
        if data == nil { data = pasteboard.image?.pngData() }
        guard let data else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "Pasted Image \(UUID().uuidString.prefix(4)).\(ext)")
        guard (try? data.write(to: file)) != nil else { return nil }
        temporaryFiles.append(file)
        return file
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return !isReadOnly && (pasteboard.hasStrings || pasteboard.hasURLs || pasteboard.hasImages)
        }
        return super.canPerformAction(action, withSender: sender)
    }

    // A hardware keyboard on iPad: Tab and Shift-Tab indent and outdent list items.
    public override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indent)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdent)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        commands += formattingKeyCommands + blockMenuKeyCommands
        return (super.keyCommands ?? []) + commands
    }
}
#endif
