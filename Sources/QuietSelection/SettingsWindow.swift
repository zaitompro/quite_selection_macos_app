import AppKit

private final class SettingsContentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onLanguage: ((String) -> Void)?
    var onVoice: ((String, String) -> Void)?
    var onRate: ((String, Float) -> Void)?
    var onAutomatic: ((Bool) -> Void)?
    var onAllowed: ((String, Bool) -> Void)?
    var onAddLanguage: ((String) -> Void)?
    var onRemoveLanguage: ((String) -> Void)?
    var onShortcut: ((Bool) -> Void)?
    var onOCRShortcut: ((OCRShortcut) -> Void)?
    var onPrimaryShortcut: ((PrimaryShortcut) -> Void)?
    var onTranslationShortcut: ((TranslationShortcut) -> Void)?
    var onReadRegion: (() -> Void)?
    var onScreenPermission: (() -> Void)?
    var onLogin: ((Bool) -> Void)?
    var onPermission: (() -> Void)?
    var onLoginSettings: (() -> Void)?
    var onPreview: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onQuit: (() -> Void)?
    var onRefresh: (() -> Void)?

    let speechSettings = SpeechSettingsView(frame: .zero)
    let translationSettings = TranslationSettingsView(frame: .zero)
    private let shortcutMenu = NSPopUpButton()
    private let ocrShortcutMenu = NSPopUpButton()
    private let primaryShortcutMenu = NSPopUpButton()
    private let translationShortcutMenu = NSPopUpButton()
    private let primaryShortcutNote = NSTextField(wrappingLabelWithString: "")
    private let translationShortcutNote = NSTextField(wrappingLabelWithString: "")
    private let screenPermissionNote = NSTextField(wrappingLabelWithString: "")
    private let screenShortcutNote = NSTextField(wrappingLabelWithString: "")
    private let loginSwitch = SettingsSwitch(frame: .zero)
    private let loginNote = NSTextField(wrappingLabelWithString: "")
    private let permissionNote = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "Готово")
    private var loginSettings: NSButton!
    private var pages: [NSView] = []
    private let tabs = NSTabView()
    private let navigation = NSTableView()
    private let sectionTitles = ["Общие", "Речь", "Перевод", "Сочетания клавиш", "Чтение с экрана"]
    private var scrollViews: [NSScrollView] = []
    private var presentationPending = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "QuietSelection — Настройки"
        window.minSize = NSSize(width: 1000, height: 760)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func label(_ text: String, size: CGFloat = 17, bold: Bool = false) -> NSTextField {
        let result = NSTextField(wrappingLabelWithString: text)
        result.isSelectable = true
        result.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        result.textColor = .labelColor
        return result
    }
    private func column(_ views: [NSView], spacing: CGFloat = 16) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let result = NSButton(title: title, target: self, action: action)
        result.bezelStyle = .rounded
        result.controlSize = .large
        result.font = .systemFont(ofSize: 17)
        return result
    }
    private func switchRow(_ title: String, toggle: SettingsSwitch, action: Selector) -> NSView {
        toggle.target = self
        toggle.action = action
        toggle.setAccessibilityLabel(title)
        let titleLabel = label(title)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row([titleLabel, toggle])
    }
    private func field(_ title: String, control: NSView) -> NSView {
        let titleLabel = label(title, bold: true)
        control.setAccessibilityLabel(title)
        return column([titleLabel, control], spacing: 7)
    }
    private func build() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        for control in [shortcutMenu, ocrShortcutMenu, primaryShortcutMenu, translationShortcutMenu] {
            control.controlSize = .large
            control.font = .systemFont(ofSize: 17)
            control.target = self
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for note in [loginNote, permissionNote, status, screenPermissionNote, screenShortcutNote, primaryShortcutNote, translationShortcutNote] {
            note.isSelectable = true
            note.font = .systemFont(ofSize: 16)
            note.textColor = .labelColor
        }
        speechSettings.onLanguage = { [weak self] in self?.onLanguage?($0) }
        speechSettings.onVoice = { [weak self] in self?.onVoice?($0, $1) }
        speechSettings.onRate = { [weak self] in self?.onRate?($0, $1) }
        speechSettings.onAutomatic = { [weak self] in self?.onAutomatic?($0) }
        speechSettings.onEnabled = { [weak self] in self?.onAllowed?($0, $1) }
        speechSettings.onAdd = { [weak self] in self?.onAddLanguage?($0) }
        speechSettings.onRemove = { [weak self] in self?.onRemoveLanguage?($0) }
        speechSettings.onPreview = { [weak self] in self?.onPreview?($0) }
        shortcutMenu.addItems(withTitles: ["Option + Esc", "Option + Shift + Esc"])
        shortcutMenu.action = #selector(shortcutChanged)
        ocrShortcutMenu.addItems(withTitles: OCRShortcut.allCases.map(\.title))
        ocrShortcutMenu.action = #selector(ocrShortcutChanged)
        ocrShortcutMenu.setAccessibilityLabel("Сочетание для распознавания области экрана")
        primaryShortcutMenu.addItems(withTitles: PrimaryShortcut.allCases.map(\.title))
        primaryShortcutMenu.action = #selector(primaryShortcutChanged)
        primaryShortcutMenu.setAccessibilityLabel("Читать основным голосом")
        translationShortcutMenu.addItems(withTitles: TranslationShortcut.allCases.map(\.title))
        translationShortcutMenu.action = #selector(translationShortcutChanged)
        translationShortcutMenu.setAccessibilityLabel("Перевести и прочитать")
        let shortcutsPage = column([
            label("Сочетания клавиш", size: 26, bold: true),
            label("Читать / остановить выделение", bold: true),
            shortcutMenu,
            label("Повторное нажатие останавливает чтение. Сочетание работает и при закрытом окне настроек."),
            label("Для Option + Esc штатное «Проговаривание выбранного текста» должно быть отключено или использовать другое сочетание.", size: 16),
            field("Читать основным голосом", control: primaryShortcutMenu),
            label("Без перевода и автоопределения: основной язык, голос и скорость из раздела «Речь».", size: 16),
            primaryShortcutNote,
            field("Перевести и прочитать", control: translationShortcutMenu),
            label("Command + Esc также используется системным Accessibility Reader. Если он включён, выберите другое сочетание.", size: 16),
            translationShortcutNote,
            label("Распознать и прочитать область экрана", bold: true),
            ocrShortcutMenu,
            label("Нажмите сочетание и выделите область мышью. Повторное нажатие отменяет распознавание или останавливает речь. Esc отменяет выбор области.", size: 16)
        ], spacing: 16)
        loginSettings = button("Настройки входа macOS…", #selector(openLoginSettings))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "тестовая сборка"
        let generalPage = column([
            label("Общие", size: 26, bold: true),
            switchRow("Запускать при входе в macOS", toggle: loginSwitch, action: #selector(loginChanged)),
            loginNote,
            loginSettings,
            label("Доступ к выделенному тексту", bold: true),
            permissionNote,
            button("Настройки доступа…", #selector(permission)),
            label("Текст обрабатывается на Mac. Буфер обмена не используется; выделенный текст не сохраняется в журнале.", size: 16),
            label("QuietSelection \(version)", size: 16)
        ], spacing: 22)
        let screenPage = column([
            label("Чтение с экрана", size: 26, bold: true),
            label("Для изображений и мест, где обычное выделение текста недоступно."),
            screenShortcutNote,
            button("Выделить область и прочитать", #selector(readRegion)),
            label("Обведите текст мышью на одном мониторе и отпустите кнопку. Esc — отмена. Лучше выделять один столбец текста.", size: 17),
            label("Распознавание выполняется на Mac. Изображение и текст не сохраняются на диск и не отправляются в интернет.", size: 16),
            label("Язык, голос и скорость используются из раздела «Речь». При ручном выборе языка распознавание тоже использует этот язык.", size: 16),
            label("Доступ к экрану", bold: true),
            screenPermissionNote,
            button("Разрешение на чтение экрана…", #selector(screenPermission))
        ], spacing: 18)
        pages = [generalPage, speechSettings, translationSettings, shortcutsPage, screenPage]
        tabs.tabPosition = .none
        tabs.tabViewBorderType = .none
        tabs.font = .systemFont(ofSize: 17, weight: .medium)
        tabs.controlSize = .large
        tabs.allowsTruncatedLabels = false
        tabs.setAccessibilityLabel("Разделы настроек")
        for (index, page) in pages.enumerated() {
            let host = SettingsContentView()
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            host.translatesAutoresizingMaskIntoConstraints = false
            page.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(page)
            scroll.documentView = host
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
                host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
                host.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                host.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
                page.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
                page.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
                page.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
                page.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -20)
            ])
            let item = NSTabViewItem(identifier: index)
            item.label = sectionTitles[index]
            item.view = scroll
            tabs.addTabViewItem(item)
            scrollViews.append(scroll)
        }
        // Native sidebar selection, without push-button bezels or rotated labels.
        navigation.style = .plain
        navigation.headerView = nil
        navigation.rowHeight = 54
        navigation.intercellSpacing = NSSize(width: 0, height: 0)
        navigation.allowsEmptySelection = false
        navigation.allowsMultipleSelection = false
        navigation.backgroundColor = .clear
        navigation.setAccessibilityLabel("Разделы настроек")
        let navigationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        navigationColumn.resizingMask = .autoresizingMask
        navigation.addTableColumn(navigationColumn)
        navigation.delegate = self
        navigation.dataSource = self
        let navigationScroll = NSScrollView()
        navigationScroll.drawsBackground = false
        navigationScroll.documentView = navigation
        let brand = label("QuietSelection", size: 19, bold: true)
        let brandHost = NSView()
        brand.translatesAutoresizingMaskIntoConstraints = false
        brandHost.addSubview(brand)
        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo: brandHost.leadingAnchor, constant: 24),
            brand.trailingAnchor.constraint(equalTo: brandHost.trailingAnchor, constant: -16),
            brand.topAnchor.constraint(equalTo: brandHost.topAnchor),
            brand.bottomAnchor.constraint(equalTo: brandHost.bottomAnchor)
        ])
        let sidebar = column([brandHost, navigationScroll], spacing: 24)
        let divider = NSBox()
        divider.boxType = .separator
        let body = row([sidebar, divider, tabs])
        body.alignment = .top
        body.spacing = 0
        NSLayoutConstraint.activate([
            sidebar.widthAnchor.constraint(equalToConstant: 230),
            sidebar.heightAnchor.constraint(equalTo: body.heightAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalTo: body.heightAnchor),
            tabs.heightAnchor.constraint(equalTo: body.heightAnchor),
            navigationScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        tabs.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stopButton = button("Остановить", #selector(stop))
        let quitButton = button("Завершить", #selector(quit))
        for control in [stopButton, quitButton] {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let footer = row([status, stopButton, quitButton])
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setAccessibilityLabel("Состояние чтения")
        let separator = NSBox()
        separator.boxType = .separator
        for view in [body, separator, footer] {
            root.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 480),
            body.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -18),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            separator.heightAnchor.constraint(equalToConstant: 1),
            footer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 18),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            footer.heightAnchor.constraint(equalToConstant: 64)
        ])
        selectSection(0)
    }

    func update(voices: [VoiceChoice], selection: VoiceSettings, automatic: Bool,
                testShortcut: Bool, login: String, trusted: Bool) {
        speechSettings.update(voices: voices, selection: selection, automatic: automatic)
        shortcutMenu.selectItem(at: testShortcut ? 1 : 0)
        loginSwitch.state = login == "enabled" || login == "requires_approval" ? .on : .off
        loginNote.stringValue = login == "enabled" ? "Автозапуск включён. Окно настроек при входе не открывается."
            : login == "requires_approval" ? "macOS ожидает вашего разрешения в настройках входа."
            : "Автозапуск выключен."
        loginSettings.isHidden = login != "requires_approval"
        permissionNote.stringValue = trusted ? "Доступ разрешён." : "Нужно разрешение «Универсальный доступ» для QuietSelection."
    }
    func setStatus(_ message: String) { status.stringValue = message }
    func updateExtraShortcuts(primary: PrimaryShortcut, primaryRegistered: Bool,
                              translation: TranslationShortcut, translationRegistered: Bool) {
        primaryShortcutMenu.selectItem(at: primary.rawValue)
        translationShortcutMenu.selectItem(at: translation.rawValue)
        primaryShortcutNote.stringValue = primaryRegistered ? "" : "Сочетание недоступно. Выберите другое."
        translationShortcutNote.stringValue = translationRegistered ? "" : "Сочетание недоступно. Выберите другое."
        primaryShortcutNote.isHidden = primaryRegistered
        translationShortcutNote.isHidden = translationRegistered
    }
    func updateScreenReading(shortcut: OCRShortcut, registered: Bool, permitted: Bool) {
        ocrShortcutMenu.selectItem(at: shortcut.rawValue)
        screenShortcutNote.stringValue = registered ? "Сочетание: " + shortcut.title
            : "Сочетание недоступно. Выберите другое в разделе «Сочетания клавиш»."
        screenPermissionNote.stringValue = permitted ? "Разрешение получено."
            : "Для первого использования нужно разрешение macOS «Запись экрана»."
    }
    func present() {
        selectSection(0)
        presentationPending = true
        NSApp.activate()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Explicit user request: raise a normal-level window even while the
        // asynchronous app activation is still completing. No always-on-top mode.
        window?.orderFrontRegardless()
        if NSApp.isActive { finishPresentation() }
        onRefresh?()
    }
    func finishPresentation() {
        guard presentationPending, let window, window.isVisible else { return }
        presentationPending = false
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { presentationPending = false }
    func windowDidBecomeKey(_ notification: Notification) { onRefresh?() }
    func closeSettings() { window?.performClose(nil) }
    var selectedSection: Int { tabs.indexOfTabViewItem(tabs.selectedTabViewItem!) }
    func numberOfRows(in tableView: NSTableView) -> Int { sectionTitles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = SettingsSectionCell()
        let title = NSTextField(labelWithString: sectionTitles[row])
        title.font = .systemFont(ofSize: 17, weight: .medium)
        title.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = title
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SettingsRowView() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        selectSection(navigation.selectedRow)
    }
    func selectSection(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        if navigation.selectedRow != index {
            navigation.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        tabs.selectTabViewItem(at: index)
        scrollViews[index].documentView?.scroll(.zero)
    }
    // Renders only our own view; no screen capture or other applications.
    func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let view = window?.contentView else { return }
        window?.animationBehavior = .none
        window?.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        for index in pages.indices {
            selectSection(index)
            view.needsDisplay = true
            view.layoutSubtreeIfNeeded()
            window?.displayIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            // Finish layout after the scroll view has settled its document size.
            scrollViews[index].documentView?.scroll(.zero)
            view.layoutSubtreeIfNeeded()
            window?.displayIfNeeded()
            if let title = (pages[index] as? NSStackView)?.views.first {
                let frame = title.convert(title.bounds, to: view)
                precondition(view.bounds.contains(frame), "Settings heading outside window")
                precondition(frame.height >= 25, "Settings heading compressed")
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            if let context = NSGraphicsContext(bitmapImageRep: bitmap), let layer = view.layer {
                context.cgContext.setFillColor(NSColor.windowBackgroundColor.cgColor)
                context.cgContext.fill(view.bounds)
                layer.render(in: context.cgContext)
            } else { view.cacheDisplay(in: view.bounds, to: bitmap) }
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: directory.appendingPathComponent("settings-\(index).png"))
            }
        }
    }
    @objc private func shortcutChanged() { onShortcut?(shortcutMenu.indexOfSelectedItem == 1) }
    @objc private func ocrShortcutChanged() {
        if let shortcut = OCRShortcut(rawValue: ocrShortcutMenu.indexOfSelectedItem) { onOCRShortcut?(shortcut) }
    }
    @objc private func primaryShortcutChanged() {
        if let value = PrimaryShortcut(rawValue: primaryShortcutMenu.indexOfSelectedItem) { onPrimaryShortcut?(value) }
    }
    @objc private func translationShortcutChanged() {
        if let value = TranslationShortcut(rawValue: translationShortcutMenu.indexOfSelectedItem) { onTranslationShortcut?(value) }
    }
    @objc private func readRegion() { onReadRegion?() }
    @objc private func screenPermission() { onScreenPermission?() }
    @objc private func loginChanged() { onLogin?(loginSwitch.state == .on) }
    @objc private func openLoginSettings() { onLoginSettings?() }
    @objc private func permission() { onPermission?() }
    @objc private func stop() { onStop?() }
    @objc private func quit() { onQuit?() }
}
