# Turn a book cover photo into the app icon: square, pixelated in the game's style, 64x64.
#   python3 cover.py cover.jpg out.png [crop|fit] [grid]
# crop: the central square of the cover; fit: the whole cover on a matching background.
# grid: how many big pixels across (32 = chunky, 48 = finer).
import sys
from PIL import Image, ImageOps, ImageFilter
src, out = sys.argv[1], sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else "fit"
grid = int(sys.argv[4]) if len(sys.argv) > 4 else 32
im = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
w, h = im.size
if mode == "crop":
    s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
else:
    # the cover's own edge colour fills the rest of the square
    edge = im.resize((1, 1), Image.LANCZOS, box=(0, 0, max(1, w // 12), h)).getpixel((0, 0))
    s = max(w, h)
    bg = Image.new("RGB", (s, s), edge)
    bg.paste(im, ((s - w) // 2, (s - h) // 2))
    im = bg
small = im.filter(ImageFilter.SMOOTH_MORE).resize((grid, grid), Image.LANCZOS)
small = small.quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
icon = small.resize((64, 64), Image.NEAREST) if 64 % grid == 0 else small.resize((64, 64), Image.NEAREST)
icon.save(out)
icon.resize((256, 256), Image.NEAREST).save(out.replace(".png", "_big.png"))
print("ok", src, "->", out, mode, grid)
