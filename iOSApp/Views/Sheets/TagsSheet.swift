import FeatherAppModel
import FeatherCore
import SwiftUI

/// Tags… for one note: tick tags on and off, or make a new one (it's ticked at once).
struct TagsSheet: View {
    let model: AppModel
    let noteID: ULID
    @State private var newTag = ""
    @Environment(\.dismiss) private var dismiss

    private var noteTags: Set<ULID> { model.tagsByNote[noteID] ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.tags) { tag in
                        Button { Task { await model.toggleTag(tag.id, on: noteID) } } label: {
                            HStack {
                                Text(tag.name).foregroundStyle(Theme.ink)
                                Spacer()
                                if noteTags.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(noteTags.contains(tag.id) ? .isSelected : [])
                    }
                }
                Section {
                    TextField("New Tag", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addTag)
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addTag() {
        let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newTag = ""
        Task {
            if let tag = await model.createTag(name: name) { await model.toggleTag(tag.id, on: noteID) }
        }
    }
}
