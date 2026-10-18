"""Sign using the pinned public certificate; fail instead of falling back to ad hoc."""
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SIGNING = Path(os.environ.get("QUIETSELECTION_SIGNING_DIR", str(ROOT / ".local" / "signing"))).expanduser().resolve()
CERT = SIGNING / "QuietSelection.cer"


def sign(app):
    if not CERT.is_file():
        raise SystemExit("Persistent signing is not configured. Run Scripts/setup_signing.py once with permission.")
    output = subprocess.run(["/usr/bin/openssl", "x509", "-inform", "DER", "-in", str(CERT),
                             "-noout", "-fingerprint", "-sha1"],
                            check=True, capture_output=True, text=True).stdout
    fingerprint = output.strip().split("=", 1)[-1].replace(":", "")
    if not re.fullmatch(r"[0-9A-Fa-f]{40}", fingerprint):
        raise SystemExit("Invalid public certificate fingerprint.")
    requirement = f'identifier "local.quietselection" and certificate leaf = H"{fingerprint}"'
    keychain = (CERT.parent / "keychain-path.txt").read_text().strip()
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", fingerprint,
                    "--keychain", keychain, "--timestamp=none", "--identifier", "local.quietselection",
                    "--requirements", "=designated => " + requirement, str(app)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + requirement, str(app)], check=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: sign_app.py path/to/QuietSelection.app")
    sign(Path(sys.argv[1]).resolve())
