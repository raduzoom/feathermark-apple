import XCTest

final class LaunchUITests: FeatherUITestCase {
    func testLaunchesWithSeededLibrary() {
        launch()
        waitFor(app.descendants(matching: .any)["library"], 10)
        let all = libraryItem("All Notes")
        waitFor(all)
        XCTAssertTrue(all.label.contains("6"), "All Notes shows 6: \(all.label)")
    }
}
