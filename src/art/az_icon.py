# Icon for the «Элайнеры от А до Я» book: the letters А and Я with an arrow between them over a clear
# aligner on a row of teeth, on a violet tile. Drawn at 60x60, saved at 120x120 with crisp pixels.
import sys
from PIL import Image, ImageDraw
S = 60
im = Image.new("RGBA", (S, S)); d = ImageDraw.Draw(im)
top, bot = (150, 96, 230), (70, 36, 140)
for y in range(S):
    k = y / (S - 1); d.line([(0, y), (S, y)], fill=tuple(round(top[i] + (bot[i] - top[i]) * k) for i in range(3)) + (255,))
OUT, WH, YEL = (36, 16, 70, 255), (255, 252, 240, 255), (255, 214, 64, 255)
A = ["..1111..", ".111111.", "11....11", "11....11", "11111111", "11111111", "11....11", "11....11", "11....11"]
YA = [".1111111", "11111111", "11....11", "11....11", ".1111111", "..111111", ".111..11", "111...11", "11....11"]
def glyph(g, x0, y0, col):
    for r, row in enumerate(g):
        for c, v in enumerate(row):
            if v == "1": d.rectangle([x0 + c * 2, y0 + r * 2, x0 + c * 2 + 1, y0 + r * 2 + 1], fill=col)
for dx, dy, col in ((1, 1, OUT), (0, 0, WH)):
    glyph(A, 5 + dx, 6 + dy, col); glyph(YA, 39 + dx, 6 + dy, col)
d.line([(24, 15), (34, 15)], fill=YEL, width=2); d.polygon([(33, 11), (38, 15), (33, 20)], fill=YEL)
# a row of six teeth under a clear aligner
EN, ENS = (252, 250, 240, 255), (206, 200, 220, 255)
for x0, x1, yb in [(6, 13, 50), (14, 21, 52), (22, 29, 54), (30, 37, 54), (38, 45, 52), (46, 53, 50)]:
    d.rounded_rectangle([x0, 34, x1, yb], radius=2, fill=EN, outline=OUT); d.line([(x1 - 1, 37), (x1 - 1, yb - 2)], fill=ENS)
al = Image.new("RGBA", (S, S)); a = ImageDraw.Draw(al)
a.rounded_rectangle([4, 31, 55, 57], radius=5, fill=(190, 240, 255, 70), outline=(236, 252, 255, 230))
a.line([(8, 35), (8, 44)], fill=(255, 255, 255, 220)); a.line([(9, 35), (12, 35)], fill=(255, 255, 255, 220))
im = Image.alpha_composite(im, al)
im.resize((120, 120), Image.NEAREST).save(sys.argv[1])
im.resize((240, 240), Image.NEAREST).save(sys.argv[2])
