#!/usr/bin/env python3
"""The numbers and the picture of what Timffle patches in Ruffle (README, "Relationship with Ruffle").

  ruffle_patches.py summarize --ruffle R.json --timffle T.json [--base 46fec3f]
      R.json and T.json are AVM2 reports written by Ruffle's own tool, once per tree:
          cargo run --locked -p stub-report -- --avm2-report <file>
      (run it in a worktree of the base commit for R.json, sharing CARGO_TARGET_DIR saves most of the build).
      Adds the golden-file counts and the git change sizes and writes timffle/docs/data/ruffle-patches.json.
  ruffle_patches.py svg
      Draws timffle/docs/images/ruffle-patches.svg (English) and the zh-TW / zh-CN copies from that JSON.

The API numbers use the same scoring as Ruffle's website: every API item is one point, a stub costs its point back,
so "implemented" = (points - missing - stubs) / points and stubs are drawn orange.
"""
import argparse
import datetime
import json
import pathlib
import re
import subprocess
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parents[2]
DATA = ROOT / "timffle/docs/data/ruffle-patches.json"
IMAGES = ROOT / "timffle/docs/images"

# The groups drawn on the cards: whole classes plus the 3D members of two 2D classes.
GROUPS = {
    "3d": {
        "classes": ["flash.geom.Vector3D", "flash.geom.Matrix3D", "flash.geom.Utils3D", "flash.geom.PerspectiveProjection"],
        "members": {
            "flash.display.DisplayObject": ["z", "rotationX", "rotationY", "rotationZ", "scaleZ",
                                            "globalToLocal3D()", "local3DToGlobal()"],
            "flash.geom.Transform": ["matrix3D", "perspectiveProjection", "getRelativeMatrix3D()"],
        },
    },
    "net": {
        "classes": ["flash.net.URLStream", "flash.net.URLLoader", "flash.net.LocalConnection", "flash.display.Loader"],
        "members": {},
    },
}


def score(report, group=None):
    """(points, implemented, stubbed) for the whole report or one group."""
    if group is None:
        s = report["summary"]
        return s["max_points"], s["impl_points"], s["stub_penalty"]
    points = impl = stub = 0
    for name in group["classes"]:
        s = report["classes"][name]["summary"]
        points += s["max_points"]
        impl += s["impl_points"]
        stub += s["stub_penalty"]
    for name, members in group["members"].items():
        entry = report["classes"][name]
        points += len(members)
        impl += sum(1 for m in members if m not in entry["missing"])
        stub += sum(1 for m in members if m in entry["stubbed"])
    return points, impl, stub


def as_dict(t):
    return {"points": t[0], "implemented": t[1], "stubbed": t[2]}


def shortstat(base, *paths):
    out = subprocess.run(["git", "-C", str(ROOT), "diff", "--shortstat", base, "HEAD", "--", *paths],
                         capture_output=True, text=True, check=True).stdout
    nums = {k: int(v) for v, k in re.findall(r"(\d+) (file|insertion|deletion)", out)}
    return {"files": nums.get("file", 0), "insertions": nums.get("insertion", 0), "deletions": nums.get("deletion", 0)}


def summarize(args):
    ruffle = json.loads(pathlib.Path(args.ruffle).read_text())
    timffle = json.loads(pathlib.Path(args.timffle).read_text())
    fixed = []
    for name in sorted(ruffle["classes"]):
        r, t = ruffle["classes"][name], timffle["classes"].get(name)
        if t is None:
            continue
        for member in sorted(set(r["missing"]) - set(t["missing"])):
            fixed.append({"class": name, "member": member, "was": "missing"})
        for member in sorted(set(r["stubbed"]) - set(t["stubbed"]) - set(t["missing"])):
            fixed.append({"class": name, "member": member, "was": "stub"})
    goldens = {"3d": 0, "net": 0, "basic": 0}
    for f in sorted((ROOT / "timffle/difftest/expected").glob("*.txt")):
        goldens["3d" if f.name.startswith("d") else "basic" if f.name.startswith("t0") else "net"] += 1
    head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short=9", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    data = {
        "measured": args.date or datetime.date.today().isoformat(),
        "ruffle": {"commit": args.base, "label": args.base_label},
        "timffle": {"commit": args.timffle_commit or head},
        "overall": {"ruffle": as_dict(score(ruffle)), "timffle": as_dict(score(timffle))},
        "groups": {k: {"ruffle": as_dict(score(ruffle, g)), "timffle": as_dict(score(timffle, g))}
                   for k, g in GROUPS.items()},
        "fixed": fixed,
        "goldens": dict(goldens, total=sum(goldens.values())),
        "changes": {"engine": shortstat(args.base, "core", "render", "web/src"),
                    "extension": shortstat(args.base, "web/packages/extension")},
    }
    DATA.parent.mkdir(parents=True, exist_ok=True)
    DATA.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("written", DATA.relative_to(ROOT))


def num(n):
    return f"{n:,}"


def texts(lang, d):
    o, g3, gn, ch, gl = d["overall"], d["groups"]["3d"], d["groups"]["net"], d["changes"], d["goldens"]
    eng, ext = ch["engine"], ch["extension"]
    n_fixed = len(d["fixed"])
    if lang == "en":
        return {
            "font": "'Segoe UI', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif",
            "title": "What Timffle patches in Ruffle",
            "subtitle": f"Base: Ruffle {d['ruffle']['label']} ({d['ruffle']['commit']}) · Measured: {d['measured']}",
            "cards": [
                ("AVM2 API (ActionScript 3)", "stub-report",
                 f"Measured with the same tool as Ruffle's website. Timffle turns {n_fixed} Flash Player APIs that "
                 "were stubs or missing into full implementations, mostly in 3D and networking.",
                 f"Scope: all AVM2 APIs ({num(o['ruffle']['points'])} items)", o),
                ("3D and Matrix3D", "0004",
                 "Such as the 3D carousel on a game's login page. Fills in Flash's 3D model: z, rotationX/Y/Z, "
                 "scaleZ, matrix3D, perspective projection, Matrix3D, Utils3D, and projected bounds, hit testing "
                 "and BitmapData.draw.",
                 f"Scope: 3D APIs ({g3['ruffle']['points']} items) · Golden files from real Flash: {gl['3d']}", g3),
                ("Networking and LocalConnection", "0003",
                 "LocalConnection reference cycles and size limit, progressive URLStream, real Loader/URLLoader "
                 "cancellation, URLLoader open timing, AMF3 reference cycles.",
                 f"Scope: 4 classes ({gn['ruffle']['points']} items) · Golden files from real Flash: {gl['net']}", gn),
            ],
            "list_title": "Beyond the API count",
            "list_pill": "0001 · 0002 · 0005",
            "items": [
                "Socket (TCP): the connection helper reaches game servers directly",
                "Chinese text: _sans/_serif no longer drop it; Windows font metrics",
                "Domain lookup is parent-first: a library can't shadow built-ins",
                "Recursion guard on the web: a catchable error, not a dead player",
                "AMF3 encoder reference indices (rust-flash-lso)",
                "Old GPUs with 256 vertex uniform vectors can draw",
                "No drawing while the tab is in the background",
            ],
            "stats": [f"Ruffle engine: {num(eng['files'])} files, +{num(eng['insertions'])}/−{num(eng['deletions'])} lines",
                      f"Chrome extension: {num(ext['files'])} files, +{num(ext['insertions'])}/−{num(ext['deletions'])} lines"],
            "legend": ["In Ruffle", "Patched by Timffle", "Stub (partial)", "Missing"],
            "note": "The API count only checks whether each API is implemented or a stub, not that it behaves exactly "
                    f"like Flash; behaviour is checked against {gl['total']} golden files from Flash Player 32.",
            "sep": ": ",
        }
    if lang == "zh-TW":
        return {
            "font": "'PingFang TC', 'Microsoft JhengHei', 'Noto Sans CJK TC', 'Noto Sans TC', 'Segoe UI', sans-serif",
            "title": "Timffle 對 Ruffle 的修補",
            "subtitle": f"基底：Ruffle {d['ruffle']['label']}（{d['ruffle']['commit']}）　統計日期：{d['measured']}",
            "cards": [
                ("AVM2 API（ActionScript 3）", "stub-report",
                 f"用 Ruffle 官網同一套工具統計 Flash Player API 的實作程度。Timffle 把 {n_fixed} 個原本是空殼或缺少的 "
                 "API 補成完整實作，集中在 3D 與網路。",
                 f"統計範圍：全部 AVM2 API（{num(o['ruffle']['points'])} 項）", o),
                ("3D 與 Matrix3D", "0004",
                 "遊戲登入畫面的 3D 轉盤等。補齊 Flash 的 3D 模型：z、rotationX/Y/Z、scaleZ、matrix3D、透視投影、"
                 "Matrix3D、Utils3D，以及投影後的邊界、命中測試與 BitmapData.draw。",
                 f"統計範圍：3D API（{g3['ruffle']['points']} 項）　真 Flash 黃金答案：{gl['3d']} 份", g3),
                ("網路、載入與 LocalConnection", "0003",
                 "LocalConnection 的循環參照與訊息上限、URLStream 漸進傳輸、Loader／URLLoader 真正取消、"
                 "URLLoader 的 open 時機、AMF3 循環參照。",
                 f"統計範圍：4 個類別（{gn['ruffle']['points']} 項）　真 Flash 黃金答案：{gl['net']} 份", gn),
            ],
            "list_title": "API 統計看不到的修補",
            "list_pill": "0001・0002・0005",
            "items": [
                "Socket（TCP）連線：用連線小幫手直接連遊戲伺服器",
                "中文：_sans／_serif 不再讓中文消失，照 Windows 字型排版",
                "網域查找改成父網域優先，函式庫同名函式不再蓋掉內建",
                "網頁版遞迴保護：丟出可捕捉的錯誤，不再整個當掉",
                "AMF3 編碼器的參照索引（rust-flash-lso）",
                "只有 256 個頂點 uniform 的舊 GPU 也能畫",
                "分頁在背景時不畫畫面",
            ],
            "stats": [f"Ruffle 引擎：{num(eng['files'])} 個檔案，+{num(eng['insertions'])}／−{num(eng['deletions'])} 行",
                      f"Chrome 擴充功能：{num(ext['files'])} 個檔案，+{num(ext['insertions'])}／−{num(ext['deletions'])} 行"],
            "legend": ["Ruffle 原本就有", "Timffle 修補", "空殼（部分實作）", "缺少"],
            "note": f"API 統計只看有沒有實作、是不是空殼，不代表行為完全相同；行為以真 Flash Player 32 的 {gl['total']} 份黃金答案驗證。",
            "sep": "：",
        }
    if lang == "zh-CN":
        return {
            "font": "'PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC', 'Noto Sans SC', 'Segoe UI', sans-serif",
            "title": "Timffle 对 Ruffle 的修补",
            "subtitle": f"基底：Ruffle {d['ruffle']['label']}（{d['ruffle']['commit']}）　统计日期：{d['measured']}",
            "cards": [
                ("AVM2 API（ActionScript 3）", "stub-report",
                 f"用 Ruffle 官网同一套工具统计 Flash Player API 的实现程度。Timffle 把 {n_fixed} 个原本是空壳或缺少的 "
                 "API 补成完整实现，集中在 3D 与网络。",
                 f"统计范围：全部 AVM2 API（{num(o['ruffle']['points'])} 项）", o),
                ("3D 与 Matrix3D", "0004",
                 "游戏登录画面的 3D 转盘等。补齐 Flash 的 3D 模型：z、rotationX/Y/Z、scaleZ、matrix3D、透视投影、"
                 "Matrix3D、Utils3D，以及投影后的边界、命中测试与 BitmapData.draw。",
                 f"统计范围：3D API（{g3['ruffle']['points']} 项）　真 Flash 黄金答案：{gl['3d']} 份", g3),
                ("网络、加载与 LocalConnection", "0003",
                 "LocalConnection 的循环引用与消息上限、URLStream 渐进传输、Loader／URLLoader 真正取消、"
                 "URLLoader 的 open 时机、AMF3 循环引用。",
                 f"统计范围：4 个类别（{gn['ruffle']['points']} 项）　真 Flash 黄金答案：{gl['net']} 份", gn),
            ],
            "list_title": "API 统计看不到的修补",
            "list_pill": "0001・0002・0005",
            "items": [
                "Socket（TCP）连接：用连接助手直接连游戏服务器",
                "中文：_sans／_serif 不再让中文消失，按 Windows 字体排版",
                "域名查找改成父域优先，库里的同名函数不再覆盖内置函数",
                "网页版递归保护：抛出可捕获的错误，不再整个卡死",
                "AMF3 编码器的引用索引（rust-flash-lso）",
                "只有 256 个顶点 uniform 的旧 GPU 也能绘制",
                "标签页在后台时不绘制画面",
            ],
            "stats": [f"Ruffle 引擎：{num(eng['files'])} 个文件，+{num(eng['insertions'])}／−{num(eng['deletions'])} 行",
                      f"Chrome 扩展程序：{num(ext['files'])} 个文件，+{num(ext['insertions'])}／−{num(ext['deletions'])} 行"],
            "legend": ["Ruffle 原本就有", "Timffle 修补", "空壳（部分实现）", "缺少"],
            "note": f"API 统计只看有没有实现、是不是空壳，不代表行为完全相同；行为以真 Flash Player 32 的 {gl['total']} 份黄金答案验证。",
            "sep": "：",
        }
    raise SystemExit(f"unknown language {lang}")


def text_width(s, size):
    """Rough advance width; errs on the wide side so wrapped lines never overflow."""
    w = 0.0
    for ch in s:
        if ord(ch) >= 0x2E80 or ch in "－／（）：，、。；":
            w += 1.0
        elif ch == " ":
            w += 0.3
        elif ch.isupper() or ch.isdigit():
            w += 0.64
        elif ch in "iljtf.,:;'|!()[]/":
            w += 0.34
        else:
            w += 0.56
    return w * size


def wrap(s, width, size):
    tokens = re.findall(r"[A-Za-z0-9_.\-+/()'’%#]+|\s|.", s)
    lines, cur = [], ""
    for tok in tokens:
        if cur and text_width(cur + tok, size) > width:
            lines.append(cur.rstrip())
            cur = "" if tok.isspace() else tok
        else:
            cur += tok
    if cur.strip():
        lines.append(cur.rstrip())
    return lines


GREEN, YELLOW, ORANGE, TRACK = ("#58A55C", "#4A9150"), ("#FFD038", "#F0BC18"), ("#F28C3A", "#DD7A2C"), "#DCE7F3"


def pct(t):
    return 100 * (t["implemented"] - t["stubbed"]) / t["points"], 100 * t["stubbed"] / t["points"]


def fmt_pct(v):
    return "100%" if v >= 99.995 else f"{v:.1f}%"


def draw(lang, d):
    T = texts(lang, d)
    W, PAD, GAP = 1200, 28, 24
    CW = (W - 2 * PAD - GAP) // 2
    INNER = CW - 2 * 26
    out = []
    bar_id = [0]

    def text(x, y, s, size, fill, weight="normal", anchor="start"):
        out.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" font-weight="{weight}" '
                   f'text-anchor="{anchor}">{escape(s)}</text>')

    def pill(right, y, s):
        w = text_width(s, 14) + 26
        out.append(f'<rect x="{right - w:.1f}" y="{y}" width="{w:.1f}" height="28" rx="7" fill="#2E5A8C"/>')
        text(right - w / 2, y + 19, s, 14, "#E9F2FB", anchor="middle")
        return w

    def title(x, y, s, room):
        size = 25
        while size > 18 and text_width(s, size) * 1.08 > room:
            size -= 1
        text(x, y, s, size, "#FFD038", "bold")

    def bar(x, y, w, segments):
        bar_id[0] += 1
        cid = f"b{lang}{bar_id[0]}"
        out.append(f'<clipPath id="{cid}"><rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="16" rx="8"/></clipPath>')
        out.append(f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="16" rx="8" fill="{TRACK}"/>')
        pos = x
        for share, pattern in segments:
            sw = w * share / 100
            if sw > 0:
                out.append(f'<rect x="{pos:.2f}" y="{y}" width="{sw:.2f}" height="16" fill="url(#{pattern})" '
                           f'clip-path="url(#{cid})"/>')
            pos += sw

    def bar_card(x, y, h, card):
        name, tag, desc, scope, group = card
        out.append(f'<rect x="{x}" y="{y}" width="{CW}" height="{h}" rx="14" fill="#1F4A78"/>')
        title(x + 26, y + 42, name, CW - 48 - pill(x + CW - 22, y + 20, tag) - 16)
        ty = y + 76
        for line in wrap(desc, INNER, 16):
            text(x + 26, ty, line, 16, "#EAF2FB")
            ty += 24
        text(x + 26, ty + 8, scope, 13.5, "#A9C6E6")
        ry = ty + 34
        r_green, r_stub = pct(group["ruffle"])
        t_green, t_stub = pct(group["timffle"])
        label_w = 178
        rows = [("Ruffle", r_green, [(r_green, "pg"), (r_stub, "po")]),
                ("Timffle", t_green, [(min(r_green, t_green), "pg"), (max(0, t_green - r_green), "py"),
                                      (t_stub, "po")])]
        for name, value, segs in rows:
            text(x + 26, ry + 13, f"{name}{T['sep']}{fmt_pct(value)}", 16, "#FFD038", "bold")
            bar(x + 26 + label_w, ry, CW - 52 - label_w, segs)
            ry += 34
        return ry - y

    def list_card(x, y, h):
        out.append(f'<rect x="{x}" y="{y}" width="{CW}" height="{h}" rx="14" fill="#1F4A78"/>')
        title(x + 26, y + 42, T["list_title"], CW - 48 - pill(x + CW - 22, y + 20, T["list_pill"]) - 16)
        ty = y + 78
        for item in T["items"]:
            lines = wrap(item, INNER - 26, 15.5)
            text(x + 26, ty, "✓", 16, "#7BD389", "bold")
            for line in lines:
                text(x + 50, ty, line, 15.5, "#EAF2FB")
                ty += 23
            ty += 3
        ty += 6
        for s in T["stats"]:
            text(x + 26, ty, s, 14, "#A9C6E6")
            ty += 22
        return ty - y

    def measure(fn, *a):
        saved = len(out)
        hgt = fn(*a)
        del out[saved:]
        return hgt

    head = 112
    c1, c2, c3 = T["cards"]
    row1 = max(measure(bar_card, PAD, head, 0, c1), measure(bar_card, PAD, head, 0, c2)) + 10
    y2 = head + row1 + GAP
    row2 = max(measure(bar_card, PAD, y2, 0, c3), measure(list_card, PAD, y2, 0)) + 14
    legend_y = y2 + row2 + 38
    note_lines = wrap(T["note"], W - 2 * PAD, 13.5)
    H = legend_y + 26 + 20 * len(note_lines) + 18

    text(PAD, 52, T["title"], 32, "#FFD038", "bold")
    text(PAD, 84, T["subtitle"], 15, "#A9C6E6")
    bar_card(PAD, head, row1, c1)
    bar_card(PAD + CW + GAP, head, row1, c2)
    bar_card(PAD, y2, row2, c3)
    list_card(PAD + CW + GAP, y2, row2)
    lx = PAD
    for label, pattern in zip(T["legend"], ["pg", "py", "po", None]):
        fill = f"url(#{pattern})" if pattern else TRACK
        out.append(f'<rect x="{lx}" y="{legend_y - 13}" width="30" height="14" rx="7" fill="{fill}"/>')
        text(lx + 40, legend_y, label, 14.5, "#EAF2FB")
        lx += 40 + text_width(label, 14.5) + 34
    ny = legend_y + 30
    for line in note_lines:
        text(PAD, ny, line, 13.5, "#A9C6E6")
        ny += 20

    defs = []
    for pid, (c1_, c2_) in (("pg", GREEN), ("py", YELLOW), ("po", ORANGE)):
        defs.append(f'<pattern id="{pid}" width="12" height="12" patternUnits="userSpaceOnUse" '
                    f'patternTransform="rotate(45)"><rect width="12" height="12" fill="{c1_}"/>'
                    f'<rect width="6" height="12" fill="{c2_}"/></pattern>')
    alt = escape(T["title"])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
            f'role="img" aria-label="{alt}" font-family="{escape(T["font"], {chr(39): "&apos;"})}">\n'
            f'<title>{alt}</title>\n<defs>{"".join(defs)}</defs>\n'
            f'<rect width="{W}" height="{H}" rx="18" fill="#163A61"/>\n' + "\n".join(out) + "\n</svg>\n")


def svg(_args):
    d = json.loads(DATA.read_text(encoding="utf-8"))
    for lang, path in (("en", IMAGES / "ruffle-patches.svg"), ("zh-TW", IMAGES / "zh-TW/ruffle-patches.svg"),
                       ("zh-CN", IMAGES / "zh-CN/ruffle-patches.svg")):
        path.write_text(draw(lang, d), encoding="utf-8")
        print("written", path.relative_to(ROOT))


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("summarize")
    s.add_argument("--ruffle", required=True)
    s.add_argument("--timffle", required=True)
    s.add_argument("--base", default="46fec3f")
    s.add_argument("--base-label", default="nightly-2026-10-13")
    s.add_argument("--timffle-commit")
    s.add_argument("--date")
    s.set_defaults(fn=summarize)
    sub.add_parser("svg").set_defaults(fn=svg)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
