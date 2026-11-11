// Tests of the AppKit editor view: macOS only.
#if os(macOS)
import AppKit
import FeatherEditorTestSupport
import Testing
@testable import FeatherEditor
@testable import FeatherEditorCore

/// Phase 4 deferred minors (Phase 5 Task 6) that need the AppKit view; the cache's own tests are in FeatherEditorCoreTests.
@MainActor @Suite struct ImageCacheTests {
    @Test func imageLoadRestylesOnlyItsBlock() async {
        let png = makePNG(width: 400, height: 200)
        let text = String(repeating: "Paragraph with some words in it.\n\n", count: 300) + "![p](feather://attachment/IMG)\n"
        let tv = EditorTextView.make()
        tv.setFrameSize(NSSize(width: 800, height: 600))
        tv.resolveAttachment = { $0 == "feather://attachment/IMG" ? png : nil }
        tv.load(text)
        _ = await waitFor({ tv.isFullyStyled }, timeout: 15)
        tv.restyledCharacters = 0
        _ = await waitFor({ tv.imageCache.image(for: png) != nil && tv.restyledCharacters > 0 }, timeout: 15)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(tv.restyledCharacters > 0 && tv.restyledCharacters < 2_000, "restyled \(tv.restyledCharacters)")
    }

    @Test func pastedImageTempFilesAreRemoved() async throws {
        let tv = makeView("")
        var pasted: URL?
        var existedDuringImport = false
        tv.importFiles = { urls in
            pasted = urls.first
            existedDuringImport = urls.first.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            return []
        }
        let pb = NSPasteboard(name: NSPasteboard.Name("FNPaste-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setData(try Data(contentsOf: makePNG(width: 4, height: 4)), forType: .png)
        _ = tv.readSelection(from: pb, type: .png)
        _ = await waitFor({ pasted != nil }, timeout: 15)
        let file = try #require(pasted)
        #expect(existedDuringImport)   // the import can still read it
        #expect(await waitFor({ !FileManager.default.fileExists(atPath: file.path) }, timeout: 5))   // gone once it finished
    }
}
#endif
