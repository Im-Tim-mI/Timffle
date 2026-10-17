#!/bin/sh
# Removes only the helper files and registrations its installer created.
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
[ -x "$helper" ] || chmod u+x "$helper" || exit 1
exec "$helper" --uninstall
