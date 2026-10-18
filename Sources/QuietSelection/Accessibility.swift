import AppKit
import ApplicationServices

final class AXDiagnostics {
    var role = "роль неизвестна"
    var stage = "фокус"
    var focusResults: [String] = []
}

struct AccessibilityBackend: SelectionBackend, FocusedElementSource {
    let pid: pid_t
    let allowsAccessibilityPreparation: Bool
    let diagnostics = AXDiagnostics()
    private let deadline = Date().addingTimeInterval(2)

    private func prepare(_ element: AXUIElement) throws {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw SelectionFailure.accessibility(AXError.cannotComplete.rawValue) }
        AXUIElementSetMessagingTimeout(element, Float(min(0.5, remaining)))
    }

    private func optional(_ status: AXError) throws -> Bool {
        switch status {
        case .success: return true
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .noValue: return false
        default: throw SelectionFailure.accessibility(status.rawValue)
        }
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) throws -> CFTypeRef? {
        // This only limits this client's message wait; it does not change target UI.
        try prepare(element)
        var value: CFTypeRef?
        guard try optional(AXUIElementCopyAttributeValue(element, name, &value)) else { return nil }
        return value
    }

    private func text(_ element: AXUIElement, _ name: CFString) throws -> String? {
        guard let value = try attribute(element, name) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String else {
            throw SelectionFailure.invalidResponse
        }
        return string
    }

    func focusedElement() throws -> AXUIElement? {
        try FocusedElementResolver(source: self, targetPID: pid).resolve()
    }

    var isTargetFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    func applicationFocus() throws -> AXUIElement? {
        diagnostics.stage = "фокус приложения"
        let app = AXUIElementCreateApplication(pid)
        return try focusAttribute(app, kAXFocusedUIElementAttribute as CFString, label: "прил.")
    }

    func systemFocus() throws -> AXUIElement? {
        diagnostics.stage = "системный фокус"
        return try focusAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, label: "сист.")
    }

    func prepareApplicationAccessibility() throws -> Bool {
        diagnostics.stage = "AXRole приложения"
        // Chromium's BrowserCrApplication.accessibilityRole lazily enables its
        // accessibility mode. Use the standard read-only role attribute, never
        // private activation flags. This path is restricted to ChatGPT/Codex.
        // Reference: chromium/chromium chrome/browser/chrome_browser_application_mac.mm
        guard try text(AXUIElementCreateApplication(pid), kAXRoleAttribute as CFString) == "AXApplication" else {
            diagnostics.focusResults.append("роль прил.: недоступна")
            return false
        }
        diagnostics.focusResults.append("роль прил.: OK")
        // Called only on the selection worker. Allow asynchronous renderer setup
        // a brief interval; the original overall deadline remains in force.
        Thread.sleep(forTimeInterval: 0.15)
        return true
    }

    private func focusAttribute(_ element: AXUIElement, _ name: CFString, label: String) throws -> AXUIElement? {
        try prepare(element)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        // Fixed labels and numeric AX codes only: no titles, names, or text.
        let outcome = status == .success ? (value == nil ? "пусто" : "OK") : String(status.rawValue)
        diagnostics.focusResults.append("\(label): \(outcome)")
        guard try optional(status), let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw SelectionFailure.invalidResponse }
        return (value as! AXUIElement)
    }

    func processID(of element: AXUIElement) throws -> Int32 {
        var owner: pid_t = 0
        let status = AXUIElementGetPid(element, &owner)
        guard status == .success else { throw SelectionFailure.accessibility(status.rawValue) }
        return owner
    }

    func role(of element: AXUIElement) throws -> String? {
        let value = try text(element, kAXRoleAttribute as CFString)
        let knownRoles = ["AXWebArea", "AXScrollArea", "AXGroup", "AXTextArea", "AXTextField",
                          "AXStaticText", "AXWindow", "AXApplication", "AXMenu", "AXMenuItem",
                          "AXOutline", "AXTable", "AXLink", "AXButton", "AXList", "AXRow"]
        diagnostics.role = value.flatMap { knownRoles.contains($0) ? $0 : nil } ?? "другая роль"
        return value
    }
    func subrole(of element: AXUIElement) throws -> String? {
        try text(element, kAXSubroleAttribute as CFString)
    }
    func selectedText(of element: AXUIElement) throws -> String? {
        diagnostics.stage = "AXSelectedText"
        return try text(element, kAXSelectedTextAttribute as CFString)
    }
    func selectedRange(of element: AXUIElement) throws -> TextRange? {
        diagnostics.stage = "AXSelectedTextRange"
        guard let value = try attribute(element, kAXSelectedTextRangeAttribute as CFString) else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { throw SelectionFailure.invalidResponse }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { throw SelectionFailure.invalidResponse }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { throw SelectionFailure.invalidResponse }
        return TextRange(location: range.location, length: range.length)
    }
    func string(for range: TextRange, of element: AXUIElement) throws -> String? {
        diagnostics.stage = "AXStringForRange"
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else {
            throw SelectionFailure.invalidResponse
        }
        var value: CFTypeRef?
        try prepare(element)
        guard try optional(AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value
        )) else { return nil }
        guard let value, CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String else {
            throw SelectionFailure.invalidResponse
        }
        return string
    }

    func selectedMarkerRange(of element: AXUIElement) throws -> AXTextMarkerRange? {
        diagnostics.stage = "AXSelectedTextMarkerRange"
        guard let value = try attribute(element, kAXSelectedTextMarkerRangeAttribute as CFString) else { return nil }
        guard CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else {
            throw SelectionFailure.invalidResponse
        }
        return (value as! AXTextMarkerRange)
    }

    private func markerValue(_ element: AXUIElement, _ name: CFString,
                             _ range: AXTextMarkerRange) throws -> CFTypeRef? {
        var value: CFTypeRef?
        try prepare(element)
        guard try optional(AXUIElementCopyParameterizedAttributeValue(element, name, range, &value)) else {
            return nil
        }
        return value
    }

    func length(of range: AXTextMarkerRange, in element: AXUIElement) throws -> Int? {
        diagnostics.stage = "AXLengthForTextMarkerRange"
        guard let value = try markerValue(element, kAXLengthForTextMarkerRangeParameterizedAttribute as CFString, range)
        else { return nil }
        guard CFGetTypeID(value) == CFNumberGetTypeID() else { throw SelectionFailure.invalidResponse }
        let number = value as! CFNumber
        var length: Int64 = 0
        guard !CFNumberIsFloatType(number), CFNumberGetValue(number, .sInt64Type, &length),
              let result = Int(exactly: length) else { throw SelectionFailure.invalidResponse }
        return result
    }

    func string(forMarkerRange range: AXTextMarkerRange, of element: AXUIElement) throws -> String? {
        diagnostics.stage = "AXStringForTextMarkerRange"
        guard let value = try markerValue(element, kAXStringForTextMarkerRangeParameterizedAttribute as CFString, range)
        else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String else {
            throw SelectionFailure.invalidResponse
        }
        return string
    }
}
