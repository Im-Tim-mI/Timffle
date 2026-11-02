#!/usr/bin/env python3
"""compare.py <out dir> [--a wgpu-webgl] [--b webgpu] [--noise 1]

Compares <out dir>/<a>/<test>.png with <out dir>/<b>/<test>.png for every test in
<out dir>/results.json. Writes:
  <out dir>/report.md          table: test, differing pixels, max channel diff, status
  <out dir>/compare.json       the same data, machine readable
  <out dir>/sbs/<test>.png     A | B | amplified diff, for every test with max diff > noise
Status: identical (0 differing pixels), noise (max channel diff <= --noise),
DIFF (max channel diff > noise), MISSING (a run failed), SIZE (different sizes).
"""
import json, sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw


def arg(k, d):
    return sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d


def main():
    out = Path(sys.argv[1])
    a_name, b_name, noise = arg("--a", "wgpu-webgl"), arg("--b", "webgpu"), int(arg("--noise", 1))
    res = json.loads((out / "results.json").read_text())
    ra, rb = res["renderers"][a_name]["tests"], res["renderers"][b_name]["tests"]
    sbs = out / "sbs"; sbs.mkdir(exist_ok=True)
    rows = []
    for name in sorted(set(ra) | set(rb)):
        fn = name.replace("/", "__") + ".png"
        pa, pb = out / a_name / fn, out / b_name / fn
        row = {"test": name, "pixels": None, "max": None, "status": None,
               "a_errors": ra.get(name, {}).get("errors", ["not run"]), "b_errors": rb.get(name, {}).get("errors", ["not run"]),
               "b_renderer": rb.get(name, {}).get("renderer"), "a_renderer": ra.get(name, {}).get("renderer")}
        if not (ra.get(name, {}).get("ok") and rb.get(name, {}).get("ok") and pa.exists() and pb.exists()):
            row["status"] = "MISSING"
        else:
            ia, ib = Image.open(pa).convert("RGBA"), Image.open(pb).convert("RGBA")
            if ia.size != ib.size:
                row["status"] = "SIZE"; row["note"] = f"{ia.size} vs {ib.size}"
            else:
                diff = ImageChops.difference(ia, ib)
                # per-pixel max over channels
                bands = diff.split()
                m = bands[0]
                for b in bands[1:]:
                    m = ImageChops.lighter(m, b)
                hist = m.histogram()
                row["pixels"] = sum(hist[1:])
                row["max"] = max(i for i, c in enumerate(hist) if c) if row["pixels"] else 0
                row["pixels_gt_noise"] = sum(hist[noise + 1:])
                row["status"] = "identical" if row["pixels"] == 0 else ("noise" if row["max"] <= noise else "DIFF")
                if row["status"] == "DIFF":
                    w, h = ia.size
                    amp = m.point(lambda v: min(255, v * 8))
                    dimg = Image.merge("RGB", (amp, m.point(lambda v: 255 if v > noise else 0), amp))
                    canvas = Image.new("RGB", (w * 3 + 20, h + 18), "#444")
                    canvas.paste(ia.convert("RGB"), (0, 18)); canvas.paste(ib.convert("RGB"), (w + 10, 18)); canvas.paste(dimg, (2 * w + 20, 18))
                    d = ImageDraw.Draw(canvas)
                    d.text((2, 2), a_name, fill="white"); d.text((w + 12, 2), b_name, fill="white"); d.text((2 * w + 22, 2), f"diff x8 (green = >{noise})  px={row['pixels']} max={row['max']}", fill="white")
                    canvas.save(sbs / fn)
        rows.append(row)

    counts = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    b_wrong = [r["test"] for r in rows if r["b_renderer"] != b_name]
    b_err = [r for r in rows if r["b_errors"] and r["b_errors"] != ["not run"]]
    a_err = [r for r in rows if r["a_errors"] and r["a_errors"] != ["not run"]]
    rr = res["renderers"]
    lines = [f"# WebGPU vs WebGL differential report — Timffle {res['version']}", "",
             f"Chrome: {res['chrome']}; args {' '.join(res['chromeArgs'])}; jobs={res['jobs']}; settle={res['settleMs']} ms; started {res['started']}",
             f"Runtime: {a_name} {rr[a_name]['totalMs']/1000:.0f} s, {b_name} {rr[b_name]['totalMs']/1000:.0f} s, total {res.get('totalMs', 0)/1000:.0f} s", "",
             f"Tests: {len(rows)}; " + ", ".join(f"{k}: {v}" for k, v in sorted(counts.items())) + f" (noise = max channel diff <= {noise})",
             f"{b_name} runs whose console did not report 'Used renderer: {b_name}': {len(b_wrong)}" + (f" -> {', '.join(b_wrong[:20])}" if b_wrong else ""),
             f"Tests with console errors: {a_name} {len(a_err)}, {b_name} {len(b_err)}", ""]
    diffs = sorted([r for r in rows if r["status"] == "DIFF"], key=lambda r: (-(r["max"] or 0), -(r["pixels"] or 0)))
    if diffs:
        lines += ["## Differing tests (sorted by max diff, then pixels)", "", "| test | pixels differing | pixels > noise | max channel diff | side-by-side |", "|---|---:|---:|---:|---|"]
        for r in diffs:
            lines.append(f"| {r['test']} | {r['pixels']} | {r['pixels_gt_noise']} | {r['max']} | [sbs](sbs/{r['test'].replace('/', '__')}.png) |")
        lines.append("")
    only_b = [r for r in b_err if r["b_errors"] != r["a_errors"]]
    if only_b or a_err:
        lines += ["## Console errors", ""]
        for r in rows:
            if r["a_errors"] and r["a_errors"] != ["not run"] or r["b_errors"] and r["b_errors"] != ["not run"]:
                lines.append(f"- {r['test']}: {a_name}: {r['a_errors'] or '-'} | {b_name}: {r['b_errors'] or '-'}")
        lines.append("")
    lines += ["## All tests", "", "| test | pixels differing | max channel diff | status |", "|---|---:|---:|---|"]
    for r in rows:
        lines.append(f"| {r['test']} | {r['pixels'] if r['pixels'] is not None else '-'} | {r['max'] if r['max'] is not None else '-'} | {r['status']}{(' ' + r['note']) if r.get('note') else ''} |")
    (out / "report.md").write_text("\n".join(lines) + "\n")
    (out / "compare.json").write_text(json.dumps({"counts": counts, "rows": rows}, indent=1))
    print("\n".join(lines[:8]))
    for r in diffs[:15]:
        print(f"DIFF {r['test']}: px={r['pixels']} (> noise {r['pixels_gt_noise']}) max={r['max']}")


if __name__ == "__main__":
    main()
