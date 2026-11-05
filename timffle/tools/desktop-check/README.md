# Desktop cursor / mouseLock check (X11, no window manager)

Verifies `Mouse.registerCursor` and `Stage.mouseLock` in the desktop player on a private Xvfb.

1. Build: `PKG_CONFIG_PATH=<dir with alsa.pc and libudev.pc> cargo build -p ruffle_desktop` (on a machine without the
   -dev packages, `apt-get download libasound2-dev libudev-dev`, `dpkg-deb -x` them into a private prefix, fix
   `prefix=` in the two .pc files, and symlink the system runtime libraries next to the `.so` links).
2. `haxe -cp . -main CursorTest -swf cursor.swf -swf-version 32 -D swf-header=400:300:30:808080 -D native_trace`
   (same for `LockTest` → `lock.swf`).
3. `Xvfb :73 &`, then run the player with a private `HOME` under `dbus-run-session -- ruffle_desktop --no-gui
   --width 400 --height 300 cursor.swf`.
4. `python3 warp.py :73 100 100; python3 cursor_image.py :73` prints the X cursor (expect 16x16, hot (2,3), red left /
   blue right); move outside (`warp.py :73 900 700`) and back to check it is applied again.
5. For `lock.swf`: `python3 xinput.py :73 click 200 150` (enters full screen and sets mouseLock), then
   `python3 xinput.py :73 grab` must print `AlreadyGrabbed`, and `xinput.py :73 move 30 -20` produces mouseMove traces.
