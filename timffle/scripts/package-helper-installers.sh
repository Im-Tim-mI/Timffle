#!/bin/sh
# Cross-compile the connection helper and make the per-system helper downloads that the extension's
# "install the helper" page fetches from the helper's GitHub release: timffle-helper-windows-{x64,arm64,x86}.exe,
# timffle-helper-macos-{arm64,x64}.zip, timffle-helper-linux-{x64,arm64}.tar.gz, LICENSES.txt and SHA256SUMS.txt.
#
# Usage: GO=/path/to/go timffle/scripts/package-helper-installers.sh [BUILD_DIR]
#   BUILD_DIR defaults to timffle/build (git-ignored).
#   GO        go binary to use (default: go from PATH; Go 1.27 or newer, see helper/go.mod)
# Output: BUILD_DIR/installers/ (the files to attach to the release) and BUILD_DIR/installers-bin/ (the build).
#
# The helper binaries are cross-compiled only; they are not signed or notarized (darwin/arm64 carries only
# the Go linker's ad-hoc signature). Nothing is uploaded by this script; publishing the files is a separate step.
# package-installers.py deletes the output again if it carries this machine's home directory or user name.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${1:-$ROOT/build}
BIN=$BUILD/installers-bin
OUT=$BUILD/installers

die() { echo "package-helper-installers: $*" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || die "python3 is required"
[ ! -e "$BIN" ] && [ ! -L "$BIN" ] || die "$BIN already exists; remove it first (the helper build never overwrites)"
[ ! -e "$OUT" ] && [ ! -L "$OUT" ] || die "$OUT already exists; the packager never overwrites"
mkdir -p "$BUILD"

echo "== Cross-compiling the helper =="
INCLUDE_LINUX_ARM64=1 GO=${GO:-go} "$ROOT/helper/build.sh" "$BIN"

echo "== Packaging the downloads =="
GO_LICENSE=$("${GO:-go}" env GOROOT)/LICENSE python3 -I "$ROOT/helper/package-installers.py" "$BIN" "$OUT"

echo
echo "Helper downloads: $OUT"
ls -l "$OUT"
echo
cat "$OUT/SHA256SUMS.txt"
