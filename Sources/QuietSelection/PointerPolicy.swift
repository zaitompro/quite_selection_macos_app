import Foundation
import CoreGraphics

// Platform-free rules for reading under the mouse pointer. Coordinates are
// global screen points with the origin at the top left, as Accessibility uses.

enum PointerPolicy {
    /// Small tolerance so a pointer resting just beside the selection still counts.
    static let selectionMargin: CGFloat = 12

    /// Read the selection when the pointer is over it. When the application does
    /// not report where the selection is, the selection is read as before.
    static func readsSelection(selectionBounds: CGRect?, pointer: CGPoint) -> Bool {
        guard let bounds = selectionBounds, !bounds.isNull, !bounds.isEmpty else { return true }
        return bounds.insetBy(dx: -selectionMargin, dy: -selectionMargin).contains(pointer)
    }

    /// Characters read on each side of the pointer to find its paragraph; only
    /// this window is requested from the application, never the whole document.
    static let paragraphRadius = 4_000

    static func window(around index: Int, total: Int) -> TextRange? {
        guard total > 0, index >= 0 else { return nil }
        let clamped = min(index, total - 1)
        let start = max(0, clamped - paragraphRadius)
        let end = min(total, clamped + paragraphRadius)
        return TextRange(location: start, length: end - start)
    }

    private static let breaks: Set<UInt16> = [0x0A, 0x0D, 0x2029]

    /// The paragraph containing `offset` (UTF-16) in `text`: bounded by line
    /// breaks, trimmed; nil for an empty paragraph.
    static func paragraph(in text: String, aroundUTF16 offset: Int) -> String? {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return nil }
        var position = min(max(0, offset), units.count - 1)
        // Pointing at the break itself belongs to the paragraph before it.
        if breaks.contains(units[position]), position > 0 { position -= 1 }
        var start = position
        while start > 0, !breaks.contains(units[start - 1]) { start -= 1 }
        var end = position
        while end < units.count, !breaks.contains(units[end]) { end += 1 }
        guard start < end else { return nil }
        let result = String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Reject text that is empty or longer than the reading limit.
    static func validated(_ text: String?, limit: Int = 60_000) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.utf16.count <= limit else { return nil }
        return trimmed
    }
}
