import Foundation
@testable import FeatherEditorCore

/// A styled run's range and attribute names, without the font and colour objects (those differ by platform).
struct RunShape: Equatable, CustomStringConvertible {
    var range: NSRange
    var keys: [String]
    init(_ location: Int, _ length: Int, _ keys: [String]) {
        range = NSRange(location: location, length: length)
        self.keys = keys
    }
    var description: String { "\(range.location)+\(range.length) \(keys)" }
}

enum StylerFixtures {
    /// `MarkdownStyler.runs` in live mode for "# Title\n\n- [ ] task **bold** `code`\n> quote\n", caret after
    /// the text. Recorded from the macOS editor before FeatherEditorCore was split out (2026-11-10).
    static let liveRuns: [RunShape] = [
        .init(0, 2, ["NSColor", "NSFont", "NSParagraphStyle", "featherHidden"]),
        .init(2, 5, ["NSColor", "NSFont", "NSParagraphStyle"]),
        .init(7, 2, ["NSColor", "NSFont", "NSParagraphStyle"]),
        .init(9, 6, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration", "featherHidden"]),
        .init(15, 5, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration"]),
        .init(20, 2, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration", "featherHidden"]),
        .init(22, 4, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration"]),
        .init(26, 2, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration", "featherHidden"]),
        .init(28, 1, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration"]),
        .init(29, 1, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration", "featherHidden"]),
        .init(30, 4, ["NSBackgroundColor", "NSColor", "NSFont", "NSParagraphStyle", "featherDecoration"]),
        .init(34, 1, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration", "featherHidden"]),
        .init(35, 1, ["NSColor", "NSFont", "NSParagraphStyle"]),
        .init(36, 2, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration", "featherHidden"]),
        .init(38, 5, ["NSColor", "NSFont", "NSParagraphStyle", "featherDecoration"]),
        .init(43, 1, ["NSColor", "NSFont", "NSParagraphStyle"]),
    ]
}

/// Every run `MarkdownStyler.runs` sets on `text` in live mode with the caret after it, as range and sorted keys.
func styledRuns(_ text: String) -> [RunShape] {
    let doc = MarkdownParser.parse(text)
    let whole = NSRange(location: 0, length: (text as NSString).length)
    return MarkdownStyler.runs(text: text, document: doc, selection: NSRange(location: whole.length + 1, length: 0),
                               mode: .live, theme: .standard, in: whole)
        .map { RunShape($0.range.location, $0.range.length, $0.attributes.keys.map(\.rawValue).sorted()) }
}
