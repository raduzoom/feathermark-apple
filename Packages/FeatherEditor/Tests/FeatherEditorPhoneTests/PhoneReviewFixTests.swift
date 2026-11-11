// Tests of the UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorTestSupport
import Testing
import UIKit
@testable import FeatherEditorCore
@testable import FeatherEditorPhone

/// Regression tests from the Phase 13 fresh review. Each was RED on the reviewed tree and pins one fixed finding.
@MainActor @Suite(.serialized) struct PhoneReviewFixTests {
    func madeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "FNFix-\(UUID().uuidString).png")
        try Data(contentsOf: makePNG(width: 4, height: 4)).write(to: url)
        return url
    }

    /// An import that lands while the person types elsewhere leaves their caret where it is.
    @Test func importLandingKeepsTheCaretWhereThePersonTypes() async throws {
        let editor = makeEditor("abc\n\nmore")
        editor.selectedRange = NSRange(location: 3, length: 0)
        editor.importFiles = { _ in
            try? await Task.sleep(for: .milliseconds(200))
            return ["[x.pdf](feather://attachment/01X)"]
        }
        editor.requestAttachment(.files)
        editor.attachPicked([try madeFile()], cleaningUp: [])
        editor.selectedRange = NSRange(location: 9, length: 0)
        editor.insertText("z")
        #expect(await waitFor({ editor.textStorage.string.contains("01X") }, timeout: 5))
        let text = editor.textStorage.string as NSString
        #expect(editor.selectedRange == NSRange(location: text.range(of: "morez").location + 5, length: 0), "caret stays after the typed z")
    }

    /// A pick that arrives after another note was opened goes nowhere.
    @Test func pickAfterNoteSwitchIsDropped() async throws {
        let editor = makeEditor("first")
        var imported = false
        editor.importFiles = { _ in imported = true; return ["[x](feather://attachment/01X)"] }
        editor.requestAttachment(.photoLibrary)
        editor.load("second")
        let file = try madeFile()
        editor.attachPicked([file], cleaningUp: [file])
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!imported)
        #expect(editor.textStorage.string == "second")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// Undo during a composition ends it first, instead of editing under the input method.
    @Test func undoDuringCompositionEndsItFirst() {
        let editor = makeEditor("")
        editor.insertText("abc")
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
        editor.undoManager?.undo()
        #expect(editor.markedTextRange == nil)
        #expect(!editor.isComposing)
        #expect(editor.textStorage.string == "abc" || editor.textStorage.string == "")
    }

    /// Opening another note mid-composition ends it, and the new note is styled.
    @Test func loadDuringCompositionStylesTheNewNote() {
        let editor = makeEditor("intro")
        editor.selectedRange = NSRange(location: 5, length: 0)
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
        editor.load("a **b** c")
        #expect(!editor.isComposing)
        #expect(editor.markedTextRange == nil)
        #expect(editor.textStorage.string == "a **b** c")
        #expect(isHidden(editor, 2), "the new note is styled: its markers are hidden")
    }

    /// Done hides the keyboard when the title has it.
    @Test func endEditingReachesTheTitle() {
        let window = hostWindow()
        defer { window.isHidden = true }
        let container = PhoneEditorContainer()
        container.frame = window.bounds
        window.rootViewController!.view.addSubview(container)
        container.editor.showsHeader = true
        container.layoutIfNeeded()
        #expect(container.editor.focusTitle())
        let handle = PhoneEditorHandle()
        handle.view = container.editor
        handle.endEditing()
        #expect(!container.editor.titleView.isFirstResponder)
    }

    /// Tab types a tab in Markdown mode (a hardware keyboard's Tab is a key command there too).
    @Test func tabTypesATabInMarkdownMode() throws {
        let editor = makeEditor("- a\n- b")
        editor.mode = .raw
        editor.selectedRange = NSRange(location: 7, length: 0)
        let tab = try #require((editor.keyCommands ?? []).first { $0.input == "\t" && $0.modifierFlags == [] })
        editor.perform(tab.action, with: tab)
        #expect(editor.textStorage.string == "- a\n- b\t")
    }
}
#endif
