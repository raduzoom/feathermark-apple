#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Draws a paragraph's decoration (markdown-rendering.md) around TextKit's own text drawing.
public final class DecoratedLayoutFragment: NSTextLayoutFragment {
    /// Set on the main thread (when the fragment is made, and on hover); TextKit draws on the main thread too.
    nonisolated(unsafe) public var theme: EditorTheme = .standard
    nonisolated(unsafe) public var showsCopyButton = false
    nonisolated(unsafe) public var imageProvider: (String) -> PlatformImage? = { _ in nil }
    nonisolated(unsafe) public var chipProvider: (String) -> ChipInfo = { _ in ChipInfo(badge: "?", isPDF: false, missing: true) }

    private var decoration: Decoration? {
        guard let p = textElement as? NSTextParagraph, p.attributedString.length > 0 else { return nil }
        return p.attributedString.attribute(.featherDecoration, at: 0, effectiveRange: nil) as? Decoration
    }

    private var paragraphStyle: NSParagraphStyle? {
        guard let p = textElement as? NSTextParagraph, p.attributedString.length > 0 else { return nil }
        return p.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    /// The first text line's box, in fragment coordinates.
    private var firstLineRect: CGRect {
        guard let line = textLineFragments.first else { return .zero }
        return line.typographicBounds
    }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    /// Where the first line's text starts, in fragment coordinates. The fragment's frame already begins at
    /// the paragraph's indent, so this is usually 0; decorations are placed relative to it.
    private var textStartX: CGFloat {
        let pad = textLayoutManager?.textContainer?.lineFragmentPadding ?? 5
        return pad + (paragraphStyle?.firstLineHeadIndent ?? 0) - layoutFragmentFrame.minX
    }

    /// Where the 16 × 16 checkbox sits (fragment coordinates): 8 before the text. Used for clicks too.
    public var checkboxRect: CGRect? {
        guard case .checkbox = decoration else { return nil }
        return CGRect(x: textStartX - 24, y: firstLineRect.midY - 8, width: 16, height: 16)
    }

    /// Where the bullet glyph sits (fragment coordinates).
    public var bulletRect: CGRect? {
        guard case .bullet(let depth) = decoration else { return nil }
        let size = bulletGlyph(depth).size()
        return CGRect(x: textStartX - 16, y: firstLineRect.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func bulletGlyph(_ depth: Int) -> NSAttributedString {
        NSAttributedString(string: ["•", "◦", "▪"][depth % 3], attributes: [.font: theme.body, .foregroundColor: theme.textBody])
    }

    /// The pills behind attachment chips (fragment coordinates), with their link URLs.
    public var chips: [(rect: CGRect, url: String)] {
        guard let p = textElement as? NSTextParagraph, p.attributedString.length > 0 else { return [] }
        var out: [(CGRect, String)] = []
        p.attributedString.enumerateAttribute(.featherChip, in: NSRange(location: 0, length: p.attributedString.length)) { value, run, _ in
            guard let url = value as? String,
                  let line = textLineFragments.first(where: { NSLocationInRange(run.location, $0.characterRange) }) else { return }
            // The chip run is the name; the hidden "[" before it carries 40 of kern, room for the badge. Measure
            // from the "[" (the x right after a kerned glyph is ambiguous).
            let bracket = max(run.location - 1, line.characterRange.location)
            let start = line.locationForCharacter(at: bracket).x + line.typographicBounds.minX
            let end = line.locationForCharacter(at: min(NSMaxRange(run), NSMaxRange(line.characterRange))).x + line.typographicBounds.minX
            out.append((CGRect(x: start - 4, y: line.typographicBounds.midY - 14, width: end - start + 12, height: 28), url))
        }
        return out
    }

    public var chipRects: [CGRect] { chips.map(\.rect) }

    /// The code or quote surface for this line, drawn at `point` (the fragment's origin in the drawing).
    /// Top and bottom are rounded to whole points, so consecutive lines' surfaces meet without a seam.
    public func surfaceRect(at point: CGPoint) -> CGRect {
        let top = point.y.rounded(), bottom = (point.y + layoutFragmentFrame.height).rounded()
        return CGRect(x: point.x - layoutFragmentFrame.minX, y: top, width: containerWidth, height: bottom - top)
    }

    /// Where the code block's Copy button sits (first line only).
    public var copyButtonRect: CGRect? {
        guard case .code(_, true, _) = decoration else { return nil }
        let top = layoutFragmentFrame.height - (textLineFragments.first.map { _ in firstLineRect.height } ?? 0) - theme.codePadding
        return CGRect(x: containerWidth - 64, y: max(0, top - 4), width: 48, height: 20)
    }

    override public var renderingSurfaceBounds: CGRect {
        var r = super.renderingSurfaceBounds
        r = r.union(CGRect(x: -layoutFragmentFrame.minX, y: 0, width: containerWidth + 16, height: layoutFragmentFrame.height))
        return r
    }

    override public func draw(at point: CGPoint, in context: CGContext) {
        let theme = self.theme
        let frame = CGRect(origin: point, size: layoutFragmentFrame.size)
        let left = point.x - layoutFragmentFrame.minX   // the text container's leading edge
        #if !canImport(AppKit)
        // UIKit drawing (paths, strings, images) goes to the current context, which a layer-backed text view
        // doesn't set; make TextKit's context current. AppKit's text view always does.
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #endif
        PlatformGraphics.save()
        defer { PlatformGraphics.restore() }

        switch decoration {
        case .code(let language, let first, let last):
            let rect = surfaceRect(at: point)
            roundedRect(rect, radius: 16, top: first, bottom: last).fill(theme.codeBackground)
            if first, let language {
                let label = NSAttributedString(string: language, attributes: [.font: PlatformFont.systemFont(ofSize: 11), .foregroundColor: theme.codeText.withAlphaComponent(0.6)])
                let size = label.size()
                let showCopy = showsCopyButton
                label.draw(at: CGPoint(x: left + containerWidth - size.width - (showCopy ? 72 : 16), y: frame.minY + 8))
            }
            if first, showsCopyButton, let r = copyButtonRect {
                let button = r.offsetBy(dx: left, dy: frame.minY)
                PlatformBezierPath.rounded(button, radius: 6).fill(PlatformColor.white.withAlphaComponent(0.12))
                let t = NSAttributedString(string: "Copy", attributes: [.font: PlatformFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: theme.codeText])
                t.draw(at: CGPoint(x: button.midX - t.size().width / 2, y: button.midY - t.size().height / 2))
            }
        case .quote(let depth, let first, let last):
            for level in 1...max(1, depth) {
                let inset = theme.quoteIndent * CGFloat(level - 1)
                let surface = surfaceRect(at: point)
                let rect = CGRect(x: surface.minX + inset, y: surface.minY, width: surface.width - inset, height: surface.height)
                let fill = level == 1 ? theme.quoteBackground : theme.quoteBackground.withAlphaComponent(0.5)
                roundedRect(rect, radius: 16, top: first, bottom: last).fill(fill)
            }
        default:
            break
        }
        drawChips(at: point)

        super.draw(at: point, in: context)

        switch decoration {
        case .bullet(let depth):
            guard let r = bulletRect else { break }
            bulletGlyph(depth).draw(at: CGPoint(x: point.x + r.minX, y: point.y + r.minY))
        case .checkbox(let checked):
            guard let box = checkboxRect?.offsetBy(dx: point.x, dy: point.y) else { break }
            let path = PlatformBezierPath.rounded(box, radius: 4)
            if checked {
                theme.accentFill.setFill(); path.fill()
                let check = PlatformBezierPath()
                check.move(to: CGPoint(x: box.minX + 4, y: box.midY))
                check.lineTo(CGPoint(x: box.minX + 7, y: box.maxY - 4))
                check.lineTo(CGPoint(x: box.maxX - 3.5, y: box.minY + 4))
                check.lineWidth = 2; check.lineCapStyle = .round; check.lineJoinStyle = .round
                PlatformColor.white.setStroke(); check.stroke()
            } else {
                path.lineWidth = 1.5
                theme.textPlaceholder.setStroke()
                PlatformBezierPath.rounded(box.insetBy(dx: 0.75, dy: 0.75), radius: 3.5).stroke()
            }
        case .rule:
            theme.hairline.setFill()
            PlatformGraphics.fill(CGRect(x: left, y: frame.midY.rounded(.down), width: containerWidth, height: 1))
        case .image(let url, let alt):
            drawImage(url: url, alt: alt, left: left, frame: frame)
        default:
            break
        }
    }

    private func drawImage(url: String, alt: String, left: CGFloat, frame: CGRect) {
        let pad = textLayoutManager?.textContainer?.lineFragmentPadding ?? 5
        let x = left + pad
        let maxWidth = min(theme.measure, containerWidth - 2 * pad)
        if let image = imageProvider(url), image.size.width > 0 {
            let width = min(image.size.width, maxWidth)
            let height = (image.size.height * width / image.size.width).rounded()
            let rect = CGRect(x: x, y: frame.minY, width: width, height: height)
            PlatformGraphics.save()
            PlatformBezierPath.rounded(rect, radius: 12).addClip()
            PlatformGraphics.draw(image, in: rect)
            PlatformGraphics.restore()
            drawCaption(alt, x: x, y: rect.maxY + 4)
        } else {
            let rect = CGRect(x: x, y: frame.minY, width: min(maxWidth, 320), height: 96)
            PlatformBezierPath.rounded(rect, radius: 12).fill(theme.unrenderedBackground)
            let name = URL(string: url)?.lastPathComponent ?? url
            let label = NSAttributedString(string: alt.isEmpty ? name : alt, attributes: [.font: PlatformFont.systemFont(ofSize: 12), .foregroundColor: theme.textSecondary])
            label.draw(at: CGPoint(x: rect.minX + 16, y: rect.midY - label.size().height / 2))
            drawCaption(alt, x: x, y: rect.maxY + 4)
        }
    }

    private func drawCaption(_ alt: String, x: CGFloat, y: CGFloat) {
        guard !alt.isEmpty else { return }
        NSAttributedString(string: alt, attributes: [.font: PlatformFont.systemFont(ofSize: 12), .foregroundColor: theme.textSecondary])
            .draw(at: CGPoint(x: x, y: y))
    }

    /// Pills behind attachment links: badge (PDF red, others slate) and name.
    private func drawChips(at point: CGPoint) {
        for (rect, url) in chips {
            let info = chipProvider(url)
            let pill = rect.offsetBy(dx: point.x, dy: point.y)
            PlatformBezierPath.rounded(pill, radius: 14)
                .fill(info.missing ? PlatformColor.srgb(red: 0.69, green: 0.43, blue: 0, alpha: 0.12) : theme.unrenderedBackground.withAlphaComponent(0.08))
            let badge = CGRect(x: pill.minX + 4, y: pill.minY + 4, width: 32, height: 20)
            let badgeColor = info.missing ? PlatformColor.srgb(red: 0.54, green: 0.33, blue: 0, alpha: 1)
                : info.isPDF ? PlatformColor.srgb(red: 0xB8 / 255, green: 0x3A / 255, blue: 0x26 / 255, alpha: 1) : PlatformColor.srgb(red: 0x3E / 255, green: 0x4C / 255, blue: 0x5A / 255, alpha: 1)
            PlatformBezierPath.rounded(badge, radius: 6).fill(badgeColor)
            let label = NSAttributedString(string: info.badge, attributes: [.font: PlatformFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: PlatformColor.white])
            label.draw(at: CGPoint(x: badge.midX - label.size().width / 2, y: badge.midY - label.size().height / 2))
        }
    }

    private func roundedRect(_ r: CGRect, radius: CGFloat, top: Bool, bottom: Bool) -> PlatformBezierPath {
        // flipped coordinates: minY is the top
        let path = PlatformBezierPath()
        let tl = top ? radius : 0, bl = bottom ? radius : 0
        path.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        path.lineTo(CGPoint(x: r.maxX - tl, y: r.minY))
        if top { path.arc(center: CGPoint(x: r.maxX - tl, y: r.minY + tl), radius: tl, startDegrees: 270, endDegrees: 0) }
        path.lineTo(CGPoint(x: r.maxX, y: r.maxY - bl))
        if bottom { path.arc(center: CGPoint(x: r.maxX - bl, y: r.maxY - bl), radius: bl, startDegrees: 0, endDegrees: 90) }
        path.lineTo(CGPoint(x: r.minX + bl, y: r.maxY))
        if bottom { path.arc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startDegrees: 90, endDegrees: 180) }
        path.lineTo(CGPoint(x: r.minX, y: r.minY + tl))
        if top { path.arc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startDegrees: 180, endDegrees: 270) }
        path.close()
        return path
    }
}

/// What the fragment draws for an attachment chip.
public struct ChipInfo: Sendable {
    public var badge: String
    public var isPDF: Bool
    public var missing: Bool
    public init(badge: String, isPDF: Bool, missing: Bool) {
        self.badge = badge
        self.isPDF = isPDF
        self.missing = missing
    }
}
