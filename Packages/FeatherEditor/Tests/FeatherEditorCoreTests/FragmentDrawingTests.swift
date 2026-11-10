#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import Testing
@testable import FeatherEditorCore

/// Gives every paragraph a DecoratedLayoutFragment, as the editor views' delegates do.
private final class FragmentDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}

/// The fragment draws its decorations into the context TextKit hands to `draw(at:in:)`. On macOS AppKit's text
/// view makes that context current; on iOS a layer-backed view doesn't, so the fragment must not rely on it.
@MainActor @Suite struct FragmentDrawingTests {
    /// Lays out `text` (styled live) and draws its rule paragraph into a 300 × 120 bitmap; returns how many pixels
    /// it painted.
    func paintedPixels(_ text: String) throws -> Int {
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        let delegate = FragmentDelegate()
        layout.delegate = delegate
        storage.addTextLayoutManager(layout)
        layout.textContainer = NSTextContainer(size: CGSize(width: 300, height: 1000))
        let styled = NSMutableAttributedString(string: text)
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for run in MarkdownStyler.runs(text: text, document: MarkdownParser.parse(text), selection: NSRange(location: whole.length + 1, length: 0),
                                       mode: .live, theme: .standard, in: whole) {
            styled.setAttributes(run.attributes.nsAttributes, range: run.range)
        }
        storage.textStorage?.setAttributedString(styled)
        layout.ensureLayout(for: layout.documentRange)
        var rule: DecoratedLayoutFragment?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let f = fragment as? DecoratedLayoutFragment, case .rule = (f.textElement as? NSTextParagraph)?
                .attributedString.attribute(.featherDecoration, at: 0, effectiveRange: nil) as? Decoration { rule = f; return false }
            return true
        }
        let fragment = try #require(rule, "no rule fragment laid out")

        let width = 300, height = 120
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))   // y-down, as text views draw
        context.scaleBy(x: 1, y: -1)
        #if canImport(AppKit)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        fragment.draw(at: CGPoint(x: 0, y: 10), in: context)
        NSGraphicsContext.restoreGraphicsState()
        #else
        fragment.draw(at: CGPoint(x: 0, y: 10), in: context)   // no UIKit context pushed, as in a layer-backed view
        #endif
        return stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
    }

    @Test func ruleIsDrawnIntoTheGivenContext() throws {
        // The hairline spans the container (about 290 pixels); hidden "---" markers paint next to nothing.
        #expect(try paintedPixels("a\n\n---\n\nb\n") > 200)
    }
}
