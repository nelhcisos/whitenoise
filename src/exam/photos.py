# Pixelate the exam photos: crop the black bars, shrink, quantize lightly, keep a soft pixel look.
#   python3 photos.py OUT_DIR PREFIX img1 img2 ...
import sys
from PIL import Image
out, prefix, srcs = sys.argv[1], sys.argv[2], sys.argv[3:]
for i, f in enumerate(srcs, 1):
    im = Image.open(f).convert("RGB")
    w, h = im.size
    px = im.load()
    dark = lambda x: sum(px[x, y][0] + px[x, y][1] + px[x, y][2] for y in range(0, h, 23)) / (3 * len(range(0, h, 23))) < 18
    x0 = 0
    while x0 < w // 3 and dark(x0): x0 += 1
    x1 = w - 1
    while x1 > 2 * w // 3 and dark(x1): x1 -= 1
    im = im.crop((x0 + 2, 0, x1 - 1, h))
    small = im.resize((240, round(240 * im.height / im.width)), Image.LANCZOS)
    small = small.quantize(colors=64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    small.save(f"{out}/{prefix}_{i}.png", optimize=True)
    print(f"{prefix}_{i}", small.size)
