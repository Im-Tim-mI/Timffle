#!/usr/bin/env python3
"""Assemble test.swf from a Haxe-compiled code SWF.

usage: make_swf.py <haxe-output.swf> <test.swf>

Keeps the Haxe FileAttributes/background/DoABC tags, adds timeline symbols:
  BodyA/BodyB/BodyC: empty 1-frame sprites
  Dir: 3 keyframes labelled "a"/"b"/"c", each placing a different Body at depth 1
and a SymbolClass binding them to the Haxe classes (the root keeps Haxe's boot class).
The root timeline gets 15 frames so root frame scripts can run.
"""
import struct, sys, zlib

def tags_of(data):
    p = 0
    while p < len(data):
        h = struct.unpack_from('<H', data, p)[0]; p += 2
        code, ln = h >> 6, h & 63
        if ln == 63:
            ln = struct.unpack_from('<I', data, p)[0]; p += 4
        yield code, data[p:p + ln]; p += ln

def tag(code, body=b''):
    if len(body) < 63:
        return struct.pack('<H', (code << 6) | len(body)) + body
    return struct.pack('<HI', (code << 6) | 63, len(body)) + body

def cstr(s):
    return s.encode() + b'\0'

SHOW = tag(1); END = tag(0)
def sprite(cid, frames):
    body = struct.pack('<HH', cid, len(frames))
    for fr in frames:
        body += b''.join(fr) + SHOW
    return tag(39, body + END)

def place(depth, cid):  # PlaceObject2: HasCharacter
    return tag(26, bytes([0x02]) + struct.pack('<HH', depth, cid))
def remove(depth):
    return tag(28, struct.pack('<H', depth))
def label(s):
    return tag(43, cstr(s))

src = open(sys.argv[1], 'rb').read()
sig, ver = src[:3], src[3]
body = zlib.decompress(src[8:]) if sig == b'CWS' else src[8:]
nb = body[0] >> 3; rl = (5 + 4 * nb + 7) // 8
rect, rate = body[:rl], body[rl:rl + 2]
rest = body[rl + 4:]

ROOT_FRAMES = 15
keep = []
for code, tb in tags_of(rest):
    if code in (69, 9, 82):  # FileAttributes, SetBackgroundColor, DoABC
        keep.append(tag(code, tb))
    elif code == 76:  # SymbolClass written by Haxe (root -> boot class): merged with ours below
        n = struct.unpack_from('<H', tb)[0]
        haxe_syms = tb[2:]
    elif code in (1, 0):
        pass
    else:
        keep.append(tag(code, tb))

A, B, C, DIR = 1, 2, 3, 4
defs = [sprite(A, [[]]), sprite(B, [[]]), sprite(C, [[]]),
        sprite(DIR, [[label('a'), place(1, A)],
                     [label('b'), remove(1), place(1, B)],
                     [label('c'), remove(1), place(1, C)]])]
symcls = tag(76, struct.pack('<H', n + 4) + haxe_syms + b''.join(
    struct.pack('<H', cid) + cstr(name)
    for cid, name in [(A, 'BodyA'), (B, 'BodyB'), (C, 'BodyC'), (DIR, 'Dir')]))

# DoABC must precede SymbolClass; definitions must precede SymbolClass.
abc = [t for t in keep if struct.unpack('<H', t[:2])[0] >> 6 == 82]
other = [t for t in keep if struct.unpack('<H', t[:2])[0] >> 6 != 82]
out_tags = b''.join(other) + b''.join(defs) + b''.join(abc) + symcls + SHOW * ROOT_FRAMES + END
out_body = rect + rate + struct.pack('<H', ROOT_FRAMES) + out_tags
out = b'FWS' + bytes([ver]) + struct.pack('<I', 8 + len(out_body)) + out_body
open(sys.argv[2], 'wb').write(out)
print('wrote', sys.argv[2], len(out), 'bytes, swf version', ver)
