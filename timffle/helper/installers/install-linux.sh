#!/bin/sh
# Per-user install of the Timffle socket helper for Google Chrome / Chromium.
# No root, background service or security setting changes.
cd "$(dirname "$0")" || exit 1
case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) target=linux-amd64 ;;
    Linux/aarch64 | Linux/arm64) target=linux-arm64 ;;
    *) echo "Unsupported system: $(uname -s) $(uname -m)"; exit 1 ;;
esac
helper=./bin/$target/timffle-socket-helper
if [ ! -f "$helper" ]; then
    echo "This package has no $target helper."
    exit 1
fi
# Some archive tools drop the executable bit.
[ -x "$helper" ] || chmod u+x "$helper" || exit 1
exec "$helper" --install
