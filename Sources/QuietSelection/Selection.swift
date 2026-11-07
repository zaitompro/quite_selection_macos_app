import Foundation

// This layer has no platform side effects. Tests use a synthetic backend.
enum SelectionFailure: Error, Equatable {
    case permission, noFocus, secureInput, secureKeyboard, noSelection, unsupported, tooLong
    case invalidResponse, changedApplication, busy, nothingUnderPointer
    case accessibility(Int32)

    var message: String {
        switch self {
        case .permission: return "Нужно разрешение Accessibility для QuietSelection"
        case .noFocus: return "Нет доступного элемента с фокусом"
        case .secureInput: return "Защищённое поле: чтение запрещено"
        case .secureKeyboard: return "В активном приложении включён защищённый ввод (поле пароля или Secure Keyboard Entry): чтение запрещено"
        case .noSelection: return "Нет выделенного текста"
        case .unsupported: return "Элемент с фокусом не отдаёт выделение через AX"
        case .tooLong: return "Выделение длиннее 60 000 символов UTF-16"
        case .invalidResponse: return "Некорректный ответ Accessibility"
        case .changedApplication: return "Активное приложение изменилось: чтение отменено"
        case .busy: return "Запрос отменён"
        case .nothingUnderPointer: return "Под курсором нет текста, который передаёт система"
        case .accessibility(let code): return "Ошибка Accessibility: \(code)"
        }
    }

    var isAccessibilityError: Bool {
        if case .accessibility = self { return true }
        return false
    }
}

// macOS reports secure keyboard input system-wide. Refuse reading when the
// target application holds it, or when its holder cannot be identified.
// A password field left focused in some other application does not block
// reading the frontmost application's selection; its own secure fields are
// still rejected by SelectionReader.
enum SecureInputPolicy {
    static func blocks(enabled: Bool, holder: Int32?, target: Int32?) -> Bool {
        guard enabled else { return false }
        guard let holder, let target else { return true }
        return holder == target
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

        // An Accessibility error from one selection attribute does not rule out
        // the others: applications often implement only some of them.
        var axError: SelectionFailure?
        let direct: String?
        do { direct = try backend.selectedText(of: element) }
        catch let error as SelectionFailure where error.isAccessibilityError { axError = error; direct = nil }
        if let direct, !direct.isEmpty { return try validate(direct) }
        // Only the actual selection range, only on this same focused element.
        // AXValue (whole document) is deliberately not used.
        let reported: TextRange?
        do { reported = try backend.selectedRange(of: element) }
        catch let error as SelectionFailure where error.isAccessibilityError { axError = axError ?? error; reported = nil }
        guard let range = reported else {
            // These web-content attributes are public in Apple SDK 26.5's
            // AXWebConstants.h. Use only the selected range, never document bounds.
            return try readWebSelection(element, emptyReported: direct != nil, previous: axError)
        }
        guard range.location >= 0, range.length >= 0,
              range.location <= Int.max - range.length else {
            throw SelectionFailure.invalidResponse
        }
        guard range.length > 0 else {
            return try readWebSelection(element, emptyReported: true, previous: axError)
        }
        guard range.length <= Self.limit else { throw SelectionFailure.tooLong }
        let ranged: String?
        do { ranged = try backend.string(for: range, of: element) }
        catch let error as SelectionFailure where error.isAccessibilityError { axError = axError ?? error; ranged = nil }
        guard let text = ranged else {
            return try readWebSelection(element, emptyReported: false, previous: axError)
        }
        // Lengths legitimately differ a little (line endings, attachments,
        // composed characters). A much longer reply means the application
        // ignored the requested range, so it is not treated as the selection.
        guard text.utf16.count <= Self.maximumLength(forRange: range.length) else {
            throw SelectionFailure.invalidResponse
        }
        return try validate(text)
    }

    static func maximumLength(forRange length: Int) -> Int { length * 2 + 64 }

    private func readWebSelection(_ element: Backend.Element, emptyReported: Bool = false,
                                  previous: SelectionFailure? = nil) throws -> String {
        // Firefox delegates these attributes from many roles, not just AXWebArea.
        let marker: Backend.MarkerRange?
        do { marker = try backend.selectedMarkerRange(of: element) }
        catch let error as SelectionFailure where error.isAccessibilityError {
            if emptyReported { throw SelectionFailure.noSelection }
            throw previous ?? error
        }
        guard let range = marker else {
            if emptyReported { throw SelectionFailure.noSelection }
            throw previous ?? SelectionFailure.unsupported
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
