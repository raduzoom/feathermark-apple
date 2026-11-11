import Foundation

/// An inline format the formatting bar and ⌘B / ⌘I toggle.
public enum InlineFormat: Sendable, CaseIterable {
    case bold, italic, code

    public var marker: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .code: "`"
        }
    }

    var kind: InlineKind {
        switch self {
        case .bold: .strong
        case .italic: .emphasis
        case .code: .code
        }
    }
}

/// What is on at the caret, for the formatting bar's selected buttons.
public struct ActiveFormats: Equatable, Sendable {
    public var inline: Set<InlineFormat>
    /// 1–6, or 0 for body text.
    public var heading: Int
    public var checklist: Bool
    public var bulleted: Bool
    /// In a fenced or indented code block.
    public var code: Bool

    public init(inline: Set<InlineFormat> = [], heading: Int = 0, checklist: Bool = false, bulleted: Bool = false, code: Bool = false) {
        self.inline = inline
        self.heading = heading
        self.checklist = checklist
        self.bulleted = bulleted
        self.code = code
    }
}

extension EditorCommands {
    /// A span counts as under the selection when it holds it; an empty selection must be strictly inside, so a
    /// caret just after "**b**" is outside the bold.
    static func span(_ inline: Inline, holds selection: NSRange) -> Bool {
        let r = inline.range
        if selection.length == 0 { return selection.location > r.location && selection.location < NSMaxRange(r) }
        return selection.location >= r.location && NSMaxRange(selection) <= NSMaxRange(r)
    }

    /// Bold, italic or inline code: unwraps the innermost span of that format holding the selection, otherwise
    /// wraps the selection (each line's text separately, block markers and surrounding spaces left outside) or,
    /// with nothing selected, inserts the pair with the caret between. Nil inside a code block.
    public static func toggleInline(_ format: InlineFormat, text: String, document: MarkdownDocument, selection: NSRange) -> Edit? {
        guard codeContent(document, containing: selection.location) == nil else { return nil }
        let s = text as NSString
        let spans = document.blocks.flatMap(\.inlines).filter { $0.kind == format.kind && $0.markers.count == 2 && span($0, holds: selection) }
        if let inner = spans.min(by: { $0.range.length < $1.range.length }) {
            return unwrap(inner, s: s, selection: selection)
        }
        return wrap(format, s: s, selection: selection)
    }

    private static func unwrap(_ span: Inline, s: NSString, selection: NSRange) -> Edit {
        let open = span.markers[0], close = span.markers[1]
        let content = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
        func moved(_ p: Int) -> Int {
            if p <= open.location { return p }
            if p < NSMaxRange(open) { return open.location }
            if p <= close.location { return p - open.length }
            if p < NSMaxRange(close) { return close.location - open.length }
            return p - open.length - close.length
        }
        let start = moved(selection.location), end = moved(NSMaxRange(selection))
        return Edit(range: span.range, replacement: s.substring(with: content), selection: NSRange(location: start, length: end - start))
    }

    private static func wrap(_ format: InlineFormat, s: NSString, selection: NSRange) -> Edit {
        var marker = format.marker
        if format == .code {
            // a run longer than any backtick run inside, so the code span holds them
            let selected = s.substring(with: selection)
            var longest = 0, run = 0
            for c in selected { run = c == "`" ? run + 1 : 0; longest = max(longest, run) }
            marker = String(repeating: "`", count: longest + 1)
        }
        let m = (marker as NSString).length
        var pieces: [NSRange] = []
        var p = selection.location
        let end = NSMaxRange(selection)
        while true {
            let l = line(s, at: p)
            let parts = splitMarkers(l.text)
            let textStart = l.range.location + (parts.indent + parts.markers).utf16.count
            var a = max(p, textStart), b = min(end, NSMaxRange(l.range))
            while a < b, isSpace(s.character(at: a)) { a += 1 }
            while b > a, isSpace(s.character(at: b - 1)) { b -= 1 }
            if b > a { pieces.append(NSRange(location: a, length: b - a)) }
            let next = NSMaxRange(l.range) + l.ending.utf16.count
            if l.ending.isEmpty || next > end || next <= p { break }
            p = next
        }
        guard let first = pieces.first, let last = pieces.last else {
            let at = selection.location
            return Edit(range: NSRange(location: at, length: 0), replacement: marker + marker, selection: NSRange(location: at + m, length: 0))
        }
        var replacement = ""
        var cursor = first.location
        for piece in pieces {
            replacement += s.substring(with: NSRange(location: cursor, length: piece.location - cursor))
            replacement += marker + s.substring(with: piece) + marker
            cursor = NSMaxRange(piece)
        }
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let selStart = first.location + m
        let selEnd = NSMaxRange(last) + (2 * pieces.count - 1) * m
        return Edit(range: range, replacement: replacement, selection: NSRange(location: selStart, length: selEnd - selStart))
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    /// Link: the selection becomes `[selection](https://)` with `https://` selected, so typing replaces it; with
    /// nothing selected, `[](https://)` with the caret between the brackets.
    public static func link(text: String, selection: NSRange) -> Edit {
        let s = text as NSString
        let label = s.substring(with: selection)
        let placeholder = "https://"
        let replacement = "[" + label + "](" + placeholder + ")"
        if selection.length == 0 {
            return Edit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + 1, length: 0))
        }
        let url = selection.location + 1 + selection.length + 2
        return Edit(range: selection, replacement: replacement, selection: NSRange(location: url, length: (placeholder as NSString).length))
    }

    /// Sets the caret line's heading level (0 = body text), replacing any heading, quote or list markers, as the
    /// block menu does. The caret stays on the same character of the line's text.
    public static func heading(_ level: Int, text: String, caret: Int) -> Edit {
        let s = text as NSString
        let l = line(s, at: caret)
        let parts = splitMarkers(l.text)
        let oldPrefix = (parts.indent + parts.markers).utf16.count
        let newPrefix = parts.indent + (level > 0 ? String(repeating: "#", count: min(level, 6)) + " " : "")
        let inText = max(0, caret - l.range.location - oldPrefix)
        return Edit(range: NSRange(location: l.range.location, length: oldPrefix), replacement: newPrefix,
                    selection: NSRange(location: l.range.location + newPrefix.utf16.count + inText, length: 0))
    }

    /// The formats on at the selection's start (inline spans holding the selection, and the caret's block).
    public static func activeFormats(document: MarkdownDocument, text: String, selection: NSRange) -> ActiveFormats {
        var formats = ActiveFormats()
        for inline in document.blocks.flatMap(\.inlines) where span(inline, holds: selection) {
            if let f = InlineFormat.allCases.first(where: { $0.kind == inline.kind }) { formats.inline.insert(f) }
        }
        let p = selection.location
        formats.code = codeContent(document, containing: p) != nil
        if let block = document.blocks.first(where: { p >= $0.range.location && p <= NSMaxRange($0.range) }) {
            switch block.kind {
            case .heading(let level): formats.heading = level
            case .listItem(let ordered, _, let box):
                formats.checklist = box != nil
                formats.bulleted = !ordered && box == nil
            case .codeBlock: formats.code = true
            default: break
            }
        }
        return formats
    }
}
