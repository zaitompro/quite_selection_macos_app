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

        check(Shortcut(keyCode: Shortcut.keypadZero, modifiers: Shortcut.control).title { _ in "0" } == "Control + Num 0",
              "keypad keys named apart from the top row")

        // Layout: source per shortcut, mode per gesture.
        func load(saved: [Any]? = nil, layout: Int = 0, actions: [String: Any]? = nil, _ values: [String: Any] = [:]) -> [ShortcutSlot] {
            ShortcutSettings.load(saved: saved, layout: layout, actions: actions, legacy: { values[$0] })
        }
        let fresh = load()
        check(fresh.count == 4, "four slots")
        check(fresh[0].short == .read && fresh[0].double == .translate && fresh[0].long == .primary, "text source: read, translate, primary")
        check(fresh[1].short == .pointerRead && fresh[1].double == .pointerTranslate && fresh[1].long == .pointerPrimary,
              "Command + Esc: recognition under the pointer")
        check(fresh[2].short == .regionRead && fresh[2].double == .regionTranslate && fresh[2].long == .regionPrimary,
              "Control + Esc: drawn region")
        var placeholder = ShortcutSlot.defaults
        placeholder[1].short = .regionRead; placeholder[1].double = .regionTranslate; placeholder[1].long = .regionPrimary
        let upgraded = load(saved: placeholder.map(\.preferenceValue), layout: 2)
        check(upgraded[1].short == .pointerRead && upgraded[1].long == .pointerPrimary && upgraded[1].shortcut == placeholder[1].shortcut,
              "1.11 placeholder on Command + Esc becomes recognition under the pointer")
        var chosen = placeholder
        chosen[1].double = nil
        check(load(saved: chosen.map(\.preferenceValue), layout: 2)[1] == chosen[1], "user-changed slot kept on upgrade")
        check(fresh[3].shortcut == Shortcut(keyCode: Shortcut.keypadZero, modifiers: Shortcut.control)
              && fresh[3].short == .repeatLast && fresh[3].double == nil && fresh[3].long == nil, "Control + Num 0 repeats")
        check(fresh[0].shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.option | Shortcut.shift), "no setting: Option + Shift + Esc as before")
        let legacyChoices = load(["UseOptionEscape": NSNumber(value: true), "OCRShortcut": NSNumber(value: 1),
                                  "TranslationShortcut": NSNumber(value: 1)])
        check(legacyChoices[0].shortcut == optionEsc && legacyChoices[1].shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.command | Shortcut.shift)
              && legacyChoices[2].shortcut == Shortcut(keyCode: esc, modifiers: Shortcut.control | Shortcut.shift), "1.8 keys kept")
        let r = Shortcut(keyCode: 15, modifiers: Shortcut.command | Shortcut.option)
        let fromActions = load(actions: ["read": r.preferenceValue], ["UseOptionEscape": NSNumber(value: true)])
        check(fromActions[0].shortcut == r, "1.9 per-action keys kept")
        // 1.10: three slots saved with older functions get the new layout, same keys.
        let old: [Any] = [["keyCode": 53, "modifiers": 2048, "short": "read", "long": "primary"],
                          ["keyCode": 53, "modifiers": 256, "short": "translate", "long": "repeatLast"],
                          ["keyCode": 53, "modifiers": 4096, "short": "screenRegion"]]
        let migrated = load(saved: old, layout: 0)
        check(migrated.map(\.shortcut) == ShortcutSlot.defaults.map(\.shortcut), "1.10 keys kept")
        check(migrated.map { $0.short } == ShortcutSlot.defaults.map { $0.short }
              && migrated.map { $0.double } == ShortcutSlot.defaults.map { $0.double }, "1.10 functions replaced by the new layout")

        // Saved slots of this layout win; duplicates resolved; round trip.
        var custom = ShortcutSlot.defaults
        custom[2].long = .repeatLast; custom[1].short = nil; custom[0].double = nil
        check(load(saved: custom.map(\.preferenceValue), layout: 3) == custom, "slot round trip, including empty functions")
        check(load(saved: custom.map(\.preferenceValue), layout: 0) != custom, "older layout number migrates")
        var clash = ShortcutSlot.defaults
        clash[1].shortcut = clash[0].shortcut
        let resolved = load(saved: clash.map(\.preferenceValue), layout: 3)
        check(Set(resolved.compactMap(\.shortcut)).count == resolved.compactMap(\.shortcut).count, "no two slots share keys")
        check(ShortcutSettings.conflict(for: 0, shortcut: ShortcutSlot.defaults[2].shortcut!, in: fresh) == 2, "conflict found")
        check(ShortcutSettings.assignment(of: .regionRead, in: fresh)!.index == 2, "assignment of a function")
        check(ShortcutSettings.assignment(of: .regionTranslate, in: fresh)!.kind == .double, "double assignment reported")
        check(ShortcutSettings.threshold(nil) == 0.4 && ShortcutSettings.threshold(NSNumber(value: 5.0)) == 1.2, "threshold limits")
        check(ShortcutSettings.doubleInterval(nil) == 0.3 && ShortcutSettings.doubleInterval(NSNumber(value: 0.01)) == 0.15
              && ShortcutSettings.doubleInterval(NSNumber(value: 2)) == 0.6, "double interval limits")
        check(ReadFunction(rawValue: "screenRegion") == .regionRead, "1.10 raw value still valid")

        // System overlaps.
        check(optionEsc.systemConflict != nil, "Speak Selection overlap explained")
        check(Shortcut(keyCode: 15, modifiers: Shortcut.command | Shortcut.shift).systemConflict == nil, "no warning for unrelated keys")

        // Gestures.
        var g = PressGesture()
        check(g.press(busy: false, hasLong: false, hasDouble: false) == .perform(.short) && g.release(hasDouble: false) == .none,
              "only a single function: runs on press")
        g = PressGesture()
        check(g.press(busy: false, hasLong: true, hasDouble: false) == .none && g.release(hasDouble: false) == .perform(.short),
              "single with long available: on release")
        g = PressGesture()
        check(g.press(busy: false, hasLong: true, hasDouble: true) == .none && g.thresholdReached() == .perform(.long)
              && g.release(hasDouble: true) == .none && g.secondPressWindowEnded() == .none, "held: long once")
        g = PressGesture()
        check(g.press(busy: false, hasLong: true, hasDouble: true) == .none && g.release(hasDouble: true) == .awaitSecond
              && g.secondPressWindowEnded() == .perform(.short), "single tap waits, then single")
        g = PressGesture()
        _ = g.press(busy: false, hasLong: true, hasDouble: true); _ = g.release(hasDouble: true)
        check(g.press(busy: false, hasLong: true, hasDouble: true) == .perform(.double) && g.thresholdReached() == .none
              && g.release(hasDouble: true) == .none && g.secondPressWindowEnded() == .none, "second tap: double only")
        g = PressGesture()
        check(g.press(busy: true, hasLong: true, hasDouble: true) == .stop && g.release(hasDouble: true) == .none
              && g.secondPressWindowEnded() == .none, "press while reading only stops")
        g = PressGesture()
        _ = g.press(busy: false, hasLong: true, hasDouble: false); _ = g.release(hasDouble: false)
        check(g.thresholdReached() == .none, "late long timer after release ignored")
        var idle = PressGesture()
        check(idle.release(hasDouble: true) == .none && idle.secondPressWindowEnded() == .none, "nothing without a press")
        print("\(count) checks passed; no keys registered.")
    }
}
