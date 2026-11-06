#!/bin/sh
# Measure Timffle's AVM2 API coverage with Ruffle's own stub-report. Run from the repository root:
#   sh timffle/docs/api100/measure.sh   -> timffle/docs/api100/reports/<UTC date>-<short sha>.json + one summary line
# Needs Rust (cargo) and Java (asc.jar). If stub-report fails with "Could not find or load main class
# macromedia.asc.embedding.ScriptCompiler", run `cargo clean -p asc -p build_playerglobal` first (a stale build dir).
set -eu
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R"
sha=$(git rev-parse --short=9 HEAD)
out=timffle/docs/api100/reports/$(date -u +%Y%m%d-%H%M)-$sha.json
mkdir -p timffle/docs/api100/reports
cargo run --locked -q -p stub-report -- --avm2-report "$out"
python3 -I - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["summary"]
missing = sum(len(c["missing"]) for c in d["classes"].values())
stubs = sum(len(c["stubbed"]) for c in d["classes"].values())
pct = 100 * (s["impl_points"] - s["stub_penalty"]) / s["max_points"]
print(f"{sys.argv[1]}: {pct:.2f}% implemented ({s['max_points']} items, {missing} missing, {stubs} stubs)")
PY
