# Icon for the «Позиционирование брекетов» book: an incisor with a bracket on it, the height gauge
# and the measurement, on an indigo tile. Drawn at 60x60, saved at 120x120 with crisp pixels.
import sys
from PIL import Image, ImageDraw
S = 60
im = Image.new("RGBA", (S, S)); d = ImageDraw.Draw(im)
top, bot = (64, 120, 230), (28, 52, 130)
for y in range(S):
    k = y / (S - 1); d.line([(0, y), (S, y)], fill=tuple(round(top[i] + (bot[i] - top[i]) * k) for i in range(3)) + (255,))
# the incisor, front view: crown and a bit of root, with an outline
OUT, EN, ENS, ROOT = (20, 26, 50, 255), (252, 250, 240, 255), (214, 210, 196, 255), (236, 214, 176, 255)
d.polygon([(18, 16), (21, 6), (25, 1), (29, 1), (33, 6), (36, 16)], fill=ROOT, outline=OUT)                  # the root, tapering up
d.polygon([(17, 15), (37, 15), (40, 26), (42, 44), (41, 49), (38, 51), (16, 51), (13, 49), (12, 44), (14, 26)], fill=EN, outline=OUT)
d.line([(15, 26), (14, 47)], fill=ENS); d.line([(39, 26), (40, 47)], fill=ENS)
d.line([(17, 50), (37, 50)], fill=ENS)
# the bracket: base pad, wings and the slot, sitting at the planned height
MET, METD, METL = (176, 186, 204, 255), (98, 108, 128, 255), (232, 238, 248, 255)
d.rectangle([20, 27, 34, 37], fill=MET, outline=METD)
d.rectangle([19, 28, 21, 30], fill=METL); d.rectangle([33, 28, 35, 30], fill=METL)
d.rectangle([19, 34, 21, 36], fill=METL); d.rectangle([33, 34, 35, 36], fill=METL)
d.rectangle([20, 31, 34, 33], fill=METD)                    # the slot
d.point((27, 32), fill=(255, 80, 80, 255))                  # the bracket's centre
# the height: from the incisal edge up to the slot, with arrows, and a red reference line
RED, YEL = (255, 70, 70, 255), (255, 214, 64, 255)
d.line([(8, 32), (44, 32)], fill=RED)
d.line([(46, 33), (46, 50)], fill=YEL)
d.line([(44, 51), (48, 51)], fill=YEL); d.line([(44, 32), (48, 32)], fill=YEL)
d.point((45, 34), fill=YEL); d.point((47, 34), fill=YEL); d.point((45, 49), fill=YEL); d.point((47, 49), fill=YEL)
# "4.5" under the tooth, in tiny pixel digits
DIG = {"4": ["1.1", "1.1", "111", "..1", "..1"], ".": ["...", "...", "...", "...", ".1."], "5": ["111", "1..", "111", "..1", "111"]}
x = 20
for ch in "4.5":
    for r, row in enumerate(DIG[ch]):
        for c, v in enumerate(row):
            if v == "1": d.point((x + c, 54 + r), fill=YEL)
    x += 4 if ch != "." else 3
im = im.resize((120, 120), Image.NEAREST)
im.save(sys.argv[1])
im.resize((240, 240), Image.NEAREST).save(sys.argv[2])
print("ok")
