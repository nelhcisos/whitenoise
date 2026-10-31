# The barin as a guest in the master's courtyard: 64x96, standing, same style as the other guests.
import sys
from PIL import Image, ImageDraw
OUT = sys.argv[1]
OUTLINE = (40, 20, 16, 255)
def outline(im, col=OUTLINE):
    w, h = im.size; px = im.load(); add = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3]: continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] and px[nx, ny] != col:
                    add.append((x, y)); break
    for p in add: px[p] = col
    return im
C = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)
SKIN, SKIN_D, BLUSH = C("#ecbc94"), C("#cf9468"), C("#ec9a86")
HAIR, HAIR_D = C("#b3ada5"), C("#6a625c")
DARK, MOUST, LIP, TEETH = C("#2a1610"), C("#3a312c"), C("#a8463c"), C("#fff8ee")
ROBE, ROBE_D, ROBE_L, GOLD, GOLD_D = C("#8a2232"), C("#5e1622"), C("#b23c4a"), C("#e6b84a"), C("#a87c24")
SHIRT, SHIRT_D = C("#f4efe4"), C("#cfc8bb")
PANTS, SHOE, SHOE_L = C("#33303e"), C("#5a3420"), C("#8a5a3a")
WICKER, WICKER_D, APR, APR_L = C("#c08a4a"), C("#8a5a2a"), C("#f09a32"), C("#ffd07a")
AMBER, AMBER_D, TASSEL = C("#f0a030"), C("#b86a10"), C("#c0282c")

im = Image.new("RGBA", (64, 96)); d = ImageDraw.Draw(im)
# shoes and trousers
d.rectangle([22, 80, 29, 89], fill=PANTS); d.rectangle([34, 80, 41, 89], fill=PANTS)
d.rectangle([20, 89, 29, 93], fill=SHOE); d.rectangle([34, 89, 43, 93], fill=SHOE)
d.rectangle([21, 89, 23, 89], fill=SHOE_L); d.rectangle([40, 89, 42, 89], fill=SHOE_L)
# the robe: long, open at the front, gold trim and sash
d.rectangle([16, 40, 47, 81], fill=ROBE)
d.rectangle([16, 40, 19, 81], fill=ROBE_D); d.rectangle([45, 40, 47, 81], fill=ROBE_L)
d.polygon([(27, 40), (36, 40), (33, 56), (30, 56)], fill=SHIRT)
d.rectangle([29, 40, 34, 43], fill=SKIN_D)                       # open collar
d.line([(26, 40), (29, 56)], fill=GOLD); d.line([(37, 40), (34, 56)], fill=GOLD)
d.rectangle([17, 56, 46, 59], fill=GOLD); d.rectangle([17, 59, 46, 59], fill=GOLD_D)
d.line([(29, 60), (27, 81)], fill=GOLD); d.line([(34, 60), (36, 81)], fill=GOLD)
d.rectangle([28, 60, 35, 81], fill=ROBE_D)                       # the robe parts over the trousers
d.rectangle([29, 66, 34, 81], fill=PANTS)
d.rectangle([17, 80, 46, 81], fill=GOLD)                         # hem
# sleeves with gold cuffs, hands
d.rectangle([9, 42, 16, 67], fill=ROBE_D); d.rectangle([47, 42, 54, 67], fill=ROBE_L)
d.rectangle([9, 66, 16, 68], fill=GOLD); d.rectangle([47, 66, 54, 68], fill=GOLD)
d.rectangle([10, 69, 15, 73], fill=SKIN); d.rectangle([48, 69, 53, 73], fill=SKIN)
# a basket of apricots in the left hand (our left)
d.rectangle([2, 66, 18, 77], fill=WICKER)
for y in range(67, 77, 3): d.line([(3, y), (17, y)], fill=WICKER_D)
for x in range(4, 18, 4): d.line([(x, 66), (x, 76)], fill=WICKER_D)
d.arc([4, 54, 16, 74], 180, 360, fill=WICKER_D)
for cx, cy in ((5, 63), (9, 62), (13, 63), (7, 60), (11, 59)):
    d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=APR); d.point((cx - 1, cy - 1), fill=APR_L)
d.rectangle([10, 69, 15, 72], fill=SKIN)                         # fingers over the handle
# neck and head
d.rectangle([28, 34, 35, 40], fill=SKIN_D)
d.ellipse([20, 9, 43, 37], fill=SKIN)
d.rectangle([18, 20, 20, 26], fill=SKIN_D); d.rectangle([43, 20, 45, 26], fill=SKIN_D)   # ears
# silver hair, combed back, darker at the temples
d.ellipse([20, 5, 43, 22], fill=HAIR)
d.rectangle([20, 14, 43, 18], fill=HAIR)
d.ellipse([23, 12, 40, 26], fill=SKIN)                            # forehead
d.rectangle([20, 16, 22, 23], fill=HAIR_D); d.rectangle([41, 16, 43, 23], fill=HAIR_D)
for x in (25, 30, 35): d.line([(x, 7), (x + 3, 10)], fill=HAIR_D)
# face: brows, kind eyes, blush, nose, moustache, smile
d.rectangle([24, 18, 28, 19], fill=DARK); d.rectangle([35, 18, 39, 19], fill=DARK)
d.rectangle([26, 21, 27, 23], fill=DARK); d.rectangle([36, 21, 37, 23], fill=DARK)
d.point((26, 21), fill=(255, 255, 255, 255)); d.point((36, 21), fill=(255, 255, 255, 255))
d.rectangle([22, 25, 24, 26], fill=BLUSH); d.rectangle([39, 25, 41, 26], fill=BLUSH)
d.rectangle([31, 22, 32, 26], fill=SKIN_D); d.point((30, 26), fill=SKIN_D); d.point((33, 26), fill=SKIN_D)
d.rectangle([25, 28, 38, 30], fill=MOUST); d.rectangle([24, 30, 26, 31], fill=MOUST); d.rectangle([37, 30, 39, 31], fill=MOUST)
d.rectangle([28, 31, 35, 31], fill=TEETH); d.point((27, 31), fill=LIP); d.point((36, 31), fill=LIP)
d.rectangle([28, 32, 35, 32], fill=LIP)
outline(im)
# prayer beads from the right hand, drawn after the outline so they stay thin
px = im.load()
for i in range(10):
    px[51, 74 + i] = AMBER if i % 2 == 0 else AMBER_D
px[51, 84] = GOLD
for y in (85, 86):
    for x in (50, 51, 52): px[x, y] = TASSEL
im.save(f"{OUT}/guest_barin.png")
# preview next to the other guests
row = [Image.open(f"{OUT}/{n}.png").convert("RGBA") for n in ("guest_patient", "guest_barin", "guest_courier", "master_calm")]
k = 5
sheet = Image.new("RGBA", (sum(i.width * k + 20 for i in row), 96 * k), (60, 60, 70, 255))
x = 0
for i in row:
    big = i.resize((i.width * k, i.height * k), Image.NEAREST); sheet.paste(big, (x, 96 * k - big.height), big); x += i.width * k + 20
sheet.save(sys.argv[2])
print("ok")
