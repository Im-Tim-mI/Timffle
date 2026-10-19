"""Regressions for the helper downloads: package-installers.py and package-helper-installers.sh.

Run: cd timffle/helper/installer-tests && python3 -I test_installers.py
PackagerTests use tiny synthetic PE/Mach-O/ELF stubs (validation fixtures, never executed); every
fixture lives in a TemporaryDirectory. RealBuildTests are skipped without a Go toolchain (GO or go on
PATH): they cross-compile and package with timffle/scripts/package-helper-installers.sh, extract the
linux-x64 tar.gz and run the extracted helper without arguments under a throw-away HOME and XDG
directories (never the real ones), then --uninstall. With wine and wineserver on PATH they also run
the Windows x64 download in a fresh temporary Wine prefix (test_windows_registry.py). Their files
are made under the system temporary directory (set TMPDIR to put them elsewhere).
"""
import calendar
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import platform
import re
import select
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest import mock
import zipfile


HERE = Path(__file__).resolve().parent
HELPER = HERE.parent
WRAPPER = HELPER.parent / "scripts" / "package-helper-installers.sh"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


installers = load("socket_helper_installers", HELPER / "package-installers.py")

# Fixed by the extension code: the test pins them instead of reading the packager's table.
NAMES = {
    "windows-amd64": "timffle-helper-windows-x64.exe",
    "windows-arm64": "timffle-helper-windows-arm64.exe",
    "windows-386": "timffle-helper-windows-x86.exe",
    "darwin-arm64": "timffle-helper-macos-arm64.zip",
    "darwin-amd64": "timffle-helper-macos-x64.zip",
    "linux-amd64": "timffle-helper-linux-x64.tar.gz",
    "linux-arm64": "timffle-helper-linux-arm64.tar.gz",
}
OUTPUT_NAMES = sorted([*NAMES.values(), "LICENSES.txt", "SHA256SUMS.txt"])
FIXED_EPOCH = calendar.timegm((2026, 10, 15, 0, 0, 0))
ORIGIN = b"chrome-extension://eandddnbchclalbjkhfelhjhpijifcog/"
GO_LICENSE_TEXT = "Copyright 2009 The Go Authors.\n\nSynthetic licence fixture, not Go's licence text.\n"
PE_MACHINES = {"amd64": 0x8664, "arm64": 0xAA64, "386": 0x14C}
MACHO_CPUS = {"amd64": 0x01000007, "arm64": 0x0100000C}
ELF_MACHINES = {"amd64": 62, "arm64": 183}
SIZE = 0x300  # every stub's last section/segment ends exactly at the end of the file, as in Go builds


def stub(target, **change):
    """A minimal, structurally complete executable header for target, with the extension's origin."""
    os_name, arch = target.split("-")
    data = bytearray(SIZE)
    if os_name == "windows":
        optional_size = 224 if arch == "386" else 240
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 0x80)
        data[0x80:0x84] = b"PE\0\0"
        struct.pack_into("<HHIIIHH", data, 0x84, change.get("machine", PE_MACHINES[arch]), 1, 0, 0, 0,
                         optional_size, change.get("characteristics", 0x22))
        struct.pack_into("<H", data, 0x98, change.get("magic", 0x10B if arch == "386" else 0x20B))
        struct.pack_into("<H", data, 0x98 + 68, change.get("subsystem", 3))
        struct.pack_into("<8sIIII", data, 0x98 + optional_size, b".text", 0x100, 0x1000, 0x100, 0x200)
        origin = 0x200
    elif os_name == "darwin":
        commands = [struct.pack("<II16sQQQQIIII", 0x19, 72, b"__TEXT", 0, 0x1000, 0, SIZE, 5, 5, 0, 0)]
        if change.get("signed", True):
            commands.append(struct.pack("<IIII", 0x1D, 16, SIZE - 0x10, 0x10))
        body = b"".join(commands)
        struct.pack_into("<IIIIIIII", data, 0, 0xFEEDFACF, change.get("cpu", MACHO_CPUS[arch]), 0,
                         change.get("filetype", 2), len(commands), len(body), 0, 0)
        data[32:32 + len(body)] = body
        origin = 0x100
    else:
        data[:7] = b"\x7fELF\x02\x01\x01"
        struct.pack_into("<HHI", data, 16, change.get("e_type", 2), change.get("machine", ELF_MACHINES[arch]), 1)
        struct.pack_into("<QQ", data, 32, 64, 0x200)
        struct.pack_into("<HHHHHH", data, 52, 64, 56, 1, 64, 2, 1)
        struct.pack_into("<IIQQQQQQ", data, 64, change.get("p_type", 1), 5, 0, 0x400000, 0x400000, 0x200, 0x200, 0x1000)
        struct.pack_into("<IIQQQQ", data, 0x240, 0, 1, 0, 0, 0x280, SIZE - 0x280)
        origin = 0x100
    if change.get("origin", True):
        data[origin:origin + len(ORIGIN)] = ORIGIN
    return bytes(data)


class PackagerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="helper-downloads-tests-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.paths = {}
        for target in NAMES:
            folder = self.bin / target
            folder.mkdir(parents=True)
            path = folder / ("timffle-socket-helper" + (".exe" if target.startswith("windows-") else ""))
            path.write_bytes(stub(target))
            path.chmod(0o755)
            self.paths[target] = path
        self.go_license = self.root / "GO-LICENSE"
        self.go_license.write_text(GO_LICENSE_TEXT)
        self.out = self.root / "downloads"

    def make(self, out=None):
        # The path check's report goes to self.printed instead of the test log.
        self.printed = io.StringIO()
        with contextlib.redirect_stdout(self.printed), contextlib.redirect_stderr(self.printed):
            return installers.package_installers(self.bin, self.out if out is None else out, self.go_license)

    def refused(self, pattern, out=None):
        out = self.out if out is None else out
        with self.assertRaisesRegex(ValueError, pattern):
            self.make(out)
        self.assertFalse(out.exists() or out.is_symlink(), "a refused run left its output")

    def cli(self, *args, env=None):
        environment = dict(os.environ, GO_LICENSE=str(self.go_license))
        environment.update(env or {})
        return subprocess.run([sys.executable, "-I", str(HELPER / "package-installers.py"), *map(str, args)],
                              env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)

    def test_exact_output_names(self):
        self.assertEqual(self.make(), self.out)
        self.assertEqual(sorted(os.listdir(self.out)), OUTPUT_NAMES)

    def test_windows_downloads_are_the_binaries_byte_for_byte(self):
        self.make()
        for target in ("windows-amd64", "windows-arm64", "windows-386"):
            self.assertEqual((self.out / NAMES[target]).read_bytes(), self.paths[target].read_bytes())

    def test_macos_zips_hold_one_executable_entry(self):
        self.make()
        for target in ("darwin-arm64", "darwin-amd64"):
            with self.subTest(target=target), zipfile.ZipFile(self.out / NAMES[target]) as archive:
                self.assertIsNone(archive.testzip())
                [item] = archive.infolist()
                self.assertEqual(item.filename, NAMES[target][:-len(".zip")])
                self.assertFalse(item.is_dir())
                self.assertEqual((item.create_system, item.external_attr >> 16), (3, stat.S_IFREG | 0o755))
                self.assertEqual((item.extra, item.comment, archive.comment, item.flag_bits), (b"", b"", b"", 0))
                self.assertEqual((item.date_time, item.compress_type), ((2026, 10, 15, 0, 0, 0), zipfile.ZIP_DEFLATED))
                self.assertEqual(archive.read(item), self.paths[target].read_bytes())

    def test_linux_tar_gz_hold_one_executable_member(self):
        self.make()
        for target in ("linux-amd64", "linux-arm64"):
            path = self.out / NAMES[target]
            with self.subTest(target=target), tarfile.open(path, "r:gz") as archive:
                [item] = archive.getmembers()
                self.assertEqual(item.name, NAMES[target][:-len(".tar.gz")])
                self.assertTrue(item.isreg())
                self.assertEqual((item.mode, item.uid, item.gid, item.uname, item.gname, item.mtime),
                                 (0o755, 0, 0, "", "", FIXED_EPOCH))
                self.assertEqual((item.pax_headers, archive.pax_headers), ({}, {}))
                self.assertEqual(archive.extractfile(item).read(), self.paths[target].read_bytes())
            # gzip header: no stored file name (FLG 0) and no time (MTIME 0).
            self.assertEqual(path.read_bytes()[:8], b"\x1f\x8b\x08\x00\x00\x00\x00\x00")

    def test_rerun_gives_identical_bytes(self):
        self.make()
        again = self.make(self.root / "again")
        for name in OUTPUT_NAMES:
            with self.subTest(name=name):
                self.assertEqual((again / name).read_bytes(), (self.out / name).read_bytes())

    def test_sha256sums_cover_every_other_file(self):
        self.make()
        lines = (self.out / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines()
        names = []
        for line in lines:
            match = re.fullmatch(r"([0-9a-f]{64})  (\S+)", line)
            self.assertIsNotNone(match, line)
            names.append(match.group(2))
            self.assertEqual(match.group(1), hashlib.sha256((self.out / match.group(2)).read_bytes()).hexdigest())
        self.assertEqual(names, sorted(set(OUTPUT_NAMES) - {"SHA256SUMS.txt"}))

    def test_licenses_hold_the_three_licence_texts(self):
        self.make()
        text = (self.out / "LICENSES.txt").read_text(encoding="utf-8")
        self.assertIn("https://github.com/Im-Tim-mI/Timffle-Helper", text)
        self.assertIn("unofficial fork of Ruffle", text)
        positions = []
        for source in (HELPER.parent / "LICENSE-MIT", HELPER.parent / "LICENSE-APACHE", self.go_license):
            with self.subTest(source=source.name):
                licence = source.read_text(encoding="utf-8").replace("\r\n", "\n").strip("\n")
                self.assertEqual(text.count(licence), 1)
                positions.append(text.index(licence))
        self.assertEqual(positions, sorted(positions))

    def test_existing_output_is_left_unchanged(self):
        self.out.mkdir()
        self.refused_existing()
        (self.out / "old.txt").write_text("old")
        self.refused_existing()
        self.assertEqual(os.listdir(self.out), ["old.txt"])

    def refused_existing(self):
        with self.assertRaisesRegex(ValueError, "Output already exists"):
            self.make()
        self.assertTrue(self.out.is_dir())

    def test_symlink_paths_are_refused(self):
        real = self.root / "real-bin"
        self.bin.rename(real)
        self.bin.symlink_to(real, target_is_directory=True)
        self.refused("Symlink")
        self.bin.unlink()
        real.rename(self.bin)
        folder = self.bin / "linux-amd64"
        moved = self.root / "moved-linux"
        folder.rename(moved)
        folder.symlink_to(moved, target_is_directory=True)
        self.refused("Symlink")
        folder.unlink()
        moved.rename(folder)
        binary = self.paths["linux-arm64"]
        moved = self.root / "moved-binary"
        binary.rename(moved)
        binary.symlink_to(moved)
        self.refused("Symlink")
        binary.unlink()
        moved.rename(binary)
        parent = self.root / "linked-parent"
        parent.symlink_to(self.root, target_is_directory=True)
        self.refused("Symlink", parent / "downloads")
        self.out.symlink_to(self.root / "nowhere")
        with self.assertRaisesRegex(ValueError, "Symlink"):
            self.make()
        self.assertFalse((self.root / "nowhere").exists())

    def test_hardlinked_input_is_refused(self):
        os.link(self.paths["darwin-amd64"], self.root / "second-name")
        self.refused("non-linked regular input")

    def test_every_target_is_required_and_nothing_else(self):
        shutil.rmtree(self.paths["linux-arm64"].parent)
        self.refused("must be exactly")
        (self.bin / "linux-arm64").mkdir()
        (self.bin / "linux-arm64" / "timffle-socket-helper").write_bytes(stub("linux-arm64"))
        (self.bin / "linux-arm64" / "timffle-socket-helper").chmod(0o755)
        (self.bin / "freebsd-amd64").mkdir()
        self.refused("must be exactly")
        (self.bin / "freebsd-amd64").rmdir()
        (self.paths["windows-386"].parent / "config.json").write_text("{}")
        self.refused("Unexpected helper directory entries")

    def test_wrong_architecture_is_refused(self):
        for target, path in self.paths.items():
            os_name, arch = target.split("-")
            other = {"windows": "arm64" if arch != "arm64" else "amd64"}.get(os_name, "arm64" if arch == "amd64" else "amd64")
            with self.subTest(target=target):
                clean = path.read_bytes()
                path.write_bytes(stub(os_name + "-" + other))
                self.refused("architecture mismatch")
                path.write_bytes(clean)

    def test_wrong_kind_of_executable_is_refused(self):
        for target, change, pattern in (
            ("windows-amd64", {"characteristics": 0x2022}, "DLL"),
            ("windows-arm64", {"characteristics": 0x0020}, "not an executable image"),
            ("windows-386", {"subsystem": 2}, "not a console program"),
            ("windows-amd64", {"magic": 0x10B}, "optional header"),
            ("darwin-amd64", {"filetype": 6}, "MH_EXECUTE"),
            ("darwin-arm64", {"signed": False}, "code signature"),
            ("linux-amd64", {"e_type": 3}, "ET_EXEC"),
            ("linux-arm64", {"p_type": 3}, "dynamically linked"),
            ("linux-amd64", {"origin": False}, "extension ID"),
        ):
            with self.subTest(target=target, change=change):
                clean = self.paths[target].read_bytes()
                self.paths[target].write_bytes(stub(target, **change))
                self.refused(pattern)
                self.paths[target].write_bytes(clean)
        # Intel Macs run unsigned code; only arm64 needs the ad-hoc signature.
        self.paths["darwin-amd64"].write_bytes(stub("darwin-amd64", signed=False))
        self.make()

    def test_truncated_input_is_refused(self):
        for target, path in self.paths.items():
            clean = path.read_bytes()
            for size, pattern in ((SIZE - 0x40, "Truncated executable"), (63, "Truncated executable"), (0x90, "")):
                with self.subTest(target=target, size=size):
                    path.write_bytes(clean[:size])
                    self.refused(pattern)
            path.write_bytes(clean)

    def test_private_key_markers_are_refused(self):
        marker = b"-----BEGIN OPENSSH PRIVATE KEY-----\nSYNTHETIC-NOT-A-KEY\n"
        for target, path in self.paths.items():
            with self.subTest(target=target):
                clean = path.read_bytes()
                path.write_bytes(clean + marker)
                self.refused("Private key material")
                path.write_bytes(clean)
        self.go_license.write_bytes(GO_LICENSE_TEXT.encode() + marker)
        self.refused("Private key material")

    def test_test_builds_and_missing_execute_bits_are_refused(self):
        path = self.paths["linux-amd64"]
        clean = path.read_bytes()
        path.write_bytes(clean + b"localtest")
        self.refused("test/private-network-bypass")
        path.write_bytes(clean)
        path.chmod(0o644)
        self.refused("missing its executable bit")

    def test_go_license_must_look_like_go_licence(self):
        self.go_license.write_text("Some other licence.\n")
        self.refused("GO_LICENSE does not look like")

    def test_planted_home_directory_deletes_the_output(self):
        fake_home = "/srv/timffle-planted-home"
        path = self.paths["windows-amd64"]
        path.write_bytes(path.read_bytes() + fake_home.encode() + b"/go/src/runtime/proc.go")
        result = self.cli(self.bin, self.out, env={"HOME": fake_home})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.out.exists())
        self.assertIn("timffle-helper-windows-x64.exe", result.stderr)
        self.assertIn("output directory was deleted", result.stderr)
        self.assertNotIn(fake_home, result.stdout + result.stderr)
        with mock.patch.dict(os.environ, {"HOME": fake_home}):
            self.refused("home directory or user name")
        self.assertIn("timffle-helper-windows-x64.exe", self.printed.getvalue())

    def test_failed_write_removes_only_its_own_files(self):
        original = installers.write_new
        calls = []

        def racing(path, data):
            calls.append(path.name)
            if len(calls) == 3:
                path.write_text("not ours")  # another process got one of the names first
            original(path, data)

        with mock.patch.object(installers, "write_new", side_effect=racing):
            with self.assertRaises(FileExistsError):
                self.make()
        # That file and the directory stay; the two files this run wrote are gone.
        self.assertEqual(os.listdir(self.out), [calls[2]])
        self.assertEqual((self.out / calls[2]).read_text(), "not ours")
        self.assertIn("did not write", self.printed.getvalue())
        (self.out / calls[2]).unlink()
        self.out.rmdir()
        # A failure while writing removes the half-written file, then the directory.
        with mock.patch.object(installers.os, "fsync", side_effect=OSError("synthetic write failure")):
            with self.assertRaisesRegex(OSError, "synthetic write failure"):
                self.make()
        self.assertFalse(self.out.exists())

    def test_command_line(self):
        result = self.cli(self.bin, self.out)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Created helper downloads:", result.stdout)
        self.assertIn("check-no-build-paths: OK (9 files, 4 archive members", result.stdout)
        self.assertEqual(sorted(os.listdir(self.out)), OUTPUT_NAMES)
        result = self.cli(self.bin, self.out)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Output already exists", result.stderr)
        for args, env in (((self.bin,), {}), ((self.bin, self.root / "x", "extra"), {}), ((self.bin, self.root / "y"), {"GO_LICENSE": ""})):
            with self.subTest(args=args, env=env):
                result = self.cli(*args, env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "x").exists() or (self.root / "y").exists())


def find_go():
    go = os.environ.get("GO") or shutil.which("go")
    return str(Path(go).absolute()) if go else None


def read_until(stream, marker, timeout):
    """Read a child's output until marker appears; returns everything read."""
    output, deadline = b"", time.monotonic() + timeout
    while marker not in output:
        if time.monotonic() > deadline:
            raise AssertionError("timed out waiting for %r in %r" % (marker, output))
        if select.select([stream], [], [], 0.2)[0]:
            chunk = os.read(stream.fileno(), 65536)
            if not chunk:
                raise AssertionError("output ended before %r: %r" % (marker, output))
            output += chunk
    return output


class RealBuildTests(unittest.TestCase):
    """A real cross-compile and packaging run; the Linux download is installed into a throw-away HOME."""

    @classmethod
    def setUpClass(cls):
        go = find_go()
        if go is None:
            raise unittest.SkipTest("no Go toolchain (set GO or put go on PATH)")
        temporary = tempfile.TemporaryDirectory(prefix="timffle-helper-downloads-")
        cls.addClassCleanup(temporary.cleanup)
        cls.root = Path(temporary.name)
        env = {k: v for k, v in os.environ.items() if k not in {"GOFLAGS", "GOWORK"}}
        env["GO"] = go
        build = cls.root / "build"
        result = subprocess.run(["sh", str(WRAPPER), str(build)], env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=1800)
        if result.returncode != 0:
            raise AssertionError("package-helper-installers.sh failed:\n" + result.stdout)
        cls.log, cls.bin, cls.out = result.stdout, build / "installers-bin", build / "installers"
        cls.go_license = subprocess.run([go, "env", "GOROOT"], env=env, stdout=subprocess.PIPE, text=True, check=True).stdout.strip() + "/LICENSE"

    def test_wrapper_output_and_files(self):
        self.assertEqual(sorted(os.listdir(self.out)), OUTPUT_NAMES)
        self.assertIn("check-no-build-paths: OK (9 files, 4 archive members", self.log)
        self.assertIn((self.out / "SHA256SUMS.txt").read_text(), self.log)
        for name in OUTPUT_NAMES:
            self.assertIn(name, self.log)

    def test_downloads_match_the_build_and_are_reproducible(self):
        for target, name in NAMES.items():
            binary = self.bin / target / ("timffle-socket-helper" + (".exe" if target.startswith("windows-") else ""))
            data = (self.out / name).read_bytes()
            if name.endswith((".zip", ".tar.gz")):
                data = installers.unpacked(name, data)
            self.assertEqual(data, binary.read_bytes(), name)
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            again = installers.package_installers(self.bin, self.root / "again", self.go_license)
        self.assertIn("check-no-build-paths: OK", printed.getvalue())
        for name in OUTPUT_NAMES:
            self.assertEqual((again / name).read_bytes(), (self.out / name).read_bytes(), name)

    @unittest.skipUnless(sys.platform.startswith("linux") and platform.machine() == "x86_64", "runs the linux-x64 download")
    def test_linux_x64_download_installs_without_arguments(self):
        work = Path(tempfile.mkdtemp(prefix="linux-x64-", dir=self.root))
        extracted = work / "extracted"
        extracted.mkdir()
        if shutil.which("tar"):
            subprocess.run(["tar", "-xzf", str(self.out / NAMES["linux-amd64"]), "-C", str(extracted)], check=True, timeout=60)
        else:
            with tarfile.open(self.out / NAMES["linux-amd64"], "r:gz") as archive:
                archive.extractall(extracted, filter="data")
        self.assertEqual(os.listdir(extracted), ["timffle-helper-linux-x64"])
        binary = extracted / "timffle-helper-linux-x64"
        self.assertEqual(stat.S_IMODE(binary.stat().st_mode) & 0o111, 0o111)
        home = work / "home"
        home.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_") and k not in {"HOME", "CHROME_CONFIG_HOME"}}
        env.update(HOME=str(home), XDG_DATA_HOME=str(home / "data"), XDG_CONFIG_HOME=str(home / "config"))
        installed = home / "data" / "timffle-socket-helper" / "timffle-socket-helper"
        manifest = home / "config" / "google-chrome" / "NativeMessagingHosts" / "timffle_socket_helper.json"

        def run(*args, **kwargs):
            return subprocess.run([str(binary), *args], cwd=work, env=env, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, timeout=60, **kwargs)

        version = run("--version", stdin=subprocess.DEVNULL).stdout.decode().split()[-1]

        def check_installed(output):
            self.assertIn("Timffle socket helper %s" % version, output)
            self.assertIn("只替目前的使用者安裝，不需要系統管理員權限", output)
            self.assertIn("Socket helper %s installed:" % version, output)
            self.assertIn("run this file with --uninstall", output)
            self.assertEqual(installed.read_bytes(), binary.read_bytes())
            self.assertEqual(json.loads(manifest.read_text()), {
                "name": "timffle_socket_helper", "description": "Timffle socket helper", "path": str(installed),
                "type": "stdio", "allowed_origins": [ORIGIN.decode()],
            })
            receipt = json.loads((installed.parent / "install.json").read_text())
            self.assertEqual((receipt["version"], receipt["binary"]), (version, str(installed)))

        def uninstall():
            result = run("--uninstall", stdin=subprocess.DEVNULL)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("removed", result.stdout.decode())
            self.assertFalse(installed.parent.exists() or manifest.exists())

        # Started from a terminal with stdin from /dev/null (a character device: the
        # Enter prompt reads end-of-file at once, so it cannot hang).
        result = run(stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 0, result.stdout)
        check_installed(result.stdout.decode())
        uninstall()

        # stdin a pipe that stays open: no prompt, and stdin is never read.
        process = subprocess.Popen([str(binary)], cwd=work, env=env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            self.assertEqual(process.wait(timeout=60), 0)
            output = process.stdout.read().decode()
        finally:
            process.stdin.close()
            process.stdout.close()
        check_installed(output)
        self.assertNotIn("Press Enter", output)
        uninstall()

        # A real terminal (a double-click in Finder opens one): waits for Enter.
        master, slave = os.openpty()
        process = subprocess.Popen([str(binary)], cwd=work, env=env, stdin=slave,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        os.close(slave)
        try:
            output = read_until(process.stdout, "Press Enter to close. ".encode(), 60)
            time.sleep(0.5)
            self.assertIsNone(process.poll(), "closed without waiting for Enter")
            os.write(master, b"\n")
            self.assertEqual(process.wait(timeout=60), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            os.close(master)
        check_installed(output.decode())
        uninstall()

    def test_windows_x64_download_under_wine(self):
        wine, wineserver = shutil.which("wine"), shutil.which("wineserver")
        if wine is None or wineserver is None or os.name != "posix":
            self.skipTest("Wine (wine and wineserver on PATH) is not available")
        registry = load("socket_helper_windows_registry", HERE / "test_windows_registry.py")
        registry.run_in_temporary_prefix(self.out / NAMES["windows-amd64"], str(Path(wine).resolve()),
                                         str(Path(wineserver).resolve()), 180,
                                         registry.WineRegistryRegression.exercise_download)


if __name__ == "__main__":
    unittest.main()
