import UIKit

/// What the copy calls this device: "this iPhone", "this iPad" (ui-copy.md says "this Mac" on the Mac).
@MainActor enum DeviceWord {
    static var current: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
}
