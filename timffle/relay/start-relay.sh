#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec node relay.mjs --origin https://mole.61.com.tw --origin http://mole.61.com.tw
