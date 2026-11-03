"""양산형 어깨 r1 (2026-11-03) — 윤곽 읽기 r2 답 [결정 11-03 "모두 동의"]:
  ① 왼 어깨 방패판(S2) = 바깥을 향하되 앞으로 30° 돌림 ② 판 + 짙은 받침대만(따로 어깨 장갑 없음)
  ③ 판은 ShoulderL 파트(팔 들면 같이) ④ 어깨는 ×1.0(몸 폭 0.88 과 따로).
그림 → 칸(삼면도): 정면 X = (x − 273) × 0.295 · z = (925 − y) × 0.295 · 뒤 X = (1247 − x) × 0.295.
[실측 읽기]
  S3 관절 원통: 정면 x172·372 → |X| ≈ 30, 중심 y170 → z223, 세로 반지름 38px → 11칸.
  S1 오른 어깨 장갑(정면 육각): (105,102) (175,105) (181,160) (162,196) (86,191) (82,130) → X −56 ~ −27, z 215 ~ 243.
      위 평평 · 안쪽 아래 1:2 깎음 · 바깥 위 45° 깎음. 깊이(앞뒤)는 그림에 없음 → Y −15 ~ 15 [판단] + 앞·뒤 모서리 45° 3칸(3면 문법).
  S2 왼 방패판(옆 육각): (700,56) (746,47) (800,60) (806,190) (786,240) (722,246) (694,182)
      → 길이 33칸 · z 200 ~ 259(높이 59) · 위가 살짝 박공 · 뒤 아래·앞 아래 깎음. 판 가운데 = 정면 x455 → X ≈ 52.
      두께 4 + 바깥 면 2칸 안쪽 판 1칸 돋움(2단 판, 테두리 줄 대신 단차). 색 2(짙은 쇠 회색).
  S4 받침대: 관절과 판 안쪽을 잇는 짙은 상자 + 아래 버팀대.
  A  판 30°(결정)   B  판 45°(비교용)
  1차 렌더 [관찰]: 판이 얇고 몸에서 떨어진 문짝처럼 보임. 그림 실측과 다시 대 봄 — 판이 정면에서 x394~516(X 36~72, 36칸),
  옆에서 33칸, 뒤에서도 넓게 보임 → 평평한 판 하나로 세 그림을 다 맞추려면 약 45° · 길이 약 46칸 [판단].
  → A = 30° · 길이 33(읽은 그대로) · 두께 4 / B = 45° · 길이 46(세 그림에 맞춘 값) · 두께 5 · 모서리 깎음. 둘 다 판 안쪽 끝을 관절(X 36)에 붙임.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, poly, slab  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_chest_r4 as c4  # noqa: E402

PAL = h2.PAL
K = 0.295
FX = lambda x: (x - 273) * K
FZ = lambda y: (925 - y) * K
SH = (31, -1, 223)                                                       # 어깨 관절(왼쪽 +X), 오른쪽은 거울
S1_FRONT = [(105, 102), (175, 105), (181, 160), (162, 196), (86, 191), (82, 130)]
S2_SIDE = [(700, 56), (746, 47), (800, 60), (806, 190), (786, 240), (722, 246), (694, 182)]
NAMES = {30: "A 30° · 길이 33", 45: "B 45° · 길이 46(그림 맞춤)"}
PLATE = {30: dict(L=1.0, h=(-2, 1)), 45: dict(L=1.4, h=(-2, 2))}


def joint(P, s):
    """S3 관절 원통(짙은) + 고리 홈."""
    G = P.g(); X, Y, Z = G; ax = s * X
    P.add(cyl(G, "x", (SH[1], SH[2]), 11, rng=sorted((s * 28, s * 35))), 3)
    for x0 in (30, 33):
        P.groove(cyl(G, "x", (SH[1], SH[2]), 11.5) & ~cyl(G, "x", (SH[1], SH[2]), 10) & (ax == x0), 4)
    P.paint(cyl(G, "x", (SH[1], SH[2]), 4) & (ax >= 35), 2)


def build_shoulders(M, ang=30):
    # ---- 오른쪽(−X) S1 장갑 + 관절
    R = M.part("ShoulderR", (-62, -22, 196), (-24, 22, 250), pivot=(-SH[0], SH[1], SH[2]), parent="Torso")
    G = R.g(); X, Y, Z = G
    fr = [(FX(x), FZ(y)) for x, y in S1_FRONT]
    pad = poly(G, "y", fr) & box(G, y=(-15, 15))
    pad &= (np.abs(Y) <= 15 - np.clip(Z - 240, 0, None))                 # 위 앞·뒤 모서리 45° 3칸
    pad &= (np.abs(Y) <= 15 - np.clip(-X - 53, 0, None))                 # 바깥 앞·뒤 세로 모서리 45° 3칸
    R.add(pad, 1)
    R.emboss((Z >= 236) & (np.abs(Y) <= 11) & (X >= -50) & (X <= -31), 1)                   # 윗면 덧판 1칸
    joint(R, -1)
    R.trim()
    # ---- 왼쪽(+X) S2 방패판 + 받침대 + 관절
    L = M.part("ShoulderL", (24, -48, 192), (80, 48, 266), pivot=SH, parent="Torso")
    G = L.g(); X, Y, Z = G
    th = np.radians(ang)
    n = np.array((np.cos(th), -np.sin(th), 0.0))                         # 판 바깥 방향(앞쪽으로 ang° 돌림)
    e1 = np.array((np.sin(th), np.cos(th), 0.0))                         # 판 길이 방향(앞 → 뒤)
    zc, yc = 229.5, -1.0
    pl = PLATE[ang]
    pts = [((x - 750) * K * pl["L"], FZ(y) - zc) for x, y in S2_SIDE]   # 옆 그림 가운데 x≈750 → u=0, 길이 배율
    half = max(abs(p[0]) for p in pts)
    o = np.array((36.0 + half * np.sin(th) + 3, yc, zc))                 # 판 안쪽 끝이 관절(X 36) 바로 바깥
    L.add(slab(G, o, e1, (0, 0, 1), pts, h=pl["h"]), 2)
    inner = []
    cx = np.mean([p[0] for p in pts]); cz = np.mean([p[1] for p in pts])
    for u, v in pts:                                                     # 2칸 안쪽 판(바깥 면 1칸 돋움)
        d = np.hypot(u - cx, v - cz); inner.append((u - (u - cx) * 3.0 / d, v - (v - cz) * 3.0 / d))
    L.add(slab(G, o, e1, (0, 0, 1), inner, h=(pl["h"][1] + 1, pl["h"][1] + 1)), 2)
    # 받침대: 관절 바깥(X 35)에서 판 안쪽까지 짙은 상자 + 아래 버팀대
    pin = o - n * 3
    L.add(box(G, x=(34, round(pin[0])), y=(-6, 5), z=(219, 233)), 3)
    L.add(r1.seg(G, (36, 0, 214), (pin[0], pin[1], 212), 2.2), 3)
    joint(L, 1)
    L.trim()
    return M


def build_all(ang=30, ws=0.88):
    M = c4.build_all("a", ws)
    build_shoulders(M, ang)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    Rr = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(Rr, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(Rr, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 2, "정면"), (-35, 8, "앞 3/4 (오른쪽)"), (35, 8, "앞 3/4 (왼쪽 판)"), (90, 2, "옆(왼쪽)"), (180, 2, "뒤")]
    rows = [(NAMES[a], build_all(a)) for a in (30, 45)]
    rend = []
    for nm, M in rows:
        for pn in ("ShoulderL", "ShoulderR"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=3.6, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((20, 20, 570, 330)), "컨셉 정면"), (mn.crop((150, 40, 990, 600)), "컨셉 메인"),
            (con.crop((600, 20, 920, 330)), "컨셉 옆"), (con.crop((980, 20, 1500, 330)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(200 + sum(cols) + 16 * 6, 200 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 어깨 r1 — 오른 장갑(S1) · 왼 방패판(S2, 짙은 쇠) · 관절 원통 · 어깨 ×1.0 (팔은 다음 단계)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 200
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_어깨r1.png"); sh.save(p); print(p, sh.size)
