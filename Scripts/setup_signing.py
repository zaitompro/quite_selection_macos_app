"""Create only QuietSelection's local code-signing identity; never export existing keys."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SIGNING = Path(os.environ.get("QUIETSELECTION_SIGNING_DIR", str(ROOT / ".local" / "signing"))).expanduser().resolve()
CERT = SIGNING / "QuietSelection.cer"
NAME = "QuietSelection Local Signing"


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    if CERT.exists():
        raise SystemExit("Public certificate already exists. Reuse it; do not replace the signing identity.")
    found = subprocess.run(["/usr/bin/security", "find-certificate", "-c", NAME],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if found.returncode == 0:
        raise SystemExit("Named certificate already exists in Keychain. Refusing to create a duplicate.")
    if found.returncode != 44:
        raise SystemExit("Cannot check the dedicated certificate in Keychain; no key was created.")
    keychain = run(["/usr/bin/security", "default-keychain", "-d", "user"],
                   capture_output=True, text=True).stdout.strip().strip('"')
    if not Path(keychain).is_file():
        raise SystemExit("User default keychain not available; no key was created.")
    CERT.parent.mkdir(parents=True, exist_ok=True)
    # A private, newly generated key exists only here until import. No existing
    # private key is read or exported. TemporaryDirectory removes only our files.
    old_mask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix="quietselection-signing-") as directory:
            work = Path(directory)
            config = work / "certificate.cnf"
            config.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions
[subject]
CN = QuietSelection Local Signing
O = QuietSelection Local
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
            key = work / "new-key.pem"
            pem = work / "certificate.pem"
            der = work / "certificate.cer"
            run(["/usr/bin/openssl", "genrsa", "-out", str(key), "3072"], stdout=subprocess.DEVNULL)
            run(["/usr/bin/openssl", "req", "-new", "-x509", "-sha256", "-days", "3650",
                 "-key", str(key), "-out", str(pem), "-config", str(config)], stdout=subprocess.DEVNULL)
            run(["/usr/bin/openssl", "x509", "-in", str(pem), "-outform", "DER", "-out", str(der)])
            # Public recovery material only, saved before modifying Keychain.
            CERT.write_bytes(der.read_bytes())
            run(["/usr/bin/security", "import", str(key), "-k", keychain,
                 "-t", "priv", "-f", "openssl", "-x", "-T", "/usr/bin/codesign"])
            run(["/usr/bin/security", "import", str(der), "-k", keychain, "-t", "cert"])
            # User domain, code-signing policy only; no SSL trust or system-wide root.
            run(["/usr/bin/security", "add-trusted-cert", "-r", "trustRoot", "-p", "codeSign",
                 "-k", keychain, str(der)])
            (CERT.parent / "keychain-path.txt").write_text(keychain + "\n")
    finally:
        os.umask(old_mask)
    print("QuietSelection identity created; private key is non-extractable in the user keychain.")
    print("Only the public certificate is saved in the project.")


if __name__ == "__main__":
    main()
