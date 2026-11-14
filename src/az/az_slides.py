# Cut slides of the webinars «Элайнеры от А до Я» out of the video frames and lay them on one sheet per
# webinar (the artifact that hosts the game holds a limited number of files). The lecturer's webcam box is painted over with the colour around it; faces of patients are not used.
#   python3 az_slides.py FRAMES_DIR FIG_DIR [ids...]
# FRAMES_DIR/<w01..w11>/f_NNNN.jpg: a 1280x720 frame every 30 s (frame N is second 30*N - 15).
# Each slide: id, webinar, "m:ss" of the frame, crop box or None (whole frame), boxes to paint over.
import sys
from PIL import Image, ImageDraw
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
    # webinar 4 (Jay Bowman: the slide fills the left three quarters, the webcam sits to the right)
    ("az4_41", "w04", "7:15", (0, 0, 290, 216), []),
    ("az4_chew", "w04", "18:15", (0, 0, 290, 216), []),
    ("az4_tear", "w04", "22:15", (0, 0, 290, 216), []),
    ("az4_notch", "w04", "23:15", (0, 0, 290, 216), []),
    ("az4_case1", "w04", "25:15", (0, 0, 290, 216), []),
    ("az4_daher", "w04", "31:15", (0, 0, 290, 216), [(12, 28, 78, 92)]),
    ("az4_combo", "w04", "35:15", (0, 0, 290, 216), []),
    ("az4_hjet", "w04", "42:15", (0, 0, 290, 216), []),
    ("az4_punch", "w04", "45:15", (0, 0, 290, 216), []),
    ("az4_boot", "w04", "48:15", (0, 0, 290, 216), []),
    ("az4_boot2", "w04", "49:15", (0, 0, 290, 216), []),
    ("az4_space", "w04", "54:15", (0, 0, 290, 216), [(196, 22, 290, 92)]),
    ("az4_sling", "w04", "65:15", (0, 0, 290, 216), [(180, 150, 215, 190)]),
    ("az4_box", "w04", "66:15", (0, 0, 290, 216), []),
    ("az4_vert", "w04", "69:15", (0, 20, 290, 216), []),
    ("az4_horiz", "w04", "71:15", (0, 0, 290, 216), []),
    ("az4_tip", "w04", "72:15", (0, 0, 290, 216), []),
    ("az4_wilson", "w04", "74:15", (0, 0, 290, 216), [(0, 138, 46, 204)]),
    ("az4_apex", "w04", "79:15", (0, 0, 290, 216), []),
    # webinar 5 (Pedro Costa-Monteiro: the slide fills the left four fifths; photos of children are cropped away)
    ("az5_grow", "w05", "6:15", (0, 22, 302, 190), []),
    ("az5_problems", "w05", "9:15", (0, 22, 302, 190), []),
    ("az5_why", "w05", "19:45", (0, 22, 302, 190), []),
    ("az5_two", "w05", "22:45", (0, 22, 302, 190), []),
    ("az5_ind", "w05", "25:45", (0, 22, 302, 190), []),
    ("az5_incl", "w05", "28:45", (0, 22, 192, 190), []),
    ("az5_stag", "w05", "37:45", (0, 22, 302, 190), []),
    ("az5_2mm", "w05", "40:45", (0, 22, 302, 190), []),
    ("az5_att", "w05", "43:45", (0, 22, 302, 190), []),
    ("az5_erup", "w05", "48:15", (0, 22, 302, 190), []),
    ("az5_timing", "w05", "52:45", (0, 22, 302, 190), []),
    ("az5_exp", "w05", "54:15", (0, 22, 302, 190), []),
    ("az5_tsd", "w05", "55:45", (0, 22, 302, 190), []),
    ("az5_75", "w05", "64:45", (0, 22, 302, 190), []),
    ("az5_changes", "w05", "66:15", (0, 22, 302, 190), []),
    ("az5_cc40", "w05", "69:15", (0, 22, 302, 190), []),
    ("az5_7days", "w05", "70:45", (0, 22, 302, 190), []),
    ("az5_plan", "w05", "78:15", (0, 22, 302, 190), []),
    ("az5_23", "w05", "79:45", (0, 22, 302, 190), []),
    ("az5_18", "w05", "81:15", (0, 22, 302, 190), []),
    ("az5_crowd", "w05", "85:45", (0, 22, 302, 190), []),
    ("az5_al16", "w05", "88:45", (0, 22, 302, 190), []),
    ("az5_ma", "w05", "97:45", (0, 22, 302, 190), []),
    ("az5_pred", "w05", "115:45", (0, 22, 302, 190), []),
    # webinar 6 (Mikhail Shishkin: the slide fills the left four fifths, the webcam sits to the right)
    ("az6_press", "w06", "10:15", (0, 22, 302, 184), []),
    ("az6_exp", "w06", "12:15", (0, 22, 302, 184), []),
    ("az6_disp", "w06", "14:15", (0, 22, 302, 184), []),
    ("az6_print", "w06", "24:15", (0, 22, 302, 184), []),
    ("az6_uv", "w06", "26:15", (0, 22, 302, 184), []),
    ("az6_trim", "w06", "30:15", (0, 22, 302, 184), []),
    ("az6_layers", "w06", "32:15", (0, 22, 302, 184), []),
    ("az6_guide", "w06", "36:15", (0, 22, 302, 184), []),
    ("az6_prep", "w06", "46:15", (0, 22, 302, 184), []),
    ("az6_sarpe", "w06", "52:15", (0, 22, 302, 184), []),
    ("az6_elast", "w06", "70:15", (0, 22, 302, 184), []),
    ("az6_tip", "w06", "76:15", (0, 22, 302, 184), []),
    ("az6_strip", "w06", "80:15", (0, 22, 302, 184), []),
    ("az6_disc", "w06", "90:15", (0, 22, 302, 184), []),
    ("az6_seed", "w06", "96:15", (0, 22, 302, 184), []),
    ("az6_ipr", "w06", "98:15", (0, 22, 302, 184), []),
    ("az6_chain", "w06", "112:15", (0, 22, 302, 184), []),
    ("az6_rotsum", "w06", "118:15", (0, 22, 302, 184), []),
    ("az6_pliers", "w06", "128:15", (0, 22, 302, 184), []),
    ("az6_dimple", "w06", "130:15", (0, 22, 302, 184), []),
    ("az6_fit", "w06", "138:15", (0, 22, 302, 184), []),
    ("az6_gap", "w06", "142:15", (0, 22, 302, 184), []),
    ("az6_ref", "w06", "146:15", (0, 22, 302, 184), []),
    ("az6_open", "w06", "160:15", (0, 22, 302, 184), []),
    ("az6_setup", "w06", "170:15", (0, 22, 302, 184), []),
]
CW, CH, COLS = 800, 450, 4   # a sheet's cell; each slide sits in the top left corner of its cell

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
    # one sheet per webinar: FIG_DIR/az_wNN.webp, and FIG_DIR/az_atlas.json with each slide's place on it
    import json, os
    only = set(sys.argv[3:])
    man_path = f"{OUT}/az_atlas.json"
    man = json.load(open(man_path)) if os.path.exists(man_path) else {}
    for w in sorted({x[1] for x in SLIDES}):
        if only and w not in only: continue
        mine = [x for x in SLIDES if x[1] == w]
        rows = (len(mine) + COLS - 1) // COLS
        sheet = Image.new("RGB", (CW * COLS, CH * rows), (0, 0, 0))
        for n, (sid, _, t, box, cams) in enumerate(mine):
            m, s = t.split(":"); k = (int(m) * 60 + int(s) - 15) // 30 + 1
            im = Image.open(f"{FR}/{w}/f_{k:04d}.jpg").convert("RGB")
            for c in cams: paint(im, c)
            crop = im.crop([round(v * K) for v in box]) if box else im
            sc = min(CW / crop.width, CH / crop.height)
            tw, th = round(crop.width * sc), round(crop.height * sc)
            x, y = (n % COLS) * CW, (n // COLS) * CH
            sheet.paste(crop.resize((tw, th), Image.LANCZOS), (x, y))
            man[sid] = {"f": f"az_{w}", "x": x, "y": y, "w": tw, "h": th, "W": sheet.width, "H": sheet.height}
        sheet.save(f"{OUT}/az_{w}.webp", quality=76, method=6)
        print(w, len(mine), "slides", sheet.size, os.path.getsize(f"{OUT}/az_{w}.webp") // 1024, "KB")
    json.dump(man, open(man_path, "w"), indent=0)
