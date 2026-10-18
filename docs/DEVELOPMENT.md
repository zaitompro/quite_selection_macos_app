# Development, signing and updates / Разработка, подпись и обновление

## Build and test

Run commands from the repository root. The checked-in build uses `xcrun swiftc`, Apple's system frameworks and Python 3 helpers; it does not download dependencies. The deployment target is declared in `Resources/Info.plist` (currently macOS 26.0). Version 1.7.0 was validated on macOS 26.5 with SDK 26.5.

- `make test`: executes selection, focus, voice configuration, language planning and privacy checks. It also compiles GUI, OCR and speech tests.
- `make test-gui`: additionally executes the native tests. These use their own test views and synthetic images/text. They do not read another application's content or capture the screen. `SpeechTests` validates speech plans without playing audio.
- `make build`: produces a signed `build/QuietSelection.app`. Signing must already be configured.
- `make audit`: runs only the static privacy checks. These are guardrails, not proof of runtime behaviour.

Optional checks after building:

```sh
build/QuietSelection.app/Contents/MacOS/QuietSelection --speech-smoke
build/QuietSelection.app/Contents/MacOS/QuietSelection --rate-smoke
build/WindowTests --render "$PWD/build/ui-preview"
```

The speech smoke checks synthesize fixed test phrases into memory, without playback or audio files. The render command saves only the application's own test window. The real Safari/Mail scrolling workflow, external-app selection, OCR focus restoration and permission continuity require manual checks. A CLI `--self-check` result is not sufficient evidence of the GUI application's Accessibility permission.

## Local configuration

`.local/` is ignored by Git:

```text
.local/signing/QuietSelection.cer   Public certificate used to pin the existing identity
.local/signing/keychain-path.txt    Local Keychain path (not a key)
.local/install-path.txt            Absolute path of the existing installed .app
```

The private signing key stays in the user's Keychain. It is not exported into this repository. Even the public certificate is kept local here because the repository should not bind other developers to this Mac's identity. `QUIETSELECTION_SIGNING_DIR` can explicitly point to another local signing directory.

On this development Mac, reuse the existing identity. Do not run `Scripts/setup_signing.py` again. A stable bundle identifier (`local.quietselection`), certificate-pinned designated requirement and installation path help preserve permission continuity; macOS ultimately controls its permission decisions.

On a **new Mac / new installation only**, first review `Scripts/setup_signing.py`. Running it explicitly creates a dedicated non-extractable signing key in the user's Keychain and adds user-domain trust for code signing. It is not run automatically by build or test. It refuses to overwrite an existing certificate. After intentional setup, build the app and grant its required permissions yourself.

Never commit private keys, Keychain databases, local signing paths, generated bundles or diagnostic artifacts containing private content. `.gitignore` is a safeguard; review every staged diff before publishing.

## Update an existing installation

Building and installation are separate. `make build` leaves the working installation untouched. The build script also supports `QUIETSELECTION_BUILD_APP`, but do not point it at a running installed app.

1. Update the release and build numbers in `Resources/Info.plist` for a new release.
2. Run tests and build.
3. Check identity continuity against the existing app:

```sh
IFS= read -r installed_app < .local/install-path.txt
python3 Scripts/verify_update.py "$installed_app" build/QuietSelection.app
```

For a same-version rebuild (for example, after moving sources), add `--allow-rebuild`. This relaxes only the version/code-change requirement, not signature verification or identity matching. The report is generated in ignored `build/`.

4. Explicitly quit QuietSelection through its own menu. Command + Q closes only settings.
5. Preserve a backup of the installed bundle, copy the verified candidate to **the same installation path**, and reopen it. Do not run a second copy from the repository's build directory as a replacement installation.
6. Check selection reading, normal arrow scrolling in Safari and Mail, OCR cancellation/focus return, speech settings, and launch at login. Do not reset privacy databases to repair a failed update; first inspect signing continuity and launch attribution.

No upload, release publication or repository push is part of these scripts.

## Краткая инструкция на русском

Команды выполняются из корня репозитория: `make test`, затем при необходимости `make test-gui`, затем `make build`. Сборка создаёт отдельный пакет в `build/`; рабочее приложение автоматически не заменяется.

На текущем Mac постоянная подпись уже настроена. Файлы `.local/` не включаются в Git, закрытый ключ остаётся в Связке ключей. Не создавайте новую подпись для уже установленного приложения. На новом Mac первоначальная настройка выполняется только после осознанного разрешения на создание ключа и изменение доверия для подписи кода.

Для обновления проверяйте подпись через `Scripts/verify_update.py`, завершайте приложение явным пунктом меню, сохраняйте резервную копию и заменяйте пакет по прежнему пути из `.local/install-path.txt`. Для проверки пересборки той же версии предусмотрен `--allow-rebuild`. После обновления проверьте привычные сценарии чтения; разрешения и системные настройки сбрасывать не нужно.
