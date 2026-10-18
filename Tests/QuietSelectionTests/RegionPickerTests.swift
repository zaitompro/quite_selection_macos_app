import AppKit

// Native window regression test: no AX queries, screenshots or external content.
// Run in a GUI session with another application in front.
@main
@MainActor
struct RegionPickerTests {
    static func pause() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await run()
            app.terminate(nil)
        }
        app.run()
    }

    static func run() async {
        let source = NSWorkspace.shared.frontmostApplication?.processIdentifier
        precondition(source != nil && source != ProcessInfo.processInfo.processIdentifier,
                     "Run with another application in front")
        let settings = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 120),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.title = "QuietSelection — synthetic focus test"
        settings.isReleasedWhenClosed = false
        settings.contentView = NSTextField(labelWithString: "Synthetic test. No capture or speech.")
        let picker = RegionPicker()
        var completions = 0
        var result: CGRect?

        for settingsVisible in [true, false] {
            if settingsVisible { settings.orderFrontRegardless() } else { settings.orderOut(nil) }
            await pause()
            for mode in 0..<3 {
                let before = completions
                result = nil
                picker.begin { rect in completions += 1; result = rect }
                await pause()
                precondition(picker.active)
                precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == source,
                             "Picker activated its owner")
                precondition(!settings.isKeyWindow, "Settings stole keyboard focus")
                let panels = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.nonactivatingPanel) }
                precondition(!panels.isEmpty)
                guard let panel = panels.first(where: { $0.isKeyWindow }), let view = panel.contentView else {
                    fatalError("Picker must accept Escape while its app is inactive")
                }
                if mode == 0 {
                    view.cancelOperation(nil)
                } else if mode == 1 {
                    // Exercise actual drag handlers without capturing the rectangle.
                    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 100),
                        modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 240, y: 160),
                        modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                        context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
                    view.mouseDown(with: down)
                    view.mouseUp(with: up)
                } else {
                    picker.cancel()
                }
                await pause()
                precondition(!picker.active && completions == before + 1)
                precondition((result != nil) == (mode == 1))
                precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == source)
                precondition(!settings.isKeyWindow && panels.allSatisfy { !$0.isVisible })
                picker.cancel()
                precondition(completions == before + 1)
            }
            print("region_picker=PASS settings_visible=\(settingsVisible) escape_drag_cancel focus_preserved")
        }
        // A deliberate move away must dismiss overlays, not restore old focus.
        picker.begin { _ in completions += 1 }
        await pause()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification,
            object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        await pause()
        precondition(!picker.active)
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == source)
        settings.close()
        print("region_picker=PASS app_switch_cancel; external_content_queries=0 captures=0")
    }
}
