#!/bin/bash
# usage: run_all.sh [--flash] [test ...]
# Runs tests in ruffle (and Flash Player too with --flash), then compares against expected/.
# Needs server.py running. After a --flash run, bless new goldens with compare.py --bless.
cd "$(dirname "$0")"
flash=0
[ "$1" = "--flash" ] && { flash=1; shift; }
tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=($(ls expected | sed 's/\.txt$//'))
for t in "${tests[@]}"; do
  [ $flash = 1 ] && ./runner.py flash "$t" 110
  ./runner.py ruffle "$t" 110
done
./compare.py "${tests[@]}"
