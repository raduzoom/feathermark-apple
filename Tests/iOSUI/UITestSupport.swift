import XCTest

/// Launches FeatherMark on a fresh temporary library seeded with the demo notes (never the real library).
@MainActor
class FeatherUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        // On iPad the three columns sit side by side in landscape; in portrait the system hides the library
        // behind the sidebar button (the standard split layout).
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    @discardableResult
    func launch(seeded: Bool = true, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FeatherTemporaryLibrary"] + (seeded ? ["-FeatherSeedDemo"] : []) + extra
        app.launch()
        self.app = app
        return app
    }

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Any element whose label starts with `prefix`.
    func element(labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// A note row whose label starts with `prefix` (on iOS 27 the row's button carries the label, not its cell).
    func row(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND (elementType == %d OR elementType == %d)",
            prefix, XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.button.rawValue)).firstMatch
    }

    /// The library's row (or chip) for a view, notebook or tag, by its visible name.
    func libraryItem(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "library-\(name)").firstMatch
    }

    /// Goes back to the library on iPhone (the split view is a stack there); on iPad it's always visible.
    func showLibrary() {
        guard !isPad else { return }
        let back = app.navigationBars.buttons.firstMatch
        while !libraryItem("All Notes").isHittable, back.exists, back.isHittable { back.tap() }
    }

    /// A full swipe across a row, edge to edge, fast (what a person does to trash or pin in one go). A right swipe
    /// starts on the row's first visible content: on iPad the floating library covers the row's left part.
    func fullSwipe(_ e: XCUIElement, left: Bool) {
        let f = e.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let visibleStart = max(f.minX + 24, e.staticTexts.firstMatch.frame.minX + 8)
        let start = origin.withOffset(CGVector(dx: left ? f.maxX - 24 : visibleStart, dy: f.midY))
        let end = origin.withOffset(CGVector(dx: left ? f.minX + 8 : f.maxX - 8, dy: f.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// A full swipe right. On iPhone it must do the action by itself. On iPad the floating library covers the row's
    /// left part, so the swipe can't travel far enough for a full swipe: it reveals the action, which is tapped.
    func swipeRight(_ e: XCUIElement, action: String) {
        fullSwipe(e, left: false)
        guard isPad else { return }
        let button = app.buttons.matching(NSPredicate(format: "label == %@", action)).firstMatch
        if button.waitForExistence(timeout: 2) { button.tap() }
    }

    /// Any element with this accessibility identifier.
    func identified(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func waitFor(_ e: XCUIElement, _ timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing: \(e)", file: file, line: line)
    }
}
