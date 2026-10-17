#!/usr/bin/env python3
"""Refuse a ZIP that carries the build machine's home directory or user name.

usage: check-no-build-paths.py <zip>

Rust panic messages embed source paths such as /home/<user>/.cargo/registry/src/..., so a wasm built
without --remap-path-prefix leaks them. timffle/scripts/build-extension.sh remaps the paths by default;
this is the gate that package-release.sh runs before and after packaging.

Exit status: 0 = clean, 1 = leak found, 2 = usage or read error.
The report lists file names and counts only; it never prints the user name itself.
"""
import getpass
import os
import re
import sys
import zipfile


def patterns():
    pats = []
    home = os.path.expanduser('~')
    if home and home not in ('/', '~') and len(home) > 3:
        pats.append(re.compile(re.escape(home.encode())))
    try:
        user = getpass.getuser()
    except Exception:  # no usable account name (some containers): the home directory check still applies
        user = ''
    if user:
        # only path-like uses of the name, so short names do not cause false alarms
        pats.append(re.compile(rb'(?:/home/|/Users/|\\Users\\)' + re.escape(user.encode()), re.I))
    return pats


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    pats = patterns()
    bad = []
    count = 0
    try:
        with zipfile.ZipFile(argv[1]) as z:
            for entry in z.infolist():
                if entry.is_dir():
                    continue
                count += 1
                data = z.read(entry)
                n = sum(len(p.findall(data)) for p in pats)
                if n:
                    bad.append((entry.filename, n))
    except (OSError, zipfile.BadZipFile) as exc:
        print('check-no-build-paths: cannot read %s: %s' % (argv[1], exc), file=sys.stderr)
        return 2
    if bad:
        print("check-no-build-paths: this machine's home directory or user name is inside:", file=sys.stderr)
        for name, n in bad:
            print('  %-64s %d occurrence(s)' % (name, n), file=sys.stderr)
        print('Rebuild with timffle/scripts/build-extension.sh, which remaps the build paths.', file=sys.stderr)
        return 1
    print('check-no-build-paths: OK (%d files, no home directory or user name)' % count)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
