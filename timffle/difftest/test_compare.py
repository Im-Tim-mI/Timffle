"""Strict fixture-specific release/debugger normalization regression tests."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import compare

RELEASE = "[f+1] rx asyncError text=Error #2095 errorID=42 error=Error#42 Error"
DEBUGGER = "[f+2] rx asyncError text=Error #2095: flash.net.LocalConnection was unable to invoke callback boom. errorID=42 error=Error#42 Error"
BEFORE = "[f+1] boom called"
AFTER = "# done"


class CompareTests(unittest.TestCase):
    def check(self, actual, status, expected=None, name="t2localconn"):
        expected = expected or [BEFORE, RELEASE, AFTER]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "expected").mkdir()
            (root / "results" / "ruffle").mkdir(parents=True)
            (root / "expected" / (name + ".txt")).write_text("\n".join(expected))
            (root / "results" / "ruffle" / (name + ".txt")).write_text("\n".join(actual))
            with patch.object(compare, "D", tmp):
                result, diff = compare.compare(name)
            self.assertEqual(result, status, diff)
            if status == "FAIL":
                self.assertTrue(diff)

    def test_release_identical_pass(self):
        self.check([BEFORE, RELEASE, AFTER], "PASS")

    def test_known_debugger_pass(self):
        self.check([BEFORE, DEBUGGER, AFTER], "PASS")

    def test_reverse_direction_pass(self):
        self.check([BEFORE, RELEASE, AFTER], "PASS", [BEFORE, DEBUGGER, AFTER])

    def test_wrong_error_id_fail(self):
        for line in [RELEASE, DEBUGGER]:
            with self.subTest(line=line):
                self.check([BEFORE, line.replace("errorID=42", "errorID=0"), AFTER], "FAIL")

    def test_wrong_text_error_code_fail(self):
        for line in [RELEASE, DEBUGGER]:
            with self.subTest(line=line):
                self.check([BEFORE, line.replace("#2095", "#2096"), AFTER], "FAIL")

    def test_wrong_error_object_fail(self):
        for value in ["Error#43 Error", "Error#42 TypeError", "null"]:
            with self.subTest(value=value):
                self.check([BEFORE, DEBUGGER.replace("error=Error#42 Error", "error=" + value), AFTER], "FAIL")

    def test_wrong_order_fail(self):
        self.check([DEBUGGER, BEFORE, AFTER], "FAIL")

    def test_unknown_description_fail(self):
        for line in [DEBUGGER.replace("callback boom.", "callback other."),
                     RELEASE.replace("#2095", "#2095: arbitrary text"),
                     DEBUGGER + " extra", DEBUGGER.replace("rx asyncError", "tx asyncError")]:
            with self.subTest(line=line):
                self.check([BEFORE, line, AFTER], "FAIL")

    def test_missing_duplicate_events_fail(self):
        self.check([BEFORE, AFTER], "FAIL")
        self.check([BEFORE, DEBUGGER, DEBUGGER, AFTER], "FAIL")

    def test_other_fixture_not_normalized(self):
        self.check([BEFORE, DEBUGGER.replace("[f+2]", "[f+1]"), AFTER], "FAIL", name="other")

    def test_other_content_not_normalized(self):
        self.check([BEFORE.replace("boom", "other"), DEBUGGER, AFTER], "FAIL")


if __name__ == "__main__":
    unittest.main()
