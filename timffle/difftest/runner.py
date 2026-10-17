#!/usr/bin/env python3
"""Run one test SWF in one player and wait for its report.

usage: runner.py <flash|ruffle> <test> [timeout_seconds]
"""
import os
import signal
import subprocess
import sys
import time

D = os.path.dirname(os.path.abspath(__file__))
# The reference player is the Adobe Flash Player 32 standalone projector (not included), run under Wine:
#   FLASH_EXE   path of flashplayer_32_sa.exe
#   WINE_DIR    directory that holds `wine` and `wineserver` (empty: use PATH)
#   WINEPREFIX  a dedicated prefix (default: difftest/.wineprefix)
# The Ruffle build under test (desktop binary) is RUFFLE_BIN (default: `ruffle` from PATH).
FLASH_EXE = os.environ.get("FLASH_EXE", "flashplayer_32_sa.exe")
WINE_DIR = os.environ.get("WINE_DIR", "")


def wine_bin(name):
    return os.path.join(WINE_DIR, name) if WINE_DIR else name


def wine_env():
    env = dict(os.environ)
    env.update(WINEPREFIX=os.environ.get("WINEPREFIX", os.path.join(D, ".wineprefix")),
               WINEDLLOVERRIDES="mscoree,mshtml=", WINEDEBUG="-all")
    return env


def run(runner, test, timeout=45):
    res = os.path.join(D, "results", runner, test + ".txt")
    os.makedirs(os.path.dirname(res), exist_ok=True)
    os.makedirs(os.path.join(D, "logs", runner), exist_ok=True)
    if os.path.exists(res):
        os.remove(res)
    url = "http://127.0.0.1:18765/t/%s/%s.swf" % (runner, test)
    if runner == "flash":
        env = wine_env()
        cmd = [wine_bin("wine"), FLASH_EXE, url]
    else:
        env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1")
        cmd = [os.environ.get("RUFFLE_BIN", "ruffle"), "--no-gui",
               "--tcp-connections", "allow", "--open-url-mode", "deny",
               "--width", "400", "--height", "300", url]
    with open(os.path.join(D, "logs", runner, test + ".log"), "wb") as logf:
        p = subprocess.Popen(["xvfb-run", "-a", "-s", "-screen 0 1024x768x24"] + cmd,
                             env=env, stdout=logf, stderr=subprocess.STDOUT,
                             start_new_session=True)
        t0 = time.time()
        ok = False
        while time.time() - t0 < timeout:
            if os.path.exists(res) and os.path.getsize(res) > 0:
                ok = True
                break
            if p.poll() is not None:
                break
            time.sleep(0.5)
        elapsed = time.time() - t0
        time.sleep(1.0)
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(p.pid, sig)
            except ProcessLookupError:
                break
            time.sleep(1.0)
    if runner == "flash":
        subprocess.run([wine_bin("wineserver"), "-k"], env=wine_env(),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return ok, elapsed


if __name__ == "__main__":
    r, t = sys.argv[1], sys.argv[2]
    ok, el = run(r, t, int(sys.argv[3]) if len(sys.argv) > 3 else 45)
    print("%s %s %s %.1fs" % (r, t, "REPORTED" if ok else "NO-REPORT", el))
