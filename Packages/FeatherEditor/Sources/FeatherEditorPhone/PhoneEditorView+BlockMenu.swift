// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit

// MARK: - The "/" block menu (design spec "Notes" › Block menu; the Mac's trigger rules)

extension PhoneEditorView {
    public var isBlockMenuOpen: Bool { blockTrigger != nil || isAskingSource }

    /// The "/query" text a pick removes: the "/" and the query as typed, if the text there still is that.
    var slashTriggerRange: NSRange? {
        guard let loc = blockTrigger else { return nil }
        let typed = "/" + blockMenuState.query
        let r = NSRange(location: loc, length: (typed as NSString).length)
        guard NSMaxRange(r) <= textStorage.length, (textStorage.string as NSString).substring(with: r) == typed else { return nil }
        return r
    }

    func openBlockMenu(at slash: Int) {
        blockTrigger = slash
        blockMenuState = BlockMenuState(hiding: [.scan])
        slashTextLength = textStorage.length
        let menu = blockMenu ?? PhoneBlockMenu(editor: self)
        blockMenu = menu
        menu.show(blockMenuState)
        inputAccessoryView = menu
        reloadInputViews()
    }

    func closeBlockMenu() {
        guard isBlockMenuOpen || inputAccessoryView !== formattingBar else { return }
        blockTrigger = nil
        isAskingSource = false
        inputAccessoryView = formattingBar
        reloadInputViews()
    }

    /// While the menu is open, Return picks the selected row.
    func blockMenuHandlesInsert(_ text: String) -> Bool {
        guard isBlockMenuOpen, text == "\n" else { return false }
        if isAskingSource { closeBlockMenu(); return false }
        pickSelectedBlock()
        return true
    }

    /// Called after text is inserted: a "/" where a line's text begins opens the menu.
    func blockMenuDidInsert(_ inserted: String) {
        guard inserted == "/", blockTrigger == nil, mode == .live, !isReadOnly, markedTextRange == nil else { return }
        let slashAt = selectedRange.location - 1
        let s = textStorage.string as NSString
        guard slashAt >= 0, slashAt < s.length, s.character(at: slashAt) == 0x2F,
              EditorCommands.slashOpensMenu(text: textStorage.string, document: styling.document, slashAt: slashAt) else { return }
        openBlockMenu(at: slashAt)
    }

    /// Called after every text change: the query is the text after the "/"; the menu closes, leaving the text as
    /// typed, when the "/" is gone or nothing matches.
    func blockMenuDidChangeText() {
        guard let loc = blockTrigger, !isComposing, markedTextRange == nil else { return }
        let s = textStorage.string as NSString
        let caret = selectedRange.location
        guard loc < s.length, s.character(at: loc) == 0x2F, caret > loc,
              caret <= NSMaxRange(EditorCommands.line(s, at: loc).range) else { closeBlockMenu(); return }
        let query = s.substring(with: NSRange(location: loc + 1, length: caret - loc - 1))
        slashTextLength = s.length
        if query == blockMenuState.query { return }
        guard blockMenuState.setQuery(query) else { closeBlockMenu(); return }
        blockMenu?.show(blockMenuState)
    }

    /// Called after the selection changes: the menu closes when the caret leaves the "/" line's tail.
    func blockMenuDidChangeSelection() {
        guard let loc = blockTrigger else {
            if isAskingSource { closeBlockMenu() }
            return
        }
        let s = textStorage.string as NSString
        let sel = selectedRange
        guard sel.length == 0, loc < s.length, sel.location > loc,
              sel.location <= NSMaxRange(EditorCommands.line(s, at: loc).range) else { closeBlockMenu(); return }
        // a caret move (the text didn't change) away from the query's end: a pick would cut the person's text
        if s.length == slashTextLength, sel.location != loc + 1 + (blockMenuState.query as NSString).length { closeBlockMenu() }
    }

    /// Inserts a block choice at the caret: one edit for text blocks, code and divider (the "/query" goes in the
    /// same undo step). Image or file asks where from, in the menu.
    func pickBlock(_ choice: BlockChoice) {
        let trigger = slashTriggerRange
        let caret = trigger.map { NSMaxRange($0) } ?? selectedRange.location
        guard !isReadOnly, blockTrigger == nil || trigger != nil else { closeBlockMenu(); return }
        if let e = EditorCommands.block(choice, text: textStorage.string, caret: caret, removing: trigger) {
            closeBlockMenu()
            apply(e)
            return
        }
        guard choice == .imageOrFile else { closeBlockMenu(); return }
        // the trigger goes now; the attachment lands later, as its own undo step
        let (removal, location) = EditorCommands.mediaInsertionPoint(text: textStorage.string, caret: caret, removing: trigger)
        blockTrigger = nil
        if let removal { apply(removal) }
        super.selectedRange = NSRange(location: location, length: 0)
        selectionMaybeChanged()
        pendingAttachment = (makeAnchor(at: NSRange(location: location, length: 0)), true)
        isAskingSource = true
        blockMenu?.showSources()
        inputAccessoryView = blockMenu
        reloadInputViews()
    }

    /// The source for a block-menu image or file.
    func pickSource(_ source: AttachSource) {
        closeBlockMenu()
        attach(source)
    }

    func pickSelectedBlock() {
        if let c = blockMenuState.selection { pickBlock(c) } else { closeBlockMenu() }
    }

    @objc func blockMenuUp() { blockMenuState.move(-1); blockMenu?.show(blockMenuState) }
    @objc func blockMenuDown() { blockMenuState.move(1); blockMenu?.show(blockMenuState) }
    @objc func blockMenuReturn() { pickSelectedBlock() }
    @objc func blockMenuEscape() { closeBlockMenu() }

    /// A hardware keyboard while the menu is open: ↑ ↓ move, Return picks, Esc closes.
    var blockMenuKeyCommands: [UIKeyCommand] {
        guard isBlockMenuOpen else { return [] }
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(blockMenuUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(blockMenuDown)),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(blockMenuReturn)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(blockMenuEscape)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }
}
#endif
