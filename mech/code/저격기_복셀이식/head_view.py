"""머리 확대 — Rodin / 복셀 (앞 · 앞3/4 · 옆 · 위3/4). 변형 함수를 넘기면 그 줄을 추가."""
import sys
sys.path.insert(0, '/home/claude/sniper')
import sniper_v2 as S, cmp
from PIL import Image, ImageDraw, ImageFont
FONT = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22, index=1)
box = ((-16, 16), (-34, 26), (224, 270))
views = [(0, 4, '앞'), (35, 10, '앞 3/4'), (90, 3, '옆'), (60, 30, '위 3/4')]

def rows_for(variants, ppc=9.0):
    rows = []
    for name, fn in variants:
        M = S.build_all()
        if fn: fn(M)
        B = M.blocks(); ref, ours = [], []
        for y, p, lab in views:
            r, o = cmp.pair(B, box, y, p, ppc, ["Head"], lab)
            ref.append(r); ours.append(o)
        if not rows: rows.append(("Rodin", ref))
        rows.append((name, ours))
    return rows

def save(rows, out):
    W = max(t.width for _, ts in rows for t in ts); H = max(t.height for _, ts in rows for t in ts)
    sheet = Image.new('RGB', (W * len(views) + 130, H * len(rows)), cmp.BG)
    d = ImageDraw.Draw(sheet)
    for i, (name, ts) in enumerate(rows):
        d.text((8, i * H + H // 2 - 12), name, font=FONT, fill=(255, 235, 120), stroke_width=2, stroke_fill=(20, 22, 28))
        for j, t in enumerate(ts): sheet.paste(t, (130 + j * W, i * H))
    sheet.save(out, quality=90); print(sheet.size)

if __name__ == '__main__':
    save(rows_for([("지금", None)]), sys.argv[1])
