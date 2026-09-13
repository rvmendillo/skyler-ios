#!/usr/bin/env python3
import json, math, os, struct, zlib

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

pixels = bytearray(SIZE * SIZE * 3)

def put(x, y, rgb):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        i = (y * SIZE + x) * 3
        pixels[i:i+3] = bytes(rgb)

def blend(a, b, t):
    return tuple(int(a[i] * (1-t) + b[i] * t) for i in range(3))

# Branded indigo -> purple background.
for y in range(SIZE):
    for x in range(SIZE):
        t = (x + y) / (2 * (SIZE - 1))
        c = blend((52, 48, 178), (139, 48, 178), t)
        # Soft central lift without alpha channels.
        d = math.hypot(x - 510, y - 500) / 720
        lift = max(0.0, 1.0 - d) * 18
        put(x, y, tuple(min(255, int(v + lift)) for v in c))

def rect(x0, y0, x1, y1, rgb):
    for y in range(max(0, y0), min(SIZE, y1)):
        i = (y * SIZE + max(0, x0)) * 3
        row = bytes(rgb) * max(0, min(SIZE, x1) - max(0, x0))
        pixels[i:i+len(row)] = row

def circle(cx, cy, r, rgb):
    rr = r*r
    for y in range(max(0, cy-r), min(SIZE, cy+r+1)):
        dy = y-cy
        span = int(math.sqrt(max(0, rr-dy*dy)))
        rect(cx-span, y, cx+span+1, y+1, rgb)

def rounded_rect(x0, y0, x1, y1, r, rgb):
    rect(x0+r, y0, x1-r, y1, rgb)
    rect(x0, y0+r, x1, y1-r, rgb)
    for cx, cy in ((x0+r,y0+r),(x1-r-1,y0+r),(x0+r,y1-r-1),(x1-r-1,y1-r-1)):
        circle(cx, cy, r, rgb)

white = (255,255,255)
dark = (28,22,70)
rounded_rect(205, 170, 819, 854, 120, dark)
# Compression stack: progressively shorter bars.
rounded_rect(286, 335, 738, 401, 32, white)
rounded_rect(350, 465, 674, 531, 32, white)
rounded_rect(414, 595, 610, 661, 32, white)
# Inward arrows.
rect(315, 720, 450, 766, white)
rect(574, 720, 709, 766, white)
# arrow heads
for dy in range(70):
    half = dy
    rect(370-half//2, 698+dy, 371+half//2, 699+dy, white)
    rect(653-half//2, 698+dy, 654+half//2, 699+dy, white)
# Small UC monogram made from block strokes.
rect(352, 235, 376, 299, white); rect(352, 283, 420, 307, white); rect(396, 235, 420, 299, white)
rect(465, 235, 489, 307, white); rect(489, 235, 555, 259, white); rect(489, 283, 555, 307, white)

raw = bytearray()
stride = SIZE * 3
for y in range(SIZE):
    raw.append(0)
    raw.extend(pixels[y*stride:(y+1)*stride])

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
png += chunk(b"IEND", b"")

with open(os.path.join(OUT, "Icon-1024.png"), "wb") as f:
    f.write(png)

contents = {
    "images": [{"filename": "Icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}
with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump(contents, f)
