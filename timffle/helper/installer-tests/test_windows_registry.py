"""Windows registry ownership regression in a fresh, disposable Wine prefix.

Usage: python3 -B installer-tests/test_windows_registry.py /path/to/helper.exe
       python3 -B -m unittest discover -s installer-tests -p 'test_windows_registry.py' -v

The first command runs the supplied, already-built helper; this script never
builds it. The unittest command runs only mocks (no Wine, helper, or registry).
No existing WINEPREFIX is accepted or reused. Every Wine subprocess gets the
same temporary prefix and isolated HOME. The real user registry is untouched.
Wine is not a sandbox for an untrusted executable: supply your own helper.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


HOST_NAME = "timffle_socket_helper"
CHROMIUM_KEY = r"HKCU\Software\Chromium"
HOST_KEYS = (
    r"HKCU\Software\Google\Chrome\NativeMessagingHosts" + "\\" + HOST_NAME,
    CHROMIUM_KEY + r"\NativeMessagingHosts" + "\\" + HOST_NAME,
)
FOREIGN_NAME = "SocketHelperRegistryTestForeign"
FOREIGN_VALUE = "foreign-named-value-must-survive"
FOREIGN_SUBKEY = "SocketHelperRegistryTestChild"
CHILD_VALUE = "foreign-subkey-value-must-survive"
FOREIGN_DEFAULT = r"C:\foreign-registration\manifest.json"


def isolated_environment(root):
    """Replace inherited Wine/profile settings; never fall back to ~/.wine."""
    root = Path(root).resolve()
    home = root / "home"
    home.mkdir()
    cache = home / "cache"
    config = home / "config"
    data = home / "data"
    for directory in (cache, config, data):
        directory.mkdir()
    env = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith("WINE")
        and key.upper() not in {
            "HOME", "USERPROFILE", "HOMEDRIVE", "HOMEPATH",
            "LOCALAPPDATA", "APPDATA", "XDG_CACHE_HOME",
            "XDG_CONFIG_HOME", "XDG_DATA_HOME",
        }
    }
    env.update({
        "HOME": str(home),
        "WINEPREFIX": str(root / "wine-prefix"),
        "WINEDEBUG": "-all",
        # Avoid optional Gecko/Mono installation prompts/network setup.
        "WINEDLLOVERRIDES": "mscoree,mshtml=",
        "XDG_CACHE_HOME": str(cache),
        "XDG_CONFIG_HOME": str(config),
        "XDG_DATA_HOME": str(data),
    })
    return env


def completed_output(result):
    """Decode Wine console output without relying on a localized default label."""
    output = result.stdout or b""
    if isinstance(output, str):
        return output.replace("\r", "")
    if output.startswith((b"\xff\xfe", b"\xfe\xff")):
        return output.decode("utf-16", errors="replace").replace("\r", "")
    if b"\x00" in output:
        return output.decode("utf-16-le", errors="replace").replace("\r", "")
    return output.decode("utf-8", errors="replace").replace("\r", "")


def registry_string(output):
    """Return REG_SZ data from one `reg query /v NAME` or `/ve` result."""
    matches = re.findall(r"^[^\n]*?\sREG_SZ(?:[ \t]+([^\n]*))?$", output, re.MULTILINE)
    if len(matches) != 1:
        raise AssertionError("expected exactly one REG_SZ value, got:\n" + output)
    return matches[0].strip()


def same_windows_path(left, right):
    return left.replace("/", "\\").casefold() == right.replace("/", "\\").casefold()


class WineRegistryRegression:
    def __init__(self, wine, helper, env, cwd, timeout):
        self.wine = wine
        self.helper = str(helper)
        self.env = env
        self.cwd = str(cwd)
        self.timeout = timeout

    def command(self, *args, check=True):
        result = subprocess.run(
            [self.wine, *map(str, args)],
            cwd=self.cwd, env=self.env, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=self.timeout, check=False,
        )
        if check and result.returncode != 0:
            raise AssertionError(
                "command failed ({0}): {1!r}\n{2}".format(
                    result.returncode, args, completed_output(result)
                )
            )
        return result

    def reg(self, *args, check=True):
        return self.command("reg.exe", *args, check=check)

    def value(self, key, name=None):
        selector = ("/ve",) if name is None else ("/v", name)
        return registry_string(completed_output(self.reg("query", key, *selector)))

    def exported_has_default(self, key):
        # Wine may print REG_SZ '(value not set)' with exit 0 for an absent
        # default. A .reg export records actual values, without UI placeholders.
        dest = Path(self.cwd) / "registry-snapshot.reg"
        win_path = "Z:" + str(dest).replace("/", "\\")
        self.reg("export", key, win_path, "/y")
        raw = dest.read_bytes()
        text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
        target = "HKEY_CURRENT_USER" + key[len("HKCU"):]
        in_section = False
        found = False
        for line in text.splitlines():
            if line.startswith("[") and line.endswith("]"):
                in_section = line[1:-1].casefold() == target.casefold()
                found = found or in_section
            elif in_section and line.startswith("@="):
                return True
        if not found:
            raise AssertionError("target registry section missing from export")
        return False

    def assert_no_default(self, key):
        # Keep the key/named values/subkeys; remove only our default value.
        self.reg("query", key)
        if self.exported_has_default(key):
            raise AssertionError("default value still exists at " + key)

    def assert_foreign_contents(self, key):
        if self.value(key, FOREIGN_NAME) != FOREIGN_VALUE:
            raise AssertionError("foreign named value changed: " + key)
        if self.value(key + "\\" + FOREIGN_SUBKEY) != CHILD_VALUE:
            raise AssertionError("foreign subkey changed: " + key)

    def exercise(self):
        # A Chromium key with named data but no default must still enable
        # Chromium registration despite get() now reporting value existence.
        self.reg("add", CHROMIUM_KEY, "/v", "RegistryTestBrowser", "/t", "REG_SZ", "/d", "present", "/f")
        self.assert_no_default(CHROMIUM_KEY)
        self.command(self.helper, "--install")
        manifests = {}
        for key in HOST_KEYS:
            manifest = self.value(key)
            if not manifest.casefold().endswith("\\timfflesockethelper\\" + HOST_NAME + ".json"):
                raise AssertionError("unexpected installed manifest: " + manifest)
            manifests[key] = manifest
            self.reg("add", key, "/v", FOREIGN_NAME, "/t", "REG_SZ", "/d", FOREIGN_VALUE, "/f")
            self.reg("add", key + "\\" + FOREIGN_SUBKEY, "/ve", "/t", "REG_SZ", "/d", CHILD_VALUE, "/f")

        self.command(self.helper, "--uninstall")
        for key in HOST_KEYS:
            self.assert_foreign_contents(key)
            self.assert_no_default(key)

        # Residual keys containing someone else's named values/subkeys must
        # not be mistaken for an existing default registration.
        self.command(self.helper, "--install")
        for key in HOST_KEYS:
            self.assert_foreign_contents(key)
            if not same_windows_path(self.value(key), manifests[key]):
                raise AssertionError("reinstallation did not restore default: " + key)

        # Also prove that uninstall preserves a foreign default, not merely
        # foreign named values, even though our receipt still lists this key.
        foreign_key = HOST_KEYS[0]
        self.reg("add", foreign_key, "/ve", "/t", "REG_SZ", "/d", FOREIGN_DEFAULT, "/f")
        self.command(self.helper, "--uninstall")
        for key in HOST_KEYS:
            self.assert_foreign_contents(key)
            if key == foreign_key:
                if self.value(key) != FOREIGN_DEFAULT:
                    raise AssertionError("foreign default was removed or changed")
            else:
                self.assert_no_default(key)


def run_in_temporary_prefix(helper, wine, wineserver, timeout):
    with tempfile.TemporaryDirectory(prefix="socket-windows-registry-") as temporary:
        root = Path(temporary)
        env = isolated_environment(root)
        # Copy only the supplied helper, keeping every test-owned artifact
        # under the temporary root. No project files or credentials are read.
        executable = root / "registry-test-helper.exe"
        shutil.copyfile(helper, executable)
        case = WineRegistryRegression(wine, executable, env, root, timeout)
        try:
            # Wine automatically initializes the brand-new prefix on first
            # launch. Avoid wineboot here: it may be a mismatched launcher.
            case.reg("query", "HKCU\\Software")
            case.exercise()
        finally:
            # Target only this prefix's server. Stop it before deleting the
            # directory so delayed registry flushes cannot recreate it.
            for option in ("-k", "-w"):
                result = subprocess.run(
                    [wineserver, option], cwd=root, env=env,
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=timeout, check=False,
                )
                if result.returncode != 0 and not (result.returncode == 1 and not completed_output(result).strip()):
                    raise RuntimeError("temporary-prefix wineserver cleanup failed:\n" + completed_output(result))


class OfflineScriptTests(unittest.TestCase):
    """Mocks and parsing checks only; safe without Wine or a Windows binary."""

    def test_host_keys_have_single_separators(self):
        self.assertEqual(HOST_KEYS, (
            "HKCU\\Software\\Google\\Chrome\\NativeMessagingHosts\\" + HOST_NAME,
            "HKCU\\Software\\Chromium\\NativeMessagingHosts\\" + HOST_NAME,
        ))

    def test_registry_output_parsing_is_not_default_label_dependent(self):
        for label in ("(Default)", "(預設)", FOREIGN_NAME):
            output = "\nHKEY_CURRENT_USER\\Example\n    " + label + "    REG_SZ    C:\\Test Files\\host.json\n"
            self.assertEqual(registry_string(output), r"C:\Test Files\host.json")
        with self.assertRaises(AssertionError):
            registry_string("    (Default)    REG_DWORD    0x1\n")

    def test_utf16_console_output(self):
        source = "    (預設)    REG_SZ    C:\\host.json\r\n"
        result = subprocess.CompletedProcess([], 0, source.encode("utf-16"))
        self.assertEqual(registry_string(completed_output(result)), r"C:\host.json")

    def test_environment_overrides_all_inherited_prefix_and_profile_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            inherited = {
                "HOME": "/must-not-use", "WINEPREFIX": "/real-prefix",
                "WINEARCH": "win32", "WINELOADER": "/inherited-loader",
                "LOCALAPPDATA": "C:\\real-cache", "USERPROFILE": "C:\\real-user",
                "XDG_DATA_HOME": "/real-data", "PATH": "/bin",
            }
            with mock.patch.dict(os.environ, inherited, clear=True):
                env = isolated_environment(temporary)
            self.assertEqual(env["WINEPREFIX"], str(Path(temporary) / "wine-prefix"))
            self.assertEqual(env["HOME"], str(Path(temporary) / "home"))
            self.assertNotIn("WINEARCH", env)
            self.assertNotIn("WINELOADER", env)
            self.assertNotIn("LOCALAPPDATA", env)
            self.assertNotIn("USERPROFILE", env)
            self.assertFalse(Path(env["WINEPREFIX"]).exists())
            self.assertTrue(Path(env["XDG_DATA_HOME"]).is_relative_to(Path(temporary)))

    def test_every_command_uses_the_explicit_environment(self):
        env = {"WINEPREFIX": "/test-only/prefix", "HOME": "/test-only/home"}
        case = WineRegistryRegression("/wine", "/helper.exe", env, "/test-only", 12)
        with mock.patch.object(subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"")) as run:
            case.reg("query", HOST_KEYS[0])
        self.assertIs(run.call_args.kwargs["env"], env)
        self.assertEqual(run.call_args.args[0], ["/wine", "reg.exe", "query", HOST_KEYS[0]])
        self.assertEqual(run.call_args.kwargs["cwd"], "/test-only")
        self.assertEqual(run.call_args.kwargs["timeout"], 12)

    def test_missing_default_requires_a_surviving_key(self):
        case = WineRegistryRegression("/wine", "/helper.exe", {}, "/tmp", 12)
        with mock.patch.object(case, "reg", return_value=subprocess.CompletedProcess([], 0, b"")) as reg:
            with mock.patch.object(case, "exported_has_default", return_value=False) as exported:
                case.assert_no_default(HOST_KEYS[0])
        reg.assert_called_once_with("query", HOST_KEYS[0])
        exported.assert_called_once_with(HOST_KEYS[0])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("helper", type=Path, help="already-built Windows helper executable")
    parser.add_argument("--wine", default="wine", help="Wine loader path/name (default: wine)")
    parser.add_argument("--wineserver", default="wineserver", help="matching Wine server path/name")
    parser.add_argument("--timeout", type=float, default=120, help="timeout per process in seconds")
    args = parser.parse_args(argv)
    helper = args.helper.resolve(strict=True)
    if not helper.is_file():
        parser.error("helper must be a regular file")
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    wine = shutil.which(args.wine)
    wineserver = shutil.which(args.wineserver)
    if wine is None or wineserver is None:
        parser.error("Wine and its matching wineserver are required for the integration run")
    if os.name != "posix":
        parser.error("run under Wine on a POSIX host, not against a native Windows registry")
    run_in_temporary_prefix(helper, str(Path(wine).resolve()), str(Path(wineserver).resolve()), args.timeout)
    print("PASS: default-only uninstall, named value/subkey preservation, reinstall, foreign default preservation (temporary Wine prefix)")


if __name__ == "__main__":
    main()
