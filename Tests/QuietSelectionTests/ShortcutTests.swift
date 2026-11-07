import Foundation

// Shortcut rules only: no keys are registered and no events are read.
@main struct Tests {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { print("FAIL: \(name)"); exit(1) }
        count += 1
        print("PASS: \(name)")
    }
    static func main() {
        let esc = Shortcut.escape
        let optionEsc = Shortcut(keyCode: esc, modifiers: Shortcut.option)
        check(optionEsc.isValid, "Option + key is valid")
        check(!Shortcut(keyCode: 15, modifiers: Shortcut.shift).isValid, "Shift alone is not enough")
        check(!Shortcut(keyCode: 15, modifiers: 0).isValid, "plain key is not a shortcut")
        check(Shortcut(keyCode: 15, modifiers: Shortcut.control | 0x10000).modifiers == Shortcut.control, "unknown modifier bits dropped")

        let all = Shortcut(keyCode: 15, modifiers: Shortcut.allModifiers)
        check(all.title { _ in "r" } == "Control + Option + Shift + Command + R", "Apple modifier order, uppercase key")
        check(optionEsc.title { _ in nil } == "Option + Esc", "special key name")
        check(Shortcut(keyCode: 122, modifiers: Shortcut.command).title { _ in nil } == "Command + F1", "function key")
        check(Shortcut(keyCode: 200, modifiers: Shortcut.command).title { _ in nil } == "Command + Клавиша 200", "unknown key fallback")

        // Migration from the fixed choices of earlier versions.
        func legacy(_ values: [String: Any]) -> [ShortcutAction: Shortcut] {
            ShortcutSettings.load(saved: nil, legacy: { values[$0] })
        }
        let fresh = legacy([:])
        check(fresh[.read] == Shortcut(keyCode: esc, modifiers: Shortcut.option | Shortcut.shift), "no setting: Option + Shift + Esc as before")
        check(fresh[.screen] == ShortcutAction.screen.defaultShortcut && fresh[.primary] == ShortcutAction.primary.defaultShortcut
              && fresh[.translate] == ShortcutAction.translate.defaultShortcut, "other defaults unchanged")
        let customised = legacy(["UseOptionEscape": NSNumber(value: true), "OCRShortcut": NSNumber(value: 1),
                                 "PrimaryShortcut": NSNumber(value: 1), "TranslationShortcut": NSNumber(value: 1)])
        check(customised[.read] == optionEsc, "Option + Esc kept")
        check(customised[.screen] == Shortcut(keyCode: esc, modifiers: Shortcut.control | Shortcut.shift), "Control + Shift + Esc kept")
        check(customised[.primary] == Shortcut(keyCode: 15, modifiers: Shortcut.control | Shortcut.option), "Control + Option + R kept")
        check(customised[.translate] == Shortcut(keyCode: esc, modifiers: Shortcut.command | Shortcut.shift), "Command + Shift + Esc kept")

        // Saved values win; invalid saved values fall back; duplicates are resolved.
        let saved: [String: Any] = ["read": ["keyCode": 15, "modifiers": Int(Shortcut.command | Shortcut.option)],
                                    "screen": ["keyCode": 15, "modifiers": Int(Shortcut.shift)]]
        let loaded = ShortcutSettings.load(saved: saved, legacy: { _ in nil })
        check(loaded[.read] == Shortcut(keyCode: 15, modifiers: Shortcut.command | Shortcut.option), "saved shortcut loaded")
        check(loaded[.screen] == ShortcutAction.screen.defaultShortcut, "invalid saved shortcut ignored")
        let clash: [String: Any] = ["read": ShortcutAction.screen.defaultShortcut.preferenceValue]
        let resolved = ShortcutSettings.load(saved: clash, legacy: { _ in nil })
        check(Set(resolved.values).count == ShortcutAction.allCases.count, "no two actions share keys after loading")
        let round = ShortcutSettings.load(saved: ShortcutSettings.preferenceValue(customised), legacy: { _ in nil })
        check(round == customised, "preference round trip")

        // Conflicts between actions and with system features.
        check(ShortcutSettings.conflict(for: .read, shortcut: ShortcutAction.screen.defaultShortcut, in: fresh) == .screen,
              "conflict with another action found")
        check(ShortcutSettings.conflict(for: .screen, shortcut: ShortcutAction.screen.defaultShortcut, in: fresh) == nil,
              "own current shortcut is not a conflict")
        check(ShortcutAction.read.systemConflict(optionEsc) != nil, "Speak Selection overlap explained")
        check(ShortcutAction.translate.systemConflict(ShortcutAction.translate.defaultShortcut) != nil, "Accessibility Reader overlap explained")
        check(ShortcutAction.read.systemConflict(Shortcut(keyCode: 15, modifiers: Shortcut.command | Shortcut.shift)) == nil,
              "no warning for unrelated keys")
        check(Set(ShortcutAction.allCases.map(\.hotKeyID)) == [1, 2, 3, 4], "hot key identifiers stable")
        print("\(count) checks passed; no keys registered.")
    }
}
