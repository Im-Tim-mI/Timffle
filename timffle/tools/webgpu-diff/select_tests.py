#!/usr/bin/env python3
"""select_tests.py <swf root> [--filter regex] -> JSON list of deterministic image tests.

Walks Ruffle's regression corpus (tests/tests/swfs), parses every test.toml the
same way tests/framework does (single-config tests only; [subtests] skipped) and
keeps tests that have an [image_comparisons] block and are static enough to be
screenshotted in a browser:
  * num_frames == 1, or no num_frames and num_ticks == 1, or
  * anything under visual/ with num_frames <= 2.
Skips: known_failure (test or any image comparison), ignore, [input]/input.json,
sleep_to_meet_frame_rate, missing test.swf.
The viewport is player_options.viewport_dimensions when present, else the SWF
header's stage size (FWS/CWS/ZWS all handled).
"""
import json, lzma, re, struct, sys, tomllib, zlib
from pathlib import Path


def swf_stage_size(path):
    data = path.read_bytes()
    sig = data[:3]
    body = data[8:8 + 64]
    if sig == b"CWS":
        body = zlib.decompressobj().decompress(data[8:], 64)
    elif sig == b"ZWS":
        # ZWS: 4-byte compressed length, 5-byte LZMA props, then raw LZMA stream
        props = data[12:17]
        dec = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=[lzma._decode_filter_properties(lzma.FILTER_LZMA1, props)])
        body = dec.decompress(data[17:], 64)
    elif sig != b"FWS":
        raise ValueError("not a SWF")
    nbits = body[0] >> 3
    bits = "".join(f"{b:08b}" for b in body[:1 + (5 + nbits * 4 + 7) // 8])
    vals = [int(bits[5 + i * nbits:5 + (i + 1) * nbits], 2) for i in range(4)]
    if vals and bits[5] == "1":  # signed; stage rects are positive in practice
        pass
    xmin, xmax, ymin, ymax = vals
    return max(1, round((xmax - xmin) / 20)), max(1, round((ymax - ymin) / 20))


def main():
    root = Path(sys.argv[1])
    flt = None
    if "--filter" in sys.argv:
        flt = re.compile(sys.argv[sys.argv.index("--filter") + 1])
    out, skipped = [], {}
    for toml_path in sorted(root.rglob("test.toml")):
        d = toml_path.parent
        name = d.relative_to(root).as_posix()
        if flt and not flt.search(name):
            continue
        try:
            o = tomllib.loads(toml_path.read_text())
        except Exception:
            skipped[name] = "toml parse"; continue
        if "image_comparisons" not in o or "subtests" in o:
            continue
        if not (d / "test.swf").exists():
            skipped[name] = "no test.swf"; continue
        nf, nt = o.get("num_frames"), o.get("num_ticks")
        static = (nf == 1) or (nf is None and nt == 1) or (name.startswith("visual/") and nf is not None and nf <= 2)
        if not static:
            continue
        why = None
        if o.get("known_failure"): why = "known_failure"
        elif o.get("ignore"): why = "ignore"
        elif "input" in o or (d / "input.json").exists(): why = "needs input"
        elif o.get("sleep_to_meet_frame_rate"): why = "sleep_to_meet_frame_rate"
        elif any(c.get("known_failure") for c in o["image_comparisons"].values()): why = "image known_failure"
        if why:
            skipped[name] = why; continue
        po = o.get("player_options", {})
        vd = po.get("viewport_dimensions")
        try:
            w, h = (vd["width"], vd["height"]) if vd else swf_stage_size(d / "test.swf")
        except Exception as e:
            skipped[name] = f"swf header: {e}"; continue
        out.append({
            "name": name, "swf": (d / "test.swf").as_posix(), "width": int(w), "height": int(h),
            "num_frames": nf, "num_ticks": nt,
            "quality": (po.get("with_renderer") or {}).get("quality"),
            "tolerance": max([c.get("tolerance", 0) for c in o["image_comparisons"].values()] or [0]),
        })
    json.dump({"tests": out, "skipped": skipped}, sys.stdout, indent=1)


if __name__ == "__main__":
    main()
