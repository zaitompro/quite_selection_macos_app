import Foundation
import Translation
import SwiftUI
import AppKit

@MainActor
final class LocalTranslation: TranslationBackend {
    private var sessions: [String: TranslationSession] = [:]

    static func availability() -> LanguageAvailability {
        if #available(macOS 26.4, *) { return LanguageAvailability(preferredStrategy: .lowLatency) }
        return LanguageAvailability()
    }
    static func installedSession(source: String, target: String) -> TranslationSession {
        let from = Locale.Language(identifier: source), to = Locale.Language(identifier: target)
        if #available(macOS 26.4, *) {
            return TranslationSession(installedSource: from, target: to, preferredStrategy: .lowLatency)
        }
        return TranslationSession(installedSource: from, target: to)
    }
    func readiness(source: String, target: String) async -> TranslationReadiness {
        if source == target { return .installed }
        let availability = await Self.availability().status(from: Locale.Language(identifier: source),
                                                            to: Locale.Language(identifier: target))
        if availability == .unsupported { return .unsupported }
        // Use the same installed-only session type as actual reading. This check
        // neither requests permission nor starts downloads.
        let probe = Self.installedSession(source: source, target: target)
        let ready = await probe.isReady
        probe.cancel()
        return ready ? .installed : .supported
    }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        try Task.checkCancellation()
        let key = source + ">" + target
        let session: TranslationSession
        if let cached = sessions[key] { session = cached }
        else {
            session = Self.installedSession(source: source, target: target)
            sessions[key] = session
        }
        // installedSource sessions cannot request downloads. User text stays local.
        guard !session.canRequestDownloads else { throw TranslationFailure.unavailable(source) }
        let response = try await session.translate(text)
        try Task.checkCancellation()
        return response.targetText
    }
    func cancel() {
        for session in sessions.values { session.cancel() }
        sessions.removeAll()
    }
}

// The only download-capable session is attached to this visible, explicitly
// opened preparation window. It never receives selected or translated text.
@MainActor
private struct TranslationPreparationView: View {
    let source: String
    let target: String
    let update: (TranslationPreparationState) -> Void
    @State private var state = TranslationPreparationState.requesting
    @State private var started = false
    @State private var activeSession: TranslationSession?
    @State private var configuration: TranslationSession.Configuration

    init(source: String, target: String, update: @escaping (TranslationPreparationState) -> Void) {
        self.source = source; self.target = target; self.update = update
        let from = Locale.Language(identifier: source), to = Locale.Language(identifier: target)
        let initial: TranslationSession.Configuration
        if #available(macOS 26.4, *) {
            initial = .init(source: from, target: to, preferredStrategy: .lowLatency)
        } else { initial = .init(source: from, target: to) }
        _configuration = State(initialValue: initial)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Подготовка перевода").font(.title2.bold())
            Text(VoiceChoice.languageTitle(source) + " → " + VoiceChoice.languageTitle(target)).font(.headline)
            Text(state.message)
            if state == .requesting || state == .waiting { ProgressView().controlSize(.small) }
            if state.canRetry {
                Button("Повторить запрос") { started = false; configuration.invalidate() }
            }
            Text("Загрузка выполняется средствами macOS. Дождитесь подтверждения готовности. Выделенный текст не передаётся; перевод работает без интернета после подготовки.")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 17)).padding(24).frame(width: 490, alignment: .leading)
        .translationTask(configuration) { session in
            guard !started else { return }
            started = true
            activeSession = session
            let ticket = configuration.version
            do {
                let backend = LocalTranslation()
                try await TranslationPreparationMonitor.run(
                    prepare: {
                        try await session.prepareTranslation()
                        try Task.checkCancellation()
                        state = .waiting; update(.waiting)
                        // A preparation call may return as soon as permission is
                        // granted. Keep the download-capable task alive through
                        // a real translation; otherwise its progress UI can close
                        // before models become available to installed-only reads.
                        // Only a fixed synthetic phrase is supplied, never selection.
                        let samples = ["en": "This is a translation test.",
                            "ru": "Это проверка перевода.", "ja": "これは翻訳のテストです。"]
                        _ = try await session.translate(samples[source] ?? "QuietSelection")
                        try Task.checkCancellation()
                    },
                    isReady: { await backend.readiness(source: source, target: target) == .installed },
                    wait: { try await Task.sleep(nanoseconds: 2_000_000_000) },
                    update: { next in
                        guard ticket == configuration.version else { return }
                        state = next; update(next)
                    })
            } catch {
                guard ticket == configuration.version else { return }
                let next: TranslationPreparationState = error is CancellationError ? .cancelled : .failed((error as NSError).code)
                state = next; update(next)
            }
            activeSession = nil
        }
        .onDisappear { activeSession?.cancel() }
    }
}

@MainActor
final class TranslationPreparationWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init(source: String, target: String, update: @escaping (TranslationPreparationState) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 370),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "QuietSelection — Загрузка языков"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: TranslationPreparationView(source: source, target: target, update: update))
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() { NSApp.activate(); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil; window?.contentView = nil
        onClose?()
    }
}
