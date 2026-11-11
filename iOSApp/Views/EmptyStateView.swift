import SwiftUI

/// A designed empty state: a serif title, one line of help, and at most one action.
struct EmptyStateView: View {
    let title: String
    let message: String
    var action: (label: String, run: () -> Void)?
    /// The screen's one main action: navy fill (Mint Glass).
    var primary = false

    var body: some View {
        VStack(spacing: Theme.s16) {
            if !title.isEmpty {
                Text(title)
                    .font(Theme.display(.title2))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
            }
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let action {
                if primary {
                    Button(action.label, action: action.run)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primaryFill)
                        .foregroundStyle(Theme.onPrimary)
                        .frame(minHeight: 44)
                } else {
                    Button(action.label, action: action.run)
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(Theme.s32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
