import Foundation

/// What the app can do only through its platform: open a URL or file in the system, and register a global
/// quick-note shortcut. The Mac app passes `MacPlatform.make()`; the iPhone app passes its own (Phase 12).
@MainActor public struct AppPlatform {
    /// Opens a URL or attachment file in the system (Mac: NSWorkspace; iOS: UIApplication).
    public var open: (URL) -> Void
    /// Registers the global quick-note shortcut and returns its registration, which stays registered until it's
    /// released; nil where there is none (iOS). Throws when the combination is taken.
    public var registerQuickNoteShortcut: ((Shortcut, @escaping () -> Void) throws -> AnyObject)?
    /// Whether a shortcut is reserved by the system (Mac: HotKey.systemShortcuts()).
    public var isSystemShortcut: (Shortcut) -> Bool

    /// Tests and isolated runs: open does nothing, no shortcut.
    public static let none = AppPlatform(open: { _ in }, registerQuickNoteShortcut: nil, isSystemShortcut: { _ in false })

    public init(open: @escaping (URL) -> Void,
                registerQuickNoteShortcut: ((Shortcut, @escaping () -> Void) throws -> AnyObject)?,
                isSystemShortcut: @escaping (Shortcut) -> Bool) {
        self.open = open
        self.registerQuickNoteShortcut = registerQuickNoteShortcut
        self.isSystemShortcut = isSystemShortcut
    }
}
