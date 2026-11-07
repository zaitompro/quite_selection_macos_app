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

        // Migration into three slots from earlier versions.
        func load(saved: [Any]? = nil, actions: [String: Any]? = nil, _ values: [String: Any] = [:]) -> [ShortcutSlot] {
            ShortcutSettings.load(saved: saved, actions: actions, legacy: { values[$0] })
        }
        let fresh = load()
        check(fresh.count == 3, "three slots")
        check(fresh[0].shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.option | Shortcut.shift)
              && fresh[0].short == .read && fresh[0].long == .primary, "no setting: Option + Shift + Esc as before, long = primary voice")
        check(fresh[1].short == .translate && fresh[1].long == .repeatLast, "translation slot with repeat on long press")
        check(fresh[2].shortcut == ShortcutSlot.defaults[2].shortcut && fresh[2].short == .screenRegion && fresh[2].long == nil,
              "screen region slot")
        let legacyChoices = load(["UseOptionEscape": NSNumber(value: true), "OCRShortcut": NSNumber(value: 1),
                                  "PrimaryShortcut": NSNumber(value: 1), "TranslationShortcut": NSNumber(value: 1)])
        check(legacyChoices[0].shortcut == optionEsc, "1.8 Option + Esc kept")
        check(legacyChoices[1].shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.command | Shortcut.shift), "1.8 Command + Shift + Esc kept")
        check(legacyChoices[2].shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.control | Shortcut.shift), "1.8 Control + Shift + Esc kept")
        let r = Shortcut(keyCode: 15, modifiers: Shortcut.command | Shortcut.option)
        let actions: [String: Any] = ["read": r.preferenceValue, "translate": ShortcutSlot.defaults[1].shortcut!.preferenceValue,
                                      "screen": ShortcutSlot.defaults[2].shortcut!.preferenceValue,
                                      "primary": Shortcut(keyCode: esc, modifiers: Shortcut.control | Shortcut.option).preferenceValue]
        let fromActions = load(actions: actions, ["UseOptionEscape": NSNumber(value: true)])
        check(fromActions[0].shortcut == r && fromActions[0].long == .primary, "1.9 per-action shortcuts moved; primary on long press")
        check(!fromActions.contains { $0.shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.control | Shortcut.option) },
              "three-key primary shortcut dropped")

        // Saved slots win; duplicates are resolved; round trip.
        var custom = ShortcutSlot.defaults
        custom[2].long = .repeatLast; custom[1].short = nil
        let round = load(saved: custom.map(\.preferenceValue))
        check(round == custom, "slot preference round trip, including empty functions")
        var clash = ShortcutSlot.defaults
        clash[1].shortcut = clash[0].shortcut
        let resolved = load(saved: clash.map(\.preferenceValue))
        check(Set(resolved.compactMap(\.shortcut)).count == resolved.compactMap(\.shortcut).count, "no two slots share keys after loading")
        check(load(saved: [["keyCode": 15, "modifiers": Int(Shortcut.shift)], [:], [:]])[0].shortcut == nil, "invalid saved shortcut ignored")
        check(ShortcutSettings.conflict(for: 0, shortcut: ShortcutSlot.defaults[2].shortcut!, in: fresh) == 2, "conflict found")
        check(ShortcutSettings.conflict(for: 2, shortcut: ShortcutSlot.defaults[2].shortcut!, in: fresh) == nil, "own shortcut is no conflict")
        check(ShortcutSettings.assignment(of: .screenRegion, in: custom)! == (2, false), "assignment of short function")
        check(ShortcutSettings.assignment(of: .repeatLast, in: custom)! == (1, true), "assignment of long function")
        check(ShortcutSettings.threshold(nil) == 0.4 && ShortcutSettings.threshold(NSNumber(value: 5.0)) == 1.2
              && ShortcutSettings.threshold(NSNumber(value: 0.01)) == 0.2, "threshold default and limits")

        // System overlaps.
        check(optionEsc.systemConflict != nil, "Speak Selection overlap explained")
        check(ShortcutSlot.defaults[1].shortcut!.systemConflict != nil, "Accessibility Reader overlap explained")
        check(Shortcut(keyCode: 15, modifiers: Shortcut.command | Shortcut.shift).systemConflict == nil, "no warning for unrelated keys")

        // Short and long presses.
        var g = PressGesture()
        check(g.press(busy: false, hasLong: true) == .none && g.release() == .perform(long: false), "quick release: short")
        g = PressGesture()
        check(g.press(busy: false, hasLong: true) == .none && g.thresholdReached() == .perform(long: true)
              && g.release() == .none, "held past threshold: long once, release does nothing")
        g = PressGesture()
        check(g.press(busy: false, hasLong: false) == .perform(long: false) && g.release() == .none,
              "no long function: short at once")
        g = PressGesture()
        check(g.press(busy: true, hasLong: true) == .stop && g.thresholdReached() == .none && g.release() == .none,
              "press while reading only stops")
        g = PressGesture()
        _ = g.press(busy: false, hasLong: true); _ = g.release()
        check(g.thresholdReached() == .none, "late timer after release ignored")
        var idle = PressGesture()
        check(idle.release() == .none, "release without press ignored")
        print("\(count) checks passed; no keys registered.")
    }
}
