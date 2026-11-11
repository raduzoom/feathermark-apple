import FeatherAppModel
import FeatherCore
import Foundation

/// Opens the app's model the way the app does: the library location, isolated settings for test runs, no
/// network (sync is Phase 15), and the iPhone's platform abilities.
@MainActor
enum AppBootstrap {
    /// Debug builds, isolated runs only: fill an empty library with the demo notes the mobile boards show.
    static let seedArgument = "-FeatherSeedDemo"
    static let isolatedDefaultsSuite = "app.feathermark.FeatherMark.isolated"

    /// Seeding writes notes, so it runs only on a test library, never the person's own.
    static func shouldSeed(arguments: [String], environment: [String: String]) -> Bool {
        #if DEBUG
        arguments.contains(seedArgument) && LibraryLocation.isIsolated(arguments: arguments, environment: environment)
        #else
        false
        #endif
    }

    static func makeModel(arguments: [String] = CommandLine.arguments,
                          environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> AppModel {
        let isolated = LibraryLocation.isIsolated(arguments: arguments, environment: environment)
        let directory = LibraryLocation.directory(arguments: arguments, environment: environment)
        try LibraryLocation.prepare(directory)
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
