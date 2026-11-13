# Icon for the «Элайнеры» book: an upper row of teeth under a clear aligner with a highlight and an
# attachment on the canine, on a teal tile. Drawn at 60x60, saved at 120x120 with crisp pixels.
import sys
from PIL import Image, ImageDraw
S = 60
im = Image.new("RGBA", (S, S)); d = ImageDraw.Draw(im)
top, bot = (60, 196, 190), (18, 104, 122)
for y in range(S):
    k = y / (S - 1); d.line([(0, y), (S, y)], fill=tuple(round(top[i] + (bot[i] - top[i]) * k) for i in range(3)) + (255,))
OUT, EN, ENS, GUM, GUMD = (14, 44, 60, 255), (252, 250, 240, 255), (212, 216, 208, 255), (236, 128, 136, 255), (190, 86, 100, 255)
# the gum above the teeth
d.rounded_rectangle([5, 8, 54, 22], radius=6, fill=GUM, outline=OUT)
d.line([(8, 20), (51, 20)], fill=GUMD)
# five teeth, front view: two centrals in the middle, laterals and canines to the sides
teeth = [(7, 14, 31), (15, 22, 34), (23, 29, 37), (30, 36, 37), (37, 44, 34), (45, 52, 31)]   # x0, x1, bottom y
for x0, x1, yb in teeth:
    d.rounded_rectangle([x0, 17, x1, yb], radius=2, fill=EN, outline=OUT)
    d.line([(x1 - 1, 20), (x1 - 1, yb - 2)], fill=ENS)
# an attachment on each canine
ATT = (255, 196, 64, 255)
d.rectangle([17, 24, 19, 27], fill=ATT, outline=OUT); d.rectangle([40, 24, 42, 27], fill=ATT, outline=OUT)
# the aligner: a clear shell slipped down off the teeth, with a bright rim and highlights
al = Image.new("RGBA", (S, S)); a = ImageDraw.Draw(al)
SH, RIM, HI = (190, 240, 255, 86), (236, 252, 255, 235), (255, 255, 255, 220)
for x0, x1, yb in teeth:      # the same row of tooth shapes, slipped 9 px down: scalloped like a real aligner
    a.rounded_rectangle([x0 - 1, 33, x1 + 1, yb + 10], radius=3, fill=SH, outline=RIM)
a.rectangle([7, 34, 52, 40], fill=SH)
a.line([(6, 33), (53, 33)], fill=RIM)
for x0, x1, yb in teeth: a.line([(x0 + 1, 36), (x0 + 1, yb + 5)], fill=HI)
im = Image.alpha_composite(im, al)
im = im.resize((120, 120), Image.NEAREST)
im.save(sys.argv[1])
im.resize((240, 240), Image.NEAREST).save(sys.argv[2])
print("ok")
