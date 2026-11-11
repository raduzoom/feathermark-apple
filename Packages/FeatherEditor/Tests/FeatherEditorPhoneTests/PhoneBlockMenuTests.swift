// Tests of the UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorTestSupport
import Testing
import UIKit
@testable import FeatherEditorCore
@testable import FeatherEditorPhone

/// The "/" block menu above the keyboard (ports of the Mac's BlockMenuViewTests that apply on iOS).
@MainActor @Suite(.serialized) struct PhoneBlockMenuTests {
    /// An editor with the caret at "|".
    func editor(_ marked: String) -> PhoneEditorView {
        let r = (marked as NSString).range(of: "|")
        let e = makeEditor((marked as NSString).replacingCharacters(in: r, with: ""))
        e.selectedRange = NSRange(location: r.location, length: 0)
        return e
    }

    func type(_ e: PhoneEditorView, _ s: String) { for c in s { e.insertText(String(c)) } }

    @Test func slashOpensOnlyAtLineStart() {
        let atStart = editor("intro\n|")
        type(atStart, "/")
        #expect(atStart.isBlockMenuOpen)
        #expect(atStart.inputAccessoryView is PhoneBlockMenu, "the menu takes the bar's place")

        let inList = editor("- |")
        type(inList, "/")
        #expect(inList.isBlockMenuOpen, "after a list marker the line's text begins")

        for marked in ["mid sen|", "```\ncode |\n```", "a|"] {
            let e = editor(marked)
            type(e, "/")
            #expect(!e.isBlockMenuOpen, "\(marked)")
            #expect(e.inputAccessoryView is FormattingBar)
        }
        let composing = editor("|")
        composing.setMarkedText("/", selectedRange: NSRange(location: 1, length: 0))
        #expect(!composing.isBlockMenuOpen, "a '/' still being composed")
        composing.unmarkText()
    }

    @Test func typingFiltersAndReturnPicks() throws {
        let e = editor("intro\n|")
        type(e, "/hea")
        #expect(e.isBlockMenuOpen)
        #expect(e.blockMenuState.items == [.heading1, .heading2, .heading3])
        e.insertText("\n")
        #expect(!e.isBlockMenuOpen)
        #expect(e.textStorage.string == "intro\n# ")
        e.undoManager?.undo()
        #expect(e.textStorage.string == "intro\n/hea", "the pick and its /query are one undo step")
    }

    @Test func tapPicksARow() throws {
        let e = editor("hello|")
        e.selectedRange = NSRange(location: 0, length: 0)
        e.load("")
        type(e, "/")
        let menu = try #require(e.blockMenu)
        let quote = try #require(menu.row(titled: "Quote"))
        quote.sendActions(for: .primaryActionTriggered)
        #expect(e.textStorage.string == "> ")
        #expect(!e.isBlockMenuOpen)
        #expect(e.inputAccessoryView is FormattingBar)
    }

    @Test func menuClosesWhenTheCaretLeavesOrANoteLoads() {
        let e = editor("intro\n|")
        type(e, "/")
        #expect(e.isBlockMenuOpen)
        e.selectedRange = NSRange(location: 0, length: 0)
        #expect(!e.isBlockMenuOpen, "caret left the line")
        #expect(e.textStorage.string == "intro\n/", "the text stays as typed")

        let f = editor("intro\n|")
        type(f, "/")
        f.load("other")
        #expect(!f.isBlockMenuOpen)

        let g = editor("|")
        type(g, "/zzz")
        #expect(!g.isBlockMenuOpen, "nothing matches")
        #expect(g.textStorage.string == "/zzz")

        let h = editor("|")
        type(h, "/")
        h.deleteBackward()
        #expect(!h.isBlockMenuOpen, "the / is gone")
    }

    @Test func arrowKeysMoveTheSelection() throws {
        let e = editor("|")
        type(e, "/")
        let commands = e.keyCommands ?? []
        let down = try #require(commands.first { $0.input == UIKeyCommand.inputDownArrow })
        let up = try #require(commands.first { $0.input == UIKeyCommand.inputUpArrow })
        let escape = try #require(commands.first { $0.input == UIKeyCommand.inputEscape })
        e.perform(down.action, with: down)
        e.perform(down.action, with: down)
        #expect(e.blockMenuState.selected == 2)
        e.perform(up.action, with: up)
        #expect(e.blockMenuState.selection == .heading2)
        let ret = try #require(commands.first { $0.input == "\r" })
        e.perform(ret.action, with: ret)
        #expect(e.textStorage.string == "## ")
        type(e, "x\n/")
        #expect(e.isBlockMenuOpen)
        e.perform(escape.action, with: escape)
        #expect(!e.isBlockMenuOpen)
        #expect(e.textStorage.string == "## x\n/")
        // closed: no arrow commands to swallow the caret keys
        #expect(!(e.keyCommands ?? []).contains { $0.input == UIKeyCommand.inputDownArrow })
    }

    @Test func scanIsHiddenOnIOS() {
        let e = editor("|")
        type(e, "/")
        #expect(!e.blockMenuState.items.contains(.scan))
        #expect(e.blockMenuState.items.contains(.imageOrFile))
        type(e, "sca")
        #expect(!e.isBlockMenuOpen, "no Scan row to match")
    }

    @Test func imageOrFileAsksForASource() async throws {
        let e = editor("hello\n|")
        var asked: [AttachSource] = []
        e.attach = { asked.append($0) }
        e.importFiles = { _ in ["![](feather://attachment/01I)"] }
        type(e, "/ima")
        let menu = try #require(e.blockMenu)
        try #require(menu.row(titled: "Image or file")).sendActions(for: .primaryActionTriggered)
        // the menu now asks where from
        #expect(e.isBlockMenuOpen)
        #expect(e.textStorage.string == "hello\n", "the /query is gone")
        try #require(menu.row(titled: "Photo Library")).sendActions(for: .primaryActionTriggered)
        #expect(asked == [.photoLibrary])
        #expect(!e.isBlockMenuOpen)
        e.attachPicked([URL(fileURLWithPath: "/tmp/x.png")], cleaningUp: [])
        #expect(await waitFor({ e.textStorage.string != "hello\n" }, timeout: 5))
        // a blank line above: right under text, an image would share its paragraph and show as a chip
        #expect(e.textStorage.string == "hello\n\n![](feather://attachment/01I)")
    }

    @Test func crlfIsKept() {
        let e = editor("one\r\n|")
        type(e, "/hea")
        e.insertText("\n")
        #expect(e.textStorage.string == "one\r\n# ")
        let f = editor("one\r\n|")
        type(f, "/code")
        f.insertText("\n")
        #expect(f.textStorage.string == "one\r\n```\r\n\r\n```")
    }
}
#endif
