import AppKit

private final class RegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RegionPicker {
    private var panels: [NSPanel] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var completion: ((CGRect?) -> Void)?
    private let focus = RegionFocus(backend: MacRegionFocus())
    private var generation = 0
    var active: Bool { completion != nil }

    func begin(_ completion: @escaping (CGRect?) -> Void) {
        guard !active else { return }
        generation += 1
        let ticket = generation
        let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        focus.begin()
        self.completion = completion
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { finish(nil); return }
        for screen in NSScreen.screens {
            // Borrow keyboard input for Esc without activating QuietSelection or
            // raising its open settings window over the source application.
            let panel = RegionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        for panel in panels { panel.orderFrontRegardless() }
        if let first = panels.first {
            first.makeKey()
            first.makeFirstResponder(first.contentView)
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observe(name, center: .default) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    // A switch initiated by the user cancels the picker without
                    // returning them to the app from which they started.
                    self.finish(nil, restoreFocus: name != NSApplication.didResignActiveNotification)
                }
            }
        }
        // With a nonactivating panel our app may already be inactive. Observe
        // workspace activation as well, so a deliberate app switch still cancels.
        observe(NSWorkspace.didActivateApplicationNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                guard let self, self.generation == ticket, let pid, pid != sourcePID else { return }
                self.finish(nil, restoreFocus: false)
            }
        }
        for panel in panels {
            observe(NSWindow.didResignKeyNotification, center: .default, object: panel) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == ticket,
                          !self.panels.contains(where: { $0.isKeyWindow }) else { return }
                    // Moving between screens keeps another picker panel key.
                    // Moving away from the picker must not pull focus back.
                    self.finish(nil, restoreFocus: false)
                }
            }
        }
    }
    private func observe(_ name: Notification.Name, center: NotificationCenter, object: AnyObject? = nil,
                         handler: @escaping @Sendable (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: .main, using: handler)))
    }
    func cancel() { finish(nil) }
    private func finish(_ result: CGRect?, restoreFocus: Bool = true) {
        guard let done = completion else { return }
        completion = nil
        for (center, observer) in observers { center.removeObserver(observer) }
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
    override var needsPanelToBecomeKey: Bool { true }
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
