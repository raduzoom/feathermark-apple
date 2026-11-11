// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit

// MARK: - Attachments: images, pasted files, imports that finish later

extension PhoneEditorView {
    /// Where an attachment import's snippets go: a range that later edits move, valid only in the note it was taken in.
    public struct Anchor: Sendable, Equatable {
        let id: Int
        let generation: Int
    }

    /// An anchor at the selection.
    public func makeAnchor() -> Anchor { makeAnchor(at: selectedRange) }

    func makeAnchor(at range: NSRange) -> Anchor {
        let id = nextAnchorID
        nextAnchorID += 1
        anchors[id] = range
        return Anchor(id: id, generation: loadGeneration)
    }

    /// The formatting bar's Attach: remembers the selection as where the files go, then asks the app for them.
    public func requestAttachment(_ source: AttachSource) {
        pendingAttachment = (makeAnchor(), false)
        attach(source)
    }

    /// The files the person picked (none when they cancelled), for the attachment asked for last. `cleaningUp`:
    /// temporary copies to remove once imported.
    public func attachPicked(_ urls: [URL], cleaningUp madeFiles: [URL]) {
        // no request waiting (another note was opened since, or it was already answered): the pick goes nowhere
        guard let pending = pendingAttachment, !urls.isEmpty else {
            if let pending = pendingAttachment { anchors[pending.anchor.id] = nil }
            pendingAttachment = nil
            for f in madeFiles { try? FileManager.default.removeItem(at: f) }
            return
        }
        pendingAttachment = nil
        importAndInsert(urls, anchor: pending.anchor, cleaningUp: madeFiles, asBlock: pending.asBlock)
    }

    /// Inserts snippets at an anchor, each on its own line, as one undo step. Dropped when another note was loaded since.
    public func insertAttachments(_ snippets: [String], at anchor: Anchor) {
        guard let range = anchors.removeValue(forKey: anchor.id), anchor.generation == loadGeneration else { return }
        let length = textStorage.length
        let start = min(range.location, length)
        let clamped = NSRange(location: start, length: min(range.length, length - start))
        if let e = EditorCommands.attachmentSnippets(snippets, text: textStorage.string, at: clamped) { applyKeepingSelection(e) }
    }

    /// Imports `urls` and inserts their snippets at the anchor. The import may take a while: the anchor moves with
    /// later edits, and the result is dropped if another note was loaded meanwhile. `cleaningUp` files are removed
    /// once the import finishes, whatever happens. `asBlock`: block-menu media, inserted as blocks of their own.
    public func importAndInsert(_ urls: [URL], anchor: Anchor, cleaningUp madeFiles: [URL], asBlock: Bool) {
        let importer = importFiles
        temporaryFiles += madeFiles.filter { !temporaryFiles.contains($0) }
        Task { @MainActor [weak self] in
            let snippets = await importer(urls)
            for f in madeFiles { try? FileManager.default.removeItem(at: f) }
            self?.temporaryFiles.removeAll { madeFiles.contains($0) }
            guard let self else { return }
            if asBlock {
                guard let range = anchors.removeValue(forKey: anchor.id), anchor.generation == loadGeneration, !snippets.isEmpty else { return }
                applyKeepingSelection(EditorCommands.mediaEdit(snippets, text: textStorage.string, at: min(range.location, textStorage.length)))
            } else {
                insertAttachments(snippets, at: anchor)
            }
        }
    }

    /// The height to reserve for an image: its size scaled to the measure once loaded, a placeholder until then.
    func imageHeight(for url: String) -> CGFloat {
        guard let file = resolveAttachment(url) else { return Self.placeholderImageHeight }
        if let image = imageCache.image(for: file), image.size.width > 0 {
            let width = min(image.size.width, measure)
            return (image.size.height * width / image.size.width).rounded()
        }
        imageCache.load(file) { [weak self] in self?.restyleImages(matching: url) }
        return Self.placeholderImageHeight
    }

    /// Restyles just the image blocks showing `url` (their reserved height changes when the image lands).
    func restyleImages(matching url: String) {
        let ranges = styling.document.blocks.compactMap { b -> NSRange? in
            if case .image(_, let u, _) = b.kind, u == url { return b.range }
            return nil
        }
        restyle(merging: ranges)
    }
}
#endif
