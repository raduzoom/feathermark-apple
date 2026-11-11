// The UIKit editor view: iOS only.
#if os(iOS)
import FeatherEditorCore
import UIKit

/// Where an attachment comes from.
public enum AttachSource: Sendable, Equatable {
    case photoLibrary, files
}

/// The formatting bar above the keyboard (component inventory "Editor formatting bar (mobile)"): Heading, Bold,
/// Italic, Checklist, Bulleted List, Code, Link, Attach, Undo, then a divider and Hide Keyboard. It scrolls sideways
/// when it doesn't fit; targets are 44 pt; the formats on at the caret show the mint tint.
@MainActor
public final class FormattingBar: UIInputView {
    public enum Item: Equatable {
        case heading(Int), bold, italic, checklist, bulleted, code, link, attach(AttachSource), undo, hideKeyboard
    }

    weak var editor: PhoneEditorView?
    let attach: (AttachSource) -> Void
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let divider = UIView()
    private(set) var buttons: [UIButton] = []
    private var buttonItems: [ObjectIdentifier: Item] = [:]
    static let target: CGFloat = 44
    static let height: CGFloat = 52

    public init(editor: PhoneEditorView, attach: @escaping (AttachSource) -> Void) {
        self.editor = editor
        self.attach = attach
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: Self.height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    private func build() {
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        addSubview(scroll)
        scroll.addSubview(stack)

        let headings = UIMenu(children: [1, 2, 3, 0].map { level in
            UIAction(title: level == 0 ? "Body" : "Heading \(level)") { [weak self] _ in self?.perform(.heading(level)) }
        })
        let sources = UIMenu(children: [
            UIAction(title: "Photo Library", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.perform(.attach(.photoLibrary)) },
            UIAction(title: "Choose File…", image: UIImage(systemName: "folder")) { [weak self] _ in self?.perform(.attach(.files)) },
        ])
        stack.addArrangedSubview(button("Heading", "textformat.size", menu: headings))
        stack.addArrangedSubview(button("Bold", "bold", .bold))
        stack.addArrangedSubview(button("Italic", "italic", .italic))
        stack.addArrangedSubview(button("Checklist", "checklist", .checklist))
        stack.addArrangedSubview(button("Bulleted List", "list.bullet", .bulleted))
        stack.addArrangedSubview(button("Code", "chevron.left.forwardslash.chevron.right", .code))
        stack.addArrangedSubview(button("Link", "link", .link))
        stack.addArrangedSubview(button("Attach", "paperclip", menu: sources))
        stack.addArrangedSubview(button("Undo", "arrow.uturn.backward", .undo))

        divider.backgroundColor = .separator
        addSubview(divider)
        addSubview(button("Hide Keyboard", "keyboard.chevron.compact.down", .hideKeyboard))
    }

    private func button(_ label: String, _ symbol: String, _ item: Item? = nil, menu: UIMenu? = nil) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .body))
        config.baseForegroundColor = .label
        config.background.cornerRadius = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let b = UIButton(configuration: config)
        b.accessibilityLabel = label
        b.largeContentTitle = label
        b.showsLargeContentViewer = true
        let tint = editor?.theme.accent ?? .tintColor
        b.configurationUpdateHandler = { button in
            var c = button.configuration
            c?.background.backgroundColor = button.isSelected ? tint.withAlphaComponent(0.14) : .clear
            c?.baseForegroundColor = button.isSelected ? tint : .label
            button.configuration = c
        }
        if let menu {
            b.menu = menu
            b.showsMenuAsPrimaryAction = true
        } else if let item {
            b.addAction(UIAction { [weak self] _ in self?.perform(item) }, for: .primaryActionTriggered)
            buttonItems[ObjectIdentifier(b)] = item
        }
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.target),
            b.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.target),
        ])
        buttons.append(b)
        return b
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let hide = buttons.last!
        let hideSize = hide.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let side: CGFloat = 8
        let h = bounds.height
        hide.frame = CGRect(x: bounds.width - side - max(Self.target, hideSize.width), y: (h - Self.target) / 2,
                            width: max(Self.target, hideSize.width), height: Self.target)
        divider.frame = CGRect(x: hide.frame.minX - 5, y: (h - 24) / 2, width: 1, height: 24)
        scroll.frame = CGRect(x: side, y: 0, width: max(0, divider.frame.minX - 4 - side), height: h)
        let size = stack.systemLayoutSizeFitting(CGSize(width: UIView.layoutFittingCompressedSize.width, height: Self.target))
        stack.frame = CGRect(x: 0, y: (h - Self.target) / 2, width: size.width, height: Self.target)
        stack.layoutIfNeeded()
        scroll.contentSize = CGSize(width: size.width, height: h)
    }

    /// The button with this accessibility label.
    public func button(labelled label: String) -> UIButton? {
        buttons.first { $0.accessibilityLabel == label }
    }

    /// Runs a bar item (buttons and menu items both come here).
    public func perform(_ item: Item) {
        guard let editor else { return }
        switch item {
        case .heading(let level): editor.setHeading(level)
        case .bold: editor.toggle(.bold)
        case .italic: editor.toggle(.italic)
        case .code: editor.toggle(.code)
        case .checklist: editor.toggleChecklist()
        case .bulleted: editor.toggleBulleted()
        case .link: editor.insertLink()
        case .attach(let source): attach(source)
        case .undo: editor.undoManager?.undo()
        case .hideKeyboard: _ = editor.resignFirstResponder()
        }
    }

    /// Selects the buttons for the formats on at the caret.
    func update(_ formats: ActiveFormats) {
        for b in buttons {
            let on: Bool
            switch b.accessibilityLabel {
            case "Heading": on = formats.heading > 0
            case "Bold": on = formats.inline.contains(.bold)
            case "Italic": on = formats.inline.contains(.italic)
            case "Code": on = formats.inline.contains(.code) || formats.code
            case "Checklist": on = formats.checklist
            case "Bulleted List": on = formats.bulleted
            default: on = false
            }
            if b.isSelected != on { b.isSelected = on }
            b.accessibilityTraits = on ? [.button, .selected] : .button
        }
    }
}

// MARK: - The commands the bar and the keyboard shortcuts run

extension PhoneEditorView {
    func toggle(_ format: InlineFormat) {
        guard !isReadOnly, markedTextRange == nil,
              let e = EditorCommands.toggleInline(format, text: textStorage.string, document: styling.document, selection: selectedRange) else { return }
        apply(e)
    }

    public func setHeading(_ level: Int) {
        guard !isReadOnly, markedTextRange == nil else { return }
        apply(EditorCommands.heading(level, text: textStorage.string, caret: selectedRange.location))
    }

    /// Checklist on, or off (back to body text) on a line that is one already.
    public func toggleChecklist() { toggleBlock(.todo, isOn: activeFormats.checklist) }

    /// Bulleted list on, or off on a bulleted line.
    public func toggleBulleted() { toggleBlock(.bulleted, isOn: activeFormats.bulleted) }

    private func toggleBlock(_ choice: BlockChoice, isOn: Bool) {
        guard !isReadOnly, markedTextRange == nil else { return }
        let text = textStorage.string, caret = selectedRange.location
        if isOn {
            apply(EditorCommands.heading(0, text: text, caret: caret))
        } else if let e = EditorCommands.block(choice, text: text, caret: caret, removing: nil) {
            apply(e)
        }
    }

    /// ⌘K and the bar's Link: `[selection](https://)` with the address selected.
    @objc public func insertLink() {
        guard !isReadOnly, markedTextRange == nil else { return }
        apply(EditorCommands.link(text: textStorage.string, selection: selectedRange))
    }

    // ⌘B and ⌘I (and the system's Bold and Italic) write Markdown, never rich text.
    public override func toggleBoldface(_ sender: Any?) { toggle(.bold) }
    public override func toggleItalics(_ sender: Any?) { toggle(.italic) }
    public override func toggleUnderline(_ sender: Any?) {}

    var formattingKeyCommands: [UIKeyCommand] {
        let commands = [
            UIKeyCommand(title: "Bold", action: #selector(toggleBoldface(_:)), input: "b", modifierFlags: .command),
            UIKeyCommand(title: "Italic", action: #selector(toggleItalics(_:)), input: "i", modifierFlags: .command),
            UIKeyCommand(title: "Link", action: #selector(insertLink), input: "k", modifierFlags: .command),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }
}
#endif
