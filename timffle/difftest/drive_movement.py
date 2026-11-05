#!/usr/bin/env python3
"""Drive d66movement (MouseEvent.movementX/Y) in real Flash 32 (Wine) on a private Xvfb display.

usage: drive_movement.py <display-number> [start_delay_s]
Env: FLASH_EXE, WINE_DIR, WINEPREFIX, DIFFTEST (difftest dir), DIFFTEST_HTTP_PORT (default 18765).
With RUFFLE_BIN set, runs that desktop player instead (`--no-gui --width 400 --height 300`, under
dbus-run-session, HOME=$RUFFLE_HOME if set); its report goes to results/ruffle/.
Input goes through XTest (libXtst via ctypes, no python-xlib needed): absolute moves, clicks and wheel
in the window, then a click that enters full screen, absolute moves there, a click that sets
Stage.mouseLock, and relative moves (XTestFakeRelativeMotionEvent) while locked.
"""
import ctypes
import os
import re
import subprocess
import sys
import time

D = os.environ["DIFFTEST"]
dnum = sys.argv[1]
start_delay = float(sys.argv[2]) if len(sys.argv) > 2 else 8
port = os.environ.get("DIFFTEST_HTTP_PORT", "18765")
test = "d66movement"
runner = "ruffle" if os.environ.get("RUFFLE_BIN") else "flash"
res = os.path.join(D, "results", runner, test + ".txt")
if os.path.exists(res):
    os.remove(res)
os.makedirs(os.path.join(D, "logs", "flash"), exist_ok=True)

xvfb = subprocess.Popen(["Xvfb", ":" + dnum, "-screen", "0", "1024x768x24"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("xvfb pid", xvfb.pid, flush=True)
time.sleep(1.5)
env = dict(os.environ)
env.update(DISPLAY=":" + dnum, WINEDLLOVERRIDES="mscoree,mshtml=", WINEDEBUG="-all")
wine = os.path.join(env["WINE_DIR"], "wine") if env.get("WINE_DIR") else "wine"
url = "http://127.0.0.1:%s/t/%s/%s.swf" % (port, runner, test)
os.makedirs(os.path.join(D, "logs", runner), exist_ok=True)
logf = open(os.path.join(D, "logs", runner, test + ".log"), "wb")
if runner == "ruffle":
    if env.get("RUFFLE_HOME"):
        env["HOME"] = env["RUFFLE_HOME"]
    cmd = ["dbus-run-session", "--", env["RUFFLE_BIN"], "--no-gui", "--width", "400", "--height", "300", url]
else:
    cmd = [wine, env["FLASH_EXE"], url]
p = subprocess.Popen(cmd, env=env, stdout=logf, stderr=subprocess.STDOUT, start_new_session=True)

x11 = ctypes.CDLL("libX11.so.6")
xt = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
xt.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xt.XTestFakeRelativeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xt.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]


def find_window():
    out = subprocess.run(["xwininfo", "-display", ":" + dnum, "-root", "-children"], capture_output=True,
                         text=True).stdout
    best = None
    for m in re.finditer(r"(0x[0-9a-f]+) .*?(\d+)x(\d+)\+(-?\d+)\+(-?\d+)", out):
        w, h, x, y = (int(m.group(i)) for i in range(2, 6))
        if w < 100 or h < 100:
            continue
        info = subprocess.run(["xwininfo", "-display", ":" + dnum, "-id", m.group(1)], capture_output=True,
                              text=True).stdout
        if "IsViewable" not in info:
            continue
        if best is None or w * h > best[0] * best[1]:
            best = (w, h, x, y)
    return best


time.sleep(start_delay)
d = x11.XOpenDisplay((":" + dnum).encode())


def absmove(x, y, pause=0.35):
    print("abs", x, y, flush=True)
    xt.XTestFakeMotionEvent(d, -1, x, y, 0)
    x11.XSync(d, 0)
    time.sleep(pause)


def relmove(dx, dy, pause=0.35):
    print("rel", dx, dy, flush=True)
    xt.XTestFakeRelativeMotionEvent(d, dx, dy, 0)
    x11.XSync(d, 0)
    time.sleep(pause)


def button(b, pause=0.5):
    print("button", b, flush=True)
    xt.XTestFakeButtonEvent(d, b, 1, 0)
    x11.XSync(d, 0)
    time.sleep(0.08)
    xt.XTestFakeButtonEvent(d, b, 0, 0)
    x11.XSync(d, 0)
    time.sleep(pause)


win = find_window()
print("window", win, flush=True)
if win is not None:
    w, h, ox, oy = win
    # windowed
    absmove(ox + 50, oy + 50)
    absmove(ox + 60, oy + 55)
    absmove(ox + 80, oy + 65)
    absmove(ox + 150, oy + 150)  # into box
    button(1)  # down #1
    button(4)
    button(5)
    absmove(ox + 152, oy + 149)
    absmove(ox + 30, oy + 40)  # out of box
    button(1, 2.5)  # down #2: full screen
    fw, fh, fx, fy = find_window() or (1024, 768, 0, 0)
    print("window after fullscreen", (fw, fh, fx, fy), flush=True)

    def fs(x, y):  # a point of the 1024x768 full screen, mapped into the window if it did not grow
        return fx + x * fw // 1024, fy + y * fh // 768

    absmove(*fs(500, 400))
    absmove(*fs(510, 400))
    absmove(*fs(510, 420))
    absmove(*fs(520, 430))
    button(1, 0.8)  # down #3: mouseLock
    relmove(10, 0)
    relmove(0, 20)
    relmove(-7, -3)
    relmove(100, 50)
    button(1)
    button(4)
    relmove(5, 5)
    time.sleep(2.5)  # unlock happens 3 s after the lock click
    absmove(*fs(300, 300))
    absmove(*fs(310, 305))

t0 = time.time()
while time.time() - t0 < 30:
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
