import XCTest

/// Screenshots of the designed screens, for comparing with universal/design/handoff/screens/mobile-*-ios-*.
/// Skipped unless asked for: `TEST_RUNNER_FEATHER_SHOT_DIR=<dir> xcodebuild test … -only-testing:FeatherMarkiOSUITests/ScreenshotUITests`.
/// Files: `ios-<screen>-<iphone|ipad>-<light|dark>.png`.
final class ScreenshotUITests: FeatherUITestCase {
    var shotDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        guard let dir = ProcessInfo.processInfo.environment["FEATHER_SHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FEATHER_SHOT_DIR to take screenshots")
        }
        shotDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
    }

    func shot(_ screen: String, _ scheme: String) {
        sleep(1)   // let animations settle
        let name = "ios-\(screen)-\(isPad ? "ipad" : "iphone")-\(scheme).png"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: shotDir.appending(path: name))
    }

    func testScreens() {
        for scheme in ["light", "dark"] {
            launch(["-FeatherColorScheme", scheme])
            showLibrary()
            waitFor(libraryItem("All Notes"))
            shot("library", scheme)

            libraryItem("All Notes").tap()
            let groceries = row("Groceries")
            waitFor(groceries)
            shot("note-list", scheme)

            let bread = row("Bread notes")
            let f = bread.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: f.maxX - 24, dy: f.midY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: f.maxX - 240, dy: f.midY)))
            shot("swipe", scheme)
            bread.swipeRight()   // closes the revealed actions

            row("Weather station build").tap()
            waitFor(app.descendants(matching: .any)["reader"], 5)
            shot("reader", scheme)

            showLibrary()
            app.buttons["Settings"].tap()
            waitFor(app.navigationBars["Settings"])
            shot("settings", scheme)
            app.terminate()
        }
    }
}
