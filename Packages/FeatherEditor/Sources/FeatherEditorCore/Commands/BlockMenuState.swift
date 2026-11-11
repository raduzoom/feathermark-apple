import Foundation

/// The block menu's query, matching choices and selected row.
public struct BlockMenuState: Equatable, Sendable {
    public static let maxQueryLength = 24

    public var query = ""
    public var items = BlockChoice.allCases
    public var selected = 0
    /// Choices this platform doesn't offer (iOS: Scan, until Phase 14).
    public var hidden: Set<BlockChoice> = []

    public init(hiding hidden: Set<BlockChoice> = []) {
        self.hidden = hidden
        items = BlockChoice.allCases.filter { !hidden.contains($0) }
    }

    public var selection: BlockChoice? { items.indices.contains(selected) ? items[selected] : nil }

    /// Filters by `query` and selects the first row. False, leaving the state as it was, when the menu should
    /// close instead: nothing matches, the query starts with a space, or it's too long.
    public mutating func setQuery(_ query: String) -> Bool {
        guard query.count <= Self.maxQueryLength, !query.hasPrefix(" ") else { return false }
        let matches = BlockChoice.matching(query).filter { !hidden.contains($0) }
        guard !matches.isEmpty else { return false }
        self.query = query
        items = matches
        selected = 0
        return true
    }

    /// Moves the selection, wrapping at either end.
    public mutating func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = ((selected + delta) % items.count + items.count) % items.count
    }
}
