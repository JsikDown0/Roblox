import os as _os
_HERE = _os.path.dirname(_os.path.abspath(__file__))
import sys; sys.path.insert(0, _HERE)
import importlib, sniper_v2 as S, cmp
from PIL import Image
M = S.build_all()
B = M.blocks()
out = sys.argv[1] if len(sys.argv) > 1 else 'Sniper_vox_full_draft2.jpg'
views = [(0, 4, '앞'), (35, 8, '앞 3/4'), (90, 3, '옆'), (150, 12, '뒤 3/4'), (180, 6, '뒤')]
tiles = []
for y, p, lab in views:
    r, o = cmp.pair(B, ((-52, 52), (-48, 50), (-4, 272)), y, p, 2.3, None, lab)
    tiles.append((r, o))
W, H = tiles[0][0].size
s = Image.new('RGB', (W * len(tiles), H * 2), (13, 14, 17))
for i, (r, o) in enumerate(tiles):
    s.paste(r, (i * W, 0)); s.paste(o, (i * W, H))
s.save(out, quality=90); print(s.size)
