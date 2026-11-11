import FeatherEditorPhone
import Foundation
import Testing
import UIKit
@testable import FeatherMarkiOS

/// The iPhone editor's speed budgets (spec "FeatherEditorPhone"): open a 50k-word note under 300 ms; keystroke median
/// under 8 ms and p99 under 16 ms. Hosted by the app, so the same test runs on a device with the team's signing:
///
///     TEST_RUNNER_FEATHER_PERF=1 xcodebuild test -project FeatherNote.xcodeproj -scheme FeatherMarkiOS -configuration Release
///       -destination 'platform=iOS,name=<iPhone>' -allowProvisioningUpdates -only-testing:FeatherMarkiOSTests/EditorPerformanceTests
///       ENABLE_TESTABILITY=YES
///
/// (`TEST_RUNNER_FEATHER_PERF=1` reaches the test as `FEATHER_PERF=1`; `ENABLE_TESTABILITY=YES` lets the Release test
/// target import the app.) Without it, the budgets are 10× (debug only catches
/// large regressions). Each test prints its numbers with the device and OS.
@MainActor @Suite(.serialized) struct EditorPerformanceTests {
    static let enforced = ProcessInfo.processInfo.environment["FEATHER_PERF"] == "1"
    static let scale: Double = enforced ? 1 : 10
    static let budget = (open: 300.0 * scale, median: 8.0 * scale, p99: 16.0 * scale)

    func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    func percentile(_ xs: [Double], _ p: Double) -> Double {
        let s = xs.sorted()
        return s[min(s.count - 1, Int(Double(s.count) * p))]
    }

    func report(_ line: String) {
        let d = UIDevice.current
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "simulator \($0)" } ?? d.model
        FileHandle.standardError.write(Data("PERF \(line) — \(model), \(d.systemName) \(d.systemVersion)\(Self.enforced ? "" : " (debug budgets)")\n".utf8))
    }

    /// An editor in a 390 × 844 window, as on an iPhone.
    func editorInWindow() throws -> (UIWindow, PhoneEditorView) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let editor = PhoneEditorView.make()
        editor.frame = window.bounds
        window.rootViewController!.view.addSubview(editor)
        return (window, editor)
    }

    func open(_ editor: PhoneEditorView, _ text: String) {
        editor.load(text)
        editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
        editor.layoutIfNeeded()
    }

    @Test func openFiftyThousandWords() throws {
        let text = PerfNote.generated(words: 50_000)
        let (window, editor) = try editorInWindow()
        defer { window.isHidden = true }
        open(editor, "warm up **TextKit** and the fonts\n\n- [ ] once")
        open(editor, text)   // warm-up of the long note
        var times: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<5 {
            editor.load("")
            times.append(ms(clock.measure { open(editor, text) }))
        }
        let median = percentile(times, 0.5)
        report(String(format: "open 50k words: median %.1f ms (%@)", median, times.map { String(format: "%.0f", $0) }.joined(separator: ", ")))
        #expect(median < Self.budget.open, "open \(median) ms, budget \(Self.budget.open) ms")
        #expect(editor.textStorage.string == text)
    }

    @Test func keystrokesInALongNote() async throws {
        let text = PerfNote.generated(words: 50_000)
        let (window, editor) = try editorInWindow()
        defer { window.isHidden = true }
        open(editor, text)
        // style the whole note first, as after a few seconds of reading
        // (a nested run loop can't run the main queue from inside a main-actor test: wait instead)
        while !editor.isFullyStyled { try? await Task.sleep(for: .milliseconds(10)) }
        var rng = PerfNote.RNG(state: 3)
        var times: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<500 {
            let at = Int.random(in: 0..<editor.textStorage.length, using: &rng)
            editor.selectedRange = NSRange(location: at, length: 0)
            let at2 = editor.selectedRange.location
            // insertText restyles its block and reports the change before it returns
            times.append(ms(clock.measure { editor.insertText("x") }))
            #expect(editor.selectedRange.location == at2 + 1)
        }
        let median = percentile(times, 0.5), p99 = percentile(times, 0.99)
        report(String(format: "keystroke: median %.2f ms, p99 %.2f ms (500 keystrokes)", median, p99))
        #expect(median < Self.budget.median, "median \(median) ms")
        #expect(p99 < Self.budget.p99, "p99 \(p99) ms")
    }

    @Test func incrementalParseStillMatches() throws {
        let text = PerfNote.generated(words: 5_000)
        let (window, editor) = try editorInWindow()
        defer { window.isHidden = true }
        open(editor, text)
        var rng = PerfNote.RNG(state: 9)
        for _ in 0..<200 {
            editor.selectedRange = NSRange(location: Int.random(in: 0..<editor.textStorage.length, using: &rng), length: 0)
            editor.insertText(["x", "\n", "**", "- ", "`"].randomElement(using: &rng)!)
        }
        #expect(editor.document == MarkdownParser.parse(editor.textStorage.string))
    }
}

/// The FeatherEditor package's generated note and RNG (its test support isn't a product the app can import).
enum PerfNote {
    struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A deterministic note of about `words` words using every construct (the same as the Mac's benchmark note).
    static func generated(words: Int, seed: UInt64 = 7) -> String {
        var rng = RNG(state: seed)
        let a = ["ka", "lo", "mi", "ne", "ru", "sa", "te", "vi"]
        let b = ["ber", "cal", "dun", "fen", "gor"]
        let c = ["a", "e", "i", "o", "u"]
        var vocab: [String] = []
        for i in 0..<200 { vocab.append(a[i % 8] + b[(i / 8) % 5] + c[(i / 40) % 5]) }
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
}
