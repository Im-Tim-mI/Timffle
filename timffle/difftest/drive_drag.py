#!/usr/bin/env python3
"""Run one difftest SWF in real Flash 32 (Wine) on a private Xvfb display and send mouse drags via XTest.

usage: drive_drag.py <test> <display-number> <start_delay_s> <drag>...
  <drag> = x1,y1:x2,y2 as fractions (0..1) of the player window: press at 1, move to 2, release.
  Drags are separated by 1.5 s. The result is printed when the SWF reports (or after 60 s).
Env: FLASH_EXE, WINE_DIR, WINEPREFIX, DIFFTEST (difftest dir), XLIB (python-xlib dir).
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.environ.get("XLIB", "/tmp/api100-xlib"))
from Xlib import X, display  # noqa: E402
from Xlib.ext import xtest  # noqa: E402

D = os.environ["DIFFTEST"]
test = sys.argv[1]
dnum = sys.argv[2]
start_delay = float(sys.argv[3])
drags = []
for spec in sys.argv[4:]:
    a, b = spec.split(":")
    x1, y1 = (float(v) for v in a.split(","))
    x2, y2 = (float(v) for v in b.split(","))
    drags.append((x1, y1, x2, y2))
res = os.path.join(D, "results", "flash", test + ".txt")
if os.path.exists(res):
    os.remove(res)
os.makedirs(os.path.join(D, "logs", "flash"), exist_ok=True)

xvfb = subprocess.Popen(["Xvfb", ":" + dnum, "-screen", "0", "1024x768x24"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1.5)
env = dict(os.environ)
env.update(DISPLAY=":" + dnum, WINEDLLOVERRIDES="mscoree,mshtml=", WINEDEBUG="-all")
wine = os.path.join(env.get("WINE_DIR", ""), "wine") if env.get("WINE_DIR") else "wine"
url = "http://127.0.0.1:18765/t/flash/%s.swf" % test
logf = open(os.path.join(D, "logs", "flash", test + ".log"), "wb")
p = subprocess.Popen([wine, env["FLASH_EXE"], url], env=env, stdout=logf, stderr=subprocess.STDOUT,
                     start_new_session=True)


def find_window(d):
    root = d.screen().root
    best = None
    for w in root.query_tree().children:
        try:
            attrs = w.get_attributes()
            if attrs.map_state != X.IsViewable:
                continue
            g = w.get_geometry()
            if g.width < 100 or g.height < 100:
                continue
            if best is None or g.width * g.height > best[1]:
                best = (w, g.width * g.height, g)
        except Exception:
            continue
    return best


def move(d, x, y):
    xtest.fake_input(d, X.MotionNotify, x=x, y=y)
    d.sync()


time.sleep(start_delay)
d = display.Display(":" + dnum)
found = find_window(d)
print("window:", None if found is None else (found[2].width, found[2].height), flush=True)
if found is not None:
    w, _, g = found
    abs_ = w.translate_coords(d.screen().root, 0, 0)
    ox, oy = -abs_.x, -abs_.y
    for (x1, y1, x2, y2) in drags:
        px, py = ox + int(g.width * x1), oy + int(g.height * y1)
        rx, ry = ox + int(g.width * x2), oy + int(g.height * y2)
        print("drag", (px, py), "->", (rx, ry), flush=True)
        move(d, px, py)
        time.sleep(0.3)
        xtest.fake_input(d, X.ButtonPress, 1)
        d.sync()
        time.sleep(0.3)
        steps = 8
        for i in range(1, steps + 1):
            move(d, px + (rx - px) * i // steps, py + (ry - py) * i // steps)
            time.sleep(0.05)
        time.sleep(0.3)
        xtest.fake_input(d, X.ButtonRelease, 1)
        d.sync()
        time.sleep(1.5)

t0 = time.time()
while time.time() - t0 < 60:
    if os.path.exists(res) and os.path.getsize(res) > 0:
        break
    if p.poll() is not None:
        break
    time.sleep(0.5)
time.sleep(1)
try:
    os.killpg(p.pid, 9)
except Exception:
    pass
xvfb.kill()
if os.path.exists(res):
    print(open(res).read())
else:
    print("NO RESULT")
