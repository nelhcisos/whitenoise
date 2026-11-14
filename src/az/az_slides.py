# Cut slides of the webinars «Элайнеры от А до Я» out of the video frames: a pixelated board picture and a
# clear zoom. The lecturer's webcam box is painted over with the colour around it; faces of patients are not used.
#   python3 az_slides.py FRAMES_DIR FIG_DIR [ids...]
# FRAMES_DIR/<w01..w11>/f_NNNN.jpg: a 1280x720 frame every 30 s (frame N is second 30*N - 15).
# Each slide: id, webinar, "m:ss" of the frame, crop box or None (whole frame), boxes to paint over.
import sys
from PIL import Image, ImageDraw, ImageEnhance
FR, OUT = sys.argv[1], sys.argv[2]
K = 1280 / 384   # boxes below are measured on 384x216 thumbnails
W2 = (0, 19, 288, 182)
SLIDES = [
    ("az1_keys", "w01", "1:15", None, [(311, 88, 384, 138)]),
    ("az1_shift", "w01", "6:15", None, [(311, 46, 384, 92)]),
    ("az1_bt", "w01", "12:15", None, [(309, 80, 384, 130)]),
    ("az1_serial", "w01", "14:15", None, [(294, 170, 374, 216)]),
    ("az1_p1", "w01", "23:15", None, [(308, 158, 384, 207)]),
    ("az1_p2", "w01", "25:15", None, [(0, 20, 77, 70)]),
    ("az1_bevel", "w01", "31:15", None, [(0, 20, 76, 70)]),
    ("az1_a70", "w01", "43:15", None, [(0, 158, 76, 207)]),
    ("az1_l7", "w01", "46:15", None, [(309, 102, 384, 152)]),
    ("az1_ramus", "w01", "51:15", None, [(309, 100, 384, 150)]),
    ("az1_sublux", "w01", "55:15", None, [(300, 68, 384, 150), (0, 140, 40, 216)]),
    ("az1_rot", "w01", "63:15", None, [(0, 36, 77, 84)]),
    ("az1_iq", "w01", "66:15", None, [(0, 33, 77, 84)]),
    ("az1_vert", "w01", "69:15", None, [(0, 33, 77, 84)]),
    ("az1_off", "w01", "71:15", None, [(0, 28, 77, 82)]),
    ("az1_deep", "w01", "77:15", None, [(0, 150, 77, 216)]),
    ("az1_frenum", "w01", "80:15", None, [(0, 156, 77, 207)]),
    ("az1_tmd", "w01", "83:15", None, [(0, 156, 77, 207)]),
    ("az1_intr", "w01", "86:15", None, []),
    ("az1_pref", "w01", "88:15", None, []),
    ("az1_tips", "w01", "92:15", None, []),
    # webinar 2 (Diego Peydro): the slide fills the left three quarters, the webcam sits to the right of it
    ("az2_dod", "w02", "11:15", W2, []),
    ("az2_aurea", "w02", "12:15", W2, []),
    ("az2_final", "w02", "14:15", W2, []),
    ("az2_tri", "w02", "16:15", W2, []),
    ("az2_class2", "w02", "19:15", W2, []),
    ("az2_list", "w02", "21:15", W2, []),
    ("az2_limit", "w02", "24:15", W2, []),
    ("az2_exp", "w02", "26:15", W2, []),
    ("az2_keys", "w02", "29:15", W2, []),
    ("az2_unblock", "w02", "33:15", W2, []),
    ("az2_seq", "w02", "34:15", W2, []),
    ("az2_hgb", "w02", "41:15", W2, []),
    ("az2_intr", "w02", "46:15", W2, []),
    ("az2_ipr", "w02", "48:15", W2, []),
    ("az2_iprp", "w02", "49:15", W2, []),
    ("az2_case2", "w02", "62:15", W2, []),
    ("az2_tmj", "w02", "64:15", W2, []),
    ("az2_plan", "w02", "66:15", W2, []),
    ("az2_comp", "w02", "67:15", W2, []),
    ("az2_after", "w02", "78:15", W2, []),
    # webinar 3 (Heloísa Alves: the slide fills the left four fifths, above a footer bar)
    ("az3_base", "w03", "5:15", (0, 19, 310, 178), []),
    ("az3_risky", "w03", "6:15", (0, 19, 310, 178), []),
    ("az3_pies", "w03", "8:15", (0, 19, 310, 178), []),
    ("az3_ant", "w03", "13:15", (0, 19, 310, 178), []),
    ("az3_squeeze", "w03", "14:15", (0, 19, 310, 178), []),
    ("az3_vert", "w03", "18:15", (0, 19, 310, 178), []),
    ("az3_pm", "w03", "19:15", (0, 19, 310, 178), []),
    ("az3_open", "w03", "20:15", (0, 19, 310, 178), []),
    ("az3_res", "w03", "21:15", (0, 19, 310, 178), []),
    ("az3_dist", "w03", "25:15", (0, 19, 310, 178), []),
    ("az3_elast", "w03", "26:15", (0, 19, 310, 178), []),
    ("az3_intr", "w03", "27:15", (0, 19, 310, 178), []),
    ("az3_exp", "w03", "37:15", (0, 19, 310, 178), []),
    ("az3_lines", "w03", "38:15", (0, 19, 310, 178), []),
    ("az3_al", "w03", "41:15", (0, 19, 310, 178), []),
]
BOX_W, BOX_H, PIX, COLORS, ZOOM_W = 616, 300, 1.4, 56, 960

def paint(im, box):
    """Fill the box with the median colour of a thin frame around it."""
    x0, y0, x1, y1 = [round(v * K) for v in box]
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(im.width, x1), min(im.height, y1)
    ring = []
    px = im.load()
    for x in range(max(0, x0 - 6), min(im.width, x1 + 6), 3):
        for y in (y0 - 5, y1 + 4):
            if 0 <= y < im.height: ring.append(px[x, y])
    for y in range(max(0, y0 - 6), min(im.height, y1 + 6), 3):
        for x in (x0 - 5, x1 + 4):
            if 0 <= x < im.width: ring.append(px[x, y])
    ring.sort(key=sum)
    ImageDraw.Draw(im).rectangle([x0, y0, x1, y1], fill=ring[len(ring) // 2])

if __name__ == "__main__":
    only = set(sys.argv[3:])
    n = 0
    for sid, w, t, box, cams in SLIDES:
        if only and sid not in only and w not in only: continue
        m, s = t.split(":"); k = (int(m) * 60 + int(s) - 15) // 30 + 1
        im = Image.open(f"{FR}/{w}/f_{k:04d}.jpg").convert("RGB")
        for c in cams: paint(im, c)
        crop = im.crop([round(v * K) for v in box]) if box else im
        cw, ch = crop.size
        sc = min(BOX_W / cw, BOX_H / ch)
        bw, bh = max(1, round(cw * sc / PIX)), max(1, round(ch * sc / PIX))
        board = ImageEnhance.Contrast(crop.resize((bw, bh), Image.LANCZOS)).enhance(1.06)
        board.quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB").save(f"{OUT}/{sid}.png", optimize=True)
        zw = min(ZOOM_W, cw)
        crop.resize((zw, round(ch * zw / cw)), Image.LANCZOS).save(f"{OUT}/{sid}_z.webp", quality=78, method=6)
        n += 1
    print(n, "slides")
