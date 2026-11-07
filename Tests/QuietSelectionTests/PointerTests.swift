import Foundation

// Rules for reading under the pointer only: no pointer, screen or application is used.
@main struct Tests {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { print("FAIL: \(name)"); exit(1) }
        count += 1
        print("PASS: \(name)")
    }
    static func main() {
        let selection = CGRect(x: 100, y: 200, width: 300, height: 40)
        check(PointerPolicy.readsSelection(selectionBounds: selection, pointer: CGPoint(x: 150, y: 220)), "pointer over selection")
        check(PointerPolicy.readsSelection(selectionBounds: selection, pointer: CGPoint(x: 95, y: 245)), "pointer just beside selection")
        check(!PointerPolicy.readsSelection(selectionBounds: selection, pointer: CGPoint(x: 150, y: 400)), "pointer elsewhere")
        check(PointerPolicy.readsSelection(selectionBounds: nil, pointer: CGPoint(x: 0, y: 0)), "unknown bounds: selection as before")
        check(PointerPolicy.readsSelection(selectionBounds: .null, pointer: CGPoint(x: 0, y: 0)), "null bounds: selection as before")

        let text = "Первый абзац.\nВторой абзац, длинный 🧪 текст.\n\nТретий."
        let second = (text as NSString).range(of: "длинный").location
        check(PointerPolicy.paragraph(in: text, aroundUTF16: second) == "Второй абзац, длинный 🧪 текст.", "middle paragraph")
        check(PointerPolicy.paragraph(in: text, aroundUTF16: 0) == "Первый абзац.", "first paragraph")
        check(PointerPolicy.paragraph(in: text, aroundUTF16: (text as NSString).length - 1) == "Третий.", "last paragraph")
        let breakAt = (text as NSString).range(of: "\n").location
        check(PointerPolicy.paragraph(in: text, aroundUTF16: breakAt) == "Первый абзац.", "pointer on line break: paragraph before")
        let blank = (text as NSString).range(of: "\n\n").location + 1
        check(PointerPolicy.paragraph(in: text, aroundUTF16: blank) == "Второй абзац, длинный 🧪 текст.", "empty line: previous paragraph")
        check(PointerPolicy.paragraph(in: "Строка\u{2029}Другая", aroundUTF16: 8) == "Другая", "paragraph separator")
        check(PointerPolicy.paragraph(in: "One\r\nTwo", aroundUTF16: 6) == "Two", "CRLF breaks")
        check(PointerPolicy.paragraph(in: "   \n  ", aroundUTF16: 1) == nil, "whitespace only: nothing")
        check(PointerPolicy.paragraph(in: "", aroundUTF16: 0) == nil, "empty text: nothing")
        check(PointerPolicy.paragraph(in: "abc", aroundUTF16: 99) == "abc", "offset past end clamps")

        check(PointerPolicy.window(around: 10, total: 100) == TextRange(location: 0, length: 100), "small text: whole window")
        check(PointerPolicy.window(around: 50_000, total: 100_000) == TextRange(location: 46_000, length: 8_000), "large text: bounded window")
        check(PointerPolicy.window(around: 200, total: 100)?.location == 0, "index past end clamps")
        check(PointerPolicy.window(around: 0, total: 0) == nil && PointerPolicy.window(around: -1, total: 10) == nil, "invalid window")

        check(PointerPolicy.validated("  Текст \n") == "Текст", "trimmed")
        check(PointerPolicy.validated(" \n") == nil && PointerPolicy.validated(nil) == nil, "empty rejected")
        check(PointerPolicy.validated(String(repeating: "x", count: 5), limit: 4) == nil, "over limit rejected")
        check(!SelectionFailure.nothingUnderPointer.message.isEmpty, "failure message exists")
        // Choosing between the selection and the paragraph under the pointer.
        let inside = CGPoint(x: 150, y: 220), outside = CGPoint(x: 150, y: 600)
        check(PointerPolicy.choose(selection: "Выделено", selectionBounds: selection, pointer: inside, pointerParagraph: nil) == .selection,
              "known bounds, pointer inside: selection")
        check(PointerPolicy.choose(selection: "Выделено", selectionBounds: selection, pointer: outside, pointerParagraph: "Другой абзац") == .pointer,
              "known bounds, pointer elsewhere: paragraph")
        check(PointerPolicy.choose(selection: "Выделено", selectionBounds: selection, pointer: outside, pointerParagraph: nil) == .nothing,
              "known bounds, nothing under pointer: failure")
        check(PointerPolicy.choose(selection: "часть второго абзаца", selectionBounds: nil, pointer: outside,
                                   pointerParagraph: "Это часть второго абзаца целиком.") == .selection,
              "unknown bounds, pointer on the selected paragraph: selection")
        check(PointerPolicy.choose(selection: "Выделенный текст первого абзаца", selectionBounds: nil, pointer: outside,
                                   pointerParagraph: "Совсем другой абзац ниже.") == .pointer,
              "unknown bounds, other paragraph: paragraph (Electron)")
        check(PointerPolicy.choose(selection: "Выделено", selectionBounds: nil, pointer: outside, pointerParagraph: nil) == .selection,
              "unknown bounds, nothing under pointer: selection")
        check(PointerPolicy.choose(selection: nil, selectionBounds: nil, pointer: outside, pointerParagraph: "Абзац") == .pointer,
              "no selection: paragraph")
        check(PointerPolicy.choose(selection: nil, selectionBounds: nil, pointer: outside, pointerParagraph: nil) == .nothing,
              "no selection, nothing under pointer: failure")
        check(PointerPolicy.overlaps("Первая строка выделения\nВторая строка выделения", "Абзац: вторая  строка ВЫДЕЛЕНИЯ и ещё"),
              "multi-paragraph selection matches one of its paragraphs, ignoring case and spaces")
        check(PointerPolicy.overlaps("да", "Где-то да, а где-то нет"), "short selection inside the paragraph counts")
        check(!PointerPolicy.overlaps("Короткая строка\nещё", "Ничего общего здесь нет"), "no shared text")
        print("\(count) checks passed; no pointer, screen or application used.")
    }
}
