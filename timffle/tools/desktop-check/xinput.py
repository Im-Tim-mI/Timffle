# xinput.py <display> click <x> <y> | move <dx> <dy> | grab   (XTest input; grab = try XGrabPointer from another client)
import ctypes, sys
x11 = ctypes.CDLL("libX11.so.6"); xt = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XDefaultRootWindow.restype = ctypes.c_ulong; x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XFlush.argtypes = [ctypes.c_void_p]; x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
xt.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xt.XTestFakeRelativeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xt.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
x11.XGrabPointer.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_uint, ctypes.c_int, ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
d = x11.XOpenDisplay(sys.argv[1].encode()); cmd = sys.argv[2]
if cmd == "click":
    xt.XTestFakeMotionEvent(d, -1, int(sys.argv[3]), int(sys.argv[4]), 0); x11.XSync(d, 0)
    xt.XTestFakeButtonEvent(d, 1, 1, 0); x11.XSync(d, 0); xt.XTestFakeButtonEvent(d, 1, 0, 30); x11.XSync(d, 0)
elif cmd == "move":
    xt.XTestFakeRelativeMotionEvent(d, int(sys.argv[3]), int(sys.argv[4]), 0); x11.XSync(d, 0)
elif cmd == "grab":
    r = x11.XGrabPointer(d, x11.XDefaultRootWindow(d), 0, 0, 1, 1, 0, 0, 0)
    print("XGrabPointer ->", {0: "GrabSuccess (nobody holds the pointer)", 1: "AlreadyGrabbed (pointer is locked by another client)"}.get(r, r))
