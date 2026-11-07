import AppKit

private final class TranslationList: NSView { override var isFlipped: Bool { true } }
private final class TranslationCard: NSStackView {
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.25).setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.stroke()
    }
}

@MainActor
final class TranslationSettingsView: NSView {
    var onRefresh: (() -> Void)?
    var onDownload: ((String) -> Void)?
    private let targetLabel = NSTextField(labelWithString: "")
    private let rows = NSStackView()
    let list = NSScrollView()
    private var sources: [String] = []
    private var target = ""
    private var statusLabels: [String: NSTextField] = [:]
    private(set) var downloadButtons: [String: NSButton] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        let heading = SettingsUI.pageTitle("Перевод")
        targetLabel.font = .systemFont(ofSize: SettingsUI.bodySize, weight: .semibold)
        let targetRow = SettingsUI.card([
            SettingsUI.row("Перевод на", caption: SettingsUI.caption("Основной язык; меняется в разделе «Речь»"),
                           controls: [targetLabel])
        ])
        let refresh = SettingsUI.iconButton("arrow.clockwise", label: "Проверить готовность языков",
                                            target: self, action: #selector(refreshPressed))
        let sourcesHeader = NSStackView(views: [SettingsUI.groupTitle("Перевод с"), NSView(), refresh])
        sourcesHeader.orientation = .horizontal
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        let document = TranslationList()
        document.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        list.documentView = document
        list.hasVerticalScroller = true
        list.autohidesScrollers = true
        list.drawsBackground = false
        NSLayoutConstraint.activate([
            list.heightAnchor.constraint(equalToConstant: 240),
            document.widthAnchor.constraint(equalTo: list.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: list.contentView.heightAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            rows.topAnchor.constraint(equalTo: document.topAnchor),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor)
        ])
        let stack = NSStackView(views: [heading,
            SettingsUI.caption("Определить язык выделенного текста, перевести на основной язык и прочитать."),
            targetRow,
            sourcesHeader,
            SettingsUI.caption("Включённые дополнительные языки из раздела «Речь»."),
            list,
            SettingsUI.caption("Для загрузки языков macOS запросит разрешение; после загрузки перевод работает без интернета. Если язык не определён, программа предложит выбрать его; текст на основном языке читается без перевода.")])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for view in stack.views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private static func label(_ text: String, size: CGFloat = SettingsUI.bodySize, bold: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        view.isSelectable = true
        return view
    }
    func update(target: String, sources: [String], states: [String: TranslationReadiness]) {
        targetLabel.stringValue = VoiceChoice.languageTitle(target)
        let sorted = sources.filter { $0 != target }.sorted {
            VoiceChoice.languageTitle($0).localizedCaseInsensitiveCompare(VoiceChoice.languageTitle($1)) == .orderedAscending
        }
        if self.target != target || self.sources != sorted {
            self.target = target; self.sources = sorted
            for view in rows.views { rows.removeArrangedSubview(view); view.removeFromSuperview() }
            statusLabels.removeAll(); downloadButtons.removeAll()
            if sorted.isEmpty {
                let empty = SettingsUI.caption("Добавьте и включите дополнительные языки в разделе «Речь».")
                rows.addArrangedSubview(empty)
                empty.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            }
            for (index, code) in sorted.enumerated() {
                let name = Self.label(VoiceChoice.languageTitle(code) + " → " + VoiceChoice.languageTitle(target), bold: true)
                let state = SettingsUI.caption("Проверка…")
                let labels = NSStackView(views: [name, state])
                labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 2
                let download = SettingsUI.button("Загрузить…", target: self, action: #selector(downloadPressed(_:)))
                download.tag = index
                download.setAccessibilityLabel("Загрузить языки: " + name.stringValue)
                download.setContentCompressionResistancePriority(.required, for: .horizontal)
                let row = TranslationCard(views: [labels, NSView(), download])
                row.orientation = .horizontal; row.spacing = 12
                row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
                rows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
                statusLabels[code] = state; downloadButtons[code] = download
            }
        }
        for code in sorted {
            let state = states[code] ?? .checking
            statusLabels[code]?.stringValue = state.title
            statusLabels[code]?.textColor = state == .installed ? .systemGreen : .secondaryLabelColor
            downloadButtons[code]?.isHidden = state == .installed || state == .unsupported
            downloadButtons[code]?.isEnabled = state == .supported
        }
    }
    @objc private func refreshPressed() { onRefresh?() }
    @objc private func downloadPressed(_ sender: NSButton) {
        guard sources.indices.contains(sender.tag) else { return }
        onDownload?(sources[sender.tag])
    }
}
