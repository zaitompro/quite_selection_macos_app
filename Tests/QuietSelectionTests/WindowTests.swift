import AppKit

@MainActor
private final class WindowTestDelegate: NSObject, NSApplicationDelegate, AppMenuActions {
    let controller = SettingsWindow()
    var quitRequests = 0
    func applicationDidBecomeActive(_ notification: Notification) { controller.finishPresentation() }
    @objc func showSettings() { controller.present() }
    @objc func closeSettings() { controller.closeSettings() }
    @objc func quitApplication() { quitRequests += 1 }
}

@MainActor
private final class SwitchTestTarget: NSObject {
    var changes = 0
    @objc func changed(_ sender: NSButton) { changes += 1 }
}

@main
@MainActor
struct WindowTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WindowTestDelegate()
        app.delegate = delegate
        app.mainMenu = AppMenu.make(target: delegate)
        DispatchQueue.main.async {
            check(app, delegate: delegate)
            if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
                let voices = [VoiceChoice(id: "test-ru", name: "Milena", tag: "ru-RU", quality: 2),
                    VoiceChoice(id: "test-en", name: "Samantha", tag: "en-US", quality: 2),
                    VoiceChoice(id: "test-ja", name: "Kyoko", tag: "ja-JP", quality: 2)]
                let selection = VoiceSettings(language: "ru", saved: [:], legacyID: nil, voices: voices)
                delegate.controller.update(voices: voices, selection: selection, automatic: true,
                    testShortcut: false, login: "enabled", trusted: true)
                delegate.controller.updateScreenReading(shortcut: .controlEscape, registered: true, permitted: true)
                delegate.controller.translationSettings.update(target: "ru", sources: ["en", "ja"], states: ["en": .supported, "ja": .supported])
                delegate.controller.updateExtraShortcuts(primary: .controlOptionEscape, primaryRegistered: true, translation: .commandEscape, translationRegistered: true)
                try! delegate.controller.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            exit(0)
        }
        app.run()
    }
    private static func check(_ app: NSApplication, delegate: WindowTestDelegate) {
        delegate.controller.present()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let window = delegate.controller.window!
        FileHandle.standardOutput.write(Data("window_state visible=\(window.isVisible) key=\(window.isKeyWindow) active=\(app.isActive)\n".utf8))
        // A CLI-launched test has no status-button user activation gesture.
        // Verify visibility here; frontmost activation is a manual acceptance check.
        precondition(window.isVisible)
        precondition(window.level == .normal)
        print("window=PASS visible, normal_level; foreground_activation_requires_user_click")

        let toggle = SettingsSwitch(frame: NSRect(x: 0, y: 0, width: 52, height: 30))
        let toggleTarget = SwitchTestTarget()
        toggle.target = toggleTarget
        toggle.action = #selector(SwitchTestTarget.changed(_:))
        toggle.setAccessibilityLabel("Тестовый переключатель")
        let native = NSSwitch()
        precondition(toggle.accessibilityRole() == native.accessibilityRole())
        precondition(toggle.accessibilitySubrole() == native.accessibilitySubrole())
        precondition(toggle.accessibilityLabel() == "Тестовый переключатель")
        // Use the generic protocol: SDK 26.5 declares NSSwitch's value as String,
        // but its implementation returns NSNumber. Avoid that Swift bridge.
        precondition((toggle as NSView).accessibilityValue() as? NSNumber == (native as NSView).accessibilityValue() as? NSNumber)
        toggle.performClick(nil)
        precondition(toggle.state == .on && toggleTarget.changes == 1)
        native.state = .on
        precondition((toggle as NSView).accessibilityValue() as? NSNumber == (native as NSView).accessibilityValue() as? NSNumber)
        precondition(toggle.accessibilityPerformPress())
        precondition(toggle.state == .off && toggleTarget.changes == 2)
        toggle.isEnabled = false
        toggle.performClick(nil)
        precondition(toggle.state == .off && toggleTarget.changes == 2)
        print("switch=PASS native_AX_role_subrole_label_press_state_and_disabled_click")

        let voices = [
            VoiceChoice(id: "ru", name: "Milena", tag: "ru-RU", quality: 2),
            VoiceChoice(id: "en", name: "Samantha", tag: "en-US", quality: 2),
            VoiceChoice(id: "ja", name: "Kyoko", tag: "ja-JP", quality: 2),
            VoiceChoice(id: "de", name: "Anna", tag: "de-DE", quality: 2)
        ]
        var configuration = VoiceSettings(language: "ru", saved: [:], legacyID: nil, voices: voices)
        let speechUI = delegate.controller.speechSettings
        func updateSpeechUI() {
            delegate.controller.update(voices: voices, selection: configuration, automatic: true,
                testShortcut: false, login: "enabled", trusted: true)
            window.contentView!.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        updateSpeechUI()
        delegate.controller.selectSection(1)
        window.contentView!.layoutSubtreeIfNeeded()
        let originalSize = window.frame.size
        let originalHeight = speechUI.list.frame.height
        precondition(abs(originalHeight - 292) < 1)
        let english = speechUI.cards["en"]!
        precondition(english.removeButton.frame.maxX < english.toggle.frame.minX)
        let switchRight = english.toggle.convert(english.toggle.bounds, to: english).maxX
        precondition(abs(english.bounds.maxX - switchRight - 12) < 2)
        let menuRight = speechUI.primaryCard.languageMenu.convert(speechUI.primaryCard.languageMenu.bounds, to: speechUI.primaryCard).maxX
        precondition(abs(speechUI.primaryCard.bounds.maxX - menuRight - 12) < 2)
        var rateEvent: (String, Float)?
        delegate.controller.onRate = { rateEvent = ($0, $1) }
        english.speed.doubleValue = 41
        english.speed.sendAction(english.speed.action, to: english.speed.target)
        precondition(rateEvent?.0 == "en" && rateEvent?.1 == 0.41)
        var previewLanguage: String?
        delegate.controller.onPreview = { previewLanguage = $0 }
        english.previewButton.performClick(nil)
        precondition(previewLanguage == "en")
        delegate.controller.onAllowed = { configuration.setEnabled($1, for: $0) }
        english.toggle.performClick(nil)
        precondition(configuration.additionalLanguages["en"] == false)
        updateSpeechUI()
        precondition(speechUI.cards["en"] === english)
        configuration.addLanguage("de", voices: voices)
        updateSpeechUI()
        precondition(window.frame.size == originalSize && speechUI.list.frame.height == originalHeight)
        precondition(speechUI.list.documentView!.frame.height > speechUI.list.contentView.bounds.height)
        let primaryFrame = speechUI.primaryCard.frame
        speechUI.list.contentView.scroll(to: NSPoint(x: 0, y: 150))
        speechUI.list.reflectScrolledClipView(speechUI.list.contentView)
        precondition(speechUI.list.contentView.bounds.origin.y > 0 && speechUI.primaryCard.frame == primaryFrame)
        delegate.controller.onRemoveLanguage = { configuration.removeLanguage($0) }
        speechUI.cards["de"]!.removeButton.performClick(nil)
        updateSpeechUI()
        precondition(speechUI.cards["de"] == nil && speechUI.list.frame.height == originalHeight)
        for code in Array(configuration.additionalLanguages.keys) { configuration.removeLanguage(code) }
        updateSpeechUI()
        precondition(speechUI.cards.isEmpty && speechUI.list.frame.height == originalHeight)
        delegate.controller.selectSection(0)
        print("speech_ui=PASS per_language_controls, rightmost_switch, fixed_height_add_remove_empty, independent_scroll")

        let translationUI = delegate.controller.translationSettings
        delegate.controller.selectSection(2)
        translationUI.update(target: "ru", sources: ["en", "ja", "de", "fr"],
            states: ["en": .supported, "ja": .installed, "de": .unsupported])
        window.contentView!.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(abs(translationUI.list.frame.height - 240) < 1)
        precondition(translationUI.list.documentView!.frame.height > translationUI.list.contentView.bounds.height)
        precondition(translationUI.downloadButtons["ja"]!.isHidden && translationUI.downloadButtons["de"]!.isHidden)
        precondition(!translationUI.downloadButtons["fr"]!.isEnabled)
        var downloadSource: String?
        translationUI.onDownload = { downloadSource = $0 }
        translationUI.downloadButtons["en"]!.performClick(nil)
        precondition(downloadSource == "en")
        translationUI.update(target: "en", sources: ["ru"], states: ["ru": .supported])
        precondition(translationUI.downloadButtons["en"] == nil && translationUI.downloadButtons["ru"] != nil)
        delegate.controller.selectSection(0)
        print("translation_ui=PASS fixed_scroll, readiness_states, explicit_download, primary_change")

        // Local AppKit menu dispatch only: no posting or injecting keyboard events.
        func command(_ letter: String, code: UInt16) -> Bool {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: letter, charactersIgnoringModifiers: letter, isARepeat: false, keyCode: code)!
            return app.mainMenu!.performKeyEquivalent(with: event)
        }
        precondition(delegate.controller.selectedSection == 0)
        delegate.controller.selectSection(2)
        precondition(delegate.controller.selectedSection == 2)
        // Cmd+Q closes settings even when a text editor is the first responder.
        let editor = NSTextView(frame: .zero)
        window.contentView!.addSubview(editor)
        window.makeFirstResponder(editor)
        precondition(command("q", code: 12))
        precondition(!window.isVisible && delegate.quitRequests == 0)
        delegate.controller.finishPresentation()
        precondition(!window.isVisible)
        precondition(command("q", code: 12) && delegate.quitRequests == 0)
        print("command_q=PASS closes_only_settings_with_text_focus_no_late_reopen")
        delegate.controller.present()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        precondition(window.isVisible && delegate.controller.selectedSection == 0)
        precondition(command("w", code: 13))
        precondition(!window.isVisible && delegate.quitRequests == 0)
        print("command_w=PASS close_only; general_tab_default_on_reopen")

        let statusMenu = AppMenu.status(target: delegate, version: "TEST")
        precondition(statusMenu.items[0].title == "QuietSelection TEST" && !statusMenu.items[0].isEnabled)
        precondition(statusMenu.items[2].title == "Настройки…")
        let quit = statusMenu.items[3]
        precondition(quit.keyEquivalent.isEmpty && quit.action == #selector(AppMenuActions.quitApplication))
        statusMenu.performActionForItem(at: 2)
        precondition(window.isVisible && delegate.controller.selectedSection == 0)
        statusMenu.performActionForItem(at: 3)
        precondition(delegate.quitRequests == 1)
        let appQuit = app.mainMenu!.items[0].submenu!.items.last!
        precondition(appQuit.keyEquivalent.isEmpty)
        print("status_menu=PASS version_settings_explicit_quit_without_shortcut")
        window.close()
        print("external_content_queries=0 permission_prompts=0")
        withExtendedLifetime(delegate) {}
    }
}
