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
        let heading = Self.label("Перевод", size: 26, bold: true)
        let targetTitle = Self.label("Перевод на", bold: true)
        targetLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        let targetRow = TranslationCard(views: [targetTitle, NSView(), targetLabel])
        targetRow.orientation = .horizontal
        targetRow.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        let refresh = NSButton(title: "Проверить готовность", target: self, action: #selector(refreshPressed))
        refresh.bezelStyle = .rounded
        refresh.font = .systemFont(ofSize: 17)
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
            Self.label("Определить язык выделенного текста, перевести на основной язык и прочитать."),
            targetRow,
            Self.label("Перевод с", bold: true),
            Self.label("Список берётся из включённых дополнительных языков раздела «Речь».", size: 16),
            list, refresh,
            Self.label("macOS запросит разрешение на загрузку языков. После загрузки перевод выполняется на Mac без интернета.", size: 16),
            Self.label("Если язык не определён — предложим выбрать его. Текст на основном языке читается без перевода.", size: 16)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for view in stack.views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private static func label(_ text: String, size: CGFloat = 17, bold: Bool = false) -> NSTextField {
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
                let empty = Self.label("Добавьте и включите дополнительные языки в разделе «Речь».")
                rows.addArrangedSubview(empty)
                empty.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            }
            for (index, code) in sorted.enumerated() {
                let name = Self.label(VoiceChoice.languageTitle(code) + " → " + VoiceChoice.languageTitle(target), bold: true)
                let state = Self.label("Проверка…", size: 16)
                let labels = NSStackView(views: [name, state])
                labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 8
                let download = NSButton(title: "Загрузить…", target: self, action: #selector(downloadPressed(_:)))
                download.bezelStyle = .rounded; download.font = .systemFont(ofSize: 17); download.tag = index
                download.setAccessibilityLabel("Загрузить языки: " + name.stringValue)
                download.setContentCompressionResistancePriority(.required, for: .horizontal)
                let row = TranslationCard(views: [labels, NSView(), download])
                row.orientation = .horizontal; row.spacing = 12
                row.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
                rows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
                statusLabels[code] = state; downloadButtons[code] = download
            }
        }
        for code in sorted {
            let state = states[code] ?? .checking
            statusLabels[code]?.stringValue = state.title
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
