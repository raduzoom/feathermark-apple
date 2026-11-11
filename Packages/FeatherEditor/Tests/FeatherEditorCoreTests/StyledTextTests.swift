import FeatherEditorCore
import FeatherEditorTestSupport
import Foundation
import Testing

/// Phase 12: the iPhone and iPad reader shows a whole note styled with no caret.
@MainActor @Suite struct StyledTextTests {
    private func font(_ s: NSAttributedString, _ i: Int) -> PlatformFont? { s.attribute(.font, at: i, effectiveRange: nil) as? PlatformFont }
    private func hidden(_ s: NSAttributedString, _ i: Int) -> Bool { s.attribute(.featherHidden, at: i, effectiveRange: nil) as? Bool == true }

    @Test func styledTextKeepsTextAndHidesEveryMarker() throws {
        for (name, text) in Corpus.all() {
            let s = MarkdownStyler.styledText(text, theme: .standard)
            #expect(Array(s.string.utf16) == Array(text.utf16), "\(name) changed")
        }
        let text = "# Title\n\nSome **bold** and `code`.\n- [ ] task\n> quote"
        let s = MarkdownStyler.styledText(text, theme: .standard)
        let ns = text as NSString
        func each(_ sub: String, from: Int = 0) -> [Int] {
            var found: [Int] = []
            var r = ns.range(of: sub, range: NSRange(location: from, length: ns.length - from))
            while r.location != NSNotFound {
                found.append(contentsOf: r.location..<NSMaxRange(r))
                let next = NSMaxRange(r)
                r = ns.range(of: sub, range: NSRange(location: next, length: ns.length - next))
            }
            return found
        }
        let markers = [0, 1] + each("**") + each("`")
        for i in markers {
            #expect(hidden(s, i), "marker at \(i) is shown")
            #expect(font(s, i) == EditorTheme.standard.hidden, "marker at \(i) has a visible font")
        }
        #expect(font(s, 2) == EditorTheme.standard.h1)
    }

    @Test func noCaretRevealsNothingAtTheStart() {
        let s = MarkdownStyler.styledText("**bold** start", theme: .standard)
        #expect(hidden(s, 0) && hidden(s, 1))
    }

    @Test func chipInfoFromFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FNChip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func file(_ name: String) throws -> URL {
            let url = dir.appending(path: name)
            try Data("x".utf8).write(to: url)
            return url
        }
        let missing = ChipInfo(file: dir.appending(path: "gone.pdf"))
        #expect(missing.badge == "?" && missing.missing && !missing.isPDF)
        let none = ChipInfo(file: nil)
        #expect(none.badge == "?" && none.missing)
        let pdf = ChipInfo(file: try file("scan.pdf"))
        #expect(pdf.badge == "PDF" && pdf.isPDF && !pdf.missing)
        #expect(ChipInfo(file: try file("notes")).badge == "FILE")
        #expect(ChipInfo(file: try file("archive.tar.gz")).badge == "GZ")
        #expect(ChipInfo(file: try file("slides.keynote")).badge == "KEYN")
    }
}
