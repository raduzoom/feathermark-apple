import XCTest

/// Task 6: reading a note.
final class ReaderUITests: FeatherUITestCase {
    func testOpenNoteShowsTitleAndBody() {
        launch()
        showLibrary()
        libraryItem("All Notes").tap()
        let groceries = row("Groceries")
        waitFor(groceries)
        groceries.tap()
        let reader = app.descendants(matching: .any)["reader"]
        waitFor(reader)
        waitFor(reader.staticTexts["Groceries"])
        let body = app.textViews["reader-body"]
        waitFor(body)
        XCTAssertTrue((body.value as? String ?? "").contains("Oat milk"))
    }

    func testTrashedNoteOffersRestore() {
        launch()
        showLibrary()
        libraryItem("Trash").tap()
        let draft = row("Old draft")
        waitFor(draft)
        draft.tap()
        waitFor(app.staticTexts["This note is in the Trash"])
        app.buttons["Restore Note"].tap()
        showLibrary()
        let all = libraryItem("All Notes")
        waitFor(all)
        XCTAssertTrue(all.label.contains("7"), "All Notes shows 7: \(all.label)")
    }

    /// On iPhone, trashing the open note goes back to the list (where its Undo shows), never on to another note.
    func testTrashFromReaderReturnsToList() throws {
        guard !isPad else { throw XCTSkip("iPhone only: on iPad the list stays beside the note") }
        launch()
        showLibrary()
        libraryItem("All Notes").tap()
        let bread = row("Bread notes")
        waitFor(bread)
        bread.tap()
        waitFor(app.descendants(matching: .any)["reader"])
        app.buttons["Note actions"].tap()
        let trash = app.buttons["Move to Trash"]
        waitFor(trash)
        trash.tap()
        waitFor(app.buttons["Undo"])
        waitFor(row("Groceries"))
        XCTAssertTrue(row("Groceries").isHittable, "the list shows again")
        XCTAssertFalse(app.descendants(matching: .any)["reader"].exists, "no other note opened in its place")
    }
}
