"""Draws the BillBox icon (a cardboard-style box with a bill sticking out) and writes AppIcon.icns. Needs Pillow."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
S = 1024

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# rounded-square gradient background (teal -> indigo)
bg = Image.new("RGB", (S, S))
px = bg.load()
c1, c2 = (16, 185, 168), (74, 61, 201)
for y in range(S):
    for x in range(S):
        px[x, y] = lerp(c1, c2, (x * 0.35 + y * 0.65) / S)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((40, 40, S - 40, S - 40), radius=210, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(bg, (0, 0), mask)

# soft shadow under the box
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse((230, 760, 794, 860), fill=(0, 0, 40, 110))
icon = Image.alpha_composite(icon, sh.filter(ImageFilter.GaussianBlur(22)))
d = ImageDraw.Draw(icon)

# the bill (white paper with ruled lines and a rupee mark) rising out of the box
d.rounded_rectangle((330, 190, 694, 560), radius=26, fill=(255, 255, 255, 255))
for i, w in enumerate((240, 200, 240, 150)):
    y = 300 + i * 58
    d.rounded_rectangle((372, y, 372 + w, y + 16), radius=8, fill=(190, 198, 225, 255))
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 110)
except Exception:
    f = ImageFont.load_default()
d.text((372, 205), "₹", font=f, fill=(74, 61, 201, 255))
d.rounded_rectangle((560, 205, 664, 262), radius=14, fill=(16, 185, 168, 255))

# the box: front face, lid flaps, tape
front = (212, 450, 812, 830)
d.rounded_rectangle(front, radius=36, fill=(247, 178, 76, 255))
d.polygon([(212, 450), (812, 450), (812, 520), (212, 520)], fill=(231, 150, 46, 255))
d.rounded_rectangle((212, 450, 812, 520), radius=36, fill=(231, 150, 46, 255))
d.rectangle((212, 490, 812, 520), fill=(231, 150, 46, 255))
d.rounded_rectangle((452, 450, 572, 640), radius=20, fill=(255, 226, 160, 255))   # tape
d.rounded_rectangle((250, 700, 440, 744), radius=20, fill=(255, 205, 120, 255))     # label
d.rounded_rectangle((600, 700, 774, 744), radius=20, fill=(255, 205, 120, 255))

# sparkle of "pcs" dots
for cx in (270, 330, 390):
    d.ellipse((cx - 12, 800 - 12, cx + 12, 800 + 12), fill=(255, 255, 255, 200))

icon.save("AppIcon.png")
sizes = [(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)]
icon.save("AppIcon.icns", format="ICNS", sizes=sizes)
print("wrote AppIcon.png and AppIcon.icns")
