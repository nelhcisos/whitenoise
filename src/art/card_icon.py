# Icon for the «Карта пациента» app: a clipboard with a tooth on a blue tile, 120x120.
import sys
from PIL import Image, ImageDraw
S = 120
im = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(im)
top, bot = (70, 160, 255), (24, 92, 214)
for y in range(S):
    k = y / (S - 1)
    d.line([(0, y), (S, y)], fill=tuple(round(top[i] + (bot[i] - top[i]) * k) for i in range(3)) + (255,))
d.rounded_rectangle([30, 22, 92, 104], 8, fill=(255, 255, 255, 255))           # the sheet
d.rounded_rectangle([46, 15, 76, 30], 5, fill=(255, 92, 92, 255))              # the clip
d.rectangle([54, 19, 68, 23], fill=(255, 190, 190, 255))
# a tooth
t = [(48, 40), (55, 37), (61, 40), (67, 37), (74, 40), (75, 50), (71, 64), (67, 64), (64, 54), (58, 54), (55, 64), (51, 64), (47, 50)]
d.polygon(t, fill=(232, 241, 255, 255), outline=(24, 92, 214, 255))
d.line(t + [t[0]], fill=(24, 92, 214, 255), width=3)
# lines of the record
for y, w in ((74, 48), (83, 40), (92, 46)):
    d.rounded_rectangle([38, y, 38 + w, y + 4], 2, fill=(180, 198, 228, 255))
d.ellipse([74, 84, 88, 98], fill=(52, 199, 89, 255))                            # a green tick
d.line([(77, 91), (80, 94), (85, 87)], fill=(255, 255, 255, 255), width=2)
im.save(sys.argv[1])
im.resize((360, 360), Image.NEAREST).save(sys.argv[2])
print("ok")
