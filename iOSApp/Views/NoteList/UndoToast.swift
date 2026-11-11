import FeatherAppModel
import SwiftUI

/// "“Bread notes” moved to the Trash." with Undo, for 5 seconds after a full swipe (the model times it).
struct UndoToast: View {
    let offer: UndoTrash
    let undo: () -> Void

    private var text: String { "“\(Formatting.displayTitle(offer.title))” moved to the Trash." }

    var body: some View {
        HStack(spacing: Theme.s16) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, Theme.s16)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, Theme.s16)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: text) }
    }
}
