#!/bin/bash
# usage: [HAXE=/path/to/haxe] build.sh <MainClass> <outname> [extra haxe args...]
set -e
cd "$(dirname "$0")"
mkdir -p bin
main=$1; out=$2; shift 2
"${HAXE:-haxe}" -cp src -main "$main" -swf "bin/$out.swf" \
  -swf-version 11 -D swf-header=400:300:30:FFFFFF "$@"
echo "built bin/$out.swf ($(stat -c%s "bin/$out.swf") bytes)"
