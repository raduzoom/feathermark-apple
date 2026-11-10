import Foundation

/// A key combination for the global quick-note shortcut: a virtual key code and Carbon modifier bits
/// (`RegisterEventHotKey`). Key names and key-event parsing are the Mac app's (`HotKey.swift`).
public struct Shortcut: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    /// ⌥⌘N: `kVK_ANSI_N` (45) with `cmdKey | optionKey` (256 | 2048). The Mac app's tests pin these to Carbon's.
    public static let quickNoteDefault = Shortcut(keyCode: 45, modifiers: 256 | 2048)

    /// Stored in UserDefaults as "<keyCode>:<modifiers>".
    public var stored: String { "\(keyCode):\(modifiers)" }

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(stored: String) {
        let parts = stored.split(separator: ":")
        guard parts.count == 2, let k = UInt32(parts[0]), let m = UInt32(parts[1]), m != 0 else { return nil }
        self.init(keyCode: k, modifiers: m)
    }
}
