import AppKit
import ApplicationServices
import Carbon

// The only file allowed to use the clipboard, post keyboard events, read menu
// children or press a menu item (see Tests/privacy_audit.py). It is used only for
// applications listed by the user in Settings → General → "Чтение через копирование",
// and only after the normal Accessibility selection read has failed.

final class SystemClipboard: ClipboardStore {
    private let board = NSPasteboard.general
    private var items: [NSPasteboardItem] = []

    var changeCount: Int { board.changeCount }

    func itemTypes() -> [[String]] {
        items = board.pasteboardItems ?? []
        return items.map { $0.types.map(\.rawValue) }
    }

    func data(itemIndex: Int, type: String) -> Data? {
        guard items.indices.contains(itemIndex) else { return nil }
        return items[itemIndex].data(forType: NSPasteboard.PasteboardType(type))
    }

    func plainText() -> String? { board.string(forType: .string) }

    func replace(with saved: [[ClipboardEntry]]) {
        board.clearContents()
        let objects = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type)) }
            return item
        }
        if !objects.isEmpty { board.writeObjects(objects) }
        items = []
    }
}

enum CopyCommand {
    /// Presses the application's own menu item with the ⌘C shortcut (normally
    /// Edit → Copy). Found by its shortcut, not its title, so the interface
    /// language does not matter; no keys are pressed and held modifiers do not
    /// interfere. Only menu-bar items are read: no window content is inspected.
    static func pressCopyMenuItem(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let barValue = value(app, kAXMenuBarAttribute),
              CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return false }
        let bar = barValue as! AXUIElement
        // Skip the Apple menu; Edit is normally within the first few menus.
        for top in children(bar).dropFirst().prefix(8) {
            for menu in children(top) {
                for item in children(menu) {
                    // Modifiers 0 means Command alone (kAXMenuItemModifierNone).
                    guard (value(item, kAXMenuItemCmdCharAttribute) as? String)?.uppercased() == "C",
                          (value(item, kAXMenuItemCmdModifiersAttribute) as? Int) == 0
                    else { continue }
                    if (value(item, kAXEnabledAttribute) as? Bool) == false { return false }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    /// Sends ⌘C to the application after the user has released the reading
    /// shortcut, so that held keys cannot turn it into another command.
    static func sendCommandC(pid: pid_t) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(1.5)
        var released = false
        while Date() < deadline {
            let held = CGEventSource.flagsState(.combinedSessionState).intersection(modifiers)
            let escape = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape))
            if held.isEmpty && !escape { released = true; break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard released,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}

enum ClipboardCopy {
    /// Runs on the selection worker; blocks for at most a few seconds.
    static func read(pid: pid_t) throws -> String {
        let reader = CopyFallbackReader(store: SystemClipboard()) { Thread.sleep(forTimeInterval: $0) }
        return try reader.read(
            attempts: [{ CopyCommand.pressCopyMenuItem(pid: pid) }, { CopyCommand.sendCommandC(pid: pid) }],
            isTargetFrontmost: { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid })
    }
}
