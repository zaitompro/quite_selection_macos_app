import AppKit

private final class RegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RegionPicker {
    private var panels: [NSPanel] = []
    private var observers: [NSObjectProtocol] = []
    private var completion: ((CGRect?) -> Void)?
    private let focus = RegionFocus(backend: MacRegionFocus())
    private var generation = 0
    var active: Bool { completion != nil }

    func begin(_ completion: @escaping (CGRect?) -> Void) {
        guard !active else { return }
        generation += 1
        let ticket = generation
        focus.begin()
        self.completion = completion
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { finish(nil); return }
        for screen in NSScreen.screens {
            let panel = RegionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            let view = RegionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.finished = { [weak self] local in
                let result = local.map { RegionGeometry.captureRect(local: $0, screen: screen.frame, primaryTop: primaryTop) }
                self?.finish(result)
            }
            panel.contentView = view
            panels.append(panel)
        }
        NSApp.activate()
        for panel in panels { panel.orderFrontRegardless() }
        if let first = panels.first {
            first.makeKey()
            first.makeFirstResponder(first.contentView)
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    // A switch initiated by the user cancels the picker without
                    // returning them to the app from which they started.
                    self.finish(nil, restoreFocus: name != NSApplication.didResignActiveNotification)
                }
            })
        }
    }
    func cancel() { finish(nil) }
    private func finish(_ result: CGRect?, restoreFocus: Bool = true) {
        guard let done = completion else { return }
        completion = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        focus.finish(restore: restoreFocus)
        done(result)
    }
}

private final class RegionView: NSView {
    var finished: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        finished?(RegionGeometry.selection(from: start, to: end, bounds: bounds))
    }
    override func rightMouseDown(with event: NSEvent) { finished?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finished?(nil) }
    }
    override func cancelOperation(_ sender: Any?) { finished?(nil) }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        var selection: CGRect?
        if let start, let current { selection = RegionGeometry.selection(from: start, to: current, bounds: bounds) }
        if let selection { shade.appendRect(selection); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.28).setFill()
        shade.fill()
        if let selection {
            NSColor.black.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 6; border.stroke()
            NSColor.white.setStroke(); border.lineWidth = 3; border.stroke()
        }
        let text = "Выделите область для чтения. Esc — отмена."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = NSRect(x: max(16, (bounds.width - size.width - 32) / 2), y: bounds.height - 100,
                         width: min(bounds.width - 32, size.width + 32), height: 54)
        NSColor.black.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(in: box.insetBy(dx: 16, dy: 12), withAttributes: attributes)
    }
}
