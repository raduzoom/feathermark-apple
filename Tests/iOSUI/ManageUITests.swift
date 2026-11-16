import XCTest

/// Task 8: creating, renaming and deleting notebooks and tags.
final class ManageUITests: FeatherUITestCase {
    func libraryMenu(_ item: String) {
        showLibrary()
        let more = app.buttons["Library actions"]
        waitFor(more)
        more.tap()
        let button = app.buttons[item]
        waitFor(button)
        button.tap()
    }

    func answerAlert(_ text: String, _ button: String) {
        let field = app.alerts.textFields.firstMatch
        waitFor(field)
        field.typeText(text)
        app.alerts.buttons[button].tap()
    }

    /// Replaces the name in the Rename alert, whose field has keyboard focus as the alert opens. It never taps the
    /// field: on iOS 27 a tap on the focused field shows the edit menu and drops the keyboard, which comes back as
    /// the text is typed and moves the alert up under the next tap.
    func renameInAlert(from old: String, to new: String) {
        let field = app.alerts.textFields.firstMatch
        waitFor(field)
        waitFor(app.keyboards.firstMatch)
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", old), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [filled], timeout: 5), .completed, "the field doesn't show \(old)")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + new)
        app.alerts.buttons["Rename"].tap()
    }

    func longPress(_ name: String, then item: String) {
        let e = libraryItem(name)
        waitFor(e)
        e.press(forDuration: 1.2)
        let button = app.buttons[item]
        waitFor(button)
        button.tap()
    }

    func testCreateAndRenameNotebook() {
        launch()
        libraryMenu("New Notebook…")
        answerAlert("Garden", "Create Notebook")
        waitFor(libraryItem("Garden"))
        longPress("Garden", then: "Rename…")
        renameInAlert(from: "Garden", to: "Allotment")
        waitFor(libraryItem("Allotment"))
        XCTAssertFalse(libraryItem("Garden").exists)
    }

    func testDeleteNotebookAsksFirst() {
        launch()
        showLibrary()
        longPress("Travel", then: "Delete Notebook…")
        waitFor(app.staticTexts["Delete “Travel”?"])
        app.buttons["Delete Notebook"].tap()
        XCTAssertTrue(libraryItem("Travel").waitForNonExistence(timeout: 3))
        let trash = libraryItem("Trash")
        XCTAssertTrue(trash.label.contains("2"), "Lisbon went to the Trash: \(trash.label)")
    }

    func testRenameTag() {
        launch()
        showLibrary()
        // The tags are the library's last row; iOS 27's floating search field covers them until the list scrolls.
        app.descendants(matching: .any)["library"].firstMatch.swipeUp()
        longPress("ideas", then: "Rename…")
        renameInAlert(from: "ideas", to: "someday")
        waitFor(libraryItem("someday"))
        // Each chip's menu acts on its own tag: the long press on "ideas" must not rename "hardware".
        XCTAssertTrue(libraryItem("hardware").exists, "hardware was renamed instead of ideas")
        XCTAssertFalse(libraryItem("ideas").exists)
    }
}
