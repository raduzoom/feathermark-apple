import Foundation

/// Keeps a caret out of hidden syntax (markers drawn at font size 0.01).
public enum EditorSelection {
    /// A caret inside a hidden run moves to the run's edge in the direction of travel (the nearer edge when there's
    /// no direction). A selection that crosses hidden runs takes them whole. `hidden(i)` says whether the character
    /// at `i` is hidden; `length` is the text's length.
    public static func adjusted(_ proposed: NSRange, from old: NSRange, hidden: (Int) -> Bool, length: Int) -> NSRange {
        guard length > 0 else { return proposed }
        /// The hidden run a position sits strictly inside (hidden characters on both sides).
        func hiddenRun(at i: Int) -> NSRange? {
            guard i > 0, i < length, hidden(i), hidden(i - 1) else { return nil }
            var lo = i - 1, hi = i + 1
            while lo > 0, hidden(lo - 1) { lo -= 1 }
            while hi < length, hidden(hi) { hi += 1 }
            return NSRange(location: lo, length: hi - lo)
        }
        if proposed.length == 0 {
            guard let run = hiddenRun(at: proposed.location) else { return proposed }
            let p: Int
            if proposed.location > old.location { p = NSMaxRange(run) }
            else if proposed.location < old.location { p = run.location }
            else { p = proposed.location - run.location <= NSMaxRange(run) - proposed.location ? run.location : NSMaxRange(run) }
            return NSRange(location: p, length: 0)
        }
        var start = proposed.location, end = NSMaxRange(proposed)
        if let r = hiddenRun(at: start) { start = r.location }
        if let r = hiddenRun(at: end) { end = NSMaxRange(r) }
        return NSRange(location: start, length: end - start)
    }
}
