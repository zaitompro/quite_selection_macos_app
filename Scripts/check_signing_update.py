"""Verify identity continuity using two synthetic builds; never touch TCC or real text."""
from pathlib import Path
import plistlib
import re
import subprocess
from sign_app import sign

ROOT = Path(__file__).resolve().parent.parent
work = ROOT / "build" / "signing-check"


def command(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


apps = []
for version in (1, 2):
    app = work / f"Version{version}.app"
    executable = app / "Contents" / "MacOS" / "Probe"
    executable.parent.mkdir(parents=True, exist_ok=True)
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "local.quietselection", "CFBundleExecutable": "Probe",
        "CFBundlePackageType": "APPL", "CFBundleVersion": str(version),
    }))
    command(["/usr/bin/xcrun", "clang", "-x", "c", "-", "-o", str(executable)],
            input=f"int main(void) {{ return {version}; }}\n", text=True)
    sign(app)
    apps.append(app)

dr = command(["/usr/bin/codesign", "-d", "-r-", str(apps[0])], capture_output=True, text=True)
match = re.search(r"^designated => (.+)$", dr.stdout + dr.stderr, re.MULTILINE)
if not match or "certificate leaf" not in match[1] or "cdhash" in match[1]:
    raise SystemExit("FAIL: signature does not pin the certificate identity.")
command(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + match[1], str(apps[1])])
hashes = []
for app in apps:
    details = command(["/usr/bin/codesign", "-d", "--verbose=4", str(app)], capture_output=True, text=True)
    hashes.append(re.search(r"^CDHash=(.+)$", details.stdout + details.stderr, re.MULTILINE)[1])
if hashes[0] == hashes[1]:
    raise SystemExit("FAIL: test builds have identical code hashes.")
# A different, ad-hoc signer must not qualify as an update, even with the same ID.
command(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", "local.quietselection", str(apps[1])])
negative = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + match[1], str(apps[1])],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if negative.returncode == 0:
    raise SystemExit("FAIL: unrelated signature accepted.")
print("PASS: two distinct executables satisfy the same certificate-pinned identity.")
print("PASS: an ad-hoc replacement with the same bundle ID is rejected.")
print("TCC permissions were not read or changed by this test.")
