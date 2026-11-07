import Foundation

// Synthetic recognised lines only: no screen capture or recognition.
@main struct Tests {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else { print("FAIL: \(name)"); exit(1) }
        count += 1
        print("PASS: \(name)")
    }
    static func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 400, height: CGFloat = 18) -> OCRLine {
        OCRLine(text: text, frame: CGRect(x: x, y: y, width: width, height: height))
    }
    static func main() {
        let capture = CGRect(x: 0, y: 0, width: 1000, height: 600)
        // Two paragraphs in the left column, one in the right column.
        let lines = [
            line("Первый абзац, первая строка с пере-", x: 50, y: 100),
            line("носом слова и продолжением.", x: 50, y: 122),
            line("Второй абзац начинается здесь", x: 50, y: 170),
            line("и заканчивается тут.", x: 50, y: 192, width: 200),
            line("Правая колонка рядом", x: 550, y: 100),
            line("её вторая строка", x: 550, y: 122)
        ]
        let first = OCRParagraph.paragraph(lines: lines, pointer: CGPoint(x: 200, y: 110), capture: capture)
        check(first?.text == "Первый абзац, первая строка с переносом слова и продолжением.", "paragraph with hyphenated word")
        let second = OCRParagraph.paragraph(lines: lines, pointer: CGPoint(x: 120, y: 200), capture: capture)
        check(second?.text == "Второй абзац начинается здесь и заканчивается тут.", "paragraph gap separates paragraphs")
        let right = OCRParagraph.paragraph(lines: lines, pointer: CGPoint(x: 600, y: 125), capture: capture)
        check(right?.text == "Правая колонка рядом её вторая строка", "other column not mixed in")
        check(first?.edges == [], "paragraph inside the snapshot: no growth")
        let between = OCRParagraph.paragraph(lines: lines, pointer: CGPoint(x: 200, y: 150), capture: capture)
        check(between != nil, "pointer between lines: nearest paragraph")
        check(OCRParagraph.paragraph(lines: lines, pointer: CGPoint(x: 200, y: 500), capture: capture) == nil, "no text near pointer")
        check(OCRParagraph.paragraph(lines: [], pointer: .zero, capture: capture) == nil, "no lines")

        // Pieces of one row are joined in order.
        let pieces = [line("конец", x: 260, y: 300, width: 80), line("Начало и", x: 100, y: 300, width: 140)]
        check(OCRParagraph.paragraph(lines: pieces, pointer: CGPoint(x: 120, y: 305), capture: capture)?.text == "Начало и конец",
              "row pieces joined left to right")
        // Much larger heading above is not part of the paragraph.
        let heading = [line("Заголовок", x: 50, y: 40, height: 40), line("Текст абзаца", x: 50, y: 88)]
        check(OCRParagraph.paragraph(lines: heading, pointer: CGPoint(x: 60, y: 95), capture: capture)?.text == "Текст абзаца",
              "different text size not merged")

        // Touching edges asks for growth in those directions.
        let cut = [line("обрезано сверху", x: 2, y: 2), line("и продолжается", x: 2, y: 24)]
        let edged = OCRParagraph.paragraph(lines: cut, pointer: CGPoint(x: 20, y: 30), capture: CGRect(x: 0, y: 0, width: 300, height: 44))
        check(edged?.edges.contains(.top) == true && edged?.edges.contains(.left) == true
              && edged?.edges.contains(.right) == true && edged?.edges.contains(.bottom) == true, "edges reported")
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let grown = OCRParagraph.expanded(CGRect(x: 400, y: 300, width: 200, height: 100), toward: [.top, .right], within: screen)
        check(grown == CGRect(x: 400, y: 200, width: 300, height: 200), "growth toward top and right")
        check(OCRParagraph.expanded(CGRect(x: 0, y: 0, width: 200, height: 100), toward: [.top, .left], within: screen)
              == CGRect(x: 0, y: 0, width: 200, height: 100), "growth stays on screen")
        check(OCRParagraph.initialCapture(around: CGPoint(x: 100, y: 100), within: screen) == CGRect(x: 0, y: 0, width: 550, height: 250),
              "initial snapshot clipped to bounds")

        check(OCRParagraph.joined(["Слово-", "Дальше"]) == "Слово- Дальше", "hyphen before capital kept")
        check(OCRParagraph.joined(["  ", "текст "]) == "текст", "empty lines skipped")
        print("\(count) checks passed; synthetic lines only.")
    }
}
