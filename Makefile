.PHONY: build test test-gui audit

build:
	bash Scripts/build.sh

test:
	bash Scripts/test.sh

test-gui: test
	build/RegionPickerTests
	build/LocalSelectionTests
	build/WindowTests
	build/OCRTests
	build/SpeechTests

audit:
	python3 Tests/privacy_audit.py
