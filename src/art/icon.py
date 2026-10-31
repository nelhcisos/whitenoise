# Placeholder cover for the «Кондилография» app: the book's teacher on a hardcover, 64x64.
# Swapped for the real (pixelated) cover once it arrives.
import sys
from PIL import Image, ImageDraw
OUT = sys.argv[1]
W = 64
im = Image.new("RGBA", (W, W))
d = ImageDraw.Draw(im)
# hardcover: deep blue, lighter toward the top, a spine on the left, a gold frame
top, bottom = (44, 62, 112), (20, 30, 62)
for y in range(W):
    k = y / (W - 1)
    d.line([(0, y), (W - 1, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * k) for i in range(3)) + (255,))
d.rectangle([0, 0, 5, W - 1], fill=(14, 20, 44, 255))
d.line([(6, 0), (6, W - 1)], fill=(214, 168, 64, 255))
d.line([(3, 0), (3, W - 1)], fill=(150, 112, 40, 255))
d.rectangle([10, 3, W - 4, W - 4], outline=(214, 168, 64, 255))
# a halo behind the teacher
for r, col in ((22, (38, 96, 124, 255)), (19, (52, 128, 148, 255)), (16, (74, 160, 166, 255))):
    d.ellipse([37 - r, 30 - r, 37 + r, 30 + r], fill=col)
# the master: head and shoulders from his calm sprite
m = Image.open(f"{OUT}/master/master_calm.png").convert("RGBA").crop((8, 6, 56, 64))
im.alpha_composite(m, (13, 6))
im.save(f"{OUT}/books/condylography.png")
im.resize((W * 4, W * 4), Image.NEAREST).save(sys.argv[2])
print("ok")
