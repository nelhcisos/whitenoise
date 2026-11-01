# Cut the textbook figures out of the page photos and pixelate them.
# For each figure: <id>.png — pixel version for the chalkboard; <id>_z.png — clearer version for zooming in.
import sys, json
from PIL import Image, ImageEnhance
UP, OUT = sys.argv[1], sys.argv[2]
PAGES = {62: "4e376dbd", 65: "b03446bb", 67: "a02f399b", 68: "db450173", 70: "f4151158", 71: "368f83a1", 73: "ce46aef0", 76: "c1abc366"}
FIGS = [
    ("f62_1", 62, (573, 1080, 1090, 1447), "draw"),
    ("f65_5", 65, (188, 158, 1026, 488), "draw"),
    ("f67_1", 67, (121, 910, 1090, 1342), "photo"),
    ("f68_2", 68, (116, 158, 1091, 592), "photo"), ("f68_3", 68, (571, 773, 1090, 1120), "photo"),
    ("f70_5", 70, (118, 580, 1088, 1230), "photo"),
    ("f71_6", 71, (121, 338, 1090, 990), "photo"),
    ("f73_10", 73, (555, 160, 1093, 750), "draw"),
    ("f76_4", 76, (718, 437, 1090, 790), "draw"), ("f76_3", 76, (118, 1007, 697, 1317), "draw"), ("f76_5", 76, (718, 1007, 1090, 1317), "draw"),
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
