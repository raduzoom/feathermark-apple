// Tests of the UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorTestSupport
import Testing
import UIKit
@testable import FeatherEditorCore
@testable import FeatherEditorPhone

/// A window to host editors, so they can lay out and take focus.
@MainActor func hostWindow() -> UIWindow {
    let window: UIWindow
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, false {
        window = UIWindow(windowScene: scene)
    } else {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
    }
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    return window
}

/// An editor showing `text` in a 390 × 800 window.
@MainActor func makeEditor(_ text: String, window: UIWindow? = nil) -> PhoneEditorView {
    let editor = PhoneEditorView.make()
    editor.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
    (window ?? hostWindow()).rootViewController!.view.addSubview(editor)
    editor.load(text)
    editor.layoutIfNeeded()
    return editor
}

@MainActor func isHidden(_ editor: PhoneEditorView, _ i: Int) -> Bool {
    editor.textStorage.attribute(.featherHidden, at: i, effectiveRange: nil) as? Bool == true
}

@MainActor func fragment(_ editor: PhoneEditorView, at offset: Int) -> DecoratedLayoutFragment? {
    guard let tlm = editor.textLayoutManager,
          let loc = tlm.location(tlm.documentRange.location, offsetBy: offset) else { return nil }
    tlm.ensureLayout(for: NSTextRange(location: loc))
    return tlm.textLayoutFragment(for: loc) as? DecoratedLayoutFragment
}

/// A point in the editor's coordinates at the centre of `rect`, given in `frag`'s own coordinates.
@MainActor func viewPoint(_ editor: PhoneEditorView, _ frag: NSTextLayoutFragment, _ rect: CGRect) -> CGPoint {
    let f = frag.layoutFragmentFrame
    return CGPoint(x: f.minX + rect.midX + editor.textContainerInset.left, y: f.minY + rect.midY + editor.textContainerInset.top)
}

@MainActor @Suite(.serialized) struct PhoneEditorViewTests {
    @Test func loadKeepsBytesAndClearsUndo() {
        let editor = makeEditor("")
        for (name, text) in Corpus.all() {
            editor.load(text)
            #expect(editor.textStorage.string.utf16.elementsEqual(text.utf16), "\(name)")
            #expect(editor.undoManager?.canUndo == false, "\(name)")
        }
    }

    @Test func phoneEditorHasNoSubstitutions() {
        let editor = makeEditor("hello")
        #expect(editor.autocorrectionType == .no)
        #expect(editor.spellCheckingType == .no)
        #expect(editor.smartQuotesType == .no)
        #expect(editor.smartDashesType == .no)
        #expect(editor.smartInsertDeleteType == .no)
        #expect(editor.inlinePredictionType == .no)
        #expect(editor.dataDetectorTypes == [])
        #expect(editor.textLayoutManager != nil)
        #expect(editor.accessibilityIdentifier == "note-body")
    }

    @Test func typedSmartQuotesStayVerbatim() {
        let editor = makeEditor("")
        editor.insertText("\"it's\" -- ok...")
        #expect(editor.textStorage.string == "\"it's\" -- ok...")
        #expect(editor.textLayoutManager != nil, "still TextKit 2")
    }

    @Test func caretNeverRestsInsideHiddenMarker() {
        let editor = makeEditor("a **bold** b")
        for p in 0...12 {
            editor.selectedRange = NSRange(location: 12, length: 0)
            editor.selectedRange = NSRange(location: p, length: 0)
            let c = editor.selectedRange.location
            #expect(!(c > 0 && c < 12 && isHidden(editor, c - 1) && isHidden(editor, c)), "caret \(p) rests at \(c)")
        }
    }

    @Test func revealFollowsTheCaret() {
        let editor = makeEditor("a **bold** b")
        editor.selectedRange = NSRange(location: 12, length: 0)
        #expect(isHidden(editor, 2) && isHidden(editor, 3))
        editor.selectedRange = NSRange(location: 6, length: 0)
        #expect(!isHidden(editor, 2) && !isHidden(editor, 3))
        editor.selectedRange = NSRange(location: 12, length: 0)
        #expect(isHidden(editor, 2))
    }

    @Test func returnContinuesAList() {
        let editor = makeEditor("- one")
        editor.selectedRange = NSRange(location: 5, length: 0)
        editor.insertText("\n")
        #expect(editor.textStorage.string == "- one\n- ")
        #expect(editor.selectedRange == NSRange(location: 8, length: 0))
        editor.insertText("\n")   // an empty item ends the list
        #expect(editor.textStorage.string == "- one\n")
    }

    @Test func backspaceAtItemStartOutdents() {
        let editor = makeEditor("- one")
        editor.selectedRange = NSRange(location: 2, length: 0)
        editor.deleteBackward()
        #expect(editor.textStorage.string == "one")
    }

    @Test func tabIndentsListItem() throws {
        let editor = makeEditor("- one\n- two")
        editor.selectedRange = NSRange(location: 9, length: 0)
        editor.indent()
        #expect(editor.textStorage.string == "- one\n  - two")
        editor.outdent()
        #expect(editor.textStorage.string == "- one\n- two")
        let inputs = (editor.keyCommands ?? []).map(\.input)
        #expect(inputs.contains("\t"))
    }

    @Test func checkboxTapToggles() throws {
        let editor = makeEditor("- [ ] milk\n\nafter")
        editor.selectedRange = NSRange(location: 15, length: 0)
        let frag = try #require(fragment(editor, at: 0))
        let box = try #require(frag.checkboxRect)
        // a finger lands a little off the 18 pt box: the 44 pt target still counts
        var point = viewPoint(editor, frag, box)
        point.x += 12
        #expect(editor.handleTap(at: point))
        #expect(editor.textStorage.string == "- [x] milk\n\nafter")
        #expect(editor.selectedRange == NSRange(location: 15, length: 0))
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "- [ ] milk\n\nafter")
        // a tap on the text itself is left to the text view
        let text = viewPoint(editor, frag, CGRect(x: box.maxX + 60, y: box.minY, width: 1, height: box.height))
        #expect(!editor.handleTap(at: text))
    }

    @Test func stylingRegistersNoUndo() {
        let editor = makeEditor("# Title\n\nSome **bold** text.")
        editor.selectedRange = NSRange(location: 3, length: 0)
        editor.selectedRange = NSRange(location: 20, length: 0)
        #expect(editor.undoManager?.canUndo == false)
    }

    @Test func undoGroupsByReturn() {
        let editor = makeEditor("")
        editor.insertText("a")
        editor.insertText("b")
        editor.insertText("\n")
        editor.insertText("c")
        editor.insertText("d")
        #expect(editor.textStorage.string == "ab\ncd")
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "ab\n")
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "ab")
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "")
        editor.undoManager?.redo()
        #expect(editor.textStorage.string == "ab")
    }

    @Test func eachNoteHasItsOwnUndo() {
        let editor = makeEditor("first")
        editor.selectedRange = NSRange(location: 5, length: 0)
        editor.insertText("!")
        editor.load("second")
        #expect(editor.undoManager?.canUndo == false)
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "second")
    }

    @Test func noRestyleDuringMarkedText() async {
        let editor = makeEditor("intro\n\n**b** text")
        editor.selectedRange = NSRange(location: 5, length: 0)
        await drainMainQueue()
        editor.restyledCharacters = 0
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
        await drainMainQueue()
        #expect(editor.restyledCharacters == 0)
        editor.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0))
        await drainMainQueue()
        #expect(editor.restyledCharacters == 0)
        editor.unmarkText()
        await drainMainQueue()
        #expect(editor.textStorage.string == "introかな\n\n**b** text")
        #expect(editor.restyledCharacters > 0 && editor.restyledCharacters <= 20, "restyled \(editor.restyledCharacters)")
    }

    @Test func cancelledCompositionKeepsText() {
        let editor = makeEditor("intro")
        editor.selectedRange = NSRange(location: 5, length: 0)
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0))
        editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        editor.unmarkText()
        #expect(editor.textStorage.string == "intro")
        #expect(!editor.isComposing)
    }

    @Test func everyChangeReachesTheModel() {
        let editor = makeEditor("")
        var reported: [String] = []
        editor.onTextChange = { reported.append($0) }
        editor.insertText("a")
        editor.insertText("b")
        editor.deleteBackward()
        editor.insertText("\n")
        #expect(reported == ["a", "ab", "a", "a\n"])
    }

    @Test func undoReachesTheModel() async {
        let editor = makeEditor("")
        var last = ""
        editor.onTextChange = { last = $0 }
        editor.insertText("abc")
        editor.undoManager?.undo()
        await drainMainQueue()
        #expect(last == "")
    }

    @Test func keystrokeRestyleIsProportional() async {
        let text = "First **bold** paragraph.\n\n" + String(repeating: "Middle paragraph with *some* words.\n\n", count: 400) + "Last **bold** paragraph."
        let editor = makeEditor(text)
        let at = (text as NSString).range(of: "Middle paragraph with").location + 3
        editor.selectedRange = NSRange(location: at, length: 0)
        await drainMainQueue()
        editor.restyledCharacters = 0
        editor.insertText("x")
        await drainMainQueue()
        #expect(editor.restyledCharacters <= 40, "restyled \(editor.restyledCharacters) for a 37-character paragraph")
        editor.restyledCharacters = 0
        editor.selectedRange = NSRange(location: 0, length: 0)
        #expect(editor.restyledCharacters < 200, "a caret jump restyled \(editor.restyledCharacters)")
    }

    @Test func openStylesAWindowThenTheRest() async {
        let text = "First **bold** paragraph.\n\n" + String(repeating: "Middle paragraph with *some* words.\n\n", count: 3_000) + "Last **bold** paragraph."
        let editor = PhoneEditorView.make()
        editor.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        editor.restyledCharacters = 0
        editor.load(text)
        #expect(editor.restyledCharacters <= 40_000)
        #expect(!editor.isFullyStyled)
        #expect(await waitFor({ editor.isFullyStyled }, timeout: 10))
        let last = (text as NSString).range(of: "bold", options: .backwards).location
        let f = editor.textStorage.attribute(.font, at: last, effectiveRange: nil) as! UIFont
        #expect(f.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test func copyGivesPlainMarkdown() {
        let editor = makeEditor("a **bold** b")
        let pasteboard = UIPasteboard.withUniqueName()
        editor.pasteboard = pasteboard
        editor.selectedRange = NSRange(location: 2, length: 8)
        editor.copy(nil)
        #expect(pasteboard.string == "**bold**")
        #expect(pasteboard.types == ["public.utf8-plain-text"] || pasteboard.types == ["public.plain-text"], "\(pasteboard.types)")
        UIPasteboard.remove(withName: pasteboard.name)
    }

    @Test func pastedImageBecomesAttachment() async throws {
        let editor = makeEditor("ab")
        let pasteboard = UIPasteboard.withUniqueName()
        editor.pasteboard = pasteboard
        pasteboard.setData(try Data(contentsOf: makePNG(width: 4, height: 4)), forPasteboardType: "public.png")
        var imported: [URL] = []
        editor.importFiles = { urls in
            imported = urls
            return ["![](feather://attachment/01P)"]
        }
        editor.selectedRange = NSRange(location: 2, length: 0)
        editor.paste(nil)
        #expect(await waitFor({ editor.textStorage.string != "ab" }, timeout: 5))
        #expect(imported.count == 1)
        #expect(editor.textStorage.string == "ab\n![](feather://attachment/01P)")
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "ab")
        UIPasteboard.remove(withName: pasteboard.name)
    }

    @Test func pastedTextIsPlain() {
        let editor = makeEditor("ab")
        let pasteboard = UIPasteboard.withUniqueName()
        editor.pasteboard = pasteboard
        pasteboard.string = "*x*"
        editor.selectedRange = NSRange(location: 1, length: 0)
        editor.paste(nil)
        #expect(editor.textStorage.string == "a*x*b")
        UIPasteboard.remove(withName: pasteboard.name)
    }

    @Test func copyButtonShowsWhileCaretInCodeBlock() throws {
        let editor = makeEditor("intro\n\n```\nlet x = 1\n```\n\nafter")
        let pasteboard = UIPasteboard.withUniqueName()
        editor.pasteboard = pasteboard
        // the button is on the first line of code, after the fence
        let codeStart = ("intro\n\n```\n" as NSString).length
        #expect(fragment(editor, at: codeStart)?.showsCopyButton == false)
        editor.selectedRange = NSRange(location: codeStart + 2, length: 0)
        // fragments are rebuilt when they change: look them up again
        let first = try #require(fragment(editor, at: codeStart))
        #expect(first.showsCopyButton)
        #expect(fragment(editor, at: 0)?.showsCopyButton == false)
        #expect(fragment(editor, at: codeStart + 10)?.showsCopyButton == false, "only the first line of code")
        let button = try #require(first.copyButtonRect)
        #expect(editor.handleTap(at: viewPoint(editor, first, button)))
        #expect(pasteboard.string == "let x = 1", "copied \(String(describing: pasteboard.string)), target \(String(describing: editor.tapTarget(at: viewPoint(editor, first, button))))")
        editor.selectedRange = NSRange(location: 0, length: 0)
        #expect(fragment(editor, at: codeStart)?.showsCopyButton == false)
        UIPasteboard.remove(withName: pasteboard.name)
    }

    @Test func linkTapOpensOnlyWithoutTheKeyboard() throws {
        let editor = makeEditor("see [docs](https://example.com) here")
        var opened: [String] = []
        editor.openLink = { opened.append($0) }
        editor.selectedRange = NSRange(location: 0, length: 0)
        let frag = try #require(fragment(editor, at: 0))
        let tlm = try #require(editor.textLayoutManager)
        // the middle of "docs"
        let loc = tlm.location(tlm.documentRange.location, offsetBy: 6)!
        var rect = CGRect.zero
        tlm.enumerateTextSegments(in: NSTextRange(location: loc, end: tlm.location(loc, offsetBy: 1))!, type: .standard, options: []) { _, r, _, _ in
            rect = r
            return false
        }
        let point = CGPoint(x: rect.midX + editor.textContainerInset.left, y: rect.midY + editor.textContainerInset.top)
        _ = frag
        #expect(!editor.isFirstResponder)
        #expect(editor.handleTap(at: point))
        #expect(opened == ["https://example.com"])
        #expect(editor.link(at: 6) == "https://example.com")
    }

    @Test func readOnlyIgnoresCommands() {
        let editor = makeEditor("- [ ] a")
        editor.isReadOnly = true
        #expect(!editor.isEditable)
        editor.apply(EditorCommands.Edit(range: NSRange(location: 0, length: 0), replacement: "x", selection: NSRange(location: 1, length: 0)))
        #expect(editor.textStorage.string == "- [ ] a")
    }

    @Test func modeSwitchShowsMarkers() {
        let editor = makeEditor("a **bold** b")
        editor.selectedRange = NSRange(location: 12, length: 0)
        #expect(isHidden(editor, 2))
        editor.mode = .raw
        #expect(!isHidden(editor, 2))
        #expect(editor.textStorage.string == "a **bold** b")
        editor.mode = .live
        #expect(isHidden(editor, 2))
    }
}

/// Lets the main queue's pending blocks run (the deferred restyle, the change report). A nested run loop can't:
/// the test itself is running on the main queue.
@MainActor func drainMainQueue() async {
    try? await Task.sleep(for: .milliseconds(50))
}
#endif
