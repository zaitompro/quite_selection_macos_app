import Foundation

enum TranslationReadiness: Equatable {
    case checking, preparing, installed, supported, unsupported
    var title: String {
        switch self {
        case .checking: return "Проверка…"
        case .preparing: return "Ожидание готовности языков…"
        case .installed: return "Готов к переводу без интернета"
        case .supported: return "Языки ещё не готовы к переводу"
        case .unsupported: return "Эта пара языков не поддерживается macOS"
        }
    }
}

enum TranslationPreparationState: Equatable {
    case requesting, waiting, ready, notReady, cancelled, failed(Int)
    var canRetry: Bool {
        switch self { case .notReady, .failed: return true; default: return false }
    }
    var message: String {
        switch self {
        case .requesting: return "Ожидание системного запроса на загрузку языков…"
        case .waiting: return "Ожидание завершения подготовки языков. Готовность проверяется автоматически."
        case .ready: return "Языки готовы. Можно закрыть это окно."
        case .notReady: return "macOS пока не подтвердила готовность языков. Проверьте подключение к интернету и повторите запрос."
        case .cancelled: return "Проверка подготовки отменена."
        case .failed(let code): return "Подготовка не завершена. Можно повторить запрос. Код: \(code)"
        }
    }
}

enum TranslationPreparationMonitor {
    // prepareTranslation() grants download permission; returning is not proof
    // that downloads completed. Only a read-only ready check can finish this step.
    @MainActor
    static func run(prepare: () async throws -> Void, isReady: () async -> Bool,
                    wait: () async throws -> Void, attempts: Int? = nil,
                    update: (TranslationPreparationState) -> Void) async throws {
        try Task.checkCancellation()
        update(.requesting)
        try await prepare()
        try Task.checkCancellation()
        update(.waiting)
        var index = 0
        while attempts == nil || index < attempts! {
            try Task.checkCancellation()
            let ready = await isReady()
            try Task.checkCancellation()
            if ready { update(.ready); return }
            index += 1
            if attempts == nil || index < attempts! { try await wait() }
        }
        update(.notReady)
    }
}

enum TranslationFailure: Error { case unavailable(String), unsupported(String), undetermined }

enum TranslationPlan {
    struct Part: Equatable {
        let text: String
        let source: String?
    }
    static func parts(_ text: String, allowed: [String], target: String) -> [Part] {
        LanguagePlan.parts(text, allowed: allowed, fallback: "").map {
            // Whitespace and numbers need no language model.
            let hasLetters = $0.text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            return Part(text: $0.text, source: hasLetters ? ($0.language.isEmpty ? nil : $0.language) : target)
        }
    }
    static func resolving(_ parts: [Part], with language: String) -> [Part] {
        parts.map { Part(text: $0.text, source: $0.source ?? language) }
    }
}

@MainActor
protocol TranslationBackend {
    func readiness(source: String, target: String) async -> TranslationReadiness
    func translate(_ text: String, source: String, target: String) async throws -> String
}

enum TranslationPipeline {
    @MainActor
    static func run(_ parts: [TranslationPlan.Part], target: String,
                    backend: any TranslationBackend) async throws -> String {
        guard parts.allSatisfy({ $0.source != nil }) else { throw TranslationFailure.undetermined }
        let sources = Set(parts.compactMap(\.source)).subtracting([target]).sorted()
        // Validate all pairs first. Never start reading a partial translation.
        for source in sources {
            try Task.checkCancellation()
            switch await backend.readiness(source: source, target: target) {
            case .installed: break
            case .unsupported: throw TranslationFailure.unsupported(source)
            default: throw TranslationFailure.unavailable(source)
            }
        }
        var output = ""
        for part in parts {
            try Task.checkCancellation()
            if part.source == target { output += part.text; continue }
            // Keep original boundary whitespace even if the model trims it.
            let leading = String(part.text.prefix(while: { $0.isWhitespace }))
            let trailing = String(part.text.reversed().prefix(while: { $0.isWhitespace }).reversed())
            let translated = try await backend.translate(part.text.trimmingCharacters(in: .whitespacesAndNewlines),
                source: part.source!, target: target)
            output += leading + translated.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
        }
        try Task.checkCancellation()
        return output
    }
}
