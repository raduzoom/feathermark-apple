// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit

/// Gives every paragraph a DecoratedLayoutFragment (bullets, checkboxes, quote and code surfaces, images, chips).
@MainActor
final class PhoneLayoutDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    weak var editor: PhoneEditorView?

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange)
        guard let editor else { return fragment }
        fragment.theme = editor.theme
        if let block = editor.copyBlock {
            let start = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
            fragment.showsCopyButton = start == block.location
        }
        fragment.imageProvider = { [weak editor] url in
            MainActor.assumeIsolated { editor.flatMap { e in e.resolveAttachment(url).flatMap { e.imageCache.image(for: $0) } } }
        }
        fragment.chipProvider = { [weak editor] url in
            MainActor.assumeIsolated { ChipInfo(file: editor?.resolveAttachment(url)) }
        }
        return fragment
    }
}
#endif
