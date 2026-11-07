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

extension Shortcut {
    /// System features that use the same keys by default, shown only on a match.
    var systemConflict: String? {
        if self == Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.option) {
            return "Совпадает с «Проговариванием выбранного текста» macOS"
        }
        if self == Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.command) {
            return "Совпадает с Accessibility Reader macOS"
        }
        if modifiers & (Shortcut.control | Shortcut.option) == Shortcut.control | Shortcut.option {
            return "Control + Option — также модификатор VoiceOver"
        }
        return nil
    }
}

/// What a shortcut does on a short or a long press.
enum ReadFunction: String, CaseIterable {
    case read, primary, translate, repeatLast, screenRegion

    var title: String {
        switch self {
        case .read: return "Читать"
        case .primary: return "Читать основным голосом"
        case .translate: return "Перевести и прочитать"
        case .repeatLast: return "Повторить последнее"
        case .screenRegion: return "Обвести область и распознать"
        }
    }
}

/// One of the three global shortcuts with its short- and long-press functions.
struct ShortcutSlot: Equatable {
    var shortcut: Shortcut?
    var short: ReadFunction?
    var long: ReadFunction?

    static let count = 3
    static func hotKeyID(_ index: Int) -> UInt32 { UInt32(index + 1) }

    static let defaults: [ShortcutSlot] = [
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.option), short: .read, long: .primary),
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.command), short: .translate, long: .repeatLast),
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.control), short: .screenRegion, long: nil)
    ]

    var preferenceValue: [String: Any] {
        var value: [String: Any] = [:]
        if let shortcut { value.merge(shortcut.preferenceValue) { $1 } }
        if let short { value["short"] = short.rawValue }
        if let long { value["long"] = long.rawValue }
        return value
    }

    init(shortcut: Shortcut?, short: ReadFunction?, long: ReadFunction?) {
        self.shortcut = shortcut; self.short = short; self.long = long
    }

    init(preferenceValue value: Any?) {
        let dictionary = value as? [String: Any] ?? [:]
        shortcut = Shortcut(preferenceValue: dictionary)
        short = (dictionary["short"] as? String).flatMap(ReadFunction.init(rawValue:))
        long = (dictionary["long"] as? String).flatMap(ReadFunction.init(rawValue:))
    }
}

enum ShortcutSettings {
    static let preferenceKey = "ShortcutSlots"
    /// Format of version 1.9.0–1.9.1: one shortcut per action.
    static let actionPreferenceKey = "Shortcuts"
    static let thresholdKey = "LongPressThreshold"
    static let defaultThreshold = 0.4
    static let thresholdRange = 0.2...1.2

    static func threshold(_ value: Any?) -> Double {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return defaultThreshold }
        return min(thresholdRange.upperBound, max(thresholdRange.lowerBound, number.doubleValue))
    }

    /// Saved slots; otherwise the shortcuts of earlier versions are moved into
    /// the three slots: reading (long press: primary voice), translation (long
    /// press: repeat) and screen region. A separate primary-voice shortcut is
    /// no longer needed and is dropped.
    static func load(saved: [Any]?, actions: [String: Any]?, legacy: (String) -> Any?) -> [ShortcutSlot] {
        var slots: [ShortcutSlot]
        if let saved, saved.count == ShortcutSlot.count {
            slots = saved.map(ShortcutSlot.init(preferenceValue:))
        } else {
            slots = ShortcutSlot.defaults
            for (index, name) in ["read", "translate", "screen"].enumerated() {
                slots[index].shortcut = Shortcut(preferenceValue: actions?[name]) ?? legacyShortcut(name, legacy: legacy)
            }
        }
        // Never start with two slots on the same keys.
        for index in slots.indices {
            guard let current = slots[index].shortcut,
                  conflict(for: index, shortcut: current, in: slots) != nil else { continue }
            let fallback = ShortcutSlot.defaults[index].shortcut
            slots[index].shortcut = fallback.flatMap { conflict(for: index, shortcut: $0, in: slots) == nil ? $0 : nil }
        }
        return slots
    }

    static func legacyShortcut(_ action: String, legacy: (String) -> Any?) -> Shortcut {
        let escape = Shortcut.escape
        switch action {
        case "read":
            // Versions up to 1.8.7 stored "UseOptionEscape"; absent meant Option + Shift + Esc.
            let plain = (legacy("UseOptionEscape") as? NSNumber)?.boolValue ?? false
            return Shortcut(keyCode: escape, modifiers: Shortcut.option | (plain ? 0 : Shortcut.shift))
        case "screen":
            let choice = (legacy("OCRShortcut") as? NSNumber)?.intValue ?? 0
            return Shortcut(keyCode: escape, modifiers: Shortcut.control | (choice == 1 ? Shortcut.shift : 0))
        default:
            let choice = (legacy("TranslationShortcut") as? NSNumber)?.intValue ?? 0
            return Shortcut(keyCode: escape, modifiers: Shortcut.command | (choice == 1 ? Shortcut.shift : 0))
        }
    }

    static func conflict(for index: Int, shortcut: Shortcut, in slots: [ShortcutSlot]) -> Int? {
        slots.indices.first { $0 != index && slots[$0].shortcut == shortcut }
    }

    /// Where a function is assigned, for hints such as the screen-reading page.
    static func assignment(of function: ReadFunction, in slots: [ShortcutSlot]) -> (index: Int, long: Bool)? {
        for (index, slot) in slots.enumerated() {
            if slot.short == function { return (index, false) }
            if slot.long == function { return (index, true) }
        }
        return nil
    }
}

/// Short or long press of one shortcut. A press while something is being read
/// stops it at once. Without a long-press function the short one runs on press.
struct PressGesture {
    enum Outcome: Equatable { case none, stop, perform(long: Bool) }
    private(set) var held = false
    private var consumed = false

    mutating func press(busy: Bool, hasLong: Bool) -> Outcome {
        held = true
        consumed = true
        if busy { return .stop }
        if !hasLong { return .perform(long: false) }
        consumed = false
        return .none
    }

    mutating func thresholdReached() -> Outcome {
        guard held, !consumed else { return .none }
        consumed = true
        return .perform(long: true)
    }

    mutating func release() -> Outcome {
        defer { held = false }
        guard held, !consumed else { return .none }
        consumed = true
        return .perform(long: false)
    }
}
