import FeatherAppModel
import FeatherCore
import ImageIO
import SwiftUI

/// One note card: tile, serif title, date and notebook, a star when pinned.
struct NoteRow: View {
    let model: AppModel
    let summary: NoteSummary
    var selected = false

    var body: some View {
        HStack(spacing: Theme.s16) {
            NoteTile(model: model, summary: summary)
            VStack(alignment: .leading, spacing: Theme.s4) {
                Text(Formatting.displayTitle(summary.title))
                    .font(Theme.display(.headline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if summary.pinned {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(Theme.s8)
        .padding(.trailing, Theme.s8)
        .background(selected ? Theme.raised : Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Formatting.rowAccessibilityLabel(summary: summary, notebookName: notebookName, now: Date()))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var notebookName: String? { summary.notebookID.flatMap(model.notebookName) }

    private var meta: String {
        if let trashed = summary.trashedAt {
            return Formatting.trashMeta(trashedAt: trashed, retentionDays: model.trashRetentionDays, now: Date())
        }
        return Formatting.noteMeta(summary: summary, notebookName: notebookName, now: Date())
    }
}

/// The note's first image, or its first letter on a tint.
struct NoteTile: View {
    let model: AppModel
    let summary: NoteSummary

    var body: some View {
        Group {
            if let url = imageURL, let image = Thumbnails.image(at: url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                let tint = NoteThumbnail.tint(summary.id)
                Text(NoteThumbnail.letter(summary.title))
                    .font(Theme.display(.title3))
                    .foregroundStyle(Theme.tileInk(tint))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.tile(tint))
            }
        }
        .frame(width: Theme.tileSize, height: Theme.tileSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var imageURL: URL? { NoteThumbnail.imageID(inPreview: summary.preview).flatMap { model.attachmentFiles[$0] } }
}

/// Small downsampled thumbnails, cached by file.
@MainActor enum Thumbnails {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(at url: URL) -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: Theme.tileSize * 3]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
