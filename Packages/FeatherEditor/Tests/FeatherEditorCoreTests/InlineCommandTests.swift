import FeatherEditorTestSupport
import Foundation
import Testing
@testable import FeatherEditorCore

/// The formatting bar's commands (Phase 13): bold, italic, inline code, link, headings and the active formats.
/// In the strings, "|" marks the caret and "«…»" the selection.
@Suite struct InlineCommandTests {
    static func parse(_ marked: String) -> (String, NSRange) {
        let ns = marked as NSString
        let open = ns.range(of: "«")
        if open.location != NSNotFound {
            let close = ns.range(of: "»")
            let text = ns.replacingCharacters(in: close, with: "") as NSString
            return (text.replacingCharacters(in: open, with: ""), NSRange(location: open.location, length: close.location - open.location - 1))
        }
        let bar = ns.range(of: "|")
        return (ns.replacingCharacters(in: bar, with: ""), NSRange(location: bar.location, length: 0))
    }

    static func show(_ text: String, _ selection: NSRange) -> String {
        let ns = text as NSString
        if selection.length == 0 { return ns.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "|") }
        let closed = ns.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "»") as NSString
        return closed.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "«")
    }

    static func apply(_ e: EditorCommands.Edit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }

    func toggle(_ format: InlineFormat, _ marked: String) -> String? {
        let (text, sel) = Self.parse(marked)
        guard let e = EditorCommands.toggleInline(format, text: text, document: MarkdownParser.parse(text), selection: sel) else { return nil }
        return Self.show(Self.apply(e, to: text), e.selection)
    }

    func link(_ marked: String) -> String {
        let (text, sel) = Self.parse(marked)
        let e = EditorCommands.link(text: text, selection: sel)
        return Self.show(Self.apply(e, to: text), e.selection)
    }

    func heading(_ level: Int, _ marked: String) -> String {
        let (text, sel) = Self.parse(marked)
        let e = EditorCommands.heading(level, text: text, caret: sel.location)
        return Self.show(Self.apply(e, to: text), e.selection)
    }

    func active(_ marked: String) -> ActiveFormats {
        let (text, sel) = Self.parse(marked)
        return EditorCommands.activeFormats(document: MarkdownParser.parse(text), text: text, selection: sel)
    }

    @Test func boldWrapsSelection() {
        #expect(toggle(.bold, "a «word» b") == "a **«word»** b")
    }

    @Test func boldOnEmptySelectionInsertsPair() {
        #expect(toggle(.bold, "a | b") == "a **|** b")
    }

    @Test func boldInsideBoldUnwraps() {
        #expect(toggle(.bold, "a **wo|rd** b") == "a wo|rd b")
        #expect(toggle(.bold, "a **«word»** b") == "a «word» b")
        #expect(toggle(.bold, "a «**word**» b") == "a «word» b")
    }

    @Test func italicAndCodeUseTheirMarkers() {
        #expect(toggle(.italic, "a «word» b") == "a *«word»* b")
        #expect(toggle(.code, "a «word» b") == "a `«word»` b")
        #expect(toggle(.italic, "**a «b» c**") == "**a *«b»* c**")
        #expect(toggle(.italic, "a *wo|rd* b") == "a wo|rd b")
        #expect(toggle(.code, "a `wo|rd` b") == "a wo|rd b")
        // a backtick inside the selection takes a longer run
        #expect(toggle(.code, "«a`b»") == "``«a`b»``")
    }

    @Test func wrappingSkipsSurroundingSpaces() {
        // "**word **" isn't bold in Markdown: the space stays outside
        #expect(toggle(.bold, "a« word »b") == "a **«word»** b")
    }

    @Test func multiLineSelectionWrapsEachLine() {
        #expect(toggle(.bold, "«one\ntwo»") == "**«one**\n**two»**")
        #expect(toggle(.bold, "«- one\n- two»") == "- **«one**\n- **two»**")
        #expect(toggle(.bold, "«one\n\ntwo»") == "**«one**\n\n**two»**")
    }

    @Test func crlfIsKept() {
        #expect(toggle(.bold, "«one\r\ntwo»") == "**«one**\r\n**two»**")
        #expect(link("«one»\r\ntwo") == "[one](«https://»)\r\ntwo")
        #expect(heading(2, "o|ne\r\ntwo") == "## o|ne\r\ntwo")
    }

    @Test func boldInsideCodeDoesNothing() {
        #expect(toggle(.bold, "```\nlet «x» = 1\n```") == nil)
    }

    @Test func linkWrapsSelection() {
        #expect(link("see «docs» here") == "see [docs](«https://») here")
    }

    @Test func linkOnEmptySelection() {
        #expect(link("see | here") == "see [|](https://) here")
    }

    @Test func headingSetsAndClears() {
        #expect(heading(2, "- it|em") == "## it|em")
        #expect(heading(0, "## t|") == "t|")
        #expect(heading(1, "### t|itle") == "# t|itle")
        #expect(heading(3, "pl|ain") == "### pl|ain")
        #expect(heading(1, "|") == "# |")
        #expect(heading(2, "- [ ] ta|sk") == "## ta|sk")
        // the caret inside the old marker lands at the content's start
        #expect(heading(0, "#|# t") == "|t")
    }

    @Test func activeFormatsAtCaret() {
        #expect(active("**a *b|* c**").inline == [.bold, .italic])
        #expect(active("a `c|ode` b").inline == [.code])
        #expect(active("plain| text").inline.isEmpty)
        #expect(active("## t|").heading == 2)
        #expect(active("plain|").heading == 0)
        #expect(active("- [ ] x|").checklist)
        #expect(active("- [ ] x|").bulleted == false)
        #expect(active("- x|").bulleted)
        #expect(active("1. x|").bulleted == false)
        #expect(active("```\nco|de\n```").code)
        #expect(active("plain|").code == false)
        // a caret right after a bold span is outside it
        #expect(active("**b**| c").inline.isEmpty)
    }

    @Test func commandsNeverTouchOtherLines() {
        var rng = SplitMix64(state: 13)
        for (name, text) in Corpus.all() {
            let ns = text as NSString
            guard ns.length > 0 else { continue }
            let doc = MarkdownParser.parse(text)
            for _ in 0..<50 {
                let a = Int.random(in: 0...ns.length, using: &rng)
                let b = min(ns.length, a + Int.random(in: 0...40, using: &rng))
                let sel = NSRange(location: a, length: b - a)
                var edits: [EditorCommands.Edit] = InlineFormat.allCases.compactMap {
                    EditorCommands.toggleInline($0, text: text, document: doc, selection: sel)
                }
                edits.append(EditorCommands.link(text: text, selection: sel))
                edits.append(EditorCommands.heading(2, text: text, caret: a))
                edits.append(EditorCommands.heading(0, text: text, caret: a))
                // the lines the selection touches, widened to the blocks it touches (a span can cross a soft break)
                var lo = EditorCommands.line(ns, at: a).range.location
                var hi = NSMaxRange(EditorCommands.line(ns, at: b).range)
                for block in doc.blocks where block.range.location <= b && NSMaxRange(block.range) >= a {
                    lo = min(lo, EditorCommands.line(ns, at: block.range.location).range.location)
                    hi = max(hi, NSMaxRange(EditorCommands.line(ns, at: NSMaxRange(block.range)).range))
                }
                for e in edits {
                    #expect(e.range.location >= lo && NSMaxRange(e.range) <= hi, "\(name): \(e) outside \(lo)..<\(hi)")
                    let changed = Self.apply(e, to: text)
                    let inverse = NSRange(location: e.range.location, length: (e.replacement as NSString).length)
                    let back = (changed as NSString).replacingCharacters(in: inverse, with: ns.substring(with: e.range))
                    #expect(back == text, "\(name)")
                    #expect(!e.replacement.unicodeScalars.contains("\r") || text.unicodeScalars.contains("\r"), "\(name): no new line-ending kind")
                    let newLength = (changed as NSString).length
                    #expect(e.selection.location >= 0 && NSMaxRange(e.selection) <= newLength, "\(name)")
                }
            }
        }
    }
}
