#!/bin/sh
# macOS: double-click in Finder to start the Timffle local bridge (relay.mjs)
# in Terminal. No website is allowed unless you name it: type one exact
# website origin when asked (for example https://game.example), or run
#   ./start-relay.command https://game.example http://game.example
# from Terminal to allow several. Then paste proxyUrl from connection.json
# into the extension options and add the same websites there.
set -eu
cd "$(dirname "$0")"
if [ "$#" -eq 0 ]; then
    printf "Website address (for example https://game.example): "
    read -r origin || origin=""
    if [ -z "$origin" ]; then
        echo "No website given; the bridge was not started." >&2
        exit 2
    fi
    set -- "$origin"
fi
n=$#
while [ "$n" -gt 0 ]; do
    set -- "$@" --origin "$1"
    shift
    n=$((n - 1))
done
exec node relay.mjs "$@"
