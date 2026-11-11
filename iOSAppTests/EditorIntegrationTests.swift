import FeatherAppModel
import FeatherCore
import FeatherEditorPhone
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import FeatherMarkiOS

/// The editor wired to the model the way the app shows it (Phase 13 Task 8).
@MainActor @Suite(.serialized) struct EditorIntegrationTests {
    /// Shows the detail column for `model` in a window of the app's scene; returns the window to keep it alive.
    func show(_ model: AppModel) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: NavigationStack { NoteDetailColumn(model: model) })
        window.makeKeyAndVisible()
        return window
    }

    func editorView(in view: UIView) -> PhoneEditorView? {
        if let e = view as? PhoneEditorView { return e }
        for sub in view.subviews { if let e = editorView(in: sub) { return e } }
        return nil
    }

    func waitUntil(_ timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func seededModel() async throws -> AppModel {
        let model = try await AppBootstrap.makeModel(arguments: ["app", "-FeatherTemporaryLibrary", "-FeatherSeedDemo"])
        await model.load()
        return model
    }

    @Test func typingThenSwitchingNoteKeepsBoth() async throws {
        let model = try await seededModel()
        let a = try #require(model.notes.first { $0.title == "Groceries" }).id
        let b = try #require(model.notes.first { $0.title == "Bread notes" }).id
        await model.selectNote(a)
        let window = try show(model)
        defer { window.isHidden = true }
        var editor: PhoneEditorView?
        #expect(await waitUntil { editor = editorView(in: window); return editor?.textStorage.string.hasPrefix("- [ ] Oat milk") == true })
        let view = try #require(editor)
        view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
        view.insertText("\n- [ ] Pears")
        await model.selectNote(b)
        // SwiftUI may give the new note a new editor view: look it up again
        #expect(await waitUntil { editor = editorView(in: window); return editor?.textStorage.string.hasPrefix("Starter fed") == true })
        let viewB = try #require(editor)
        viewB.selectedRange = NSRange(location: viewB.textStorage.length, length: 0)
        viewB.insertText("\nRest overnight.")
        await model.flush()
        let noteA = try #require(try await model.library.note(a))
        let noteB = try #require(try await model.library.note(b))
        #expect(noteA.body == "- [ ] Oat milk\n- [ ] Lemons\n- [x] Rye flour\n- [ ] Pears")
        #expect(noteB.body.hasSuffix("- Fold every 30 minutes for 2 hours\nRest overnight."))
    }

    @Test func titleEditsReachTheModel() async throws {
        let model = try await seededModel()
        let a = try #require(model.notes.first { $0.title == "Groceries" }).id
        await model.selectNote(a)
        let window = try show(model)
        defer { window.isHidden = true }
        var editor: PhoneEditorView?
        #expect(await waitUntil { editor = editorView(in: window); return editor?.title == "Groceries" })
        let view = try #require(editor)
        view.titleView.selectedRange = NSRange(location: 9, length: 0)
        view.titleView.insertText(" for Sunday")
        await model.flush()
        #expect(try await model.library.note(a)?.title == "Groceries for Sunday")
    }

    @Test func newNoteFocusesTitle() async throws {
        let model = try await seededModel()
        await model.newNote()
        #expect(model.titleWantsFocus)
        let window = try show(model)
        defer { window.isHidden = true }
        var editor: PhoneEditorView?
        #expect(await waitUntil { editor = editorView(in: window); return editor?.titleView.isFirstResponder == true })
        #expect(await waitUntil { !model.titleWantsFocus }, "the model heard the title took focus")
        editor?.titleView.resignFirstResponder()
    }

    @Test func trashedNoteIsReadOnly() async throws {
        let model = try await seededModel()
        await model.select(.trash)
        let draft = try #require(model.notes.first { $0.title == "Old draft" }).id
        await model.selectNote(draft)
        let window = try show(model)
        defer { window.isHidden = true }
        var editor: PhoneEditorView?
        #expect(await waitUntil { editor = editorView(in: window); return editor?.textStorage.length ?? 0 > 0 })
        let view = try #require(editor)
        #expect(view.isReadOnly && !view.isEditable && !view.titleView.isEditable)
    }

    /// Review fix: a keystroke in the app restyles its paragraph, not the note (SwiftUI updates the editor on every
    /// change; a theme set on each update restyled everything).
    @Test func keystrokeInTheAppRestylesItsParagraphOnly() async throws {
        let model = try await seededModel()
        let a = try #require(model.notes.first { $0.title == "Weather station build" }).id
        await model.selectNote(a)
        let window = try show(model)
        defer { window.isHidden = true }
        var editor: PhoneEditorView?
        #expect(await waitUntil { editor = editorView(in: window); return editor?.textStorage.string.hasPrefix("Goal:") == true })
        let view = try #require(editor)
        #expect(await waitUntil { view.isFullyStyled })
        try? await Task.sleep(for: .milliseconds(200))
        view.selectedRange = NSRange(location: 4, length: 0)
        try? await Task.sleep(for: .milliseconds(200))
        let before = view.restyledCharacters
        view.insertText("x")
        try? await Task.sleep(for: .milliseconds(300))   // the model's change reaches SwiftUI, which updates the editor
        let restyled = view.restyledCharacters - before
        #expect(restyled < 200, "a keystroke restyled \(restyled) of \(view.textStorage.length) characters")
    }
}
