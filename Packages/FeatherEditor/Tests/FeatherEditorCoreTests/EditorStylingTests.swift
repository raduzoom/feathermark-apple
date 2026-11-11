import FeatherEditorTestSupport
import Foundation
import Testing
@testable import FeatherEditorCore

/// The restyle scheduler both editor views use (Phase 13): what to style at open, per keystroke, per caret move
/// and in the background.
@Suite struct EditorStylingTests {
    static func replace(_ text: String, _ range: NSRange, _ with: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: with)
    }

    @Test func loadStylesTheCaretWindowFirst() {
        let text = generatedNote(words: 30_000)
        let length = (text as NSString).length
        #expect(length > 150_000)
        let caret = length / 2
        let styling = EditorStyling(text: "")
        let now = styling.load(text: text, caret: caret)
        let covered = now.reduce(0) { $0 + $1.length }
        #expect(now.contains { $0.location <= caret - 8_192 && NSMaxRange($0) >= caret + 8_192 }, "\(now)")
        #expect(covered <= EditorStyling.eagerLength + 2_000)
        #expect(!styling.isFullyStyled)
        #expect(styling.unstyled.count == length - covered)
        var seen = IndexSet()
        now.forEach { seen.insert(integersIn: $0.location..<NSMaxRange($0)) }
        while let chunk = styling.nextChunk() {
            #expect(chunk.length <= EditorStyling.chunkLength + 2_000)
            let r = chunk.location..<NSMaxRange(chunk)
            #expect(!seen.intersects(integersIn: r), "styled twice: \(chunk)")
            seen.insert(integersIn: r)
        }
        #expect(styling.isFullyStyled)
        #expect(seen == IndexSet(integersIn: 0..<length))
    }

    @Test func chunksStartNearTheCaret() {
        let text = generatedNote(words: 30_000)
        let length = (text as NSString).length
        let styling = EditorStyling(text: "")
        let window = styling.load(text: text, caret: length / 2)[0]
        let first = try! #require(styling.nextChunk())
        // right next to the window, on either side
        #expect(first.location == NSMaxRange(window) || NSMaxRange(first) == window.location, "\(first) vs \(window)")
    }

    @Test func emptyNoteHasNothingToStyle() {
        let styling = EditorStyling(text: "")
        #expect(styling.load(text: "", caret: 0).allSatisfy { $0.length == 0 })
        #expect(styling.isFullyStyled)
        #expect(styling.nextChunk() == nil)
    }

    @Test func keystrokeRestylesItsBlockOnly() throws {
        let text = generatedNote(words: 50_000)
        let styling = EditorStyling(text: "")
        _ = styling.load(text: text, caret: 0)
        // a paragraph in the middle of the note
        let middle = (text as NSString).length / 2
        let paragraph = try #require(styling.document.blocks.first { b in
            b.range.location > middle && b.kind == .paragraph
        })
        let at = paragraph.range.location + 3
        let new = Self.replace(text, NSRange(location: at, length: 0), "x")
        let region = styling.edit(range: NSRange(location: at, length: 0), replacementLength: 1, newText: new)
        // the paragraph, the typed character and the blank line after it (the parser's safe boundary)
        #expect(region.length <= paragraph.range.length + 1 + 2, "\(region) for a \(paragraph.range.length)-character paragraph")
        #expect(region.location <= at && NSMaxRange(region) >= at + 1)
        #expect(styling.takePendingEdit() == region)
        #expect(styling.takePendingEdit() == nil)
    }

    @Test func caretJumpRestylesBothBlocks() {
        let text = "# Title\n\nSome text here.\n\n- one\n- two\n\nEnd."
        let ns = text as NSString
        let styling = EditorStyling(text: "")
        _ = styling.load(text: text, caret: 0)
        let heading = styling.document.blocks[0].range
        let item = styling.document.blocks.first { if case .listItem = $0.kind { return true }; return false }!.range
        let ranges = styling.selectionChanged(from: NSRange(location: 3, length: 0), to: NSRange(location: ns.range(of: "one").location + 1, length: 0))
        #expect(ranges == [heading, item])
    }

    @Test func pendingEditIsRestyledWithTheCaretMove() {
        let text = "one\n\ntwo\n\nthree"
        let styling = EditorStyling(text: "")
        _ = styling.load(text: text, caret: 0)
        let new = Self.replace(text, NSRange(location: 5, length: 0), "x")
        let region = styling.edit(range: NSRange(location: 5, length: 0), replacementLength: 1, newText: new)
        let ranges = styling.selectionChanged(from: NSRange(location: 5, length: 0), to: NSRange(location: 6, length: 0))
        #expect(ranges.contains { NSIntersectionRange($0, region) == region })
        #expect(styling.takePendingEdit() == nil)
    }

    /// Mirrors a view: edits mark their new characters unstyled until the returned region is styled; chunks style
    /// the rest. Afterwards nothing may be left unstyled that the scheduler thinks is done.
    @Test func editsDuringBackgroundStylingStayAligned() {
        var text = generatedNote(words: 30_000)
        var done = [Bool](repeating: false, count: (text as NSString).length)
        func mark(_ r: NSRange) { for i in r.location..<NSMaxRange(r) where i < done.count { done[i] = true } }
        let styling = EditorStyling(text: "")
        styling.load(text: text, caret: 2_000).forEach(mark)
        var rng = SplitMix64(state: 5)
        for step in 0..<60 {
            if step % 3 == 0, let chunk = styling.nextChunk() { mark(chunk) }
            let length = (text as NSString).length
            let at = Int.random(in: 0..<length, using: &rng)
            let del = Int.random(in: 0...min(40, length - at), using: &rng)
            let ins = ["x", "", "**b**", "\n\n", "- a\n"].randomElement(using: &rng)!
            let range = (text as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: at, length: del))
            text = Self.replace(text, range, ins)
            let insLength = (ins as NSString).length
            done.replaceSubrange(range.location..<NSMaxRange(range), with: [Bool](repeating: false, count: insLength))
            mark(styling.edit(range: range, replacementLength: insLength, newText: text))
            _ = styling.takePendingEdit()
        }
        while let chunk = styling.nextChunk() { mark(chunk) }
        #expect(styling.isFullyStyled)
        #expect(done.allSatisfy { $0 }, "unstyled characters left: \(done.indices.filter { !done[$0] }.prefix(5))")
    }

    @Test func incrementalParseMatchesFullParse() {
        var rng = SplitMix64(state: 21)
        let alphabet = ["a", " ", "\n", "\n\n", "**", "`", "```", "- ", "> ", "# ", "[x](y)", "\r\n"]
        for (name, original) in Corpus.all() {
            var text = original
            let styling = EditorStyling(text: "")
            _ = styling.load(text: text, caret: 0)
            for step in 0..<200 {
                let ns = text as NSString
                let at = Int.random(in: 0...ns.length, using: &rng)
                let del = Bool.random(using: &rng) ? 0 : Int.random(in: 0...min(5, ns.length - at), using: &rng)
                let range = del == 0 ? NSRange(location: at, length: 0) : ns.rangeOfComposedCharacterSequences(for: NSRange(location: at, length: del))
                let ins = alphabet.randomElement(using: &rng)!
                text = Self.replace(text, range, ins)
                _ = styling.edit(range: range, replacementLength: (ins as NSString).length, newText: text)
                if styling.document != MarkdownParser.parse(text) {
                    Issue.record("\(name) step \(step): diverged")
                    break
                }
            }
        }
    }
}

/// The caret never rests inside hidden syntax (the Mac's `adjustedSelection`, shared).
@Suite struct EditorSelectionTests {
    /// "- item": the "- " (0..<2) is hidden.
    let hidden: (Int) -> Bool = { $0 < 2 }

    @Test func directionOfTravel() {
        #expect(EditorSelection.adjusted(NSRange(location: 1, length: 0), from: NSRange(location: 0, length: 0), hidden: hidden, length: 6).location == 2)
        #expect(EditorSelection.adjusted(NSRange(location: 1, length: 0), from: NSRange(location: 3, length: 0), hidden: hidden, length: 6).location == 0)
        // no direction: the nearer edge
        #expect(EditorSelection.adjusted(NSRange(location: 1, length: 0), from: NSRange(location: 1, length: 0), hidden: hidden, length: 6).location == 0)
    }

    @Test func caretNeverRestsInHiddenRun() {
        // "a **bold** b": "**" at 2..<4 and 8..<10 hidden
        let marks: Set<Int> = [2, 3, 8, 9]
        let isHidden: (Int) -> Bool = { marks.contains($0) }
        for p in 0...12 {
            for from in [0, 12] {
                let r = EditorSelection.adjusted(NSRange(location: p, length: 0), from: NSRange(location: from, length: 0), hidden: isHidden, length: 12)
                #expect(!(isHidden(r.location - 1) && isHidden(r.location)), "caret \(p) from \(from) → \(r.location)")
            }
        }
    }

    @Test func selectionAcrossHiddenTakesItWhole() {
        // "- one\n- two": hidden 0..<2 and 6..<8; a selection from 1 to 7 widens to 0..<8
        let isHidden: (Int) -> Bool = { $0 < 2 || ($0 >= 6 && $0 < 8) }
        let r = EditorSelection.adjusted(NSRange(location: 1, length: 6), from: NSRange(location: 1, length: 0), hidden: isHidden, length: 11)
        #expect(r == NSRange(location: 0, length: 8))
    }

    @Test func outsideHiddenRunsNothingMoves() {
        let r = NSRange(location: 4, length: 1)
        #expect(EditorSelection.adjusted(r, from: .init(location: 0, length: 0), hidden: { _ in false }, length: 6) == r)
    }
}

/// Pasted and dropped files: each snippet on its own line, the note's line ending kept (the Mac's rule, shared).
@Suite struct AttachmentSnippetTests {
    func insert(_ snippets: [String], _ text: String, at range: NSRange) -> String? {
        guard let e = EditorCommands.attachmentSnippets(snippets, text: text, at: range) else { return nil }
        return (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }

    @Test func attachmentSnippetsKeepLineEndings() {
        #expect(insert(["![a](A)", "[b](B)"], "before\nafter", at: NSRange(location: 6, length: 0)) == "before\n![a](A)\n[b](B)\nafter")
        #expect(insert(["![a](x)"], "hello\r\nnext", at: NSRange(location: 5, length: 0)) == "hello\r\n![a](x)\r\nnext")
        #expect(insert(["[x](X)"], "", at: NSRange(location: 0, length: 0)) == "[x](X)")
        // mid-line: on a line of their own
        #expect(insert(["[x](X)"], "ab\r\ncd", at: NSRange(location: 1, length: 0)) == "a\r\n[x](X)\r\nb\r\ncd")
        // at a line start: above the line
        #expect(insert(["[x](X)"], "ab\ncd", at: NSRange(location: 3, length: 0)) == "ab\n[x](X)\ncd")
        #expect(insert([], "ab", at: NSRange(location: 0, length: 0)) == nil)
    }

    @Test func caretGoesAfterTheSnippets() throws {
        let e = try #require(EditorCommands.attachmentSnippets(["[x](X)"], text: "ab", at: NSRange(location: 2, length: 0)))
        #expect(e.selection == NSRange(location: 2 + ("\n[x](X)" as NSString).length, length: 0))
    }
}
