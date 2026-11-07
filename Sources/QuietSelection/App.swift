import AppKit
import ApplicationServices
import Carbon
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppMenuActions {
    private let speech = Speech()
    private let worker = DispatchQueue(label: "local.quietselection.ax", qos: .userInitiated)
    private var hotKeys: [Int: HotKey] = [:]
    private var slots = ShortcutSlot.defaults
    /// Slots whose keys could not be registered (taken by another application).
    private var failedShortcuts: Set<Int> = []
    private var gestures = [PressGesture](repeating: PressGesture(), count: ShortcutSlot.count)
    private var gestureTickets = [Int](repeating: 0, count: ShortcutSlot.count)
    private var longPressThreshold = ShortcutSettings.defaultThreshold
    private var doublePressInterval = ShortcutSettings.defaultDoubleInterval
    /// The last text spoken, kept in memory only, for "repeat last".
    private var lastReading: (text: String, primary: Bool)?
    private enum ReadMode { case normal, primary, translated }
    private let translator = LocalTranslation()
    private var translationTask: Task<Void, Never>?
    private var translating = false
    private var languageChooser: SourceLanguageChooser?
    private var preparation: TranslationPreparationWindow?
    private var preparationID = UUID()
    private var preparingPair: (source: String, target: String)?
    private var availabilityTask: Task<Void, Never>?
    private var availabilityKey = ""
    private var translationStates: [String: TranslationReadiness] = [:]
    private let regionPicker = RegionPicker()
    private var captureTask: Task<Void, Never>?
    private var ocrJob: OCRJob?
    private var ocrBusy = false
    private var ocrGeneration = 0
    private let ocrWorker = DispatchQueue(label: "local.quietselection.ocr", qos: .userInitiated)
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindow?
    private var pending = false
    private var generation = 0
    private var message = "Готово"
    private let preferences = UserDefaults.standard
    private var voices: [VoiceChoice] = []
    private var selection = VoiceSettings(language: "ru", saved: [:], legacyID: nil, voices: [])
    private var automatic = false
    private var allowed: [String] { selection.allowedLanguages }
    /// Bundle identifiers whose selection may be read by asking the app to copy it.
    private var copyApps: [String] = []
    /// Read the paragraph under the pointer when it is not over the selection.
    private var readUnderPointer = true

    static func availableVoices() -> [VoiceChoice] {
        Speech.installedVoices().map {
            VoiceChoice(id: $0.identifier, name: $0.name, tag: $0.language, quality: $0.quality.rawValue)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenu.make(target: self)
        voices = Self.availableVoices()
        selection = VoiceSettings(language: preferences.string(forKey: "SelectedLanguage"),
            saved: preferences.dictionary(forKey: "VoicesByLanguage") as? [String: String] ?? [:],
            legacyID: preferences.string(forKey: "VoiceID"), voices: voices,
            rates: (preferences.dictionary(forKey: "SpeechRatesByLanguage") as? [String: NSNumber] ?? [:]).mapValues { $0.floatValue },
            legacyRate: preferences.object(forKey: "SpeechRate") == nil ? AVSpeechUtteranceDefaultSpeechRate : preferences.float(forKey: "SpeechRate"),
            additional: preferences.dictionary(forKey: "AdditionalLanguages") as? [String: Bool],
            legacyAllowed: preferences.stringArray(forKey: "AllowedLanguages") ?? ["ru", "en", "ja"])
        automatic = preferences.bool(forKey: "AutomaticLanguage")
        copyApps = preferences.stringArray(forKey: "CopyFallbackApps") ?? []
        readUnderPointer = preferences.object(forKey: "ReadUnderPointer") as? Bool ?? true
        applySpeechSettings()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Читать"
        statusItem.button?.setAccessibilityLabel("Меню QuietSelection")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        statusItem.menu = AppMenu.status(target: self, version: version)
        speech.finished = { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.speech.speaking, !self.ocrBusy, !self.regionPicker.active, !self.pending, !self.translating else { return }
                self.setStatus("Готово")
            }
        }
        slots = ShortcutSettings.load(saved: preferences.array(forKey: ShortcutSettings.preferenceKey),
                                      layout: preferences.integer(forKey: ShortcutSettings.layoutKey),
                                      actions: preferences.dictionary(forKey: ShortcutSettings.actionPreferenceKey),
                                      legacy: { [preferences] in preferences.object(forKey: $0) })
        longPressThreshold = ShortcutSettings.threshold(preferences.object(forKey: ShortcutSettings.thresholdKey))
        doublePressInterval = ShortcutSettings.doubleInterval(preferences.object(forKey: ShortcutSettings.doubleIntervalKey))
        for index in slots.indices {
            do {
                let key = try HotKey(identifier: ShortcutSlot.hotKeyID(index))
                key.onPress = { [weak self] in self?.shortcutPressed(index) }
                key.onRelease = { [weak self] in self?.shortcutReleased(index) }
                hotKeys[index] = key
            } catch { failedShortcuts.insert(index) }
        }
        registerAllShortcuts()
        saveShortcuts()
        if !failedShortcuts.isEmpty {
            fail("Некоторые сочетания заняты другими приложениями. Назначьте другие в разделе «Сочетания клавиш».")
        }
        if CommandLine.arguments.contains("--show-settings") { showSettings() }
    }

    // MARK: Short and long presses

    private func shortcutPressed(_ index: Int) {
        let slot = slots[index]
        gestureTickets[index] += 1
        let ticket = gestureTickets[index]
        let outcome = gestures[index].press(busy: busy, hasLong: slot.long != nil, hasDouble: slot.double != nil)
        handle(outcome, slot: index)
        guard outcome == .none, slot.long != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold) { [weak self] in
            guard let self, self.gestureTickets[index] == ticket else { return }
            let outcome = self.gestures[index].thresholdReached()
            if outcome != .none { Feedback.longPress() }
            self.handle(outcome, slot: index)
        }
    }
    private func shortcutReleased(_ index: Int) {
        let outcome = gestures[index].release(hasDouble: slots[index].double != nil)
        guard outcome == .awaitSecond else { handle(outcome, slot: index); return }
        let ticket = gestureTickets[index]
        DispatchQueue.main.asyncAfter(deadline: .now() + doublePressInterval) { [weak self] in
            // A second press starts a new ticket, so this single press is dropped.
            guard let self, self.gestureTickets[index] == ticket else { return }
            self.handle(self.gestures[index].secondPressWindowEnded(), slot: index)
        }
    }
    private func handle(_ outcome: PressGesture.Outcome, slot index: Int) {
        switch outcome {
        case .none, .awaitSecond: return
        case .stop: stop()
        case .perform(let kind):
            if let function = slots[index].function(kind) { perform(function) }
        }
    }
    private func perform(_ function: ReadFunction) {
        switch function {
        case .read: trigger()
        case .primary: trigger(mode: .primary)
        case .translate: trigger(mode: .translated)
        case .regionRead: triggerOCR()
        case .regionPrimary: triggerOCR(mode: .primary)
        case .regionTranslate: triggerOCR(mode: .translated)
        case .repeatLast: repeatLast()
        }
    }
    private func repeatLast() {
        if busy { stop(); return }
        guard let last = lastReading else { fail("Ещё нечего повторять"); return }
        let success = last.primary
            ? speech.speakPrimary(last.text, voiceID: selection.selectedVoice(in: voices)?.id, rate: selection.rate(for: selection.language))
            : speech.speak(last.text)
        if success { setStatus("Чтение: повтор последнего; повторное сочетание — остановить") }
        else { fail("Нужный голос недоступен. Выберите его в настройках речи.") }
    }

    // MARK: Shortcut settings

    private func registerAllShortcuts() {
        for index in slots.indices {
            guard let key = hotKeys[index] else { continue }
            guard let shortcut = slots[index].shortcut else { key.unregister(); continue }
            do { try key.register(shortcut); failedShortcuts.remove(index) }
            catch { failedShortcuts.insert(index) }
        }
    }
    private func saveShortcuts() {
        preferences.set(slots.map(\.preferenceValue), forKey: ShortcutSettings.preferenceKey)
        preferences.set(longPressThreshold, forKey: ShortcutSettings.thresholdKey)
        preferences.set(doublePressInterval, forKey: ShortcutSettings.doubleIntervalKey)
        preferences.set(ShortcutSettings.layoutVersion, forKey: ShortcutSettings.layoutKey)
    }
    /// While a new shortcut is recorded, the current ones must not fire.
    private func setShortcutRecording(_ recording: Bool) {
        if recording { for key in hotKeys.values { key.unregister() } }
        else { registerAllShortcuts() }
        refresh()
    }
    private func changeShortcut(_ index: Int, to requested: Shortcut) {
        guard let key = hotKeys[index] else { return }
        defer { refresh() }
        guard requested.isValid, slots[index].shortcut != requested || failedShortcuts.contains(index) else { return }
        if let other = ShortcutSettings.conflict(for: index, shortcut: requested, in: slots) {
            fail("«\(KeyNames.title(requested))» уже назначено сочетанию \(other + 1). Прежнее сохранено.")
            settings?.showShortcutMessage("Это сочетание уже используется в строке \(other + 1).")
            return
        }
        do {
            try key.register(requested)
            slots[index].shortcut = requested
            failedShortcuts.remove(index)
            saveShortcuts()
            setStatus("Сочетание \(index + 1): \(KeyNames.title(requested))")
            settings?.showShortcutMessage("")
        } catch {
            fail("«\(KeyNames.title(requested))» занято другим приложением или системой. Прежнее сочетание сохранено.")
            settings?.showShortcutMessage("«\(KeyNames.title(requested))» занято другим приложением или системой.")
            // Re-register the previous keys in case they were released.
            if let previous = slots[index].shortcut { try? key.register(previous) }
        }
    }
    private func changeSlotFunction(_ index: Int, kind: PressKind, to function: ReadFunction?) {
        slots[index].set(function, for: kind)
        saveShortcuts()
        refresh()
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
        settings?.update(voices: voices, selection: selection, automatic: automatic, login: LoginLaunch.statusCode)
        settings?.updatePermissions(accessibility: AXIsProcessTrusted(), screen: CGPreflightScreenCaptureAccess())
        settings?.updatePointerReading(readUnderPointer)
        settings?.updateShortcuts(slots, failed: failedShortcuts, threshold: longPressThreshold,
                                  doubleInterval: doublePressInterval)
        settings?.setStatus(message, busy: busy)
        if settings != nil { updateCopyFallbackSettings() }
        refreshTranslation()
    }
    private func updateCopyFallbackSettings() {
        let own = Bundle.main.bundleIdentifier
        var seen = Set(copyApps)
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> (id: String, name: String)? in
            guard let id = app.bundleIdentifier, id != own, app.activationPolicy != .prohibited,
                  seen.insert(id).inserted else { return nil }
            return (id, app.localizedName ?? id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        settings?.updateCopyFallback(apps: copyApps.map { ($0, Self.applicationName($0)) }, candidates: candidates)
    }
    private static func applicationName(_ id: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName {
            return running
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
    }
    private func setCopyApps(_ ids: [String]) {
        copyApps = ids
        preferences.set(ids, forKey: "CopyFallbackApps")
        refresh()
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
            controller.onShortcutChange = { [weak self] in self?.changeShortcut($0, to: $1) }
            controller.onSlotFunction = { [weak self] in self?.changeSlotFunction($0, kind: $1, to: $2) }
            controller.onDoubleInterval = { [weak self] value in
                guard let self else { return }
                self.doublePressInterval = ShortcutSettings.doubleInterval(NSNumber(value: value))
                self.saveShortcuts()
            }
            controller.onThreshold = { [weak self] value in
                guard let self else { return }
                self.longPressThreshold = ShortcutSettings.threshold(NSNumber(value: value))
                self.saveShortcuts()
            }
            controller.onShortcutRecording = { [weak self] in self?.setShortcutRecording($0) }
            controller.translationSettings.onRefresh = { [weak self] in self?.refreshTranslation(force: true) }
            controller.translationSettings.onDownload = { [weak self] in self?.prepareTranslation(source: $0) }
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
            controller.onPointerReading = { [weak self] enabled in
                guard let self else { return }
                self.readUnderPointer = enabled
                self.preferences.set(enabled, forKey: "ReadUnderPointer")
                self.refresh()
            }
            controller.onAddCopyApp = { [weak self] id in
                guard let self, !self.copyApps.contains(id) else { return }
                self.setCopyApps(self.copyApps + [id])
            }
            controller.onRemoveCopyApp = { [weak self] id in
                guard let self else { return }
                self.setCopyApps(self.copyApps.filter { $0 != id })
            }
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
    /// Something is being read, recognised or translated, so Stop has an effect.
    private var busy: Bool {
        speech.speaking || pending || ocrBusy || regionPicker.active || translating
    }
    private func setStatus(_ text: String) {
        // Only fixed technical messages; never selected content.
        message = text
        // Speech may not report itself as speaking until the next run loop turn.
        let reading = text.hasPrefix("Чтение") || text.hasPrefix("Прослушивание")
        settings?.setStatus(text, busy: busy || reading)
        statusItem?.button?.toolTip = "QuietSelection: \(text)"
    }
    private func trigger(mode: ReadMode = .normal) {
        if speech.speaking || pending || ocrBusy || regionPicker.active || translating { stop(); return }
        guard let front = NSWorkspace.shared.frontmostApplication else {
            fail(SelectionFailure.noFocus.message); return
        }
        let frontPID = front.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Read where the keyboard is: a launcher panel such as Alfred receives
        // typing and selection without becoming the frontmost application.
        let pid = AXIsProcessTrusted()
            ? FocusTarget.pid(frontmost: frontPID, keyboardFocusOwner: KeyboardFocus.ownerPID(), own: ownPID)
            : frontPID
        let app = pid == frontPID ? front : (NSRunningApplication(processIdentifier: pid) ?? front)
        guard !SecureInput.blocks(target: pid) else { fail(SelectionFailure.secureKeyboard.message); return }
        if pid == ownPID {
            do {
                let selected = try LocalSelection.read(from: NSApp.keyWindow)
                read(selected, mode: mode)
            } catch { fail((error as? SelectionFailure)?.message ?? "Не удалось получить выделение") }
            return
        }
        guard AXIsProcessTrusted() else { fail(SelectionFailure.permission.message); return }
        generation += 1
        let ticket = generation
        pending = true
        setStatus("Получение выделения…")
        // Application-role preparation only for Chromium browsers and Electron
        // apps; it was validated with ChatGPT/Codex (see focus-investigation).
        let allowsAccessibilityPreparation = ChromiumFamily.contains(app)
        let allowsCopy = app.bundleIdentifier.map(copyApps.contains) ?? false
        // What is under the pointer, found now so the moment of the key press counts.
        let pointer = readUnderPointer ? PointerTarget.current().flatMap { $0.pid == ownPID ? nil : $0 } : nil
        let pointerChromium = pointer.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
            .map(ChromiumFamily.contains) ?? false
        worker.async { [weak self] in
            var result: Result<String, Error>
            var viaCopy = false
            var viaPointer = false
            var backend = AccessibilityBackend(pid: pid, allowsAccessibilityPreparation: allowsAccessibilityPreparation,
                                               frontPID: frontPID)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != frontPID {
                result = .failure(SelectionFailure.changedApplication)
            } else {
                result = Result { try SelectionReader(backend: backend).read() }
                // Chromium may expose only its window chrome until web accessibility
                // is built on the first query. Prepare once, then read once more.
                if allowsAccessibilityPreparation, case .failure(let error) = result,
                   [.unsupported, .noSelection].contains(error as? SelectionFailure),
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID {
                    let retry = AccessibilityBackend(pid: pid, allowsAccessibilityPreparation: false, timeLimit: 2,
                                                     frontPID: frontPID)
                    if (try? retry.prepareApplicationAccessibility()) == true {
                        backend = retry
                        result = Result { try SelectionReader(backend: retry).read() }
                    }
                }
                // Listed applications only: ask the app to copy its selection,
                // then restore the previous clipboard (see CopyFallback.swift).
                if allowsCopy, case .failure(let error) = result,
                   (error as? SelectionFailure)?.allowsCopyFallback == true,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID,
                   !SecureInput.blocks(target: pid) {
                    viaCopy = true
                    result = Result { try ClipboardCopy.read(pid: pid, frontPID: frontPID) }
                }
                // The pointer over the selection reads the selection; anywhere else
                // the paragraph under the pointer is read (nothing there: failure).
                if let pointer, NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID {
                    var usesSelection = false
                    if case .success = result {
                        usesSelection = viaCopy
                            || PointerPolicy.readsSelection(selectionBounds: backend.selectionBounds(), pointer: pointer.point)
                    }
                    if !usesSelection {
                        viaPointer = true
                        if SecureInput.blocks(target: pointer.pid) {
                            result = .failure(SelectionFailure.secureKeyboard)
                        } else {
                            result = Result { try PointerTextReader().read(pointer) }
                            // Chromium builds web accessibility on the first query.
                            if pointerChromium, case .failure = result,
                               (try? AccessibilityBackend(pid: pointer.pid, allowsAccessibilityPreparation: true)
                                   .prepareApplicationAccessibility()) == true,
                               let fresh = pointer.refreshed() {
                                result = Result { try PointerTextReader().read(fresh) }
                            }
                        }
                    }
                }
            }
            let diagnosticRole = backend.diagnostics.role
            let diagnosticStage = backend.diagnostics.stage
            let focusReport = backend.diagnostics.focusResults.joined(separator: "; ")
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending = false
                guard ticket == self.generation else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID else {
                    self.fail(SelectionFailure.changedApplication.message); return
                }
                guard !SecureInput.blocks(target: pid) else {
                    self.fail(SelectionFailure.secureKeyboard.message); return
                }
                switch result {
                case .success(let text):
                    self.read(text, mode: mode)
                    if viaPointer, self.speech.speaking {
                        self.setStatus("Чтение текста под курсором; повторное сочетание — остановить")
                    } else if viaCopy, self.speech.speaking {
                        self.setStatus("Чтение через копирование, буфер обмена восстановлен; повторное сочетание — остановить")
                    }
                case .failure(let error):
                    if let copyFailure = error as? CopyFallbackFailure { self.fail(copyFailure.message); return }
                    let reason = error as? SelectionFailure
                    let detail: String
                    if reason == .secureInput || reason == .secureKeyboard || viaPointer { detail = "" }
                    else if reason == .noFocus { detail = " (\(focusReport))" }
                    else { detail = " (\(diagnosticRole); \(diagnosticStage))" }
                    let hint = !allowsCopy && reason?.allowsCopyFallback == true
                        ? ". Если выделение видно, но не читается, включите для этого приложения «Чтение через копирование» (Настройки → Общие)."
                        : ""
                    self.fail((reason?.message ?? "Не удалось получить выделение") + detail + hint)
                }
            }
        }
    }
    private func read(_ text: String, mode: ReadMode) {
        let voiceID = selection.selectedVoice(in: voices)?.id
        let rate = selection.rate(for: selection.language)
        if mode != .translated {
            let success = mode == .primary ? speech.speakPrimary(text, voiceID: voiceID, rate: rate) : speech.speak(text)
            if success { lastReading = (text, mode == .primary); setStatus("Чтение; повторное сочетание — остановить") }
            else { fail("Нужный голос недоступен. Выберите его в настройках речи.") }
            return
        }
        guard voiceID != nil else { fail("Основной голос недоступен. Выберите его в настройках речи."); return }
        generation += 1
        let ticket = generation
        let target = selection.language
        let languages = allowed
        let plan = TranslationPlan.parts(text, allowed: languages, target: target)
        guard !plan.isEmpty else { fail("Нет текста для перевода"); return }
        translating = true
        if plan.contains(where: { $0.source == nil }) {
            setStatus("Выберите язык неопределённых фрагментов")
            languageChooser = SourceLanguageChooser(languages: languages) { [weak self] code in
                guard let self, ticket == self.generation else { return }
                self.languageChooser = nil
                guard let code else { self.translating = false; self.setStatus("Перевод отменён"); return }
                self.translate(TranslationPlan.resolving(plan, with: code), target: target,
                    voiceID: voiceID, rate: rate, ticket: ticket)
            }
            languageChooser?.present()
        } else { translate(plan, target: target, voiceID: voiceID, rate: rate, ticket: ticket) }
    }
    private func translate(_ plan: [TranslationPlan.Part], target: String, voiceID: String?, rate: Float, ticket: Int) {
        setStatus("Перевод на основной язык…")
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let translated = try await TranslationPipeline.run(plan, target: target, backend: self.translator)
                try Task.checkCancellation()
                guard ticket == self.generation else { return }
                self.translating = false; self.translationTask = nil
                self.translator.cancel()
                if self.speech.speakPrimary(translated, voiceID: voiceID, rate: rate) {
                    self.lastReading = (translated, true)
                    self.setStatus("Чтение на основном языке; повторное сочетание — остановить")
                } else { self.fail("Основной голос недоступен. Выберите его в настройках речи.") }
            } catch {
                guard ticket == self.generation else { return }
                self.translating = false; self.translationTask = nil
                self.translator.cancel()
                if error is CancellationError { self.setStatus("Перевод отменён") }
                else if case TranslationFailure.unavailable(let source) = error {
                    self.fail("Нужна загрузка языков: \(VoiceChoice.languageTitle(source)) → \(VoiceChoice.languageTitle(target)). Откройте раздел «Перевод».")
                } else if case TranslationFailure.unsupported(let source) = error {
                    self.fail("macOS не поддерживает перевод: \(VoiceChoice.languageTitle(source)) → \(VoiceChoice.languageTitle(target)).")
                } else { self.fail("Не удалось выполнить локальный перевод. Проверьте готовность языков. Код: \((error as NSError).code)") }
            }
        }
    }
    private func refreshTranslation(force: Bool = false) {
        let target = selection.language
        let sources = allowed.filter { $0 != target }.sorted()
        let key = ([target] + sources).joined(separator: ":")
        if force || key != availabilityKey {
            availabilityTask?.cancel()
            availabilityKey = key
            translationStates = [:]
            availabilityTask = Task { [weak self] in
                guard let self else { return }
                let backend = LocalTranslation()
                for source in sources {
                    let state = await backend.readiness(source: source, target: target)
                    guard !Task.isCancelled, self.availabilityKey == key else { return }
                    self.translationStates[source] = state
                    self.updateTranslationUI()
                }
            }
        }
        updateTranslationUI()
    }
    private func updateTranslationUI() {
        var states = translationStates
        if let pair = preparingPair, pair.target == selection.language, states[pair.source] != .installed {
            states[pair.source] = .preparing
        }
        settings?.translationSettings.update(target: selection.language,
            sources: allowed.filter { $0 != selection.language }, states: states)
    }
    private func prepareTranslation(source: String) {
        guard source != selection.language, allowed.contains(source), translationStates[source] == .supported else { return }
        if preparation?.window?.isVisible == true { preparation?.present(); return }
        let target = selection.language
        preparationID = UUID()
        let ticket = preparationID
        preparingPair = (source, target)
        updateTranslationUI()
        preparation = TranslationPreparationWindow(source: source, target: target) { [weak self] state in
            guard let self, self.preparationID == ticket else { return }
            switch state {
            case .requesting, .waiting: self.preparingPair = (source, target)
            default: self.preparingPair = nil; self.refreshTranslation(force: true)
            }
            self.setStatus(state.message)
            self.updateTranslationUI()
        }
        preparation?.onClose = { [weak self] in
            guard let self, self.preparationID == ticket else { return }
            self.preparationID = UUID() // Ignore late completion from the detached view.
            if self.preparingPair != nil { self.setStatus("Проверка подготовки закрыта. Готовность можно проверить в разделе «Перевод».") }
            self.preparingPair = nil
            self.refreshTranslation(force: true)
        }
        preparation?.present()
    }
    private func fail(_ text: String) { setStatus(text); Feedback.failure() }
    private func stop() {
        generation += 1
        translationTask?.cancel(); translationTask = nil
        translator.cancel()
        translating = false
        languageChooser?.cancel(); languageChooser = nil
        ocrGeneration += 1
        captureTask?.cancel(); captureTask = nil
        ocrJob?.cancel(); ocrJob = nil
        ocrBusy = false
        regionPicker.cancel()
        speech.stop()
        setStatus(pending ? "Запрос отменён; ожидание завершения" : "Остановлено")
    }
    private func preview(language: String) {
        if speech.speaking || pending || ocrBusy || regionPicker.active || translating { stop(); return }
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
    private func triggerOCR(mode: ReadMode = .normal) {
        if regionPicker.active || ocrBusy || speech.speaking || pending || translating { stop(); return }
        guard !SecureInput.blocks(target: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            fail(SelectionFailure.secureKeyboard.message); return
        }
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
                    guard !SecureInput.blocks(target: NSWorkspace.shared.frontmostApplication?.processIdentifier),
                          CGPreflightScreenCaptureAccess() else {
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
                                // Same path as selected text: plain, primary voice or translation.
                                self.read(text, mode: mode)
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
    func applicationWillTerminate(_ notification: Notification) {
        stop(); availabilityTask?.cancel()
        hotKeys.removeAll()
    }
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
            controller.update(voices: voices, selection: selection, automatic: true, login: "enabled")
            controller.updatePermissions(accessibility: true, screen: false)
            controller.updateShortcuts(ShortcutSlot.defaults, failed: [], threshold: ShortcutSettings.defaultThreshold,
                                       doubleInterval: ShortcutSettings.defaultDoubleInterval)
            controller.translationSettings.update(target: "ru", sources: ["en", "ja"], states: [:])
            controller.updateCopyFallback(apps: [("ru.keepcoder.Telegram", "Telegram")],
                                          candidates: [("com.runningwithcrayons.Alfred", "Alfred")])
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
            let keys = ShortcutSettings.load(saved: defaults.array(forKey: ShortcutSettings.preferenceKey),
                                             layout: defaults.integer(forKey: ShortcutSettings.layoutKey),
                                             actions: defaults.dictionary(forKey: ShortcutSettings.actionPreferenceKey),
                                             legacy: { defaults.object(forKey: $0) })
            print("speech_rate=\(rate) shortcuts=\(keys.map { $0.shortcut.map(KeyNames.title) ?? "none" })")
            print("selection_queries=0 permission_prompts=0")
            return
        }
        if arguments.contains("--speech-smoke") { exit(speechSmoke()) }
        if arguments.contains("--rate-smoke") { exit(speechSmoke(compareRates: true)) }
        if arguments.contains("--hotkey-check") {
            do {
                let key = try HotKey()
                // A combination unlikely to be taken, to check registration only.
                try key.register(Shortcut(keyCode: Shortcut.escape, modifiers: Shortcut.option | Shortcut.shift | Shortcut.control))
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

enum SecureInput {
    /// The process holding secure keyboard input, as reported by the window server.
    static func holder() -> Int32? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let number = session["kCGSSessionSecureInputPID"] as? NSNumber else { return nil }
        let pid = number.int32Value
        return pid > 0 ? pid : nil
    }

    static func blocks(target: Int32?) -> Bool {
        let enabled = IsSecureEventInputEnabled()
        return SecureInputPolicy.blocks(enabled: enabled, holder: enabled ? holder() : nil, target: target)
    }
}

@MainActor
enum ChromiumFamily {
    private static var cache: [String: Bool] = [:]

    /// Chromium browsers and Electron apps ship a "<Name> Helper (Renderer).app".
    /// Only file names inside the application bundle are inspected.
    static func contains(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier == "com.openai.codex" { return true }
        guard let bundle = app.bundleURL else { return false }
        if let known = cache[bundle.path] { return known }
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        var found = hasRenderer(frameworks)
        if !found {
            let files = FileManager.default
            let names = (try? files.contentsOfDirectory(atPath: frameworks.path)) ?? []
            for name in names where name.hasSuffix(".framework") {
                let helpers = frameworks.appendingPathComponent(name).appendingPathComponent("Versions/Current/Helpers")
                if hasRenderer(helpers) { found = true; break }
            }
        }
        cache[bundle.path] = found
        return found
    }

    private static func hasRenderer(_ directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { $0.hasSuffix(" Helper (Renderer).app") }
    }
}

/// Short system sounds: a click when a long press is recognised, and one
/// uncommon sound when a function could not be carried out.
@MainActor
enum Feedback {
    static func longPress() { play("Pop") }
    static func failure() { play("Basso") }
    private static func play(_ name: String) {
        (NSSound(named: NSSound.Name(name))?.copy() as? NSSound)?.play()
    }
}
