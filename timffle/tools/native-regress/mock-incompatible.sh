#!/bin/sh
exec node "$(dirname "$0")/mock-host.mjs" incompatible "$@"
