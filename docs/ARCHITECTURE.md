# Architecture / Устройство приложения

QuietSelection is a small native Swift/AppKit menu-bar application. There is intentionally no web service, external dependency manager or application-wide accessibility-tree crawler. The clipboard is used only by the opt-in copy fallback described below.

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

Selection reading resolves the foreground application's focused element, obtains only the selected fragment, then prepares local speech. Queries and text sizes are bounded; secure input is rejected.

The application read is the one holding keyboard focus (system-wide `AXFocusedApplication`, process ID only). It is normally the frontmost application; launcher panels such as Alfred take keyboard focus without becoming frontmost, and are read instead. Switching the frontmost application still cancels the request.

Selection attributes are tried in order — `AXSelectedText`, `AXSelectedTextRange` with `AXStringForRange`, then the selected text-marker range — and an Accessibility error from one attribute moves on to the next instead of ending the request. Each query may wait up to 1.5 s and is repeated once if the target reports it is busy (`kAXErrorCannotComplete`); the whole request is limited to 4 s. A range reply may differ in length from the reported range (line endings, attachments), but a reply far longer than the range is rejected as not being the selection.

Secure keyboard input is a system-wide flag. Reading is refused when the frontmost application holds it or when its holder cannot be identified; a password field left focused in another application does not block reading. Secure fields in the target are always rejected.

Chromium browsers and Electron applications (detected by a `* Helper (Renderer).app` inside the bundle) may build web accessibility only after the first query. For them the application's standard `AXRole` is read, and an unsuccessful read is repeated once. No attributes are written; `AXManualAccessibility`/`AXEnhancedUserInterface` remain prohibited. The original evidence is the ChatGPT/Codex case; other Chromium/Electron apps need user confirmation. Accessibility behaviour varies between apps and can itself affect WebKit, so automated tests must be complemented by the user's Safari/Mail scrolling checks.

OCR is a separate, explicit action: choose a region, capture that region, recognize locally, then speak. Images and recognized text stay in memory. There is no whole-screen or mailbox traversal as a fallback for selection.

Automatic speech considers the primary language and enabled additional languages. Uncertain detection falls back to the primary language. Each prepared utterance receives the exact saved voice and that language's rate. Missing saved voices cause an error rather than a silent substitution. Configuration changes apply to subsequent reading.

Settings are stored in the application's UserDefaults domain. Only configuration is persisted: languages, voice identifiers, rates, shortcut choices and related preferences. Selected text, OCR images and reading history are not persisted. Disabling or removing an additional language retains its saved voice and rate for later reuse.

The settings window's additional-language list is height-constrained and scrolls independently. Command + Q and Command + W close settings; explicit Quit exits the application.

## Copy fallback

For applications the user lists in Settings → General (stored as bundle identifiers in `CopyFallbackApps`), a failed Accessibility read (no focus, no selection, unsupported, invalid response or an Accessibility error) is followed by a copy read. Secure input, permission, size and app-switch failures never are.

`CopyFallback.swift` holds the platform-free logic. The whole clipboard (every item and type) is saved first; concealed/transient entries, file promises, unreadable types or more than 50 MB cancel the fallback before anything is copied. Copy commands are tried in order until the change count moves: pressing the menu item whose shortcut is ⌘C (`ClipboardCopy.swift`, menu bar only, `kAXPressAction` only), then ⌘C posted to the target process after the user releases all modifiers and Escape. After the count settles the plain text is taken and the saved clipboard is restored immediately — unless the count moved again, in which case the newer content is kept. Every error path after copying restores as well. `ClipboardCopy.swift` is the only file the privacy audit allows to use `NSPasteboard`, `CGEvent`, `kAXChildrenAttribute` or `AXUIElementPerformAction`.

## Tests

`Tests/QuietSelectionTests/` contains standalone Swift test executables. They use in-memory backends, native test controls and synthetic text/images. `Tests/privacy_audit.py` rejects known prohibited API patterns and checks OCR capture restrictions. Build and GUI tests are separate so ordinary logic checks do not request system permissions or inspect the user's apps.

## По-русски

Приложение состоит из независимых частей: получение выделения, локальная речь, OCR выбранной области, настройки и системные сочетания. `App.swift` связывает их между собой. Ресурсы пакета находятся в `Resources/`, проверки — в `Tests/`, вспомогательные команды — в `Scripts/`.

При ошибке одного способа получения выделения пробуется следующий; запросы ждут дольше и повторяются один раз, если приложение занято. Защищённый ввод в другом приложении больше не блокирует чтение. Для браузеров на Chromium и приложений на Electron доступность «будится» чтением роли приложения, без записи атрибутов.

Ключевые ограничения: буфер обмена и копирование только в «Чтении через копирование» для приложений из списка пользователя, с полным возвратом буфера; не читать страницу или дерево доступности целиком вместо выделения, не отправлять пользовательский текст в сеть и не сохранять его на диск. OCR запускается только после явного выбора области. Основной язык отвечает и за ручной режим, и за неуверенное автоопределение; голос и скорость задаются для каждого языка отдельно.

## Translation

The primary-only command bypasses automatic speech planning without mutating saved preferences. Translation shares the existing narrow selection path. It snapshots the target, voice and rate, splits sentences using the restricted language plan, and asks for a source only for uncertain fragments. Primary-language and non-letter fragments pass through. All foreign pairs must be installed before any translation; all results complete before speech. Cancellation uses task cancellation, session cancellation and generation tickets to discard stale completions.

`TranslationSession(installedSource:target:)` cannot request downloads. On macOS 26.4+ both readiness and sessions explicitly select `.lowLatency`; older supported systems use the original translation API. A separate visible SwiftUI `.translationTask` calls `prepareTranslation()` after a download button click, then translates a fixed synthetic phrase in that same download-capable task before checking installed-only readiness. That session never receives user text. Readiness uses `LanguageAvailability` for support and `isReady` on an installed-only session for actual readiness, not guessed model files; statuses describe language pairs. `prepareTranslation()` may return while downloading: the visible task keeps a stable state-owned configuration and waits for installed-only readiness, with cancellable polling and no fixed download deadline, so slow connections are not treated as failures. A returned preparation call never marks a pair ready by itself. No model deletion or file scanning API is used.

Tests use a fake translation backend for ordering, missing/unsupported models, primary pass-through and cancellation. Real model preparation and translation require explicit user checks on the installed signed application; these are not claimed by the fake-backend tests.
