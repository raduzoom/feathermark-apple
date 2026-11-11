// Tests of the UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorTestSupport
import Testing
import UIKit
@testable import FeatherEditorCore
@testable import FeatherEditorPhone

/// Attachments from Photos and Files: imports that finish later land where they were asked for, in the note
/// they were asked for, or nowhere.
@MainActor @Suite(.serialized) struct PhoneAttachmentTests {
    /// A temporary file, as the app's picker makes one.
    func madeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "FNPick-\(UUID().uuidString).png")
        try Data(contentsOf: makePNG(width: 4, height: 4)).write(to: url)
        return url
    }

    @Test func importAfterNoteSwitchIsDropped() async throws {
        let editor = makeEditor("first note")
        editor.selectedRange = NSRange(location: 5, length: 0)
        var finished = false
        editor.importFiles = { _ in
            try? await Task.sleep(for: .milliseconds(300))
            finished = true
            return ["![](feather://attachment/01A)"]
        }
        let file = try madeFile()
        editor.requestAttachment(.photoLibrary)
        editor.attachPicked([file], cleaningUp: [file])
        editor.load("other note")
        #expect(await waitFor({ finished }, timeout: 5))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(editor.textStorage.string == "other note")
        #expect(!FileManager.default.fileExists(atPath: file.path), "the temporary copy is gone")
    }

    @Test func typingDuringImportMovesTheInsertionPoint() async throws {
        let editor = makeEditor("abc")
        editor.selectedRange = NSRange(location: 3, length: 0)
        editor.importFiles = { _ in
            try? await Task.sleep(for: .milliseconds(300))
            return ["[x.pdf](feather://attachment/01X)"]
        }
        editor.requestAttachment(.files)
        editor.attachPicked([try madeFile()], cleaningUp: [])
        editor.selectedRange = NSRange(location: 0, length: 0)
        editor.insertText("12345")
        #expect(await waitFor({ editor.textStorage.string.contains("01X") }, timeout: 5))
        #expect(editor.textStorage.string == "12345abc\n[x.pdf](feather://attachment/01X)")
    }

    @Test func snippetsInsertAsOneUndoStep() async throws {
        let editor = makeEditor("before\nafter")
        editor.selectedRange = NSRange(location: 6, length: 0)
        editor.importFiles = { _ in ["![a](feather://attachment/01A)", "[b.pdf](feather://attachment/01B)"] }
        editor.requestAttachment(.files)
        editor.attachPicked([try madeFile(), try madeFile()], cleaningUp: [])
        #expect(await waitFor({ editor.textStorage.string != "before\nafter" }, timeout: 5))
        #expect(editor.textStorage.string == "before\n![a](feather://attachment/01A)\n[b.pdf](feather://attachment/01B)\nafter")
        editor.undoManager?.undo()
        #expect(editor.textStorage.string == "before\nafter")
    }

    @Test func cancelledPickInsertsNothing() async throws {
        let editor = makeEditor("abc")
        var imported = false
        editor.importFiles = { _ in imported = true; return ["x"] }
        editor.requestAttachment(.photoLibrary)
        editor.attachPicked([], cleaningUp: [])
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!imported)
        #expect(editor.textStorage.string == "abc")
        #expect(editor.anchors.isEmpty, "the anchor is let go")
    }

    @Test func imagesRenderOnceLoaded() async throws {
        let png = makePNG(width: 400, height: 200)
        let text = String(repeating: "Paragraph with some words in it.\n\n", count: 200) + "![p](feather://attachment/IMG)\n"
        let editor = PhoneEditorView.make()
        editor.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        editor.resolveAttachment = { $0 == "feather://attachment/IMG" ? png : nil }
        let imageAt = (text as NSString).range(of: "![p]").location
        editor.load(text)
        #expect(await waitFor({ editor.isFullyStyled }, timeout: 10))
        editor.restyledCharacters = 0
        #expect(await waitFor({ editor.imageCache.image(for: png) != nil && editor.restyledCharacters > 0 }, timeout: 10))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(editor.restyledCharacters > 0 && editor.restyledCharacters < 2_000, "restyled \(editor.restyledCharacters)")
        // the block now reserves the image's height at the measure (400 × 200 shown 358 wide: 179 high)
        let frag = try #require(fragment(editor, at: imageAt))
        #expect(frag.layoutFragmentFrame.height > 170, "\(frag.layoutFragmentFrame)")
    }

    @Test func temporaryFilesAreRemoved() async throws {
        let editor = makeEditor("abc")
        // success
        editor.importFiles = { _ in ["[f](feather://attachment/01F)"] }
        let ok = try madeFile()
        editor.requestAttachment(.files)
        editor.attachPicked([ok], cleaningUp: [ok])
        #expect(await waitFor({ !FileManager.default.fileExists(atPath: ok.path) }, timeout: 5))
        // failure: nothing imported
        editor.importFiles = { _ in [] }
        let bad = try madeFile()
        editor.requestAttachment(.files)
        editor.attachPicked([bad], cleaningUp: [bad])
        #expect(await waitFor({ !FileManager.default.fileExists(atPath: bad.path) }, timeout: 5))
        #expect(editor.temporaryFiles.isEmpty)
        // cancelled: the copies made for it go too
        let cancelled = try madeFile()
        editor.requestAttachment(.files)
        editor.attachPicked([], cleaningUp: [cancelled])
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
    }
}
#endif
