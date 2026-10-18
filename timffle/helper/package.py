"""Validate inputs and create a NEW extension/helper ZIP; never overwrite a release.

Usage: GO_LICENSE=$(go env GOROOT)/LICENSE python3 -I package.py <extension.zip> <helper-bin-dir> <extension-id> <NEW-out.zip>
No executable is launched here. Cross-builds are NOT runtime test evidence.
The ZIP also carries the licence texts (LICENSES/): Ruffle's (with its third-party list), Timffle's,
rust-flash-lso's and Go's (statically linked into the helper; GO_LICENSE names that file).
"""
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import tempfile
import unicodedata
import zipfile

ROOT = "timffle"
HERE = Path(__file__).absolute().parent
REPO = HERE.parent.parent
# Release ZIP name -> source file (relative to the repository root). The Go licence is added from GO_LICENSE.
LICENSE_FILES = {
    "NOTICE.md": "NOTICE.md",
    "LICENSES/Timffle-LICENSE-MIT": "timffle/LICENSE-MIT",
    "LICENSES/Timffle-LICENSE-APACHE": "timffle/LICENSE-APACHE",
    "LICENSES/Ruffle-LICENSE.md": "LICENSE.md",
    "LICENSES/Ruffle-web-LICENSE.md": "web/LICENSE.md",
    "LICENSES/rust-flash-lso-LICENSE": "vendor/rust-flash-lso/LICENSE",
}
EXPECTED_ID = "eandddnbchclalbjkhfelhjhpijifcog"
REQUIRED_TARGETS = {"windows-amd64", "windows-arm64", "windows-386", "darwin-amd64", "darwin-arm64", "linux-amd64"}
OPTIONAL_TARGETS = {"linux-arm64"}
# Thin launchers: the installer itself is built into the helper binary.
INSTALLERS = {"install-windows.cmd", "uninstall-windows.cmd", "install-macos.command", "uninstall-macos.command", "install-linux.sh", "uninstall-linux.sh"}
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
# Match PEM private-key labels generically (PKCS#8, encrypted, OpenSSH,
# algorithm-specific, and future labels), even inside binary/text payloads.
# RFC 7468 label characters are printable ASCII, separated by space/hyphen;
# do not restrict the prefix to a fixed algorithm list or uppercase letters.
PRIVATE_KEY_MARKER = re.compile(
    rb"-----BEGIN (?:[\x21-\x2c\x2e-\x7e](?:[ -]?[\x21-\x2c\x2e-\x7e])* )?PRIVATE KEY-----"
)


def fail(message):
    raise ValueError(message)


def reject_private_key_material(data):
    if PRIVATE_KEY_MARKER.search(data):
        fail("Private key material is forbidden.")


def safe_path(path):
    path = Path(os.path.abspath(path))
    for part in [*reversed(path.parents), path]:
        if part.is_symlink():
            fail("Symlink input/output path refused.")
    return path


def read_regular(path, limit=MAX_FILE):
    path = safe_path(path)
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > limit:
            fail("Expected a bounded, non-linked regular input file.")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(limit + 1)
        if len(data) > limit:
            fail("Input file too large.")
        return data
    finally:
        os.close(fd)


def extension_id_from_manifest(manifest):
    if not isinstance(manifest, dict) or manifest.get("manifest_version") != 3:
        fail("Expected Manifest V3.")
    key = manifest.get("key")
    if not isinstance(key, str) or len(key) > 8192:
        fail("Manifest must contain its stable public key.")
    try:
        public_key = base64.b64decode(key, validate=True)
    except ValueError:
        fail("Invalid manifest public key encoding.")
    if len(public_key) < 32 or public_key[0] != 0x30:
        fail("Invalid manifest DER public key.")
    digest = hashlib.sha256(public_key).hexdigest()[:32]
    return "".join(chr(ord("a") + int(nibble, 16)) for nibble in digest)


def allowed_asset(name, directory=False):
    parts = PurePosixPath(name).parts
    if directory:
        return (name in {"_locales", "css", "dist", "fonts", "images"} or
                re.fullmatch(r"_locales/[A-Za-z_@-]+", name) is not None)
    if len(parts) == 1:
        return name in {"manifest.json", "onboard.html", "options.html", "player.html", "popup.html", "prompt.html"}
    if re.fullmatch(r"_locales/[A-Za-z_@-]+/messages[.]json", name):
        return True
    if len(parts) != 2:
        return False
    folder, leaf = parts
    if folder == "dist":
        return bool(re.fullmatch(r"[A-Za-z0-9_-]+[.](js|wasm)", leaf) or leaf in {"4399_rules.json", "LICENSE_APACHE", "LICENSE_MIT", "README.md"})
    if folder == "css":
        return bool(re.fullmatch(r"[A-Za-z0-9_-]+[.]css", leaf))
    if folder == "fonts":
        return bool(re.fullmatch(r"[A-Za-z0-9_-]+[.](woff|woff2|ttf)", leaf))
    if folder == "images":
        return bool(re.fullmatch(r"[A-Za-z0-9_-]+[.](png|svg|jpg|jpeg|webp|gif)", leaf))
    return False


def extension_assets(path, supplied_id):
    # A regular input descriptor closes the symlink race at the archive leaf.
    import io
    source = read_regular(path, MAX_TOTAL)
    assets, seen, total = {}, set(), 0
    with zipfile.ZipFile(io.BytesIO(source)) as archive:
        if len(archive.infolist()) > 2048:
            fail("Unexpectedly many extension entries.")
        for item in archive.infolist():
            name = item.filename
            normalized = unicodedata.normalize("NFC", name.rstrip("/")).casefold()
            if not name or "\\" in name or ":" in name or name.startswith("/") or any(ord(c) < 32 for c in name) or any(p in ("", ".", "..") for p in name.rstrip("/").split("/")):
                fail("Unsafe extension archive path.")
            if normalized in seen:
                fail("Duplicate/case-colliding extension entry.")
            seen.add(normalized)
            mode = item.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if item.flag_bits & 1 or kind not in (0, stat.S_IFREG, stat.S_IFDIR) or (kind == stat.S_IFDIR) != item.is_dir() and kind != 0:
                fail("Encrypted, linked, or special archive entries are not allowed.")
            if not allowed_asset(name.rstrip("/"), item.is_dir()):
                fail("Unexpected extension asset (private/config/profile entries are never packaged).")
            if item.is_dir():
                continue
            total += item.file_size
            if item.file_size > MAX_FILE or total > MAX_TOTAL:
                fail("Extension archive exceeds size limits.")
            data = archive.read(item)  # validates CRC
            if len(data) != item.file_size:
                fail("Invalid extension entry size.")
            reject_private_key_material(data)
            assets[name] = data
    try:
        manifest = json.loads(assets["manifest.json"])
    except (KeyError, ValueError, UnicodeError):
        fail("Missing/invalid root manifest.json.")
    if extension_id_from_manifest(manifest) != supplied_id:
        fail("Extension manifest key does not match the supplied extension ID.")
    if "nativeMessaging" not in manifest.get("permissions", []):
        fail("Extension is missing the nativeMessaging permission.")
    return assets


def validate_binary(data, target):
    if len(data) < 64:
        fail("Truncated executable.")
    os_name, arch = target.split("-")
    if os_name == "windows":
        offset = struct.unpack_from("<I", data, 0x3C)[0]
        if data[:2] != b"MZ" or offset + 6 > len(data) or data[offset:offset + 4] != b"PE\0\0":
            fail("Expected a Windows PE executable.")
        machine = struct.unpack_from("<H", data, offset + 4)[0]
        if machine != {"amd64": 0x8664, "arm64": 0xAA64, "386": 0x14C}[arch]:
            fail("Windows executable architecture mismatch.")
    elif os_name == "linux":
        if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", data, 18)[0] != {"amd64": 62, "arm64": 183}[arch]:
            fail("Linux executable architecture mismatch.")
    elif os_name == "darwin":
        if data[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", data, 4)[0] != {"amd64": 0x01000007, "arm64": 0x0100000C}[arch]:
            fail("macOS executable architecture mismatch.")
    if b"localtest" in data or b"TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE" in data:
        fail("A test/private-network-bypass executable must not be packaged.")
    if ("chrome-extension://" + EXPECTED_ID + "/").encode("ascii") not in data:
        fail("Helper does not accept this package's extension ID.")


def binary_assets(bin_dir):
    bin_dir = safe_path(bin_dir)
    targets = set(p.name for p in bin_dir.iterdir())
    if not REQUIRED_TARGETS <= targets or not targets <= REQUIRED_TARGETS | OPTIONAL_TARGETS:
        fail("Helper targets must include Windows amd64/arm64/386, macOS amd64/arm64 and Linux amd64; only Linux arm64 is optional.")
    assets = {}
    for target in sorted(targets):
        folder = safe_path(bin_dir / target)
        name = "timffle-socket-helper" + (".exe" if target.startswith("windows-") else "")
        if not folder.is_dir() or {p.name for p in folder.iterdir()} != {name}:
            fail("Unexpected helper directory entries; configs/private files are forbidden.")
        path = folder / name
        data = read_regular(path)
        if not path.stat().st_mode & stat.S_IXUSR:
            fail("Build input is missing its executable bit.")
        validate_binary(data, target)
        assets["helper/bin/" + target + "/" + name] = (data, True)
    return assets


def add(z, arcname, data, executable=False):
    info = zipfile.ZipInfo(arcname, date_time=(2026, 10, 15, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, data)


def license_assets(go_license):
    assets = {}
    for name, rel in LICENSE_FILES.items():
        assets[name] = (read_regular(REPO / rel, 1024 * 1024), False)
    data = read_regular(go_license, 64 * 1024)
    if b"Copyright" not in data or b"The Go Authors" not in data:
        fail("GO_LICENSE does not look like Go's LICENSE file.")
    assets["LICENSES/Go-LICENSE"] = (data, False)
    return assets


def package(extension_zip, bin_dir, extension_id, out, source_dir=HERE, licenses=None):
    if not re.fullmatch(r"[a-p]{32}", extension_id) or extension_id != EXPECTED_ID:
        fail("Unexpected extension ID for the shared v2 contract.")
    out = safe_path(out)
    if out.exists():
        fail("Output already exists; old destination was preserved.")
    if not out.parent.is_dir():
        fail("Output parent must already exist.")
    assets = {"extension/" + name: (data, False) for name, data in extension_assets(extension_zip, extension_id).items()}
    assets.update(binary_assets(bin_dir))
    installers = safe_path(Path(source_dir) / "installers")
    if {p.name for p in installers.iterdir()} != INSTALLERS:
        fail("Unexpected/missing installer entries; refusing to sweep a directory into the package.")
    for name in sorted(INSTALLERS):
        data = read_regular(installers / name, 512 * 1024)
        if name.endswith(".cmd"):
            # cmd.exe needs CRLF; keep batch files ASCII so no code page can garble them.
            data.decode("ascii")
            data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        assets["helper/" + name] = (data, name.endswith((".sh", ".command")))
    readme = read_regular(Path(source_dir) / "README.zh-TW.txt", 128 * 1024).decode("utf-8-sig")
    assets["README.txt"] = (b"\xef\xbb\xbf" + readme.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"), False)
    if licenses:
        assets.update(licenses)
    # Scan every final payload, including normalized launchers and README,
    # before creating a ZIP. Header/allowlist checks alone do not detect keys.
    for data, _ in assets.values():
        reject_private_key_material(data)
    fd, temp_name = tempfile.mkstemp(prefix=".timffle-package-", suffix=".zip", dir=out.parent)
    try:
        with os.fdopen(fd, "w+b") as stream:
            with zipfile.ZipFile(stream, "w") as z:
                for name, (data, executable) in sorted(assets.items()):
                    add(z, ROOT + "/" + name, data, executable)
            stream.flush()
            os.fsync(stream.fileno())
        with zipfile.ZipFile(temp_name) as z:
            if z.testzip() is not None or len(z.infolist()) != len(assets):
                fail("Generated ZIP integrity check failed.")
            for name, (data, executable) in assets.items():
                item = z.getinfo(ROOT + "/" + name)
                expected = stat.S_IFREG | (0o755 if executable else 0o644)
                if item.create_system != 3 or item.external_attr >> 16 != expected or z.read(item) != data:
                    fail("Generated ZIP content/permissions check failed.")
        # Atomic, exclusive publication: link never replaces an old output.
        safe_path(out)
        os.link(temp_name, out, follow_symlinks=False)
    finally:
        os.unlink(temp_name)
    return out


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__.strip())
    go_license = os.environ.get("GO_LICENSE")
    if not go_license:
        sys.exit("Package refused: set GO_LICENSE to Go's LICENSE file (the helper links the Go standard library).")
    try:
        out = package(*sys.argv[1:], licenses=license_assets(go_license))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        sys.exit("Package refused: " + str(error))
    print("Created validated ZIP:", out)
    print("ZIP/header validation is not signing, browser integration, game-login, or cross-platform runtime evidence.")


if __name__ == "__main__":
    main()
