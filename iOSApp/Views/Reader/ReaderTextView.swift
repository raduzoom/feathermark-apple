import FeatherAppModel
import FeatherCore
import FeatherEditorCore
import SwiftUI
import UIKit

/// A read-only TextKit 2 text view showing a note's exact Markdown, styled like the Mac editor with every marker
/// hidden. The note's meta line and title sit above the text and scroll with it. Never touches `layoutManager`
/// (that would switch the view to TextKit 1).
@MainActor
final class ReaderUITextView: UITextView {
    let images: ReaderImages
    let theme: EditorTheme
    private let layoutDelegate: ReaderLayoutDelegate
    private let metaLabel = UILabel()
    private let titleLabel = UILabel()
    private var body = ""
    private var measure: CGFloat = 0

    init(images: ReaderImages, theme: EditorTheme = .standard) {
        self.images = images
        self.theme = theme
        layoutDelegate = ReaderLayoutDelegate(theme: theme, images: images)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        let content = NSTextContentStorage()
        content.addTextLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        layoutManager.delegate = layoutDelegate
        isEditable = false
        isSelectable = true
        dataDetectorTypes = []
        backgroundColor = .clear
        alwaysBounceVertical = true
        accessibilityIdentifier = "reader-body"

        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = theme.textSecondary
        titleLabel.font = theme.h1
        titleLabel.textColor = theme.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        addSubview(metaLabel)
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a note. The text storage gets exactly `body`; styling is attributes only.
    func show(_ body: String, title: String = "", meta: String = "") {
        self.body = body
        titleLabel.text = title
        metaLabel.text = meta
        restyle()
        setNeedsLayout()
    }

    private func restyle() {
        images.maxWidth = max(1, measure > 0 ? measure : theme.measure)
        let styled = MarkdownStyler.styledText(body, theme: theme) { [images] url in
            MainActor.assumeIsolated { images.height(for: url) }
        }
        textStorage.setAttributedString(styled)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The 560 pt reading measure, centred, with at least 16 pt each side.
        let width = bounds.width
        let newMeasure = max(1, min(theme.measure, width - 32))
        let side = max(16, (width - newMeasure) / 2)
        let header = layoutHeader(x: side, width: newMeasure)
        let inset = UIEdgeInsets(top: header, left: side, bottom: 32, right: side)
        if textContainerInset != inset { textContainerInset = inset }
        if newMeasure != measure {
            measure = newMeasure
            if !body.isEmpty { restyle() }
        }
    }

    /// Places the meta line and title above the text; returns the height they take.
    private func layoutHeader(x side: CGFloat, width measure: CGFloat) -> CGFloat {
        // Line up with the text, which starts after TextKit's line fragment padding.
        let pad = textContainer.lineFragmentPadding
        let x = side + pad, width = max(1, measure - 2 * pad)
        var y: CGFloat = 16
        let meta = metaLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        metaLabel.frame = CGRect(x: x, y: y, width: width, height: metaLabel.text?.isEmpty == false ? meta.height : 0)
        y = metaLabel.frame.maxY + (metaLabel.frame.height > 0 ? 8 : 0)
        let title = titleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        titleLabel.frame = CGRect(x: x, y: y, width: width, height: titleLabel.text?.isEmpty == false ? title.height : 0)
        return titleLabel.frame.maxY + (titleLabel.frame.height > 0 ? 16 : 0)
    }
}

/// SwiftUI wrapper. Re-sets the text only when the note or its saved version changes.
struct ReaderTextView: UIViewRepresentable {
    let model: AppModel
    let editor: EditorState
    let meta: String

    final class Coordinator {
        var shown: (ULID, Int64, String)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ReaderUITextView {
        let model = model
        return ReaderUITextView(images: ReaderImages(resolve: { model.attachmentURL(for: $0) }, maxWidth: EditorTheme.standard.measure))
    }

    func updateUIView(_ view: ReaderUITextView, context: Context) {
        let key = (editor.id, editor.modified, meta)
        if let shown = context.coordinator.shown, shown == key { return }
        context.coordinator.shown = key
        view.show(editor.body, title: Formatting.displayTitle(editor.title), meta: meta)
        view.setContentOffset(.zero, animated: false)
    }
}
