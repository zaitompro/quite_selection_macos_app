import AppKit

enum SettingsPalette {
    // Approved mock: #176fca at 55% over #202020 -> #1b4b7e.
    static let accent = NSColor(srgbRed: 27 / 255, green: 75 / 255, blue: 126 / 255, alpha: 1)
    static let selectedText = NSColor(srgbRed: 244 / 255, green: 246 / 255, blue: 248 / 255, alpha: 1)
    static let thumb = NSColor(srgbRed: 226 / 255, green: 230 / 255, blue: 235 / 255, alpha: 1)
}

final class SettingsRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        SettingsPalette.accent.setFill()
        bounds.fill()
    }
}

final class SettingsSectionCell: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = backgroundStyle == .emphasized ? SettingsPalette.selectedText : .labelColor
            imageView?.contentTintColor = backgroundStyle == .emphasized ? SettingsPalette.selectedText : .controlAccentColor
        }
    }
}

// Keep AppKit button tracking, keyboard activation, state and target/action.
// Only the cell drawing changes from a checkbox to the approved switch shape.
final class SettingsSwitch: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = SettingsSwitchCell()
        setButtonType(.switch)
        title = ""
        setAccessibilityRole(.button)
        setAccessibilitySubrole(.switch)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var intrinsicContentSize: NSSize { NSSize(width: 52, height: 30) }
    override func accessibilityValue() -> Any? { NSNumber(value: state == .on) }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
}

private final class SettingsSwitchCell: NSButtonCell {
    override var state: NSControl.StateValue {
        didSet {
            if state != oldValue, let controlView {
                NSAccessibility.post(element: controlView, notification: .valueChanged)
            }
        }
    }
    private func track(in frame: NSRect) -> NSRect {
        NSRect(x: frame.midX - 26, y: frame.midY - 14, width: 52, height: 28)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = track(in: cellFrame).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        let opacity: CGFloat = isEnabled ? 1 : 0.5
        let fill = state == .on ? SettingsPalette.accent : NSColor.controlColor
        fill.withAlphaComponent(opacity).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let right = (state == .on) != (controlView.userInterfaceLayoutDirection == .rightToLeft)
        let knob = NSRect(x: right ? rect.maxX - 25 : rect.minX + 3,
                          y: rect.midY - 11, width: 22, height: 22)
        SettingsPalette.thumb.withAlphaComponent(opacity).setFill()
        NSBezierPath(ovalIn: knob).fill()
    }
    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSBezierPath(roundedRect: track(in: cellFrame), xRadius: 14, yRadius: 14).fill()
    }
    override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect {
        track(in: cellFrame)
    }
}


/// A wrapping label that measures its height at its actual width, so rows
/// with multi-line captions get enough room in stack views.
final class WrappingLabel: NSTextField {
    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

// Shared layout for settings pages: grouped cards of rows with the title on the
// left and controls on the right, short secondary captions, natural-size buttons.

final class SettingsCard: NSStackView {
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.25).setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.stroke()
    }
}

@MainActor
enum SettingsUI {
    nonisolated static let pageTitleSize: CGFloat = 22
    nonisolated static let groupTitleSize: CGFloat = 15
    nonisolated static let bodySize: CGFloat = 13
    nonisolated static let captionSize: CGFloat = 11.5

    static func pageTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: pageTitleSize, weight: .bold)
        field.setAccessibilityRole(.staticText)
        return field
    }
    static func groupTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: groupTitleSize, weight: .semibold)
        return field
    }
    static func text(_ text: String, size: CGFloat = bodySize, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = WrappingLabel(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.isSelectable = true
        return field
    }
    static func caption(_ text: String) -> NSTextField {
        let field = self.text(text, size: captionSize)
        field.textColor = .secondaryLabelColor
        return field
    }
    static func button(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: bodySize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
    static func iconButton(_ symbol: String, label: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = self.button("", target: target, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(label)
        button.toolTip = label
        return button
    }
    /// Title (and optional caption) on the left, controls on the right.
    /// The label column takes all free width, so captions wrap at the real
    /// row width and the controls stay at the right edge.
    static func row(_ title: String, caption: NSView? = nil, controls: [NSView]) -> NSStackView {
        let titleField = text(title)
        let labels = NSStackView(views: [titleField] + (caption.map { [$0] } ?? []))
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in labels.views {
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        }
        let controlStack = NSStackView(views: controls)
        controlStack.orientation = .horizontal
        controlStack.spacing = 8
        controlStack.setHuggingPriority(.required, for: .horizontal)
        controlStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [labels, controlStack])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 16
        // Stack edge insets do not reliably add height around wrapped captions;
        // explicit constraints keep the same padding for every row.
        for view in [labels, controlStack] {
            view.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 9).isActive = true
            row.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor, constant: 10).isActive = true
        }
        return row
    }
    static func card(_ rows: [NSView]) -> SettingsCard {
        let card = SettingsCard()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 0
        card.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                card.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -28).isActive = true
            }
            card.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -28).isActive = true
        }
        return card
    }
    /// Vertical page; every element spans the page width.
    static func page(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    static func symbol(_ name: String, color: NSColor, label: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        view.contentTintColor = color
        view.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
}

/// One permission: status icon and text, and a button only while it is missing.
@MainActor
final class PermissionRow {
    let view: NSStackView
    private let icon = NSImageView()
    private let state = NSTextField(labelWithString: "")
    private let button: NSButton

    init(title: String, caption: String, buttonTitle: String, target: AnyObject, action: Selector) {
        button = SettingsUI.button(buttonTitle, target: target, action: action)
        state.font = .systemFont(ofSize: SettingsUI.bodySize)
        icon.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        view = SettingsUI.row(title, caption: SettingsUI.caption(caption), controls: [icon, state, button])
        button.setAccessibilityLabel(buttonTitle + " " + title)
    }

    func update(granted: Bool) {
        icon.image = NSImage(systemSymbolName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             accessibilityDescription: granted ? "Разрешено" : "Не разрешено")
        icon.contentTintColor = granted ? .systemGreen : .systemOrange
        state.stringValue = granted ? "Разрешено" : "Не разрешено"
        button.isHidden = granted
    }
}
