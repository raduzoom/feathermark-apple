import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A document scan becomes one JPEG per page. The Mac renders the pages of the PDF Continuity Camera's scanner
/// returns; the iPhone encodes VisionKit's page images. CoreGraphics and ImageIO only, so both platforms share it.
public enum ScanImages {
    public static let jpegQuality: CGFloat = 0.9
    /// Pages render at this many pixels per inch of the PDF page (72 points).
    public static let dpi: CGFloat = 300
    /// No image is larger than this on its long edge, so a receipt stays legible at a sensible size.
    public static let maxLongEdge: Int = 3000

    /// One JPEG per page, in order; empty when `data` isn't a readable PDF, has no pages, or any page fails to
    /// render, so the caller keeps the PDF rather than a scan with a page missing.
    public static func jpegPages(fromPDF data: Data) -> [Data] {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider) else { return [] }
        guard doc.numberOfPages > 0 else { return [] }
        var out: [Data] = []
        for index in 1...doc.numberOfPages {
            guard let page = doc.page(at: index), let image = render(page), let jpeg = encode(image) else { return [] }
            out.append(jpeg)
        }
        return out
    }

    /// One page image as a JPEG, scaled down so its long edge is at most `maxLongEdge`.
    public static func jpeg(from image: CGImage) -> Data? {
        let (w, h) = capped(CGFloat(image.width), CGFloat(image.height))
        if w == image.width, h == image.height { return encode(image) }
        guard let ctx = whiteContext(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage().flatMap(encode)
    }

    /// "Scan 2026-11-15 10.42.jpg" for one page; "Scan 2026-11-15 10.42 (1).jpg", "(2)"… for several. Local time.
    public static func fileNames(count: Int, at date: Date = Date(), timeZone: TimeZone = .current) -> [String] {
        let stamp = stamp(date, timeZone)
        if count == 1 { return ["Scan \(stamp).jpg"] }
        return count < 1 ? [] : (1...count).map { "Scan \(stamp) (\($0)).jpg" }
    }

    /// "Photo 2026-11-15 10.42.jpg", local time: a camera photo, named like a scan.
    public static func photoName(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "Photo \(stamp(date, timeZone)).jpg"
    }

    // MARK: private

    private static func stamp(_ date: Date, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f.string(from: date)
    }

    /// The page drawn upright on white, at `dpi`, capped at `maxLongEdge`.
    private static func render(_ page: CGPDFPage) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        let turned = (page.rotationAngle % 180 + 180) % 180 == 90
        let points = turned ? CGSize(width: box.height, height: box.width) : box.size
        guard points.width > 0, points.height > 0 else { return nil }
        let (w, h) = capped(points.width * dpi / 72, points.height * dpi / 72)
        guard let ctx = whiteContext(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .high
        // getDrawingTransform never scales up, so scale first and let it do only the rotation and the box origin
        ctx.scaleBy(x: CGFloat(w) / points.width, y: CGFloat(h) / points.height)
        ctx.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: points), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    /// Pixel size scaled down (never up) so the long edge is at most `maxLongEdge`.
    private static func capped(_ width: CGFloat, _ height: CGFloat) -> (Int, Int) {
        let factor = min(1, CGFloat(maxLongEdge) / max(width, height))
        return (max(1, Int((width * factor).rounded())), max(1, Int((height * factor).rounded())))
    }

    /// An opaque RGB bitmap filled white: JPEG has no alpha, and an unpainted page must not turn black.
    private static func whiteContext(width: Int, height: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    private static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
