# QuietSelection

**[English](#english) | [Русский](#russian)**

A small, local macOS utility that reads selected text and text in a screen region aloud.
Небольшая локальная утилита для macOS, озвучивающая выделенный текст и текст в выбранной области экрана.

<a id="english"></a>
## English

[Перейти к русскому описанию ↓](#russian)

### Purpose

QuietSelection is an accessibility tool built for everyday reading without disrupting the user's workflow. Select text in an application and press **Option + Esc** to hear it spoken with an installed Apple voice. Press the shortcut again to stop.

The project started as a replacement for macOS “Speak selection”: in the user's Safari and Apple Mail setup, invoking that feature changed subsequent arrow-key scrolling into text navigation. QuietSelection uses its own selection-reading and speech paths, without invoking the system Spoken Content controller. Safari and Mail behaviour has been checked manually on the development Mac; compatibility still depends on the application's accessibility implementation.

When an application does not expose its selection, press **Control + Esc**, draw a screen region, and hear the text recognized locally. Escape cancels region selection. All shortcuts are configured only in the Keyboard Shortcuts section.

### Speech settings

- An **always-available primary language**, with its own voice and speaking rate. It is used in manual mode and when language detection is uncertain.
- Optional sentence-level language detection restricted to the primary language and enabled additional languages.
- A separate installed voice and speaking rate for each language. Saved voices are not silently replaced when unavailable.
- Additional languages can be added, disabled, or removed. Their list has a fixed height and scrolls internally.
- Local voice previews, optional launch at login, and a menu-bar settings window.
- **Command + Q / Command + W close settings only.** Quitting the utility requires an explicit Quit action in its menu or settings window.

### Read in the primary language and translate

- **Control + Option + Esc** reads the original selection with the primary voice and rate, ignoring automatic detection for this reading only.
- **Command + Esc** detects the language among the primary and enabled additional languages, translates into the primary language, then reads with its exact voice and rate. Already-primary text passes through unchanged. Uncertain fragments prompt for a language for this reading.
- The **Translation** tab shows “Translate to”, “Translate from”, and actual model readiness. Its source list follows enabled additional languages even when automatic speech detection is switched off. Download buttons open Apple's explicit preparation UI; selected text is never supplied during preparation.
- Translation uses Apple's on-device Translation framework, preferring the low-latency model on macOS 26.4+. Reading uses installed-only sessions and never starts a model download. Models are shared system resources; manage their removal in macOS Language & Region settings. Apple may change supported pairs.
- Repeating any reading shortcut stops speech or cancels pending translation. The complete translation is prepared before speech begins.

**Shortcut conflict:** macOS Accessibility Reader uses Command + Esc by default when enabled. This installation uses it for translation at the user's request; Command + Shift + Esc is an alternative. Control + Option is also a VoiceOver modifier. Registration failures preserve the previous working binding; no system shortcuts are changed.

### Privacy and permissions

The application does not read or modify the clipboard, simulate copying, or send selected text or recognized images to a network service. It uses Apple frameworks for local speech, language detection, OCR, and translation. Selected text, OCR text, translations, and captured images are not written to logs or files.

Accessibility permission is needed for selection reading in other applications. Screen Recording permission is needed for the explicitly selected OCR region. Permissions are granted by the user; the application does not reset accessibility settings or alter magnification and mouse settings. Some applications do not expose a usable selection; OCR is the alternative in those cases.

### Development

Current minimum deployment target: **macOS 26.0**. You need Xcode or compatible Apple command-line tools providing the macOS 26.4+ SDK, plus Python 3 for the build helpers. There are no third-party runtime packages. The interface is native Swift/AppKit; a scripted build produces the `.app` bundle without a generated Xcode project.

```sh
make test        # Run logic/privacy checks; compile native GUI, OCR and speech tests
make test-gui    # Also run native tests using synthetic data (may open a test window)
make build      # Build and sign build/QuietSelection.app
```

A stable local signing identity must be configured before `make build`. On the existing development Mac it is already configured in ignored local files. **Do not create a new identity for an existing installation.** On a new Mac, read [Development and signing](docs/DEVELOPMENT.md) before running any setup script: setup changes the user's Keychain and code-signing trust.

Build output stays in this repository's `build/` directory. Building does **not** replace or restart the installed application. The existing installation path is stored separately in ignored `.local/install-path.txt`; keep that path stable when updating.

### Repository layout

```text
Sources/QuietSelection/       Swift application code
Resources/                   Info.plist, bundled help and synthetic fixtures
Tests/QuietSelectionTests/   Native executable test suites
Tests/privacy_audit.py       Static privacy guardrails
Scripts/                     Build, test and signing helpers
docs/                       Development and architecture notes
.local/                      Ignored, machine-specific configuration
build/                       Ignored, generated output
```

See [Development and updates](docs/DEVELOPMENT.md), [Architecture](docs/ARCHITECTURE.md), and the bundled [Russian user guide](Resources/START.html). Test fixtures contain synthetic content, not personal messages or screen captures. The application UI currently uses Russian.

<a id="russian"></a>
## Русский

[Go to English description ↑](#english)

### Назначение

QuietSelection — инструмент доступности для повседневного чтения текста. Выделите текст в приложении и нажмите **Option + Esc**, чтобы прослушать его установленным голосом Apple. Повторное нажатие останавливает чтение.

Проект появился как замена штатному «Проговариванию выбранного текста» macOS. В Safari и Apple Mail у пользователя после его запуска стрелки начинали перемещать курсор по тексту вместо обычной прокрутки. QuietSelection самостоятельно получает выделение и запускает синтез речи, не вызывая системный контроллер проговаривания. Сценарии Safari и Mail проверены пользователем на рабочем Mac; совместимость с другими приложениями зависит от того, как они предоставляют выделение через API доступности.

Если обычное выделение недоступно, нажмите **Control + Esc**, обведите область экрана мышью и прослушайте локально распознанный текст. Escape отменяет выбор области. Все сочетания настраиваются только в разделе «Сочетания клавиш».

### Настройки речи

- **Основной язык** с собственными голосом и скоростью, доступный независимо от автоопределения. Он используется в ручном режиме и при неуверенном определении языка.
- Необязательное определение языка каждого предложения только среди основного и включённых дополнительных языков.
- Отдельные голос и скорость для каждого языка. Недоступный сохранённый голос не подменяется автоматически другим.
- Добавление, отключение и удаление дополнительных языков. Их список имеет фиксированную высоту и собственную прокрутку.
- Прослушивание голосов, автозапуск по желанию пользователя и окно настроек через меню в строке меню macOS.
- **Command + Q / Command + W закрывают только настройки.** Для полного выхода нужно явно выбрать пункт завершения в меню или нажать соответствующую кнопку окна.

### Основной голос и перевод

- **Control + Option + Esc** читает исходное выделение основным голосом с его скоростью, игнорируя автоопределение только для текущего чтения.
- **Command + Esc** определяет язык среди основного и включённых дополнительных, переводит на основной и читает его голосом с его скоростью. Текст на основном языке проходит без перевода. Для неопределённых фрагментов приложение предлагает выбрать язык текущего чтения.
- На вкладке **«Перевод»** находятся «Перевод на», «Перевод с» и фактическая готовность моделей. Список берётся из включённых дополнительных языков независимо от общего тумблера автоопределения речи. Кнопка загрузки открывает системную подготовку языков; выделенный текст ей не передаётся.
- Используется локальный Translation framework Apple, на macOS 26.4+ — стратегия lowLatency. Команда чтения работает только с установленными моделями и не запускает загрузку. Модели общие для системы; удаляются через настройки macOS «Язык и регион». Доступность пар зависит от Apple.
- Повторное сочетание чтения останавливает речь или отменяет перевод. Озвучивание начинается после подготовки всего результата.

**Конфликт сочетаний:** Command + Esc по умолчанию используется Accessibility Reader, когда он включён. По выбору пользователя здесь это сочетание назначено переводу; доступна альтернатива Command + Shift + Esc. Control + Option также является модификатором VoiceOver. Если новое сочетание занято, прежнее рабочее назначение сохраняется. Системные настройки приложение не меняет.

### Приватность и разрешения

Приложение не читает и не изменяет буфер обмена, не имитирует копирование и не отправляет выделенный текст или распознаваемые изображения в интернет. Синтез речи, определение языка, перевод и OCR выполняются локально средствами Apple. Выделенный, распознанный и переведённый текст, а также снимки экрана не записываются в журналы или файлы.

Для чтения выделения в других приложениях нужен «Универсальный доступ», для OCR выбранной области — разрешение «Запись экрана». Их выдаёт пользователь. Приложение не сбрасывает настройки доступности и не меняет увеличение экрана или параметры мыши. Если приложение не предоставляет пригодное выделение, можно использовать чтение области экрана.

### Разработка

Минимальная целевая версия — **macOS 26.0**. Нужны Xcode либо совместимые инструменты командной строки Apple с SDK macOS 26.4+, а также Python 3 для вспомогательных скриптов. Сторонних пакетов времени выполнения нет. Приложение написано на Swift/AppKit; скрипт собирает пакет `.app` без генерируемого проекта Xcode.

```sh
make test        # Проверки логики и приватности; сборка тестов интерфейса, OCR и речи
make test-gui    # Дополнительно запуск тестов на синтетических данных; возможно тестовое окно
make build      # Сборка и подпись build/QuietSelection.app
```

Перед сборкой нужна постоянная локальная подпись. На текущем Mac она уже настроена; её локальная конфигурация исключена из Git. **Для установленного приложения нельзя создавать новую подпись вместо существующей.** На другом Mac сначала прочитайте [инструкцию по разработке и подписи](docs/DEVELOPMENT.md): первоначальная настройка меняет Связку ключей и доверие к сертификату для подписи кода.

Результат сборки находится в `build/` внутри репозитория. Сборка **не заменяет и не перезапускает** установленное приложение. Его прежний путь сохранён отдельно в исключённом из Git файле `.local/install-path.txt`; при обновлении этот путь следует сохранять.

### Структура

- `Sources/QuietSelection/` — исходники приложения.
- `Resources/` — описание пакета, встроенная справка и синтетические материалы для проверки.
- `Tests/` — тесты и статическая проверка ограничений приватности.
- `Scripts/` — сборка, проверки и работа с подписью.
- `docs/` — устройство приложения и инструкции разработчика.
- `.local/` и `build/` — локальные настройки и результаты сборки; в Git не включаются.

Дополнительно: [разработка и обновление](docs/DEVELOPMENT.md), [архитектура](docs/ARCHITECTURE.md), [руководство пользователя](Resources/START.html). В тестовых материалах нет настоящих писем или снимков пользовательского экрана. Интерфейс приложения пока русскоязычный.
