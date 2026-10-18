import AVFoundation

@main
@MainActor
struct SpeechTests {
    static func main() {
        let voices = Speech.installedVoices()
        let speech = Speech()
        for code in ["ru", "en", "ja"] {
            guard let voice = voices.first(where: { $0.language.hasPrefix(code + "-") }) else {
                print("speech_plan=UNAVAILABLE required_installed_voice=\(code)")
                exit(2)
            }
            speech.voicesByLanguage[code] = voice.identifier
        }
        speech.automatic = true
        speech.allowedLanguages = ["ru", "en", "ja"]
        speech.fallbackLanguage = "ru"
        speech.rate = 0.55
        speech.ratesByLanguage = ["ru": 0.55, "en": 0.41, "ja": 0.66]
        let cases = [
            ("Это достаточно длинное предложение для проверки русского голоса.", "ru"),
            ("This is an English sentence to verify the selected voice and language.", "en"),
            ("公演期間：2027/03/03(水)", "ja")
        ]
        for (text, code) in cases {
            let plan = speech.preparedUtterances(for: text)!
            precondition(plan.allSatisfy { $0.voice?.identifier == speech.voicesByLanguage[code] && abs($0.rate - speech.ratesByLanguage[code]!) < 0.001 })
        }
        let combined = speech.preparedUtterances(for: cases.map { $0.0 }.joined(separator: "\n"))!
        precondition(Set(combined.compactMap { $0.voice?.identifier }).count == 3)
        for part in combined {
            let code = speech.voicesByLanguage.first { $0.value == part.voice?.identifier }!.key
            precondition(abs(part.rate - speech.ratesByLanguage[code]!) < 0.001)
            precondition(!part.prefersAssistiveTechnologySettings)
        }
        speech.fallbackLanguage = "en"
        let fallback = speech.preparedUtterances(for: "12345")!
        precondition(fallback.first?.voice?.identifier == speech.voicesByLanguage["en"])
        precondition(fallback.first?.rate == 0.41)
        speech.automatic = false
        speech.voiceID = speech.voicesByLanguage["ja"]
        speech.rate = 0.66
        precondition(speech.preparedUtterances(for: cases[0].0)?.first?.voice?.identifier == speech.voiceID)
        precondition(speech.preparedUtterances(for: cases[0].0)?.first?.rate == 0.66)
        speech.automatic = true
        let primary = speech.primaryUtterance(cases[1].0, voiceID: speech.voicesByLanguage["ru"], rate: 0.58)!
        precondition(primary.voice?.identifier == speech.voicesByLanguage["ru"] && primary.rate == 0.58)
        precondition(primary.speechString == cases[1].0 && !primary.prefersAssistiveTechnologySettings)
        precondition(speech.automatic && speech.voiceID == speech.voicesByLanguage["ja"] && speech.rate == 0.66)
        precondition(speech.primaryUtterance("Synthetic", voiceID: "missing", rate: 0.5) == nil)
        speech.voicesByLanguage["en"] = "missing"
        precondition(speech.preparedUtterances(for: cases[1].0) == nil)
        print("speech_plan=PASS exact_voices, per_language_rates, mixed_text, primary_fallback, manual_mode, missing_voice_no_substitution")
        print("audio_played=0 external_content_queries=0")
    }
}
