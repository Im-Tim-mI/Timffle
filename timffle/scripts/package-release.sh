#!/bin/sh
# Cross-compile the connection helper and assemble the release ZIP (extension + helper + installers + README.txt).
#
# Usage: VERSION4=0.8.0.26301 timffle/scripts/package-release.sh [BUILD_DIR]
#   BUILD_DIR defaults to timffle/build (git-ignored).
#   Needs the extension zip from timffle/scripts/build-extension.sh (or set EXTENSION_ZIP=/path/to/ruffle_extension.zip).
#   GO                   go binary to use (default: go from PATH; Go 1.27 or newer, see helper/go.mod)
#   INCLUDE_LINUX_ARM64  1 adds the linux/arm64 helper (default 1, as in the published release)
#   SKIP_PATH_CHECK=1    do not refuse a ZIP that carries this machine's home directory or user name (a ZIP that
#                        never leaves this machine; never upload such a ZIP)
# Output: BUILD_DIR/out/timffle-chrome-<VERSION4>.zip and a matching SHA256SUMS file.
#
# The helper binaries are cross-compiled only; they are not signed or notarized.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$ROOT/.." && pwd)
BUILD=${1:-$ROOT/build}
VERSION4=${VERSION4:-0.8.0.1}
EXT_ZIP=${EXTENSION_ZIP:-$REPO/web/packages/extension/dist/ruffle_extension.zip}
EXT_ID=$(tr -d ' \r\n' < "$ROOT/extension-key/extension-id.txt")
OUT=$BUILD/out
BIN=$BUILD/helper-bin
ZIP=$OUT/timffle-chrome-$VERSION4.zip

die() { echo "package-release: $*" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || die "python3 is required"
[ -f "$EXT_ZIP" ] || die "extension zip not found: $EXT_ZIP (run timffle/scripts/build-extension.sh first)"
# Release gate: a wasm built without the path remapping of build-extension.sh carries the build machine's home
# directory and user name in its panic messages. Checked here, and again on the finished ZIP below.
[ "${SKIP_PATH_CHECK:-0}" = 1 ] || python3 -I "$ROOT/scripts/check-no-build-paths.py" "$EXT_ZIP" \
  || die "the extension zip carries this machine's paths; rebuild it with timffle/scripts/build-extension.sh"
[ ! -e "$BIN" ] || die "$BIN already exists; remove it first (the helper build never overwrites)"
[ ! -e "$ZIP" ] || die "$ZIP already exists; the packager never overwrites a release"
mkdir -p "$OUT"

echo "== Cross-compiling the helper =="
INCLUDE_LINUX_ARM64=${INCLUDE_LINUX_ARM64:-1} GO=${GO:-go} "$ROOT/helper/build.sh" "$BIN"

echo "== Packaging =="
GO_LICENSE=$("${GO:-go}" env GOROOT)/LICENSE python3 -I "$ROOT/helper/package.py" "$EXT_ZIP" "$BIN" "$EXT_ID" "$ZIP"

if [ "${SKIP_PATH_CHECK:-0}" != 1 ] && ! python3 -I "$ROOT/scripts/check-no-build-paths.py" "$ZIP"; then
  rm -f "$ZIP"
  die "the release ZIP carries this machine's paths; it was deleted so it cannot be uploaded by mistake"
fi

(cd "$OUT" && { sha256sum "$(basename "$ZIP")" 2>/dev/null || shasum -a 256 "$(basename "$ZIP")"; } \
  > "timffle-${VERSION4##*.}-SHA256SUMS.txt")
echo
echo "Release ZIP: $ZIP"
cat "$OUT/timffle-${VERSION4##*.}-SHA256SUMS.txt"
