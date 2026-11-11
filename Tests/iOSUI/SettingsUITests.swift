import XCTest

/// Task 7: Settings (General, About) and Export Notes to Files.
final class SettingsUITests: FeatherUITestCase {
    func openSettings() {
        showLibrary()
        let gear = app.buttons["Settings"]
        waitFor(gear)
        gear.tap()
        waitFor(app.navigationBars["Settings"])
    }

    /// A picker row: iOS 27 labels it "<name>, <value>".
    func picker(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    func testRetentionPickerChangesValue() {
        launch()
        openSettings()
        picker("Empty Trash after").tap()
        let seven = app.buttons["7 days"]
        waitFor(seven)
        seven.tap()
        app.buttons["Done"].tap()
        openSettings()
        let row = picker("Empty Trash after")
        waitFor(row)
        XCTAssertTrue(row.label.hasSuffix("7 days"), row.label)
    }

    func testExportSavesToFiles() {
        launch()
        openSettings()
        let export = app.buttons["Export Notes…"]
        waitFor(export)
        export.tap()
        // The system's Files picker appears (the simulator's On My iPhone); Save puts the folder there.
        let save = app.buttons["DOCPicker.actionButton"]
        waitFor(save, 15)
        let ready = expectation(for: NSPredicate(format: "isHittable == true AND isEnabled == true"), evaluatedWith: save)
        wait(for: [ready], timeout: 10)   // the picker slides in; a tap before it settles is lost
        save.tap()
        let alert = app.alerts["Export finished"]
        waitFor(alert, 10)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Exported 6 notes to")).firstMatch.exists)
        alert.buttons["OK"].tap()
        waitFor(app.buttons["Export Notes…"])
        XCTAssertTrue(app.buttons["Export Notes…"].isEnabled)
    }

    func testAboutShowsVersion() {
        launch()
        openSettings()
        app.buttons["About FeatherMark"].tap()
        waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "MIT License")).firstMatch)
    }
}
