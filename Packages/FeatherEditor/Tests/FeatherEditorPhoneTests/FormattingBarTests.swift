// Tests of the UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorTestSupport
import Testing
import UIKit
@testable import FeatherEditorCore
@testable import FeatherEditorPhone

/// The formatting bar above the keyboard (component inventory "Editor formatting bar (mobile)").
@MainActor @Suite(.serialized) struct FormattingBarTests {
    func bar(_ editor: PhoneEditorView) throws -> FormattingBar {
        let bar = try #require(editor.inputAccessoryView as? FormattingBar)
        bar.frame = CGRect(x: 0, y: 0, width: 390, height: 52)
        bar.layoutIfNeeded()
        return bar
    }

    func expected(_ text: String, _ sel: NSRange, _ edit: EditorCommands.Edit?) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func barButtonsRunTheirCommands() throws {
        let text = "one two\n\nthree"
        let sel = NSRange(location: 4, length: 3)   // "two"
        let doc = MarkdownParser.parse(text)
        let cases: [(String, EditorCommands.Edit?)] = [
            ("Bold", EditorCommands.toggleInline(.bold, text: text, document: doc, selection: sel)),
            ("Italic", EditorCommands.toggleInline(.italic, text: text, document: doc, selection: sel)),
            ("Code", EditorCommands.toggleInline(.code, text: text, document: doc, selection: sel)),
            ("Checklist", EditorCommands.block(.todo, text: text, caret: sel.location, removing: nil)),
            ("Bulleted List", EditorCommands.block(.bulleted, text: text, caret: sel.location, removing: nil)),
            ("Link", EditorCommands.link(text: text, selection: sel)),
        ]
        for (label, edit) in cases {
            let editor = makeEditor(text)
            editor.selectedRange = sel
            let button = try #require(try bar(editor).button(labelled: label), "\(label)")
            button.sendActions(for: .primaryActionTriggered)
            #expect(editor.textStorage.string == expected(text, sel, edit), "\(label)")
            editor.undoManager?.undo()
            #expect(editor.textStorage.string == text, "\(label): one undo step")
        }
        for level in 0...3 {
            let editor = makeEditor("## " + text)
            editor.selectedRange = NSRange(location: 5, length: 0)
            try bar(editor).perform(.heading(level))
            let e = EditorCommands.heading(level, text: "## " + text, caret: 5)
            #expect(editor.textStorage.string == expected("## " + text, sel, e), "heading \(level)")
            editor.undoManager?.undo()
            #expect(editor.textStorage.string == "## " + text)
        }
    }

    @Test func checklistAndListTurnOffWhenOn() throws {
        let editor = makeEditor("- [ ] task")
        editor.selectedRange = NSRange(location: 8, length: 0)
        try bar(editor).button(labelled: "Checklist")?.sendActions(for: .primaryActionTriggered)
        #expect(editor.textStorage.string == "task")
        editor.load("- item")
        editor.selectedRange = NSRange(location: 4, length: 0)
        try bar(editor).button(labelled: "Bulleted List")?.sendActions(for: .primaryActionTriggered)
        #expect(editor.textStorage.string == "item")
    }

    @Test func activeFormatsTintButtons() throws {
        let editor = makeEditor("a **bold** b *it*")
        let bar = try bar(editor)
        editor.selectedRange = NSRange(location: 6, length: 0)
        #expect(bar.button(labelled: "Bold")?.isSelected == true)
        #expect(bar.button(labelled: "Italic")?.isSelected == false)
        editor.selectedRange = NSRange(location: 15, length: 0)
        #expect(bar.button(labelled: "Bold")?.isSelected == false)
        #expect(bar.button(labelled: "Italic")?.isSelected == true)
        editor.load("## Title")
        editor.selectedRange = NSRange(location: 5, length: 0)
        #expect(bar.button(labelled: "Heading")?.isSelected == true)
    }

    @Test func undoButtonUndoes() throws {
        let editor = makeEditor("")
        editor.insertText("abc")
        try bar(editor).button(labelled: "Undo")?.sendActions(for: .primaryActionTriggered)
        #expect(editor.textStorage.string == "")
    }

    @Test func hideKeyboardResigns() throws {
        let editor = makeEditor("text")
        #expect(editor.becomeFirstResponder())
        try bar(editor).button(labelled: "Hide Keyboard")?.sendActions(for: .primaryActionTriggered)
        #expect(!editor.isFirstResponder)
    }

    @Test func barTargetsAre44Points() throws {
        let editor = makeEditor("")
        let bar = try bar(editor)
        let labels = ["Heading", "Bold", "Italic", "Checklist", "Bulleted List", "Code", "Link", "Attach", "Undo", "Hide Keyboard"]
        for label in labels {
            let button = try #require(bar.button(labelled: label), "\(label)")
            #expect(button.frame.width >= 44 && button.frame.height >= 44, "\(label): \(button.frame.size)")
        }
        // the order on the board
        #expect(bar.buttons.map(\.accessibilityLabel) == labels)
    }

    /// On a wide keyboard (iPad) the buttons sit centred; on a narrow one they start at the leading edge and scroll.
    @Test func buttonsCentreWhenTheyFit() throws {
        let editor = makeEditor("text")
        let bar = try bar(editor)
        let bold = try #require(bar.button(labelled: "Heading"))
        #expect(bold.convert(bold.bounds, to: bar).minX < 20, "starts at the edge on iPhone")
        bar.frame = CGRect(x: 0, y: 0, width: 1194, height: 52)
        bar.layoutIfNeeded()
        let first = try #require(bar.button(labelled: "Heading")).convert(bold.bounds, to: bar)
        let last = try #require(bar.button(labelled: "Undo"))
        let lastFrame = last.convert(last.bounds, to: bar)
        let left = first.minX, right = 1194 - lastFrame.maxX
        #expect(left > 200, "centred, not at the edge: \(left)")
        #expect(abs(left - right) < 120, "about as far from both edges: \(left) vs \(right)")
    }

    @Test func keyCommandsRunTheEditorCommands() throws {
        let editor = makeEditor("one two")
        let commands = editor.keyCommands ?? []
        func command(_ input: String, _ flags: UIKeyModifierFlags) -> UIKeyCommand? {
            commands.first { $0.input == input && $0.modifierFlags == flags }
        }
        for (input, result) in [("b", "one **two**"), ("i", "one *two*"), ("k", "one [two](https://)")] {
            editor.load("one two")
            editor.selectedRange = NSRange(location: 4, length: 3)
            let c = try #require(command(input, .command), "⌘\(input)")
            editor.perform(c.action, with: c)
            #expect(editor.textStorage.string == result, "⌘\(input)")
        }
        editor.load("- a\n- b")
        editor.selectedRange = NSRange(location: 6, length: 0)
        let tab = try #require(command("\t", []))
        editor.perform(tab.action, with: tab)
        #expect(editor.textStorage.string == "- a\n  - b")
        let backtab = try #require(command("\t", .shift))
        editor.perform(backtab.action, with: backtab)
        #expect(editor.textStorage.string == "- a\n- b")
    }

    @Test func attachMenuReportsSource() throws {
        let editor = makeEditor("")
        var sources: [AttachSource] = []
        editor.attach = { sources.append($0) }
        let bar = try bar(editor)
        bar.perform(.attach(.photoLibrary))
        bar.perform(.attach(.files))
        #expect(sources == [.photoLibrary, .files])
        let menu = try #require(bar.button(labelled: "Attach")?.menu)
        #expect(menu.children.compactMap { ($0 as? UIAction)?.title } == ["Photo Library", "Choose File…"])
        let headings = try #require(bar.button(labelled: "Heading")?.menu)
        #expect(headings.children.compactMap { ($0 as? UIAction)?.title } == ["Heading 1", "Heading 2", "Heading 3", "Body"])
    }

    @Test func typingKeepsOneUndoStepWhileTheBarRefreshes() throws {
        let editor = makeEditor("")
        _ = try bar(editor)
        editor.insertText("a")
        editor.insertText("b")
        editor.insertText("c")
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "")
    }
}
#endif
