import SwiftUI
import UIKit

/// Design tokens for the iPhone and iPad app (universal/design/tokens.json, direction D · Mint Glass).
enum Theme {
    static func color(_ light: UInt32, _ dark: UInt32, _ lightAlpha: CGFloat = 1, _ darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark, darkAlpha) : rgb(light, lightAlpha) })
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    // Colour
    static let ink = color(0x13243A, 0xECF2EE)
    static let textSecondary = color(0x3E4C5A, 0xA4B1BC)
    static let accent = color(0x1F7A55, 0x6FD3A3)
    static let accentTint = color(0x1F7A55, 0x6FD3A3, 0.14, 0.18)
    /// Navy fill: only the screen's main action (universal/AGENTS.md "Visual design").
    static let primaryFill = color(0x13243A, 0x6FD3A3)
    static let onPrimary = color(0xFFFFFF, 0x0E1A16)
    static let hairline = color(0x13243A, 0xFFFFFF, 0.08, 0.08)
    static let raised = color(0xFFFFFF, 0xFFFFFF, 0.80, 0.10)
    static let card = color(0xFFFFFF, 0xFFFFFF, 0.55, 0.06)
    static let windowBackground = color(0xF1E2D5, 0x11171D)
    static let glowMint = color(0xCFE7D9, 0x1C4A3A)
    static let glowPeach = color(0xF7CDB4, 0x4A2E26)
    static let destructive = color(0xB3372B, 0xE5796E)
    static let swipeMove = color(0x13243A, 0x2C3E55)
    static let swipeTags = color(0x4A5D75, 0x56677D)

    /// Note tiles: peach, mint, lavender, sky (NoteThumbnail.tint).
    static func tile(_ tint: Int) -> Color {
        [color(0xF7DCCB, 0x4A3329), color(0xDCEDE3, 0x23402F), color(0xE4E0F3, 0x332E4A), color(0xDCE6F2, 0x26344A)][tint & 3]
    }

    static func tileInk(_ tint: Int) -> Color {
        [color(0x9A4A2A, 0xF2B99B), color(0x2F6B4C, 0x9FDABA), color(0x4B3F8C, 0xC5BBF0), color(0x34557D, 0xA9C4E6)][tint & 3]
    }

    // Type: a serif display face for titles, the system sans for UI.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    // Spacing: the 8 pt grid (4 only inside a control).
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let tileSize: CGFloat = 48
    static let cornerRadius: CGFloat = 16

    /// Large navigation titles in the serif display face, in navy ink ("Library", "All Notes").
    @MainActor static func configureNavigationBars() {
        func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let bold = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            let descriptor = bold.fontDescriptor.withDesign(.serif) ?? bold.fontDescriptor
            return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: base.pointSize))
        }
        let ink = UIColor(ink)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: serif(.largeTitle, .bold), .foregroundColor: ink]
        UINavigationBar.appearance().titleTextAttributes = [.font: serif(.headline, .semibold), .foregroundColor: ink]
    }
}
