import FeatherAppModel
import FeatherCore
import SwiftUI

/// A search hit: the title, the snippet with each match in semibold ink, then the date and notebook.
struct SearchResultRow: View {
    let model: AppModel
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s16) {
            NoteTile(model: model, summary: hit.note)
            VStack(alignment: .leading, spacing: Theme.s4) {
                Text(Formatting.displayTitle(hit.note.title))
                    .font(Theme.display(.headline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(Self.highlighted(hit.snippet, hit.matches))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Text(Formatting.noteMeta(summary: hit.note, notebookName: hit.note.notebookID.flatMap(model.notebookName), now: Date()))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.s8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Formatting.displayTitle(hit.note.title)), \(hit.snippet)")
        .accessibilityAddTraits(.isButton)
    }

    /// The snippet with its matches (character offsets) in semibold ink.
    static func highlighted(_ snippet: String, _ matches: [Range<Int>]) -> AttributedString {
        var text = AttributedString(snippet)
        let count = snippet.count
        for m in matches where m.lowerBound >= 0 && m.upperBound <= count && !m.isEmpty {
            let lower = text.index(text.startIndex, offsetByCharacters: m.lowerBound)
            let upper = text.index(text.startIndex, offsetByCharacters: m.upperBound)
            text[lower..<upper].font = .subheadline.weight(.semibold)
            text[lower..<upper].foregroundColor = Theme.ink
        }
        return text
    }
}
