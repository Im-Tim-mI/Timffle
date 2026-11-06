#!/usr/bin/env python3
"""Turn a real-Flash golden of the Loader-timing probe (expected/lt*.txt) into the output.txt of
the matching Ruffle regression test (tests/tests/swfs/avm2/timffle_loader_timing_*): drop '#'/'~'
lines and everything before the `progress(all bytes)` event, and rewrite frame numbers relative
to that event's frame (`D+k`), which is what LTMain prints without -D harness.

usage: lt_regression_output.py <golden.txt> > output.txt
"""
import re
import sys

lines = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if not l.startswith(("#", "~"))]
start = next(i for i, l in enumerate(lines) if l.startswith("event progress(all bytes)"))
dl = int(re.search(r" in frame (\d+) ", lines[start]).group(1))
rel = lambda m: "%sD+%d" % (m.group(1), int(m.group(2)) - dl)
for l in lines[start:]:
    l = re.sub(r"^((?:enterFrame|frameConstructed|exitFrame) )(\d+)", rel, l)
    l = re.sub(r"( in frame )(\d+)", rel, l)
    l = re.sub(r"(\(frame )(\d+)(?=\)$)", rel, l)
    print(l)
