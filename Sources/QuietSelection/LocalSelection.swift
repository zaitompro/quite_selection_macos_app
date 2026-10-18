import AppKit

@MainActor
enum LocalSelection {
    static func read(from window: NSWindow?) throws -> String {
        guard let editor = window?.firstResponder as? NSTextView else { throw SelectionFailure.noSelection }
        guard !(editor.delegate is NSSecureTextField) else { throw SelectionFailure.secureInput }
        let range = editor.selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { throw SelectionFailure.noSelection }
        guard range.length <= 60_000 else { throw SelectionFailure.tooLong }
        guard let storage = editor.textStorage, range.location <= storage.length,
              range.length <= storage.length - range.location else { throw SelectionFailure.invalidResponse }
        let selected = storage.attributedSubstring(from: range).string
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionFailure.noSelection
        }
        return selected
    }
}
