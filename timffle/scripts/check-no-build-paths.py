#!/usr/bin/env python3
"""Refuse a ZIP or a directory that carries the build machine's home directory or user name.

usage: check-no-build-paths.py <zip>
       check-no-build-paths.py <directory>

Rust panic messages embed source paths such as /home/<user>/.cargo/registry/src/..., so a wasm built
without --remap-path-prefix leaks them. timffle/scripts/build-extension.sh remaps the paths by default;
this is the gate that package-release.sh runs before and after packaging.

A directory (such as the helper downloads made by timffle/helper/package-installers.py) is scanned
without following links: the bytes of every regular file in it, and the members of each .zip and
.tar.gz/.tgz in it (for tar members also their names, link targets and owner names). A link or a
special file in the directory is a read error.

Exit status: 0 = clean, 1 = leak found, 2 = usage or read error.
The report lists file names and counts only; it never prints the user name itself.
"""
import getpass
import io
import os
import re
import stat
import sys
import tarfile
import zipfile
import zlib

MAX_SCAN = 1 << 30  # bytes of one file or archive member in a directory scan


class ScanError(Exception):
    pass


READ_ERRORS = (OSError, EOFError, zlib.error, zipfile.BadZipFile, tarfile.TarError, RuntimeError,
               NotImplementedError, ScanError)


def account_name():
    try:
        return getpass.getuser()
    except Exception:  # no usable account name (some containers): the home directory check still applies
        return ''


def patterns():
    pats = []
    home = os.path.expanduser('~')
    if home and home not in ('/', '~') and len(home) > 3:
        pats.append(re.compile(re.escape(home.encode())))
    user = account_name()
    if user:
        # only path-like uses of the name, so short names do not cause false alarms
        pats.append(re.compile(rb'(?:/home/|/Users/|\\Users\\)' + re.escape(user.encode()), re.I))
    return pats


def occurrences(data, pats):
    return sum(len(p.findall(data)) for p in pats)


def redact(text, pats):
    """Text for the report with every match replaced, so a leaked name is never printed."""
    data = text.encode('utf-8', 'surrogateescape')
    for p in pats:
        data = p.sub(b'<home or user>', data)
    return data.decode('utf-8', 'replace')


def scan_zip(z, pats, prefix=''):
    bad, count = [], 0
    for entry in z.infolist():
        if entry.is_dir():
            continue
        count += 1
        if prefix and entry.file_size > MAX_SCAN:
            raise ScanError('%s%s is too large to scan' % (prefix, entry.filename))
        data = z.read(entry)
        n = occurrences(data, pats)
        if n:
            bad.append((prefix + entry.filename, n))
    return bad, count


def scan_tar(data, pats, user, prefix):
    bad, count = [], 0
    def text_occurrences(*texts):
        return occurrences('\0'.join(texts).encode('utf-8', 'surrogateescape'), pats)

    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar:
        for member in tar:
            count += 1
            # Names, link targets and pax records are inside the compressed stream, out of reach of
            # the raw scan; an owner name equal to the account name is a leak even without a path.
            n = text_occurrences(member.name, member.linkname, *member.pax_headers.values())
            if user and user.casefold() in (member.uname.casefold(), member.gname.casefold()):
                n += 1
            if member.isreg():
                if member.size > MAX_SCAN:
                    raise ScanError('%s%s is too large to scan' % (prefix, member.name))
                n += occurrences(tar.extractfile(member).read(), pats)
            if n:
                bad.append((prefix + member.name, n))
        n = text_occurrences(*tar.pax_headers.values())
        if n:
            bad.append((prefix + '(global pax header)', n))
    return bad, count


def read_file(path):
    # No link is followed and nothing but a regular file is read (a FIFO would block).
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0))
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise ScanError('%s is not a regular file' % path)
        if info.st_size > MAX_SCAN:
            raise ScanError('%s is too large to scan' % path)
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            return stream.read(MAX_SCAN + 1)
    finally:
        os.close(fd)


def walk(root, rel=''):
    with os.scandir(os.path.join(root, rel) if rel else root) as entries:
        items = sorted(entries, key=lambda e: e.name)
    for entry in items:
        name = rel + entry.name
        if entry.is_symlink():
            raise ScanError('%s is a link; links are not followed' % name)
        if entry.is_dir(follow_symlinks=False):
            yield from walk(root, name + '/')
        elif entry.is_file(follow_symlinks=False):
            yield name, entry.path
        else:
            raise ScanError('%s is not a regular file' % name)


def scan_directory(root, pats):
    user = account_name()
    bad, files, members = [], 0, 0
    for name, path in walk(root):
        data = read_file(path)
        files += 1
        n = occurrences(data, pats)
        if n:
            bad.append((name, n))
        lower = name.lower()
        if lower.endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                found, count = scan_zip(z, pats, name + '!')
        elif lower.endswith(('.tar.gz', '.tgz')):
            found, count = scan_tar(data, pats, user, name + '!')
        else:
            continue
        bad += found
        members += count
    return bad, files, members


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    pats = patterns()
    directory = os.path.isdir(argv[1])
    try:
        if directory:
            bad, count, members = scan_directory(argv[1], pats)
        else:
            with zipfile.ZipFile(argv[1]) as z:
                bad, count = scan_zip(z, pats)
    except READ_ERRORS as exc:
        print('check-no-build-paths: cannot read %s: %s' % (redact(argv[1], pats), redact(str(exc), pats)), file=sys.stderr)
        return 2
    if bad:
        print("check-no-build-paths: this machine's home directory or user name is inside:", file=sys.stderr)
        for name, n in bad:
            print('  %-64s %d occurrence(s)' % (redact(name, pats), n), file=sys.stderr)
        if directory:
            print('Rebuild with timffle/helper/build.sh or timffle/scripts/build-extension.sh, which keep the build paths out.', file=sys.stderr)
        else:
            print('Rebuild with timffle/scripts/build-extension.sh, which remaps the build paths.', file=sys.stderr)
        return 1
    if directory:
        print('check-no-build-paths: OK (%d files, %d archive members, no home directory or user name)' % (count, members))
    else:
        print('check-no-build-paths: OK (%d files, no home directory or user name)' % count)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
