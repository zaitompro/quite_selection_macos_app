import AppKit
import UniformTypeIdentifiers

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
    var onShortcutChange: ((Int, Shortcut) -> Void)?
    var onSlotFunction: ((Int, PressKind, ReadFunction?) -> Void)?
    var onThreshold: ((Double) -> Void)?
    var onDoubleInterval: ((Double) -> Void)?
    var onShortcutRecording: ((Bool) -> Void)?
    var onReadRegion: (() -> Void)?
    var onScreenPermission: (() -> Void)?
    var onLogin: ((Bool) -> Void)?
    var onPermission: (() -> Void)?
    var onLoginSettings: (() -> Void)?
    var onPreview: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onQuit: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onAddCopyApp: ((String) -> Void)?
    var onRemoveCopyApp: ((String) -> Void)?

    let speechSettings = SpeechSettingsView(frame: .zero)
    let translationSettings = TranslationSettingsView(frame: .zero)
    private(set) var recorders: [Int: ShortcutRecorder] = [:]
    private(set) var shortMenus: [Int: NSPopUpButton] = [:]
    private(set) var doubleMenus: [Int: NSPopUpButton] = [:]
    private(set) var longMenus: [Int: NSPopUpButton] = [:]
    private var shortcutWarnings: [Int: NSTextField] = [:]
    let thresholdSlider = NSSlider(value: ShortcutSettings.defaultThreshold,
                                   minValue: ShortcutSettings.thresholdRange.lowerBound,
                                   maxValue: ShortcutSettings.thresholdRange.upperBound, target: nil, action: nil)
    private let thresholdValue = NSTextField(labelWithString: "")
    let doubleSlider = NSSlider(value: ShortcutSettings.defaultDoubleInterval,
                                minValue: ShortcutSettings.doubleIntervalRange.lowerBound,
                                maxValue: ShortcutSettings.doubleIntervalRange.upperBound, target: nil, action: nil)
    private let doubleValue = NSTextField(labelWithString: "")
    private let shortcutHint = SettingsUI.caption("")
    private let screenShortcut = NSTextField(labelWithString: "")
    private let loginSwitch = SettingsSwitch(frame: .zero)
    private let loginNote = SettingsUI.caption("")
    private var loginSettings: NSButton!
    private var accessibilityPermission: PermissionRow!
    private var screenPermissionGeneral: PermissionRow!
    private var screenPermissionPage: PermissionRow!
    private let status = NSTextField(wrappingLabelWithString: "Готово")
    private var stopButton: NSButton!
    private let copyAppsCard = SettingsCard()
    private let copyAddButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var copyAppIDs: [String] = []
    private var copyCandidateIDs: [String] = []
    private var pages: [NSView] = []
    private let tabs = NSTabView()
    private let navigation = NSTableView()
    private let sections: [(title: String, symbol: String)] = [
        ("Общие", "gearshape"), ("Речь", "waveform"), ("Перевод", "character.bubble"),
        ("Сочетания клавиш", "keyboard"), ("Чтение с экрана", "text.viewfinder"),
        ("Копирование", "doc.on.clipboard")
    ]
    private var scrollViews: [NSScrollView] = []
    private var presentationPending = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "QuietSelection — Настройки"
        window.minSize = NSSize(width: 820, height: 620)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Pages

    private func generalPage() -> NSView {
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged)
        loginSwitch.setAccessibilityLabel("Запускать при входе в macOS")
        loginSettings = SettingsUI.button("Настройки входа…", target: self, action: #selector(openLoginSettings))
        accessibilityPermission = PermissionRow(title: "Универсальный доступ",
            caption: "Нужен для чтения выделенного текста в других приложениях",
            buttonTitle: "Открыть…", target: self, action: #selector(permission))
        screenPermissionGeneral = PermissionRow(title: "Запись экрана",
            caption: "Нужна только для чтения выбранной области экрана",
            buttonTitle: "Открыть…", target: self, action: #selector(screenPermission))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "тестовая сборка"
        let quit = SettingsUI.button("Завершить QuietSelection", target: self, action: #selector(quit))
        quit.setAccessibilityHelp("Полностью завершает программу. Command + Q закрывает только настройки.")
        return SettingsUI.page([
            SettingsUI.pageTitle("Общие"),
            SettingsUI.card([
                SettingsUI.row("Запускать при входе в macOS", caption: loginNote, controls: [loginSettings, loginSwitch])
            ]),
            SettingsUI.groupTitle("Разрешения"),
            SettingsUI.card([accessibilityPermission.view, screenPermissionGeneral.view]),
            SettingsUI.caption("Текст обрабатывается на Mac и не сохраняется в журнале. Буфер обмена используется только для приложений из раздела «Копирование»."),
            SettingsUI.card([
                SettingsUI.row("QuietSelection \(version)",
                    caption: SettingsUI.caption("Command + Q и Command + W закрывают только окно настроек"),
                    controls: [quit])
            ])
        ], spacing: 12)
    }

    private func functionMenu(slot: Int, kind: PressKind) -> NSPopUpButton {
        let menu = NSPopUpButton()
        menu.font = .systemFont(ofSize: SettingsUI.bodySize)
        menu.addItem(withTitle: "Ничего")
        for function in ReadFunction.allCases {
            menu.addItem(withTitle: function.title)
            menu.lastItem?.representedObject = function.rawValue
        }
        menu.tag = slot * PressKind.allCases.count + PressKind.allCases.firstIndex(of: kind)!
        menu.target = self
        menu.action = #selector(slotFunctionChanged(_:))
        let gesture = kind == .short ? "одно нажатие" : kind == .double ? "двойное нажатие" : "долгое нажатие"
        menu.setAccessibilityLabel("Сочетание \(slot + 1), \(gesture)")
        menu.setContentHuggingPriority(.required, for: .horizontal)
        menu.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        return menu
    }

    private func shortcutsPage() -> NSView {
        var views: [NSView] = [SettingsUI.pageTitle("Сочетания клавиш"),
            SettingsUI.caption("У каждого сочетания три действия: одно нажатие, двойное и долгое. Долгое срабатывает после щелчка — тогда клавиши можно отпустить. По умолчанию сочетание выбирает, откуда взять текст, а нажатие — как читать: одно — читать, дважды — перевести, долго — основным голосом. Любое сочетание во время чтения останавливает его.")]
        for index in 0..<ShortcutSlot.count {
            let recorder = ShortcutRecorder(actionTitle: "сочетание \(index + 1)")
            recorder.onRecord = { [weak self] in self?.onShortcutChange?(index, $0) }
            recorder.onRecordingChanged = { [weak self] recording in
                guard let self else { return }
                if recording { for (other, view) in self.recorders where other != index { view.stop() } }
                self.shortcutHint.stringValue = recording
                    ? "Введите сочетание: нужна клавиша Command, Option или Control. Esc — отмена." : ""
                self.onShortcutRecording?(recording)
            }
            recorder.onInvalid = { [weak self] in
                self?.shortcutHint.stringValue = "Нужна хотя бы одна из клавиш Command, Option или Control. Esc — отмена."
            }
            let reset = SettingsUI.iconButton("arrow.counterclockwise",
                                              label: "Вернуть сочетание \(index + 1) по умолчанию",
                                              target: self, action: #selector(resetShortcut(_:)))
            reset.tag = index
            let warning = SettingsUI.caption("")
            warning.isHidden = true
            let short = functionMenu(slot: index, kind: .short)
            let double = functionMenu(slot: index, kind: .double)
            let long = functionMenu(slot: index, kind: .long)
            recorders[index] = recorder
            shortMenus[index] = short
            doubleMenus[index] = double
            longMenus[index] = long
            shortcutWarnings[index] = warning
            views.append(SettingsUI.card([
                SettingsUI.row("Сочетание \(index + 1)", caption: warning, controls: [recorder, reset]),
                SettingsUI.row("Одно нажатие", controls: [short]),
                SettingsUI.row("Дважды", controls: [double]),
                SettingsUI.row("Долго", controls: [long])
            ]))
        }
        thresholdSlider.target = self
        thresholdSlider.action = #selector(thresholdChanged)
        thresholdSlider.isContinuous = true
        thresholdSlider.trackFillColor = SettingsPalette.accent
        thresholdSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        thresholdSlider.setAccessibilityLabel("Время удержания для долгого нажатия")
        thresholdValue.font = .monospacedDigitSystemFont(ofSize: SettingsUI.bodySize, weight: .medium)
        thresholdValue.widthAnchor.constraint(equalToConstant: 56).isActive = true
        doubleSlider.target = self
        doubleSlider.action = #selector(doubleIntervalChanged)
        doubleSlider.isContinuous = true
        doubleSlider.trackFillColor = SettingsPalette.accent
        doubleSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        doubleSlider.setAccessibilityLabel("Время между нажатиями для двойного нажатия")
        doubleValue.font = .monospacedDigitSystemFont(ofSize: SettingsUI.bodySize, weight: .medium)
        doubleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true
        views += [
            SettingsUI.card([
                SettingsUI.row("Долгое нажатие", caption: SettingsUI.caption("Сколько держать сочетание до щелчка"),
                               controls: [thresholdSlider, thresholdValue]),
                SettingsUI.row("Двойное нажатие",
                               caption: SettingsUI.caption("Сколько ждать второго нажатия; одно нажатие срабатывает после этой паузы"),
                               controls: [doubleSlider, doubleValue])
            ]),
            shortcutHint
        ]
        return SettingsUI.page(views, spacing: 12)
    }

    private func screenPage() -> NSView {
        screenShortcut.font = .systemFont(ofSize: SettingsUI.bodySize, weight: .medium)
        screenPermissionPage = PermissionRow(title: "Запись экрана",
            caption: "Нужна для снимка выбранной области",
            buttonTitle: "Открыть…", target: self, action: #selector(screenPermission))
        return SettingsUI.page([
            SettingsUI.pageTitle("Чтение с экрана"),
            SettingsUI.caption("Для изображений и мест, где выделение текста недоступно."),
            SettingsUI.card([
                SettingsUI.row("Сочетание", caption: SettingsUI.caption("Меняется в разделе «Сочетания клавиш»"),
                               controls: [screenShortcut]),
                SettingsUI.row("Прочитать область сейчас",
                               caption: SettingsUI.caption("Обведите текст мышью на одном мониторе; Esc — отмена"),
                               controls: [SettingsUI.button("Выделить область…", target: self, action: #selector(readRegion))]),
                screenPermissionPage.view
            ]),
            SettingsUI.caption("Распознавание выполняется на Mac. Изображение и текст не сохраняются и не отправляются в интернет. Язык, голос и скорость — из раздела «Речь»; лучше выделять один столбец текста.")
        ], spacing: 12)
    }

    private func copyPage() -> NSView {
        copyAppsCard.orientation = .vertical
        copyAppsCard.alignment = .leading
        copyAppsCard.spacing = 0
        copyAppsCard.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        copyAppsCard.setAccessibilityLabel("Приложения для чтения через копирование")
        copyAddButton.font = .systemFont(ofSize: SettingsUI.bodySize)
        copyAddButton.setAccessibilityLabel("Добавить приложение для чтения через копирование")
        copyAddButton.setContentHuggingPriority(.required, for: .horizontal)
        let header = NSStackView(views: [SettingsUI.groupTitle("Приложения"), NSView(), copyAddButton])
        header.orientation = .horizontal
        return SettingsUI.page([
            SettingsUI.pageTitle("Чтение через копирование"),
            SettingsUI.caption("Для приложений, которые показывают выделение, но не передают его системе (например, Telegram). Если обычное чтение не удалось, QuietSelection просит приложение скопировать выделенный текст и сразу возвращает прежнее содержимое буфера обмена."),
            header,
            copyAppsCard,
            SettingsUI.caption("Если буфер нельзя вернуть без потерь — пароль из менеджера паролей, файлы, больше 50 МБ, — он не трогается, и чтение отменяется. macOS может один раз спросить разрешение на доступ к буферу обмена.")
        ], spacing: 12)
    }

    // MARK: Window

    private func build() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        for note in [loginNote] { note.isSelectable = true }
        speechSettings.onLanguage = { [weak self] in self?.onLanguage?($0) }
        speechSettings.onVoice = { [weak self] in self?.onVoice?($0, $1) }
        speechSettings.onRate = { [weak self] in self?.onRate?($0, $1) }
        speechSettings.onAutomatic = { [weak self] in self?.onAutomatic?($0) }
        speechSettings.onEnabled = { [weak self] in self?.onAllowed?($0, $1) }
        speechSettings.onAdd = { [weak self] in self?.onAddLanguage?($0) }
        speechSettings.onRemove = { [weak self] in self?.onRemoveLanguage?($0) }
        speechSettings.onPreview = { [weak self] in self?.onPreview?($0) }
        pages = [generalPage(), speechSettings, translationSettings, shortcutsPage(), screenPage(), copyPage()]
        tabs.tabPosition = .none
        tabs.tabViewBorderType = .none
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
                page.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
                page.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -24),
                page.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
                page.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -20)
            ])
            let item = NSTabViewItem(identifier: index)
            item.label = sections[index].title
            item.view = scroll
            tabs.addTabViewItem(item)
            scrollViews.append(scroll)
        }
        // Native sidebar selection, without push-button bezels or rotated labels.
        navigation.style = .plain
        navigation.headerView = nil
        navigation.rowHeight = 38
        navigation.intercellSpacing = NSSize(width: 0, height: 2)
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
        let brand = NSTextField(labelWithString: "QuietSelection")
        brand.font = .systemFont(ofSize: 15, weight: .bold)
        let brandHost = NSView()
        brand.translatesAutoresizingMaskIntoConstraints = false
        brandHost.addSubview(brand)
        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo: brandHost.leadingAnchor, constant: 18),
            brand.trailingAnchor.constraint(equalTo: brandHost.trailingAnchor, constant: -12),
            brand.topAnchor.constraint(equalTo: brandHost.topAnchor),
            brand.bottomAnchor.constraint(equalTo: brandHost.bottomAnchor)
        ])
        let sidebar = SettingsUI.page([brandHost, navigationScroll], spacing: 16)
        let divider = NSBox()
        divider.boxType = .separator
        let body = NSStackView(views: [sidebar, divider, tabs])
        body.orientation = .horizontal
        body.alignment = .top
        body.distribution = .fill
        body.spacing = 0
        NSLayoutConstraint.activate([
            sidebar.widthAnchor.constraint(equalToConstant: 210),
            sidebar.heightAnchor.constraint(equalTo: body.heightAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalTo: body.heightAnchor),
            tabs.heightAnchor.constraint(equalTo: body.heightAnchor),
            navigationScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        tabs.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stopButton = SettingsUI.button("Остановить", target: self, action: #selector(stop))
        status.font = .systemFont(ofSize: SettingsUI.bodySize)
        status.isSelectable = true
        status.maximumNumberOfLines = 3
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setAccessibilityLabel("Состояние чтения")
        let footer = NSStackView(views: [status, stopButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        let separator = NSBox()
        separator.boxType = .separator
        for view in [body, separator, footer] {
            root.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 440),
            body.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            separator.heightAnchor.constraint(equalToConstant: 1),
            footer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        setStatus("Готово")
        updateCopyFallback(apps: [], candidates: [])
        selectSection(0)
    }

    // MARK: Updates

    func update(voices: [VoiceChoice], selection: VoiceSettings, automatic: Bool, login: String) {
        speechSettings.update(voices: voices, selection: selection, automatic: automatic)
        loginSwitch.state = login == "enabled" || login == "requires_approval" ? .on : .off
        loginNote.stringValue = login == "enabled" ? "Окно настроек при входе не открывается"
            : login == "requires_approval" ? "macOS ожидает вашего разрешения в настройках входа"
            : "Выключено"
        loginSettings.isHidden = login != "requires_approval"
    }

    func updatePermissions(accessibility: Bool, screen: Bool) {
        accessibilityPermission.update(granted: accessibility)
        screenPermissionGeneral.update(granted: screen)
        screenPermissionPage.update(granted: screen)
    }

    /// `failed`: slots whose keys could not be registered (taken by another app).
    func updateShortcuts(_ slots: [ShortcutSlot], failed: Set<Int>, threshold: Double, doubleInterval: Double) {
        for (index, slot) in slots.enumerated() {
            recorders[index]?.shortcut = slot.shortcut
            select(slot.short, in: shortMenus[index])
            select(slot.double, in: doubleMenus[index])
            select(slot.long, in: longMenus[index])
            let warning = shortcutWarnings[index]
            if failed.contains(index) {
                warning?.stringValue = "Не удалось назначить: сочетание занято. Выберите другое."
                warning?.textColor = .systemOrange
            } else if let conflict = slot.shortcut?.systemConflict {
                warning?.stringValue = conflict
                warning?.textColor = .secondaryLabelColor
            } else {
                warning?.stringValue = ""
            }
            warning?.isHidden = warning?.stringValue.isEmpty ?? true
        }
        thresholdSlider.doubleValue = threshold
        doubleSlider.doubleValue = doubleInterval
        updateThresholdValue()
        if let place = ShortcutSettings.assignment(of: .regionRead, in: slots),
           let shortcut = slots[place.index].shortcut {
            let gesture = place.kind == .short ? "" : place.kind == .double ? ", дважды" : ", долгое нажатие"
            screenShortcut.stringValue = KeyNames.title(shortcut) + gesture
        } else {
            screenShortcut.stringValue = "Не назначено"
        }
    }

    private func select(_ function: ReadFunction?, in menu: NSPopUpButton?) {
        guard let menu else { return }
        let index = function.flatMap { value in menu.itemArray.firstIndex { ($0.representedObject as? String) == value.rawValue } } ?? 0
        menu.selectItem(at: index)
    }

    private func updateThresholdValue() {
        thresholdValue.stringValue = String(format: "%.2f с", thresholdSlider.doubleValue).replacingOccurrences(of: ".", with: ",")
        doubleValue.stringValue = String(format: "%.2f с", doubleSlider.doubleValue).replacingOccurrences(of: ".", with: ",")
    }

    func showShortcutMessage(_ message: String) { shortcutHint.stringValue = message }

    func setStatus(_ message: String, busy: Bool = false) {
        status.stringValue = message
        stopButton?.isEnabled = busy
    }

    func updateCopyFallback(apps: [(id: String, name: String)], candidates: [(id: String, name: String)]) {
        copyAppIDs = apps.map(\.id)
        for view in copyAppsCard.arrangedSubviews { copyAppsCard.removeArrangedSubview(view); view.removeFromSuperview() }
        var rows: [NSView] = []
        if apps.isEmpty {
            rows.append(SettingsUI.row("Список пуст", caption: SettingsUI.caption("Добавьте приложение кнопкой «Добавить»"), controls: []))
        }
        for (index, app) in apps.enumerated() {
            let remove = SettingsUI.iconButton("minus.circle", label: "Убрать " + app.name, target: self,
                                               action: #selector(copyAppRemoved(_:)))
            remove.tag = index
            let icon = NSImageView(image: Self.icon(for: app.id))
            icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let name = SettingsUI.text(app.name)
            let row = NSStackView(views: [icon, name, NSView(), remove])
            row.orientation = .horizontal
            row.spacing = 10
            row.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
            rows.append(row)
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                copyAppsCard.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: copyAppsCard.widthAnchor, constant: -28).isActive = true
            }
            copyAppsCard.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: copyAppsCard.widthAnchor, constant: -28).isActive = true
        }
        copyCandidateIDs = candidates.map(\.id)
        copyAddButton.removeAllItems()
        copyAddButton.addItem(withTitle: "Добавить…")
        for candidate in candidates {
            let item = NSMenuItem(title: candidate.name, action: #selector(copyAppAdded(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.id
            let image = Self.icon(for: candidate.id)
            image.size = NSSize(width: 16, height: 16)
            item.image = image
            copyAddButton.menu?.addItem(item)
        }
        if !candidates.isEmpty { copyAddButton.menu?.addItem(.separator()) }
        let choose = NSMenuItem(title: "Выбрать в папке «Программы»…", action: #selector(chooseCopyApp), keyEquivalent: "")
        choose.target = self
        copyAddButton.menu?.addItem(choose)
    }

    private static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: Presentation

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
    func windowWillClose(_ notification: Notification) {
        presentationPending = false
        for recorder in recorders.values { recorder.stop() }
    }
    func windowDidBecomeKey(_ notification: Notification) { onRefresh?() }
    func closeSettings() { window?.performClose(nil) }
    var selectedSection: Int { tabs.indexOfTabViewItem(tabs.selectedTabViewItem!) }
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = SettingsSectionCell()
        let title = NSTextField(labelWithString: sections[row].title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: sections[row].symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        for view in [title, icon] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.textField = title
        cell.imageView = icon
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
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
                precondition(frame.height >= 20, "Settings heading compressed")
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

    // MARK: Actions

    @objc private func resetShortcut(_ sender: NSButton) {
        guard ShortcutSlot.defaults.indices.contains(sender.tag),
              let shortcut = ShortcutSlot.defaults[sender.tag].shortcut else { return }
        onShortcutChange?(sender.tag, shortcut)
    }
    @objc private func slotFunctionChanged(_ sender: NSPopUpButton) {
        let function = (sender.selectedItem?.representedObject as? String).flatMap(ReadFunction.init(rawValue:))
        let kinds = PressKind.allCases
        onSlotFunction?(sender.tag / kinds.count, kinds[sender.tag % kinds.count], function)
    }
    @objc private func doubleIntervalChanged() {
        doubleSlider.doubleValue = (doubleSlider.doubleValue * 20).rounded() / 20
        updateThresholdValue()
        onDoubleInterval?(doubleSlider.doubleValue)
    }
    @objc private func thresholdChanged() {
        // Steps of 0.05 s are enough and easier to hear back.
        thresholdSlider.doubleValue = (thresholdSlider.doubleValue * 20).rounded() / 20
        updateThresholdValue()
        onThreshold?(thresholdSlider.doubleValue)
    }
    @objc private func readRegion() { onReadRegion?() }
    @objc private func screenPermission() { onScreenPermission?() }
    @objc private func loginChanged() { onLogin?(loginSwitch.state == .on) }
    @objc private func openLoginSettings() { onLoginSettings?() }
    @objc private func permission() { onPermission?() }
    @objc private func stop() { onStop?() }
    @objc private func quit() { onQuit?() }
    @objc private func copyAppAdded(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { onAddCopyApp?(id) }
    }
    @objc private func chooseCopyApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        onAddCopyApp?(id)
    }
    @objc private func copyAppRemoved(_ sender: NSButton) {
        guard copyAppIDs.indices.contains(sender.tag) else { return }
        onRemoveCopyApp?(copyAppIDs[sender.tag])
    }
}
