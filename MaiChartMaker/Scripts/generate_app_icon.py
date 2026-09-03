from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources" / "Assets.xcassets" / "AppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)

S = 1024
img = Image.new("RGB", (S, S), (239, 250, 255))
px = img.load()

# Soft arcade gradient: cyan -> violet -> pink.
for y in range(S):
    for x in range(S):
        u = x / (S - 1)
        v = y / (S - 1)
        r = int(232 + 18*u + 5*v)
        g = int(249 - 48*u + 2*v)
        b = int(255 - 3*u)
        px[x, y] = (max(0,min(255,r)), max(0,min(255,g)), max(0,min(255,b)))

# Glow layer.
glow = Image.new("RGBA", (S, S), (0,0,0,0))
gd = ImageDraw.Draw(glow)
gd.ellipse((90, 90, 934, 934), fill=(57, 219, 245, 46))
gd.ellipse((210, 120, 880, 790), fill=(157, 93, 245, 42))
gd.ellipse((250, 300, 910, 950), fill=(255, 93, 176, 38))
glow = glow.filter(ImageFilter.GaussianBlur(70))
img = Image.alpha_composite(img.convert("RGBA"), glow)

d = ImageDraw.Draw(img)

# Outer white arcade bezel.
d.ellipse((72,72,952,952), fill=(255,255,255,235))
d.ellipse((96,96,928,928), fill=(248,252,255,255))

# Multi-color ring.
ring_colors = [(48,204,241,255),(52,231,198,255),(249,103,180,255),(143,92,239,255)]
for i, color in enumerate(ring_colors):
    inset = 128 + i*24
    d.arc((inset,inset,S-inset,S-inset), start=210+i*70, end=345+i*70, fill=color, width=28)

# Full inner ring.
d.ellipse((220,220,804,804), outline=(130,100,241,210), width=18)
d.ellipse((250,250,774,774), outline=(72,210,239,150), width=8)

# Rhythm dots.
dots = [
    (512,166,(255,102,187,255)), (812,438,(53,219,205,255)),
    (690,790,(147,88,240,255)), (242,658,(48,199,243,255)),
    (218,356,(255,188,52,255))
]
for cx,cy,c in dots:
    d.ellipse((cx-33,cy-33,cx+33,cy+33), fill=c, outline=(255,255,255,255), width=8)

# Musical eighth note, drawn with rounded geometry.
note = (92, 69, 236, 255)
note2 = (253, 87, 176, 255)
# beam/stem
d.rounded_rectangle((470, 338, 570, 665), radius=38, fill=note)
d.rounded_rectangle((545, 318, 748, 402), radius=30, fill=note)
# note heads
d.ellipse((392, 603, 574, 745), fill=note2)
d.ellipse((650, 520, 823, 658), fill=note)
# subtle highlight
d.rounded_rectangle((492, 354, 521, 590), radius=14, fill=(255,255,255,135))

# Sparkles.
for cx,cy,size in [(348,292,24),(744,250,18),(328,780,17),(790,714,21)]:
    d.polygon([(cx,cy-size),(cx+size//3,cy-size//3),(cx+size,cy),
               (cx+size//3,cy+size//3),(cx,cy+size),
               (cx-size//3,cy+size//3),(cx-size,cy),
               (cx-size//3,cy-size//3)], fill=(255,255,255,235))

base = img.convert("RGB")

specs = {
    "icon-20@1x.png":20, "icon-20@2x.png":40, "icon-20@3x.png":60,
    "icon-29@1x.png":29, "icon-29@2x.png":58, "icon-29@3x.png":87,
    "icon-40@1x.png":40, "icon-40@2x.png":80, "icon-40@3x.png":120,
    "icon-60@2x.png":120, "icon-60@3x.png":180,
    "icon-76@1x.png":76, "icon-76@2x.png":152,
    "icon-83.5@2x.png":167,
    "icon-1024.png":1024,
}

for name, size in specs.items():
    base.resize((size,size), Image.Resampling.LANCZOS).save(OUT / name, "PNG", optimize=True)
