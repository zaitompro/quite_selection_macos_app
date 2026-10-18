#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_root="$PWD"
destination="${QUIETSELECTION_BUILD_APP:-$task_root/build/QuietSelection.app}"
mkdir -p "$task_root/build"
work=$(mktemp -d "$task_root/build/compile.XXXXXX")
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$work"' EXIT
app="$work/QuietSelection.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$task_root/build/module-cache"
xcrun swiftc -swift-version 5 -O -warnings-as-errors \
    -module-cache-path "$task_root/build/module-cache" \
    -framework AppKit -framework ApplicationServices -framework Carbon \
    -framework AVFoundation -framework NaturalLanguage -framework ServiceManagement -framework Vision -framework ScreenCaptureKit -framework Translation -framework SwiftUI \
    Sources/QuietSelection/Selection.swift Sources/QuietSelection/FocusedElement.swift Sources/QuietSelection/Accessibility.swift Sources/QuietSelection/LocalSelection.swift Sources/QuietSelection/HotKey.swift Sources/QuietSelection/VoiceSettings.swift Sources/QuietSelection/LanguagePlan.swift Sources/QuietSelection/Speech.swift Sources/QuietSelection/LoginLaunch.swift Sources/QuietSelection/ScreenOCR.swift Sources/QuietSelection/RegionFocus.swift Sources/QuietSelection/RegionPicker.swift Sources/QuietSelection/SettingsStyle.swift Sources/QuietSelection/SpeechSettingsView.swift Sources/QuietSelection/SettingsWindow.swift Sources/QuietSelection/AppMenu.swift Sources/QuietSelection/TranslationPlan.swift Sources/QuietSelection/LocalTranslation.swift Sources/QuietSelection/TranslationSettingsView.swift Sources/QuietSelection/SourceLanguageChooser.swift Sources/QuietSelection/App.swift \
    -o "$app/Contents/MacOS/QuietSelection"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/START.html "$app/Contents/Resources/START.html"
mkdir -p "$app/Contents/Resources/Fixtures"
cp Resources/Fixtures/selection.html Resources/Fixtures/test-message.eml Resources/Fixtures/ocr-test.png "$app/Contents/Resources/Fixtures/"
python3 Scripts/sign_app.py "$app"
/usr/bin/codesign --verify --strict "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
# Do not replace a working app until signing and verification have succeeded.
/usr/bin/ditto "$app" "$destination"
printf 'Built: %s\n' "$destination"
