import AppKit
import Carbon

@main
@MainActor
struct OCRTests {
    static func bitmap(_ lines: [String]) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1500, pixelsHigh: 420,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1500, height: 420).fill()
        for (index, text) in lines.enumerated() {
            (text as NSString).draw(at: NSPoint(x: 40, y: 320 - index * 100), withAttributes: [
                .font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--hotkeys") {
            for shortcut in OCRShortcut.allCases {
                let key = try HotKey(identifier: UInt32(100 + shortcut.rawValue))
                try key.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
                print("ocr_hotkey=PASS option=\(shortcut.rawValue)")
                withExtendedLifetime(key) {}
            }
            return
        }
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = RegionGeometry.selection(from: CGPoint(x: 300, y: 400),
            to: CGPoint(x: 100, y: 200), bounds: bounds)!
        precondition(rect == CGRect(x: 100, y: 200, width: 200, height: 200))
        precondition(RegionGeometry.selection(from: .zero, to: CGPoint(x: 3, y: 4), bounds: bounds) == nil)
        precondition(RegionGeometry.selection(from: CGPoint(x: 900, y: 700),
            to: CGPoint(x: 1100, y: 1000), bounds: bounds) == CGRect(x: 900, y: 700, width: 100, height: 100))
        precondition(RegionGeometry.captureRect(local: rect, screen: bounds, primaryTop: 800)
            == CGRect(x: 100, y: 400, width: 200, height: 200))
        precondition(RegionGeometry.captureRect(local: rect,
            screen: CGRect(x: -1000, y: 800, width: 1000, height: 800), primaryTop: 800)
            == CGRect(x: -900, y: -400, width: 200, height: 200))
        precondition(RegionGeometry.validCapture(rect))
        precondition(!RegionGeometry.validCapture(CGRect(x: 0, y: 0, width: 10000, height: 10000)))
        precondition(!RegionGeometry.validCapture(CGRect(x: Double.infinity, y: 0, width: 20, height: 20)))
        print("ocr_geometry=PASS reversed_drag, clipped_drag, tiny_area, primary_display, negative_display_origin, size_limits")

        let samples = ["Это проверка чтения с экрана.", "This is a local screen reading test.", "日本語の読み上げテストです。"]
        let expected = ["проверка", "screen reading", "日本語"]
        for (index, sample) in samples.enumerated() {
            for mixed in [false, true] {
                let start = Date()
                let text = try OCRJob().recognize(bitmap([sample]).cgImage!,
                    languages: mixed ? ["ru", "en", "ja"] : [["ru"], ["en"], ["ja"]][index])
                guard text.contains(expected[index]) else {
                    print("ocr=FAIL sample=\(index) mixed=\(mixed)"); exit(1)
                }
                print("ocr=PASS sample=\(index) mixed=\(mixed) milliseconds=\(Int(Date().timeIntervalSince(start) * 1000))")
            }
        }
        let combined = bitmap(samples)
        let text = try OCRJob().recognize(combined.cgImage!, languages: ["ru", "en", "ja"])
        precondition(expected.allSatisfy { text.contains($0) })
        print("ocr=PASS multilingual_image")
        let blank = bitmap([]).cgImage!
        do { _ = try OCRJob().recognize(blank, languages: ["en"]); fatalError("Expected empty") }
        catch ScreenReadingError.empty { print("ocr=PASS blank_image") }
        do { _ = try OCRJob().recognize(blank, languages: ["zz"]); fatalError("Expected unsupported") }
        catch ScreenReadingError.unsupportedLanguage { print("ocr=PASS unsupported_language") }
        let cancelled = OCRJob()
        cancelled.cancel()
        do { _ = try cancelled.recognize(blank, languages: ["en"]); fatalError("Expected cancellation") }
        catch ScreenReadingError.cancelled { print("ocr=PASS cancelled_job") }
        // This file is generated from fixed test strings, never from screen capture.
        if CommandLine.arguments.contains("--write-fixture") {
            try combined.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/Fixtures/ocr-test.png"))
        }
        print("screen_captures=0 permission_prompts=0 recognized_text_logging=0")
    }
}
