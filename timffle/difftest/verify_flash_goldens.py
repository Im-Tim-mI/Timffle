#!/usr/bin/env python3
"""Read-only check of fresh Flash reports against goldens using comparator policy."""
import difflib
from pathlib import Path
import compare


def main():
    root = Path(__file__).resolve().parent
    bad = 0
    for expected in sorted((root / "expected").glob("*.txt")):
        actual = root / "results" / "flash" / expected.name
        if not actual.exists():
            print("FAIL", expected.stem, "missing Flash report")
            bad += 1
            continue
        diff = list(difflib.unified_diff(compare.lines(expected), compare.lines(actual),
                                         "golden", "fresh-flash", lineterm=""))
        print("FAIL" if diff else "PASS", expected.stem)
        for line in diff:
            print(line)
        bad += bool(diff)
    return int(bool(bad))


if __name__ == "__main__":
    raise SystemExit(main())
