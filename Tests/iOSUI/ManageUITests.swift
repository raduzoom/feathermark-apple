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
        let field = app.alerts.textFields.firstMatch
        waitFor(field)
        field.clearAndType("Allotment")
        app.alerts.buttons["Rename"].tap()
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
        let field = app.alerts.textFields.firstMatch
        waitFor(field)
        field.clearAndType("someday")
        app.alerts.buttons["Rename"].tap()
        waitFor(libraryItem("someday"))
    }
}

extension XCUIElement {
    /// Replaces a text field's contents.
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty, current != placeholderValue {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
