#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" \
    Sources/QuietSelection/Selection.swift Tests/QuietSelectionTests/SelectionTests.swift -o build/SelectionTests
build/SelectionTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" \
    Sources/QuietSelection/Selection.swift Sources/QuietSelection/FocusedElement.swift Tests/QuietSelectionTests/FocusedElementTests.swift -o build/FocusedElementTests
build/FocusedElementTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AppKit \
    Sources/QuietSelection/RegionFocus.swift Tests/QuietSelectionTests/RegionFocusTests.swift -o build/RegionFocusTests
build/RegionFocusTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework Vision -framework ScreenCaptureKit \
    Sources/QuietSelection/Selection.swift Sources/QuietSelection/ScreenOCR.swift Sources/QuietSelection/RegionFocus.swift Sources/QuietSelection/RegionPicker.swift Tests/QuietSelectionTests/RegionPickerTests.swift -o build/RegionPickerTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework NaturalLanguage \
    Sources/QuietSelection/VoiceSettings.swift Sources/QuietSelection/LanguagePlan.swift Tests/QuietSelectionTests/VoiceSettingsTests.swift -o build/VoiceSettingsTests
build/VoiceSettingsTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework NaturalLanguage \
    Sources/QuietSelection/LanguagePlan.swift Sources/QuietSelection/TranslationPlan.swift Tests/QuietSelectionTests/TranslationTests.swift -o build/TranslationTests
build/TranslationTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework Translation -framework SwiftUI \
    Sources/QuietSelection/LanguagePlan.swift Sources/QuietSelection/TranslationPlan.swift Sources/QuietSelection/LocalTranslation.swift Sources/QuietSelection/VoiceSettings.swift Tests/QuietSelectionTests/TranslationSystemTests.swift -o build/TranslationSystemTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AppKit \
    Sources/QuietSelection/Selection.swift Sources/QuietSelection/LocalSelection.swift Tests/QuietSelectionTests/LocalSelectionTests.swift -o build/LocalSelectionTests
python3 Tests/privacy_audit.py
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework Carbon -framework Vision -framework ScreenCaptureKit \
    Sources/QuietSelection/Selection.swift Sources/QuietSelection/HotKey.swift Sources/QuietSelection/ScreenOCR.swift Tests/QuietSelectionTests/OCRTests.swift -o build/OCRTests
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework Carbon \
    Sources/QuietSelection/HotKey.swift Sources/QuietSelection/VoiceSettings.swift Sources/QuietSelection/SettingsStyle.swift Sources/QuietSelection/SpeechSettingsView.swift Sources/QuietSelection/TranslationPlan.swift Sources/QuietSelection/LanguagePlan.swift Sources/QuietSelection/TranslationSettingsView.swift Sources/QuietSelection/SettingsWindow.swift Sources/QuietSelection/AppMenu.swift Tests/QuietSelectionTests/WindowTests.swift -o build/WindowTests

xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$PWD/build/module-cache" -framework AVFoundation -framework NaturalLanguage \
    Sources/QuietSelection/LanguagePlan.swift Sources/QuietSelection/Speech.swift Tests/QuietSelectionTests/SpeechTests.swift -o build/SpeechTests
