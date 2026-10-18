import AppKit

@MainActor
protocol RegionFocusBackend {
    associatedtype Target
    func captureTarget() -> Target?
    var ownsFocus: Bool { get }
    func restore(_ target: Target)
}

@MainActor
final class RegionFocus<Backend: RegionFocusBackend> {
    private let backend: Backend
    private var target: Backend.Target?
    init(backend: Backend) { self.backend = backend }
    func begin() { target = backend.captureTarget() }
    func finish(restore: Bool = true) {
        let previous = target
        target = nil
        // Consume the saved target once, including cancellation and app switches.
        // No delayed retries that could steal focus after the user moves elsewhere.
        guard restore, let previous, backend.ownsFocus else { return }
        backend.restore(previous)
    }
}

@MainActor
struct MacRegionFocus: RegionFocusBackend {
    @MainActor
    final class Target {
        let application: NSRunningApplication
        weak var window: NSWindow?
        weak var responder: NSResponder?
        init(application: NSRunningApplication) {
            self.application = application
            if application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                window = NSApp.keyWindow
                responder = window?.firstResponder
            }
        }
    }
    func captureTarget() -> Target? {
        // Application identity only; no AX query or inspection of other windows.
        NSWorkspace.shared.frontmostApplication.map { Target(application: $0) }
    }
    var ownsFocus: Bool {
        NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
    }
    func restore(_ target: Target) {
        guard !target.application.isTerminated else { return }
        if target.application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if let window = target.window, window.isVisible, !window.isMiniaturized {
                window.makeKeyAndOrderFront(nil)
                if let responder = target.responder { window.makeFirstResponder(responder) }
            }
        } else {
            // Transfer our active status to the original app, preserving its last
            // key window. Do not raise all its windows or change its AX focus.
            NSApp.yieldActivation(to: target.application)
            _ = target.application.activate(from: NSRunningApplication.current, options: [])
        }
    }
}
