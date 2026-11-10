import AppKit
import FeatherAppModel

/// The Mac's abilities for the shared `AppModel`: NSWorkspace opens URLs and files, Carbon registers the global
/// quick-note shortcut (`HotKey`, released to unregister), and macOS's own shortcuts are reported.
@MainActor enum MacPlatform {
    static func make() -> AppPlatform {
        AppPlatform(open: { NSWorkspace.shared.open($0) },
                    registerQuickNoteShortcut: { shortcut, action in try HotKey(shortcut: shortcut, action: action) },
                    isSystemShortcut: { HotKey.systemShortcuts().contains($0) })
    }
}
