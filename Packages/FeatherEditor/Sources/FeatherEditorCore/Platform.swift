// The editor core's only platform layer. Core files name `Platform*` types, never `NS*` or `UI*` ones, and use
// these helpers where AppKit and UIKit spell the same thing differently. On macOS every helper calls exactly
// what the core called before the split, so the Mac editor draws and styles as it did.

#if canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformBezierPath = NSBezierPath
public typealias PlatformFontTraits = NSFontDescriptor.SymbolicTraits
#else
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformBezierPath = UIBezierPath
public typealias PlatformFontTraits = UIFontDescriptor.SymbolicTraits
#endif

extension PlatformFontTraits {
    #if canImport(AppKit)
    static let featherBold: PlatformFontTraits = .bold
    static let featherItalic: PlatformFontTraits = .italic
    static let featherMonoSpace: PlatformFontTraits = .monoSpace
    #else
    static let featherBold: PlatformFontTraits = .traitBold
    static let featherItalic: PlatformFontTraits = .traitItalic
    static let featherMonoSpace: PlatformFontTraits = .traitMonoSpace
    #endif
}

extension PlatformFont {
    /// The system font with the serif design (New York), optionally italic.
    static func serifSystemFont(ofSize size: CGFloat, weight: PlatformFont.Weight, italic: Bool) -> PlatformFont {
        var d = PlatformFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        d = d.withDesign(.serif) ?? d
        #if canImport(AppKit)
        if italic { d = d.withSymbolicTraits(.italic) }
        return NSFont(descriptor: d, size: size) ?? .systemFont(ofSize: size, weight: weight)
        #else
        if italic { d = d.withSymbolicTraits(.traitItalic) ?? d }
        return UIFont(descriptor: d, size: size)
        #endif
    }

    /// This font with `traits` added, or itself when the family has no such face.
    func adding(_ traits: PlatformFontTraits) -> PlatformFont {
        var all = fontDescriptor.symbolicTraits
        all.insert(traits)
        #if canImport(AppKit)
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(all), size: pointSize) ?? self
        #else
        guard let d = fontDescriptor.withSymbolicTraits(all) else { return self }
        return UIFont(descriptor: d, size: pointSize)
        #endif
    }
}

extension PlatformColor {
    /// An sRGB colour from 0–255 channels packed as 0xRRGGBB.
    static func srgb(_ rgb: UInt32, alpha: CGFloat = 1) -> PlatformColor {
        srgb(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }

    static func srgb(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// A colour that follows light and dark mode.
    static func dynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
        #else
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }
}

extension PlatformBezierPath {
    static func rounded(_ rect: CGRect, radius: CGFloat) -> PlatformBezierPath {
        #if canImport(AppKit)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        #else
        UIBezierPath(roundedRect: rect, cornerRadius: radius)
        #endif
    }

    func lineTo(_ point: CGPoint) {
        #if canImport(AppKit)
        line(to: point)
        #else
        addLine(to: point)
        #endif
    }

    /// An arc from `start` to `end` degrees, angles increasing (clockwise on a flipped, y-down surface).
    func arc(center: CGPoint, radius: CGFloat, startDegrees start: CGFloat, endDegrees end: CGFloat) {
        #if canImport(AppKit)
        appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
        #else
        addArc(withCenter: center, radius: radius, startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: true)
        #endif
    }

    func fill(_ color: PlatformColor) { color.setFill(); fill() }
}

/// The current drawing context's state, as TextKit sets it up when it asks a layout fragment to draw.
extension PlatformImage {
    /// An image of `cgImage` (a downsampled thumbnail) that reports `size` in points: the original's pixel size,
    /// which the editor scales down to the measure.
    static func make(cgImage: CGImage, size: CGSize) -> PlatformImage {
        #if canImport(AppKit)
        NSImage(cgImage: cgImage, size: size)
        #else
        UIImage(cgImage: cgImage, scale: size.width > 0 ? CGFloat(cgImage.width) / size.width : 1, orientation: .up)
        #endif
    }
}

enum PlatformGraphics {
    static func save() {
        #if canImport(AppKit)
        NSGraphicsContext.saveGraphicsState()
        #else
        UIGraphicsGetCurrentContext()?.saveGState()
        #endif
    }

    static func restore() {
        #if canImport(AppKit)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsGetCurrentContext()?.restoreGState()
        #endif
    }

    /// Fills `rect` with the current fill colour, blending over what's there.
    static func fill(_ rect: CGRect) {
        #if canImport(AppKit)
        rect.fill()
        #else
        UIRectFillUsingBlendMode(rect, .normal)
        #endif
    }

    /// Draws `image` scaled into `rect`, upright on the flipped surface.
    static func draw(_ image: PlatformImage, in rect: CGRect) {
        #if canImport(AppKit)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        image.draw(in: rect)
        #endif
    }
}
