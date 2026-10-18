import Foundation
import NaturalLanguage

@main
struct VoiceSettingsTests {
    static func main() {
        let voices = [
            VoiceChoice(id: "ru-standard", name: "Русский", tag: "ru-RU", quality: 1),
            VoiceChoice(id: "ru-enhanced", name: "Русский", tag: "ru-RU", quality: 2),
            VoiceChoice(id: "en-us", name: "English", tag: "en-US", quality: 2),
            VoiceChoice(id: "en-gb", name: "English", tag: "en-GB", quality: 3),
            VoiceChoice(id: "ja", name: "Japanese", tag: "ja-JP", quality: 2)
        ]
        var selection = VoiceSettings(language: nil, saved: [:], legacyID: nil, voices: voices)
        precondition(selection.language == "ru")
        precondition(selection.selectedVoice(in: voices)?.id == "ru-enhanced")
        selection.voicesByLanguage["ru"] = "ru-standard"
        selection.selectLanguage("en", voices: voices)
        precondition(selection.selectedVoice(in: voices)?.id == "en-gb")
        selection.voicesByLanguage["en"] = "en-us"
        selection.selectLanguage("ru", voices: voices)
        precondition(selection.selectedVoice(in: voices)?.id == "ru-standard")
        selection.selectLanguage("en", voices: voices)
        precondition(selection.selectedVoice(in: voices)?.id == "en-us")
        selection.voicesByLanguage["en"] = "removed"
        selection.selectLanguage("en", voices: voices)
        precondition(selection.selectedVoice(in: voices) == nil)
        precondition(selection.voicesByLanguage["en"] == "removed")
        let legacy = VoiceSettings(language: nil, saved: [:], legacyID: "en-us", voices: voices)
        precondition(legacy.language == "en" && legacy.selectedVoice(in: voices)?.id == "en-us")
        precondition(VoiceSettings.languages(in: voices) == ["en", "ru", "ja"])
        precondition(VoiceSettings.choices(for: "en", in: voices).count == 2)
        print("voice_settings=PASS migration, per_language_memory, quality, no_silent_fallback, russian_sort, regions")

        var configured = VoiceSettings(language: "ru", saved: ["en": "en-us"], legacyID: nil, voices: voices,
            legacyRate: 0.63, legacyAllowed: ["ru", "en", "ja"])
        precondition(configured.rate(for: "ru") == 0.63 && configured.rate(for: "en") == 0.63)
        precondition(configured.additionalLanguages == ["en": true, "ja": true])
        configured.ratesByLanguage["en"] = 0.4
        configured.setEnabled(false, for: "en")
        precondition(!configured.allowedLanguages.contains("en") && configured.allowedLanguages.contains("ru"))
        configured.removeLanguage("en")
        configured.addLanguage("en", voices: voices)
        precondition(configured.rate(for: "en") == 0.4 && configured.voicesByLanguage["en"] == "en-us")
        configured.setPrimaryLanguage("en", voices: voices)
        precondition(configured.additionalLanguages["en"] == nil && configured.additionalLanguages["ru"] == true)
        configured.setEnabled(false, for: "en")
        precondition(configured.allowedLanguages.contains("en"))
        configured.removeLanguage("ru")
        configured.removeLanguage("ja")
        let plist: [String: Any] = ["rates": configured.ratesByLanguage, "additional": configured.additionalLanguages]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let restored = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        let reloaded = VoiceSettings(language: configured.language, saved: configured.voicesByLanguage,
            legacyID: nil, voices: voices,
            rates: (restored["rates"] as! [String: NSNumber]).mapValues { $0.floatValue },
            legacyRate: configured.initialRate, additional: restored["additional"] as? [String: Bool])
        precondition(reloaded.additionalLanguages.isEmpty && reloaded.allowedLanguages == ["en"])
        precondition(reloaded.rate(for: "en") == 0.4 && reloaded.rate(for: "ru") == 0.63)
        precondition(VoiceSettings.validRate(.nan) == 0.5 && VoiceSettings.validRate(-1) == 0 && VoiceSettings.validRate(2) == 1)
        precondition(LanguagePlan.preferredLanguage(scores: [:], allowed: ["en", "ja"], fallback: "en") == "en")
        print("speech_configuration=PASS migration, independent_rates, disable_remove_readd, primary_change, persistence, empty_list")

        let allowed = ["ru", "en", "ja"]
        precondition(LanguagePlan.preferredLanguage(scores: ["ja": 0.64], allowed: allowed, fallback: "ru") == "ru")
        precondition(LanguagePlan.preferredLanguage(scores: ["ja": 0.5, "en": 0.45], allowed: allowed, fallback: "ru") == "ru")
        precondition(LanguagePlan.preferredLanguage(scores: ["ja": 0.8, "en": 0.15], allowed: allowed, fallback: "ru") == "ja")
        precondition(LanguagePlan.preferredLanguage(scores: ["zh": 0.99], allowed: allowed, fallback: "ru") == "ru")
        let samples = [
            ("Это достаточно длинное предложение на русском языке для проверки чтения.", "ru"),
            ("This is an English sentence to verify the selected voice and language.", "en"),
            ("公演期間：2027/03/03(水)", "ja")
        ]
        for (index, sample) in samples.enumerated() {
            let detected = LanguagePlan.language(for: sample.0, allowed: allowed, fallback: "ru")
            guard detected == sample.1 else {
                print("language_case=FAIL index=\(index) expected=\(sample.1) actual=\(detected ?? "none")")
                exit(1)
            }
            print("language_case=PASS index=\(index) language=\(sample.1)")
        }
        precondition(LanguagePlan.language(for: "12345", allowed: allowed, fallback: "ru") == "ru")
        precondition(LanguagePlan.language(for: "", allowed: allowed, fallback: "ru") == "ru")
        let combined = samples.map { $0.0 }.joined(separator: "\n") + "\n"
        let parts = LanguagePlan.parts(combined, allowed: allowed, fallback: "ru")
        precondition(parts.map(\.text).joined() == combined)
        precondition(parts.allSatisfy { allowed.contains($0.language) })
        let outside = LanguagePlan.language(for: "مرحبا بكم في هذا الاختبار", allowed: allowed, fallback: "ru")
        precondition(outside.map { allowed.contains($0) } == true)
        print("language_plan=PASS russian_fallback, whitelist, text_preservation")
    }
}
