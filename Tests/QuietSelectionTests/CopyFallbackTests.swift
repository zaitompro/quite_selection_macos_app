import Foundation

// Synthetic clipboard only: no real pasteboard, application or keystroke is used.
final class FakeClipboard: ClipboardStore {
    var items: [[ClipboardEntry]]
    var changeCount = 100
    var missing: Set<String> = []
    var replaced: [[[ClipboardEntry]]] = []
    init(_ items: [[ClipboardEntry]]) { self.items = items }

    func itemTypes() -> [[String]] { items.map { $0.map(\.type) } }
    func data(itemIndex: Int, type: String) -> Data? {
        guard !missing.contains(type) else { return nil }
        return items[itemIndex].first { $0.type == type }?.data
    }
    func plainText() -> String? {
        items.first?.first { $0.type == "public.utf8-plain-text" }.flatMap { String(data: $0.data, encoding: .utf8) }
    }
    func replace(with saved: [[ClipboardEntry]]) {
        items = saved; changeCount += 1; replaced.append(saved)
    }
    /// What an application does when it copies text: one or more writes.
    func copy(_ text: String, writes: Int = 1) {
        items = [[ClipboardEntry(type: "public.utf8-plain-text", data: Data(text.utf8))]]
        changeCount += writes
    }
}

func entry(_ type: String, _ text: String) -> ClipboardEntry { ClipboardEntry(type: type, data: Data(text.utf8)) }

@main struct Tests {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { print("FAIL: \(name)"); exit(1) }
        count += 1
        print("PASS: \(name)")
    }
    static func reader(_ board: FakeClipboard) -> CopyFallbackReader<FakeClipboard> {
        CopyFallbackReader(store: board) { _ in }
    }
    static func failure(_ body: () throws -> String) -> CopyFallbackFailure? {
        do { _ = try body(); return nil } catch { return error as? CopyFallbackFailure }
    }
    static let original: [[ClipboardEntry]] = [
        [entry("public.utf8-plain-text", "Мой буфер"), entry("public.rtf", "{\\rtf1 Мой буфер}")],
        [entry("public.png", "PNGDATA")]
    ]

    static func main() {
        // Success: text returned, every item and type of the old clipboard restored.
        let board = FakeClipboard(original)
        let text = try? reader(board).read(attempts: [{ board.copy("Выделенный текст"); return true }],
                                           isTargetFrontmost: { true })
        check(text == "Выделенный текст", "copied selection returned")
        check(board.items == original && board.replaced.count == 1, "all items and types restored once")

        // Several writes by the application are waited for before reading.
        let multi = FakeClipboard(original)
        let multiText = try? reader(multi).read(attempts: [{ multi.copy("Текст", writes: 2); return true }],
                                                isTargetFrontmost: { true })
        check(multiText == "Текст" && multi.items == original, "multi-step copy restored")

        // Empty clipboard stays empty afterwards.
        let empty = FakeClipboard([])
        _ = try? reader(empty).read(attempts: [{ empty.copy("Текст"); return true }], isTargetFrontmost: { true })
        check(empty.items.isEmpty, "empty clipboard restored as empty")

        // Unrestorable clipboard: nothing is copied at all.
        for (name, items) in [
            ("concealed password", [[entry("public.utf8-plain-text", "secret"), entry("org.nspasteboard.ConcealedType", "")]]),
            ("transient data", [[entry("org.nspasteboard.TransientType", "")]]),
            ("file promise", [[entry("com.apple.pasteboard.promised-file-url", "x")]])
        ] {
            let guarded = FakeClipboard(items)
            var copied = false
            let error = failure { try reader(guarded).read(attempts: [{ copied = true; return true }], isTargetFrontmost: { true }) }
            check(error == .unsafeClipboard && !copied && guarded.replaced.isEmpty && guarded.items == items,
                  "\(name): clipboard untouched, no copy")
        }
        let unreadable = FakeClipboard(original); unreadable.missing = ["public.png"]
        var unreadableCopied = false
        check(failure { try reader(unreadable).read(attempts: [{ unreadableCopied = true; return true }], isTargetFrontmost: { true }) } == .unsafeClipboard
              && !unreadableCopied, "unreadable type: clipboard untouched")
        let huge = FakeClipboard([[ClipboardEntry(type: "public.tiff", data: Data(count: ClipboardSnapshotPolicy.byteLimit + 1))]])
        check(failure { try reader(huge).read(attempts: [{ true }], isTargetFrontmost: { true }) } == .unsafeClipboard,
              "oversized clipboard refused")

        // Nothing copied: clipboard not rewritten.
        let nothing = FakeClipboard(original)
        check(failure { try reader(nothing).read(attempts: [{ true }], isTargetFrontmost: { true }) } == .nothingCopied
              && nothing.replaced.isEmpty, "nothing copied, nothing restored")

        // First method unavailable or ineffective: the second is used.
        let second = FakeClipboard(original)
        var order: [String] = []
        let secondText = try? reader(second).read(attempts: [
            { order.append("menu"); return false },
            { order.append("keys"); second.copy("Через клавиши"); return true }
        ], isTargetFrontmost: { true })
        check(secondText == "Через клавиши" && order == ["menu", "keys"] && second.items == original, "falls back to ⌘C")
        let ineffective = FakeClipboard(original)
        order = []
        _ = try? reader(ineffective).read(attempts: [
            { order.append("menu"); return true },
            { order.append("keys"); ineffective.copy("Текст"); return true }
        ], isTargetFrontmost: { true })
        check(order == ["menu", "keys"] && ineffective.items == original, "menu without effect, then ⌘C")
        let firstWins = FakeClipboard(original)
        order = []
        _ = try? reader(firstWins).read(attempts: [
            { order.append("menu"); firstWins.copy("Меню"); return true },
            { order.append("keys"); return true }
        ], isTargetFrontmost: { true })
        check(order == ["menu"], "no second copy after success")

        // Error paths after copying still restore the clipboard.
        let notText = FakeClipboard(original)
        check(failure { try reader(notText).read(attempts: [{
            notText.items = [[entry("public.png", "IMG")]]; notText.changeCount += 1; return true
        }], isTargetFrontmost: { true }) } == .notText && notText.items == original, "non-text copy restored")
        let blank = FakeClipboard(original)
        check(failure { try reader(blank).read(attempts: [{ blank.copy(" \n"); return true }], isTargetFrontmost: { true }) } == .notText
              && blank.items == original, "whitespace copy restored")
        let long = FakeClipboard(original)
        check(failure { try reader(long).read(attempts: [{ long.copy(String(repeating: "x", count: 60_001)); return true }],
                                               isTargetFrontmost: { true }) } == .tooLong && long.items == original, "oversize copy restored")
        let switched = FakeClipboard(original)
        var front = true
        check(failure { try reader(switched).read(attempts: [{ switched.copy("Текст"); front = false; return true }],
                                                   isTargetFrontmost: { front }) } == .changedApplication
              && switched.items == original, "app switch after copy restored")
        let before = FakeClipboard(original)
        var beforeCopied = false
        check(failure { try reader(before).read(attempts: [{ beforeCopied = true; return true }], isTargetFrontmost: { false }) } == .changedApplication
              && !beforeCopied && before.replaced.isEmpty, "app switch before copy: nothing copied")

        // Late copy after the wait is still restored.
        let late = FakeClipboard(original)
        var polls = 0
        let slow = CopyFallbackReader(store: late, copyTimeout: 0.06, pollInterval: 0.03) { _ in
            polls += 1
            if polls == 3 { late.copy("Поздно") }
        }
        check((try? slow.read(attempts: [{ true }], isTargetFrontmost: { true })) == nil && late.items == original,
              "late copy restored")

        // Something else writes after the copy: newer content is kept.
        let raced = FakeClipboard(original)
        let racing = RacingClipboard(raced)
        _ = try? CopyFallbackReader(store: racing) { _ in }.read(attempts: [{ raced.copy("Текст"); return true }],
                                                                 isTargetFrontmost: { true })
        check(raced.items == [[entry("public.utf8-plain-text", "Новое от пользователя")]] && raced.replaced.isEmpty,
              "newer clipboard content not overwritten")

        // Policy for which selection failures may use the copy fallback.
        check([SelectionFailure.noSelection, .unsupported, .noFocus, .invalidResponse, .accessibility(-25204)]
              .allSatisfy(\.allowsCopyFallback), "selection gaps allow copy fallback")
        check(![SelectionFailure.secureInput, .secureKeyboard, .permission, .tooLong, .changedApplication, .busy]
              .contains(where: \.allowsCopyFallback), "secure, permission, size and app-switch failures never copy")
        print("\(count) checks passed; synthetic clipboard only.")
    }
}

/// Simulates another program writing right after the copied text is read.
final class RacingClipboard: ClipboardStore {
    let base: FakeClipboard
    init(_ base: FakeClipboard) { self.base = base }
    var changeCount: Int { base.changeCount }
    func itemTypes() -> [[String]] { base.itemTypes() }
    func data(itemIndex: Int, type: String) -> Data? { base.data(itemIndex: itemIndex, type: type) }
    func plainText() -> String? {
        let text = base.plainText()
        base.items = [[entry("public.utf8-plain-text", "Новое от пользователя")]]
        base.changeCount += 1
        return text
    }
    func replace(with saved: [[ClipboardEntry]]) { base.replace(with: saved) }
}
