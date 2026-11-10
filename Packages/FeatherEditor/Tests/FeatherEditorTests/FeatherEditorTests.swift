// Tests of the AppKit editor view: macOS only.
#if os(macOS)
import Testing
@testable import FeatherEditor
@testable import FeatherEditorCore

@Test func moduleNameIsSet() {
    #expect(FeatherEditor.moduleName == "FeatherEditor")
}
#endif
