// Tests of the UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorTestSupport
import Testing
import UIKit
@testable import FeatherEditorCore
@testable import FeatherEditorPhone

/// The note's title and meta line, above the body inside the editor's scroll (they scroll with the note).
@MainActor @Suite(.serialized) struct PhoneTitleTests {
    func editor(title: String = "Groceries", body: String = "- [ ] milk") -> PhoneEditorView {
        let e = makeEditor(body)
        e.showsHeader = true
        e.title = title
        e.meta = "Home · Edited today"
        e.layoutIfNeeded()
        return e
    }

    @Test func titleHasNoSubstitutions() {
        let t = editor().titleView
        #expect(t.autocorrectionType == .no && t.smartQuotesType == .no && t.smartDashesType == .no)
        #expect(t.smartInsertDeleteType == .no && t.spellCheckingType == .no && t.inlinePredictionType == .no)
        #expect(t.accessibilityIdentifier == "note-title")
        t.insertText("\"it's\"")
        #expect(t.text == "Groceries\"it's\"")
    }

    @Test func titleEditsReachTheModel() {
        let e = editor(title: "")
        var titles: [String] = []
        e.onTitleChange = { titles.append($0) }
        e.titleView.insertText("S")
        e.titleView.insertText("e")
        #expect(titles == ["S", "Se"])
        #expect(e.title == "Se")
    }

    @Test func returnInTitleMovesToTheBody() {
        let e = editor(title: "")
        var titles: [String] = []
        e.onTitleChange = { titles.append($0) }
        e.titleView.insertText("Seeds")
        e.titleView.insertText("\n")
        #expect(e.title == "Seeds", "no line break in a title")
        #expect(e.isFirstResponder, "the body has focus")
        #expect(e.selectedRange == NSRange(location: 0, length: 0))
        #expect(titles.last == "Seeds")
    }

    @Test func pastedNewlinesBecomeSpaces() {
        let e = editor(title: "")
        e.titleView.paste(text: "one\ntwo\r\nthree")
        #expect(e.title == "one two three")
    }

    @Test func headerPushesTheBodyDown() {
        let e = editor()
        // the header sits beside the body; in the body's content coordinates it is above the text
        let titleFrame = e.convert(e.titleView.frame, from: e.titleView.superview)
        #expect(e.titleView.superview !== e, "not inside the body's accessibility element")
        #expect(titleFrame.height > 20)
        #expect(e.textContainerInset.top >= titleFrame.maxY, "the body starts below the title")
        #expect(e.metaLabel.text == "Home · Edited today")
        #expect(e.convert(e.metaLabel.frame, from: e.metaLabel.superview).maxY <= titleFrame.minY)
        // a long title wraps and the body moves down with it
        let before = e.textContainerInset.top
        e.title = String(repeating: "A long title ", count: 8)
        e.layoutIfNeeded()
        #expect(e.textContainerInset.top > before)
    }

    /// iPad shows a larger title (34 pt portrait, 38 pt landscape); nil goes back to the theme's.
    @Test func titleSizeSetsTheTitleFont() {
        let e = editor()
        let before = e.headerFrames.title.height
        e.titleSize = 38
        e.layoutIfNeeded()
        #expect(e.titleView.font?.pointSize == 38)
        #expect(e.titleView.placeholderLabel.font.pointSize == 38)
        #expect(e.headerFrames.title.height > before, "the header grows with the title")
        e.titleSize = nil
        #expect(e.titleView.font?.pointSize == e.theme.h1.pointSize)
    }

    @Test func readOnlyTitle() {
        let e = editor()
        e.isReadOnly = true
        #expect(!e.titleView.isEditable)
    }

    @Test func checkboxTapStillHitsBelowTheHeader() throws {
        let e = editor()
        let frag = try #require(fragment(e, at: 0))
        let box = try #require(frag.checkboxRect)
        #expect(e.handleTap(at: viewPoint(e, frag, box)))
        #expect(e.textStorage.string == "- [x] milk")
    }

    @Test func titleFocusWaitsForAWindow() async {
        // a new note is pushed: the editor gets its window after the focus was asked for
        let e = PhoneEditorView.make()
        e.showsHeader = true
        e.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        e.load("")
        var done = false
        e.requestTitleFocus { done = true }
        #expect(!done)
        let window = hostWindow()
        window.rootViewController!.view.addSubview(e)
        #expect(await waitFor({ done }, timeout: 3))
        #expect(e.titleView.isFirstResponder)
        _ = e.titleView.resignFirstResponder()
        window.isHidden = true
    }
}
#endif
