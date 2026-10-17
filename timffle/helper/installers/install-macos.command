#!/bin/sh
# Per-user install of the Timffle socket helper for Google Chrome on macOS.
# No administrator rights, background service or security setting changes.
cd "$(dirname "$0")" || exit 1
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) target=darwin-arm64 ;;
    Darwin/x86_64) target=darwin-amd64 ;;
    *) target= ;;
esac
if [ -z "$target" ]; then
    echo "Unsupported system: $(uname -s) $(uname -m)"
    rc=1
else
    ./bin/"$target"/timffle-socket-helper --install
    rc=$?
fi
echo
printf '按 Enter 關閉 / Press Enter to close. '
read -r _ || true
exit "$rc"
