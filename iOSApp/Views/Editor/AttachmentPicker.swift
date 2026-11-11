import FeatherEditorPhone
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Photos and Files for the editor's Attach (the formatting bar and the "/" menu's Image or file). Picked items are
/// copied to temporary files first (Photos data, or a Files item read inside its security scope), which the editor
/// removes once they're imported. A cancelled pick reports no files.
struct AttachmentPicker: ViewModifier {
    @Binding var source: AttachSource?
    /// The temporary copies, or none when cancelled.
    let onPicked: ([URL]) -> Void
    @State private var photos: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .onChange(of: source) { _, picked in
                // UI tests: a file without the system picker (debug builds, isolated runs only)
                guard picked != nil, let fixture = AppBootstrap.pickFixture() else { return }
                source = nil
                onPicked([fixture])
            }
            .photosPicker(isPresented: Binding(get: { source == .photoLibrary }, set: { if !$0 { photosClosed() } }),
                          selection: $photos, maxSelectionCount: 10, matching: .images, preferredItemEncoding: .current)
            .fileImporter(isPresented: Binding(get: { source == .files }, set: { if !$0 { source = nil } }),
                          allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                source = nil
                switch result {
                case .success(let urls): onPicked(urls.compactMap(Self.copyOut))
                case .failure: onPicked([])
                }
            } onCancellation: {
                source = nil
                onPicked([])
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                photos = []
                Task { onPicked(await Self.write(items)) }
            }
    }

    /// The Photos sheet closed: with nothing picked, the pick was cancelled (a selection arrives through `photos`).
    private func photosClosed() {
        source = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            // ...unless a new Attach was asked for meanwhile (it owns the pending request now)
            if photos.isEmpty, !Self.photosArrived, source == nil { onPicked([]) }
            Self.photosArrived = false
        }
    }

    @MainActor private static var photosArrived = false

    /// Each picked photo as `<uuid>.<its own extension>` (HEIC stays HEIC) in its own temporary folder.
    @MainActor static func write(_ items: [PhotosPickerItem]) async -> [URL] {
        photosArrived = true
        var urls: [URL] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let folder = FileManager.default.temporaryDirectory.appending(path: "FeatherPick-\(UUID().uuidString)", directoryHint: .isDirectory)
            let file = folder.appending(path: "\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file)
                urls.append(file)
            } catch { continue }
        }
        return urls
    }

    /// Copies a Files item out of its security scope, keeping its name (the chip shows it).
    static func copyOut(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appending(path: "FeatherPick-\(UUID().uuidString)", directoryHint: .isDirectory)
        let copy = folder.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        } catch {
            return nil
        }
    }

    /// The temporary folders the copies live in, for the editor to remove once imported.
    static func folders(of urls: [URL]) -> [URL] { urls.map { $0.deletingLastPathComponent() } }
}

extension View {
    /// Shows Photos or Files while `source` is set, and hands back the picked items as temporary files.
    func attachmentPicker(source: Binding<AttachSource?>, onPicked: @escaping ([URL]) -> Void) -> some View {
        modifier(AttachmentPicker(source: source, onPicked: onPicked))
    }
}
