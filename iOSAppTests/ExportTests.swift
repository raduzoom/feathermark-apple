import FeatherAppModel
import Foundation
import Testing
@testable import FeatherMarkiOS

@MainActor @Suite struct ExportTests {
    @Test func exportWritesMarkdownFolder() async throws {
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary", "-FeatherSeedDemo"])
        await model.load()
        let controller = ExportController()
        let root = try #require(await controller.exportAll(model: model))
        #expect(root.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Personal/Groceries.md").path))
        #expect(controller.summary == "Exported 6 notes to “\(root.lastPathComponent)”.")
        #expect(!controller.isExporting)
        controller.finish()
        #expect(!FileManager.default.fileExists(atPath: root.path))   // the temporary copy goes once Files has it
    }

    /// Files can't merge into an existing folder: each export gets its own dated name, so a second export to the
    /// same place never collides with the first.
    @Test func exportFolderHasADatedName() async throws {
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary", "-FeatherSeedDemo"])
        await model.load()
        let controller = ExportController()
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00:00 UTC
        let root = try #require(await controller.exportAll(model: model, now: now, timeZone: TimeZone(identifier: "UTC")!))
        #expect(root.lastPathComponent == "FeatherMark Export 2027-01-15 08.00.00")
        #expect(controller.summary == "Exported 6 notes to “FeatherMark Export 2027-01-15 08.00.00”.")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Personal/Groceries.md").path))
        controller.finish()
    }

    @Test func newExportRemovesThePreviousOne() async throws {
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary", "-FeatherSeedDemo"])
        await model.load()
        let controller = ExportController()
        let first = try #require(await controller.exportAll(model: model))
        let second = try #require(await controller.exportAll(model: model))
        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        controller.finish()
    }

    /// An export the Files picker never took (the app was closed, the sheet dismissed) is cleared at the next launch.
    @Test func staleExportsAreRemoved() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "FNStale-\(UUID().uuidString)", directoryHint: .isDirectory)
        let stale = tmp.appending(path: "FeatherMark-Export-OLD", directoryHint: .isDirectory)
        let other = tmp.appending(path: "Something-Else", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stale.appending(path: "FeatherMark Export"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        ExportController.removeStaleExports(in: tmp)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
