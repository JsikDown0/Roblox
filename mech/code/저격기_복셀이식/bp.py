"""bp.py — 설계도 렌더: 참고 메시(칸 좌표)를 직교로 그리고 칸 격자·눈금을 덮음.
python3 bp.py OUT x0:x1 y0:y1 z0:z1 views(0,90,180,-90) [ppc] [parts]"""
import os as _os
_HERE = _os.path.dirname(_os.path.abspath(__file__))
import sys, numpy as np
sys.path[:0] = [_HERE]
from rast import render
from view import vm
from PIL import Image, ImageDraw, ImageFont
FONT = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 13, index=1)
PAL = np.array([[205, 207, 212], [52, 54, 60], [40, 170, 100]], float)
NAMES = ["Pelvis", "Torso", "Head", "ShoulderPadL", "ShoulderPadR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
         "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR"]
_d = np.load(_os.path.join(_HERE, 'ref', 'ref_mesh.npz')); TRI, P, Z = _d['tri'].astype(float), _d['P'], _d['Z']
V = TRI.reshape(-1, 3); F = np.arange(len(V)).reshape(-1, 3)


def view(box, az, ppc=6.0, parts=None, tint=None, el=0, grid=(5, 10)):
    (x0, x1), (y0, y1), (z0, z1) = box
    sel = np.ones(len(P), bool) if parts is None else np.isin(P, [NAMES.index(p) for p in parts])
    c = TRI[sel].reshape(-1, 3).mean(0) if False else None
    R = vm(az, el)
    corners = np.array([[x, y, z] for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)], float) @ R.T
    ux0, ux1 = corners[:, 0].min(), corners[:, 0].max(); uy0, uy1 = corners[:, 1].min(), corners[:, 1].max()
    W, H = int((ux1 - ux0) * ppc), int((uy1 - uy0) * ppc)
    cen = R.T @ np.array([(ux0 + ux1) / 2, (uy0 + uy1) / 2, 0])
    col = PAL[Z[sel]].copy()
    if tint is not None: col = tint(col, sel)
    im = render(V, F[sel], col, az, el, W=W, H=H, center=tuple(cen), span=H / ppc, bg=(14, 15, 18))
    d = ImageDraw.Draw(im)
    def sx(u): return (u - ux0) * ppc
    def sy(v): return (uy1 - v) * ppc
    lab = {0: 'X', 180: 'X', 90: 'Y', -90: 'Y'}.get(az, 'u')
    for g in range(int(np.floor(ux0)), int(np.ceil(ux1)) + 1):
        if g % grid[0]: continue
        strong = g % grid[1] == 0
        d.line([(sx(g), 0), (sx(g), H)], fill=(255, 255, 255, 0) if False else ((120, 120, 140) if strong else (60, 60, 72)), width=1)
        if strong: d.text((sx(g) + 2, H - 16), f'{g}', font=FONT, fill=(255, 220, 120))
    for g in range(int(np.floor(uy0)), int(np.ceil(uy1)) + 1):
        if g % grid[0]: continue
        strong = g % grid[1] == 0
        d.line([(0, sy(g)), (W, sy(g))], fill=(120, 120, 140) if strong else (60, 60, 72), width=1)
        if strong: d.text((2, sy(g) - 15), f'{g}', font=FONT, fill=(255, 220, 120))
    name = {0: '앞(화면 오른쪽 = +X 기체 왼쪽)', 180: '뒤', 90: '왼옆(화면 오른쪽 = +Y 뒤)', -90: '오른옆'}.get(az, str(az))
    d.text((W // 2 - 60, 2), f'{name}', font=FONT, fill=(150, 230, 255))
    # 격자선은 메시 위에 반투명으로: 다시 메시를 0.65 섞어 덮음
    return im


def sheet(out, box, views, ppc=6.0, parts=None):
    ims = [view(box, a, ppc, parts) for a in views]
    W = sum(i.width for i in ims) + 8 * (len(ims) - 1); H = max(i.height for i in ims)
    s = Image.new('RGB', (W, H), (0, 0, 0)); x = 0
    for i in ims: s.paste(i, (x, 0)); x += i.width + 8
    s.save(out, quality=90); return s.size


if __name__ == "__main__":
    out = sys.argv[1]
    box = [tuple(map(float, a.split(':'))) for a in sys.argv[2:5]]
    views = [int(v) for v in sys.argv[5].split(',')]
    ppc = float(sys.argv[6]) if len(sys.argv) > 6 else 6.0
    parts = sys.argv[7].split(',') if len(sys.argv) > 7 else None
    print(sheet(out, box, views, ppc, parts))
