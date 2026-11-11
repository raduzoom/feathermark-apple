import XCTest

/// Phase 13: writing on iPhone and iPad (replaces Phase 12's reader tests).
final class EditorUITests: FeatherUITestCase {
    var body: XCUIElement { app.textViews["note-body"] }
    /// The title sits inside the body's scroll; iOS 27 lists it twice in the accessibility tree, so typing goes to
    /// whatever has focus (`app.typeText`), as a keyboard does.
    var title: XCUIElement { app.textViews["note-title"].firstMatch }
    var bodyText: String { body.value as? String ?? "" }

    func open(_ note: String, in view: String = "All Notes") {
        showLibrary()
        libraryItem(view).tap()
        let r = row(note)
        waitFor(r)
        r.tap()
        waitFor(body)
    }

    /// Goes back to the list on iPhone; on iPad the list is beside the note.
    func backToList() {
        guard !isPad else { return }
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
    }

    func newNote() {
        showLibrary()
        libraryItem("All Notes").tap()
        let compose = app.buttons["New Note"]
        waitFor(compose)
        compose.tap()
        waitFor(title)
        // the title takes focus once the push settles
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the new note's title has focus")
    }

    func testOpenNoteShowsTitleAndBody() {
        launch()
        open("Groceries")
        XCTAssertEqual(title.value as? String, "Groceries")
        XCTAssertTrue(bodyText.contains("Oat milk"))
    }

    func testWriteANewNote() {
        launch()
        newNote()
        app.typeText("Seeds\n")
        app.typeText("- [ ] tomatoes")
        XCTAssertEqual(bodyText, "- [ ] tomatoes")
        backToList()
        let seeds = row("Seeds")
        waitFor(seeds)
        seeds.tap()
        waitFor(body)
        XCTAssertEqual(bodyText, "- [ ] tomatoes")
    }

    func testUndoFromTheBar() {
        launch()
        newNote()
        app.typeText("Undo\n")
        app.typeText("abc")
        let undo = app.buttons["Undo"]
        waitFor(undo)
        undo.tap()
        XCTAssertEqual(bodyText, "", "one step undoes the typing, once")
    }

    func testCheckboxTapToggles() {
        launch()
        open("Groceries")
        // the first line's checkbox: at the text's left edge, one line below the title
        let t = title.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: t.minX + 8, dy: t.maxY + 16 + 13)).tap()
        let toggled = NSPredicate(format: "value BEGINSWITH %@", "- [x] Oat milk")
        expectation(for: toggled, evaluatedWith: body)
        waitForExpectations(timeout: 3)
        backToList()
        open("Groceries")
        XCTAssertTrue(bodyText.hasPrefix("- [x] Oat milk"), "kept: \(bodyText)")
    }

    func testBoldFromTheBar() {
        launch()
        newNote()
        app.typeText("Bold\n")
        app.typeText("make this loud")
        body.doubleTap()   // selects the word under the finger
        let bold = app.buttons["Bold"]
        waitFor(bold)
        bold.tap()
        XCTAssertTrue(bodyText.contains("**"), "bold markers: \(bodyText)")
        XCTAssertEqual(bodyText.replacingOccurrences(of: "**", with: ""), "make this loud")
    }

    func testSlashMenuMakesAHeading() {
        launch()
        newNote()
        app.typeText("Plans\n")
        app.typeText("/")
        let heading = app.buttons["Heading 2"]
        waitFor(heading)
        heading.tap()
        app.typeText("Plan")
        XCTAssertEqual(bodyText, "## Plan")
    }

    func testRawMarkdownToggle() {
        launch()
        open("Reading list 2027")
        let before = bodyText
        app.buttons["Note actions"].tap()
        let markdown = app.buttons["Markdown"]
        waitFor(markdown)
        markdown.tap()
        XCTAssertEqual(body.label, "Note body, Markdown")
        XCTAssertEqual(bodyText, before, "the text never changes for display")
    }

    func testAttachFromFiles() {
        launch(seeded: true, ["-FeatherPickFixture"])
        newNote()
        app.typeText("Trip\n")
        app.typeText("Tickets:")
        let attach = app.buttons["Attach"]
        waitFor(attach)
        attach.tap()
        let files = app.buttons["Choose File…"]
        waitFor(files)
        files.tap()
        let attached = NSPredicate(format: "value CONTAINS %@", "](feather://attachment/")
        expectation(for: attached, evaluatedWith: body)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(bodyText.hasPrefix("Tickets:\n["), bodyText)
    }

    func testTrashedNoteIsReadOnly() {
        launch()
        open("Old draft", in: "Trash")
        waitFor(app.staticTexts["This note is in the Trash"])
        body.tap()
        XCTAssertEqual(app.keyboards.count, 0, "no keyboard for a note in the Trash")
        app.buttons["Restore Note"].tap()
        showLibrary()
        let all = libraryItem("All Notes")
        waitFor(all)
        XCTAssertTrue(all.label.contains("7"), "All Notes shows 7: \(all.label)")
    }

    /// On iPhone, trashing the open note goes back to the list (where its Undo shows), never on to another note.
    func testTrashFromEditorReturnsToList() throws {
        guard !isPad else { throw XCTSkip("iPhone only: on iPad the list stays beside the note") }
        launch()
        open("Bread notes")
        app.buttons["Note actions"].tap()
        let trash = app.buttons["Move to Trash"]
        waitFor(trash)
        trash.tap()
        waitFor(app.buttons["Undo"])
        waitFor(row("Groceries"))
        XCTAssertTrue(row("Groceries").isHittable, "the list shows again")
        XCTAssertFalse(body.exists, "no other note opened in its place")
    }
}
