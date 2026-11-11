import XCTest

/// Task 5: search from the library and within a notebook.
final class SearchUITests: FeatherUITestCase {
    /// The note list's search field: on iPad the library's field is visible too, to its left.
    func listSearchField() -> XCUIElement {
        let fields = app.searchFields.allElementsBoundByIndex.filter(\.exists)
        return fields.max { $0.frame.minX < $1.frame.minX } ?? app.searchFields.firstMatch
    }

    func testSearchFromLibraryFindsAcrossNotebooks() {
        launch()
        showLibrary()
        let field = app.searchFields["Search"].firstMatch
        waitFor(field)
        field.tap()
        field.typeText("milk")
        waitFor(row("Groceries"))
        XCTAssertFalse(row("Bread notes").exists)
    }

    func testScopedSearchOffersAllNotebooks() {
        launch()
        showLibrary()
        libraryItem("Travel").tap()
        waitFor(row("Lisbon, spring trip"))
        let field = listSearchField()   // the list's search field hides under the title until pulled down
        waitFor(field)
        field.tap()
        field.typeText("milk")
        waitFor(app.staticTexts["No notes match “milk”"])
        let all = app.buttons["Search All Notebooks"]
        waitFor(all)
        all.tap()
        waitFor(row("Groceries"))
    }

    func testClearingSearchRestoresList() {
        launch()
        showLibrary()
        libraryItem("Travel").tap()
        waitFor(row("Lisbon, spring trip"))
        let field = listSearchField()
        waitFor(field)
        field.tap()
        field.typeText("zzz")
        waitFor(app.staticTexts["No notes match “zzz”"])
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))   // iOS 27's field has no Cancel
        waitFor(row("Lisbon, spring trip"))
    }

    /// iPad: both columns have a search field. Clearing the list's must also clear the library's, so the library
    /// shows its notebooks again rather than an empty result list.
    func testClearingListSearchClearsLibrarySearch() throws {
        guard isPad else { throw XCTSkip("iPad only: on iPhone the library and list don't show together") }
        launch()
        let fields = app.searchFields.allElementsBoundByIndex.filter(\.exists).sorted { $0.frame.minX < $1.frame.minX }
        let library = try XCTUnwrap(fields.first)
        library.tap()
        library.typeText("milk")
        waitFor(row("Groceries"))
        let list = listSearchField()
        list.tap()
        list.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        waitFor(libraryItem("All Notes"))
    }
}
