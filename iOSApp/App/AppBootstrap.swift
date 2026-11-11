import FeatherAppModel
import FeatherCore
import Foundation
import UIKit

/// Opens the app's model the way the app does: the library location, isolated settings for test runs, no
/// network (sync is Phase 15), and the iPhone's platform abilities.
@MainActor
enum AppBootstrap {
    /// Debug builds, isolated runs only: fill an empty library with the demo notes the mobile boards show.
    static let seedArgument = "-FeatherSeedDemo"
    static let isolatedDefaultsSuite = "app.feathermark.FeatherMark.isolated"
    /// UI tests only (debug builds, isolated runs): Photos and Files hand back a small PDF instead of showing.
    static let pickFixtureArgument = "-FeatherPickFixture"

    /// Seeding writes notes, so it runs only on a test library, never the person's own.
    static func shouldSeed(arguments: [String], environment: [String: String]) -> Bool {
        #if DEBUG
        arguments.contains(seedArgument) && LibraryLocation.isIsolated(arguments: arguments, environment: environment)
        #else
        false
        #endif
    }

    /// The file a UI test's pick returns ("Packing list.pdf" in its own temporary folder), or nil outside UI tests.
    static func pickFixture(arguments: [String] = CommandLine.arguments,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        #if DEBUG
        guard arguments.contains(pickFixtureArgument), LibraryLocation.isIsolated(arguments: arguments, environment: environment) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "FeatherPick-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = folder.appending(path: "Packing list.pdf")
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            context.beginPage()
            ("Passport, tickets" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? pdf.write(to: file)) != nil else { return nil }
        return file
        #else
        nil
        #endif
    }

    static func makeModel(arguments: [String] = CommandLine.arguments,
                          environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> AppModel {
        let isolated = LibraryLocation.isIsolated(arguments: arguments, environment: environment)
        let directory = LibraryLocation.directory(arguments: arguments, environment: environment)
        try LibraryLocation.prepare(directory)
        // a fresh temporary library starts with fresh settings, so one test run never changes the next
        if arguments.contains(LibraryLocation.temporaryArgument) {
            UserDefaults().removePersistentDomain(forName: isolatedDefaultsSuite)
        }
        let defaults = isolated ? UserDefaults(suiteName: isolatedDefaultsSuite)! : .standard
        let model = try AppModel.open(at: directory, defaults: defaults,
                                      cloud: .live(isolated: isolated, deviceName: DeviceWord.current),
                                      platform: IOSPlatform.make())
        #if DEBUG
        if shouldSeed(arguments: arguments, environment: environment) { try await DemoLibrary.seed(into: model.library) }
        #endif
        return model
    }

    /// Everything the app does once its model is open. Anything added here at launch (sync, later) is covered by
    /// `appMakesNoRequestAtLaunch`.
    static func launch(_ model: AppModel) async {
        ExportController.removeStaleExports()
        await model.load()
        model.startMaintenance()
    }
}
