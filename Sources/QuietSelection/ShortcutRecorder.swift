import AppKit
import Carbon

enum KeyNames {
    /// Character of a key on the current ASCII-capable layout, so that letters stay
    /// Latin ("R", not "К") while a Russian layout is active.
    static func name(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    static func title(_ shortcut: Shortcut) -> String { shortcut.title(keyName: name(for:)) }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= Shortcut.command }
        if flags.contains(.shift) { result |= Shortcut.shift }
        if flags.contains(.option) { result |= Shortcut.option }
        if flags.contains(.control) { result |= Shortcut.control }
        return result
    }
}

/// A button that records a new shortcut: click, then press the keys.
/// Esc without modifiers or clicking elsewhere cancels recording. Keys are read
/// only from QuietSelection's own window while recording.
@MainActor
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut? { didSet { if !recording { showShortcut() } } }
    var onRecord: ((Shortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onInvalid: (() -> Void)?
    private(set) var recording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(actionTitle: String) {
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .regular
        font = .systemFont(ofSize: 13)
        target = self
        action = #selector(toggleRecording)
        setAccessibilityLabel("Сочетание: " + actionTitle)
        setAccessibilityHelp("Нажмите, затем введите новое сочетание. Esc — отмена.")
        widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func showShortcut() {
        title = shortcut.map(KeyNames.title) ?? "Не назначено"
    }

    @objc private func toggleRecording() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        title = "Введите сочетание…"
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.recording else { return event }
            self.handle(event)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        showShortcut()
        onRecordingChanged?(false)
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyNames.carbonModifiers(event.modifierFlags)
        if event.keyCode == UInt16(Shortcut.escape) && modifiers == 0 { stop(); return }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else { onInvalid?(); return }
        stop()
        onRecord?(candidate)
    }

    override func accessibilityValue() -> Any? { title }
}
