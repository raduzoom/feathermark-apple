import Foundation

/// Word-processor behaviour as pure text edits. Each returns nil when it doesn't apply (default handling then).
public enum EditorCommands {
    public struct Edit: Equatable, Sendable {
        public var range: NSRange
        public var replacement: String
        public var selection: NSRange
        public init(range: NSRange, replacement: String, selection: NSRange) {
            self.range = range
            self.replacement = replacement
            self.selection = selection
        }
    }

    public struct Line: Sendable {
        public var range: NSRange        // without the line ending
        public var ending: String        // "\n", "\r\n", "\r" or ""
        public var text: String
    }

    public static func line(_ s: NSString, at p: Int) -> Line {
        var start = min(p, s.length)
        while start > 0 { let c = s.character(at: start - 1); if c == 0x0A || c == 0x0D { break }; start -= 1 }
        var end = start
        while end < s.length { let c = s.character(at: end); if c == 0x0A || c == 0x0D { break }; end += 1 }
        var ending = ""
        if end < s.length {
            ending = s.character(at: end) == 0x0D && end + 1 < s.length && s.character(at: end + 1) == 0x0A ? "\r\n"
                : (s.character(at: end) == 0x0D ? "\r" : "\n")
        }
        let r = NSRange(location: start, length: end - start)
        return Line(range: r, ending: ending, text: s.substring(with: r))
    }

    /// A list item's first line: indentation, bullet ("-", "1."), spacing and checkbox.
    struct ItemMarker {
        var indent: String
        var bullet: String
        var spacing: String
        var checkbox: String?
        var length: Int { (indent + bullet + spacing + (checkbox ?? "")).utf16.count }
        var bulletWidth: Int { bullet.utf16.count + 1 }
    }

    static let itemPattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+|$)(\[[ xX]\][ \t]+|\[[ xX]\]$)?"#)

    static func itemMarker(_ line: Line) -> ItemMarker? {
        let ns = line.text as NSString
        guard let m = itemPattern.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        return ItemMarker(indent: g(1) ?? "", bullet: g(2) ?? "-", spacing: g(3) ?? "", checkbox: g(4))
    }

    static func codeContent(_ document: MarkdownDocument, containing p: Int) -> NSRange? {
        for b in document.blocks {
            if case .codeBlock(_, let content) = b.kind, p >= content.location, p <= NSMaxRange(content), content.length > 0 || p == content.location {
                return content
            }
        }
        return nil
    }

    static func leadingWhitespace(_ s: String) -> String { String(s.prefix { $0 == " " || $0 == "\t" }) }

    static func nextBullet(_ bullet: String) -> String {
        guard let last = bullet.last, last == "." || last == ")", let n = Int(bullet.dropLast()) else { return bullet }
        return "\(n + 1)\(last)"
    }

    // MARK: Commands

    public static func returnKey(text: String, document: MarkdownDocument, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let s = text as NSString
        let p = selection.location
        let l = line(s, at: p)
        let newline = l.ending.isEmpty ? previousEnding(s, before: l.range.location) : l.ending
        if codeContent(document, containing: p) != nil {
            let insert = newline + leadingWhitespace(l.text)
            return Edit(range: NSRange(location: p, length: 0), replacement: insert, selection: NSRange(location: p + insert.utf16.count, length: 0))
        }
        guard let m = itemMarker(l) else { return nil }
        let markerEnd = l.range.location + m.length
        guard p >= markerEnd else { return nil }
        let rest = s.substring(with: NSRange(location: markerEnd, length: NSMaxRange(l.range) - markerEnd))
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            // empty item: the list ends here
            return Edit(range: NSRange(location: l.range.location, length: NSMaxRange(l.range) - l.range.location), replacement: "",
                        selection: NSRange(location: l.range.location, length: 0))
        }
        let marker = m.indent + nextBullet(m.bullet) + (m.spacing.isEmpty ? " " : m.spacing) + (m.checkbox != nil ? "[ ] " : "")
        let insert = newline + marker
        return Edit(range: NSRange(location: p, length: 0), replacement: insert, selection: NSRange(location: p + insert.utf16.count, length: 0))
    }

    public static func tab(text: String, document: MarkdownDocument, selection: NSRange) -> Edit? {
        let s = text as NSString
        let p = selection.location
        if codeContent(document, containing: p) != nil {
            return Edit(range: selection, replacement: "    ", selection: NSRange(location: p + 4, length: 0))
        }
        let l = line(s, at: p)
        guard let m = itemMarker(l), let previous = previousItem(s, before: l.range.location) else { return nil }
        let target = previous.indent.utf16.count + previous.bulletWidth
        let current = m.indent.utf16.count
        guard target > current else { return nil }
        let add = String(repeating: " ", count: target - current)
        return Edit(range: NSRange(location: l.range.location, length: 0), replacement: add,
                    selection: NSRange(location: selection.location + add.utf16.count, length: selection.length))
    }

    public static func backtab(text: String, document: MarkdownDocument, selection: NSRange) -> Edit? {
        let s = text as NSString
        let p = selection.location
        let l = line(s, at: p)
        if codeContent(document, containing: p) != nil {
            let spaces = min(4, l.text.prefix { $0 == " " }.count)
            guard spaces > 0 else { return nil }
            return Edit(range: NSRange(location: l.range.location, length: spaces), replacement: "",
                        selection: NSRange(location: max(l.range.location, p - spaces), length: 0))
        }
        guard let m = itemMarker(l) else { return nil }
        let current = m.indent.utf16.count
        guard current > 0 else { return nil }
        var target = 0
        var start = l.range.location
        while start > 0 {
            let prev = line(s, at: start - 1)
            if prev.text.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if let pm = itemMarker(prev), pm.indent.utf16.count < current { target = pm.indent.utf16.count; break }
            start = prev.range.location
        }
        let remove = current - target
        return Edit(range: NSRange(location: l.range.location, length: remove), replacement: "",
                    selection: NSRange(location: max(l.range.location, p - remove), length: selection.length))
    }

    public static func backspaceAtItemStart(text: String, document: MarkdownDocument, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let s = text as NSString
        let p = selection.location
        guard codeContent(document, containing: p) == nil else { return nil }
        let l = line(s, at: p)
        var markerLength: Int?
        if let m = itemMarker(l) { markerLength = m.length }
        else if let q = l.text.range(of: #"^[ ]{0,3}(>[ ]?)+"#, options: .regularExpression) {
            markerLength = (String(l.text[q]) as NSString).length
        }
        guard let len = markerLength, len > 0, p == l.range.location + len else { return nil }
        return Edit(range: NSRange(location: l.range.location, length: len), replacement: "", selection: NSRange(location: l.range.location, length: 0))
    }

    public static func toggleCheckbox(text: String, document: MarkdownDocument, at location: Int) -> Edit? {
        for b in document.blocks where location >= b.range.location && location <= NSMaxRange(b.range) {
            guard case .listItem(_, _, let box?) = b.kind else { continue }
            switch box {
            case .unchecked(let r): return Edit(range: r, replacement: "[x]", selection: NSRange(location: NSMaxRange(r), length: 0))
            case .checked(let r): return Edit(range: r, replacement: "[ ]", selection: NSRange(location: NSMaxRange(r), length: 0))
            }
        }
        return nil
    }

    /// The code bar's language menu (specs/editor.md "Code bar"): label and id, the id written as the info string.
    public static let codeLanguages: [(label: String, id: String)] = [
        ("Plain text", ""), ("Bash", "bash"), ("C", "c"), ("C++", "cpp"), ("C#", "csharp"), ("CSS", "css"), ("Go", "go"),
        ("HTML", "html"), ("Java", "java"), ("JavaScript", "javascript"), ("JSON", "json"), ("Kotlin", "kotlin"),
        ("Markdown", "markdown"), ("PHP", "php"), ("Python", "python"), ("Ruby", "ruby"), ("Rust", "rust"), ("SQL", "sql"),
        ("Swift", "swift"), ("TypeScript", "typescript"), ("YAML", "yaml"),
    ]

    /// Replaces the info string of the fenced code block holding `location` with `language` ("" for none); the caret stays.
    public static func setCodeLanguage(text: String, document: MarkdownDocument, at location: Int, language: String, selection: NSRange) -> Edit? {
        let s = text as NSString
        for b in document.blocks where location >= b.range.location && location <= NSMaxRange(b.range) {
            guard case .codeBlock = b.kind, let open = b.markers.first else { continue }
            let l = line(s, at: open.location)
            guard let fence = l.text.range(of: #"^[ \t]*(`{3,}|~{3,})"#, options: .regularExpression) else { return nil }
            let from = l.range.location + (String(l.text[fence]) as NSString).length
            let old = NSRange(location: from, length: NSMaxRange(l.range) - from)
            guard s.substring(with: old) != language else { return nil }
            let delta = (language as NSString).length - old.length
            func shift(_ p: Int) -> Int { p <= from ? p : p >= NSMaxRange(old) ? p + delta : from + (language as NSString).length }
            let a = shift(selection.location), e = shift(NSMaxRange(selection))
            return Edit(range: old, replacement: language, selection: NSRange(location: a, length: e - a))
        }
        return nil
    }

    /// Down arrow on the last line of a fenced code block that ends the note (only blank lines after it): the caret
    /// goes to the line below, and a line break is added first when the note ends at the block.
    public static func leaveCodeBlock(text: String, document: MarkdownDocument, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let s = text as NSString
        let p = selection.location
        for b in document.blocks where p >= b.range.location && p <= NSMaxRange(b.range) {
            guard case .codeBlock(_, let c) = b.kind, b.markers.count == 2 else { continue }
            guard s.substring(from: NSMaxRange(b.range)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var end = NSMaxRange(c)
            while end > c.location, s.character(at: end - 1) == 0x0A || s.character(at: end - 1) == 0x0D { end -= 1 }
            guard p >= line(s, at: end).range.location else { return nil } // not on the last line yet
            let close = line(s, at: b.markers[1].location)
            let closeEnd = NSMaxRange(close.range)
            if !close.ending.isEmpty {
                let below = closeEnd + (close.ending as NSString).length
                return Edit(range: NSRange(location: below, length: 0), replacement: "", selection: NSRange(location: below, length: 0))
            }
            let ending = previousEnding(s, before: close.range.location)
            return Edit(range: NSRange(location: closeEnd, length: 0), replacement: ending,
                        selection: NSRange(location: closeEnd + (ending as NSString).length, length: 0))
        }
        return nil
    }

    public enum DeleteKey: Sendable { case backspace, delete }

    /// Backspace at the start of a fenced block's content, or Delete at its end, would join a hidden fence line: an
    /// edit that does nothing, or, for Backspace in a block of blank lines, one that removes the block.
    public static func codeFenceGuard(text: String, document: MarkdownDocument, selection: NSRange, key: DeleteKey) -> Edit? {
        guard selection.length == 0 else { return nil }
        let s = text as NSString
        let p = selection.location
        let caret = NSRange(location: p, length: 0)
        for b in document.blocks where p >= b.range.location && p <= NSMaxRange(b.range) {
            guard case .codeBlock(_, let c) = b.kind, !b.markers.isEmpty else { continue }
            if key == .backspace, p == c.location {
                if s.substring(with: c).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return Edit(range: b.range, replacement: "", selection: NSRange(location: b.range.location, length: 0))
                }
                return Edit(range: caret, replacement: "", selection: caret)
            }
            var end = NSMaxRange(c)
            while end > c.location, s.character(at: end - 1) == 0x0A || s.character(at: end - 1) == 0x0D { end -= 1 }
            if key == .delete, b.markers.count == 2, p == end, c.length > 0 { return Edit(range: caret, replacement: "", selection: caret) }
        }
        return nil
    }

    // MARK: Helpers

    static func previousItem(_ s: NSString, before lineStart: Int) -> ItemMarker? {
        var start = lineStart
        while start > 0 {
            let prev = line(s, at: start - 1)
            if prev.text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            if let m = itemMarker(prev) { return m }
            start = prev.range.location
        }
        return nil
    }

    public static func previousEnding(_ s: NSString, before lineStart: Int) -> String {
        guard lineStart > 0 else { return "\n" }
        if lineStart >= 2, s.character(at: lineStart - 2) == 0x0D, s.character(at: lineStart - 1) == 0x0A { return "\r\n" }
        return s.character(at: lineStart - 1) == 0x0D ? "\r" : "\n"
    }
}
