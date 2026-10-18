import Foundation
import NaturalLanguage

enum LanguagePlan {
    struct Part { let text: String; let language: String }

    static func language(for text: String, allowed: [String], fallback: String) -> String? {
        guard !allowed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        var mapping: [NLLanguage: String] = [:]
        for code in allowed {
            let languages: [NLLanguage] = code == "zh" ? [.simplifiedChinese, .traditionalChinese]
                : code == "nb" ? [.norwegian] : [NLLanguage(rawValue: code)]
            for language in languages { mapping[language] = code }
        }
        recognizer.languageConstraints = Array(mapping.keys)
        recognizer.processString(String(text.prefix(4_000)))
        var scores: [String: Double] = [:]
        for (key, value) in recognizer.languageHypotheses(withMaximum: max(2, mapping.count)) {
            if let code = mapping[key] { scores[code, default: 0] += value }
        }
        return preferredLanguage(scores: scores, allowed: allowed, fallback: fallback)
    }

    static func preferredLanguage(scores: [String: Double], allowed: [String], fallback: String) -> String {
        let candidates = scores.filter { allowed.contains($0.key) }.sorted { $0.value > $1.value }
        // Confidence is a heuristic, not a guarantee. Ambiguous snippets use
        // the explicitly configured fallback instead of a random allowed voice.
        if let best = candidates.first, best.value >= 0.65,
           best.value - (candidates.dropFirst().first?.value ?? 0) >= 0.15 {
            return best.key
        }
        return fallback
    }

    static func parts(_ text: String, allowed: [String], fallback: String) -> [Part] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [Part] = []
        var start = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // Preserve punctuation and whitespace between tokens.
            let fragment = String(text[start..<range.upperBound])
            if let code = language(for: fragment, allowed: allowed, fallback: fallback) {
                result.append(Part(text: fragment, language: code))
            }
            start = range.upperBound
            return true
        }
        if start < text.endIndex {
            let fragment = String(text[start...])
            if let code = language(for: fragment, allowed: allowed, fallback: fallback) {
                result.append(Part(text: fragment, language: code))
            }
        }
        return result
    }
}
