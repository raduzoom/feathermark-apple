import XCTest

/// Task 4: the library, the note list and the split layout (boards mobile-library, mobile-note-list,
/// mobile-note-actions-swipe and mobile-note-actions-menu).
final class LibraryUITests: FeatherUITestCase {
    func open(_ name: String) {
        showLibrary()
        let item = libraryItem(name)
        waitFor(item)
        item.tap()
    }

    func testOpenNotebookShowsItsNotes() {
        launch()
        open("Projects")
        waitFor(row("Weather station build"))
        XCTAssertTrue(row("1:1 with Mara").exists)
        XCTAssertFalse(row("Groceries").exists)
    }

    func testSubNotebookDisclosure() {
        launch()
        showLibrary()
        waitFor(libraryItem("Projects"))
        XCTAssertFalse(libraryItem("Home").exists)
        app.buttons["Show sub-notebooks of Projects"].tap()
        waitFor(libraryItem("Home"))
        XCTAssertTrue(libraryItem("Work").exists)
    }

    func testFilterChipSwitchesList() {
        launch()
        open("All Notes")
        let chip = identified("chip-Travel")
        waitFor(chip)
        chip.tap()
        waitFor(row("Lisbon, spring trip"))
        XCTAssertTrue(row("Groceries").waitForNonExistence(timeout: 3))
    }

    func testFullSwipeTrashesWithUndo() {
        launch()
        open("All Notes")
        let bread = row("Bread notes")
        waitFor(bread)
        fullSwipe(bread, left: true)
        XCTAssertTrue(bread.waitForNonExistence(timeout: 3), "a full swipe left trashes the note")
        let undo = app.buttons["Undo"]
        waitFor(undo)
        undo.tap()
        waitFor(row("Bread notes"))
        XCTAssertTrue(undo.waitForNonExistence(timeout: 3))
    }

    func testSwipeRightPins() {
        launch()
        open("All Notes")
        let bread = row("Bread notes")
        waitFor(bread)
        XCTAssertFalse(bread.label.contains("pinned"))
        swipeRight(bread, action: "Pin")
        waitFor(row("Bread notes, pinned"))
    }

    func testMoveToNotebookFromContextMenu() {
        launch()
        open("All Notes")
        let bread = row("Bread notes")
        waitFor(bread)
        bread.press(forDuration: 1.2)
        let move = app.buttons["Move to Notebook…"]
        waitFor(move)
        move.tap()
        let travel = identified("move-Travel")
        waitFor(travel)
        travel.tap()
        XCTAssertTrue(travel.waitForNonExistence(timeout: 3))
        open("Travel")
        waitFor(row("Bread notes"))
    }

    func testTrashRestoreAndEmpty() {
        launch()
        open("Trash")
        let draft = row("Old draft")
        waitFor(draft)
        swipeRight(draft, action: "Restore")
        XCTAssertTrue(draft.waitForNonExistence(timeout: 3), "a full swipe right restores")
        waitFor(app.staticTexts["Trash is empty"])
        showLibrary()
        let all = libraryItem("All Notes")
        waitFor(all)
        XCTAssertTrue(all.label.contains("7"), "All Notes shows 7: \(all.label)")
    }

    func testEmptyTrashAsksFirst() {
        launch()
        open("Trash")
        waitFor(row("Old draft"))
        app.buttons["Empty Trash…"].tap()
        let confirm = app.buttons["Empty Trash"]
        waitFor(confirm)
        confirm.tap()
        waitFor(app.staticTexts["Trash is empty"])
    }

    func testIPadShowsColumnsSideBySide() throws {
        guard isPad else { throw XCTSkip("iPad only") }
        launch()
        let all = libraryItem("All Notes")
        waitFor(all)
        waitFor(row("Weather station build"))
        XCTAssertTrue(all.isHittable && row("Weather station build").isHittable)
    }

    func testFooterCountsNotes() {
        launch()
        open("All Notes")
        let device = isPad ? "iPad" : "iPhone"
        waitFor(app.staticTexts["6 notes · on this \(device) only"])
    }
}
