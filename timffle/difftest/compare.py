#!/usr/bin/env python3
"""Compare ruffle results against the Flash Player golden answers.

usage: compare.py [test ...]        (default: every expected/*.txt)

Golden answers live in expected/<test>.txt (copied from results/flash/ by
`compare.py --bless test...`). Lines starting with "~" are timing info and ignored.
If ruffle produced no report, the cause is pulled from logs/ruffle/<test>.log.
"""
import difflib
import os
import re
import shutil
import sys

D = os.path.dirname(os.path.abspath(__file__))
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        data = [l for l in f.read().splitlines() if not l.startswith("~")]
        # Ignore Flash frame-number jitter, not event order or content.
        if os.path.basename(path) == "t2localconn.txt":
            data = [re.sub(re.escape("[f+") + r"[0-9]+" + re.escape("]"), "[frame]", l) for l in data]
            # Approved release/debugger wording difference for this one fixture.
            # Exact whole-line match: never discard arbitrary descriptions, IDs,
            # error objects, extra fields, or events; list order stays unchanged.
            release = "[frame] rx asyncError text=Error #2095 errorID=42 error=Error#42 Error"
            debugger = "[frame] rx asyncError text=Error #2095: flash.net.LocalConnection was unable to invoke callback boom. errorID=42 error=Error#42 Error"
            data = [release if l == debugger else l for l in data]
        return data


def crash_reason(test):
    log = os.path.join(D, "logs", "ruffle", test + ".log")
    if not os.path.exists(log):
        return "no log"
    text = ANSI.sub("", open(log, encoding="utf-8", errors="replace").read())
    traces = [l.split("avm_trace: ", 1)[1] for l in text.splitlines() if "avm_trace: " in l]
    for pat in (r"panicked at .*\n.*", r"has overflowed its stack", r"fatal runtime error.*"):
        m = re.search(pat, text)
        if m:
            return "CRASH: %s | last trace: %s" % (m.group(0).replace("\n", " / "),
                                                    traces[-1] if traces else "-")
    return "NO REPORT (hang?) | last trace: %s" % (traces[-1] if traces else "-")


def compare(test):
    exp = os.path.join(D, "expected", test + ".txt")
    got = os.path.join(D, "results", "ruffle", test + ".txt")
    if not os.path.exists(got):
        return "FAIL", [crash_reason(test)]
    diff = list(difflib.unified_diff(lines(exp), lines(got), "flash", "ruffle", n=0, lineterm=""))
    return ("PASS", []) if not diff else ("FAIL", diff[2:])


def main(argv):
    if argv[:1] == ["--bless"]:
        os.makedirs(os.path.join(D, "expected"), exist_ok=True)
        for t in argv[1:]:
            shutil.copy(os.path.join(D, "results", "flash", t + ".txt"),
                        os.path.join(D, "expected", t + ".txt"))
            print("blessed", t)
        return 0
    tests = argv or sorted(f[:-4] for f in os.listdir(os.path.join(D, "expected")) if f.endswith(".txt"))
    bad = 0
    for t in tests:
        status, detail = compare(t)
        bad += status != "PASS"
        print("%-4s %s" % (status, t))
        for l in detail:
            print("     " + l)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
