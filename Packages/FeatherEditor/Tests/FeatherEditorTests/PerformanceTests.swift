// Tests of the AppKit editor view: macOS only.
#if os(macOS)
import AppKit
import FeatherEditorTestSupport
import Testing
@testable import FeatherEditor
@testable import FeatherEditorCore

func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

func percentile(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted()
    return s[min(s.count - 1, Int(Double(s.count) * p))]
}

#if DEBUG
let budget = (parse: 600.0, open: 1500.0, median: 40.0, p99: 160.0, scroll: 160.0, hostile: 5000.0)
#else
let budget = (parse: 60.0, open: 150.0, median: 4.0, p99: 16.0, scroll: 16.0, hostile: 1000.0)
#endif

@MainActor @Suite(.serialized) struct PerformanceTests {
    @Test(.timeLimit(.minutes(5))) func fiftyThousandWordsWithinBudget() async {
        let text = generatedNote(words: 50_000)
        let clock = ContinuousClock()
        let parse = ms(clock.measure { _ = MarkdownParser.parse(text) })

        // The first text view in a process pays ~80 ms of one-time AppKit and font setup; the app pays it once
        // at launch (measured with launch time), then reuses its editor for every note. Warm up first.
        EditorTextView.make().load("warm **up**")
        var tv: EditorTextView!
        let open = ms(clock.measure {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 800))
            tv = EditorTextView.make()
            tv.frame = scroll.bounds
            scroll.documentView = tv
            tv.load(text)
            tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        })

        var rng = SplitMix64(state: 11)
        var times: [Double] = []
        for _ in 0..<500 {
            let length = (tv.string as NSString).length
            let at = Int.random(in: 0..<length, using: &rng)
            let safe = (tv.string as NSString).rangeOfComposedCharacterSequence(at: at).location
            tv.setSelectedRange(NSRange(location: safe, length: 0))
            // Like real typing: each keystroke is its own event, with its own autorelease pool, and the
            // main queue runs between keystrokes (undo groups close, deferred work runs). Only the keystroke is timed.
            autoreleasepool {
                times.append(ms(clock.measure { tv.insertText("x", replacementRange: tv.selectedRange()) }))
            }
            await Task.yield()
        }
        let median = percentile(times, 0.5), p99 = percentile(times, 0.99)
        perf("PERF parse \(parse) ms, open \(open) ms, keystroke median \(median) ms p99 \(p99) ms")
        #expect(parse < budget.parse)
        #expect(open < budget.open)
        #expect(median < budget.median)
        #expect(p99 < budget.p99)
        #expect(tv.parser.document == MarkdownParser.parse(tv.string))
    }

    @Test(.timeLimit(.minutes(5))) func scrollingWithinBudget() {
        let text = generatedNote(words: 50_000)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 800))
        let tv = EditorTextView.make()
        tv.frame = scroll.bounds
        scroll.documentView = tv
        tv.load(text)
        let tlm = tv.textLayoutManager!
        tlm.ensureLayout(for: tlm.documentRange)
        let height = tlm.usageBoundsForTextContainer.height
        let clock = ContinuousClock()
        var times: [Double] = []
        for i in 0..<20 {
            let y = height * Double(i) / 20
            times.append(ms(clock.measure {
                tv.scroll(NSPoint(x: 0, y: y))
                tlm.textViewportLayoutController.layoutViewport()
                tv.display()
            }))
        }
        perf("PERF scroll max \(times.max()!) ms")
        #expect(times.max()! < budget.scroll)
    }

    @Test(.timeLimit(.minutes(5))) func hostileInputsStayWithinBudget() {
        let clock = ContinuousClock()
        let cases: [(String, String)] = [
            ("1 MB line", String(repeating: "word **b** ", count: 100_000)),
            ("10k nested quotes", String(repeating: ">", count: 10_000) + " deep"),
            ("unclosed fence on 50k", "```\n" + generatedNote(words: 50_000)),
        ]
        for (name, text) in cases {
            var tv: EditorTextView!
            let open = ms(clock.measure {
                tv = EditorTextView.make()
                tv.frame = NSRect(x: 0, y: 0, width: 900, height: 800)
                tv.load(text)
            })
            tv.setSelectedRange(NSRange(location: 2, length: 0))
            let edit = ms(clock.measure { tv.insertText("x", replacementRange: tv.selectedRange()) })
            perf("PERF \(name): open \(open) ms, edit \(edit) ms")
            #expect(open < budget.hostile && edit < budget.hostile, "\(name)")
        }
        // closing the unclosed fence restores the rest of the note
        let tv = EditorTextView.make()
        tv.load("```\ncode\n\n# Heading")
        let time = ms(clock.measure { tv.insertText("\n```", replacementRange: NSRange(location: 8, length: 0)) })
        #expect(time < budget.hostile)
        #expect(tv.parser.document.blocks.last?.kind == .heading(level: 1))
    }
}
#endif
