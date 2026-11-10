#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import FeatherEditorCore
import Foundation
import Testing

/// The Markdown corpus (Fixtures/corpus/*.md). Every corpus test, on macOS and iOS, reads it from here.
public enum Corpus {
    public static var directory: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appending(path: "corpus") }

    public static func all() -> [(name: String, text: String)] {
        let files = try! FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.map { ($0.lastPathComponent, String(decoding: try! Data(contentsOf: $0), as: UTF8.self)) }
    }
}

/// Deterministic RNG so random edit sequences repeat.
public struct SplitMix64: RandomNumberGenerator {
    public var state: UInt64
    public init(state: UInt64) { self.state = state }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Prints a timing line to stderr, unbuffered, so it survives a run that is stopped.
public func perf(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

/// Styles `text` with the caret at `caret` and returns the storage, for reading attributes back.
@MainActor public func styled(_ text: String, caret: Int? = nil, mode: EditorMode = .live) -> NSTextStorage {
    let storage = NSTextStorage(string: text)
    let doc = MarkdownParser.parse(text)
    let whole = NSRange(location: 0, length: (text as NSString).length)
    let sel = NSRange(location: caret ?? (text as NSString).length + 1, length: 0)
    for run in MarkdownStyler.runs(text: text, document: doc, selection: sel, mode: mode, theme: .standard, in: whole) {
        storage.setAttributes(run.attributes.nsAttributes, range: run.range)
    }
    return storage
}

@MainActor public func isHidden(_ s: NSTextStorage, _ i: Int) -> Bool { s.attribute(.featherHidden, at: i, effectiveRange: nil) as? Bool == true }
@MainActor public func font(_ s: NSTextStorage, _ i: Int) -> PlatformFont { s.attribute(.font, at: i, effectiveRange: nil) as! PlatformFont }
@MainActor public func decoration(_ s: NSTextStorage, _ i: Int) -> Decoration? { s.attribute(.featherDecoration, at: i, effectiveRange: nil) as? Decoration }

/// Timing tests run on macOS only. The code is the same on both platforms, so the Mac measures its scaling;
/// the iOS simulator's timings swing 2–3× from run to run, and iOS budgets are measured on a device (Phase 13).
public let isMac: Bool = {
    #if os(macOS)
    true
    #else
    false
    #endif
}()

public let timingReason: Comment = "timing is measured on macOS; the iOS simulator's timings are too noisy to judge"
