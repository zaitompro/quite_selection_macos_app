import AppKit
import ApplicationServices
import Carbon
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppMenuActions {
    private let speech = Speech()
    private let worker = DispatchQueue(label: "local.quietselection.ax", qos: .userInitiated)
    private var hotKey: HotKey?
    private var ocrHotKey: HotKey?
    private var ocrShortcut = OCRShortcut.controlEscape
    private var ocrRegistered = false
    private let regionPicker = RegionPicker()
    private var captureTask: Task<Void, Never>?
    private var ocrJob: OCRJob?
    private var ocrBusy = false
    private var ocrGeneration = 0
    private let ocrWorker = DispatchQueue(label: "local.quietselection.ocr", qos: .userInitiated)
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindow?
    private var testShortcut = true
    private var registered = false
    private var pending = false
    private var generation = 0
    private var message = "Готово"
    private let preferences = UserDefaults.standard
    private var voices: [VoiceChoice] = []
    private var selection = VoiceSettings(language: "ru", saved: [:], legacyID: nil, voices: [])
    private var automatic = false
    private var allowed: [String] { selection.allowedLanguages }

    static func availableVoices() -> [VoiceChoice] {
        Speech.installedVoices().map {
            VoiceChoice(id: $0.identifier, name: $0.name, tag: $0.language, quality: $0.quality.rawValue)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenu.make(target: self)
        testShortcut = !preferences.bool(forKey: "UseOptionEscape")
        voices = Self.availableVoices()
        selection = VoiceSettings(language: preferences.string(forKey: "SelectedLanguage"),
            saved: preferences.dictionary(forKey: "VoicesByLanguage") as? [String: String] ?? [:],
            legacyID: preferences.string(forKey: "VoiceID"), voices: voices,
            rates: (preferences.dictionary(forKey: "SpeechRatesByLanguage") as? [String: NSNumber] ?? [:]).mapValues { $0.floatValue },
            legacyRate: preferences.object(forKey: "SpeechRate") == nil ? AVSpeechUtteranceDefaultSpeechRate : preferences.float(forKey: "SpeechRate"),
            additional: preferences.dictionary(forKey: "AdditionalLanguages") as? [String: Bool],
            legacyAllowed: preferences.stringArray(forKey: "AllowedLanguages") ?? ["ru", "en", "ja"])
        automatic = preferences.bool(forKey: "AutomaticLanguage")
        applySpeechSettings()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Читать"
        statusItem.button?.setAccessibilityLabel("Меню QuietSelection")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        statusItem.menu = AppMenu.status(target: self, version: version)
        speech.finished = { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.speech.speaking, !self.ocrBusy, !self.regionPicker.active, !self.pending else { return }
                self.setStatus("Готово")
            }
        }
        do {
            hotKey = try HotKey()
            hotKey?.action = { [weak self] in self?.trigger() }
            changeShortcut(testShortcut)
        } catch { setStatus("Не удалось установить обработчик сочетания") }
        ocrShortcut = OCRShortcut(rawValue: preferences.integer(forKey: "OCRShortcut")) ?? .controlEscape
        do {
            ocrHotKey = try HotKey(identifier: 2)
            ocrHotKey?.action = { [weak self] in self?.triggerOCR() }
            changeOCRShortcut(ocrShortcut)
        } catch { setStatus("Не удалось установить сочетание чтения области") }
        if CommandLine.arguments.contains("--show-settings") { showSettings() }
    }

    private func applySpeechSettings() {
        speech.voiceID = selection.selectedVoice(in: voices)?.id
        speech.automatic = automatic
        speech.allowedLanguages = allowed
        speech.voicesByLanguage = selection.voicesByLanguage
        speech.fallbackLanguage = selection.language
        speech.rate = selection.rate(for: selection.language)
        speech.ratesByLanguage = selection.ratesByLanguage
        preferences.set(selection.language, forKey: "SelectedLanguage")
        preferences.set(selection.voicesByLanguage, forKey: "VoicesByLanguage")
        preferences.set(automatic, forKey: "AutomaticLanguage")
        preferences.set(allowed, forKey: "AllowedLanguages")
        preferences.set(selection.additionalLanguages, forKey: "AdditionalLanguages")
        preferences.set(selection.ratesByLanguage, forKey: "SpeechRatesByLanguage")
        preferences.set(selection.initialRate, forKey: "SpeechRate")
    }
    private func refresh() {
        voices = Self.availableVoices()
        speech.voiceID = selection.selectedVoice(in: voices)?.id
        settings?.update(voices: voices, selection: selection,
            automatic: automatic, testShortcut: testShortcut,
            login: LoginLaunch.statusCode, trusted: AXIsProcessTrusted())
        settings?.setStatus(message)
        settings?.updateScreenReading(shortcut: ocrShortcut, registered: ocrRegistered,
                                      permitted: CGPreflightScreenCaptureAccess())
    }
    @objc func closeSettings() { settings?.closeSettings() }
    @objc func quitApplication() { NSApp.terminate(nil) }
    @objc func showSettings() {
        // Request activation while handling the user's status-button click,
        // before building the window or refreshing installed voice information.
        NSApp.activate()
        if settings == nil {
            let controller = SettingsWindow()
            controller.onRefresh = { [weak self] in self?.refresh() }
            controller.onLanguage = { [weak self] code in
                guard let self else { return }
                self.selection.setPrimaryLanguage(code, voices: self.voices)
                self.applySpeechSettings(); self.refresh()
            }
            controller.onVoice = { [weak self] code, id in
                guard let self, self.voices.contains(where: { $0.id == id && $0.language == code }) else { return }
                self.selection.voicesByLanguage[code] = id
                self.applySpeechSettings(); self.refresh()
            }
            controller.onRate = { [weak self] code, rate in
                guard let self else { return }
                self.selection.ratesByLanguage[code] = VoiceSettings.validRate(rate)
                self.applySpeechSettings()
                // Keep the same slider under the pointer throughout dragging.
            }
            controller.onAutomatic = { [weak self] enabled in
                guard let self else { return }
                self.automatic = enabled
                self.applySpeechSettings(); self.refresh()
            }
            controller.onAllowed = { [weak self] code, enabled in
                guard let self else { return }
                self.selection.setEnabled(enabled, for: code)
                self.applySpeechSettings(); self.refresh()
            }
            controller.onAddLanguage = { [weak self] code in
                guard let self else { return }
                self.selection.addLanguage(code, voices: self.voices)
                self.applySpeechSettings(); self.refresh()
            }
            controller.onRemoveLanguage = { [weak self] code in
                guard let self else { return }
                self.selection.removeLanguage(code)
                self.applySpeechSettings(); self.refresh()
            }
            controller.onShortcut = { [weak self] in self?.changeShortcut($0) }
            controller.onOCRShortcut = { [weak self] in self?.changeOCRShortcut($0) }
            controller.onReadRegion = { [weak self] in self?.triggerOCR() }
            controller.onScreenPermission = { [weak self] in self?.screenPermission() }
            controller.onLogin = { [weak self] enabled in
                guard let self else { return }
                do {
                    if enabled { try LoginLaunch.enable() } else { try LoginLaunch.disable() }
                } catch { self.fail("Ошибка настройки автозапуска: \((error as NSError).code)") }
                self.refresh()
            }
            controller.onLoginSettings = { LoginLaunch.openSettings() }
            controller.onPermission = { [weak self] in self?.permission() }
            controller.onPreview = { [weak self] in self?.preview(language: $0) }
            controller.onStop = { [weak self] in self?.stop() }
            controller.onQuit = { [weak self] in self?.quitApplication() }
            settings = controller
        }
        settings?.present()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        settings?.finishPresentation()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func setStatus(_ text: String) {
        // Only fixed technical messages; never selected content.
        message = text
        settings?.setStatus(text)
        statusItem?.button?.toolTip = "QuietSelection: \(text)"
    }
    private func changeShortcut(_ requestedTest: Bool) {
        guard let hotKey else { return }
        if registered && requestedTest == testShortcut { return }
        do {
            try hotKey.register(testShortcut: requestedTest)
            registered = true
            testShortcut = requestedTest
            preferences.set(!requestedTest, forKey: "UseOptionEscape")
            setStatus(requestedTest ? "Готово: Option + Shift + Esc" : "Готово: Option + Esc")
        } catch HotKeyError.registration(let code) {
            fail("Сочетание недоступно: \(code). Прежнее сохранено.")
        } catch { fail("Не удалось сменить сочетание. Прежнее сохранено.") }
        refresh()
    }
    private func trigger() {
        if speech.speaking || pending || ocrBusy || regionPicker.active { stop(); return }
        guard !IsSecureEventInputEnabled() else { fail(SelectionFailure.secureInput.message); return }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            fail(SelectionFailure.noFocus.message); return
        }
        let pid = app.processIdentifier
        if pid == ProcessInfo.processInfo.processIdentifier {
            do {
                let selected = try LocalSelection.read(from: NSApp.keyWindow)
                if speech.speak(selected) { setStatus("Чтение; повторное сочетание — остановить") }
                else { fail("Нужный голос недоступен. Выберите его в настройках речи.") }
            } catch { fail((error as? SelectionFailure)?.message ?? "Не удалось получить выделение") }
            return
        }
        guard AXIsProcessTrusted() else { fail(SelectionFailure.permission.message); return }
        generation += 1
        let ticket = generation
        pending = true
        setStatus("Получение выделения…")
        // Limit application-role preparation to the verified ChatGPT/Codex bundle.
        let allowsAccessibilityPreparation = app.bundleIdentifier == "com.openai.codex"
        worker.async { [weak self] in
            let result: Result<String, Error>
            let backend = AccessibilityBackend(pid: pid, allowsAccessibilityPreparation: allowsAccessibilityPreparation)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                result = .failure(SelectionFailure.changedApplication)
            } else {
                result = Result { try SelectionReader(backend: backend).read() }
            }
            let diagnosticRole = backend.diagnostics.role
            let diagnosticStage = backend.diagnostics.stage
            let focusReport = backend.diagnostics.focusResults.joined(separator: "; ")
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending = false
                guard ticket == self.generation else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      !IsSecureEventInputEnabled() else {
                    self.fail(SelectionFailure.changedApplication.message); return
                }
                switch result {
                case .success(let text):
                    if self.speech.speak(text) {
                        self.setStatus("Чтение; повторное сочетание — остановить")
                    } else { self.fail("Нужный голос недоступен. Выберите его в настройках речи.") }
                case .failure(let error):
                    let reason = error as? SelectionFailure
                    let detail: String
                    if reason == .secureInput { detail = "" }
                    else if reason == .noFocus { detail = " (\(focusReport))" }
                    else { detail = " (\(diagnosticRole); \(diagnosticStage))" }
                    self.fail((reason?.message ?? "Не удалось получить выделение") + detail)
                }
            }
        }
    }
    private func fail(_ text: String) { setStatus(text); NSSound.beep() }
    private func stop() {
        generation += 1
        ocrGeneration += 1
        captureTask?.cancel(); captureTask = nil
        ocrJob?.cancel(); ocrJob = nil
        ocrBusy = false
        regionPicker.cancel()
        speech.stop()
        setStatus(pending ? "Запрос отменён; ожидание завершения" : "Остановлено")
    }
    private func preview(language: String) {
        if speech.speaking || pending || ocrBusy || regionPicker.active { stop(); return }
        // Audition always uses the voice shown in the menus, even in auto mode.
        let enabled = speech.automatic
        let previousVoice = speech.voiceID
        let previousRate = speech.rate
        defer {
            speech.automatic = enabled
            speech.voiceID = previousVoice
            speech.rate = previousRate
        }
        speech.automatic = false
        speech.voiceID = selection.voicesByLanguage[language]
        speech.rate = selection.rate(for: language)
        let samples = ["ru": Self.sampleText, "en": "This is the selected voice. You can adjust the speaking rate.",
            "ja": "選択した音声です。読み上げる速さを調整できます。",
            "de": "Dies ist die ausgewählte Stimme.", "fr": "Voici la voix sélectionnée.",
            "es": "Esta es la voz seleccionada.", "zh": "这是所选的声音。"]
        let success = speech.speak(samples[language] ?? Self.sampleText)
        if success { setStatus("Прослушивание выбранного голоса") }
        else { fail("Выбранный голос недоступен") }
    }
    private func permission() {
        let alert = NSAlert()
        alert.messageText = "Доступ к выделенному тексту"
        alert.informativeText = "Разрешение «Универсальный доступ» нужно только для получения выделенного фрагмента по вашему сочетанию. Буфер обмена не используется. Разрешение включаете вы, только для QuietSelection."
        alert.addButton(withTitle: "Открыть настройки доступа")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    private func changeOCRShortcut(_ requested: OCRShortcut) {
        guard let ocrHotKey else { return }
        if ocrRegistered && requested == ocrShortcut { return }
        do {
            try ocrHotKey.register(keyCode: requested.keyCode, modifiers: requested.modifiers)
            ocrShortcut = requested
            ocrRegistered = true
            preferences.set(requested.rawValue, forKey: "OCRShortcut")
        } catch { fail("Сочетание чтения области занято. Прежнее сохранено.") }
        refresh()
    }
    private func screenPermission() {
        guard !CGPreflightScreenCaptureAccess() else { refresh(); return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Разрешение на чтение области экрана"
        alert.informativeText = "Для распознавания текста на изображениях macOS требует разрешение «Запись экрана». QuietSelection получает только выбранную вами область после отпускания мыши. Снимок и текст остаются в памяти; файл не сохраняется, интернет и буфер обмена не используются. Разрешение даёт системе возможность захвата экрана; его включаете вы только для QuietSelection."
        alert.addButton(withTitle: "Продолжить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        setStatus("После выдачи доступа снова нажмите сочетание чтения области")
        refresh()
    }
    private func triggerOCR() {
        if regionPicker.active || ocrBusy || speech.speaking || pending { stop(); return }
        guard !IsSecureEventInputEnabled() else { fail(SelectionFailure.secureInput.message); return }
        guard CGPreflightScreenCaptureAccess() else { screenPermission(); return }
        ocrGeneration += 1
        let ticket = ocrGeneration
        let languages = automatic ? allowed : [selection.language]
        setStatus("Выделите область мышью. Esc — отмена.")
        regionPicker.begin { [weak self] rect in
            guard let self, ticket == self.ocrGeneration else { return }
            guard let rect else { self.setStatus("Выделение области отменено"); return }
            self.ocrBusy = true
            self.setStatus("Распознавание текста…")
            self.captureTask = Task { @MainActor [weak self] in
                do {
                    // Let the selection windows disappear before the one-shot capture.
                    try await Task.sleep(nanoseconds: 150_000_000)
                    try Task.checkCancellation()
                    guard let self, ticket == self.ocrGeneration else { return }
                    guard !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() else {
                        throw ScreenReadingError.capture
                    }
                    let image = try await RegionCapture.image(in: rect)
                    try Task.checkCancellation()
                    guard ticket == self.ocrGeneration else { return }
                    let job = OCRJob()
                    self.ocrJob = job
                    self.ocrWorker.async { [weak self] in
                        let result = Result { try job.recognize(image, languages: languages) }
                        DispatchQueue.main.async {
                            guard let self, ticket == self.ocrGeneration else { return }
                            self.ocrBusy = false; self.ocrJob = nil; self.captureTask = nil
                            switch result {
                            case .success(let text):
                                if self.speech.speak(text) { self.setStatus("Чтение распознанного текста; повторное сочетание — остановить") }
                                else { self.fail("Нужный голос недоступен. Выберите его в настройках речи.") }
                            case .failure(let error): self.reportOCRError(error)
                            }
                        }
                    }
                } catch {
                    guard let self, ticket == self.ocrGeneration else { return }
                    self.ocrBusy = false; self.captureTask = nil
                    self.reportOCRError(error)
                }
            }
        }
    }
    private func reportOCRError(_ error: Error) {
        if error is CancellationError { setStatus("Распознавание отменено"); return }
        if let reason = error as? ScreenReadingError { fail(reason.message) }
        else if let reason = error as? SelectionFailure { fail(reason.message) }
        else { fail("Ошибка распознавания или захвата экрана: \((error as NSError).code)") }
    }
    func applicationWillTerminate(_ notification: Notification) { stop(); hotKey = nil; ocrHotKey = nil }
    static let sampleText = "Это выбранный голос. Вы можете настроить удобную скорость чтения."
}

@MainActor
@main
struct QuietSelectionMain {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if let index = CommandLine.arguments.firstIndex(of: "--render-settings"),
           CommandLine.arguments.count > index + 1 {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.finishLaunching()
            let controller = SettingsWindow()
            let voices = AppDelegate.availableVoices()
            let selection = VoiceSettings(language: "ru", saved: [:], legacyID: nil, voices: voices)
            controller.update(voices: voices, selection: selection, automatic: true,
                testShortcut: false, login: "enabled", trusted: true)
            controller.updateScreenReading(shortcut: .controlEscape, registered: true, permitted: false)
            do {
                try controller.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                print("settings_render=PASS selection_queries=0")
            } catch { print("settings_render=FAIL"); exit(1) }
            return
        }
        if arguments.contains("--enable-login") || arguments.contains("--disable-login") {
            do {
                if arguments.contains("--enable-login") { try LoginLaunch.enable() }
                else { try LoginLaunch.disable() }
                print("login_status=\(LoginLaunch.statusCode)")
                if LoginLaunch.status == .requiresApproval { exit(3) }
            } catch {
                print("login_error_code=\((error as NSError).code) login_status=\(LoginLaunch.statusCode)")
                exit(1)
            }
            return
        }
        if arguments.contains("--login-status") { print("login_status=\(LoginLaunch.statusCode)"); return }
        if arguments.contains("--self-check") {
            print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("accessibility_trusted=\(AXIsProcessTrusted())")
            print("installed_apple_voices=\(Speech.installedVoices().count)")
            print("login_status=\(LoginLaunch.statusCode)")
            let defaults = UserDefaults.standard
            let primary = defaults.string(forKey: "SelectedLanguage") ?? "ru"
            let rates = defaults.dictionary(forKey: "SpeechRatesByLanguage") as? [String: NSNumber] ?? [:]
            let legacyRate = defaults.object(forKey: "SpeechRate") == nil ? AVSpeechUtteranceDefaultSpeechRate : defaults.float(forKey: "SpeechRate")
            let rate = Speech.validatedRate(rates[primary]?.floatValue ?? legacyRate)
            print("speech_rate=\(rate) use_option_escape=\(defaults.bool(forKey: "UseOptionEscape"))")
            print("selection_queries=0 permission_prompts=0")
            return
        }
        if arguments.contains("--speech-smoke") { exit(speechSmoke()) }
        if arguments.contains("--rate-smoke") { exit(speechSmoke(compareRates: true)) }
        if arguments.contains("--hotkey-check") {
            do {
                let key = try HotKey()
                try key.register(testShortcut: true)
                print("hotkey_register_unregister=PASS selection_queries=0")
                withExtendedLifetime(key) {}
            } catch HotKeyError.registration(let code) {
                print("hotkey_register_unregister=FAIL osstatus=\(code)"); exit(1)
            } catch { print("hotkey_register_unregister=FAIL"); exit(1) }
            return
        }
        if !arguments.isEmpty && !arguments.elementsEqual(["--show-settings"]) { print("Usage: QuietSelection [--show-settings|--self-check|--speech-smoke|--rate-smoke|--hotkey-check|--enable-login|--disable-login|--login-status]"); exit(2) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    // Only fixed synthetic text. Render PCM in memory; never write audio or text.
    private static func speechSmoke(compareRates: Bool = false) -> Int32 {
        let selection = Speech()
        let samples: [(String, Float)] = compareRates
            ? [(AppDelegate.sampleText, Float(0.4)), (AppDelegate.sampleText, Float(0.7))]
            : [(AppDelegate.sampleText, Float(0.5)), ("This is a local speech test.", Float(0.5)),
               ("公演期間：2027/03/03(水)", Float(0.5))]
        var durations: [Double] = []
        for (index, sample) in samples.enumerated() {
            selection.rate = sample.1
            let code = compareRates ? "ru" : ["ru", "en", "ja"][index]
            selection.voiceID = Speech.installedVoices().first { $0.language.hasPrefix(code + "-") }?.identifier
            guard let utterance = selection.utterance(for: sample.0) else {
                print("speech_smoke=FAIL reason=no_installed_voice sample=\(index)"); return 1
            }
            let synthesizer = AVSpeechSynthesizer()
            var complete = false
            var frames: UInt64 = 0
            var hasSignal = false
            var duration = 0.0
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                let count = pcm.frameLength
                var signal = false
                if let samples = pcm.floatChannelData, count > 0 {
                    for i in 0..<Int(count) where abs(samples[0][i]) > 0.00001 { signal = true; break }
                }
                let nonzero = signal
                let seconds = Double(count) / pcm.format.sampleRate
                DispatchQueue.main.async {
                    frames += UInt64(count)
                    duration += seconds
                    hasSignal = hasSignal || nonzero
                    if count == 0 { complete = true }
                }
            }
            let deadline = Date().addingTimeInterval(40)
            while !complete && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            guard complete, frames > 0, hasSignal else {
                synthesizer.stopSpeaking(at: .immediate)
                print("speech_smoke=FAIL sample=\(index) completed=\(complete) frames=\(frames) signal=\(hasSignal)")
                return 1
            }
            print("speech_smoke=PASS sample=\(index) frames=\(frames) nonzero_pcm=true")
            durations.append(duration)
        }
        if compareRates {
            guard durations[0] > durations[1] else {
                print("rate_comparison=FAIL"); return 1
            }
            print("rate_comparison=PASS slow_seconds=\(durations[0]) fast_seconds=\(durations[1])")
        }
        return 0
    }
}
