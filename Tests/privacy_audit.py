"""Static guardrails only. Does not inspect clipboard, other apps, or user data."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
source_dir = root / "Sources" / "QuietSelection"
# The copy fallback (user-listed applications only) is the single exception for
# clipboard access, synthetic ⌘C and pressing a menu-bar Copy item.
COPY_FILE = "ClipboardCopy.swift"
COPY_ONLY = (r"\bNSPasteboard\b", r"\bCGEvent\b", r"\bAXUIElementPerformAction\b", r"\bkAXChildrenAttribute\b")
# Reading under the pointer (on a reading shortcut only) is the single exception
# for the pointer position, hit-testing, parents and whole element values.
POINTER_FILE = "PointerText.swift"
POINTER_ONLY = (r"NSEvent\.mouseLocation", r"\bAXUIElementCopyElementAtPosition\b", r"\bkAXValueAttribute\b",
                r"\bkAXParentAttribute\b", r"\bkAXTitleAttribute\b")


def strip(text):
    # Remove comments before checking forbidden calls. This is not a substitute for
    # reviewing the source or for the Safari/Mail manual acceptance test.
    return re.sub(r"//[^\n]*", "", text)


files = {p.name: strip(p.read_text()) for p in source_dir.glob("*.swift")}
code = "\n".join(text for name, text in files.items() if name not in (COPY_FILE, POINTER_FILE))
copy_code = files[COPY_FILE]
pointer_code = files[POINTER_FILE]
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
    if pattern not in COPY_ONLY:
        assert not re.search(pattern, copy_code), f"Forbidden API in {COPY_FILE}: {pattern}"
    if pattern not in POINTER_ONLY:
        assert not re.search(pattern, pointer_code), f"Forbidden API in {POINTER_FILE}: {pattern}"
# Pointer reading invariants: bounded text, secure fields refused, no output,
# no clipboard or events, and only a bounded walk to parents.
assert "PointerPolicy.validated" in pointer_code and "AXSecureTextField" in pointer_code
assert re.search(r"for _ in 0\.\.<10", pointer_code), "parent walk must stay bounded"
assert not re.search(r"print\s*\(|FileManager|\.write\s*\(|UserDefaults|NSPasteboard|CGEvent", pointer_code)

# Copy fallback invariants: menu bar only, Press only, events only to the target
# process, no output of any kind.
assert "kAXMenuBarAttribute" in copy_code
for call in re.findall(r"AXUIElementPerformAction\(([^)]*)\)", copy_code):
    assert "kAXPressAction" in call, "only the Press action is allowed"
assert ".postToPid(" in copy_code and not re.search(r"\.post\(\s*tap", copy_code)
assert "NSPasteboard.general" in copy_code
assert not re.search(r"print\s*\(|FileManager|\.write\s*\(|UserDefaults", copy_code)
fallback = files["CopyFallback.swift"]
assert "isRestorable" in fallback and "org.nspasteboard.concealedtype" in fallback
assert "replace(with: saved)" in fallback and "changeCount" in fallback
app = files["App.swift"]
assert app.count("PointerTextReader()") >= 1 and "if let pointer," in app, "pointer reading only on a reading shortcut"
assert app.count("ClipboardCopy.read(") == 1 and re.search(r"if allowsCopy,", app), "copy fallback only for listed apps"
for line in code.splitlines():
    if re.search(r"\bprint\s*\(", line):
        assert not any(x in line for x in ("speechString", "\u005c(text)", "\u005c(result)", "localizedDescription"))
print("PASS: source privacy guardrails (clipboard/⌘C/menu press only in the copy fallback; pointer position, hit-test and element text only in reading under the pointer; no network client or text logging)")

ocr = (root / "Sources" / "QuietSelection" / "ScreenOCR.swift").read_text()
assert "configuration.fileURL = nil" in ocr
assert "captureScreenshot(rect: rect, configuration: configuration)" in ocr
assert not re.search(r"\.write\s*\(|FileManager|NSLog|print\s*\(", ocr)
print("PASS: region-only screen capture, no OCR image/text file output or window inventory")
