#!/usr/bin/env python3
"""Run one difftest SWF in real Flash (Wine) or in Ruffle desktop on a private Xvfb and save a screenshot as PNG.

usage: shot.py <flash|ruffle> <test> <out.png> [seconds-before-the-shot=7] [width=960] [height=560]
Needs the difftest server (difftest/server.py) running. Environment, as for difftest/runner.py:
  FLASH_EXE   path of flashplayer_32_sa.exe (Adobe's standalone projector, not included)
  WINE_DIR    directory that holds `wine` and `wineserver` (empty: use PATH)
  WINEPREFIX  a dedicated prefix (default: difftest/.wineprefix)
  RUFFLE_BIN  the Ruffle desktop binary under test (default: `ruffle` from PATH)
The screen is read from Xvfb's `-fbdir` framebuffer file (XWD), so no X tools are needed.
"""
import os
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zlib

D = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "difftest")
FLASH_EXE = os.environ.get("FLASH_EXE", "flashplayer_32_sa.exe")
WINE_DIR = os.environ.get("WINE_DIR", "")


def wine_bin(name):
    return os.path.join(WINE_DIR, name) if WINE_DIR else name


def free_display():
    n = 140
    while os.path.exists("/tmp/.X11-unix/X%d" % n) or os.path.exists("/tmp/.X%d-lock" % n):
        n += 1
    return n


def xwd_to_rgb(path):
    data = open(path, "rb").read()
    hdr = struct.unpack(">25I", data[:100])
    header_size, bpp, bpl = hdr[0], hdr[11], hdr[12]
    width, height, ncolors = hdr[4], hdr[5], hdr[19]
    byte_order = hdr[7]
    assert bpp == 32, "expected a 32 bit framebuffer, got %d" % bpp
    off = header_size + ncolors * 12
    rows = []
    for y in range(height):
        line = data[off + y * bpl: off + y * bpl + width * 4]
        out = bytearray(width * 3)
        if byte_order == 0:  # little endian: B G R x
            out[0::3] = line[2::4]
            out[1::3] = line[1::4]
            out[2::3] = line[0::4]
        else:  # big endian: x R G B
            out[0::3] = line[1::4]
            out[1::3] = line[2::4]
            out[2::3] = line[3::4]
        rows.append(bytes(out))
    return width, height, rows


def write_png(path, width, height, rows):
    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + r for r in rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    runner, test, out = sys.argv[1], sys.argv[2], sys.argv[3]
    wait = float(sys.argv[4]) if len(sys.argv) > 4 else 7.0
    width = int(sys.argv[5]) if len(sys.argv) > 5 else 960
    height = int(sys.argv[6]) if len(sys.argv) > 6 else 560
    n = free_display()
    fbdir = tempfile.mkdtemp(prefix="fb-")
    xvfb = subprocess.Popen(
        ["Xvfb", ":%d" % n, "-screen", "0", "1280x800x24", "-fbdir", fbdir, "-nolisten", "tcp"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(50):
        if os.path.exists("/tmp/.X11-unix/X%d" % n):
            break
        time.sleep(0.1)
    url = "http://127.0.0.1:18765/t/%s/%s.swf" % (runner, test)
    env = dict(os.environ, DISPLAY=":%d" % n)
    if runner == "flash":
        env.update(WINEPREFIX=os.environ.get("WINEPREFIX", os.path.join(D, ".wineprefix")),
                   WINEDLLOVERRIDES="mscoree,mshtml=", WINEDEBUG="-all")
        cmd = [wine_bin("wine"), FLASH_EXE, url]
    else:
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        cmd = [os.environ.get("RUFFLE_BIN", "ruffle"), "--no-gui",
               "--tcp-connections", "allow", "--open-url-mode", "deny", "--width", str(width), "--height", str(height), url]
    log = open(os.path.join(tempfile.gettempdir(), "shot-%s-%s.log" % (runner, test)), "wb")
    player = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        time.sleep(wait)
        w, h, rows = xwd_to_rgb(os.path.join(fbdir, "Xvfb_screen0"))
        write_png(out, w, h, rows)
        print("saved", out, w, "x", h)
    finally:
        for p in (player, xvfb):
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(1.0)
        for p in (player, xvfb):
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if runner == "flash":
            subprocess.run([wine_bin("wineserver"), "-k"], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["rm", "-rf", fbdir])


main()
