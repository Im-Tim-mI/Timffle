"""Validate the helper builds and create the per-system helper downloads in a NEW directory.

Usage: GO_LICENSE=$(go env GOROOT)/LICENSE python3 -I package-installers.py <helper-bin-dir> <NEW-output-dir>
<helper-bin-dir> is what build.sh makes with INCLUDE_LINUX_ARM64=1; all seven targets are required.
The output directory gets exactly the files the extension downloads (their names are fixed by the
extension): the three Windows .exe files byte for byte, a .zip per macOS target and a .tar.gz per
Linux target that each hold only the helper binary, LICENSES.txt and SHA256SUMS.txt. The archives are
reproducible (fixed times and owners, no extra fields): a rerun gives identical bytes.
No executable is launched here. Header checks are not signing, notarization or runtime test evidence,
and nothing is uploaded. If the finished directory carries this machine's home directory or user name
(timffle/scripts/check-no-build-paths.py), it is deleted again.
"""
import calendar
import gzip
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import stat
import struct
import sys
import tarfile
import zipfile

HERE = Path(__file__).absolute().parent
REPO = HERE.parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# The release packager's input checks are reused as they are: symlink-free paths, bounded non-linked
# regular files, executable headers, test-build and extension-ID markers, private-key markers.
package = load("timffle_helper_package", HERE / "package.py")
check_paths = load("timffle_check_no_build_paths", HERE.parent / "scripts" / "check-no-build-paths.py")
fail = package.fail

# build.sh target -> download name (fixed by the extension code).
DOWNLOADS = {
    "windows-amd64": "timffle-helper-windows-x64.exe",
    "windows-arm64": "timffle-helper-windows-arm64.exe",
    "windows-386": "timffle-helper-windows-x86.exe",
    "darwin-arm64": "timffle-helper-macos-arm64.zip",
    "darwin-amd64": "timffle-helper-macos-x64.zip",
    "linux-amd64": "timffle-helper-linux-x64.tar.gz",
    "linux-arm64": "timffle-helper-linux-arm64.tar.gz",
}
LICENSES = "LICENSES.txt"
SUMS = "SHA256SUMS.txt"
# The release ZIP's entry time (package.py), so reruns give identical bytes.
FIXED_TIME = (2026, 10, 15, 0, 0, 0)
FIXED_EPOCH = calendar.timegm(FIXED_TIME)
LICENSE_HEADER = """\
Timffle socket helper - licences
================================

These downloads (timffle-helper-windows-*.exe, timffle-helper-macos-*.zip,
timffle-helper-linux-*.tar.gz) are the Timffle socket helper, the small per-user
program that lets the Timffle Chrome extension open the TCP connections that Flash
games need. Timffle is an unofficial fork of Ruffle (https://ruffle.rs/) and is not
affiliated with the Ruffle project.
https://github.com/Im-Tim-mI/Timffle-Helper

The helper is Timffle's own code (Im-Tim-mI and Timffle contributors), licensed under
the MIT licence or the Apache License 2.0, at your option. It is statically linked
with the Go runtime and standard library, which are under Go's licence. It has no
other third-party dependencies. The three licence texts follow.

這些下載檔是 Timffle 連線小幫手。Timffle 是 Ruffle 的非官方分支，與 Ruffle 專案沒有隸屬關係。
小幫手以 MIT 或 Apache-2.0 授權（任選其一），並靜態連結 Go 的執行環境與標準函式庫（Go 授權）。
"""


def u16(data, offset):
    return struct.unpack_from("<H", data, offset)[0]


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def check_pe(data, arch):
    header = u32(data, 0x3C)
    sections, optional_size, characteristics = u16(data, header + 6), u16(data, header + 20), u16(data, header + 22)
    if not characteristics & 0x0002 or characteristics & 0x2000:
        fail("Windows input is not an executable image (or is a DLL).")
    optional = header + 24
    if u16(data, optional) != (0x10B if arch == "386" else 0x20B) or optional_size < 70:
        fail("Windows executable optional header mismatch.")
    if u16(data, optional + 68) != 3:
        fail("Windows input is not a console program; a double-click would show no window.")
    table = optional + optional_size
    if not sections or table + 40 * sections > len(data):
        fail("Truncated executable.")
    for i in range(sections):
        size, offset = struct.unpack_from("<II", data, table + 40 * i + 16)
        if offset + size > len(data):
            fail("Truncated executable.")


def check_macho(data, arch):
    filetype, commands, commands_size = struct.unpack_from("<III", data, 12)
    if filetype != 2:
        fail("macOS input is not an executable (MH_EXECUTE).")
    offset, end, signed = 32, 32 + commands_size, False
    if not commands or end > len(data):
        fail("Truncated executable.")
    for _ in range(commands):
        command, size = struct.unpack_from("<II", data, offset)
        if size < {0x19: 72, 0x1D: 16}.get(command, 8) or offset + size > end:
            fail("Truncated executable.")
        if command == 0x19:  # LC_SEGMENT_64: fileoff + filesize
            extent = sum(struct.unpack_from("<QQ", data, offset + 40))
        elif command == 0x1D:  # LC_CODE_SIGNATURE: dataoff + datasize
            extent, signed = sum(struct.unpack_from("<II", data, offset + 8)), True
        else:
            extent = 0
        if extent > len(data):
            fail("Truncated executable.")
        offset += size
    # Apple silicon runs no unsigned code; Go's linker signs darwin/arm64 builds ad hoc.
    if arch == "arm64" and not signed:
        fail("macOS arm64 executable has no (ad-hoc) code signature.")


def check_elf(data):
    if data[6] != 1 or u16(data, 16) != 2:
        fail("Linux input is not an executable (ET_EXEC).")
    ph, sh = struct.unpack_from("<QQ", data, 32)
    ph_size, ph_count, sh_size, sh_count = struct.unpack_from("<HHHH", data, 54)
    if not ph_count or ph_size < 56 or ph + ph_size * ph_count > len(data) or \
            sh_count and (sh_size < 64 or sh + sh_size * sh_count > len(data)):
        fail("Truncated executable.")
    for i in range(ph_count):
        kind, _, offset, _, _, size = struct.unpack_from("<IIQQQQ", data, ph + ph_size * i)
        if kind == 3:  # PT_INTERP
            fail("Linux executable is dynamically linked; the download must run on any distribution.")
        if kind == 1 and offset + size > len(data):
            fail("Truncated executable.")
    for i in range(sh_count):
        kind, _, _, offset, size = struct.unpack_from("<IQQQQ", data, sh + sh_size * i + 4)
        if kind != 8 and offset + size > len(data):  # SHT_NOBITS has no file data
            fail("Truncated executable.")


def check_executable(data, target):
    """package.py's header checks plus the whole header: a complete program of the right kind."""
    package.validate_binary(data, target)
    os_name, arch = target.split("-")
    try:
        if os_name == "windows":
            check_pe(data, arch)
        elif os_name == "darwin":
            check_macho(data, arch)
        else:
            check_elf(data)
    except (struct.error, IndexError):
        fail("Truncated executable.")
    package.reject_private_key_material(data)


def single_zip(name, data):
    info = zipfile.ZipInfo(name, date_time=FIXED_TIME)
    info.create_system = 3  # Unix, so Archive Utility applies the mode below
    info.external_attr = (stat.S_IFREG | 0o755) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        archive.writestr(info, data, compresslevel=9)
    return stream.getvalue()


def single_tar_gz(name, data):
    info = tarfile.TarInfo(name)
    info.size, info.mode, info.mtime = len(data), 0o755, FIXED_EPOCH
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    tar = io.BytesIO()
    with tarfile.open(fileobj=tar, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        archive.addfile(info, io.BytesIO(data))
    stream = io.BytesIO()
    # No file name and a zero time in the gzip header, as with gzip -n.
    with gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0, compresslevel=9) as compressed:
        compressed.write(tar.getvalue())
    return stream.getvalue()


def member_name(name):
    """The archive member: the download's name without .zip or .tar.gz."""
    return name.rsplit(".", 2 if name.endswith(".tar.gz") else 1)[0]


def unpacked(name, data):
    """The single member of a download archive, re-read and checked."""
    member = member_name(name)
    if name.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            items = archive.infolist()
            if archive.testzip() is not None or [i.filename for i in items] != [member] or items[0].extra or \
                    items[0].create_system != 3 or items[0].external_attr >> 16 != stat.S_IFREG | 0o755:
                fail("Generated ZIP check failed.")
            return archive.read(items[0])
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        items = archive.getmembers()
        if [i.name for i in items] != [member] or not items[0].isreg() or items[0].mode != 0o755 or \
                (items[0].uid, items[0].gid, items[0].uname, items[0].gname, items[0].mtime) != (0, 0, "", "", FIXED_EPOCH):
            fail("Generated tar.gz check failed.")
        return archive.extractfile(items[0]).read()


def read_license(path, limit=1024 * 1024):
    data = package.read_regular(path, limit)
    package.reject_private_key_material(data)
    return data.decode("utf-8").replace("\r\n", "\n").strip("\n") + "\n"


def licenses_text(go_license):
    go = read_license(go_license, 64 * 1024)
    if "Copyright" not in go or "The Go Authors" not in go:
        fail("GO_LICENSE does not look like Go's LICENSE file.")
    parts = [LICENSE_HEADER]
    for title, text in (
        ("Timffle socket helper: MIT License (timffle/LICENSE-MIT)", read_license(REPO / "timffle" / "LICENSE-MIT")),
        ("Timffle socket helper: Apache License 2.0 (timffle/LICENSE-APACHE)", read_license(REPO / "timffle" / "LICENSE-APACHE")),
        ("The Go runtime and standard library: Go's LICENSE", go),
    ):
        parts.append("\n\n" + "=" * 78 + "\n" + title + "\n" + "=" * 78 + "\n\n" + text)
    return "".join(parts).encode("utf-8")


def downloads(bin_dir, go_license):
    """Every output file's bytes, built and checked in memory before anything is written."""
    bin_dir = package.safe_path(bin_dir)
    if {p.name for p in bin_dir.iterdir()} != set(DOWNLOADS):
        fail("Helper targets must be exactly " + ", ".join(sorted(DOWNLOADS)) + " (build.sh with INCLUDE_LINUX_ARM64=1).")
    binaries = package.binary_assets(bin_dir)
    files = {}
    for target, name in DOWNLOADS.items():
        data = binaries["helper/bin/%s/timffle-socket-helper%s" % (target, ".exe" if target.startswith("windows-") else "")][0]
        check_executable(data, target)
        if name.endswith(".exe"):
            files[name] = data
        else:
            files[name] = (single_zip if name.endswith(".zip") else single_tar_gz)(member_name(name), data)
            if unpacked(name, files[name]) != data:
                fail("Generated archive content check failed.")
    files[LICENSES] = licenses_text(go_license)
    files[SUMS] = "".join("%s  %s\n" % (hashlib.sha256(files[n]).hexdigest(), n) for n in sorted(files)).encode("ascii")
    for data in files.values():
        package.reject_private_key_material(data)
    return files


def write_new(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        os.unlink(path)  # created exclusively above
        raise


def remove_output(out, written):
    # Only the files this run created, then the directory, which mkdir created exclusively.
    for name in written:
        try:
            os.unlink(out / name)
        except FileNotFoundError:
            pass
    try:
        os.rmdir(out)
    except OSError:
        print("Kept %s: it holds files this packager did not write." % out, file=sys.stderr)


def package_installers(bin_dir, out, go_license):
    out = package.safe_path(out)
    if out.exists() or out.is_symlink():
        fail("Output already exists; it was left unchanged.")
    if not out.parent.is_dir():
        fail("Output parent must already exist.")
    files = downloads(bin_dir, go_license)
    os.mkdir(out, 0o755)  # exclusive: an existing directory is never reused
    written = []
    try:
        for name, data in sorted(files.items()):
            write_new(out / name, data)
            written.append(name)
        if sorted(os.listdir(out)) != sorted(files) or any((out / n).read_bytes() != d for n, d in files.items()):
            fail("Written downloads differ from the checked ones.")
        if check_paths.main(["check-no-build-paths.py", str(out)]) != 0:
            fail("The downloads carry this machine's home directory or user name; the output directory was deleted.")
    except BaseException:
        remove_output(out, written)
        raise
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip())
    go_license = os.environ.get("GO_LICENSE")
    if not go_license:
        sys.exit("Package refused: set GO_LICENSE to Go's LICENSE file (the helper links the Go standard library).")
    try:
        out = package_installers(sys.argv[1], sys.argv[2], go_license)
    except (OSError, ValueError, UnicodeError, zipfile.BadZipFile, tarfile.TarError) as error:
        sys.exit("Package refused: " + str(error))
    print("Created helper downloads:", out)
    print("Cross-compiled and header-checked only: not signed, notarized or runtime-tested; nothing was uploaded.")


if __name__ == "__main__":
    main()
