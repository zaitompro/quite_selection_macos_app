import Foundation

final class FakeBackend: SelectionBackend {
    var focus: Int? = 1
    var roleValue: String? = "AXTextArea"
    var subroleValue: String? = nil
    var text: String? = "Synthetic selection"
    var range: TextRange? = nil
    var rangeText: String? = nil
    var marker: Int? = nil
    var markerLength: Int? = nil
    var markerText: String? = nil
    var failure: SelectionFailure?
    var calls: [String] = []
    func focusedElement() throws -> Int? { calls.append("focus"); if let failure { throw failure }; return focus }
    func role(of element: Int) -> String? { calls.append("role"); return roleValue }
    func subrole(of element: Int) -> String? { calls.append("subrole"); return subroleValue }
    func selectedText(of element: Int) -> String? { calls.append("selected"); return text }
    func selectedRange(of element: Int) -> TextRange? { calls.append("range"); return range }
    func string(for range: TextRange, of element: Int) -> String? { calls.append("rangeString"); return rangeText }
    func selectedMarkerRange(of element: Int) -> Int? { calls.append("marker"); return marker }
    func length(of range: Int, in element: Int) -> Int? { calls.append("markerLength"); return markerLength }
    func string(forMarkerRange range: Int, of element: Int) -> String? { calls.append("markerString"); return markerText }
}

@main struct Tests {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { print("FAIL: \(name)"); exit(1) }
        count += 1
        print("PASS: \(name)")
    }
    static func fails(_ backend: FakeBackend, _ expected: SelectionFailure) -> Bool {
        do { _ = try SelectionReader(backend: backend).read(); return false }
        catch { return (error as? SelectionFailure) == expected }
    }
    static func main() throws {
        let direct = FakeBackend()
        check(try SelectionReader(backend: direct).read() == direct.text, "direct selection")
        check(direct.calls == ["focus", "role", "subrole", "selected"], "minimal attribute requests")
        let secure = FakeBackend(); secure.subroleValue = "AXSecureTextField"
        check(fails(secure, .secureInput) && !secure.calls.contains("selected"), "secure field never read")
        let absent = FakeBackend(); absent.focus = nil
        check(fails(absent, .noFocus) && absent.calls == ["focus"], "absent focus")
        let empty = FakeBackend(); empty.text = " \n\t"; empty.range = TextRange(location: 0, length: 2)
        check(fails(empty, .noSelection) && !empty.calls.contains("range"), "empty selection never falls back")
        let unsupported = FakeBackend(); unsupported.text = nil
        check(fails(unsupported, .unsupported), "unsupported selection")
        let fallback = FakeBackend(); fallback.text = nil
        fallback.rangeText = "Тест 🧪"; fallback.range = TextRange(location: 7, length: 7)
        check(try SelectionReader(backend: fallback).read() == fallback.rangeText, "UTF-16 selected range")
        let emptyRange = FakeBackend(); emptyRange.text = nil; emptyRange.range = TextRange(location: 7, length: 0)
        check(fails(emptyRange, .noSelection) && !emptyRange.calls.contains("rangeString"), "zero length range")
        let negative = FakeBackend(); negative.text = nil; negative.range = TextRange(location: -1, length: 2)
        check(fails(negative, .invalidResponse) && !negative.calls.contains("rangeString"), "invalid range rejected before text request")
        let overflow = FakeBackend(); overflow.text = nil; overflow.range = TextRange(location: Int.max, length: 2)
        check(fails(overflow, .invalidResponse), "range overflow")
        let large = FakeBackend(); large.text = nil; large.range = TextRange(location: 0, length: 60_001)
        check(fails(large, .tooLong) && !large.calls.contains("rangeString"), "oversize range never read")
        let largeText = FakeBackend(); largeText.text = String(repeating: "x", count: 60_001)
        check(fails(largeText, .tooLong), "oversize direct selection")
        let mismatch = FakeBackend(); mismatch.text = nil; mismatch.range = TextRange(location: 0, length: 5); mismatch.rangeText = "x"
        check(fails(mismatch, .invalidResponse), "range response length mismatch")
        let window = FakeBackend(); window.roleValue = "AXWindow"
        check(fails(window, .unsupported) && !window.calls.contains("selected"), "window not a text source")
        let timeout = FakeBackend(); timeout.failure = .accessibility(-25204)
        check(fails(timeout, .accessibility(-25204)) && timeout.calls == ["focus"], "AX failure propagated without retry")
        let web = FakeBackend(); web.roleValue = "AXWebArea"; web.text = nil
        web.marker = 42; web.markerLength = 7; web.markerText = "Тест 🧪"
        check(try SelectionReader(backend: web).read() == web.markerText, "web selected marker range with Unicode")
        check(web.calls == ["focus", "role", "subrole", "selected", "range", "marker", "markerLength", "markerString"], "web selection only; length checked before reading")
        web.calls = []; web.markerLength = 60_001
        check(fails(web, .tooLong) && !web.calls.contains("markerString"), "oversize web selection never read")
        web.calls = []; web.markerLength = 0
        check(fails(web, .noSelection) && !web.calls.contains("markerString"), "empty web selection never read")
        web.calls = []; web.markerLength = -1
        check(fails(web, .invalidResponse) && !web.calls.contains("markerString"), "negative web selection length")
        web.calls = []; web.markerLength = 7; web.markerText = "• Тест 🧪"
        check(try SelectionReader(backend: web).read() == web.markerText, "Firefox list marker is in text but not range length")
        web.calls = []; web.marker = nil
        check(fails(web, .unsupported) && !web.calls.contains("markerLength"), "unsupported web marker range")
        check(unsupported.calls.contains("marker"), "marker capability checked independently of role")
        check(!secure.calls.contains("marker"), "no web fallback on secure field")
        for role in ["AXGroup", "AXStaticText", "AXTextArea", "AXLink", "AXScrollArea"] {
            let delegated = FakeBackend(); delegated.roleValue = role; delegated.text = nil
            delegated.marker = 42; delegated.markerLength = 7; delegated.markerText = "Тест 🧪"
            check(try SelectionReader(backend: delegated).read() == delegated.markerText, "delegated selection on \(role)")
        }
        let emptyDirect = FakeBackend(); emptyDirect.roleValue = "AXGroup"; emptyDirect.text = ""
        emptyDirect.marker = 42; emptyDirect.markerLength = 7; emptyDirect.markerText = "Тест 🧪"
        check(try SelectionReader(backend: emptyDirect).read() == emptyDirect.markerText, "empty local selection permits document selected marker")
        let emptyEditor = FakeBackend(); emptyEditor.text = ""; emptyEditor.range = TextRange(location: 0, length: 0)
        emptyEditor.marker = 42; emptyEditor.markerLength = 7; emptyEditor.markerText = "Тест 🧪"
        check(try SelectionReader(backend: emptyEditor).read() == emptyEditor.markerText, "editor retains focus while document has a selection")
        emptyEditor.calls = []; emptyEditor.markerLength = 0
        check(fails(emptyEditor, .noSelection) && !emptyEditor.calls.contains("markerString"), "collapsed document range never reads text")
        let secureRole = FakeBackend(); secureRole.roleValue = "AXSecureTextField"
        check(fails(secureRole, .secureInput) && !secureRole.calls.contains("selected"), "secure role never reads text")
        let list = FakeBackend(); list.text = nil; list.roleValue = "AXList"
        list.marker = 42
        for (name, content, reported) in [
            ("multiple bullets", "• First\n• Second", 12),
            ("numbered list", "1. First\n2. Second", 12),
            ("nested list", "• Outer\n  ◦ Inner 🧪", 13),
            ("partial item", "First", 5)
        ] {
            list.markerText = content; list.markerLength = reported
            check(try SelectionReader(backend: list).read() == content, "selected range preserved: \(name)")
        }
        list.markerLength = 60_000; list.markerText = "• " + String(repeating: "x", count: 60_000)
        check(fails(list, .tooLong), "actual marker text limit includes generated bullets")
        list.markerLength = 10; list.markerText = ""
        check(fails(list, .noSelection), "empty text with nonempty marker never spoken")
        print("\(count) checks passed; no real application or selection accessed.")
    }
}
