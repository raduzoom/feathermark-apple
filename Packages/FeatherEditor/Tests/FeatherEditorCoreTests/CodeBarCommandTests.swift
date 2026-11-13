import Foundation
import Testing
@testable import FeatherEditorCore

/// specs/editor.md "Code bar" (setCodeLanguage) and "Commands" (codeFenceGuard); the web's cases are the same.
@Suite struct CodeBarCommandTests {
    func language(_ t: String, _ at: Int, _ id: String) -> (String, NSRange)? {
        guard let e = EditorCommands.setCodeLanguage(text: t, document: MarkdownParser.parse(t), at: at, language: id,
                                                     selection: NSRange(location: at, length: 0)) else { return nil }
        return ((t as NSString).replacingCharacters(in: e.range, with: e.replacement), e.selection)
    }

    func guarded(_ t: String, _ p: Int, _ key: EditorCommands.DeleteKey) -> String? {
        guard let e = EditorCommands.codeFenceGuard(text: t, document: MarkdownParser.parse(t), selection: NSRange(location: p, length: 0), key: key)
        else { return nil }
        return (t as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }

    @Test func setsReplacesAndClearsTheInfoString() {
        let r = language("```\nx\n```", 4, "swift")
        #expect(r?.0 == "```swift\nx\n```" && r?.1 == NSRange(location: 9, length: 0))
        #expect(language("  ~~~~js  \nx\n~~~~", 11, "python")?.0 == "  ~~~~python\nx\n~~~~")
        #expect(language("```js\r\nx\r\n```", 7, "")?.0 == "```\r\nx\r\n```")
    }

    @Test func languageNothingOutsideAFencedBlockOrWhenUnchanged() {
        #expect(language("plain", 1, "go") == nil)
        #expect(language("    indented", 5, "go") == nil)
        #expect(language("```go\nx\n```", 6, "go") == nil)
        #expect(EditorCommands.codeLanguages.first?.label == "Plain text" && EditorCommands.codeLanguages.first?.id == "")
    }

    @Test func fenceGuard() {
        let t = "a\n\n```js\nx = 1\ny\n```\n\nb"
        #expect(guarded(t, 9, .backspace) == t)
        #expect(guarded(t, 16, .delete) == t)
        #expect(guarded(t, 10, .backspace) == nil)
        #expect(guarded(t, 15, .delete) == nil)
        #expect(guarded(t, 1, .backspace) == nil)
        #expect(guarded("a\n\n```\n\n```\n\nb", 7, .backspace) == "a\n\n\n\nb")
    }

    func leave(_ t: String, _ p: Int) -> (String, Int)? {
        guard let e = EditorCommands.leaveCodeBlock(text: t, document: MarkdownParser.parse(t), selection: NSRange(location: p, length: 0))
        else { return nil }
        return ((t as NSString).replacingCharacters(in: e.range, with: e.replacement), e.selection.location)
    }

    @Test func downLeavesACodeBlockAtTheNoteEnd() {
        let t = "a\n\n```js\nx = 1\ny\n```", n = (t as NSString).length
        #expect(leave(t, 15).map { [$0.0, String($0.1)] } == [t + "\n", String(n + 1)])
        #expect(leave(t, n).map { [$0.0, String($0.1)] } == [t + "\n", String(n + 1)])
        #expect(leave(t.replacingOccurrences(of: "\n", with: "\r\n"), n + 5)?.0.hasSuffix("```\r\n") == true)
        #expect(leave(t + "\n\n", 15).map { [$0.0, String($0.1)] } == [t + "\n\n", String(n + 1)])
        #expect(leave(t, 10) == nil)
        #expect(leave(t + "\n\nb", 15) == nil)
        #expect(leave("```\nx", 4) == nil)
    }
}
