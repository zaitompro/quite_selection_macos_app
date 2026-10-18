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

When an application does not expose its selection, press **Control + Esc**, draw a screen region, and hear the text recognized locally. Escape cancels region selection. Both shortcuts are configurable from the available options.

### Speech settings

- An **always-available primary language**, with its own voice and speaking rate. It is used in manual mode and when language detection is uncertain.
- Optional sentence-level language detection restricted to the primary language and enabled additional languages.
- A separate installed voice and speaking rate for each language. Saved voices are not silently replaced when unavailable.
- Additional languages can be added, disabled, or removed. Their list has a fixed height and scrolls internally.
- Local voice previews, optional launch at login, and a menu-bar settings window.
- **Command + Q / Command + W close settings only.** Quitting the utility requires an explicit Quit action in its menu or settings window.

### Privacy and permissions

The application does not read or modify the clipboard, simulate copying, or send selected text or recognized images to a network service. It uses Apple frameworks for local speech, language detection, and OCR. Selected text, OCR text, and captured images are not written to logs or files.

Accessibility permission is needed for selection reading in other applications. Screen Recording permission is needed for the explicitly selected OCR region. Permissions are granted by the user; the application does not reset accessibility settings or alter magnification and mouse settings. Some applications do not expose a usable selection; OCR is the alternative in those cases.

### Development

Current minimum deployment target: **macOS 26.0**. You need Xcode or compatible Apple command-line tools providing the macOS 26 SDK, plus Python 3 for the build helpers. There are no third-party runtime packages. The interface is native Swift/AppKit; a scripted build produces the `.app` bundle without a generated Xcode project.

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

Если обычное выделение недоступно, нажмите **Control + Esc**, обведите область экрана мышью и прослушайте локально распознанный текст. Escape отменяет выбор области. Для обеих функций можно выбрать сочетание из предусмотренных вариантов.

### Настройки речи

- **Основной язык** с собственными голосом и скоростью, доступный независимо от автоопределения. Он используется в ручном режиме и при неуверенном определении языка.
- Необязательное определение языка каждого предложения только среди основного и включённых дополнительных языков.
- Отдельные голос и скорость для каждого языка. Недоступный сохранённый голос не подменяется автоматически другим.
- Добавление, отключение и удаление дополнительных языков. Их список имеет фиксированную высоту и собственную прокрутку.
- Прослушивание голосов, автозапуск по желанию пользователя и окно настроек через меню в строке меню macOS.
- **Command + Q / Command + W закрывают только настройки.** Для полного выхода нужно явно выбрать пункт завершения в меню или нажать соответствующую кнопку окна.

### Приватность и разрешения

Приложение не читает и не изменяет буфер обмена, не имитирует копирование и не отправляет выделенный текст или распознаваемые изображения в интернет. Синтез речи, определение языка и OCR выполняются локально средствами Apple. Выделенный и распознанный текст, а также снимки экрана не записываются в журналы или файлы.

Для чтения выделения в других приложениях нужен «Универсальный доступ», для OCR выбранной области — разрешение «Запись экрана». Их выдаёт пользователь. Приложение не сбрасывает настройки доступности и не меняет увеличение экрана или параметры мыши. Если приложение не предоставляет пригодное выделение, можно использовать чтение области экрана.

### Разработка

Минимальная целевая версия — **macOS 26.0**. Нужны Xcode либо совместимые инструменты командной строки Apple с SDK macOS 26, а также Python 3 для вспомогательных скриптов. Сторонних пакетов времени выполнения нет. Приложение написано на Swift/AppKit; скрипт собирает пакет `.app` без генерируемого проекта Xcode.

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
