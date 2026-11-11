import FeatherEditorCore
import UIKit

/// Gives every paragraph a DecoratedLayoutFragment (bullets, checkboxes, quote and code surfaces, images, chips).
@MainActor
final class ReaderLayoutDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    let theme: EditorTheme
    let images: ReaderImages

    init(theme: EditorTheme, images: ReaderImages) {
        self.theme = theme
        self.images = images
    }

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.theme = theme
        let images = images
        fragment.imageProvider = { url in MainActor.assumeIsolated { images.image(for: url) } }
        fragment.chipProvider = { url in MainActor.assumeIsolated { ChipInfo(file: images.file(for: url)) } }
        return fragment
    }
}
