#!/usr/bin/env python3
"""Print the Chrome extension ID that belongs to a public key.

Usage: python3 -I timffle/scripts/extension-id.py [timffle/extension-key/chrome-extension-public.b64]

The input is the base64 of the DER-encoded public key, the same value that goes into the "key" field of
manifest.json. The ID is the first 32 hex digits of its SHA-256, with the digits 0-f written as the letters a-p.
Only public key material is read; never pass a private key.
"""
import base64
import hashlib
import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "extension-key" / "chrome-extension-public.b64"


def extension_id(public_key_b64: str) -> str:
    der = base64.b64decode(public_key_b64.strip(), validate=True)
    digest = hashlib.sha256(der).hexdigest()[:32]
    return "".join(chr(ord("a") + int(c, 16)) for c in digest)


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT
    text = path.read_text(encoding="ascii")
    if "PRIVATE KEY" in text:
        print("Refusing to read private key material.", file=sys.stderr)
        return 2
    print(extension_id(text))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
