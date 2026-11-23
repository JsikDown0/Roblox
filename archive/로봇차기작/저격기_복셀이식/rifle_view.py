"""저격총 r1 보기: 1줄 = 컨셉 + 라이플 혼자(옆 · 3/4 · 위 · 총구) / 2줄 = 기체가 쥠(조준 3/4 · 조준 옆 · 낮춰 듦 3/4 · 낮춰 듦 옆)."""
import sys, time, numpy as np
sys.path.insert(0, '/home/claude/sniper')
from PIL import Image, ImageDraw, ImageFont
import sniper_v2 as S, sniper_rifle as R, vox_preview as vp
from view import vm
FONT = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 18, index=1)
BG = (128, 142, 160)


def win(lo, hi, yaw, pitch):
    Rm = vm(yaw, pitch)
    c = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])], float) @ Rm.T
    return (c[:, 0].min(), c[:, 0].max()), (c[:, 1].min(), c[:, 1].max())


def tile(B, yaw, pitch, ppc, lo, hi, label):
    im = vp.render(B, S.PAL, {6}, yaw=yaw, pitch=pitch, ppc=ppc, ss=2, size=win(lo, hi, yaw, pitch), ao_amt=0.45, ground=False, bg=BG)
    ImageDraw.Draw(im).text((6, 4), label, font=FONT, fill=(255, 235, 120), stroke_width=2, stroke_fill=(20, 22, 28))
    return im


def row(ims, h):
    ims = [im.resize((max(1, int(im.width * h / im.height)), h)) for im in ims]
    out = Image.new('RGB', (sum(i.width for i in ims), h), BG); x = 0
    for i in ims: out.paste(i, (x, 0)); x += i.width
    return out


if __name__ == '__main__':
    t0 = time.time()
    out = sys.argv[1]; concept = sys.argv[2] if len(sys.argv) > 2 else None
    Mr = R.rifle_only(); Br = Mr.blocks()
    p = Mr.parts["SniperRifle"]; idx = np.argwhere(p.a > 0) + p.lo; lo, hi = idx.min(0) - 2, idx.max(0) + 3
    side = tile(Br, 270, 2, 5.0, lo, hi, '라이플 옆')
    r1 = [Image.open(concept).convert('RGB')] if concept else []
    r1.append(side)
    r2 = [tile(Br, 300, 18, 4.0, lo, hi, '3/4'), tile(Br, 240, 14, 4.0, lo, hi, '반대 3/4'), tile(Br, 0, 4, 9.0, lo, hi, '총구'), tile(Br, 180, 4, 9.0, lo, hi, '개머리 끝')]
    print('rifle', round(time.time() - t0, 1), flush=True)
    M = R.build_all()
    blo, bhi = np.array([-60, -200, -4]), np.array([60, 60, 272])
    r3 = []
    for pose, lab in ((R.AIM, '조준'), (R.LOW, '낮춰 듦')):
        B = M.blocks(pose=pose)
        r3 += [tile(B, 325, 6, 2.0, blo, bhi, lab + ' 3/4'), tile(B, 270, 3, 2.0, blo, bhi, lab + ' 옆')]
        print(lab, round(time.time() - t0, 1), flush=True)
    rows = [row(r1, 420), row(r2, 420), row(r3, 620)]
    W = max(r.width for r in rows)
    rows = [r.resize((W, int(r.height * W / r.width))) if r.width > W else r for r in rows]
    sheet = Image.new('RGB', (W, sum(r.height for r in rows)), BG); y = 0
    for r in rows: sheet.paste(r, (0, y)); y += r.height
    sheet.save(out, quality=90); print(sheet.size, 'done', round(time.time() - t0, 1))
