import SwiftUI

/// About FeatherMark: version, what the app promises, license.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.s8) {
                    Text("FeatherMark")
                        .font(Theme.display(.title))
                        .foregroundStyle(Theme.ink)
                    Text(version)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, Theme.s8)
                Text("Your notes are plain Markdown files you own.")
            }
            Section {
                LabeledContent("License", value: "MIT License")
                LabeledContent("Made by", value: "The FeatherMark authors")
            }
        }
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
