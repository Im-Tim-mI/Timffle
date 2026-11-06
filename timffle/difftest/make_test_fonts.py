#!/usr/bin/env python3
"""Make the TrueType files that let Flash Player (under Wine) draw device text
with the same font the test harness uses.

usage: make_test_fonts.py <core/assets/notosans.subset.ttf.gz> <outdir>

The harness (`with_default_font = true`) draws every default device font
(`_sans`, `_serif`, `_typewriter`, ...) with Ruffle's embedded Noto Sans subset,
regular only (a bold request gets the regular face). Two files are written,
family "Timffle Test Sans", both with the same glyph outlines and hinting as
that subset:

  NotoSans-TestRegular.ttf  the subset itself, with usWinAscent/usWinDescent
                            set to the ascender/descender Ruffle uses
                            (1069/293; the merged math subset has 3105/2550,
                            and GDI places lines with the Win values)
  NotoSans-TestBold.ttf     the same outlines marked as the bold face of the
                            family, so GDI picks it for bold text instead of
                            emboldening the regular one (Ruffle draws the
                            regular outlines for bold, too)

No third-party modules: the tables are patched in place and the checksums
recomputed.
"""
import struct
import sys
import zlib
from pathlib import Path


FAMILY = "Timffle Test Sans"  # install_test_fonts.sh substitutes this name
PS = "TimffleTestSans"


def checksum(data: bytes) -> int:
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def read_tables(font: bytes):
    num = struct.unpack(">H", font[4:6])[0]
    tables = {}
    for i in range(num):
        tag, _, off, length = struct.unpack(">4sIII", font[12 + 16 * i: 28 + 16 * i])
        tables[tag.decode("latin-1")] = bytearray(font[off: off + length])
    return font[:4], tables


def write_font(sfnt_version: bytes, tables: dict) -> bytes:
    tags = sorted(tables)
    num = len(tags)
    es = max(i for i in range(16) if (1 << i) <= num)
    header = sfnt_version + struct.pack(">HHHH", num, 16 << es, es, num * 16 - (16 << es))
    tables["head"][8:12] = b"\0\0\0\0"  # checkSumAdjustment, set below
    offset = 12 + 16 * num
    directory, body = b"", b""
    for tag in tags:
        data = bytes(tables[tag])
        directory += struct.pack(">4sIII", tag.encode("latin-1"), checksum(data), offset + len(body), len(data))
        body += data + b"\0" * (-len(data) % 4)
    font = bytearray(header + directory + body)
    head_off = 12 + 16 * num + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[: tags.index("head")])
    adjust = (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF
    font[head_off + 8: head_off + 12] = struct.pack(">I", adjust)
    return bytes(font)


def rebuild_name(name: bytearray, replace: dict) -> bytearray:
    """Return a name table (format 0) with the strings of the given name IDs replaced."""
    fmt, count, string_off = struct.unpack(">HHH", name[:6])
    records, strings = [], b""
    for i in range(count):
        pid, eid, lid, nid, length, off = struct.unpack(">6H", name[6 + 12 * i: 18 + 12 * i])
        raw = bytes(name[string_off + off: string_off + off + length])
        if nid in replace:
            raw = replace[nid].encode("utf-16-be" if pid in (0, 3) else "latin-1")
        records.append((pid, eid, lid, nid, len(raw), len(strings)))
        strings += raw
    out = struct.pack(">HHH", 0, count, 6 + 12 * count)
    for r in records:
        out += struct.pack(">6H", *r)
    return bytearray(out + strings)


def main():
    src, outdir = Path(sys.argv[1]), Path(sys.argv[2])
    data = src.read_bytes()
    try:
        font = zlib.decompress(data, -15)  # core/assets stores raw deflate
    except zlib.error:
        font = data
    version, tables = read_tables(font)
    hhea, os2 = tables["hhea"], tables["OS/2"]
    ascender, descender = struct.unpack(">hh", hhea[4:8])
    # OS/2: usWinAscent / usWinDescent at 74 / 76
    os2[74:78] = struct.pack(">HH", ascender, -descender)
    # A family name of its own: the host's fontconfig may have the full Noto
    # Sans (other outlines, a real bold), and Wine would mix the two.
    tables["name"] = rebuild_name(tables["name"], {
        1: FAMILY, 3: "2.015;GOOG;%s-Regular" % PS, 4: FAMILY + " Regular", 6: PS + "-Regular"})
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "NotoSans-TestRegular.ttf").write_bytes(write_font(version, {k: bytearray(v) for k, v in tables.items()}))

    bold = {k: bytearray(v) for k, v in tables.items()}
    bold["OS/2"][4:6] = struct.pack(">H", 700)  # usWeightClass
    fs_selection = struct.unpack(">H", bold["OS/2"][62:64])[0]
    fs_selection = (fs_selection & ~0x0040) | 0x0020  # REGULAR off, BOLD on
    bold["OS/2"][62:64] = struct.pack(">H", fs_selection)
    mac_style = struct.unpack(">H", bold["head"][44:46])[0] | 1
    bold["head"][44:46] = struct.pack(">H", mac_style)
    bold["name"] = rebuild_name(bold["name"], {
        1: FAMILY, 2: "Bold", 3: "2.015;GOOG;%s-Bold" % PS, 4: FAMILY + " Bold", 6: PS + "-Bold"})
    (outdir / "NotoSans-TestBold.ttf").write_bytes(write_font(version, bold))
    print("wrote", outdir / "NotoSans-TestRegular.ttf", outdir / "NotoSans-TestBold.ttf",
          "(ascender %d, descender %d)" % (ascender, descender))


if __name__ == "__main__":
    main()
