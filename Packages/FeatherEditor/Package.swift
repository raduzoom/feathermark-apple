// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatherEditor",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        // The parser, styler, commands and TextKit 2 layout fragment, for macOS and iOS. Names only Platform* types.
        .library(name: "FeatherEditorCore", targets: ["FeatherEditorCore"]),
        // The AppKit editor view (macOS); re-exports FeatherEditorCore. Its files compile to nothing on iOS.
        .library(name: "FeatherEditor", targets: ["FeatherEditor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "FeatherEditorCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "FeatherEditor", dependencies: ["FeatherEditorCore"]),
        // The Markdown corpus and helpers both test targets use (public API only, so release test runs build it).
        .target(name: "FeatherEditorTestSupport", dependencies: ["FeatherEditorCore"],
                path: "Tests/FeatherEditorTestSupport", resources: [.copy("Fixtures")]),
        .testTarget(name: "FeatherEditorCoreTests", dependencies: ["FeatherEditorCore", "FeatherEditorTestSupport"]),
        .testTarget(name: "FeatherEditorTests", dependencies: ["FeatherEditor", "FeatherEditorTestSupport"]),
    ]
)
