#!/bin/sh
# Build the Timffle Chrome extension (WebAssembly core + extension bundle) from this repository.
#
# Usage: VERSION4=0.8.0.26296 timffle/scripts/build-extension.sh
#   VERSION4        extension version, four dot-separated numbers (default 0.8.0.1; the last one is just a build counter)
#   CARGO_FEATURES  Ruffle web features (default: jpegxr)
#   SKIP_TESTS=1    skip the extension type check and unit tests
#   KEEP_BUILD_PATHS=1  do not rewrite this machine's home directory in the wasm (a build that never leaves this machine)
# Output: web/packages/extension/dist/ruffle_extension.zip (the upstream build's file name; the release ZIP is named
#         timffle-chrome-<VERSION4>.zip by timffle/scripts/package-release.sh)
#
# Needs on PATH: cargo/rustc with the wasm32-unknown-unknown target, a wasm-bindgen CLI whose version equals the
# wasm-bindgen crate in Cargo.lock, wasm-opt (binaryen, optional but strongly recommended), node and npm.
# A wasm build from scratch takes a long time (tens of minutes) and several GB of disk.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
R=$(cd "$ROOT/.." && pwd)
VERSION4=${VERSION4:-0.8.0.1}
KEY_FILE=$ROOT/extension-key/chrome-extension-public.b64

die() { echo "build-extension: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

[ -d "$R/web/packages/extension" ] || die "$R does not look like the Timffle repository"
python3 -I "$ROOT/scripts/rebrand.py" --check || die "user-visible texts still say Ruffle; run timffle/scripts/rebrand.py"
if python3 -I -c "import PIL" 2>/dev/null; then
  python3 -I "$ROOT/branding/make_branding.py" --check || die "branding files are stale; run timffle/branding/make_branding.py"
fi
[ -f "$KEY_FILE" ] || die "missing $KEY_FILE"
printf '%s' "$VERSION4" | grep -Eq '^[0-9]+(\.[0-9]+){3}$' || die "VERSION4 must look like 0.8.0.26295"
need cargo; need rustc; need node; need npm; need wasm-bindgen
command -v wasm-opt >/dev/null 2>&1 || echo "warning: wasm-opt not found; the wasm will be larger and slower" >&2

want=$(awk '/^name = "wasm-bindgen"$/ { getline; gsub(/[^0-9.]/, ""); print; exit }' "$R/Cargo.lock")
have=$(wasm-bindgen --version | awk '{ print $2 }')
[ "$want" = "$have" ] || die "wasm-bindgen CLI is $have but Cargo.lock needs $want"
rustup target list --installed 2>/dev/null | grep -qx wasm32-unknown-unknown \
  || echo "warning: could not confirm the wasm32-unknown-unknown target (rustup target add wasm32-unknown-unknown)" >&2

cd "$R/web"
[ -d node_modules ] || npm ci

# Rust panic messages embed source paths. Rewrite the build machine's home directory (and with it the user name)
# so the wasm, and the release ZIP made from it, do not carry them. A later --remap-path-prefix entry wins,
# so the general one comes first. package-release.sh refuses a ZIP that still has them.
if [ "${KEEP_BUILD_PATHS:-0}" != 1 ]; then
  RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }--remap-path-prefix=$HOME=/h --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=$R=/src"
  export RUSTFLAGS
fi

echo "== Core (wasm) =="
CARGO_FEATURES=${CARGO_FEATURES:-jpegxr} npm run build --workspace=ruffle-core

if [ "${SKIP_TESTS:-0}" != 1 ]; then
  echo "== Extension type check and unit tests =="
  npm run checkTypes --workspace=ruffle-extension
  npm test --workspace=ruffle-extension
fi

echo "== Extension bundle =="
VERSION4=$VERSION4 CFG_RELEASE_CHANNEL=local-native-auto EXTENSION_PUBLIC_KEY=$(cat "$KEY_FILE") \
  npm run build:generic --workspace=ruffle-extension

ZIP=$R/web/packages/extension/dist/ruffle_extension.zip
[ -f "$ZIP" ] || die "build finished but $ZIP is missing"
echo
echo "Extension: $ZIP"
echo "Next: VERSION4=$VERSION4 timffle/scripts/package-release.sh   (adds the connection helper, installers and licences)"
