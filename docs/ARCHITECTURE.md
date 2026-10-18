# Architecture / Устройство приложения

QuietSelection is a small native Swift/AppKit menu-bar application. There is intentionally no web service, clipboard adapter, external dependency manager or application-wide accessibility-tree crawler.

## Source map

All application sources are in `Sources/QuietSelection/`.

| Component | Responsibility |
| --- | --- |
| `App.swift` | Application lifecycle, preferences, command routing and orchestration |
| `AppMenu.swift`, `HotKey.swift`, `LoginLaunch.swift` | Explicit menu actions, global shortcuts and launch at login |
| `Selection.swift` | Selection-only extraction policy with bounded UTF-16 lengths |
| `FocusedElement.swift`, `Accessibility.swift` | Narrow focus resolution and supported selected-text/range attributes |
| `LocalSelection.swift` | Selection from the app's own focused native text control |
| `Speech.swift` | Installed Apple voices and local AVSpeechSynthesizer utterances |
| `VoiceSettings.swift`, `LanguagePlan.swift` | Per-language voices/rates, primary language, restricted sentence-level detection |
| `ScreenOCR.swift`, `RegionPicker.swift`, `RegionFocus.swift` | Explicit region capture, local OCR and focus restoration; nonactivating panels keep open settings in the background |
| `TranslationPlan.swift`, `LocalTranslation.swift` | Restricted source detection, all-pair preflight, ordered local translation and cancellation |
| `TranslationSettingsView.swift`, `SourceLanguageChooser.swift` | Model readiness, explicit preparation, per-reading uncertain-language choice |
| `SettingsWindow.swift`, `SpeechSettingsView.swift`, `SettingsStyle.swift` | Native settings UI and muted appearance |

## Data flow and invariants

Selection reading resolves the foreground application's focused element, obtains only the selected fragment, then prepares local speech. Queries and text sizes are bounded; secure input is rejected. Accessibility behaviour varies between apps and can itself affect WebKit, so automated tests must be complemented by the user's Safari/Mail scrolling checks.

OCR is a separate, explicit action: choose a region, capture that region, recognize locally, then speak. Images and recognized text stay in memory. There is no whole-screen or mailbox traversal as a fallback for selection.

Automatic speech considers the primary language and enabled additional languages. Uncertain detection falls back to the primary language. Each prepared utterance receives the exact saved voice and that language's rate. Missing saved voices cause an error rather than a silent substitution. Configuration changes apply to subsequent reading.

Settings are stored in the application's UserDefaults domain. Only configuration is persisted: languages, voice identifiers, rates, shortcut choices and related preferences. Selected text, OCR images and reading history are not persisted. Disabling or removing an additional language retains its saved voice and rate for later reuse.

The settings window's additional-language list is height-constrained and scrolls independently. Command + Q and Command + W close settings; explicit Quit exits the application.

## Tests

`Tests/QuietSelectionTests/` contains standalone Swift test executables. They use in-memory backends, native test controls and synthetic text/images. `Tests/privacy_audit.py` rejects known prohibited API patterns and checks OCR capture restrictions. Build and GUI tests are separate so ordinary logic checks do not request system permissions or inspect the user's apps.

## По-русски

Приложение состоит из независимых частей: получение выделения, локальная речь, OCR выбранной области, настройки и системные сочетания. `App.swift` связывает их между собой. Ресурсы пакета находятся в `Resources/`, проверки — в `Tests/`, вспомогательные команды — в `Scripts/`.

Ключевые ограничения: не использовать буфер обмена и имитацию копирования, не читать страницу или дерево доступности целиком вместо выделения, не отправлять пользовательский текст в сеть и не сохранять его на диск. OCR запускается только после явного выбора области. Основной язык отвечает и за ручной режим, и за неуверенное автоопределение; голос и скорость задаются для каждого языка отдельно.

## Translation

The primary-only command bypasses automatic speech planning without mutating saved preferences. Translation shares the existing narrow selection path. It snapshots the target, voice and rate, splits sentences using the restricted language plan, and asks for a source only for uncertain fragments. Primary-language and non-letter fragments pass through. All foreign pairs must be installed before any translation; all results complete before speech. Cancellation uses task cancellation, session cancellation and generation tickets to discard stale completions.

`TranslationSession(installedSource:target:)` cannot request downloads. On macOS 26.4+ both readiness and sessions explicitly select `.lowLatency`; older supported systems use the original translation API. A separate visible SwiftUI `.translationTask` calls `prepareTranslation()` after a download button click, then translates a fixed synthetic phrase in that same download-capable task before checking installed-only readiness. That session never receives user text. Readiness uses `LanguageAvailability` for support and `isReady` on an installed-only session for actual readiness, not guessed model files; statuses describe language pairs. `prepareTranslation()` may return while downloading: the visible task keeps a stable state-owned configuration and waits for installed-only readiness, with cancellable polling and no fixed download deadline, so slow connections are not treated as failures. A returned preparation call never marks a pair ready by itself. No model deletion or file scanning API is used.

Tests use a fake translation backend for ordering, missing/unsupported models, primary pass-through and cancellation. Real model preparation and translation require explicit user checks on the installed signed application; these are not claimed by the fake-backend tests.
