import AppKit

private final class SpeechListDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private enum SpeechLayout {
    static func label(_ text: String, size: CGFloat = 17, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.isSelectable = true
        return field
    }
    static func column(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    static func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }
    static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 17)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
}

@MainActor
final class SpeechLanguageCard: NSView {
    let primary: Bool
    private(set) var code = "ru"
    let languageMenu = NSPopUpButton()
    let voiceMenu = NSPopUpButton()
    let speed = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let toggle = SettingsSwitch(frame: .zero)
    private(set) var removeButton: NSButton!
    private(set) var previewButton: NSButton!
    private let value = NSTextField(labelWithString: "50 / 100")
    private let title = SpeechLayout.label("", bold: true)
    var onLanguage: ((String) -> Void)?
    var onVoice: ((String, String) -> Void)?
    var onRate: ((String, Float) -> Void)?
    var onEnabled: ((String, Bool) -> Void)?
    var onRemove: ((String) -> Void)?
    var onPreview: ((String) -> Void)?

    init(primary: Bool) {
        self.primary = primary
        super.init(frame: .zero)
        for menu in [languageMenu, voiceMenu] {
            menu.controlSize = .large
            menu.font = .systemFont(ofSize: 17)
            menu.target = self
            menu.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        languageMenu.action = #selector(languageChanged)
        voiceMenu.action = #selector(voiceChanged)
        speed.trackFillColor = SettingsPalette.accent
        speed.target = self
        speed.action = #selector(rateChanged)
        speed.isContinuous = true
        value.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        value.widthAnchor.constraint(equalToConstant: 88).isActive = true
        previewButton = SpeechLayout.button("Прослушать", target: self, action: #selector(preview))
        previewButton.widthAnchor.constraint(equalToConstant: 142).isActive = true
        toggle.target = self
        toggle.action = #selector(enabledChanged)
        removeButton = SpeechLayout.button("", target: self, action: #selector(remove))
        removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Удалить язык")
        removeButton.imagePosition = .imageOnly
        removeButton.widthAnchor.constraint(equalToConstant: 38).isActive = true
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        func field(_ text: String, _ controls: [NSView]) -> NSView {
            let label = SpeechLayout.label(text)
            label.widthAnchor.constraint(equalToConstant: 82).isActive = true
            return SpeechLayout.row([label] + controls)
        }
        let first = primary ? field("Язык", [languageMenu]) : SpeechLayout.row([title, removeButton, toggle])
        let stack = SpeechLayout.column([
            first, field("Голос", [voiceMenu]), field("Скорость", [speed, value, previewButton])
        ], spacing: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 140)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.25).setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.stroke()
    }
    func update(code: String, voices: [VoiceChoice], selection: VoiceSettings) {
        self.code = code
        let languageTitle = VoiceChoice.languageTitle(code)
        title.stringValue = languageTitle
        if primary {
            languageMenu.removeAllItems()
            let languages = Set(VoiceSettings.languages(in: voices) + [code]).sorted {
                VoiceChoice.languageTitle($0).compare(VoiceChoice.languageTitle($1), locale: VoiceChoice.russian) == .orderedAscending
            }
            for language in languages {
                languageMenu.addItem(withTitle: VoiceChoice.languageTitle(language))
                languageMenu.lastItem?.representedObject = language
                if language == code { languageMenu.select(languageMenu.lastItem) }
            }
            languageMenu.setAccessibilityLabel("Основной язык")
        }
        voiceMenu.removeAllItems()
        let selectedID = selection.voicesByLanguage[code]
        let choices = VoiceSettings.choices(for: code, in: voices)
        if !choices.contains(where: { $0.id == selectedID }) {
            voiceMenu.addItem(withTitle: "Голос недоступен — выберите другой")
            voiceMenu.lastItem?.isEnabled = false
        }
        for voice in choices {
            voiceMenu.addItem(withTitle: voice.title)
            voiceMenu.lastItem?.representedObject = voice.id
            if voice.id == selectedID { voiceMenu.select(voiceMenu.lastItem) }
        }
        voiceMenu.setAccessibilityLabel("Голос: " + languageTitle)
        speed.doubleValue = Double(selection.rate(for: code) * 100)
        updateValue()
        speed.setAccessibilityLabel("Скорость: " + languageTitle + ", от 0 до 100")
        toggle.state = selection.additionalLanguages[code] == true ? .on : .off
        toggle.setAccessibilityLabel("Использовать в автоопределении: " + languageTitle)
        removeButton.setAccessibilityLabel("Удалить язык: " + languageTitle)
        removeButton.toolTip = "Удалить язык из автоопределения"
        previewButton.setAccessibilityLabel("Прослушать: " + languageTitle)
    }
    private func updateValue() { value.stringValue = "\(Int(speed.doubleValue.rounded())) / 100" }
    @objc private func languageChanged() {
        if let code = languageMenu.selectedItem?.representedObject as? String { onLanguage?(code) }
    }
    @objc private func voiceChanged() {
        if let id = voiceMenu.selectedItem?.representedObject as? String { onVoice?(code, id) }
    }
    @objc private func rateChanged() {
        updateValue()
        onRate?(code, Float(speed.doubleValue.rounded()) / 100)
    }
    @objc private func enabledChanged() { onEnabled?(code, toggle.state == .on) }
    @objc private func remove() { onRemove?(code) }
    @objc private func preview() { onPreview?(code) }
}

@MainActor
final class SpeechSettingsView: NSView {
    let primaryCard = SpeechLanguageCard(primary: true)
    let autoSwitch = SettingsSwitch(frame: .zero)
    let list = NSScrollView()
    private let listStack = SpeechLayout.column([] , spacing: 12)
    private let document = SpeechListDocument()
    private let emptyLabel = SpeechLayout.label("Добавьте язык для автоопределения. Основной язык используется всегда.", size: 16)
    private(set) var cards: [String: SpeechLanguageCard] = [:]
    private var orderedCodes: [String] = []
    private var availableToAdd: [String] = []
    private var addButton: NSButton!
    var onLanguage: ((String) -> Void)?
    var onVoice: ((String, String) -> Void)?
    var onRate: ((String, Float) -> Void)?
    var onAutomatic: ((Bool) -> Void)?
    var onEnabled: ((String, Bool) -> Void)?
    var onRemove: ((String) -> Void)?
    var onAdd: ((String) -> Void)?
    var onPreview: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoSwitch.target = self
        autoSwitch.action = #selector(automaticChanged)
        autoSwitch.setAccessibilityLabel("Автоопределение языка")
        addButton = SpeechLayout.button("+ Добавить язык", target: self, action: #selector(add))
        let autoTitle = SpeechLayout.label("Автоопределение языка", size: 20, bold: true)
        autoTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let additionalTitle = SpeechLayout.label("Дополнительные языки", size: 20, bold: true)
        additionalTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        list.hasVerticalScroller = true
        list.autohidesScrollers = false
        list.scrollerStyle = .legacy
        list.drawsBackground = false
        list.setAccessibilityLabel("Дополнительные языки автоопределения")
        list.heightAnchor.constraint(equalToConstant: 292).isActive = true
        list.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(listStack)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: list.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: list.contentView.heightAnchor),
            listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -4),
            listStack.topAnchor.constraint(equalTo: document.topAnchor),
            listStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor)
        ])
        let stack = SpeechLayout.column([
            SpeechLayout.label("Речь", size: 26, bold: true),
            SpeechLayout.label("Основной язык", size: 20, bold: true),
            primaryCard,
            SpeechLayout.label("Используется при выключенном автоопределении и когда язык текста не удалось определить.", size: 16),
            SpeechLayout.row([autoTitle, autoSwitch]),
            SpeechLayout.label("Основной язык участвует всегда. Добавьте другие языки.", size: 16),
            SpeechLayout.row([additionalTitle, addButton]),
            list,
            SpeechLayout.label("Изменения сохраняются автоматически.", size: 16)
        ], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        connect(primaryCard)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func connect(_ card: SpeechLanguageCard) {
        card.onLanguage = { [weak self] in self?.onLanguage?($0) }
        card.onVoice = { [weak self] in self?.onVoice?($0, $1) }
        card.onRate = { [weak self] in self?.onRate?($0, $1) }
        card.onEnabled = { [weak self] in self?.onEnabled?($0, $1) }
        card.onRemove = { [weak self] in self?.onRemove?($0) }
        card.onPreview = { [weak self] in self?.onPreview?($0) }
    }
    func update(voices: [VoiceChoice], selection: VoiceSettings, automatic: Bool) {
        primaryCard.update(code: selection.language, voices: voices, selection: selection)
        autoSwitch.state = automatic ? .on : .off
        let codes = selection.additionalLanguages.keys.sorted {
            VoiceChoice.languageTitle($0).compare(VoiceChoice.languageTitle($1), locale: VoiceChoice.russian) == .orderedAscending
        }
        if codes != orderedCodes || listStack.views.isEmpty {
            let position = list.contentView.bounds.origin
            for view in listStack.views { listStack.removeArrangedSubview(view); view.removeFromSuperview() }
            cards = cards.filter { codes.contains($0.key) }
            for code in codes {
                let card = cards[code] ?? SpeechLanguageCard(primary: false)
                connect(card)
                cards[code] = card
                listStack.addArrangedSubview(card)
            }
            // Rebuild only the stack-owned widths to avoid retaining removed cards.
            NSLayoutConstraint.deactivate(listStack.constraints.filter { $0.identifier == "cardWidth" })
            for card in cards.values {
                let width = card.widthAnchor.constraint(equalTo: listStack.widthAnchor)
                width.identifier = "cardWidth"
                width.isActive = true
            }
            if codes.isEmpty {
                listStack.addArrangedSubview(emptyLabel)
                emptyLabel.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }
            orderedCodes = codes
            layoutSubtreeIfNeeded()
            let maxY = max(0, document.bounds.height - list.contentView.bounds.height)
            list.contentView.scroll(to: NSPoint(x: 0, y: min(position.y, maxY)))
            list.reflectScrolledClipView(list.contentView)
        }
        for code in codes { cards[code]?.update(code: code, voices: voices, selection: selection) }
        availableToAdd = VoiceSettings.languages(in: voices).filter { $0 != selection.language && selection.additionalLanguages[$0] == nil }
        addButton.isEnabled = !availableToAdd.isEmpty
        // Configuration remains editable while detection is off; only speech behaviour changes.
    }
    @objc private func automaticChanged() { onAutomatic?(autoSwitch.state == .on) }
    @objc private func add() {
        let menu = NSMenu()
        for code in availableToAdd {
            let item = NSMenuItem(title: VoiceChoice.languageTitle(code), action: #selector(addChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addButton.bounds.maxY), in: addButton)
    }
    @objc private func addChosen(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { onAdd?(code) }
    }
}
