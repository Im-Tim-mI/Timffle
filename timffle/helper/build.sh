#!/bin/sh
# Compile into a NEW staging directory only; never creates a release/package.
# Usage: GO=/absolute/path/to/go ./build.sh NEW_OUTPUT_DIR
# Optional: INCLUDE_LINUX_ARM64=1 (Chromium community target, not official Chrome)
# Parent owns invocation, final builds, executable runtime tests and packaging.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: build.sh NEW_OUTPUT_DIR (must not exist)' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required for path-safety checks.' >&2; exit 1; }
GO=${GO:-go}
case "$GO" in */*) GO=$(python3 -I -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$GO") ;; esac
OUT=$(python3 -I - "$1" <<'PY'
import os, pathlib, sys
p = pathlib.Path(os.path.abspath(sys.argv[1]))
for q in [*reversed(p.parents), p]:
    if q.is_symlink():
        sys.exit("Output path contains a symlink; refused.")
if not p.parent.is_dir() or p.exists():
    sys.exit("Output parent must exist and output must be a new directory.")
print(p)
PY
)
cd "$(dirname "$0")"
# Do not inherit -tags=localtest or an overlay from a developer's environment.
[ -z "${GOFLAGS:-}" ] || { echo 'Unset GOFLAGS; production staging forbids ambient build tags/overlays.' >&2; exit 1; }
[ -z "${GOWORK:-}" ] || [ "$GOWORK" = off ] || { echo 'Unset GOWORK or set it to off.' >&2; exit 1; }
TARGETS='windows/amd64 windows/arm64 windows/386 darwin/amd64 darwin/arm64 linux/amd64'
case "${INCLUDE_LINUX_ARM64:-0}" in
  0) ;;
  1) TARGETS="$TARGETS linux/arm64" ;;
  *) echo 'INCLUDE_LINUX_ARM64 must be 0 or 1.' >&2; exit 2 ;;
esac
SUPPORTED=$(GOENV=off GOWORK=off "$GO" tool dist list)
for target in $TARGETS; do
  printf '%s\n' "$SUPPORTED" | grep -Fx "$target" >/dev/null || { echo "Toolchain does not support $target" >&2; exit 1; }
done
# Exclusive mkdir preserves old build directories even after interruption.
mkdir -m 700 "$OUT"
trap 'echo "Build interrupted/failed. Partial staging preserved at: $OUT (not a release)." >&2' 1 2 3 15
for target in $TARGETS; do
  os=${target%/*}
  arch=${target#*/}
  ext=''
  [ "$os" != windows ] || ext=.exe
  mkdir -m 755 "$OUT/$os-$arch"
  CGO_ENABLED=0 GOENV=off GOWORK=off GOFLAGS= GOOS="$os" GOARCH="$arch" \
    "$GO" build -trimpath -buildvcs=false -tags= -ldflags='-s -w' \
    -o "$OUT/$os-$arch/.timffle-socket-helper$ext.partial" . || {
      echo "Build failed for $target; partial staging preserved (not a release)." >&2; exit 1;
    }
  mv "$OUT/$os-$arch/.timffle-socket-helper$ext.partial" "$OUT/$os-$arch/timffle-socket-helper$ext"
  chmod 755 "$OUT/$os-$arch/timffle-socket-helper$ext"
done
printf 'Cross-compiled staging only: %s\nNot signed, not runtime-tested, not a final release.\n' "$OUT"
