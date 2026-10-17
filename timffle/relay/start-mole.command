#!/bin/sh
# macOS: double-click in Finder to start the relay in Terminal.
set -eu
cd "$(dirname "$0")"
exec node relay.mjs --origin https://mole.61.com.tw --origin http://mole.61.com.tw
