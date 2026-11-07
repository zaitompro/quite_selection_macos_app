import Foundation

// Reading a selection by asking the application to copy it, for applications the
// user listed explicitly. This layer has no platform side effects: the clipboard
// and the copy command are supplied by the caller, so tests use fakes.
//
// Rules:
// - The previous clipboard is saved completely before anything is copied. If it
//   cannot be saved without loss, nothing is copied and the clipboard is untouched.
// - The previous clipboard is restored immediately after the text is taken,
//   before speech starts, unless something else changed the clipboard meanwhile.
// - Nothing is logged or written to disk.

enum CopyFallbackFailure: Error, Equatable {
    case unsafeClipboard, nothingCopied, notText, changedApplication, tooLong

    var message: String {
        switch self {
        case .unsafeClipboard:
            return "Буфер обмена содержит пароль, файлы или слишком много данных и не может быть восстановлен без потерь. Буфер не тронут; можно прочитать область экрана."
        case .nothingCopied: return "Нет выделенного текста (копирование ничего не дало)"
        case .notText: return "Скопирован не текст. Буфер обмена восстановлен."
        case .changedApplication: return "Активное приложение изменилось: чтение отменено. Буфер обмена восстановлен."
        case .tooLong: return "Выделение длиннее 60 000 символов UTF-16. Буфер обмена восстановлен."
        }
    }
}

struct ClipboardEntry: Equatable {
    let type: String
    let data: Data
}

protocol ClipboardStore: AnyObject {
    var changeCount: Int { get }
    /// Types of every item currently on the clipboard, in order.
    func itemTypes() -> [[String]]
    func data(itemIndex: Int, type: String) -> Data?
    func plainText() -> String?
    /// Clears the clipboard and writes these items (none: leaves it empty).
    func replace(with items: [[ClipboardEntry]])
}

enum ClipboardSnapshotPolicy {
    static let byteLimit = 50 * 1024 * 1024

    /// Password managers mark secrets as concealed or transient and clear them by
    /// watching the change count; restoring would keep such a secret forever.
    /// File promises are produced on demand and cannot be restored at all.
    static func isRestorable(type: String) -> Bool {
        let lower = type.lowercased()
        if lower == "org.nspasteboard.concealedtype" || lower == "org.nspasteboard.transienttype" { return false }
        return !lower.contains("promise")
    }
}

struct CopyFallbackReader<Store: ClipboardStore> {
    let store: Store
    var limit = 60_000
    /// How long to wait for one copy command to change the clipboard.
    var copyTimeout: TimeInterval = 0.6
    var pollInterval: TimeInterval = 0.03
    let sleep: (TimeInterval) -> Void

    func snapshot() throws -> [[ClipboardEntry]] {
        var total = 0
        var items: [[ClipboardEntry]] = []
        for (index, types) in store.itemTypes().enumerated() {
            var entries: [ClipboardEntry] = []
            for type in types {
                guard ClipboardSnapshotPolicy.isRestorable(type: type),
                      let data = store.data(itemIndex: index, type: type) else {
                    throw CopyFallbackFailure.unsafeClipboard
                }
                total += data.count
                guard total <= ClipboardSnapshotPolicy.byteLimit else { throw CopyFallbackFailure.unsafeClipboard }
                entries.append(ClipboardEntry(type: type, data: data))
            }
            items.append(entries)
        }
        return items
    }

    /// Copy commands are tried in order. A command returns false when it could
    /// not be issued at all (for example, no Copy menu item was found).
    func read(attempts: [() -> Bool], isTargetFrontmost: () -> Bool) throws -> String {
        let saved = try snapshot()
        let before = store.changeCount
        var restored = false
        defer {
            // Error paths: if anything was copied, put the previous clipboard back.
            if !restored, store.changeCount != before { store.replace(with: saved) }
        }

        var changed = false
        for attempt in attempts {
            guard isTargetFrontmost() else { throw CopyFallbackFailure.changedApplication }
            guard attempt() else { continue }
            if waitForChange(from: before, timeout: copyTimeout) { changed = true; break }
        }
        guard changed else {
            // A slow application may still copy; give it a moment so the
            // cleanup above can restore the clipboard if it does.
            _ = waitForChange(from: before, timeout: 0.3)
            throw CopyFallbackFailure.nothingCopied
        }

        // Applications may write in several steps; wait until the count settles.
        var settled = store.changeCount
        var waited: TimeInterval = 0
        while waited < 0.3 {
            sleep(pollInterval); waited += pollInterval
            let now = store.changeCount
            if now == settled { break }
            settled = now
        }
        let text = store.plainText()
        if store.changeCount == settled { store.replace(with: saved) }
        // Otherwise something else wrote to the clipboard after the copy;
        // that newer content is kept rather than overwritten.
        restored = true

        guard isTargetFrontmost() else { throw CopyFallbackFailure.changedApplication }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CopyFallbackFailure.notText
        }
        guard text.utf16.count <= limit else { throw CopyFallbackFailure.tooLong }
        return text
    }

    private func waitForChange(from count: Int, timeout: TimeInterval) -> Bool {
        var waited: TimeInterval = 0
        while waited < timeout {
            if store.changeCount != count { return true }
            sleep(pollInterval); waited += pollInterval
        }
        return store.changeCount != count
    }
}

extension SelectionFailure {
    /// Failures after which a listed application may be asked to copy its
    /// selection. Secure input, permission, size and app-switch failures never are.
    var allowsCopyFallback: Bool {
        switch self {
        case .noFocus, .noSelection, .unsupported, .invalidResponse, .accessibility: return true
        default: return false
        }
    }
}
