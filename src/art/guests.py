# Pixel sprites for the master's chapter: walk cycle, jaw-drop, and guest characters.
from PIL import Image, ImageDraw
import sys
OUT = sys.argv[1]
OUTLINE = (40, 20, 16, 255)

def outline(im, col=OUTLINE):
    """Add a 1px outline around opaque pixels (4-neighbourhood)."""
    w, h = im.size
    px = im.load()
    add = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] and px[nx, ny] != col:
                    add.append((x, y)); break
    for p in add:
        px[p] = col
    return im

def load(name):
    return Image.open(f"{OUT}/{name}.png").convert("RGBA")

# ---------- walk cycle from the "think" pose: robe hem lifted, feet alternate ----------
base = load("master_think")
SKIN = (232, 184, 140, 255); SANDAL = (92, 48, 24, 255); DARKROBE = (196, 98, 16, 255)
def walk_frame(step):
    im = base.copy()
    px = im.load()
    # cut the robe 5 rows higher and close it with an outline row
    for y in range(91, 96):
        for x in range(64):
            px[x, y] = (0, 0, 0, 0)
    for x in range(64):
        if px[x, 90][3]:
            px[x, 90] = OUTLINE
    # feet: one forward (lower, bigger), one back
    d = ImageDraw.Draw(im)
    if step == 0:
        fx = [(18, 26, 95), (36, 42, 93)]
    else:
        fx = [(22, 28, 93), (34, 42, 95)]
    for x0, x1, yb in fx:
        d.rectangle([x0, yb - 3, x1, yb - 1], fill=SKIN)
        d.rectangle([x0, yb, x1, yb], fill=SANDAL)
        d.rectangle([x0 - 1, yb - 4, x1 + 1, yb - 4], fill=OUTLINE)
    # hem sways toward the forward foot
    sway = -1 if step == 0 else 1
    shifted = Image.new("RGBA", im.size)
    shifted.paste(im.crop((0, 70, 64, 91)), (sway, 70))
    top = im.crop((0, 0, 64, 70)); low = im.crop((0, 91, 64, 96))
    out = Image.new("RGBA", im.size)
    out.paste(top, (0, 0)); out.alpha_composite(shifted); out.paste(low, (0, 91))
    # a 1px bob: the passing frame sits a pixel higher
    if step == 1:
        up = Image.new("RGBA", out.size)
        up.paste(out.crop((0, 1, 64, 91)), (0, 0)); up.paste(out.crop((0, 91, 64, 96)), (0, 91))
        out = up
    return out
sheet = Image.new("RGBA", (128, 96))
sheet.paste(walk_frame(0), (0, 0)); sheet.paste(walk_frame(1), (64, 0))
sheet.save(f"{OUT}/master_walk.png")

# ---------- jaw drop: eyes pop, mouth hangs open down to the chest ----------
im = load("master_calm")
d = ImageDraw.Draw(im)
px = im.load()
WHITE = (245, 245, 240, 255); GLASS = (210, 230, 240, 255); BLACK = (30, 26, 30, 255)
MOUTH = (90, 20, 24, 255); TONGUE = (230, 110, 120, 255); BROW = (200, 200, 196, 255); SKIN2 = (232, 184, 140, 255)
# eyebrows jump up
for y in (19,):
    for x in range(64):
        if px[x, y] == BROW: px[x, y] = SKIN2
for x in list(range(24, 30)) + list(range(35, 41)):
    px[x, 17] = BROW
# eyes: tiny pupils in white lenses
for (cx, cy) in ((28, 24), (39, 24)):
    for y in range(22, 27):
        for x in range(cx - 4, cx + 3):
            if px[x, y] == GLASS or px[x, y] == BLACK and 23 <= y <= 25 and cx - 3 <= x <= cx + 1:
                px[x, y] = (250, 252, 255, 255)
    px[cx - 1, 24] = BLACK; px[cx, 24] = BLACK
# the dropped jaw: a long dark mouth inside a stretched beard
d.ellipse([27, 32, 38, 58], fill=WHITE)           # beard stretched down
d.ellipse([29, 34, 36, 54], fill=MOUTH)
d.ellipse([30, 47, 35, 53], fill=TONGUE)
d.rectangle([29, 34, 36, 35], fill=WHITE)          # upper teeth
im.save(f"{OUT}/master_shock.png")

# ---------- guests ----------
def shade_rect(d, box, base, dark, light):
    x0, y0, x1, y1 = box
    d.rectangle(box, fill=base)
    d.rectangle([x0, y0, x0 + max(1, (x1 - x0) // 4), y1], fill=dark)
    d.rectangle([x1 - max(1, (x1 - x0) // 6), y0, x1, y1], fill=light)

def person(kind):
    im = Image.new("RGBA", (64, 96)); d = ImageDraw.Draw(im)
    skin, skin_d = (240, 196, 150, 255), (214, 160, 118, 255)
    if kind == "patient":
        top, top_d, top_l = (70, 110, 190, 255), (48, 80, 150, 255), (100, 140, 215, 255)
        legs = (52, 62, 92, 255)
    else:
        top, top_d, top_l = (250, 200, 30, 255), (214, 160, 10, 255), (255, 226, 90, 255)
        legs = (40, 40, 50, 255)
    if kind == "courier":   # thermal cube backpack behind the shoulders
        bag, bag_d, bag_l = (236, 176, 24, 255), (200, 140, 10, 255), (250, 206, 70, 255)
        shade_rect(d, [8, 18, 56, 64], bag, bag_d, bag_l)
        d.rectangle([8, 18, 56, 64], outline=OUTLINE)
        d.rectangle([9, 40, 55, 41], fill=bag_d)
    # legs and shoes
    d.rectangle([22, 72, 30, 90], fill=legs); d.rectangle([34, 72, 42, 90], fill=legs)
    d.rectangle([20, 90, 30, 94], fill=(235, 235, 235, 255) if kind == "courier" else (60, 40, 30, 255))
    d.rectangle([34, 90, 44, 94], fill=(235, 235, 235, 255) if kind == "courier" else (60, 40, 30, 255))
    # torso and arms
    shade_rect(d, [18, 40, 46, 74], top, top_d, top_l)
    d.rectangle([12, 42, 18, 68], fill=top_d); d.rectangle([46, 42, 52, 68], fill=top_l)
    if kind == "courier":
        d.rectangle([11, 41, 53, 75], outline=OUTLINE); d.rectangle([12, 42, 18, 68], fill=top_d); d.rectangle([46, 42, 52, 68], fill=top_l)
        d.line([(18, 42), (18, 68)], fill=OUTLINE); d.line([(46, 42), (46, 68)], fill=OUTLINE)
    d.rectangle([12, 68, 18, 72], fill=skin); d.rectangle([46, 68, 52, 72], fill=skin)
    if kind == "courier":   # reflective stripe and a paper bag in the hands
        d.rectangle([18, 58, 46, 60], fill=(200, 205, 210, 255))
        d.rectangle([24, 62, 40, 78], fill=(196, 150, 100, 255))
        d.rectangle([24, 62, 40, 63], fill=(160, 116, 70, 255))
        d.rectangle([12, 66, 24, 70], fill=top_d); d.rectangle([40, 66, 52, 70], fill=top_l)
    else:                   # hoodie strings and pocket; one hand up to the sore cheek
        d.rectangle([28, 44, 28, 52], fill=(230, 230, 230, 255)); d.rectangle([36, 44, 36, 52], fill=(230, 230, 230, 255))
        d.rectangle([24, 62, 40, 68], fill=top_d)
        d.rectangle([46, 26, 52, 42], fill=top_l)          # raised forearm
        d.rectangle([42, 24, 48, 30], fill=skin)           # hand on the cheek
    # neck and head
    d.rectangle([28, 34, 36, 40], fill=skin_d)
    d.ellipse([20, 10, 44, 38], fill=skin)
    d.ellipse([20, 10, 25, 38], fill=skin_d)
    # face
    eye = (30, 26, 30, 255)
    d.rectangle([26, 22, 27, 24], fill=eye); d.rectangle([36, 22, 37, 24], fill=eye)
    if kind == "patient":
        d.ellipse([37, 26, 45, 35], fill=(246, 170, 160, 255))    # swollen cheek
        d.rectangle([28, 31, 33, 31], fill=(150, 60, 60, 255)); d.point((27, 32), fill=(150, 60, 60, 255))
        d.rectangle([25, 19, 28, 19], fill=(90, 60, 40, 255)); d.rectangle([35, 18, 38, 18], fill=(90, 60, 40, 255))
        d.rectangle([22, 6, 42, 15], fill=(80, 50, 30, 255))        # hair
        # bandage around the jaw, knotted on top of the head
        band = (250, 250, 245, 255)
        d.rectangle([18, 16, 22, 36], fill=band); d.rectangle([42, 16, 46, 32], fill=band)
        d.rectangle([22, 34, 42, 38], fill=band)
        d.rectangle([22, 6, 42, 9], fill=band)
        d.polygon([(27, 6), (23, 0), (30, 4)], fill=band); d.polygon([(37, 6), (41, 0), (34, 4)], fill=band)
    else:
        d.arc([27, 26, 37, 33], 20, 160, fill=(150, 60, 60, 255))
        d.rectangle([24, 19, 28, 19], fill=(60, 40, 30, 255)); d.rectangle([35, 19, 39, 19], fill=(60, 40, 30, 255))
        d.rectangle([20, 8, 44, 15], fill=top)                       # cap
        d.rectangle([20, 8, 26, 15], fill=top_d)
        d.rectangle([30, 14, 50, 17], fill=top_d)                    # visor to the side
    return outline(im)

person("patient").save(f"{OUT}/guest_patient.png")
person("courier").save(f"{OUT}/guest_courier.png")

# ---------- the cat (white, pink bow), sitting ----------
cat = Image.new("RGBA", (48, 48)); d = ImageDraw.Draw(cat)
W1, W2, W3 = (255, 255, 255, 255), (226, 228, 236, 255), (196, 200, 214, 255)
PINK, PINK_D = (255, 150, 190, 255), (220, 90, 140, 255)
d.ellipse([10, 22, 40, 46], fill=W1)                 # body
d.ellipse([10, 22, 18, 46], fill=W2)
d.ellipse([36, 32, 46, 40], fill=W2)                 # tail
d.ellipse([8, 6, 38, 32], fill=W1)                   # head
d.ellipse([8, 6, 14, 32], fill=W2)
d.polygon([(10, 12), (12, 0), (19, 8)], fill=W1); d.polygon([(28, 8), (35, 0), (36, 12)], fill=W1)
d.polygon([(12, 9), (13, 3), (17, 8)], fill=PINK); d.polygon([(30, 8), (34, 3), (34, 10)], fill=PINK)
# bow on the left ear
d.polygon([(4, 2), (12, 6), (4, 10)], fill=PINK); d.polygon([(20, 2), (12, 6), (20, 10)], fill=PINK)
d.rectangle([11, 5, 13, 7], fill=PINK_D)
# eyes, nose, mouth, paws
for ex in (14, 26):
    d.ellipse([ex, 15, ex + 5, 21], fill=(30, 26, 30, 255)); d.point((ex + 1, 16), fill=W1)
d.rectangle([21, 22, 22, 23], fill=PINK_D)
d.point((20, 25), fill=(120, 80, 90, 255)); d.point((23, 25), fill=(120, 80, 90, 255)); d.rectangle([21, 24, 22, 24], fill=(120, 80, 90, 255))
d.ellipse([10, 22, 15, 26], fill=(255, 200, 215, 255)); d.ellipse([29, 22, 34, 26], fill=(255, 200, 215, 255))
d.ellipse([15, 41, 22, 46], fill=W2); d.ellipse([27, 41, 34, 46], fill=W2)
outline(cat).save(f"{OUT}/guest_cat.png")
print("ok")
