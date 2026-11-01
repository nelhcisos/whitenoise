# Cut the textbook figures out of the page photos and pixelate them.
# For each figure: <id>.png — pixel version for the chalkboard; <id>_z.png — clearer version for zooming in.
import sys, json
from PIL import Image, ImageEnhance
UP, OUT = sys.argv[1], sys.argv[2]
PAGES = {107: "9acb7c63", 108: "b7e46958", 110: "85709a42", 111: "22718eec", 113: "bd180ffe", 114: "8ac31eb3",
         116: "efd9b972", 118: "4a8ec502", 119: "c353b763", 120: "add90c29", 122: "29a715ae"}
FIGS = [
    ("f107_7", 107, (121, 467, 638, 872), "draw"), ("f107_8", 107, (121, 987, 721, 1448), "draw"),
    ("f108_9", 108, (217, 691, 992, 921), "draw"), ("f108_10", 108, (118, 1110, 1090, 1370), "draw"),
    ("f110_13", 110, (656, 697, 1090, 1225), "draw"),
    ("f111_1", 111, (121, 848, 630, 1210), "photo"),
    ("f113_3", 113, (638, 390, 1093, 698), "draw"), ("f113_4", 113, (266, 788, 948, 1388), "draw"),
    ("f114_5", 114, (207, 928, 1000, 1372), "photo"),
    ("f116_6", 116, (118, 158, 1090, 450), "draw"), ("f116_7", 116, (118, 585, 621, 1063), "draw"), ("f116_8", 116, (118, 1128, 656, 1448), "draw"),
    ("f118_9", 118, (263, 167, 946, 650), "draw"), ("f118_10", 118, (121, 755, 1090, 1205), "photo"),
    ("f119_11", 119, (210, 930, 1004, 1306), "draw"),
    ("f120_12", 120, (118, 158, 1090, 521), "draw"),
    ("f122_1", 122, (118, 160, 1090, 521), "draw"), ("f122_2", 122, (118, 621, 1090, 982), "draw"), ("f122_3", 122, (232, 1078, 977, 1393), "draw"),
]
BOX_W, BOX_H = 616, 300          # where the figure sits on the 640x400 board
PIX = {"photo": 2.0, "draw": 1.7, "text": 1.3}      # board pixel size (bigger = chunkier)
COLORS = {"photo": 48, "draw": 32, "text": 24}

def quant(im, n):
    return im.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")

# flipbook figures: frames in crop pixels (x0, y0, x1, y1); the board shows one frame at a time
FRAMES = {} and {
    "f18_15": [(0, 0, 973, 190), (0, 190, 973, 375), (0, 375, 973, 560), (0, 560, 973, 740), (0, 740, 973, 919)],
    "f52_8": [(0, 0, 288, 211), (0, 214, 288, 425), (0, 428, 288, 637), (295, 0, 581, 211), (295, 214, 581, 425), (295, 428, 581, 637)],
}
manifest = {}
cache = {}
def page_img(page):
    if page not in cache:
        cache[page] = Image.open(f"{UP}/{PAGES[page]}-image.jpg").convert("RGB")
    return cache[page]
for fid, page, box, kind in FIGS:
    if isinstance(box, list):          # several parts of one figure, side by side, without the caption text
        parts = [page_img(page).crop(b) for b in box]
        crop = Image.new("RGB", (sum(p.width for p in parts) + 12 * (len(parts) - 1), max(p.height for p in parts)), (255, 255, 255))
        x = 0
        for part in parts:
            crop.paste(part, (x, 0)); x += part.width + 12
    else:
        crop = page_img(page).crop(box)
    cw, ch = crop.size
    if fid in FRAMES:
        fw = max(f[2] - f[0] for f in FRAMES[fid]); fh = max(f[3] - f[1] for f in FRAMES[fid])
        s = min(BOX_W / fw, (BOX_H - 26) / fh)
    else:
        s = min(BOX_W / cw, BOX_H / ch)
    bw, bh = max(1, round(cw * s / PIX[kind])), max(1, round(ch * s / PIX[kind]))
    board = quant(ImageEnhance.Contrast(crop.resize((bw, bh), Image.LANCZOS)).enhance(1.08), COLORS[kind])
    board.save(f"{OUT}/{fid}.png", optimize=True)
    zw = min(cw, 820)
    zh = round(ch * zw / cw)
    crop.resize((zw, zh), Image.LANCZOS).save(f"{OUT}/{fid}_z.webp", quality=84, method=6)
    manifest[fid] = {"page": page, "w": bw, "h": bh, "zw": zw, "zh": zh, "kind": kind}
    if fid in FRAMES:
        manifest[fid]["frames"] = [[round(a / cw, 4), round(b / ch, 4), round((c - a) / cw, 4), round((d - b) / ch, 4)] for a, b, c, d in FRAMES[fid]]
json.dump(manifest, open(sys.argv[3] if len(sys.argv) > 3 else "fig_manifest.json", "w"), indent=0)
print(len(manifest), "figures")
