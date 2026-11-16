import SwiftUI

/// What the hardware-keyboard commands do in the window that has focus; `RootView` publishes it.
struct FeatherCommandActions {
    var newNote: () -> Void
    var search: () -> Void
    /// Nil while no note is open.
    var toggleMarkdown: (() -> Void)?
}

extension FocusedValues {
    @Entry var featherCommands: FeatherCommandActions?
}

/// The Mac's shortcuts on an iPad keyboard (ipad-adaptation-notes "Keyboard"): ⌘N, ⌘F and ⇧⌘M here; ⌘B, ⌘I and ⌘K
/// come from the editor. Holding ⌘ lists them.
struct FeatherCommands: Commands {
    @FocusedValue(\.featherCommands) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { actions?.newNote() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Notes") { actions?.search() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }
        CommandMenu("Note") {
            Button("Markdown") { actions?.toggleMarkdown?() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(actions?.toggleMarkdown == nil)
        }
    }
}
