#!/usr/bin/env python3
"""Make the Chrome Web Store upload from a Timffle release ZIP.

Usage: python3 -I timffle/scripts/package-store.py timffle/build/out/timffle-chrome-<VERSION4>.zip <out.zip>

The store wants manifest.json at the root of the ZIP and refuses a manifest with a "key" field (the store signs
the extension itself; the store item already has Timffle's ID, see timffle/docs/BUILD.md). The release ZIP made by
timffle/scripts/package-release.sh keeps the extension in timffle/extension/ next to the connection helper, so this
writes a new ZIP with:
- everything under timffle/extension/ at the root, with "key" removed from manifest.json (nothing else changes);
- timffle/LICENSES/ and timffle/NOTICE.md at the root.
The connection helper, its installers and README.txt stay out: users get the helper from its own download.

Refuses to write over an existing file, and refuses (deleting its own output) when the result would carry a PEM
private key, a program or installer script, or fails timffle/scripts/check-no-build-paths.py.
"""
import hashlib
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

EXTENSION = "timffle/extension/"
EXTRA = {"timffle/NOTICE.md": "NOTICE.md"}
EXTRA_DIR = ("timffle/LICENSES/", "LICENSES/")
REFUSED_SUFFIXES = (".exe", ".dll", ".so", ".dylib", ".sh", ".cmd", ".bat", ".command", ".ps1", ".pem", ".key")
CHECK_PATHS = Path(__file__).resolve().parent / "check-no-build-paths.py"


def store_name(name: str) -> str | None:
    """The name a release ZIP entry gets in the store ZIP, or None when it stays out."""
    if name.startswith(EXTENSION):
        return name[len(EXTENSION):] or None
    if name in EXTRA:
        return EXTRA[name]
    if name.startswith(EXTRA_DIR[0]):
        return EXTRA_DIR[1] + name[len(EXTRA_DIR[0]):]
    return None


def build(release: Path, out: Path) -> dict:
    with zipfile.ZipFile(release) as zin:
        try:
            manifest = json.loads(zin.read(EXTENSION + "manifest.json"))
        except KeyError:
            raise SystemExit(f"package-store: {release} has no {EXTENSION}manifest.json; is it a Timffle release ZIP?")
        manifest.pop("key", None)
        left_out = sorted({"/".join(n.split("/")[:2]) for n in zin.namelist() if store_name(n) is None})
        fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        with os.fdopen(fd, "wb") as fh, zipfile.ZipFile(fh, "w", zipfile.ZIP_DEFLATED) as zout:
            for info in zin.infolist():
                name = store_name(info.filename)
                if name is None or info.is_dir():
                    continue
                data = zin.read(info)
                if name == "manifest.json":
                    data = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
                entry = zipfile.ZipInfo(name, date_time=info.date_time)
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                zout.writestr(entry, data)
    return {"version": manifest["version"], "left_out": left_out}


def check(out: Path) -> list[str]:
    problems = []
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
        if z.testzip() is not None:
            problems.append("a member fails its CRC check")
        if "manifest.json" not in names:
            problems.append("manifest.json is not at the root")
        elif "key" in json.loads(z.read("manifest.json")):
            problems.append('manifest.json still has a "key" field')
        for name in names:
            if name.lower().endswith(REFUSED_SUFFIXES):
                problems.append(f"{name} must not be in the store ZIP")
            elif b"PRIVATE KEY-----" in z.read(name):
                problems.append(f"{name} contains a PEM private key")
    gate = subprocess.run([sys.executable, "-I", str(CHECK_PATHS), str(out)], capture_output=True, text=True)
    if gate.returncode != 0:
        problems.append("check-no-build-paths.py: " + (gate.stdout + gate.stderr).strip())
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    release, out = Path(argv[1]), Path(argv[2])
    if out.exists():
        print(f"package-store: {out} already exists; not overwriting it", file=sys.stderr)
        return 1
    info = build(release, out)
    problems = check(out)
    if problems:
        out.unlink()
        for problem in problems:
            print("package-store:", problem, file=sys.stderr)
        print(f"package-store: refused; {out} was deleted", file=sys.stderr)
        return 1
    with zipfile.ZipFile(out) as z:
        count = len(z.namelist())
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"{out}: version {info['version']}, {count} files, {out.stat().st_size} bytes")
    print(f"left out: {', '.join(info['left_out'])}")
    print(f"sha256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
