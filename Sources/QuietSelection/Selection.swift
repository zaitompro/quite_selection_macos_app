import Foundation

// This layer has no platform side effects. Tests use a synthetic backend.
enum SelectionFailure: Error, Equatable {
    case permission, noFocus, secureInput, noSelection, unsupported, tooLong
    case invalidResponse, changedApplication, busy
    case accessibility(Int32)

    var message: String {
        switch self {
        case .permission: return "Нужно разрешение Accessibility для QuietSelection"
        case .noFocus: return "Нет доступного элемента с фокусом"
        case .secureInput: return "Защищённое поле: чтение запрещено"
        case .noSelection: return "Нет выделенного текста"
        case .unsupported: return "Элемент с фокусом не отдаёт выделение через AX"
        case .tooLong: return "Выделение длиннее 60 000 символов UTF-16"
        case .invalidResponse: return "Некорректный ответ Accessibility"
        case .changedApplication: return "Активное приложение изменилось: чтение отменено"
        case .busy: return "Запрос отменён"
        case .accessibility(let code): return "Ошибка Accessibility: \(code)"
        }
    }
}

struct TextRange: Equatable {
    let location: Int
    let length: Int
}

protocol SelectionBackend {
    associatedtype Element
    associatedtype MarkerRange
    func focusedElement() throws -> Element?
    func role(of element: Element) throws -> String?
    func subrole(of element: Element) throws -> String?
    func selectedText(of element: Element) throws -> String?
    func selectedRange(of element: Element) throws -> TextRange?
    func string(for range: TextRange, of element: Element) throws -> String?
    func selectedMarkerRange(of element: Element) throws -> MarkerRange?
    func length(of range: MarkerRange, in element: Element) throws -> Int?
    func string(forMarkerRange range: MarkerRange, of element: Element) throws -> String?
}

struct SelectionReader<Backend: SelectionBackend> {
    let backend: Backend
    static var limit: Int { 60_000 }

    func read() throws -> String {
        guard let focused = try backend.focusedElement() else { throw SelectionFailure.noFocus }
        return try read(focused, role: backend.role(of: focused))
    }

    private func read(_ element: Backend.Element, role: String?) throws -> String {
        // Never ask secure fields for text or ranges. No titles, values, children,
        // ancestors, URLs, or whole-document text are requested.
        let subrole = try backend.subrole(of: element)
        guard subrole != "AXSecureTextField", role != "AXSecureTextField" else { throw SelectionFailure.secureInput }
        guard let role, !["AXApplication", "AXWindow", "AXMenu", "AXMenuItem"].contains(role)
        else { throw SelectionFailure.unsupported }

        let direct = try backend.selectedText(of: element)
        if let direct, !direct.isEmpty { return try validate(direct) }
        // Only the actual selection range, only on this same focused element.
        // AXValue (whole document) is deliberately not used.
        guard let range = try backend.selectedRange(of: element) else {
            // These web-content attributes are public in Apple SDK 26.5's
            // AXWebConstants.h. Use only the selected range, never document bounds.
            return try readWebSelection(element, emptyReported: direct != nil)
        }
        guard range.location >= 0, range.length >= 0,
              range.location <= Int.max - range.length else {
            throw SelectionFailure.invalidResponse
        }
        guard range.length > 0 else {
            return try readWebSelection(element, emptyReported: true)
        }
        guard range.length <= Self.limit else { throw SelectionFailure.tooLong }
        guard let text = try backend.string(for: range, of: element) else {
            throw SelectionFailure.unsupported
        }
        guard text.utf16.count == range.length else { throw SelectionFailure.invalidResponse }
        return try validate(text)
    }

    private func readWebSelection(_ element: Backend.Element, emptyReported: Bool = false) throws -> String {
        // Firefox delegates these attributes from many roles, not just AXWebArea.
        guard let range = try backend.selectedMarkerRange(of: element) else {
            throw emptyReported ? SelectionFailure.noSelection : SelectionFailure.unsupported
        }
        guard let length = try backend.length(of: range, in: element) else { throw SelectionFailure.unsupported }
        guard length >= 0 else { throw SelectionFailure.invalidResponse }
        guard length > 0 else { throw SelectionFailure.noSelection }
        guard length <= Self.limit else { throw SelectionFailure.tooLong }
        guard let text = try backend.string(forMarkerRange: range, of: element) else {
            throw SelectionFailure.unsupported
        }
        // An opaque marker range is not an NSRange into the returned string.
        // Firefox includes generated list markers in Text(), but deliberately
        // excludes them from Length() (GeckoTextMarkerRange). Keep both size
        // limits; do not reject selected text merely for that representation gap.
        return try validate(text)
    }

    private func validate(_ text: String) throws -> String {
        guard text.utf16.count <= Self.limit else { throw SelectionFailure.tooLong }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionFailure.noSelection
        }
        return text
    }
}
