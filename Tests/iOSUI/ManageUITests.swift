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
        tapWhenSettled(app.alerts.buttons[button])
    }

    /// Replaces the name in the Rename alert, whose field has keyboard focus as the alert opens. It never taps the
    /// field: on iOS 27 a tap on the focused field shows the edit menu.
    func renameInAlert(from old: String, to new: String) {
        let field = app.alerts.textFields.firstMatch
        waitFor(field)
        waitFor(app.keyboards.firstMatch)
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", old), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [filled], timeout: 5), .completed, "the field doesn't show \(old)")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + new)
        tapWhenSettled(app.alerts.buttons["Rename"])
    }

    /// Taps an alert's button once the alert has stopped moving. On the iOS 27 simulator, typed text hides the
    /// on-screen keyboard (the alert slides to the middle) and the keyboard comes back just after the last key,
    /// sliding the alert up again; a tap during that slide lands where the button was and the alert stays open.
    func tapWhenSettled(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(button, file: file, line: line)
        for attempt in 1...2 where button.exists {
            var last = button.frame, still = 0
            let deadline = Date().addingTimeInterval(5)
            while still < 6, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                let now = button.frame
                still = now == last ? still + 1 : 0
                last = now
            }
            button.tap()
            // The tap landed if the alert went away; otherwise it moved under the tap, so try once more.
            if attempt == 2 || app.alerts.firstMatch.waitForNonExistence(timeout: 2) { return }
        }
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
