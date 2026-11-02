#!/usr/bin/env bash
# Timffle: automated checks for the WebGPU renderer path (sub-rectangle MSAA
# resolve, WebGPU-first renderer order).
#
#   timffle/scripts/verify-webgpu.sh [unpacked-extension-dir]
#
# Runs, in order:
#   1. the wgpu crate's unit tests (dirty-region tracking, blend rectangles);
#   2. render/wgpu/tests/resolve.rs — resolve.wgsl vs the GPU's own resolve —
#      and render/wgpu/tests/readback.rs — readback.wgsl (the synchronous
#      WebGPU readback) reproduces texture bytes exactly — on lavapipe
#      (software Vulkan) and, when HW_ICD points at a hardware Vulkan ICD
#      (e.g. /usr/share/vulkan/icd.d/nouveau_icd.json), on the GPU;
#   3. Ruffle's image regression suite on the same adapters (the Vulkan
#      backend takes the sub-rectangle path, like WebGPU);
#   4. with an unpacked extension build: the browser differential test —
#      every static regression SWF rendered with wgpu-webgl and with webgpu in
#      the same headless Chrome, screenshots compared pixel by pixel
#      (timffle/tools/webgpu-diff/run.mjs).
#
# Exit status is non-zero when any step fails. Known upstream failures of the
# image suite (listed in KNOWN_FAILURES) are tolerated.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
EXT_DIR=${1:-}
LVP_ICD=${LVP_ICD:-/usr/share/vulkan/icd.d/lvp_icd.json}
HW_ICD=${HW_ICD:-}
OUT=${OUT:-$ROOT/timffle/build/verify-webgpu}
mkdir -p "$OUT"
status=0
KNOWN_FAILURES="avm2/loader_duplicate_class avm2/matrix3d_append_rotation avm2/matrix3d_recompose_edge_cases avm2/textblock_recreateline from_shumway/avm2/flash/geom/matrix3d/TransformBasics from_shumway/flash_net_classes visual/edittext/edittext_caret_multiline visual/edittext/edittext_caret_empty"

step() { echo; echo "=== $*"; }
fail() { echo "FAILED: $*"; status=1; }

step "1. wgpu unit tests"
cargo test -p ruffle_render_wgpu --lib 2>&1 | tail -3 | grep -q "test result: ok" || fail "wgpu unit tests"

adapters=("lavapipe:$LVP_ICD")
[ -n "$HW_ICD" ] && adapters+=("hardware:$HW_ICD")
for entry in "${adapters[@]}"; do
  name=${entry%%:*}; icd=${entry#*:}
  [ -f "$icd" ] || { echo "skip $name: $icd not found"; continue; }
  step "2. resolve shader vs hardware resolve ($name)"
  VK_ICD_FILENAMES=$icd WGPU_BACKEND=vulkan cargo test -p ruffle_render_wgpu --test resolve -- --nocapture 2>&1 \
    | tee "$OUT/resolve-$name.log" | grep -E "adapter:|pixels differing|test result"
  grep -q "test result: ok. 2 passed" "$OUT/resolve-$name.log" || fail "resolve test on $name"

  step "2b. readback shader reproduces texture bytes ($name)"
  VK_ICD_FILENAMES=$icd WGPU_BACKEND=vulkan cargo test -p ruffle_render_wgpu --test readback -- --nocapture 2>&1 \
    | tee "$OUT/readback-$name.log" | grep -E "adapter:|wrong bytes|test result"
  grep -q "test result: ok. 1 passed" "$OUT/readback-$name.log" || fail "readback test on $name"

  step "3. image regression suite ($name)"
  VK_ICD_FILENAMES=$icd WGPU_BACKEND=vulkan cargo test --release -p tests --features imgtests --test tests > "$OUT/imgtests-$name.log" 2>&1
  grep -E "^test result" "$OUT/imgtests-$name.log" | tail -1
  unexpected=0
  while read -r t; do
    case " $KNOWN_FAILURES " in *" $t "*) ;; *) echo "unexpected failure: $t"; unexpected=1;; esac
  done < <(grep -E "^test +(\[!\] +)?[^ ]+ +\.\.\. FAILED" "$OUT/imgtests-$name.log" | sed -E 's/^test +(\[!\] +)?([^ ]+).*/\2/')
  [ "$unexpected" = 0 ] || fail "image suite on $name has unexpected failures"
done

if [ -n "$EXT_DIR" ]; then
  step "4. browser differential test (wgpu-webgl vs webgpu)"
  if [ -f "$ROOT/timffle/tools/webgpu-diff/run.mjs" ]; then
    node "$ROOT/timffle/tools/webgpu-diff/run.mjs" "$EXT_DIR" "$OUT/browser-diff" ${DIFF_ARGS:-} || fail "browser differential run"
    python3 -I "$ROOT/timffle/tools/webgpu-diff/compare.py" "$OUT/browser-diff" > /dev/null 2>&1
    summary=$(grep -E "^Tests:" "$OUT/browser-diff/report.md" 2>/dev/null); echo "$summary"
    # Anything differing or missing is a failure. (Since 0.8.0.26329 the BitmapData.draw +
    # CPU-read SWFs render on WebGPU too: synchronous readback through an OffscreenCanvas.)
    bad=$(grep -E "^\| [^|]+ \| [^|]* \| [^|]* \| (DIFF|MISSING) \|" "$OUT/browser-diff/report.md" | awk -F'|' '{gsub(/ /,"",$2); print $2}' || true)
    if [ -n "$bad" ]; then echo "unexpected differences:"; echo "$bad"; fail "browser differential test"; fi
  else
    echo "timffle/tools/webgpu-diff/run.mjs missing"; status=1
  fi
else
  echo; echo "(no extension dir given: browser differential test skipped)"
fi

echo
[ $status = 0 ] && echo "verify-webgpu: all checks passed" || echo "verify-webgpu: FAILURES above"
exit $status
