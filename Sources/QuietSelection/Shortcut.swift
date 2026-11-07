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
        79: "F18", 80: "F19", 90: "F20",
        // Numeric keypad: separate keys from the top-row digits.
        82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5", 88: "Num 6",
        89: "Num 7", 91: "Num 8", 92: "Num 9", 65: "Num .", 67: "Num *", 69: "Num +", 75: "Num /",
        78: "Num -", 81: "Num =", 71: "Num Clear"
    ]
    static let keypadZero: UInt32 = 82

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

/// What a gesture does: a text source combined with a reading mode, or a
/// helper such as repeating the last reading.
enum ReadFunction: String, CaseIterable {
    // Raw values of 1.10 are kept so saved settings stay valid.
    case read, translate, primary
    case regionRead = "screenRegion", regionTranslate, regionPrimary
    case repeatLast

    var title: String {
        switch self {
        case .read: return "Текст: читать"
        case .translate: return "Текст: перевести"
        case .primary: return "Текст: основным голосом"
        case .regionRead: return "Область: читать"
        case .regionTranslate: return "Область: перевести"
        case .regionPrimary: return "Область: основным голосом"
        case .repeatLast: return "Повторить последнее"
        }
    }
}

enum PressKind: CaseIterable { case short, double, long }

/// One global shortcut with its single-, double- and long-press functions.
struct ShortcutSlot: Equatable {
    var shortcut: Shortcut?
    var short: ReadFunction?
    var double: ReadFunction?
    var long: ReadFunction?

    static let count = 4
    static func hotKeyID(_ index: Int) -> UInt32 { UInt32(index + 1) }

    /// Source per shortcut, mode per gesture: single = read, double = translate,
    /// long = primary voice. Option + Esc: text from the system; Command + Esc:
    /// recognition under the pointer (the drawn region until that exists);
    /// Control + Esc: drawn screen region. Control + Num 0 repeats.
    static let defaults: [ShortcutSlot] = [
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.option),
                     short: .read, double: .translate, long: .primary),
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.command),
                     short: .regionRead, double: .regionTranslate, long: .regionPrimary),
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.control),
                     short: .regionRead, double: .regionTranslate, long: .regionPrimary),
        ShortcutSlot(shortcut: Shortcut(keyCode: Shortcut.keypadZero, modifiers: Shortcut.control),
                     short: .repeatLast, double: nil, long: nil)
    ]

    func function(_ kind: PressKind) -> ReadFunction? {
        switch kind { case .short: return short; case .double: return double; case .long: return long }
    }
    mutating func set(_ function: ReadFunction?, for kind: PressKind) {
        switch kind { case .short: short = function; case .double: double = function; case .long: long = function }
    }

    var preferenceValue: [String: Any] {
        var value: [String: Any] = [:]
        if let shortcut { value.merge(shortcut.preferenceValue) { $1 } }
        if let short { value["short"] = short.rawValue }
        if let double { value["double"] = double.rawValue }
        if let long { value["long"] = long.rawValue }
        return value
    }

    init(shortcut: Shortcut?, short: ReadFunction?, double: ReadFunction?, long: ReadFunction?) {
        self.shortcut = shortcut; self.short = short; self.double = double; self.long = long
    }

    init(preferenceValue value: Any?) {
        let dictionary = value as? [String: Any] ?? [:]
        func function(_ key: String) -> ReadFunction? { (dictionary[key] as? String).flatMap(ReadFunction.init(rawValue:)) }
        shortcut = Shortcut(preferenceValue: dictionary)
        short = function("short"); double = function("double"); long = function("long")
    }
}

enum ShortcutSettings {
    static let preferenceKey = "ShortcutSlots"
    /// 2: source per shortcut, mode per gesture (version 1.11).
    static let layoutKey = "ShortcutLayout"
    static let layoutVersion = 2
    /// Format of version 1.9.0–1.9.1: one shortcut per action.
    static let actionPreferenceKey = "Shortcuts"
    static let thresholdKey = "LongPressThreshold"
    static let defaultThreshold = 0.4
    static let thresholdRange = 0.2...1.2
    static let doubleIntervalKey = "DoublePressInterval"
    static let defaultDoubleInterval = 0.3
    static let doubleIntervalRange = 0.15...0.6

    static func threshold(_ value: Any?) -> Double { clamp(value, defaultThreshold, thresholdRange) }
    static func doubleInterval(_ value: Any?) -> Double { clamp(value, defaultDoubleInterval, doubleIntervalRange) }
    private static func clamp(_ value: Any?, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, number.doubleValue))
    }

    /// Saved slots of the current layout as they are. Earlier settings keep
    /// their keys, receive the current default functions, and gain the
    /// Control + Num 0 repeat shortcut.
    static func load(saved: [Any]?, layout: Int, actions: [String: Any]?, legacy: (String) -> Any?) -> [ShortcutSlot] {
        var slots: [ShortcutSlot]
        if let saved, saved.count == ShortcutSlot.count, layout >= layoutVersion {
            slots = saved.map(ShortcutSlot.init(preferenceValue:))
        } else {
            slots = ShortcutSlot.defaults
            if let saved, saved.count == 3 {
                // 1.10: three slots with read, translate and screen-region keys.
                for index in 0..<3 { slots[index].shortcut = ShortcutSlot(preferenceValue: saved[index]).shortcut }
            } else {
                for (index, name) in ["read", "translate", "screen"].enumerated() {
                    slots[index].shortcut = Shortcut(preferenceValue: actions?[name]) ?? legacyShortcut(name, legacy: legacy)
                }
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
    static func assignment(of function: ReadFunction, in slots: [ShortcutSlot]) -> (index: Int, kind: PressKind)? {
        for (index, slot) in slots.enumerated() {
            for kind in PressKind.allCases where slot.function(kind) == function { return (index, kind) }
        }
        return nil
    }
}

/// Single, double or long press of one shortcut.
/// - A press while something is being read stops it at once.
/// - Without long or double functions the single one runs on press.
/// - With a long function, holding past the threshold runs it (after a click).
/// - With a double function, a released single press waits for a second press;
///   a second press within the interval runs the double function.
struct PressGesture {
    enum Outcome: Equatable { case none, stop, perform(PressKind), awaitSecond }
    private(set) var held = false
    private var consumed = false
    private var awaitingSecond = false

    mutating func press(busy: Bool, hasLong: Bool, hasDouble: Bool) -> Outcome {
        held = true
        consumed = true
        if awaitingSecond {
            awaitingSecond = false
            return .perform(.double)
        }
        if busy { return .stop }
        if !hasLong && !hasDouble { return .perform(.short) }
        consumed = false
        return .none
    }

    mutating func thresholdReached() -> Outcome {
        guard held, !consumed else { return .none }
        consumed = true
        return .perform(.long)
    }

    mutating func release(hasDouble: Bool) -> Outcome {
        defer { held = false }
        guard held, !consumed else { return .none }
        consumed = true
        if hasDouble {
            awaitingSecond = true
            return .awaitSecond
        }
        return .perform(.short)
    }

    mutating func secondPressWindowEnded() -> Outcome {
        guard awaitingSecond else { return .none }
        awaitingSecond = false
        return .perform(.short)
    }
}
