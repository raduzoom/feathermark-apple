import ImageIO
import UIKit

/// Images for the reader: each attachment downsampled once to the reading width and cached; heights follow the
/// Mac editor's rule (scaled to fit the measure, never enlarged; 96 pt while missing).
@MainActor
final class ReaderImages {
    static let placeholderHeight: CGFloat = 96

    private let resolve: (String) -> URL?
    /// The reading measure; images are never drawn wider.
    var maxWidth: CGFloat {
        didSet { if maxWidth != oldValue { images.removeAll() } }
    }
    private var images: [String: UIImage] = [:]
    private var sizes: [String: CGSize] = [:]

    /// `resolve` turns a `feather://attachment/<id>` link into its file (the model's `attachmentURL(for:)`).
    init(resolve: @escaping (String) -> URL?, maxWidth: CGFloat) {
        self.resolve = resolve
        self.maxWidth = maxWidth
    }

    func file(for url: String) -> URL? { resolve(url) }

    /// The image's natural size in points (pixels at scale 1, as the Mac reads it), nil when it can't be read.
    private func naturalSize(_ url: String) -> CGSize? {
        if let size = sizes[url] { return size }
        guard let file = resolve(url), let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else { return nil }
        let rotated = ((props[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5   // EXIF 5–8 swap width and height
        let size = rotated ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        sizes[url] = size
        return size
    }

    func height(for url: String) -> CGFloat {
        guard let size = naturalSize(url) else { return Self.placeholderHeight }
        let width = min(size.width, maxWidth)
        return (size.height * width / size.width).rounded()
    }

    func image(for url: String) -> UIImage? {
        if let hit = images[url] { return hit }
        guard let file = resolve(url), let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, maxWidth * 3)]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        images[url] = image
        return image
    }
}
