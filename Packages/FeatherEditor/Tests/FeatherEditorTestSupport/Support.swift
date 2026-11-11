#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import FeatherEditorCore
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

/// A deterministic note of about `words` words using every construct (the performance and styling tests).
public func generatedNote(words: Int, seed: UInt64 = 7) -> String {
    var rng = SplitMix64(state: seed)
    let a = ["ka", "lo", "mi", "ne", "ru", "sa", "te", "vi"]
    let b = ["ber", "cal", "dun", "fen", "gor"]
    let c = ["a", "e", "i", "o", "u"]
    var vocab: [String] = []
    for i in 0..<200 {
        let first: String = a[i % 8]
        let second: String = b[(i / 8) % 5]
        let third: String = c[(i / 40) % 5]
        vocab.append(first + second + third)
    }
    func w() -> String { vocab[Int.random(in: 0..<vocab.count, using: &rng)] }
    func sentence(_ n: Int) -> String {
        (0..<n).map { i -> String in
            switch Int.random(in: 0..<30, using: &rng) {
            case 0: return "**\(w())**"
            case 1: return "*\(w())*"
            case 2: return "`\(w())`"
            case 3: return "[\(w())](https://example.com/\(i))"
            default: return w()
            }
        }.joined(separator: " ")
    }
    var out: [String] = []
    var count = 0
    var i = 0
    while count < words {
        switch i % 12 {
        case 0: out.append("## " + sentence(4)); count += 4
        case 3: out.append((0..<5).map { _ in "- " + sentence(8) }.joined(separator: "\n")); count += 40
        case 5: out.append((0..<4).map { j in "- [\(j % 2 == 0 ? " " : "x")] " + sentence(6) }.joined(separator: "\n")); count += 24
        case 7: out.append("> " + sentence(30)); count += 30
        case 9: out.append("```swift\nlet \(w()) = \"\(w())\" // \(w())\nfunc \(w())() {}\n```"); count += 8
        case 11: out.append("---"); count += 0
        default: out.append(sentence(60)); count += 60
        }
        i += 1
    }
    return out.joined(separator: "\n\n")
}

/// A solid-colour PNG of the given pixel size, in a new temporary file.
public func makePNG(width: Int, height: Int) -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "FNImg-\(UUID().uuidString).png")
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return url
}

/// Waits while yielding the main actor, so background loads can land.
@MainActor public func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 3) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
