#!/bin/bash
# Browser + native helper regression (headless Chrome, localhost only; never touches a real game server).
#   PACKAGE_DIR       the unpacked release (the folder that holds extension/ and helper/)
#   LOCALTEST_HELPER  a helper built with the test-only tag:  (cd timffle/helper && CGO_ENABLED=0 go build -tags localtest -o ../build/localtest/timffle-socket-helper .)
#   TEST_FONTCONFIG   optional fontconfig file for CJK text in headless Chrome
set -u
cd "$(dirname "$0")"
L=$PWD
P=${PACKAGE_DIR:?set PACKAGE_DIR to the unpacked release folder}
H=${LOCALTEST_HELPER:?set LOCALTEST_HELPER to the localtest helper binary}
run() { name=$1; shift; node "$@" > "$L/regress-$name.log" 2>&1; echo $? > "$L/regress-$name.exit"; echo "$name exit=$(cat "$L/regress-$name.exit") pass=$(grep -c '"pass":true' "$L/regress-$name.log") fail=$(grep -c '"pass":false' "$L/regress-$name.log")" >> "$L/regress-summary.txt"; }
: > "$L/regress-summary.txt"
run localtest    browser-auto-tests.mjs "$P/extension" "$H" localtest
run missing      browser-auto-tests.mjs "$P/extension" /nonexistent/timffle-socket-helper missing
run delayed      browser-auto-tests.mjs "$P/extension" "$L/mock-delayed.sh" delayed
run incompatible browser-auto-tests.mjs "$P/extension" "$L/mock-incompatible.sh" incompatible
OUT_NAME=browser-manual node manual-mode-tests.mjs "$P/extension" > "$L/regress-manual.log" 2>&1; echo $? > "$L/regress-manual.exit"
echo "manual exit=$(cat "$L/regress-manual.exit") pass=$(grep -c '"pass":true' "$L/regress-manual.log") fail=$(grep -c '"pass":false' "$L/regress-manual.log")" >> "$L/regress-summary.txt"
echo DONE >> "$L/regress-summary.txt"
cat "$L/regress-summary.txt"
