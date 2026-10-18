"""Compare installed and candidate signatures without reading privacy databases."""
from pathlib import Path
import json
import argparse
import plistlib
import re
import subprocess


def inspect(path):
    result = subprocess.run(["/usr/bin/codesign", "-d", "-r-", "--verbose=4", str(path)],
                            check=True, capture_output=True, text=True)
    details = result.stdout + result.stderr
    requirement = re.search(r"^designated => (.+)$", details, re.MULTILINE)
    code_hash = re.search(r"^CDHash=(.+)$", details, re.MULTILINE)
    if not requirement or not code_hash:
        raise SystemExit("FAIL: missing persistent signing requirement or code hash")
    info = plistlib.loads((path / "Contents" / "Info.plist").read_bytes())
    return {"version": info["CFBundleShortVersionString"],
            "requirement": requirement[1], "code_hash": code_hash[1]}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("installed", type=Path)
parser.add_argument("candidate", type=Path)
parser.add_argument("--allow-rebuild", action="store_true", help="Allow the same version or identical code when verifying a rebuild")
args = parser.parse_args()
installed, candidate = args.installed.resolve(), args.candidate.resolve()
before, after = inspect(installed), inspect(candidate)
if not args.allow_rebuild and (before["version"] == after["version"] or before["code_hash"] == after["code_hash"]):
    raise SystemExit("FAIL: test update must change both version and signed code hash")
if before["requirement"] != after["requirement"]:
    raise SystemExit("FAIL: signing identity changed")
for app in (installed, candidate):
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R",
                    "=" + before["requirement"], str(app)], check=True)
report = {"before": before, "after": after, "identity_continuity": "PASS",
          "accessibility_retention": "awaiting_user_test"}
report_path = Path(__file__).resolve().parent.parent / "build" / "update-test-report.json"
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: {before['version']} -> {after['version']}; signing identity preserved.")
print("PASS: both releases satisfy the installed version's signing requirement.")
print("Accessibility permissions were not requested or changed.")
