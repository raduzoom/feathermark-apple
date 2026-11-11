import Foundation

/// Decides what an editor view restyles, so styling work stays proportional to the edit (apple/AGENTS.md
/// "FeatherEditor"): opening a note styles 16 KB around the caret and the rest in 8 KB background chunks,
/// a keystroke restyles its block once, and a caret move restyles the blocks it left and entered. It keeps
/// the parse current (`IncrementalParser`); the view applies `MarkdownStyler.runs` to the ranges it returns.
/// Main-thread use only.
public final class EditorStyling {
    public static let eagerLength = 16_384
    public static let chunkLength = 8_192

    public private(set) var parser: IncrementalParser
    public var document: MarkdownDocument { parser.document }
    /// Characters not styled yet; `nextChunk` hands them out.
    public private(set) var unstyled = IndexSet()
    public var isFullyStyled: Bool { unstyled.isEmpty }
    /// Edited text not restyled yet: restyled once the caret has moved too, so a keystroke styles its block once.
    public private(set) var pendingEdit: NSRange?
    private var text: NSString
    private var caret = 0

    public init(text: String) {
        self.text = text as NSString
        parser = IncrementalParser(text: text)
    }

    /// A new note: returns the ranges to style now (whole lines around the caret); the rest waits in `unstyled`.
    public func load(text: String, caret: Int) -> [NSRange] {
        self.text = text as NSString
        parser = IncrementalParser(text: text)
        pendingEdit = nil
        let length = self.text.length
        self.caret = min(max(0, caret), length)
        unstyled = IndexSet(integersIn: 0..<length)
        guard length > 0 else { return [] }
        let hi = min(length, max(0, self.caret - Self.eagerLength / 2) + Self.eagerLength)
        let lo = max(0, hi - Self.eagerLength)
        let window = self.text.lineRange(for: NSRange(location: lo, length: hi - lo))
        styled(window)
        return [window]
    }

    /// The whole note, styled now (a mode switch): returns its range and empties `unstyled`.
    public func all() -> NSRange {
        let whole = NSRange(location: 0, length: text.length)
        pendingEdit = nil
        unstyled.removeAll()
        return whole
    }

    /// Applies an edit (`range` in the old text, replaced by `replacementLength` characters giving `newText`).
    /// Returns the region to restyle, which is also kept as `pendingEdit` until a selection change or
    /// `takePendingEdit` collects it.
    @discardableResult
    public func edit(range: NSRange, replacementLength: Int, newText: String) -> NSRange {
        text = newText as NSString
        let delta = replacementLength - range.length
        if !unstyled.isEmpty {   // keep the not-yet-styled ranges on the same characters
            unstyled.remove(integersIn: range.location..<NSMaxRange(range))
            unstyled.shift(startingAt: NSMaxRange(range), by: delta)
        }
        let changed = parser.apply(edit: range, replacementLength: replacementLength, newText: newText)
        var region = NSUnionRange(changed, NSRange(location: range.location, length: replacementLength))
        if var p = pendingEdit {
            if p.location >= NSMaxRange(range) { p.location += delta } else if NSMaxRange(p) > range.location { p.length = max(0, p.length + delta) }
            region = NSUnionRange(p, region)
        }
        pendingEdit = region
        return region
    }

    /// The pending edit region, clamped to the text, and clears it.
    public func takePendingEdit() -> NSRange? {
        guard let p = pendingEdit else { return nil }
        pendingEdit = nil
        return clamped(p)
    }

    /// The ranges to restyle when the selection moves: the pending edit and the blocks at both ends of the old
    /// and new selections (markers reveal only there), merged. A jump across the note never restyles what lies between.
    public func selectionChanged(from old: NSRange, to new: NSRange) -> [NSRange] {
        caret = new.location
        let ends = [old, new].flatMap { [NSRange(location: $0.location, length: 0), NSRange(location: NSMaxRange($0), length: 0)] }
        return merged(([takePendingEdit()] + ends.map { blockRanges(touching: $0) }).compactMap { $0 })
    }

    /// The next background chunk (at most 8 KB, widened to whole lines), nearest the caret first; it counts as styled.
    public func nextChunk() -> NSRange? {
        var best: Range<Int>?
        var bestDistance = Int.max
        for run in unstyled.rangeView {
            let d = caret < run.lowerBound ? run.lowerBound - caret : (caret >= run.upperBound ? caret - run.upperBound + 1 : 0)
            if d < bestDistance { best = run; bestDistance = d }
        }
        guard let run = best else { return nil }
        let raw: NSRange
        if caret >= run.upperBound {
            let lo = max(run.lowerBound, run.upperBound - Self.chunkLength)
            raw = NSRange(location: lo, length: run.upperBound - lo)
        } else {
            let lo = max(run.lowerBound, min(caret, run.upperBound - 1))
            raw = NSRange(location: lo, length: min(run.upperBound, lo + Self.chunkLength) - lo)
        }
        let lines = text.lineRange(for: raw)
        let lo = max(lines.location, run.lowerBound), hi = min(NSMaxRange(lines), run.upperBound)
        let chunk = NSRange(location: lo, length: hi - lo)
        styled(chunk)
        return chunk
    }

    /// Marks a range styled.
    public func styled(_ range: NSRange) {
        guard range.length > 0 else { return }
        unstyled.remove(integersIn: range.location..<NSMaxRange(range))
    }

    /// The blocks a selection is in or touches, as one range.
    public func blockRanges(touching sel: NSRange) -> NSRange? {
        var out: NSRange?
        for b in document.blocks where sel.location <= NSMaxRange(b.range) && NSMaxRange(sel) >= b.range.location {
            out = out.map { NSUnionRange($0, b.range) } ?? b.range
        }
        return out
    }

    /// Ranges sorted, with those that overlap or touch merged.
    public func merged(_ ranges: [NSRange]) -> [NSRange] {
        var out: [NSRange] = []
        for r in ranges.map(clamped).sorted(by: { $0.location < $1.location }) {
            if let last = out.last, r.location <= NSMaxRange(last) {
                out[out.count - 1] = NSUnionRange(last, r)
            } else {
                out.append(r)
            }
        }
        return out
    }

    private func clamped(_ r: NSRange) -> NSRange {
        let length = text.length
        let lo = min(r.location, length)
        return NSRange(location: lo, length: max(0, min(NSMaxRange(r), length) - lo))
    }
}
