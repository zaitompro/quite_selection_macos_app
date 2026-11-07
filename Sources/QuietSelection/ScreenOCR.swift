import Foundation
import Vision
import ScreenCaptureKit

enum ScreenReadingError: Error {
    case empty, unsupportedLanguage, tooLarge, cancelled, capture
    var message: String {
        switch self {
        case .empty: return "Текст на экране не найден"
        case .unsupportedLanguage: return "Выбранный язык не поддерживается распознаванием текста"
        case .tooLarge: return "Область слишком большая. Выделите меньший фрагмент."
        case .cancelled: return "Распознавание отменено"
        case .capture: return "Не удалось получить изображение области. Проверьте доступ к экрану."
        }
    }
}

enum RegionGeometry {
    static func selection(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect? {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        guard !rect.isNull, rect.width >= 8, rect.height >= 8 else { return nil }
        return rect
    }
    static func captureRect(local: CGRect, screen: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: screen.minX + local.minX, y: primaryTop - screen.minY - local.maxY,
               width: local.width, height: local.height)
    }
    static func validCapture(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width >= 8 && rect.height >= 8 && rect.width * rect.height <= 12_000_000
    }
}

enum RegionCapture {
    // Invoked only after the user finishes a rectangle and has granted access.
    // No window inventory, screen-wide image, audio, file URL, or saved snapshot.
    static func image(in rect: CGRect) async throws -> CGImage {
        guard RegionGeometry.validCapture(rect) else { throw ScreenReadingError.tooLarge }
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        configuration.fileURL = nil
        let output = try await SCScreenshotManager.captureScreenshot(rect: rect, configuration: configuration)
        guard let image = output.sdrImage else { throw ScreenReadingError.capture }
        return image
    }
}

final class OCRJob: @unchecked Sendable {
    private let request = VNRecognizeTextRequest()
    private let lock = NSLock()
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        request.cancel()
    }
    private func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw ScreenReadingError.cancelled }
    }
    func recognize(_ image: CGImage, languages: [String]) throws -> String {
        let lines = try observations(image, languages: languages).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ScreenReadingError.empty }
        guard text.utf16.count <= 60_000 else { throw SelectionFailure.tooLong }
        return text
    }

    /// Recognised lines placed in global screen coordinates (top-left origin) of `rect`.
    func recognizeLines(_ image: CGImage, languages: [String], in rect: CGRect) throws -> [OCRLine] {
        try observations(image, languages: languages).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            let frame = CGRect(x: rect.minX + box.minX * rect.width,
                               y: rect.minY + (1 - box.maxY) * rect.height,
                               width: box.width * rect.width, height: box.height * rect.height)
            return OCRLine(text: text, frame: frame)
        }
    }

    private func observations(_ image: CGImage, languages: [String]) throws -> [VNRecognizedTextObservation] {
        try checkCancellation()
        guard image.width > 0, image.height > 0,
              Double(image.width) * Double(image.height) <= 48_000_000 else { throw ScreenReadingError.tooLarge }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        let resolved = languages.compactMap { code in
            supported.first(where: { $0 == code }) ?? supported.first(where: {
                $0.split(separator: "-").first.map(String.init) == code
            })
        }
        guard !resolved.isEmpty else { throw ScreenReadingError.unsupportedLanguage }
        request.recognitionLanguages = resolved
        request.automaticallyDetectsLanguage = resolved.count > 1
        // No compute-device override: Vision chooses supported local hardware.
        try checkCancellation()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try checkCancellation()
        return request.results ?? []
    }
}
