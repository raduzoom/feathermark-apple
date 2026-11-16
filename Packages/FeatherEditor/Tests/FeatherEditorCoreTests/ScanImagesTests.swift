import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import FeatherEditorCore

/// A scan becomes one JPEG per page (Mac: rendered from the scanner's PDF; iPhone: VisionKit's page images).
@Suite struct ScanImagesTests {
    /// A PDF with one page per media box, each with a small black mark so it isn't empty.
    func pdf(pages: [CGSize], mark: Bool = true) -> Data {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)!
        for size in pages {
            var box = CGRect(origin: .zero, size: size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            if mark {
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    func decode(_ data: Data) -> (type: String, image: CGImage)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(src) as String?,
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (type, image)
    }

    /// RGB of the top-left pixel.
    func cornerPixel(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return Array(px[0..<3])
    }

    @Test func twoPagesGiveTwoJPEGs() throws {
        let pages = ScanImages.jpegPages(fromPDF: pdf(pages: [CGSize(width: 200, height: 300), CGSize(width: 300, height: 200)]))
        #expect(pages.count == 2)
        let first = try #require(decode(pages[0]))
        let second = try #require(decode(pages[1]))
        #expect(first.type == "public.jpeg" && second.type == "public.jpeg")
        #expect(first.image.height > first.image.width, "first page is portrait")
        #expect(second.image.width > second.image.height, "second page is landscape")
    }

    @Test func pageRendersAt300DPI() throws {
        let page = try #require(ScanImages.jpegPages(fromPDF: pdf(pages: [CGSize(width: 144, height: 72)])).first)
        let image = try #require(decode(page)).image
        #expect(image.width == 600 && image.height == 300, "\(image.width) × \(image.height)")
    }

    @Test func longEdgeIsCapped() throws {
        let page = try #require(ScanImages.jpegPages(fromPDF: pdf(pages: [CGSize(width: 612, height: 792)])).first)
        let image = try #require(decode(page)).image
        #expect(image.height == 3000)
        #expect(abs(image.width - 2318) <= 1, "width \(image.width)")
    }

    @Test func rotatedPageRendersUpright() throws {
        let doc = try #require(PDFDocument(data: pdf(pages: [CGSize(width: 200, height: 300)])))
        doc.page(at: 0)?.rotation = 90
        let rotated = try #require(doc.dataRepresentation())
        let page = try #require(ScanImages.jpegPages(fromPDF: rotated).first)
        let image = try #require(decode(page)).image
        #expect(image.width > image.height, "\(image.width) × \(image.height)")
    }

    @Test func blankPageIsWhite() throws {
        let page = try #require(ScanImages.jpegPages(fromPDF: pdf(pages: [CGSize(width: 100, height: 100)], mark: false)).first)
        let rgb = cornerPixel(try #require(decode(page)).image)
        #expect(rgb.allSatisfy { $0 >= 250 }, "corner is \(rgb)")
    }

    @Test func unreadableDataGivesNoPages() {
        #expect(ScanImages.jpegPages(fromPDF: Data("not a pdf".utf8)).isEmpty)
        #expect(ScanImages.jpegPages(fromPDF: Data()).isEmpty)
    }

    /// A page that can't render (here an empty media box) must not be skipped: the caller then keeps the PDF.
    @Test func pageThatFailsToRenderDropsTheWholeScan() {
        let data = pdf(pages: [CGSize(width: 200, height: 300), CGSize(width: 0, height: 300)])
        #expect(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.numberOfPages == 2)
        #expect(ScanImages.jpegPages(fromPDF: data).isEmpty)
    }

    @Test func jpegFromLargeImageIsCapped() throws {
        let ctx = CGContext(data: nil, width: 4000, height: 6000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 6000))
        let data = try #require(ScanImages.jpeg(from: ctx.makeImage()!))
        let decoded = try #require(decode(data))
        #expect(decoded.type == "public.jpeg")
        #expect(decoded.image.width == 2000 && decoded.image.height == 3000, "\(decoded.image.width) × \(decoded.image.height)")
    }

    @Test func namesUseLocalTime() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Bucharest"))
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute) = (2026, 11, 15, 10, 42)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try #require(calendar.date(from: parts))
        #expect(ScanImages.fileNames(count: 1, at: date, timeZone: zone) == ["Scan 2026-11-15 10.42.jpg"])
        #expect(ScanImages.fileNames(count: 3, at: date, timeZone: zone) ==
                ["Scan 2026-11-15 10.42 (1).jpg", "Scan 2026-11-15 10.42 (2).jpg", "Scan 2026-11-15 10.42 (3).jpg"])
        #expect(ScanImages.photoName(at: date, timeZone: zone) == "Photo 2026-11-15 10.42.jpg")
    }
}
