#!/bin/sh
# Starts the Timffle local bridge (relay.mjs) for the websites you name.
# No website is allowed unless you pass it: each argument is one exact
# website origin (scheme and host, optional port), for example
#   ./start-relay.sh https://game.example http://game.example
# Then paste proxyUrl from connection.json into the extension options and add
# the same websites there.
set -eu
cd "$(dirname "$0")"
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 https://game.example [http://game.example ...]" >&2
    exit 2
fi
n=$#
while [ "$n" -gt 0 ]; do
    set -- "$@" --origin "$1"
    shift
    n=$((n - 1))
done
exec node relay.mjs "$@"
