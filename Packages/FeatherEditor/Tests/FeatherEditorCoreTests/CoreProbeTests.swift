import FeatherEditorTestSupport
import Foundation
import Testing
@testable import FeatherEditorCore

/// Regression tests from the Phase 4 fresh review that need only the core (moved from the Mac view tests in
/// Phase 13, so they run on iOS too). Each was RED on the reviewed tree and pins one fixed finding.
// MARK: NestingLimit bypasses (checked without parsing, so they fail instead of crashing)

@Test func probeNestingLimitAfterBackslashLineBreak() {
    // a hard line break ("\" before LF) makes the next line's ">" skip the container-prefix scan
    let text = "a\\\n" + String(repeating: "> ", count: 200) + "x"
    let limited = NestingLimit.apply(text)
    #expect(!limited.utf8.elementsEqual(text.utf8), "no '>' past depth 32 was neutralised")
}

@Test func probeNestingLimitWithTabs() {
    for text in [String(repeating: ">\t", count: 200) + "x", String(repeating: "-\t", count: 200) + "x"] {
        #expect(!NestingLimit.apply(text).utf8.elementsEqual(text.utf8), "\(text.prefix(4).debugDescription): nothing neutralised")
    }
}

/// These overflowed the stack (and killed the process) before the NestingLimit fix.
@Test func probeCrashDeepTabQuotes() {
    #expect(!MarkdownParser.parse(String(repeating: ">\t", count: 200) + "x").blocks.isEmpty)
}

@Test func probeCrashDeepQuotesAfterHardBreak() {
    #expect(!MarkdownParser.parse("a\\\n" + String(repeating: "> ", count: 200) + "x").blocks.isEmpty)
}

// MARK: IncrementalParser

@Test func probeTypingHTMLCommentOpenerMatchesFullParse() {
    let t = "intro\n\npara one\n\npara two\n\n-->\n\nafter\n"
    let p = IncrementalParser(text: t)
    let n = "<!--\n" + t
    p.apply(edit: NSRange(location: 0, length: 0), replacementLength: 5, newText: n)
    #expect(p.document == MarkdownParser.parse(n))
}

@Test func probeRandomEditsWithHTMLAndDefinitions() {
    let alphabet = ["a", " ", "\n", "\n\n", "<!--", "-->", "<pre>", "</pre>", "[a]: u", "[a]", "\\", "\r\n", "> ", "- ", "```", "\t"]
    var failures = 0
    for seed in UInt64(1)...8 {
    var rng = SplitMix64(state: seed)
    for (name, original) in Corpus.all() {
        let parser = IncrementalParser(text: original)
        var text = original as NSString
        for step in 0..<300 {
            let length = text.length
            let start = Int.random(in: 0...length, using: &rng)
            let del = Bool.random(using: &rng) ? 0 : Int.random(in: 0...min(6, length - start), using: &rng)
            let ins = alphabet.randomElement(using: &rng)!
            let edit = length == 0 ? NSRange(location: 0, length: 0)
                : (del == 0 ? NSRange(location: start, length: 0)
                   : text.rangeOfComposedCharacterSequences(for: NSRange(location: min(start, length - 1), length: del)))
            let newText = text.replacingCharacters(in: edit, with: ins) as NSString
            parser.apply(edit: edit, replacementLength: (ins as NSString).length, newText: newText as String)
            if parser.referenceDefinitionCount != IncrementalParser.countReferenceDefinitions(newText) {
                Issue.record("\(name) step \(step): definition count \(parser.referenceDefinitionCount) vs \(IncrementalParser.countReferenceDefinitions(newText))")
                failures += 1
                break
            }
            if parser.document != MarkdownParser.parse(newText as String) {
                Issue.record("\(name) step \(step): edit \(edit) insert \(ins.debugDescription)")
                let full = MarkdownParser.parse(newText as String).blocks, inc = parser.document.blocks
                for i in 0..<max(full.count, inc.count) where i >= inc.count || i >= full.count || inc[i] != full[i] {
                    perf("DIFF \(i): inc \(i < inc.count ? "\(inc[i])" : "-")\n   full \(i < full.count ? "\(full[i])" : "-")")
                    if i > 3 { break }
                }
                perf("BEFORE \((text as String).debugDescription)")
                failures += 1
                break
            }
            text = newText
        }
    }
    }
    #expect(failures == 0)
}

@Test func probeTypingCodeWithBlankLineAtEndOfNote() {
    // writing a code block at the end of a note, one keystroke at a time, with a blank line inside it
    let start = "Notes\n\n"
    let typed = "```python\nimport os\n\n# list the files\nprint(os.listdir())\n```\n"
    let p = IncrementalParser(text: start)
    var text = start as NSString
    for ch in typed {
        let s = String(ch) as NSString
        let newText = text.replacingCharacters(in: NSRange(location: text.length, length: 0), with: s as String) as NSString
        p.apply(edit: NSRange(location: text.length, length: 0), replacementLength: s.length, newText: newText as String)
        text = newText
        if p.document != MarkdownParser.parse(text as String) {
            Issue.record("diverged after typing \(text.debugDescription): incremental \(p.document.blocks.map { "\($0.kind) \($0.range)" })")
            return
        }
    }
}
