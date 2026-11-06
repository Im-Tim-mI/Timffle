import ctypes, sys
x11 = ctypes.CDLL("libX11.so.6"); x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XDefaultRootWindow.restype = ctypes.c_ulong; x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XWarpPointer.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_int, ctypes.c_int]
x11.XFlush.argtypes = [ctypes.c_void_p]
d = x11.XOpenDisplay(sys.argv[1].encode()); r = x11.XDefaultRootWindow(d)
x11.XWarpPointer(d, 0, r, 0, 0, 0, 0, int(sys.argv[2]), int(sys.argv[3])); x11.XFlush(d)
