# Cut the screens of the course «Моделирование и изготовление элайнеров с нуля» (М. Пешкова) out of the
# video frames: a pixelated board picture and a clear zoom of the same crop.
#   python3 al_slides.py FULL_FRAMES_DIR FIG_DIR MANIFEST.json [ids...]
# FULL_FRAMES_DIR holds <id>.png, the full frame (1920x1080; lesson 7 is 1280x720) at the listed second of the listed video.
# Crops keep the 3D window only: no patient data, no file dialogs, no lecturer.
import sys, json
from PIL import Image, ImageEnhance
FR, OUT, MAN = sys.argv[1], sys.argv[2], sys.argv[3]
VIEW = (372, 142, 1908, 978)      # Maestro: the 3D window right of the tool panel
APP = (0, 132, 1908, 978)         # Maestro with the tool panel
PLASTY = (60, 70, 1610, 1030)     # PlastyCAD's 3D window
VIEW2 = (585, 180, 1770, 975)     # Maestro in the smaller recording window (lessons 4-6)
SLIDES = [   # id, video, second, crop
    ("al_scan", "v04", 50, (0, 60, 1920, 1040)),
    ("al_raw", "v04", 150, PLASTY), ("al_base", "v04", 250, PLASTY), ("al_perf", "v04", 330, PLASTY),
    ("al_plane", "v09", 90, VIEW), ("al_width", "v09", 170, VIEW), ("al_border", "v10", 330, VIEW), ("al_border2", "v10", 170, VIEW),
    ("al_axes", "v08", 70, VIEW), ("al_manip", "v01", 10, VIEW2), ("al_split", "v01", 130, VIEW2), ("al_grid", "v03", 150, VIEW2),
    ("al_drag", "v08", 290, VIEW),
    ("al_att_fix", "v06", 30, VIEW), ("al_att_rot", "v06", 90, VIEW), ("al_att_neg", "v06", 170, VIEW),
    ("al_att_tri", "v06", 270, VIEW), ("al_att_rect", "v06", 350, VIEW),
    ("al_num", "v08", 670, VIEW), ("al_calc", "v08", 790, VIEW), ("al_contacts", "v01", 90, VIEW2), ("al_ipr", "v08", 1090, VIEW),
    ("al_c1_start", "v09", 410, VIEW), ("al_c1_att", "v09", 730, VIEW), ("al_c1_l3", "v09", 1050, VIEW), ("al_c1_calc", "v09", 1290, VIEW),
    ("al_c2_dist", "v10", 490, VIEW), ("al_c2_grid", "v10", 890, VIEW), ("al_c2_cont", "v10", 810, VIEW), ("al_c2_att", "v10", 1130, VIEW),
    ("al_ct_teeth", "v05", 90, (160, 200, 960, 640)), ("al_ct_bone", "v05", 210, (200, 22, 900, 380)), ("al_ct_root", "v05", 490, (350, 150, 980, 560)),
]
BOX_W, BOX_H, PIX, COLORS, ZOOM_W = 616, 300, 1.5, 48, 1000
if __name__ == "__main__":
    man = {}
    only = set(sys.argv[4:])
    for sid, v, t, box in SLIDES:
        if only and sid not in only:
            continue
        crop = Image.open(f"{FR}/{sid}.png").convert("RGB").crop(box)
        cw, ch = crop.size
        s = min(BOX_W / cw, BOX_H / ch)
        bw, bh = max(1, round(cw * s / PIX)), max(1, round(ch * s / PIX))
        board = ImageEnhance.Contrast(crop.resize((bw, bh), Image.LANCZOS)).enhance(1.06)
        board = board.quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        board.save(f"{OUT}/{sid}.png", optimize=True)
        crop.resize((ZOOM_W, round(ch * ZOOM_W / cw)), Image.LANCZOS).save(f"{OUT}/{sid}_z.webp", quality=80, method=6)
        man[sid] = {"v": v, "t": t, "w": bw, "h": bh}
    json.dump(man, open(MAN, "w"), indent=0)
    print(len(man), "slides")
