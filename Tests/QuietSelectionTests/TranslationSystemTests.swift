import Foundation

@main
@MainActor
struct TranslationSystemTests {
    static func main() async {
        let backend = LocalTranslation()
        let samples = ["en": "This is a local translation test.", "ja": "これは翻訳のテストです。"]
        var completed = 0
        for source in ["en", "ja"] {
            let readiness = await backend.readiness(source: source, target: "ru")
            let ready = readiness == .installed
            print("translation_pair=\(source)_ru installed=\(ready) supported=\(readiness != .unsupported)")
            guard ready, CommandLine.arguments.contains("--translate") else { continue }
            do {
                let output = try await backend.translate(samples[source]!, source: source, target: "ru")
                guard !output.isEmpty, output.unicodeScalars.contains(where: { (0x0400...0x04ff).contains($0.value) }) else {
                    print("translation_smoke=FAIL reason=unexpected_output_language"); exit(1)
                }
                completed += 1
                print("translation_smoke=PASS source=\(source) target=ru output_not_logged=true")
            } catch { print("translation_smoke=FAIL error_code=\((error as NSError).code)"); exit(1) }
        }
        backend.cancel()
        print("completed_translations=\(completed) downloads_requested=0 user_text_read=0")
    }
}
