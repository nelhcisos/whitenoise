# Cut the textbook figures out of the page photos and pixelate them.
# For each figure: <id>.png — pixel version for the chalkboard; <id>_z.png — clearer version for zooming in.
import sys, json
from PIL import Image, ImageEnhance
UP, OUT = sys.argv[1], sys.argv[2]
PAGES = {63: "50b8c050", 66: "6682da75", 69: "fead2829", 72: "6ed3352d", 74: "c19c78b0", 77: "80a3c368",
         80: "bc4a20ab", 83: "268ea056", 86: "39007736", 89: "e075ef3b", 91: "b411bf4c", 94: "981bfd3a",
         97: "8f57529a", 103: "026732b3", 106: "69ffa2a6", 109: "8518bc00"}
FIGS = [
    ("f63_2", 63, (120, 158, 638, 526), "draw"), ("f63_3", 63, (658, 158, 1093, 680), "draw"),
    ("f69_4", 69, (120, 545, 1088, 1200), "photo"),
    ("f72_7", 72, (118, 163, 1088, 483), "photo"), ("f72_8", 72, (118, 593, 1088, 915), "photo"), ("f72_9", 72, (118, 1028, 1088, 1350), "photo"),
    ("f74_11", 74, (118, 163, 1088, 815), "photo"), ("f74_12", 74, (573, 990, 1090, 1376), "photo"),
    ("f77_6", 77, (183, 158, 1031, 598), "draw"),
    ("f80_1", 80, (243, 1006, 965, 1332), "draw"),
    ("f83_5", 83, [(120, 158, 690, 470), (700, 158, 1093, 690)], "draw"), ("f83_6", 83, [(120, 710, 705, 1257), (705, 720, 1093, 1075)], "draw"),
    ("f86_10", 86, [(140, 168, 1060, 425), (140, 428, 570, 742)], "photo"), ("f86_11", 86, [(140, 783, 1060, 1035), (140, 1037, 540, 1313)], "photo"),
    ("f89_3", 89, (594, 158, 1093, 563), "draw"), ("f89_4", 89, (120, 1045, 1093, 1366), "draw"),
    ("f91_7", 91, (535, 512, 1093, 949), "draw"), ("f91_8", 91, (121, 1019, 1093, 1361), "draw"),
    ("f94_13", 94, (118, 158, 1090, 463), "draw"), ("f94_14", 94, (118, 1013, 1090, 1368), "draw"),
    ("f97_4", 97, (245, 158, 969, 712), "draw"), ("f97_5", 97, (245, 824, 969, 1320), "draw"),
    ("f103_1", 103, (122, 750, 632, 1123), "photo"),
    ("f106_6", 106, (118, 158, 718, 604), "draw"), ("t106_1", 106, (272, 673, 935, 1140), "text"),
    ("f109_11", 109, (658, 158, 1093, 658), "draw"), ("f109_12", 109, (120, 912, 1093, 1350), "draw"),
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
