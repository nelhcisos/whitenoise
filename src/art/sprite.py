# Seated barin sprite (32 wide). Validates row widths and renders a preview.
import sys
from PIL import Image
PAL = {
 'K': '#2a1610', 'H': '#4a403a', 'h': '#a9a39b', 'S': '#e8b48c', 's': '#c98f66', 'B': '#2b211d',
 'E': '#2a1610', 'C': '#ec9a86', 'M': '#3a312c', 'L': '#a8463c', 'T': '#fff8ee',
 'W': '#f4efe4', 'w': '#cfc8bb', 'R': '#8a2232', 'r': '#5e1622', 'Q': '#b23c4a', 'G': '#e6b84a', 'g': '#a87c24',
 'P': '#33303e', 'p': '#22202a', 'N': '#5a3420', 'n': '#8a5a3a', 'A': '#f0a030', 'a': '#b86a10',
}
ROWS = [
 "...........KKKKKKKKKK...........",  # 0 hair top
 ".........KKhhhhhhhhhhKK.........",  # 1
 "........KhhhHHHHHHHHhhhK........",  # 2
 "........KhHHHHHHHHHHHHhK........",  # 3
 "........KHHSSSSSSSSSSHHK........",  # 4 forehead
 "........KhSSSSSSSSSSSShK........",  # 5
 "........KhSBBBSSSSBBBShK........",  # 6 brows
 ".......KSSSSEESSSSEESSSSK.......",  # 7 eyes, ears
 ".......KsSCCSSSssSSSCCSsK.......",  # 8 cheeks, nose bridge
 "........KSSSSSsSSsSSSSSK........",  # 9 nose
 "........KSSSMMMMMMMMSSSK........",  # 10 moustache
 "........KSSMMMMMMMMMMSSK........",  # 11
 "........KSSSSLTTTTLSSSSK........",  # 12 smile
 "........KSSSSSLLLLSSSSSK........",  # 13
 ".........KSSSSSSSSSSSSK.........",  # 14 chin
 "..........KKSSSSSSSSKK..........",  # 15
 "...........KssssssssK...........",  # 16 neck
 "......KKKRRRGWWWWWWGRRRKKK......",  # 17 collar
 "....KKRRRRRRGWWWWWWGRRRRRRKK....",  # 18 shoulders
 "...KRRRRRRRRGWWWWWWGRRRRRRRRK...",  # 19
 "..KRRrRRRRRRRGWWWWGRRRRRRRQRRK..",  # 20
 "..KRRrRRRRRRRGWwwWGRRRRRRRQRRK..",  # 21
 "..KRRrRRRRRRRRGWWGRRRRRRRRQRRK..",  # 22
 "..KRRrRRRRRRRRGWWGRRRRRRRRQRRK..",  # 23
 "..KRRrKRRRRRRRRGGRRRRRRRRKQRRK..",  # 24 arms separate from the body
 "..KRRrKRRRRRRRRRRRRRRRRRRKQRRK..",  # 25
 "..KRRrKRRRgGGGGGGGGGGGGgRKQRRK..",  # 26 sash
 "..KRRrKRRRgGGGGGGGGGGGGgRKQRRK..",  # 27
 "..KRRrKRRRRRRRRRRRRRRRRRRKQRRK..",  # 28
 "..KRRRRKKRRRRRRRRRRRRRRKKRRRRK..",  # 29 forearms turn in
 "..KKRRRRRRKKRRRRRRRRRKKRRRRRKK..",  # 30
 "...KSSSRRRRRKKRRRRRKKRRRRRSSSK..",  # 31 hands
 "...KSSSSKRRRRRKKKKKRRRRRKSSSSK..",  # 32
 "...KSSSSKPPPPPPPPPPPPPPPKSSSSK..",  # 33 lap
 "....KAAKPPPPPPPPPPPPPPPPPKKKK...",  # 34 beads start
 "....KAKPPPPPPPPPpPPPPPPPPPPK....",  # 35
 "....KAKPPPPPPPPPpPPPPPPPPPPK....",  # 36
 "....KAKRRPPPPPPPpPPPPPPPPRRK....",  # 37 robe hem over the knees
 "....KAKRRRPPPPPPpPPPPPPPRRRK....",  # 38
 "....KAKRRRKPPPPKpKPPPPKRRRRK....",  # 39 shins
 "....KAKRRRKPPPPK.KPPPPKRRRRK....",  # 40
 "...KAAAKRRKPPPPK.KPPPPKRRRK.....",  # 41
 "...KAaAKRRKPPPPK.KPPPPKRRRK.....",  # 42 tassel
 "....KaK.KKKPPPPK.KPPPPKKKK......",  # 43
 ".....K....KPPPPK.KPPPPK.........",  # 44
 "..........KPPPPK.KPPPPK.........",  # 45
 "..........KPPPPK.KPPPPK.........",  # 46
 ".........KNNNNNK.KNNNNNK........",  # 47 shoes
 "........KNnNNNNK.KNNNNnNK.......",  # 48
 "........KKKKKKKK.KKKKKKKK.......",  # 49
]
bad = [(i, len(r)) for i, r in enumerate(ROWS) if len(r) != 32]
if bad:
    print("BAD ROWS", bad); sys.exit(1)
def render(rows, scale=8, bg=(70, 60, 60)):
    h, w = len(rows), len(rows[0])
    im = Image.new('RGB', (w * scale, h * scale), bg)
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in PAL:
                c = tuple(int(PAL[ch][i:i+2], 16) for i in (1, 3, 5))
                for yy in range(scale):
                    for xx in range(scale):
                        px[x * scale + xx, y * scale + yy] = c
    return im
render(ROWS).save(sys.argv[1])
print("ok", len(ROWS))
