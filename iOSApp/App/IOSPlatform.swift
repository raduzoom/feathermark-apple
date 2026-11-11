import FeatherAppModel
import UIKit

/// The iPhone's abilities for the shared `AppModel`: web and mail links open in the system; attachment files
/// open in Phase 13 (the editor's Quick Look). There is no global shortcut on iOS.
@MainActor enum IOSPlatform {
    static func make() -> AppPlatform {
        AppPlatform(open: { url in
                        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
                        UIApplication.shared.open(url)
                    },
                    registerQuickNoteShortcut: nil,
                    isSystemShortcut: { _ in false })
    }
}
