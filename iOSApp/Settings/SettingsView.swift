import FeatherAppModel
import FeatherCore
import SwiftUI

/// Settings without sync (Phase 12): General and About. Sync and Advanced arrive with Phase 15.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var export = ExportController()
    @State private var showFilesPicker = false
    @State private var showSummary = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Quick notes go to", selection: $model.quickNoteNotebookID) {
                        Text("No Notebook").tag(ULID?.none)
                        ForEach(model.notebooks) { Text($0.name).tag(ULID?.some($0.id)) }
                    }
                } header: {
                    Text("General")
                } footer: {
                    Text("Captures from the Share sheet land here.")
                }
                Section {
                    Picker("Empty Trash after", selection: $model.trashRetentionDays) {
                        ForEach(AppModel.retentionChoices, id: \.self) { Text("\($0) days").tag($0) }
                    }
                } footer: {
                    Text("Notes in the Trash are removed for good after this.")
                }
                Section {
                    Button {
                        Task {
                            if await export.exportAll(model: model) != nil { showFilesPicker = true }
                        }
                    } label: {
                        HStack(spacing: Theme.s8) {
                            Text(export.isExporting ? "Exporting…" : "Export Notes…")
                            if export.isExporting { ProgressView() }
                        }
                    }
                    .disabled(export.isExporting || showFilesPicker)
                } footer: {
                    Text("Saves every note as a Markdown file, in folders for your notebooks.")
                }
                Section {
                    NavigationLink("About FeatherMark") { AboutView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileMover(isPresented: $showFilesPicker, file: export.pending) { result in
                if case .success = result { showSummary = true } else { export.clearSummary() }
                export.finish()
            } onCancellation: {
                export.clearSummary()
                export.finish()
            }
            .onDisappear { export.finish() }
            .alert("Export finished", isPresented: $showSummary) {
                Button("OK") { export.clearSummary() }
            } message: {
                Text(export.summary ?? "")
            }
        }
    }
}
