// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit

/// The "/" block menu on iPhone and iPad: a list above the keyboard that takes the formatting bar's place while it's
/// open. Rows show the choice's symbol, title and Markdown; the selected row (hardware keyboard arrows) is tinted.
/// "Image or file" turns the list into its two sources.
@MainActor
public final class PhoneBlockMenu: UIInputView {
    weak var editor: PhoneEditorView?
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private(set) var rows: [UIButton] = []
    static let rowHeight: CGFloat = 44
    static let visibleRows: CGFloat = 4.5

    init(editor: PhoneEditorView) {
        self.editor = editor
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: Self.rowHeight * Self.visibleRows), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        stack.axis = .vertical
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = true
        addSubview(scroll)
        scroll.addSubview(stack)
        accessibilityIdentifier = "block-menu"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight * min(Self.visibleRows, CGFloat(max(rows.count, 1))))
    }

    /// Shows the menu's choices.
    func show(_ state: BlockMenuState) {
        setRows(state.items.enumerated().map { i, c in
            (c.title, c.symbolName, c.hint, i == state.selected, { [weak self] in self?.editor?.pickBlock(c) })
        })
    }

    /// Shows where an image or file comes from.
    func showSources() {
        setRows([
            ("Photo Library", "photo.on.rectangle", "", false, { [weak self] in self?.editor?.pickSource(.photoLibrary) }),
            ("Choose File…", "folder", "", false, { [weak self] in self?.editor?.pickSource(.files) }),
        ])
    }

    private func setRows(_ items: [(String, String, String, Bool, () -> Void)]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = items.map { title, symbol, hint, selected, action in
            var config = UIButton.Configuration.plain()
            config.title = title
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 12
            config.imagePlacement = .leading
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            config.background.backgroundColor = selected ? (editor?.theme.accent ?? .tintColor).withAlphaComponent(0.14) : .clear
            config.subtitle = nil
            let b = UIButton(configuration: config)
            b.contentHorizontalAlignment = .leading
            b.accessibilityLabel = title
            if selected { b.accessibilityTraits.insert(.selected) }
            b.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
            if !hint.isEmpty {
                let label = UILabel()
                label.text = hint
                label.font = editor?.theme.mono13 ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
                label.textColor = .secondaryLabel
                label.isAccessibilityElement = false
                label.translatesAutoresizingMaskIntoConstraints = false
                b.addSubview(label)
                NSLayoutConstraint.activate([
                    label.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -16),
                    label.centerYAnchor.constraint(equalTo: b.centerYAnchor),
                ])
            }
            b.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.rowHeight).isActive = true
            stack.addArrangedSubview(b)
            return b
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        if let i = rows.firstIndex(where: { $0.accessibilityTraits.contains(.selected) }) { scrollToRow(i) }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let height = Self.rowHeight * CGFloat(rows.count)
        stack.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        scroll.contentSize = CGSize(width: bounds.width, height: height)
    }

    private func scrollToRow(_ i: Int) {
        layoutIfNeeded()
        scroll.scrollRectToVisible(CGRect(x: 0, y: CGFloat(i) * Self.rowHeight, width: 1, height: Self.rowHeight), animated: false)
    }

    /// The row with this title.
    public func row(titled title: String) -> UIButton? {
        rows.first { $0.accessibilityLabel == title }
    }
}
#endif
