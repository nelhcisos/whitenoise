# Cut the lecture's slides out of the video frames and pixelate them for the chalkboard.
#   python3 slides.py FRAMES_DIR FIG_DIR MANIFEST.json
# Each slide: id, second of the video, crop box in the 854x480 frame, kind (photo / draw / text).
# The webinar's webcam box (402..612 x 0..119, until ~92 min) and the later corner badge are painted
# over with the slide's own background, so no faces of the lecturer and no chat get in.
import sys, json
from PIL import Image, ImageDraw, ImageEnhance
FR, OUT, MAN = sys.argv[1], sys.argv[2], sys.argv[3]
SLIDES = [
    ("pz_params", 330, (0, 52, 612, 446), "photo"),
    ("pz_frush", 500, (0, 62, 612, 446), "draw"),
    ("pz_sarver", 640, (0, 150, 612, 400), "photo"),
    ("pz_harm", 820, (0, 100, 612, 340), "photo"),
    ("pz_head", 950, (0, 40, 612, 446), "photo"),
    ("pz_brazil", 1250, (0, 0, 612, 446), "draw"),
    ("pz_canine", 1400, (0, 0, 612, 446), "draw"),
    ("pz_mbt", 1640, (0, 60, 612, 446), "draw"),
    ("pz_alex", 2050, (60, 60, 520, 446), "draw"),
    ("pz_pitts", 2220, (0, 0, 612, 446), "draw"),
    ("pz_544", 2600, (0, 0, 612, 446), "draw"),
    ("pz_planes", 2700, (0, 0, 612, 446), "draw"),
    ("pz_height", 2950, (0, 0, 612, 446), "draw"),
    ("pz_protr", 3200, (0, 0, 612, 446), "draw"),
    ("pz_indiv", 3420, (0, 0, 612, 446), "draw"),
    ("pz_ridges", 4460, (0, 120, 612, 446), "photo"),
    ("pz_grind", 4600, (0, 0, 612, 446), "photo"),
    ("pz_guid", 4830, (0, 0, 612, 446), "draw"),
    ("pz_lower", 5560, (0, 0, 612, 446), "draw"),
    ("pz_case", 5730, (0, 0, 612, 446), "photo"),
    ("pz_ang1", 6050, (0, 0, 612, 446), "photo"),
    ("pz_ang2", 6200, (0, 0, 612, 446), "photo"),
]
BOX_W, BOX_H = 616, 300
PIX = {"photo": 2.0, "draw": 1.6, "text": 1.3}
COLORS = {"photo": 56, "draw": 36, "text": 24}

def paint_over(im, box):
    """Fill box with the slide's background: white on a light slide, black otherwise."""
    x0, y0, x1, y1 = box
    small = im.crop((0, 0, 612, 446)).resize((153, 112))
    px = small.load()
    light = sum(1 for y in range(112) for x in range(153)
                if not (x0 // 4 <= x < x1 // 4 and y < y1 // 4) and sum(px[x, y]) > 690)
    ImageDraw.Draw(im).rectangle(box, fill=(255, 255, 255) if light > 0.5 * 153 * 112 else (0, 0, 0))

if __name__ == "__main__":
    man = {}
    only = set(sys.argv[4:])
    for sid, t, box, kind in SLIDES:
        if only and sid not in only:
            continue
        im = Image.open(f"{FR}/s_{t}.png").convert("RGB")
        paint_over(im, (402, 0, 612, 120) if t < 5530 else (580, 0, 612, 32))
        crop = im.crop(box)
        cw, ch = crop.size
        s = min(BOX_W / cw, BOX_H / ch)
        bw, bh = max(1, round(cw * s / PIX[kind])), max(1, round(ch * s / PIX[kind]))
        board = crop.resize((bw, bh), Image.LANCZOS)
        board = ImageEnhance.Contrast(board).enhance(1.06)
        board = board.quantize(colors=COLORS[kind], method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        board.save(f"{OUT}/{sid}.png", optimize=True)
        zoom = crop.resize((cw * 3 // 2, ch * 3 // 2), Image.LANCZOS)
        zoom.save(f"{OUT}/{sid}_z.webp", quality=86, method=6)
        man[sid] = {"t": t, "w": bw, "h": bh, "kind": kind}
        print(sid, bw, bh)
    json.dump(man, open(MAN, "w"), indent=0)
