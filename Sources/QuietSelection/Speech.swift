import AVFoundation
import NaturalLanguage

@MainActor
final class Speech: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var finished: (() -> Void)?
    var speaking: Bool { synthesizer.isSpeaking || synthesizer.isPaused }
    var voiceID: String?
    var automatic = false
    var allowedLanguages: [String] = ["ru", "en"]
    var voicesByLanguage: [String: String] = [:]
    var ratesByLanguage: [String: Float] = [:]
    var fallbackLanguage = "ru"
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    static func validatedRate(_ value: Float) -> Float {
        guard value.isFinite else { return AVSpeechUtteranceDefaultSpeechRate }
        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, value))
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // Exclude third-party synthesis extensions and Personal Voice. No download,
    // network client, recognition service, or authorization for personal voices.
    static func installedVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice)
        }.sorted {
            if $0.language != $1.language { return $0.language < $1.language }
            if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.identifier < $1.identifier
        }
    }

    func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let voices = Self.installedVoices()
        if let voiceID { return voices.first { $0.identifier == voiceID } }
        return nil
    }

    func utterance(for text: String) -> AVSpeechUtterance? {
        guard let voice = voice(for: text) else { return nil }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.validatedRate(rate)
        // Do not inherit Spoken Content's highlighting or controller settings.
        utterance.prefersAssistiveTechnologySettings = false
        return utterance
    }

    func preparedUtterances(for text: String) -> [AVSpeechUtterance]? {
        if !automatic {
            guard let utterance = utterance(for: text) else { return nil }
            return [utterance]
        }
        let voices = Self.installedVoices()
        let plan = LanguagePlan.parts(text, allowed: allowedLanguages, fallback: fallbackLanguage)
        guard !plan.isEmpty else { return nil }
        // Validate the entire plan before starting; never substitute another voice.
        var utterances: [AVSpeechUtterance] = []
        for part in plan {
            guard let id = voicesByLanguage[part.language],
                  let voice = voices.first(where: { $0.identifier == id }) else { return nil }
            let utterance = AVSpeechUtterance(string: part.text)
            utterance.voice = voice
            utterance.rate = Self.validatedRate(ratesByLanguage[part.language] ?? rate)
            utterance.prefersAssistiveTechnologySettings = false
            utterances.append(utterance)
        }
        return utterances
    }

    @discardableResult func speak(_ text: String) -> Bool {
        guard let utterances = preparedUtterances(for: text) else { return false }
        for utterance in utterances { synthesizer.speak(utterance) }
        return true
    }

    func primaryUtterance(_ text: String, voiceID: String?, rate: Float) -> AVSpeechUtterance? {
        guard let voice = Self.installedVoices().first(where: { $0.identifier == voiceID }) else { return nil }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.validatedRate(rate)
        utterance.prefersAssistiveTechnologySettings = false
        return utterance
    }

    @discardableResult func speakPrimary(_ text: String, voiceID: String?, rate: Float) -> Bool {
        guard let utterance = primaryUtterance(text, voiceID: voiceID, rate: rate) else { return false }
        synthesizer.speak(utterance)
        return true
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished?() } // Never inspect or log utterance.speechString.
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished?() }
    }
}
