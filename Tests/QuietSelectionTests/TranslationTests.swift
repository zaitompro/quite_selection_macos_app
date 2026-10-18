import Foundation

@MainActor
private final class FakeTranslation: TranslationBackend {
    var states: [String: TranslationReadiness] = [:]
    var translations = 0
    var delayed = false
    func readiness(source: String, target: String) async -> TranslationReadiness { states[source] ?? .installed }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        translations += 1
        if delayed { try await Task.sleep(nanoseconds: 5_000_000_000) }
        return source == "en" ? "Английский перевод." : "Японский перевод."
    }
}

@main
@MainActor
struct TranslationTests {
    static func main() async throws {
        var preparationStates: [TranslationPreparationState] = []
        var requests = 0, checks = 0
        try await TranslationPreparationMonitor.run(prepare: { requests += 1 },
            isReady: { checks += 1; return false }, wait: {}, attempts: 3,
            update: { preparationStates.append($0) })
        precondition(requests == 1 && checks == 3)
        precondition(preparationStates == [.requesting, .waiting, .notReady])
        preparationStates = []; checks = 0
        try await TranslationPreparationMonitor.run(prepare: { requests += 1 },
            isReady: { checks += 1; return checks == 151 }, wait: {},
            update: { preparationStates.append($0) })
        precondition(preparationStates == [.requesting, .waiting, .ready] && checks == 151)
        preparationStates = []
        do {
            try await TranslationPreparationMonitor.run(prepare: {}, isReady: { false },
                wait: { throw CancellationError() }, update: { preparationStates.append($0) })
            fatalError("preparation cancellation ignored")
        } catch is CancellationError { }
        precondition(!preparationStates.contains(.ready))
        print("translation_preparation=PASS prepare_return_is_not_ready, delayed_ready, slow_connection_no_default_deadline, cancellation_no_success, single_download_request")
        let backend = FakeTranslation()
        let plan = [TranslationPlan.Part(text: "Russian unchanged.\n", source: "ru"),
                    .init(text: "English.\n", source: "en"), .init(text: "Japanese.", source: "ja")]
        let result = try await TranslationPipeline.run(plan, target: "ru", backend: backend)
        precondition(result == "Russian unchanged.\nАнглийский перевод.\nЯпонский перевод.")
        precondition(backend.translations == 2)
        let primary = try await TranslationPipeline.run([plan[0]], target: "ru", backend: backend)
        precondition(primary == plan[0].text && backend.translations == 2)
        backend.states["ja"] = .supported
        do { _ = try await TranslationPipeline.run(plan, target: "ru", backend: backend); fatalError("missing models accepted") }
        catch TranslationFailure.unavailable(let source) { precondition(source == "ja") }
        precondition(backend.translations == 2) // No partial translation before preflight ends.
        backend.states["ja"] = .unsupported
        do { _ = try await TranslationPipeline.run(plan, target: "ru", backend: backend); fatalError("unsupported pair accepted") }
        catch TranslationFailure.unsupported(let source) { precondition(source == "ja") }
        let ambiguous = [TranslationPlan.Part(text: "Short.", source: nil), plan[1]]
        do { _ = try await TranslationPipeline.run(ambiguous, target: "ru", backend: backend); fatalError("uncertain language accepted") }
        catch TranslationFailure.undetermined { }
        let resolved = TranslationPlan.resolving(ambiguous, with: "ja")
        precondition(resolved[0].source == "ja" && resolved[1].source == "en")
        backend.states = [:]; backend.delayed = true
        let task = Task { try await TranslationPipeline.run(plan, target: "ru", backend: backend) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; fatalError("cancelled output accepted") }
        catch is CancellationError { }
        let sample = "Это русское предложение для проверки.\nThis is an English sentence to verify language recognition.\n公演期間：2027/03/03(水)"
        let detected = TranslationPlan.parts(sample, allowed: ["ru", "en", "ja"], target: "ru")
        precondition(detected.map(\.text).joined() == sample)
        precondition(Set(detected.compactMap(\.source)) == Set(["ru", "en", "ja"]))
        let numeric = TranslationPlan.parts("12345\n", allowed: ["ru", "en", "ja"], target: "ru")
        precondition(numeric.allSatisfy { $0.source == "ru" })
        print("translation_pipeline=PASS mixed_order, whitespace, primary_passthrough, model_preflight, unsupported, ambiguous_choice, cancellation, restricted_detection")
        print("system_translations=0 downloads=0 user_text_queries=0")
    }
}
