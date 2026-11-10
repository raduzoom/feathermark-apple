import Foundation
import Testing
@testable import FeatherAppModel

/// Platform abilities reach the model only through `AppPlatform`; the model itself names no AppKit or UIKit type.
@MainActor @Suite struct AppPlatformTests {
    @Test func modelHasNoPlatformDependencies() async throws {
        let m = try await makeModel()                     // AppPlatform.none
        m.openLink("feather-attachment://missing")        // must not crash or reach AppKit
        m.registerQuickNoteShortcut(action: {})           // no shortcut on a platform without one
        #expect(m.quickNoteShortcutError == nil)
    }

    @Test func macOnlyAbilitiesComeFromThePlatform() async throws {
        var opened: [URL] = []
        var registered = 0
        let platform = AppPlatform(open: { opened.append($0) },
                                   registerQuickNoteShortcut: { _, _ in registered += 1; return NSObject() },
                                   isSystemShortcut: { _ in false })
        let m = try await makeModel(platform: platform)
        m.openLink("https://example.com")
        m.registerQuickNoteShortcut(action: {})
        #expect(opened == [URL(string: "https://example.com")!])
        #expect(registered == 1)
        m.changeQuickNoteShortcut(Shortcut(keyCode: 1, modifiers: 256))   // re-registers with the same action
        #expect(registered == 2)
    }

    /// A shortcut the system reserves is reported, and the registration is let go (that unregisters it).
    @Test func systemShortcutReleasesTheRegistration() async throws {
        final class Registration {
            let onRelease: () -> Void
            init(_ onRelease: @escaping () -> Void) { self.onRelease = onRelease }
            deinit { onRelease() }
        }
        var released = 0
        let platform = AppPlatform(open: { _ in },
                                   registerQuickNoteShortcut: { _, _ in Registration { released += 1 } },
                                   isSystemShortcut: { $0 == .quickNoteDefault })
        let m = try await makeModel(platform: platform)
        m.registerQuickNoteShortcut(action: {})
        #expect(m.quickNoteShortcutError == "macOS uses this shortcut.")
        #expect(released == 1)
    }
}
