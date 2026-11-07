import Foundation
import CoreGraphics

// Platform-free: finds the recognised paragraph under the pointer and decides
// whether the snapshot should grow. Rectangles are global screen points with
// the origin at the top left.

struct OCRLine: Equatable {
    let text: String
    let frame: CGRect
}

enum OCRParagraph {
    struct Edges: OptionSet, Equatable {
        let rawValue: Int
        static let top = Edges(rawValue: 1), bottom = Edges(rawValue: 2)
        static let left = Edges(rawValue: 4), right = Edges(rawValue: 8)
    }

    struct Result: Equatable {
        let text: String
        let frame: CGRect
        /// Snapshot edges the paragraph touches: text may continue beyond them.
        let edges: Edges
    }

    /// Initial snapshot around the pointer, before limiting to the element under it.
    static let initialSize = CGSize(width: 900, height: 300)
    static let edgeMargin: CGFloat = 6
    static let maxExpansions = 2

    static func initialCapture(around pointer: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: pointer.x - initialSize.width / 2, y: pointer.y - initialSize.height / 2,
               width: initialSize.width, height: initialSize.height).intersection(bounds)
    }

    static func paragraph(lines: [OCRLine], pointer: CGPoint, capture: CGRect) -> Result? {
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.frame.height > 0 }
        guard let seed = seedLine(usable, pointer: pointer) else { return nil }
        let height = seed.frame.height
        var members = [seed]
        var frame = seed.frame
        var remaining = usable.filter { $0 != seed }
        while let next = remaining.filter({ belongs($0, to: frame, lineHeight: height) })
                .min(by: { distance($0.frame, frame) < distance($1.frame, frame) }) {
            members.append(next)
            frame = frame.union(next.frame)
            remaining.removeAll { $0 == next }
        }
        let ordered = rows(members).map { $0.map(\.text).joined(separator: " ") }
        let text = joined(ordered)
        guard !text.isEmpty else { return nil }
        var edges: Edges = []
        if frame.minY - capture.minY < edgeMargin { edges.insert(.top) }
        if capture.maxY - frame.maxY < edgeMargin { edges.insert(.bottom) }
        if frame.minX - capture.minX < edgeMargin { edges.insert(.left) }
        if capture.maxX - frame.maxX < edgeMargin { edges.insert(.right) }
        return Result(text: text, frame: frame, edges: edges)
    }

    /// Grows the snapshot toward the touched edges, staying inside `bounds`.
    static func expanded(_ capture: CGRect, toward edges: Edges, within bounds: CGRect) -> CGRect {
        var rect = capture
        if edges.contains(.top) { rect.origin.y -= capture.height; rect.size.height += capture.height }
        if edges.contains(.bottom) { rect.size.height += capture.height }
        if edges.contains(.left) { rect.origin.x -= capture.width / 2; rect.size.width += capture.width / 2 }
        if edges.contains(.right) { rect.size.width += capture.width / 2 }
        return rect.intersection(bounds)
    }

    /// Line texts in reading order; a hyphen at a line end followed by a
    /// lowercase letter joins the word.
    static func joined(_ lines: [String]) -> String {
        var result = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let last = result.last, last == "-" || last == "\u{2010}",
               let first = line.first, first.isLowercase {
                result.removeLast()
                result += line
            } else {
                result += result.isEmpty ? line : " " + line
            }
        }
        return result
    }

    // MARK: Private

    private static func seedLine(_ lines: [OCRLine], pointer: CGPoint) -> OCRLine? {
        let hits = lines.filter {
            $0.frame.insetBy(dx: -4, dy: -$0.frame.height / 2).contains(pointer)
        }
        if let hit = hits.min(by: { centerDistance($0.frame, pointer) < centerDistance($1.frame, pointer) }) {
            return hit
        }
        // Pointer between lines or just beside the text: the nearest close line.
        return lines.filter {
            let dy = max($0.frame.minY - pointer.y, pointer.y - $0.frame.maxY, 0)
            let dx = max($0.frame.minX - pointer.x, pointer.x - $0.frame.maxX, 0)
            return dy <= $0.frame.height * 1.5 && dx <= 40
        }.min(by: { centerDistance($0.frame, pointer) < centerDistance($1.frame, pointer) })
    }

    private static func belongs(_ line: OCRLine, to frame: CGRect, lineHeight: CGFloat) -> Bool {
        let ratio = line.frame.height / lineHeight
        guard ratio >= 0.6, ratio <= 1.6 else { return false }
        let verticalOverlap = min(line.frame.maxY, frame.maxY) - max(line.frame.minY, frame.minY)
        if verticalOverlap > line.frame.height * 0.5 {
            // Same row split into pieces by recognition: close horizontally.
            let gap = max(line.frame.minX - frame.maxX, frame.minX - line.frame.maxX)
            return gap <= lineHeight * 1.5
        }
        let horizontalOverlap = min(line.frame.maxX, frame.maxX) - max(line.frame.minX, frame.minX)
        guard horizontalOverlap >= 0.3 * min(line.frame.width, frame.width) else { return false }
        let gap = line.frame.midY < frame.midY ? frame.minY - line.frame.maxY : line.frame.minY - frame.maxY
        return gap <= lineHeight * 0.9
    }

    private static func rows(_ lines: [OCRLine]) -> [[OCRLine]] {
        var rows: [[OCRLine]] = []
        for line in lines.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let index = rows.indices.last, let reference = rows[index].first,
               abs(reference.frame.midY - line.frame.midY) < reference.frame.height * 0.5 {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(a.minX - b.maxX, b.minX - a.maxX, 0)
        let dy = max(a.minY - b.maxY, b.minY - a.maxY, 0)
        return dx + dy
    }

    private static func centerDistance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(rect.midX - point.x, rect.midY - point.y)
    }
}
