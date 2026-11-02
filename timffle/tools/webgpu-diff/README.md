# WebGPU vs WebGL differential test for Timffle

Renders Ruffle's static regression SWFs twice in the same headless Chrome build with the
Timffle extension — once with `preferredRenderer = "wgpu-webgl"`, once with `"webgpu"`
(SwiftShader Vulkan) — and compares the screenshots pixel by pixel. It checks that the
WebGPU path (incl. the new `resolve.wgsl` sub-rect MSAA resolve) draws the same thing as
the WebGL path; it does not compare against Flash or Ruffle's expected.png.

## Files

- `select_tests.py <swf root> [--filter re]` — picks the tests (see rules below), prints JSON.
- `run.mjs <ext dir> <out dir> [--filter re] [--jobs N] [--swfs dir] [--renderers a,b]` —
  one Chrome per renderer, N tabs in parallel, `<out>/<renderer>/<test>.png` + `results.json`.
- `compare.py <out dir> [--a wgpu-webgl] [--b webgpu] [--noise 1]` — `report.md`, `compare.json`,
  `sbs/<test>.png` (A | B | diff x8, green = above noise) for every DIFF.
- `out-26328/` — results for the 0.8.0.26328 test build (`report.md`, `notes.md`, PNGs).

## How to run

```sh
cd timffle/tools/webgpu-diff
node run.mjs ../ext-final out-XXXX --jobs 4        # ~10 min for 242 tests
python3 -I compare.py out-XXXX                      # a few seconds
```

Environment knobs: `LOAD_TIMEOUT` (ms, default 25000), `SETTLE_MS` (default 500; use 3000
for video tests), `KEEP_CHROME_DIR=1` keeps `chrome-<renderer>/chrome-stderr.log`,
`CHROME_WINDOW_SIZE` (default 1600,1200). Chrome is launched with
`--enable-unsafe-webgpu --enable-features=Vulkan --use-webgpu-adapter=swiftshader` for both
renderers (same binary, same flags; only the storage.sync key differs). Chrome is closed
and SIGKILLed at the end of each renderer pass; check `pgrep chrome` if a run was aborted.

Per test: navigate to a page with `<embed src="test.swf" width=W height=H>` (W/H from
`player_options.viewport_dimensions`, else the SWF header stage size), wait for
`readyState >= 2`, wait for the `Used renderer: <name>` console line (5 s max), wait
`SETTLE_MS`, `Page.captureScreenshot` clipped to the player's bounding rect. Console
errors / exceptions / wgpu panics and the renderer name are recorded in `results.json`.

## Test selection (select_tests.py)

From `Timffle/tests/tests/swfs/**/test.toml` (single-config tests; `[subtests]` skipped):
must have `[image_comparisons]` and be static: `num_frames = 1`, or no `num_frames` and
`num_ticks = 1`, or under `visual/` with `num_frames <= 2`. Skipped: `known_failure`
(test-level or on any image comparison), `ignore = true`, `[input]`/`input.json`,
`sleep_to_meet_frame_rate`, missing `test.swf`. 242 tests on 2026-11-02 (visual 106,
avm2 76, from_shumway 31, avm1 16, stage3d 5, text 5, fonts 2, import_assets 1).

To add a test: drop a directory with `test.swf` + `test.toml` (same fields as Ruffle's)
under the corpus, or point `--swfs` at another root with the same layout. `--filter` is
a regex on the test's relative path.

## Expected runtime

Extension load ~18 s per renderer; first SWF on each tab ~15 s (wasm compile), then
~1 s/test on WebGL and ~5 s/test on WebGPU (SwiftShader). Full corpus with `--jobs 4`:
WebGL ~2.5 min, WebGPU ~7 min, total ~9.5 min on this 44-core box.

## Reading the report

- `identical` — byte-identical pixels. `noise` — max channel diff <= 1 (rounding;
  expected on gradients / Stage3D).
- `DIFF` — max channel diff > 1: look at `sbs/<test>.png`. Means the WebGPU and WebGL
  backends disagree on this SWF. Before blaming the renderer, rerun with `SETTLE_MS=3000`
  (video and anything that loads assets asynchronously can be timing).
- `MISSING` — one renderer did not produce a screenshot: timeout on load/evaluate/screenshot,
  renderer crash, or harness error; `results.json` has the message. A WebGPU-only MISSING
  that reproduces with `--jobs 1 LOAD_TIMEOUT=150000` is a hang in the WebGPU path.
- `webgpu runs whose console did not report 'Used renderer: webgpu'` must be 0, otherwise
  the WebGPU pass silently fell back to WebGL and the comparison is meaningless.
