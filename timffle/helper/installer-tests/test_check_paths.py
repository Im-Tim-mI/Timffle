"""Offline regressions for timffle/scripts/check-no-build-paths.py with ZIP and directory input.

Run: cd timffle/helper/installer-tests && python3 -I test_check_paths.py
The checker runs as a subprocess with a planted fake home directory and account name (HOME,
LOGNAME, USER), so no fixture holds the real ones. Every fixture lives in a TemporaryDirectory.
"""
import gzip
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "check-no-build-paths.py"
FAKE_HOME = "/srv/timffle-fake-home"
FAKE_USER = "timffle-fake-user"
# A path-like use of the account name in another case, as Windows and macOS paths spell it.
USER_PATH = "C:\\Users\\TIMFFLE-FAKE-USER\\AppData"
# Repetitive text deflates well, so a planted string is invisible in the compressed bytes.
FILLER = b"synthetic build output, not a leak. " * 64


def run_check(*args):
    env = {k: v for k, v in os.environ.items() if k not in {"HOME", "LOGNAME", "USER", "LNAME", "USERNAME"}}
    env.update(HOME=FAKE_HOME, LOGNAME=FAKE_USER, USER=FAKE_USER)
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), *map(str, args)], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60,
    )


def zip_bytes(members):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in members.items():
            archive.writestr(name, data)
    return stream.getvalue()


def tar_gz_bytes(members, uname=""):
    tar = io.BytesIO()
    with tarfile.open(fileobj=tar, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size, info.uname = len(data), uname
            archive.addfile(info, io.BytesIO(data))
    return gzip.compress(tar.getvalue(), mtime=0)


class CheckerCase(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="check-paths-tests-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.dir = self.root / "downloads"
        self.dir.mkdir()

    def assert_result(self, result, code):
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        printed = (result.stdout + result.stderr).casefold()
        self.assertNotIn(FAKE_HOME.casefold(), printed)
        self.assertNotIn(FAKE_USER.casefold(), printed)


class DirectoryTests(CheckerCase):
    def write_clean_downloads(self):
        (self.dir / "helper.exe").write_bytes(b"MZ" + FILLER)
        (self.dir / "helper-macos.zip").write_bytes(zip_bytes({"helper-macos": FILLER}))
        (self.dir / "helper-linux.tar.gz").write_bytes(tar_gz_bytes({"helper-linux": FILLER}))

    def assert_leak(self, *names):
        result = run_check(self.dir)
        self.assert_result(result, 1)
        self.assertIn("home directory or user name is inside", result.stderr)
        for name in names:
            self.assertRegex(result.stderr, r"(?m)^  " + re.escape(name) + r" +\d+ occurrence\(s\)$")
        return result

    def test_clean_directory_passes(self):
        self.write_clean_downloads()
        result = run_check(self.dir)
        self.assert_result(result, 0)
        self.assertEqual(result.stdout, "check-no-build-paths: OK (3 files, 2 archive members, no home directory or user name)\n")

    def test_home_directory_in_a_raw_file(self):
        self.write_clean_downloads()
        (self.dir / "LICENSES.txt").write_bytes(FILLER + FAKE_HOME.encode() + b"/go/src/runtime/proc.go")
        self.assert_leak("LICENSES.txt")

    def test_home_directory_inside_a_zip_member(self):
        self.write_clean_downloads()
        data = zip_bytes({"helper-macos": FILLER + FAKE_HOME.encode() + b"/.cargo/registry" + FILLER})
        self.assertNotIn(FAKE_HOME.encode(), data, "fixture must hide the string from the raw scan")
        (self.dir / "helper-macos.zip").write_bytes(data)
        self.assert_leak("helper-macos.zip!helper-macos")

    def test_home_directory_inside_a_tar_gz_member(self):
        self.write_clean_downloads()
        for suffix in (".tar.gz", ".tgz"):
            with self.subTest(suffix=suffix):
                data = tar_gz_bytes({"helper-linux": FILLER + FAKE_HOME.encode() + FILLER})
                self.assertNotIn(FAKE_HOME.encode(), data)
                (self.dir / ("leaky" + suffix)).write_bytes(data)
                self.assert_leak("leaky" + suffix + "!helper-linux")
                (self.dir / ("leaky" + suffix)).unlink()

    def test_user_name_path_in_any_case(self):
        (self.dir / "helper.exe").write_bytes(FILLER + USER_PATH.encode("ascii"))
        (self.dir / "inner.tar.gz").write_bytes(tar_gz_bytes({"x": FILLER + USER_PATH.encode("ascii")}))
        self.assert_leak("helper.exe", "inner.tar.gz!x")

    def test_tar_metadata_is_scanned(self):
        # Member names, link targets and owner names are only inside the compressed stream.
        (self.dir / "named.tar.gz").write_bytes(tar_gz_bytes({"build" + FAKE_HOME + "/helper": FILLER}))
        (self.dir / "owned.tar.gz").write_bytes(tar_gz_bytes({"helper": FILLER}, uname=FAKE_USER))
        tar = io.BytesIO()
        with tarfile.open(fileobj=tar, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            link = tarfile.TarInfo("helper")
            link.type, link.linkname = tarfile.SYMTYPE, FAKE_HOME + "/bin/helper"
            archive.addfile(link)
        (self.dir / "linked.tar.gz").write_bytes(gzip.compress(tar.getvalue(), mtime=0))
        # A leaking member name is reported, but redacted.
        self.assert_leak("linked.tar.gz!helper", "named.tar.gz!build<home or user>/helper", "owned.tar.gz!helper")

    def test_leaking_file_names_are_redacted(self):
        nested = self.dir / "sub" / FAKE_HOME.lstrip("/")
        nested.mkdir(parents=True)
        (nested / "x.bin").write_bytes(FAKE_HOME.encode())
        self.assert_leak("sub<home or user>/x.bin")

    def test_nested_directories_are_scanned(self):
        self.write_clean_downloads()
        nested = self.dir / "a" / "b"
        nested.mkdir(parents=True)
        (nested / "c.bin").write_bytes(FAKE_HOME.encode())
        self.assert_leak("a/b/c.bin")

    def test_links_and_special_files_are_read_errors(self):
        self.write_clean_downloads()
        outside = self.root / "outside.bin"
        outside.write_bytes(FAKE_HOME.encode())
        (self.dir / "link.bin").symlink_to(outside)
        self.assert_result(run_check(self.dir), 2)
        (self.dir / "link.bin").unlink()
        (self.dir / "linked-dir").symlink_to(self.root, target_is_directory=True)
        self.assert_result(run_check(self.dir), 2)
        (self.dir / "linked-dir").unlink()
        os.mkfifo(self.dir / "fifo")  # must not block
        result = run_check(self.dir)
        self.assert_result(result, 2)
        self.assertIn("not a regular file", result.stderr)

    def test_corrupt_archives_are_read_errors(self):
        for name, data in (("bad.zip", b"PK\x03\x04 not a zip"), ("bad.tar.gz", b"\x1f\x8b\x08\x00 not gzip"),
                           ("cut.tar.gz", tar_gz_bytes({"x": FILLER})[:40])):
            with self.subTest(name=name):
                (self.dir / name).write_bytes(data)
                self.assert_result(run_check(self.dir), 2)
                (self.dir / name).unlink()


class ZipTests(CheckerCase):
    """The original ZIP input: same output format and exit codes as before."""

    def write_zip(self, members):
        path = self.root / "release.zip"
        path.write_bytes(zip_bytes(members))
        return path

    def test_clean_zip(self):
        path = self.write_zip({"timffle/README.txt": FILLER, "timffle/dist/": b"", "timffle/dist/a.wasm": FILLER})
        result = run_check(path)
        self.assert_result(result, 0)
        self.assertEqual(result.stdout, "check-no-build-paths: OK (2 files, no home directory or user name)\n")

    def test_leaking_zip(self):
        path = self.write_zip({"timffle/README.txt": FILLER, "timffle/dist/a.wasm": FAKE_HOME.encode() * 2 + USER_PATH.encode()})
        result = run_check(path)
        self.assert_result(result, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "check-no-build-paths: this machine's home directory or user name is inside:\n"
                         "  %-64s %d occurrence(s)\n" % ("timffle/dist/a.wasm", 3) +
                         "Rebuild with timffle/scripts/build-extension.sh, which remaps the build paths.\n")

    def test_usage_and_read_errors(self):
        not_zip = self.root / "not.zip"
        not_zip.write_bytes(b"plain text")
        for args in ((), (not_zip, not_zip), (not_zip,), (self.root / "missing.zip",), (FAKE_HOME + "/missing.zip",)):
            with self.subTest(args=args):
                self.assert_result(run_check(*args), 2)


if __name__ == "__main__":
    unittest.main()
