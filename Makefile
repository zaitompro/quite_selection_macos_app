.PHONY: build test test-gui audit

build:
	/bin/bash Scripts/build.sh

test:
	/bin/bash Scripts/test.sh

test-gui: test
	build/RegionPickerTests
	build/LocalSelectionTests
	build/WindowTests
	build/OCRTests
	build/SpeechTests

audit:
	python3 Tests/privacy_audit.py
