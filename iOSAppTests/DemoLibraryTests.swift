// The demo library is compiled into debug builds only (a Release test run measures speed).
#if DEBUG
import FeatherCore
import Foundation
import Testing
@testable import FeatherMarkiOS

@Suite struct DemoLibraryTests {
    @Test func seedMatchesTheBoards() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FNDemo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let library = try Library.open(at: dir)
        try await DemoLibrary.seed(into: library)

        let counts = try await library.counts()
        #expect(counts.all == 6 && counts.pinned == 2 && counts.trash == 1)

        let notebooks = try await library.notebooks()
        let byName = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["Personal", "Projects", "Home", "Work", "Travel"])
        let projects = try #require(byName["Projects"])
        #expect(byName["Home"]?.parentID == projects.id && byName["Work"]?.parentID == projects.id)
        #expect(byName["Personal"]?.parentID == nil && byName["Travel"]?.parentID == nil)

        #expect(Set(try await library.tags().map(\.name)) == ["hardware", "ideas", "reading", "to-do"])

        let weather = try #require(try await library.notes(in: .all).first { $0.title == "Weather station build" })
        let attachments = try await library.attachments()
        #expect(attachments.count == 1)
        let body = try #require(try await library.note(weather.id)).body
        #expect(body.contains("](feather://attachment/\(attachments[0].id))"))
    }

    @Test func seedingTwiceDoesNothingTheSecondTime() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FNDemo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let library = try Library.open(at: dir)
        try await DemoLibrary.seed(into: library)
        try await DemoLibrary.seed(into: library)
        #expect(try await library.counts().all == 6)
    }
}
#endif
