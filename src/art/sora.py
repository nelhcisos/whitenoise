# Сора, the teacher of the positioning book: the master's sprites recoloured into a younger monk
# in an indigo robe with a dark beard. Same poses, same 3D layers.
import sys
from PIL import Image
SRC, OUT = sys.argv[1], sys.argv[2]
MAP = {
    (0xf0, 0x8c, 0x1e): (0x3a, 0x6f, 0xd8),   # robe
    (0xc4, 0x62, 0x10): (0x26, 0x4b, 0xa0),   # robe shadow
    (0xff, 0xb8, 0x50): (0x7f, 0xb0, 0xff),   # robe light
    (0x78, 0x40, 0x1e): (0x1d, 0x2c, 0x5c),   # sash / beads
    (0x5c, 0x30, 0x18): (0x14, 0x1e, 0x40),
    (0xf5, 0xf5, 0xf0): (0x3b, 0x2c, 0x24),   # white beard and brows -> dark
    (0xc8, 0xc8, 0xc4): (0x2a, 0x1f, 0x1a),
    (0xfa, 0xe6, 0xc8): (0xf2, 0xd2, 0xae),
}
for mood in ("calm", "happy", "stern", "think", "blink", "shock", "walk"):
    im = Image.open(f"{SRC}/master_{mood}.png").convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in MAP:
                px[x, y] = MAP[(r, g, b)] + (a,)
    im.save(f"{OUT}/sora_{mood}.png")
print("ok")
