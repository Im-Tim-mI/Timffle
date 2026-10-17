"""Offline packaging regressions: synthetic bytes only, no builds or real keys.

Run: python3 -B -m unittest discover -s installer-tests -p 'test_package.py' -v
Only package.py is imported from the project. Every input/output fixture lives
in TemporaryDirectory; the production extension ID is temporarily replaced
with the hash of synthetic manifest bytes (not a cryptographic public key).
The synthetic executable headers are validation fixtures, never executed.
"""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import struct
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "socket_helper_package", Path(__file__).resolve().parents[1] / "package.py"
)
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)

# All markers have deliberately non-key payloads. No key generation or real
# credentials/certificates are needed, even for the encrypted/OpenSSH cases.
PRIVATE_LABELS = (
    b"PRIVATE KEY",
    b"RSA PRIVATE KEY",
    b"EC PRIVATE KEY",
    b"ENCRYPTED PRIVATE KEY",
    b"OPENSSH PRIVATE KEY",
    b"DSA PRIVATE KEY",
    b"ED25519 PRIVATE KEY",
    b"SYNTHETIC-ALGORITHM V2 PRIVATE KEY",
    b"Synthetic_Algorithm.v3 PRIVATE KEY",
)


def private_marker(label):
    return b"-----BEGIN " + label + b"-----\nSYNTHETIC-NOT-A-KEY\n"


def synthetic_binary(target, extension_id):
    data = bytearray(128)
    os_name, arch = target.split("-")
    if os_name == "windows":
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 64)
        data[64:68] = b"PE\0\0"
        struct.pack_into("<H", data, 68, {"amd64": 0x8664, "arm64": 0xAA64, "386": 0x14C}[arch])
    elif os_name == "linux":
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", data, 18, {"amd64": 62, "arm64": 183}[arch])
    else:
        data[:4] = b"\xcf\xfa\xed\xfe"
        struct.pack_into("<I", data, 4, {"amd64": 0x01000007, "arm64": 0x0100000C}[arch])
    return bytes(data) + ("chrome-extension://" + extension_id + "/").encode("ascii")


class PrivateKeyMarkerTests(unittest.TestCase):
    def test_generic_private_key_labels_in_binary_payload(self):
        for label in PRIVATE_LABELS:
            with self.subTest(label=label):
                with self.assertRaisesRegex(ValueError, "Private key material is forbidden"):
                    package.reject_private_key_material(b"\x00\xffprefix" + private_marker(label) + b"\x00suffix")

    def test_public_key_certificate_and_plain_text_are_not_private_markers(self):
        for data in (
            b"-----BEGIN PUBLIC KEY-----\nSYNTHETIC-NOT-A-KEY",
            b"-----BEGIN RSA PUBLIC KEY-----\nSYNTHETIC-NOT-A-KEY",
            b"-----BEGIN CERTIFICATE-----\nSYNTHETIC-NOT-A-CERTIFICATE",
            b"Do not share your PRIVATE KEY.",
            b"-----BEGIN PRIVATE KEY REQUEST-----",
        ):
            with self.subTest(data=data):
                package.reject_private_key_material(data)


class PackageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="socket-package-tests-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source_dir = self.root / "source"
        installers = self.source_dir / "installers"
        installers.mkdir(parents=True)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.extension_zip = self.root / "extension.zip"
        self.out = self.root / "release.zip"
        # Matches only the packager's minimal DER-prefix sanity check; neither
        # these bytes nor the PEM marker strings are actual key material.
        synthetic_public_bytes = b"\x30" + b"SYNTHETIC-NOT-A-PUBLIC-KEY" * 2
        digest = hashlib.sha256(synthetic_public_bytes).hexdigest()[:32]
        self.extension_id = "".join(chr(ord("a") + int(n, 16)) for n in digest)
        expected_id_patch = mock.patch.object(package, "EXPECTED_ID", self.extension_id)
        expected_id_patch.start()
        self.addCleanup(expected_id_patch.stop)
        self.manifest = {
            "manifest_version": 3,
            "key": base64.b64encode(synthetic_public_bytes).decode("ascii"),
            "permissions": ["nativeMessaging"],
        }
        self.extension_entries = {
            "manifest.json": json.dumps(self.manifest).encode("utf-8"),
            "dist/main.js": b"// Synthetic extension fixture.\n",
        }
        self.write_extension()
        self.binary_paths = {}
        for target in sorted(package.REQUIRED_TARGETS | package.OPTIONAL_TARGETS):
            folder = self.bin_dir / target
            folder.mkdir()
            name = "timffle-socket-helper" + (".exe" if target.startswith("windows-") else "")
            path = folder / name
            path.write_bytes(synthetic_binary(target, self.extension_id))
            path.chmod(0o700)
            self.binary_paths[target] = path
        self.installer_paths = {}
        for name in sorted(package.INSTALLERS):
            path = installers / name
            path.write_bytes(b"@echo off\necho Synthetic launcher\r\n" if name.endswith(".cmd") else b"#!/bin/sh\n# Synthetic launcher; never executed.\n")
            self.installer_paths[name] = path
        self.readme = self.source_dir / "README.zh-TW.txt"
        self.readme.write_bytes("合成說明\n第二行\r\n".encode("utf-8"))

    def write_extension(self, entries=None):
        if entries is None:
            entries = list(self.extension_entries.items())
        with zipfile.ZipFile(self.extension_zip, "w") as archive:
            for name, data in entries:
                archive.writestr(name, data)

    def make_package(self, extension_id=None):
        return package.package(
            self.extension_zip, self.bin_dir,
            self.extension_id if extension_id is None else extension_id,
            self.out, source_dir=self.source_dir,
        )

    def assert_no_artifacts(self):
        self.assertFalse(self.out.exists())
        self.assertEqual(list(self.root.glob(".timffle-package-*")), [])

    def assert_private_rejected_before_zip(self):
        # Scanning must finish before even creating a temporary release ZIP.
        with mock.patch.object(package.tempfile, "mkstemp") as create_zip:
            with self.assertRaisesRegex(ValueError, "Private key material is forbidden"):
                self.make_package()
            create_zip.assert_not_called()
        self.assert_no_artifacts()

    def test_private_markers_rejected_in_extension(self):
        for label in PRIVATE_LABELS:
            with self.subTest(label=label):
                self.extension_entries["dist/main.js"] = b"// embedded fixture\n" + private_marker(label)
                self.write_extension()
                self.assert_private_rejected_before_zip()

    def test_private_markers_rejected_in_every_native_target(self):
        for target, path in self.binary_paths.items():
            clean = path.read_bytes()
            for label in PRIVATE_LABELS:
                with self.subTest(target=target, label=label):
                    path.write_bytes(clean + b"\x00" + private_marker(label) + b"\x00")
                    self.assert_private_rejected_before_zip()
            path.write_bytes(clean)

    def test_private_markers_rejected_in_every_launcher(self):
        for name, path in self.installer_paths.items():
            clean = path.read_bytes()
            for label in PRIVATE_LABELS:
                with self.subTest(launcher=name, label=label):
                    path.write_bytes(clean + private_marker(label))
                    self.assert_private_rejected_before_zip()
            path.write_bytes(clean)

    def test_private_markers_rejected_in_readme(self):
        clean = self.readme.read_bytes()
        for label in PRIVATE_LABELS:
            with self.subTest(label=label):
                self.readme.write_bytes(b"\xef\xbb\xbf" + clean + private_marker(label))
                self.assert_private_rejected_before_zip()

    def test_final_payload_scan_also_covers_extension_assets(self):
        # Verify the final collection's check independently of extension parsing.
        with mock.patch.object(package, "extension_assets", return_value={"dist/main.js": private_marker(b"OPENSSH PRIVATE KEY")}):
            self.assert_private_rejected_before_zip()

    def test_clean_package_content_modes_and_normalization(self):
        original_link = os.link
        with mock.patch.object(package.os, "link", wraps=original_link) as publish:
            self.assertEqual(self.make_package(), self.out)
        publish.assert_called_once()
        self.assertEqual(publish.call_args.args[1], self.out)
        self.assertEqual(publish.call_args.kwargs, {"follow_symlinks": False})
        expected = {
            "extension/" + name: (data, False)
            for name, data in self.extension_entries.items()
        }
        for target, path in self.binary_paths.items():
            expected["helper/bin/" + target + "/" + path.name] = (path.read_bytes(), True)
        for name, path in self.installer_paths.items():
            data = path.read_bytes()
            if name.endswith(".cmd"):
                data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            expected["helper/" + name] = (data, name.endswith((".sh", ".command")))
        expected["README.txt"] = (b"\xef\xbb\xbf" + "合成說明\r\n第二行\r\n".encode("utf-8"), False)
        with zipfile.ZipFile(self.out) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(set(archive.namelist()), {package.ROOT + "/" + name for name in expected})
            for name, (data, executable) in expected.items():
                with self.subTest(asset=name):
                    info = archive.getinfo(package.ROOT + "/" + name)
                    self.assertEqual(archive.read(info), data)
                    self.assertEqual(info.create_system, 3)
                    self.assertEqual(info.external_attr >> 16, stat.S_IFREG | (0o755 if executable else 0o644))
        self.assertEqual(list(self.root.glob(".timffle-package-*")), [])

    def test_existing_output_is_preserved(self):
        self.out.write_bytes(b"EXISTING-RELEASE")
        with self.assertRaisesRegex(ValueError, "Output already exists"):
            self.make_package()
        self.assertEqual(self.out.read_bytes(), b"EXISTING-RELEASE")

    def test_atomic_publish_race_preserves_competing_output(self):
        original_link = os.link

        def competing_publish(source, destination, **kwargs):
            Path(destination).write_bytes(b"COMPETING-RELEASE")
            return original_link(source, destination, **kwargs)

        with mock.patch.object(package.os, "link", side_effect=competing_publish):
            with self.assertRaises(FileExistsError):
                self.make_package()
        self.assertEqual(self.out.read_bytes(), b"COMPETING-RELEASE")
        self.assertEqual(list(self.root.glob(".timffle-package-*")), [])

    def test_failed_archive_write_cleans_temporary_output(self):
        with mock.patch.object(package, "add", side_effect=OSError("synthetic write failure")):
            with self.assertRaisesRegex(OSError, "synthetic write failure"):
                self.make_package()
        self.assert_no_artifacts()

    def test_archive_path_and_allowlist_guards_remain(self):
        for name in ("../escape.js", "/absolute.js", "dist/../escape.js", "dist\\escape.js", "dist/extra.pem", "profile/config.json"):
            with self.subTest(name=name):
                self.write_extension(list(self.extension_entries.items()) + [(name, b"synthetic")])
                with self.assertRaisesRegex(ValueError, "Unsafe extension archive path|Unexpected extension asset"):
                    self.make_package()
                self.assert_no_artifacts()

    def test_duplicate_archive_entry_is_refused(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            self.write_extension(list(self.extension_entries.items()) + [("dist/main.js", b"duplicate")])
        with self.assertRaisesRegex(ValueError, "Duplicate/case-colliding"):
            self.make_package()
        self.assert_no_artifacts()

    def test_linked_archive_entry_is_refused(self):
        info = zipfile.ZipInfo("dist/link.js")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.write_extension(list(self.extension_entries.items()) + [(info, b"main.js")])
        with self.assertRaisesRegex(ValueError, "linked, or special archive entries"):
            self.make_package()
        self.assert_no_artifacts()

    def test_symlink_input_path_is_refused(self):
        moved = self.root / "real-extension.zip"
        self.extension_zip.rename(moved)
        self.extension_zip.symlink_to(moved)
        with self.assertRaisesRegex(ValueError, "Symlink input/output path refused"):
            self.make_package()
        self.assert_no_artifacts()

    def test_hardlinked_input_is_refused(self):
        os.link(self.readme, self.root / "readme-hardlink")
        with self.assertRaisesRegex(ValueError, "non-linked regular input file"):
            self.make_package()
        self.assert_no_artifacts()

    def test_native_architecture_checks_remain(self):
        for target, path in self.binary_paths.items():
            with self.subTest(target=target):
                clean = path.read_bytes()
                wrong_arch = "amd64" if not target.endswith("amd64") else "arm64"
                path.write_bytes(synthetic_binary(target.split("-")[0] + "-" + wrong_arch, self.extension_id))
                with self.assertRaisesRegex(ValueError, "architecture mismatch"):
                    self.make_package()
                self.assert_no_artifacts()
                path.write_bytes(clean)

    def test_native_executable_permission_check_remains(self):
        self.binary_paths["linux-amd64"].chmod(0o600)
        with self.assertRaisesRegex(ValueError, "missing its executable bit"):
            self.make_package()
        self.assert_no_artifacts()

    def test_unexpected_native_directory_entry_is_refused(self):
        (self.binary_paths["linux-amd64"].parent / "config.json").write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "Unexpected helper directory entries"):
            self.make_package()
        self.assert_no_artifacts()

    def test_unexpected_installer_entry_is_refused(self):
        (self.source_dir / "installers" / "extra.sh").write_bytes(b"# synthetic")
        with self.assertRaisesRegex(ValueError, "Unexpected/missing installer entries"):
            self.make_package()
        self.assert_no_artifacts()

    def test_shared_extension_id_check_remains(self):
        for extension_id in ("bad-id", "a" * 32):
            with self.subTest(extension_id=extension_id):
                with self.assertRaisesRegex(ValueError, "Unexpected extension ID"):
                    self.make_package(extension_id)
                self.assert_no_artifacts()

    def test_manifest_extension_id_check_remains(self):
        self.manifest["key"] = base64.b64encode(b"\x30" + b"DIFFERENT-SYNTHETIC-PUBLIC-BYTES" * 2).decode("ascii")
        self.extension_entries["manifest.json"] = json.dumps(self.manifest).encode("utf-8")
        self.write_extension()
        with self.assertRaisesRegex(ValueError, "does not match the supplied extension ID"):
            self.make_package()
        self.assert_no_artifacts()

    def test_native_extension_id_and_private_network_guards_remain(self):
        path = self.binary_paths["linux-amd64"]
        clean = path.read_bytes()
        for data, message in (
            (synthetic_binary("linux-amd64", "a" * 32), "does not accept this package's extension ID"),
            (clean + b"localtest", "test/private-network-bypass"),
            (clean + b"TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", "test/private-network-bypass"),
        ):
            with self.subTest(message=message):
                path.write_bytes(data)
                with self.assertRaisesRegex(ValueError, message):
                    self.make_package()
                self.assert_no_artifacts()


if __name__ == "__main__":
    unittest.main()
