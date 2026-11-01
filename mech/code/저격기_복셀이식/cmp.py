"""cmp.py — 우리 복셀 모델과 Rodin 참고 메시를 같은 시점·같은 축척으로 나란히."""
import os as _os
_HERE = _os.path.dirname(_os.path.abspath(__file__))
import sys, numpy as np
sys.path[:0] = [_HERE]
from PIL import Image, ImageDraw, ImageFont
import vox_preview as vp
from rast import render
from view import vm
FONT = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 16, index=1)
_d = np.load(_os.path.join(_HERE, 'ref', 'ref_mesh.npz')); TRI, P, Z = _d['tri'].astype(float), _d['P'], _d['Z']
V = TRI.reshape(-1, 3); F = np.arange(len(V)).reshape(-1, 3)
RPAL = np.array([[205, 207, 212], [44, 46, 52], [40, 170, 100]], float)
NAMES = ["Pelvis", "Torso", "Head", "ShoulderPadL", "ShoulderPadR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
         "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR"]
BG = (128, 142, 160)   # 10-29 유저 "배경이 까매서 잘 안 보여" — 흰 판(226)·검은 판(40) 둘 다와 대비 나는 청회색
PAL = {1: (226, 228, 232), 2: (66, 70, 78), 3: (40, 43, 50), 4: (16, 17, 20), 5: (40, 160, 96), 6: (90, 255, 160), 7: (140, 146, 156), 8: (180, 184, 192)}


def window(box, yaw, pitch):
    R = vm(yaw, pitch)
    (x0, x1), (y0, y1), (z0, z1) = box
    c = np.array([[x, y, z] for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)], float) @ R.T
    return (c[:, 0].min(), c[:, 0].max()), (c[:, 1].min(), c[:, 1].max()), R


def pair(blocks, box, yaw, pitch=0, ppc=5.0, ref_parts=None, label=''):
    (u0, u1), (v0, v1), R = window(box, yaw, pitch)
    ours = vp.render(blocks, PAL, {6}, yaw=yaw, pitch=pitch, ppc=ppc, ss=2, size=((u0, u1), (v0, v1)), ao_amt=0.45, ground=False, bg=BG)
    W, H = ours.size
    sel = np.ones(len(P), bool) if ref_parts is None else np.isin(P, [NAMES.index(n) for n in ref_parts])
    cen = R.T @ np.array([(u0 + u1) / 2, (v0 + v1) / 2, 0])
    ref = render(V, F[sel], RPAL[Z[sel]], yaw, pitch, W=W, H=H, center=tuple(cen), span=(v1 - v0) * H / H, bg=BG)
    # rast span = 세로 범위(칸) — vox 이미지 높이와 맞춤
    ref = ref.resize((W, H))
    for im, t in ((ref, 'Rodin ' + label), (ours, '복셀 ' + label)):
        ImageDraw.Draw(im).text((6, 4), t, font=FONT, fill=(255, 235, 120), stroke_width=2, stroke_fill=(20, 22, 28))
    return ref, ours


def sheet(out, blocks, box, views, ppc=5.0, ref_parts=None, rows=1):
    tiles = []
    for yaw, pitch, lab in views:
        r, o = pair(blocks, box, yaw, pitch, ppc, ref_parts, lab)
        tiles += [r, o]
    W = max(t.width for t in tiles); H = max(t.height for t in tiles)
    n = len(tiles); cols = (n + rows - 1) // rows
    s = Image.new('RGB', (cols * W, rows * H), (0, 0, 0))
    for i, t in enumerate(tiles): s.paste(t, ((i % cols) * W, (i // cols) * H))
    s.save(out, quality=88); return s.size


def overlay(out, blocks, box, views, ppc=6.0, ref_parts=None):
    """참고(빨강 윤곽 느낌) 위에 우리 모델 반투명 — 차이를 한눈에."""
    tiles = []
    for yaw, pitch, lab in views:
        r, o = pair(blocks, box, yaw, pitch, ppc, ref_parts, lab)
        import numpy as np
        ra = np.asarray(r).astype(float); oa = np.asarray(o).astype(float)
        bl = 0.5 * ra + 0.5 * oa
        tiles += [r, o, Image.fromarray(bl.astype(np.uint8))]
    W = max(t.width for t in tiles); H = max(t.height for t in tiles)
    cols = 3; rows = (len(tiles) + 2) // 3
    s = Image.new('RGB', (cols * W, rows * H))
    for i, t in enumerate(tiles): s.paste(t, ((i % cols) * W, (i // cols) * H))
    s.save(out, quality=88); return s.size
