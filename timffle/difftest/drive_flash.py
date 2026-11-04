#!/usr/bin/env python3
"""Run one difftest SWF in real Flash 32 (Wine) on a private Xvfb display and send input via XTest.

usage: drive_flash.py <test> <display-number> [click_delay_s] [paste_delay_s]
Env: FLASH_EXE, WINE_DIR, WINEPREFIX, DIFFTEST (difftest dir), XLIB (python-xlib dir).
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.environ.get("XLIB", "/tmp/api100-xlib"))
from Xlib import X, display, XK  # noqa: E402
from Xlib.ext import xtest  # noqa: E402

D = os.environ["DIFFTEST"]
test = sys.argv[1]
dnum = sys.argv[2]
click_delay = float(sys.argv[3]) if len(sys.argv) > 3 else 8
paste_delay = float(sys.argv[4]) if len(sys.argv) > 4 else 6
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


def key(d, keysym, mod=None):
    kc = d.keysym_to_keycode(keysym)
    mk = d.keysym_to_keycode(mod) if mod else None
    print("keycodes", kc, mk, flush=True)
    if mk:
        xtest.fake_input(d, X.KeyPress, mk)
        d.sync()
        time.sleep(0.1)
    xtest.fake_input(d, X.KeyPress, kc)
    d.sync()
    time.sleep(0.1)
    xtest.fake_input(d, X.KeyRelease, kc)
    d.sync()
    time.sleep(0.1)
    if mk:
        xtest.fake_input(d, X.KeyRelease, mk)
        d.sync()


time.sleep(click_delay)
d = display.Display(":" + dnum)
found = find_window(d)
print("window:", None if found is None else (found[2].width, found[2].height), flush=True)
if found is not None:
    w, _, g = found
    abs_ = w.translate_coords(d.screen().root, 0, 0)  # root -> window; we want window->root
    # translate window origin to root coordinates
    tr = d.screen().root.translate_coords(w, 0, 0)
    cx, cy = tr.x + g.width // 2, tr.y + g.height // 2
    # translate_coords(root, 0, 0) on w gives root's origin in w coords; use inverse
    cx, cy = -abs_.x + g.width // 2, -abs_.y + g.height // 2
    print("click at", cx, cy, flush=True)
    xtest.fake_input(d, X.MotionNotify, x=cx, y=cy)
    d.sync()
    time.sleep(0.3)
    xtest.fake_input(d, X.ButtonPress, 1)
    xtest.fake_input(d, X.ButtonRelease, 1)
    d.sync()
    time.sleep(paste_delay)
    xtest.fake_input(d, X.MotionNotify, x=cx, y=cy)
    xtest.fake_input(d, X.ButtonPress, 1)
    xtest.fake_input(d, X.ButtonRelease, 1)
    d.sync()
    time.sleep(0.5)
    key(d, XK.XK_v, XK.XK_Control_L)
    print("sent ctrl+v", flush=True)
    time.sleep(2)
    key(d, XK.XK_Insert, XK.XK_Shift_L)
    print("sent shift+insert", flush=True)
    time.sleep(2)
    key(d, XK.XK_V, XK.XK_Control_L)
    print("sent ctrl+V", flush=True)

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
