# cursor_image.py: print the X server's current cursor (XFixesGetCursorImage): size, hotspot, a few pixels.
import ctypes, ctypes.util, sys
x11 = ctypes.CDLL("libX11.so.6"); xf = ctypes.CDLL("libXfixes.so.3")
class Img(ctypes.Structure):
    _fields_ = [("x", ctypes.c_short), ("y", ctypes.c_short), ("width", ctypes.c_ushort), ("height", ctypes.c_ushort),
                ("xhot", ctypes.c_ushort), ("yhot", ctypes.c_ushort), ("cursor_serial", ctypes.c_ulong),
                ("pixels", ctypes.POINTER(ctypes.c_ulong)), ("atom", ctypes.c_ulong), ("name", ctypes.c_char_p)]
x11.XOpenDisplay.restype = ctypes.c_void_p
xf.XFixesGetCursorImage.restype = ctypes.POINTER(Img); xf.XFixesGetCursorImage.argtypes = [ctypes.c_void_p]
d = x11.XOpenDisplay(sys.argv[1].encode())
if not d: sys.exit("cannot open display")
im = xf.XFixesGetCursorImage(d).contents
print(f"cursor {im.width}x{im.height} hot=({im.xhot},{im.yhot}) name={im.name}")
for (px, py) in [(1, 1), (12, 1), (1, 14), (12, 14)]:
    if px < im.width and py < im.height:
        print(f"  pixel({px},{py}) = {im.pixels[py * im.width + px] & 0xFFFFFFFF:08x}")
