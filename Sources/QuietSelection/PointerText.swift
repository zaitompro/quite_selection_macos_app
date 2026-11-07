import AppKit
import ApplicationServices

// The only file allowed to read the pointer position, ask Accessibility for the
// element at a screen point, walk to its parents, or read an element's value
// or title (see Tests/privacy_audit.py). Used only when a reading shortcut is
// pressed and the pointer is not over the selection. Only the paragraph at the
// pointer is read; nothing is logged or written.

struct PointerTarget {
    let point: CGPoint
    let element: AXUIElement
    let pid: pid_t

    /// Pointer position in global top-left coordinates (the same as
    /// Accessibility, unaffected by the full-screen Zoom magnification).
    @MainActor
    static func current() -> PointerTarget? {
        let location = NSEvent.mouseLocation
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
        let point = CGPoint(x: location.x, y: primaryTop - location.y)
        guard let element = elementAt(point) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return PointerTarget(point: point, element: element, pid: pid)
    }

    static func elementAt(_ point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }

    /// Hit-test again, for example after Chromium has built its accessibility tree.
    func refreshed() -> PointerTarget? {
        guard let element = Self.elementAt(point) else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
        return PointerTarget(point: point, element: element, pid: pid)
    }
}

extension PointerTarget {
    /// Where to look for the paragraph under the pointer: the screen under the
    /// pointer, limited to the first element (or ancestor) large enough to hold
    /// text, such as an image, a message or a document area. Only frames are read.
    @MainActor
    func recognitionBounds() -> CGRect {
        let cocoaPoint = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
        let screen = NSScreen.screens.first { $0.frame.contains(cocoaPoint) } ?? NSScreen.screens.first
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenRect = screen.map {
            CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        } ?? .null
        var current: AXUIElement? = element
        for _ in 0..<10 {
            guard let candidate = current else { break }
            if let frame = Self.frame(of: candidate), frame.width >= 240, frame.height >= 48, frame.contains(point) {
                return frame.intersection(screenRect)
            }
            var parent: CFTypeRef?
            AXUIElementSetMessagingTimeout(candidate, 0.5)
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        return screenRect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// Pointer position only, for recognition when no element can be found.
    @MainActor
    static func location() -> CGPoint? {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x, y: primaryTop - location.y)
    }

    @MainActor
    static func screenBounds(at point: CGPoint) -> CGRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let cocoaPoint = CGPoint(x: point.x, y: primaryTop - point.y)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) }) ?? NSScreen.screens.first else { return .null }
        return CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    }
}

struct PointerTextReader {
    private let deadline = Date().addingTimeInterval(3)
    static let limit = 60_000
    /// Editable fields that cannot locate a position are read whole only when short.
    static let editableValueLimit = 4_000

    func read(_ target: PointerTarget) throws -> String {
        let element = target.element
        let role = text(element, kAXRoleAttribute)
        let subrole = text(element, kAXSubroleAttribute)
        guard role != "AXSecureTextField", subrole != "AXSecureTextField" else { throw SelectionFailure.secureInput }
        if let paragraph = webParagraph(element, at: target.point) { return paragraph }
        if let paragraph = textParagraph(element, at: target.point) { return paragraph }
        let editable = role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox"
        let valueLimit = editable ? Self.editableValueLimit : Self.limit
        for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = PointerPolicy.validated(text(element, name), limit: valueLimit) { return value }
        }
        throw SelectionFailure.nothingUnderPointer
    }

    // MARK: Web content (Safari, Mail, Firefox, Chromium)

    private func webParagraph(_ element: AXUIElement, at point: CGPoint) -> String? {
        var point = point
        guard let pointValue = AXValueCreate(.cgPoint, &point) else { return nil }
        // Text-marker queries are answered by the web area; inner elements may
        // forward them. Walk up a few parents at most.
        var current: AXUIElement? = element
        for _ in 0..<10 {
            guard let holder = current else { return nil }
            if let marker = parameterized(holder, kAXTextMarkerForPositionParameterizedAttribute, pointValue),
               CFGetTypeID(marker) == AXTextMarkerGetTypeID(),
               let range = parameterized(holder, kAXParagraphTextMarkerRangeForTextMarkerParameterizedAttribute, marker),
               CFGetTypeID(range) == AXTextMarkerRangeGetTypeID(),
               let string = parameterized(holder, kAXStringForTextMarkerRangeParameterizedAttribute, range) as? String {
                return PointerPolicy.validated(string, limit: Self.limit)
            }
            current = attribute(holder, kAXParentAttribute).flatMap {
                CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
            }
        }
        return nil
    }

    // MARK: Plain text (text views, Notes, Pages, Terminal)

    private func textParagraph(_ element: AXUIElement, at point: CGPoint) -> String? {
        var point = point
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let rangeValue = parameterized(element, kAXRangeForPositionParameterizedAttribute, pointValue),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var hit = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &hit),
              let total = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue,
              let window = PointerPolicy.window(around: hit.location, total: total) else { return nil }
        var cfWindow = CFRange(location: window.location, length: window.length)
        guard let windowValue = AXValueCreate(.cfRange, &cfWindow),
              let string = parameterized(element, kAXStringForRangeParameterizedAttribute, windowValue) as? String
        else { return nil }
        return PointerPolicy.paragraph(in: string, aroundUTF16: hit.location - window.location)
            .flatMap { PointerPolicy.validated($0, limit: Self.limit) }
    }

    // MARK: Accessibility helpers (read-only)

    private func prepare(_ element: AXUIElement) -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(1.5, remaining)))
        return true
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard prepare(element) else { return nil }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func text(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }
    private func parameterized(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        guard prepare(element) else { return nil }
        var value: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success ? value : nil
    }
}
