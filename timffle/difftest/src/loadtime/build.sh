#!/bin/bash
# Builds the Loader-timing probes (LTMain.hx + loadtime/Child.as) in two flavours:
#   harness builds -> $DT/bin/lt*.swf           (difftest: real Flash goldens in expected/)
#   trace builds   -> $TESTS/timffle_loader_timing_<variant>/  (Ruffle regression tests)
# usage: [DT=difftest dir] [TESTS=tests/tests/swfs/avm2] [PLAYERGLOBAL_ABC=…] [ASC_JAR=…] [HAXE=…] build.sh
# Needs Java (asc.jar) and Haxe. The children are AS3 (asc.jar) because a Haxe main() has no `this`
# and Haxe's boot waits for the stage before running main() in a loaded SWF.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
DT=${DT:-$HERE/../..}
TESTS=${TESTS:-$REPO/tests/tests/swfs/avm2}
ASC_JAR=${ASC_JAR:-$REPO/tools/asc/asc.jar}
if [ -z "$PLAYERGLOBAL_ABC" ]; then
  PLAYERGLOBAL_ABC=$(ls -t "${CARGO_TARGET_DIR:-$REPO/target}"/debug/build/ruffle_core-*/out/playerglobal_import.abc 2>/dev/null | head -1)
fi
[ -f "$PLAYERGLOBAL_ABC" ] || { echo "playerglobal_import.abc not found (build ruffle_core once, or set PLAYERGLOBAL_ABC)"; exit 1; }
FR="-D swf-header=400:300:10:FFFFFF"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Pad.as: a 300 KB string constant for the big child (deterministic), an empty one otherwise.
python3 - "$TMP" <<'EOF'
import sys, os
tmp = sys.argv[1]
x = 12345
chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
out = []
for i in range(300000):
    x = (x * 1103515245 + 12345) & 0x7fffffff
    out.append(chars[(x >> 16) & 63])
open(os.path.join(tmp, "PadBig.as"), "w").write('package { public class Pad { public static const DATA:String = "%s"; } }\n' % "".join(out))
open(os.path.join(tmp, "PadNone.as"), "w").write('package { public class Pad { public static const DATA:String = ""; } }\n')
open(os.path.join(tmp, "GrandNone.as"), "w").write('package { public class GrandBytes { public static const HEX:String = ""; } }\n')
EOF

# child <out.swf> <harness true|false> <grandchild> <grand> <Pad.as> <GrandBytes.as>
child() {
  local out=$1 harness=$2 grandchild=$3 grand=$4 pad=$5 gb=$6
  local d="$TMP/c$$RANDOM"; mkdir -p "$d"
  # The grandchild gets its own class name: a loadBytes child domain finds its loader's `Child` first
  # (parent-first lookup), so a grandchild also called `Child` would run the child's constructor again.
  local cls=Child; [ $grandchild = true ] && cls=Grand
  sed "s/\bChild\b/$cls/g" "$HERE/Child.as" > "$d/$cls.as"; cp "$pad" "$d/Pad.as"; cp "$gb" "$d/GrandBytes.as"
  (cd "$d" && java -jar "$ASC_JAR" -AS3 -optimize -import "$PLAYERGLOBAL_ABC" \
     -config CONFIG::harness=$harness -config CONFIG::grandchild=$grandchild -config CONFIG::grand=$grand \
     -in Pad.as -in GrandBytes.as -swf $cls,400,300,10 $cls.as > /dev/null)
  cp "$d/$cls.swf" "$out"
  echo "built $out ($(stat -c%s "$out") bytes)"
}

hexfile() {  # GrandBytes.as from a SWF
  python3 -c "import sys; d=open(sys.argv[1],'rb').read().hex(); open(sys.argv[2],'w').write('package { public class GrandBytes { public static const HEX:String = \"%s\"; } }\n' % d)" "$1" "$2"
}

mkdir -p "$DT/bin"
# A private difftest copy (own port in its H.hx) gets the current probe main.
[ "$(cd "$DT/src" && pwd)" = "$(cd "$HERE/.." && pwd)" ] || cp "$HERE/../LTMain.hx" "$DT/src/"
for flavour in harness trace; do
  if [ $flavour = harness ]; then H=true; HD="-D harness"; OUT="$TMP/h"; else H=false; HD=""; OUT="$TMP/t"; fi
  mkdir -p "$OUT"
  child "$OUT/ltchild.swf" $H false false "$TMP/PadNone.as" "$TMP/GrandNone.as"
  child "$OUT/ltchildbig.swf" $H false false "$TMP/PadBig.as" "$TMP/GrandNone.as"
  child "$OUT/ltgrand.swf" $H true false "$TMP/PadNone.as" "$TMP/GrandNone.as"
  hexfile "$OUT/ltgrand.swf" "$TMP/GrandHex.as"
  child "$OUT/ltchildgrand.swf" $H false true "$TMP/PadNone.as" "$TMP/GrandHex.as"
  # mains (Haxe); the loadBytes variants embed the child SWF as resource "child"
  m() { local out=$1; shift; "${HAXE:-haxe}" -cp "$DT/src" -main LTMain -swf "$out" -swf-version 11 $FR $HD "$@"; echo "built $out ($(stat -c%s "$out") bytes)"; }
  m "$OUT/ltload.swf"
  m "$OUT/ltload_orphan.swf" -D orphan
  m "$OUT/ltload_big.swf" -D big
  m "$OUT/ltload_grand.swf" -D grand
  m "$OUT/ltbytes.swf" -D bytes -resource "$OUT/ltchild.swf@child"
  m "$OUT/ltbytes_big.swf" -D bytes -D big -resource "$OUT/ltchildbig.swf@child"
done
cp "$TMP"/h/*.swf "$DT/bin/"
for v in load load_orphan load_grand bytes bytes_big; do  # load_big: difftest only (the test framework does not stream a download over frames)
  d="$TESTS/timffle_loader_timing_$v"; mkdir -p "$d"
  cp "$TMP/t/lt$v.swf" "$d/test.swf"
  case $v in
    load|load_orphan) cp "$TMP/t/ltchild.swf" "$d/";;
    load_grand) cp "$TMP/t/ltchildgrand.swf" "$d/";;
  esac
done
echo "harness SWFs in $DT/bin, trace SWFs in $TESTS/timffle_loader_timing_*"
