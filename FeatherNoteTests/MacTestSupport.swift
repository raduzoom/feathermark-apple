import FeatherAppModel
import FeatherCore
import Foundation
@testable import FeatherNote

/// A model on a temporary library with the Mac's platform (NSWorkspace, Carbon hot keys), as the app opens it.
/// FeatherAppModel's own tests use `AppPlatform.none`.
@MainActor
func makeModel(clock: LibraryClock = .system, defaults: UserDefaults? = nil) async throws -> AppModel {
    let dir = FileManager.default.temporaryDirectory.appending(path: "FNModel-\(UUID().uuidString)")
    let model = try AppModel.open(at: dir, clock: clock, defaults: defaults ?? UserDefaults(suiteName: "FNTests-\(UUID().uuidString)")!,
                                  platform: MacPlatform.make())
    await model.load()
    return model
}
