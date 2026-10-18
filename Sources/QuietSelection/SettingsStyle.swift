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

