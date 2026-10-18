import AppKit

@MainActor
final class SourceLanguageChooser: NSWindowController, NSWindowDelegate {
    private let languageMenu = NSPopUpButton()
    private let codes: [String]
    private var completion: ((String?) -> Void)?
    private let focus = RegionFocus(backend: MacRegionFocus())
    init(languages: [String], completion: @escaping (String?) -> Void) {
        codes = languages.sorted { VoiceChoice.languageTitle($0).localizedCaseInsensitiveCompare(VoiceChoice.languageTitle($1)) == .orderedAscending }
        self.completion = completion
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "QuietSelection — Язык текста"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        let label = NSTextField(wrappingLabelWithString: "Не удалось уверенно определить язык части текста. Выберите язык неопределённых фрагментов для этого чтения.")
        label.font = .systemFont(ofSize: 17)
        languageMenu.addItems(withTitles: codes.map(VoiceChoice.languageTitle))
        languageMenu.font = .systemFont(ofSize: 17)
        languageMenu.setAccessibilityLabel("Язык неопределённых фрагментов")
        let cancel = NSButton(title: "Отмена", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let read = NSButton(title: "Продолжить", target: self, action: #selector(readPressed))
        read.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, read])
        let stack = NSStackView(views: [label, languageMenu, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24),
            languageMenu.widthAnchor.constraint(equalTo: stack.widthAnchor), label.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() { focus.begin(); NSApp.activate(); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
    func cancel() { finish(nil) }
    private func finish(_ code: String?) {
        guard let completion else { return }
        self.completion = nil
        window?.orderOut(nil)
        focus.finish()
        completion(code)
    }
    func windowWillClose(_ notification: Notification) { finish(nil) }
    @objc private func cancelPressed() { cancel() }
    @objc private func readPressed() {
        finish(codes.indices.contains(languageMenu.indexOfSelectedItem) ? codes[languageMenu.indexOfSelectedItem] : nil)
    }
}
