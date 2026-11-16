// Tests of the AppKit editor view: macOS only.
#if os(macOS)
import AppKit
import FeatherEditorTestSupport
import Testing
@testable import FeatherEditor
@testable import FeatherEditorCore

/// Continuity Camera: "Scan Documents" delivers a PDF on its own pasteboard; each page becomes a JPEG in the note.
/// Serialized: the note-switch test counts the `FeatherScan-*` temporary folders, which only these tests make.
@MainActor @Suite(.serialized) struct ScanTests {
    func onePagePDF() -> Data { pdf(pages: 1) }

    func pdf(pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(x: 20, y: 20, width: 100, height: 20))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// What Continuity Camera's scanner hands the view: PDF data alone, on a pasteboard of its own.
    func scanPasteboard(_ data: Data) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("FNScan-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setData(data, forType: .pdf)
        return pb
    }

    /// Imports each file as an image (or file) link, as the app's importer does, and records what it was given.
    final class Importer {
        var received: [URL] = []
        func callAsFunction(_ urls: [URL]) -> [String] {
            received += urls
            return urls.enumerated().map { i, url in
                let bang = url.pathExtension == "jpg" ? "!" : ""
                return "\(bang)[\(url.lastPathComponent)](feather://attachment/01S\(i))"
            }
        }
    }

    func scanFolders() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("FeatherScan-") })
    }

    @Test func scanBecomesImages() async {
        let tv = makeView("Receipt:")
        tv.setSelectedRange(NSRange(location: 8, length: 0))
        let importer = Importer()
        tv.importFiles = { importer($0) }
        #expect(tv.readSelection(from: scanPasteboard(onePagePDF()), type: .pdf))
        _ = await waitFor({ tv.string.contains("feather://") }, timeout: 15)
        #expect(importer.received.count == 1)
        let name = importer.received.first?.lastPathComponent ?? ""
        #expect(name.range(of: #"^Scan \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.jpg$"#, options: .regularExpression) != nil, "named \(name)")
        #expect(tv.string.contains("![Scan "))
    }

    @Test func twoPageScanBecomesTwoImageLinesInOneUndo() async {
        let tv = makeView("Receipt:")
        tv.setSelectedRange(NSRange(location: 8, length: 0))
        let importer = Importer()
        tv.importFiles = { importer($0) }
        #expect(tv.readSelection(from: scanPasteboard(pdf(pages: 2)), type: .pdf))
        _ = await waitFor({ tv.string.contains("feather://") }, timeout: 15)
        let names = importer.received.map(\.lastPathComponent)
        #expect(names.count == 2 && names.first?.hasSuffix(" (1).jpg") == true && names.last?.hasSuffix(" (2).jpg") == true, "\(names)")
        let lines = tv.string.components(separatedBy: "\n")
        #expect(lines.count == 3 && lines[0] == "Receipt:", "\(lines)")
        #expect(lines.count == 3 && lines[1].hasPrefix("![Scan ") && lines[1].contains("(1).jpg") && lines[2].contains("(2).jpg"))
        tv.undoManager?.undo()
        #expect(tv.string == "Receipt:")
    }

    @Test func blockMenuScanLandsAsImageBlock() async {
        let tv = makeView("hello\nnext")
        let importer = Importer()
        tv.importFiles = { importer($0) }
        tv.presentsMenus = false
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        tv.pickBlock(.scan)
        #expect(tv.readSelection(from: scanPasteboard(pdf(pages: 2)), type: .pdf))
        _ = await waitFor({ tv.string.contains("feather://") }, timeout: 15)
        #expect(tv.string.hasPrefix("hello\n\n![Scan ") && tv.string.hasSuffix("\n\nnext"), "\(tv.string)")
        #expect(tv.string.contains("(1).jpg") && tv.string.contains("(2).jpg"))
    }

    @Test func scanAfterNoteSwitchIsDropped() async {
        let before = scanFolders()
        let tv = makeView("Receipt:")
        tv.setSelectedRange(NSRange(location: 8, length: 0))
        let importer = Importer()
        tv.importFiles = { importer($0) }
        #expect(tv.readSelection(from: scanPasteboard(pdf(pages: 2)), type: .pdf))
        tv.load("Other")
        _ = await waitFor({ false }, timeout: 2)   // let the pages render and the result come back
        #expect(importer.received.isEmpty)
        #expect(tv.string == "Other")
        #expect(scanFolders().subtracting(before).isEmpty, "temporary scan folder left behind")
    }

    @Test func unreadableScanFallsBackToPDF() async {
        let tv = makeView("")
        let importer = Importer()
        tv.importFiles = { importer($0) }
        #expect(tv.readSelection(from: scanPasteboard(Data("not a pdf".utf8)), type: .pdf))
        _ = await waitFor({ !importer.received.isEmpty }, timeout: 15)
        #expect(importer.received.count == 1 && importer.received.first?.pathExtension == "pdf")
    }

    /// A PDF dragged or pasted in stays a PDF; only the scanner's own pasteboard is a scan. (The drag pasteboard
    /// stands in for the general one, so the test never wipes the clipboard.)
    @Test func draggedPDFStaysPDF() async {
        let tv = makeView("")
        let importer = Importer()
        tv.importFiles = { importer($0) }
        let pb = NSPasteboard(name: .drag)
        pb.clearContents()
        pb.setData(pdf(pages: 2), forType: .pdf)
        #expect(tv.readSelection(from: pb, type: .pdf))
        _ = await waitFor({ !importer.received.isEmpty }, timeout: 15)
        #expect(importer.received.count == 1 && importer.received.first?.pathExtension == "pdf")
    }

    @Test func continuityRequestorAcceptsImagesAndPDF() {
        let tv = makeView("")
        #expect(tv.validRequestor(forSendType: nil, returnType: .pdf) as AnyObject? === tv)
        #expect(tv.validRequestor(forSendType: nil, returnType: .png) as AnyObject? === tv)
        #expect(tv.validRequestor(forSendType: nil, returnType: .tiff) as AnyObject? === tv)
        #expect(tv.validRequestor(forSendType: nil, returnType: .string) as AnyObject? !== tv)
    }
}

/// The right-click menu offers Continuity Camera (Take Photo, Scan Documents, Add Sketch) where the caret is.
@MainActor @Suite struct ScanMenuTests {
    @Test func editorContextMenuOffersContinuityCamera() throws {
        let tv = makeView("Receipt:")
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [],
                                                    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(tv.menu(for: event))
        #expect(menu.items.contains { $0.identifier == NSMenuItem.importFromDeviceIdentifier })
    }
}
#endif
