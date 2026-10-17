#!/usr/bin/env python3
"""Generate the Timffle logo (word mark) and icons.

The artwork is plain geometry (rectangles and polygons), so it renders the same everywhere and needs no
font. It is original Timffle artwork, deliberately unlike the Ruffle logo, and is covered by the
repository licence (MIT OR Apache-2.0).

Usage: python3 timffle/branding/make_branding.py [--check]
  Writes timffle/branding/{timffle-logo.svg,timffle-icon.svg,splash-logo.tsx.txt} and the copies used by the
  web packages (extension images, demo page). --check only verifies that the files on disk are current.
Needs Pillow (python3-pil) for the PNG icons.
"""
import io
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "timffle" / "branding"

FACE = "#38b6ff"  # letter face
SHADE = "#145a86"  # letter shadow / depth
ICON_BG_TOP = (40, 150, 225)
ICON_BG_BOTTOM = (18, 84, 140)

# Block letters on a 100-unit-high grid: (width, [shapes]); a shape is ("rect", x, y, w, h) or ("poly", [(x, y), ...]).
S = 22  # stroke
LETTERS = {
    "T": (80, [("rect", 0, 0, 80, S), ("rect", 29, 0, S, 100)]),
    "I": (S, [("rect", 0, 0, S, 100)]),
    "M": (96, [("rect", 0, 0, S, 100), ("rect", 96 - S, 0, S, 100),
               ("poly", [(0, 0), (S + 4, 0), (48, 40), (96 - S - 4, 0), (96, 0), (48, 74)])]),
    "F": (68, [("rect", 0, 0, S, 100), ("rect", 0, 0, 68, S), ("rect", 0, 40, 56, 20)]),
    "L": (64, [("rect", 0, 0, S, 100), ("rect", 0, 100 - S, 64, S)]),
    "E": (68, [("rect", 0, 0, S, 100), ("rect", 0, 0, 68, S), ("rect", 0, 40, 58, 20), ("rect", 0, 100 - S, 68, S)]),
}
WORD = "TIMFFLE"
GAP = 14
DEPTH = 7  # shadow offset
MARGIN = 10


def word_shapes():
    """Absolute shapes of the word, origin at the top-left of the first letter."""
    x = 0
    out = []
    for ch in WORD:
        w, shapes = LETTERS[ch]
        for s in shapes:
            if s[0] == "rect":
                out.append(("rect", s[1] + x, s[2], s[3], s[4]))
            else:
                out.append(("poly", [(px + x, py) for px, py in s[1]]))
        x += w + GAP
    return out, x - GAP


def svg_shape(s, dx, dy, fill):
    if s[0] == "rect":
        _, x, y, w, h = s
        return f'<rect x="{x + dx}" y="{y + dy}" width="{w}" height="{h}" rx="3" fill="{fill}"/>'
    pts = " ".join(f"{px + dx},{py + dy}" for px, py in s[1])
    return f'<polygon points="{pts}" fill="{fill}"/>'


def logo_svg():
    shapes, width = word_shapes()
    w, h = width + 2 * MARGIN + DEPTH, 100 + 2 * MARGIN + DEPTH
    body = [svg_shape(s, MARGIN + DEPTH, MARGIN + DEPTH, SHADE) for s in shapes]
    body += [svg_shape(s, MARGIN, MARGIN, FACE) for s in shapes]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" role="img" aria-label="Timffle">'
            "<title>Timffle</title>" + "".join(body) + "</svg>\n"), (w, h)


def splash_tsx():
    """JSX children for the splash-screen <svg class="logo"> in web/packages/core/src/internal/ui/splash-screen.tsx."""
    shapes, _ = word_shapes()
    lines = []
    for dx, fill in ((MARGIN + DEPTH, SHADE), (MARGIN, FACE)):
        for s in shapes:
            lines.append(svg_shape(s, dx, dx, fill).replace("/>", "></" + ("rect" if s[0] == "rect" else "polygon") + ">"))
    return "\n".join(lines) + "\n"


ICON_T = [("rect", 18, 22, 64, 16), ("rect", 41, 22, 18, 58)]  # on a 100x100 canvas


def icon_svg():
    body = "".join(svg_shape(s, 4, 4, SHADE) for s in ICON_T) + "".join(svg_shape(s, 0, 0, "#ffffff") for s in ICON_T)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Timffle">'
            "<title>Timffle</title><defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
            f'<stop offset="0" stop-color="rgb{ICON_BG_TOP}"/><stop offset="1" stop-color="rgb{ICON_BG_BOTTOM}"/>'
            '</linearGradient></defs><rect x="2" y="2" width="96" height="96" rx="20" fill="url(#g)"/>'
            + body + "</svg>\n")


def icon_png(size):
    """Render the icon with Pillow, supersampled 8x, as deterministic PNG bytes."""
    n = 100 * 8
    k = n / 100
    bg = Image.new("RGBA", (n, n))
    grad = ImageDraw.Draw(bg)
    for y in range(n):
        t = y / (n - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(ICON_BG_TOP, ICON_BG_BOTTOM)) + (255,)
        grad.line([(0, y), (n, y)], fill=c)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle([2 * k, 2 * k, 98 * k, 98 * k], radius=20 * k, fill=255)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    for off, fill in ((4, SHADE), (0, "#ffffff")):
        for _, x, y, w, h in ICON_T:
            d.rounded_rectangle([(x + off) * k, (y + off) * k, (x + off + w) * k, (y + off + h) * k], radius=3 * k, fill=fill)
    img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def outputs():
    logo, _ = logo_svg()
    icon = icon_svg()
    files = {
        BRANDING / "timffle-logo.svg": logo.encode(),
        BRANDING / "timffle-icon.svg": icon.encode(),
        BRANDING / "splash-logo.tsx.txt": splash_tsx().encode(),
        ROOT / "web/packages/extension/assets/images/logo.svg": logo.encode(),
        ROOT / "web/packages/demo/public/logo.svg": logo.encode(),
    }
    for size in (16, 32, 48, 128, 180):
        files[ROOT / f"web/packages/extension/assets/images/icon{size}.png"] = icon_png(size)
    for size in (32, 180):
        files[ROOT / f"web/packages/demo/public/icon{size}.png"] = icon_png(size)
    return files


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for path, data in outputs().items():
        if path.exists() and path.read_bytes() == data:
            continue
        if check:
            stale.append(path.relative_to(ROOT))
        else:
            path.write_bytes(data)
            print("wrote", path.relative_to(ROOT))
    if stale:
        print("stale branding files (run timffle/branding/make_branding.py):", *stale, sep="\n  ")
        sys.exit(1)


if __name__ == "__main__":
    main()
