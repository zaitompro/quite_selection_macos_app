import Foundation

struct VoiceChoice: Equatable {
    let id: String
    let name: String
    let tag: String
    let quality: Int
    var language: String { tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? tag }
    var title: String {
        let region = Locale(identifier: tag).region?.identifier
        let place = region.flatMap { Self.russian.localizedString(forRegionCode: $0) }
        let level = quality >= 3 ? "Премиум" : quality == 2 ? "Улучшенный" : "Стандартный"
        return [name, place, level].compactMap { $0 }.joined(separator: " · ")
    }
    static let russian = Locale(identifier: "ru_RU")
    static func languageTitle(_ code: String) -> String {
        let title = russian.localizedString(forLanguageCode: code) ?? code
        return title.prefix(1).uppercased(with: russian) + title.dropFirst()
    }
}

struct VoiceSettings {
    var language: String
    var voicesByLanguage: [String: String]
    var ratesByLanguage: [String: Float]
    private(set) var additionalLanguages: [String: Bool]
    let initialRate: Float

    static func validRate(_ value: Float) -> Float {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }
    func rate(for code: String) -> Float { Self.validRate(ratesByLanguage[code] ?? initialRate) }
    var allowedLanguages: [String] {
        [language] + additionalLanguages.keys.filter { additionalLanguages[$0] == true && $0 != language }.sorted()
    }
    mutating func setPrimaryLanguage(_ code: String, voices: [VoiceChoice]) {
        let previous = language
        if previous != code { additionalLanguages[previous] = true }
        additionalLanguages.removeValue(forKey: code)
        selectLanguage(code, voices: voices)
    }
    mutating func addLanguage(_ code: String, voices: [VoiceChoice]) {
        guard code != language, additionalLanguages[code] == nil else { return }
        additionalLanguages[code] = true
        if voicesByLanguage[code] == nil { voicesByLanguage[code] = Self.choices(for: code, in: voices).first?.id }
        if ratesByLanguage[code] == nil { ratesByLanguage[code] = initialRate }
    }
    mutating func setEnabled(_ enabled: Bool, for code: String) {
        guard code != language, additionalLanguages[code] != nil else { return }
        additionalLanguages[code] = enabled
    }
    mutating func removeLanguage(_ code: String) {
        additionalLanguages.removeValue(forKey: code)
        // Keep voice and speed so adding this language again restores them.
    }

    static func languages(in voices: [VoiceChoice]) -> [String] {
        Set(voices.map(\.language)).sorted {
            VoiceChoice.languageTitle($0).compare(VoiceChoice.languageTitle($1),
                options: [.caseInsensitive], locale: VoiceChoice.russian) == .orderedAscending
        }
    }

    static func choices(for language: String, in voices: [VoiceChoice]) -> [VoiceChoice] {
        voices.filter { $0.language == language }.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            let order = $0.title.compare($1.title, options: [.caseInsensitive], locale: VoiceChoice.russian)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    init(language: String?, saved: [String: String], legacyID: String?, voices: [VoiceChoice],
         rates: [String: Float] = [:], legacyRate: Float = 0.5,
         additional: [String: Bool]? = nil, legacyAllowed: [String] = ["ru", "en", "ja"]) {
        initialRate = Self.validRate(legacyRate)
        ratesByLanguage = rates.mapValues(Self.validRate)
        additionalLanguages = additional ?? Dictionary(legacyAllowed.map { ($0, true) }, uniquingKeysWith: { first, _ in first })
        voicesByLanguage = saved
        if let legacyID, let old = voices.first(where: { $0.id == legacyID }), saved[old.language] == nil {
            voicesByLanguage[old.language] = old.id
        }
        self.language = language ?? voices.first(where: { $0.id == legacyID })?.language
            ?? (voices.contains { $0.language == "ru" } ? "ru" : Self.languages(in: voices).first ?? "ru")
        additionalLanguages.removeValue(forKey: self.language)
        for code in additionalLanguages.keys {
            if voicesByLanguage[code] == nil { voicesByLanguage[code] = Self.choices(for: code, in: voices).first?.id }
            if ratesByLanguage[code] == nil { ratesByLanguage[code] = initialRate }
        }
        selectLanguage(self.language, voices: voices)
    }

    mutating func selectLanguage(_ code: String, voices: [VoiceChoice]) {
        language = code
        if ratesByLanguage[code] == nil { ratesByLanguage[code] = initialRate }
        // Only initialise a new language. A missing saved voice is never replaced.
        if voicesByLanguage[code] == nil {
            voicesByLanguage[code] = Self.choices(for: code, in: voices).first?.id
        }
    }

    func selectedVoice(in voices: [VoiceChoice]) -> VoiceChoice? {
        guard let id = voicesByLanguage[language] else { return nil }
        return voices.first { $0.id == id && $0.language == language }
    }
}
