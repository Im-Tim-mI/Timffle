#!/usr/bin/env python3
"""Generate the Timffle logo (word mark) and icons.

The artwork is plain geometry (rectangles, polygons, a gradient and one soft shadow), so it renders the same
everywhere and needs no font. The icon is a white T and a yellow play triangle on an azure tile. It is
original Timffle artwork, deliberately unlike the Ruffle logo, and is covered by the repository licence
(MIT OR Apache-2.0).

Usage: python3 timffle/branding/make_branding.py [--check]
  Writes timffle/branding/{timffle-logo.svg,timffle-icon.svg,splash-logo.tsx.txt,social-preview.png}, the copies
  used by the web packages (extension images, demo page) and the desktop app artwork (about logo, window and
  installer icons, macOS iconset, Linux icon, WiX installer banner/dialog). --check only verifies that the files
  on disk are current.
Needs Pillow (python3-pil) for the PNG icons.
"""
import io
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "timffle" / "branding"

FACE = "#38b6ff"  # letter face
SHADE = "#145a86"  # letter shadow / depth
ICON_BG_TOP = (40, 150, 225)  # background panels (social preview, installer dialog), not the icon tile
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


# The icon, on a 100-unit square canvas: a white T and a yellow play triangle on an azure rounded tile. The T is
# the letter, the triangle says "player", and it sits in the empty corner under the crossbar. The SVG and the
# Pillow rendering below are drawn from the same numbers.
ICON_TOP = (36, 148, 238)  # tile gradient, top and bottom
ICON_BOTTOM = (10, 70, 160)
ICON_PLAY = (255, 208, 56)  # the play triangle
ICON_SHADOW = (4, 30, 90)  # one soft shadow under the T and the triangle
ICON_SHADOW_OPACITY = 0.37
ICON_SHADOW_DY, ICON_SHADOW_BLUR = 2.2, 2.4
ICON_TILE = (2, 2, 98, 98, 22)  # x0, y0, x1, y1, corner radius
ICON_T = [(15.5, 19, 79.5, 36, 5), (38.5, 19, 56.5, 81, 5)]  # crossbar and stem: x0, y0, x1, y1, corner radius
ICON_TRI = [(64, 45), (64, 81), (88, 63)]  # the play triangle ...
ICON_TRI_R = 3.2  # ... with its corners rounded by this radius


def num(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def inset_triangle(pts, r):
    """The triangle moved inwards by r on every side. Drawn with a round stroke of width 2r it is the original
    triangle with rounded corners."""
    (ax, ay), (bx, by), (cx, cy) = pts
    a, b, c = math.dist(pts[1], pts[2]), math.dist(pts[0], pts[2]), math.dist(pts[0], pts[1])
    s = a + b + c
    ix, iy = (a * ax + b * bx + c * cx) / s, (a * ay + b * by + c * cy) / s  # incenter
    rho = abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) / s  # inradius
    f = (rho - r) / rho
    return [(ix + (x - ix) * f, iy + (y - iy) * f) for x, y in pts]


def icon_svg():
    tri = " ".join(f"{num(x)},{num(y)}" for x, y in inset_triangle(ICON_TRI, ICON_TRI_R))
    play = "#%02x%02x%02x" % ICON_PLAY
    shadow = "#%02x%02x%02x" % ICON_SHADOW
    bars = "".join(f'<rect x="{num(x0)}" y="{num(y0)}" width="{num(x1 - x0)}" height="{num(y1 - y0)}" rx="{num(r)}" fill="#ffffff"/>'
                   for x0, y0, x1, y1, r in ICON_T)
    tx0, ty0, tx1, ty1, tr = ICON_TILE
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Timffle">'
            "<title>Timffle</title><defs>"
            '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="rgb{ICON_TOP}"/><stop offset="1" stop-color="rgb{ICON_BOTTOM}"/></linearGradient>'
            '<filter id="s" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">'
            f'<feGaussianBlur in="SourceAlpha" stdDeviation="{num(ICON_SHADOW_BLUR)}"/><feOffset dy="{num(ICON_SHADOW_DY)}" result="b"/>'
            f'<feFlood flood-color="{shadow}" flood-opacity="{num(ICON_SHADOW_OPACITY)}"/><feComposite in2="b" operator="in"/>'
            '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>'
            f'<rect x="{num(tx0)}" y="{num(ty0)}" width="{num(tx1 - tx0)}" height="{num(ty1 - ty0)}" rx="{num(tr)}" fill="url(#g)"/>'
            f'<g filter="url(#s)">{bars}'
            f'<polygon points="{tri}" fill="{play}" stroke="{play}" stroke-width="{num(2 * ICON_TRI_R)}" stroke-linejoin="round"/></g>'
            "</svg>\n")


def fit_to_pixels(box, size):
    """Small icons only: move the edges of a rounded rectangle onto whole pixels of the target size, so the T stays
    crisp in the toolbar. The SVG is the master and is not fitted."""
    x0, y0, x1, y1, r = box
    s = size / 100
    nx0, ny0, nx1, ny1 = (round(v * s) / s for v in (x0, y0, x1, y1))
    return nx0, ny0, max(nx1, nx0 + 1 / s), max(ny1, ny0 + 1 / s), r


def icon_image(size):
    """Render the icon with Pillow, supersampled, as an RGBA image."""
    ss = max(2, min(8, 2048 // size))
    n = size * ss
    k = n / 100
    x0, y0, x1, y1, r = ICON_TILE
    # tile: vertical gradient over the tile's own height, through a rounded-rectangle mask
    grad = Image.new("RGBA", (n, n))
    gd = ImageDraw.Draw(grad)
    for y in range(n):
        t = min(1.0, max(0.0, (y - y0 * k) / ((y1 - y0) * k - 1)))
        gd.line([(0, y), (n, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(ICON_TOP, ICON_BOTTOM)) + (255,))
    tile = Image.new("L", (n, n), 0)
    ImageDraw.Draw(tile).rounded_rectangle([x0 * k, y0 * k, x1 * k - 1, y1 * k - 1], radius=r * k, fill=255)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    img.paste(grad, (0, 0), tile)
    # the T (white) and the play triangle (yellow)
    white = Image.new("L", (n, n), 0)
    wd = ImageDraw.Draw(white)
    for box in ICON_T:
        bx0, by0, bx1, by1, br = fit_to_pixels(box, size) if size <= 48 else box
        wd.rounded_rectangle([bx0 * k, by0 * k, bx1 * k - 1, by1 * k - 1], radius=br * k, fill=255)
    play = Image.new("L", (n, n), 0)
    pd = ImageDraw.Draw(play)
    ins = inset_triangle(ICON_TRI, ICON_TRI_R)
    pd.polygon([(x * k, y * k) for x, y in ins], fill=255)
    for i in range(3):
        (px, py), (qx, qy) = ins[i], ins[(i + 1) % 3]
        pd.line([(px * k, py * k), (qx * k, qy * k)], fill=255, width=round(2 * ICON_TRI_R * k))
        pd.ellipse([(px - ICON_TRI_R) * k, (py - ICON_TRI_R) * k, (px + ICON_TRI_R) * k, (py + ICON_TRI_R) * k], fill=255)
    # one soft shadow for both, then the shapes
    shadow = ImageChops.offset(ImageChops.lighter(white, play), 0, round(ICON_SHADOW_DY * k)).filter(
        ImageFilter.GaussianBlur(ICON_SHADOW_BLUR * k))
    shadow_rgba = Image.new("RGBA", (n, n), ICON_SHADOW + (round(255 * ICON_SHADOW_OPACITY),))
    img.alpha_composite(Image.composite(shadow_rgba, Image.new("RGBA", (n, n), (0, 0, 0, 0)), shadow))
    img.alpha_composite(Image.composite(Image.new("RGBA", (n, n), (255, 255, 255, 255)), Image.new("RGBA", (n, n), (0, 0, 0, 0)), white))
    img.alpha_composite(Image.composite(Image.new("RGBA", (n, n), ICON_PLAY + (255,)), Image.new("RGBA", (n, n), (0, 0, 0, 0)), play))
    return img.resize((size, size), Image.LANCZOS)


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def icon_png(size):
    """The icon as deterministic PNG bytes."""
    return png_bytes(icon_image(size))


def mac_icon_png(size):
    """macOS-style icon: the artwork inset to ~80% of the canvas, as Apple's icon grid expects."""
    inner = round(size * 0.8)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.alpha_composite(icon_image(inner), ((size - inner) // 2, (size - inner) // 2))
    return png_bytes(img)


def word_image(width):
    """The word mark (with its shadow) as a transparent RGBA image of the given width, supersampled 4x."""
    shapes, word_w = word_shapes()
    full_w, full_h = word_w + DEPTH, 100 + DEPTH
    k = 4 * width / full_w
    img = Image.new("RGBA", (round(full_w * k), round(full_h * k)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for off, fill in ((DEPTH, SHADE), (0, FACE)):
        for sh in shapes:
            if sh[0] == "rect":
                _, x, y, w, h = sh
                d.rounded_rectangle([(x + off) * k, (y + off) * k, (x + off + w) * k, (y + off + h) * k], radius=3 * k, fill=fill)
            else:
                d.polygon([((px + off) * k, (py + off) * k) for px, py in sh[1]], fill=fill)
    return img.resize((width, round(full_h * width / full_w)), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def about_logo_png():
    """desktop/assets/about_logo.png: the word mark on transparency, 700x230 like upstream's."""
    img = Image.new("RGBA", (700, 230), (0, 0, 0, 0))
    word = word_image(660)
    img.alpha_composite(word, ((700 - word.width) // 2, (230 - word.height) // 2))
    return png_bytes(img)


def wix_banner_png():
    """WiX installer top banner (493x58): white, the icon on the right."""
    img = Image.new("RGB", (493, 58), (255, 255, 255))
    icon = icon_image(46)
    img.paste(icon, (493 - 46 - 8, 6), icon)
    return png_bytes(img)


def wix_dialog_png():
    """WiX installer welcome/finish dialog (493x312): a 164 px brand panel on the left, white elsewhere."""
    img = Image.new("RGB", (493, 312), (255, 255, 255))
    img.paste(vertical_gradient((164, 312), ICON_BG_BOTTOM, (6, 18, 34)), (0, 0))
    word = word_image(148)
    img.paste(word, ((164 - word.width) // 2, 24), word)
    return png_bytes(img)


def favicon_ico():
    buf = io.BytesIO()
    icon_image(256).save(buf, "ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    return buf.getvalue()


def social_preview_png():
    """GitHub social preview (1280x640, upload it in the repository settings): word mark and icon, no text font."""
    img = vertical_gradient((1280, 640), ICON_BG_BOTTOM, (6, 18, 34)).convert("RGBA")
    icon = icon_image(200)
    img.alpha_composite(icon, ((1280 - 200) // 2, 90))
    word = word_image(820)
    img.alpha_composite(word, ((1280 - word.width) // 2, 340))
    return png_bytes(img.convert("RGB"))


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
    files[BRANDING / "social-preview.png"] = social_preview_png()
    # Desktop app artwork (the file names are upstream's and are referenced by its build files).
    desktop = ROOT / "desktop"
    files[desktop / "assets/about_logo.png"] = about_logo_png()
    files[desktop / "assets/favicon.ico"] = favicon_ico()
    files[desktop / "assets/favicon-32.rgba"] = icon_image(32).tobytes()  # raw 32x32 RGBA window icon
    iconset = desktop / "assets/Assets.xcassets/RuffleMacIcon.iconset"
    for base in (16, 32, 128, 256, 512):
        files[iconset / f"icon_{base}x{base}.png"] = mac_icon_png(base)
        files[iconset / f"icon_{base}x{base}@2x.png"] = mac_icon_png(base * 2)
    files[desktop / "packages/linux/rs.ruffle.Ruffle.svg"] = icon.replace(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"',
        '<svg xmlns="http://www.w3.org/2000/svg" width="128px" height="128px" viewBox="0 0 100 100"', 1).encode()
    files[desktop / "packages/windows/wix/banner.png"] = wix_banner_png()
    files[desktop / "packages/windows/wix/dialog.png"] = wix_dialog_png()
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
