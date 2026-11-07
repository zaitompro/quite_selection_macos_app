import Foundation

// User-defined global shortcuts. Platform-free: key codes and Carbon modifier
// masks are plain numbers so the rules can be tested without registering keys.

struct Shortcut: Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    // Carbon modifier masks (cmdKey, shiftKey, optionKey, controlKey).
    static let command: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000
    static let allModifiers = command | shift | option | control

    static let escape: UInt32 = 53

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.allModifiers
    }

    /// Shift alone would take ordinary typing; at least Command, Option or Control is required.
    var isValid: Bool { modifiers & (Self.command | Self.option | Self.control) != 0 }

    /// Modifier words in Apple's order (⌃⌥⇧⌘), then the key: "Control + Option + Esc".
    func title(keyName: (UInt32) -> String?) -> String {
        var parts: [String] = []
        if modifiers & Self.control != 0 { parts.append("Control") }
        if modifiers & Self.option != 0 { parts.append("Option") }
        if modifiers & Self.shift != 0 { parts.append("Shift") }
        if modifiers & Self.command != 0 { parts.append("Command") }
        parts.append(Self.specialKeyNames[keyCode] ?? keyName(keyCode)?.uppercased() ?? "Клавиша \(keyCode)")
        return parts.joined(separator: " + ")
    }

    static let specialKeyNames: [UInt32: String] = [
        53: "Esc", 36: "Return", 76: "Enter", 48: "Tab", 49: "Пробел", 51: "Delete", 117: "Forward Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20"
    ]

    var preferenceValue: [String: Int] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers)] }

    init?(preferenceValue value: Any?) {
        guard let value = value as? [String: Any],
              let key = (value["keyCode"] as? NSNumber)?.uint32Value,
              let modifiers = (value["modifiers"] as? NSNumber)?.uint32Value else { return nil }
        self.init(keyCode: key, modifiers: modifiers)
        guard isValid else { return nil }
    }
}

enum ShortcutAction: String, CaseIterable {
    case read, primary, translate, screen

    var title: String {
        switch self {
        case .read: return "Читать выделенный текст"
        case .primary: return "Читать основным голосом"
        case .translate: return "Перевести и прочитать"
        case .screen: return "Прочитать область экрана"
        }
    }

    var caption: String {
        switch self {
        case .read: return "Повторное нажатие останавливает чтение"
        case .primary: return "Без автоопределения языка и перевода"
        case .translate: return "Перевод на основной язык, затем чтение"
        case .screen: return "Обведите область мышью; Esc — отмена"
        }
    }

    /// Identifier of the Carbon hot key registration.
    var hotKeyID: UInt32 {
        switch self {
        case .read: return 1
        case .screen: return 2
        case .primary: return 3
        case .translate: return 4
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .read: return Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.option)
        case .primary: return Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.control | Shortcut.option)
        case .translate: return Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.command)
        case .screen: return Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.control)
        }
    }

    /// System features that use the same keys by default, shown only on a match.
    func systemConflict(_ shortcut: Shortcut) -> String? {
        if shortcut == Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.option) {
            return "Совпадает с «Проговариванием выбранного текста» macOS"
        }
        if shortcut == Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.command) {
            return "Совпадает с Accessibility Reader macOS"
        }
        if shortcut.modifiers & (Shortcut.control | Shortcut.option) == Shortcut.control | Shortcut.option {
            return "Control + Option — также модификатор VoiceOver"
        }
        return nil
    }
}

enum ShortcutSettings {
    static let preferenceKey = "Shortcuts"

    /// Saved shortcuts, or the earlier fixed choices of versions up to 1.8.7.
    static func load(saved: [String: Any]?, legacy: (String) -> Any?) -> [ShortcutAction: Shortcut] {
        var result: [ShortcutAction: Shortcut] = [:]
        for action in ShortcutAction.allCases {
            if let shortcut = Shortcut(preferenceValue: saved?[action.rawValue]) {
                result[action] = shortcut
            } else {
                result[action] = legacyShortcut(action, legacy: legacy)
            }
        }
        // Never start with two actions on the same keys.
        for action in ShortcutAction.allCases {
            if let current = result[action], conflict(for: action, shortcut: current, in: result) != nil {
                result[action] = action.defaultShortcut
            }
        }
        return result
    }

    static func legacyShortcut(_ action: ShortcutAction, legacy: (String) -> Any?) -> Shortcut {
        let escape = Shortcut.escape
        switch action {
        case .read:
            // Versions up to 1.8.7 stored "UseOptionEscape"; absent meant Option + Shift + Esc.
            let plain = (legacy("UseOptionEscape") as? NSNumber)?.boolValue ?? false
            return Shortcut(keyCode: escape, modifiers: Shortcut.option | (plain ? 0 : Shortcut.shift))
        case .screen:
            let choice = (legacy("OCRShortcut") as? NSNumber)?.intValue ?? 0
            return Shortcut(keyCode: escape, modifiers: Shortcut.control | (choice == 1 ? Shortcut.shift : 0))
        case .primary:
            let choice = (legacy("PrimaryShortcut") as? NSNumber)?.intValue ?? 0
            return Shortcut(keyCode: choice == 1 ? 15 : escape, modifiers: Shortcut.control | Shortcut.option)
        case .translate:
            let choice = (legacy("TranslationShortcut") as? NSNumber)?.intValue ?? 0
            return Shortcut(keyCode: escape, modifiers: Shortcut.command | (choice == 1 ? Shortcut.shift : 0))
        }
    }

    static func conflict(for action: ShortcutAction, shortcut: Shortcut,
                         in current: [ShortcutAction: Shortcut]) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && current[$0] == shortcut }
    }

    static func preferenceValue(_ shortcuts: [ShortcutAction: Shortcut]) -> [String: [String: Int]] {
        Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value.preferenceValue) })
    }
}
