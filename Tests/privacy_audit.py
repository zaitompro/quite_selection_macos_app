"""Static guardrails only. Does not inspect clipboard, other apps, or user data."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
sources = "\n".join(p.read_text() for p in (root / "Sources" / "QuietSelection").glob("*.swift"))
# Remove comments before checking forbidden calls. This is not a substitute for
# reviewing the source or for the Safari/Mail manual acceptance test.
code = re.sub(r"//[^\n]*", "", sources)
forbidden = (
    r"\bNSPasteboard\b", r"\bNSPerformService\b", r"\bCGEvent\b",
    r"\bAXUIElementSetAttributeValue\b", r"\bAXUIElementPerformAction\b",
    r"\bAXUIElementPostKeyboardEvent\b", r"\bkAXChildrenAttribute\b",
    r"\bkAXValueAttribute\b", r"\bkAXParentAttribute\b",
    r"\bkAXTitleAttribute\b", r"\bURLSession\b", r"\bURLRequest\b",
    r"\bProcess\s*\(", r"\bNSLog\b", r"\bLogger\s*\(",
    r"AXManualAccessibility", r"AXEnhancedUserInterface",
    r"\bkAXStartTextMarkerAttribute\b", r"\bkAXEndTextMarkerAttribute\b",
    r"\bkAXTextMarkerRangeForUIElementParameterizedAttribute\b", r"\bAXTextMarkerRangeCreate\b",
    r"\bAXUIElementCopyElementAtPosition\b", r"NSEvent\.mouseLocation",
    r"\bSCShareableContent\b", r"\bCGDisplayCreateImage\b", r"\bCGWindowListCreateImage\b",
    r"\bcaptureSampleBuffer\b",
)
for pattern in forbidden:
    assert not re.search(pattern, code), f"Forbidden API: {pattern}"
for line in code.splitlines():
    if re.search(r"\bprint\s*\(", line):
        assert not any(x in line for x in ("speechString", "\u005c(text)", "\u005c(result)", "localizedDescription"))
print("PASS: source privacy guardrails (no clipboard, event injection, AX tree walking, network client, or text logging)")

ocr = (root / "Sources" / "QuietSelection" / "ScreenOCR.swift").read_text()
assert "configuration.fileURL = nil" in ocr
assert "captureScreenshot(rect: rect, configuration: configuration)" in ocr
assert not re.search(r"\.write\s*\(|FileManager|NSLog|print\s*\(", ocr)
print("PASS: region-only screen capture, no OCR image/text file output or window inventory")
