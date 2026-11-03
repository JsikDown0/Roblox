"""양산형 머리 r5 (2026-11-03) — 유저 "머리를 좀 더 각지게 구분. 원본 아트 보면 머리가 3면으로 나뉜 느낌".

[관찰: 메인 그림 확대] 이마·턱 = 가운데 앞면 + 양옆 비스듬한 면(3면) · 이마 처마 아래 끝은 가운데에서 곧은 가로 모서리,
옆 면에서 꺾여 내려감 · 정수리 판이 따로 얹혀 있고 양옆이 45° 로 깎임 · 턱 아래 끝은 곧음.
r2~r4 가 둥글게 보인 원인 [판단]: 앞 모서리를 0.7 기울기(약 35°)로 깎아 계단이 1·1·2 로 불규칙 → 면이 아니라 곡면처럼 읽힘.
이마 윗면도 그림 윤곽 그대로(0.6~0.74)라 정면에서 가로 줄무늬.

r5: 모양을 평면으로만 자름(스타일 가이드 1-4: 45° 또는 정수비).
  공통  옆 윤곽 = 그림(h2.SIDE)이되 이마 윗면은 정확히 2:3 평면(z 247.5 @ Y −15 → z 259.5 @ Y +3, 그림 Y +2.4 와 맞음)
        앞 3면 = 가운데 앞면 |X| ≤ 6(그림 x252~292) + 양옆 45° 면 · 뒤도 같은 3면(뒤 그림 가운데 판)
        바이저 홈·발광 = 면을 따라 각 기둥 앞면에서 3칸 파냄 · 하관 = a(매끈, 단차 없음) · 귀 모듈·손잡이 = r4 그대로
  A  3면(앞·뒤)만
  B  A + 정수리도 3면(위 평면 |X| ≤ 7 + 양옆 45° → 정면 윤곽이 팔각)
  C  B + 면 경계 1칸 단차(옆 면·정수리 옆 면을 1칸 뒤로 → 가운데 면이 한 장 덮은 판처럼)
  → A~C 렌더 [관찰]: 45° 옆 면은 계단의 앞·옆 칸면이 같은 밝기라 면으로 안 읽히고 윤곽만 깎인 둥근 덩어리.
     B 의 좁은 정수리는 오히려 돔(그림 정면은 위가 넓고 평평, x240~305). 그림 정면의 옆 면은 좁게 보이며 뒤로 많이 물러남.
  D  옆 면 가파르게 2:1(X 1칸당 뒤로 2칸 ≈ 63°) · 정수리 넓고 평평 + 3칸 45° 모서리 · 턱 = 아래 평평한 사다리꼴(1:2 로 좁아짐)
  E  D + 면 경계 1칸 단차
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import poly, cyl, box  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_head_r3 as h3  # noqa: E402

PAL = h2.PAL
NAMES = {"A": "A 3면(앞·뒤)", "B": "B 3면 + 정수리 팔각", "C": "C B + 면 경계 단차",
         "D": "D 가파른 3면(2:1)", "E": "E D + 면 경계 단차"}
# D·E 정면 껍데기(오른쪽 반, 칸): 위 평평 z259.5 · 3칸 45° 모서리 · 옆 |X| 11 · 턱 1:2 로 좁아져 아래 평평 z235
FRONT_D = [(0, 259.5), (8.5, 259.5), (11.5, 256.5), (11.5, 243), (7.5, 235), (0, 235)]
C_HALF = 6          # 가운데 앞면 반폭(그림 x252~292)
TOP_HALF = 7        # 정수리 위 평면 반폭
TOP_Z = 258


def _front_back(H):
    """기둥(x, z)마다 가장 앞/뒤 칸의 Y (없으면 nan)."""
    f = H.a > 0
    has = f.any(1)
    jf = np.where(has, f.argmax(1), -1)
    jb = np.where(has, f.shape[1] - 1 - f[:, ::-1, :].argmax(1), -1)
    y0 = H.lo[1]
    return np.where(has, jf + y0, np.nan), np.where(has, jb + y0, np.nan)


def build_head(M, var="B", parent="Torso", pivot_z=r1.NECK_Z):
    M.parts.pop("Head", None)
    H = M.part("Head", (-18, -18, 226), (19, 19, 266), pivot=(0, -3, pivot_z), parent=parent)
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    step = 1 if var in "CE" else 0
    fr = [(h2.FX(x), h2.FZ(y)) for x, y in h2.FRONT_R] if var in "ABC" else FRONT_D
    fr = fr + [(-a, b) for a, b in fr[::-1]]
    sd = [(h2.SY(x), h2.FZ(y)) for x, y in h2.SIDE]
    hull = poly(G, "y", fr) & poly(G, "x", sd)
    hull &= ~((Y < 3) & (Z > 247.5 + (Y + 15) * 2 / 3))                                     # 이마 윗면 2:3 평면
    H.add(hull, 1)
    # 앞·뒤 3면: 가운데 기둥(X=0)의 앞/뒤 Y 를 높이마다 기준으로, |X|>C_HALF 는 45° 로 물러남
    yf, yb = _front_back(H)
    i0 = -H.lo[0]
    yf0 = yf[i0][None, None, :]; yb0 = yb[i0][None, None, :]
    kf = 2 if var in "DE" else 1
    d = np.clip(ax - C_HALF, 0, None) + np.where(ax > C_HALF, step, 0)
    H.cut((Y < yf0 + kf * d) | (Y > yb0 - d))
    if var in "BC":                                                                           # 정수리 팔각
        dt = np.clip(ax - TOP_HALF, 0, None) + np.where(ax > TOP_HALF, step, 0)
        H.cut(Z > TOP_Z - dt + 0.5 - (0 if var == "B" else 0))
    neck = cyl(G, "z", (0, 3), 7, rng=(226, 236)) & ~(H.a > 0)
    H.add(neck, 3)
    # 바이저 홈: 처마(z≥247.5)와 턱(z≤243) 사이, 기둥마다 앞면에서 3칸 파냄 → 그 뒤 칸 = 짙은 벽, 가운데 띠 발광
    yf, _ = _front_back(H)
    YF = yf[:, None, :]
    top = 247.5 - np.clip(ax - 8, 0, None) * 1.0                                              # 양끝은 처마가 45° 로 감싸 내려옴
    zone = (ax <= 10.5) & (Z >= 243) & (Z <= top) & (Z <= 248)
    if var in "ABC":
        H.cut(zone & (Y < YF + 3))
        wall = zone & (Y >= YF + 3) & (Y <= YF + 3)
        H.add(wall, 3)
        zc = 245.0 + 1.3 * (X / 8.0) ** 2
        H.paint(wall & (ax <= 8) & (np.abs(Z - zc) <= 1.5), 6)
    else:
        # D·E: 그림의 발광은 가운데 면 폭(x250~297 ≈ |X| ≤ 7)뿐 → 홈은 가운데 면만 파고, 가파른 옆 면은 겉칠(짙은 띠)로만 이음
        #      (옆 면까지 파면 계단마다 벽이 엇갈려 이빨·점 발광이 보였음)
        cz = zone & (ax <= C_HALF + 1)
        H.cut(cz & (Y < YF + 3))
        wall = cz & (Y == YF + 3)
        H.add(wall, 3)
        zc = 245.0 + 1.3 * (X / 8.0) ** 2
        H.paint(wall & (ax <= C_HALF + 0.5) & (np.abs(Z - zc) <= 1.5), 6)
        H.paint_s(zone & (ax > C_HALF + 1) & (Y < 0), 3)
    # 정수리 손잡이(ㄷ) · 귀 모듈 — r4 그대로
    ztop = {"B": TOP_Z, "C": TOP_Z, "A": 259}.get(var, 260)
    for s in (1, -1):
        H.add(box(G, x=(min(2 * s, 4 * s), max(2 * s, 4 * s)), y=(-3, 4), z=(ztop, ztop + 2)), 3)
    H.add(box(G, x=(-4, 4), y=(-3, 4), z=(ztop + 3, ztop + 4)), 3)
    for s in (1, -1):
        lo_, hi_ = sorted((10 * s, 16 * s))
        H.add(cyl(G, "x", (1.5, 248.5), 5.6, rng=(lo_, hi_)), 3)
        H.groove(cyl(G, "x", (1.5, 248.5), 3.6) & ~cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 4)
        H.paint(cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 2)
    H.paint((Y >= 8) & (Z >= 241) & (Z <= 243), 3)                                           # 뒤 아래 테 그늘
    H.trim()
    return H


def build_all(var="B", ws=0.88):
    M = r1.build_all(ws)
    h2.lower_neck_well(M, ws)
    h3.collar_lip(M, ws)
    build_head(M, var)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    import mass_head_r4 as h4
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 0, "정면"), (-35, 6, "앞 3/4"), (-90, 0, "옆"), (150, 10, "뒤 3/4")]
    sel = sys.argv[2] if len(sys.argv) > 2 else "ADE"
    rows = [("r4 a (전)", h4.build_all("a"))] + [(NAMES[v], build_all(v)) for v in sel]
    rend = []
    for nm, M in rows:
        p = M.parts["Head"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Head", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = []
        for y, pt, _ in specs:
            im = vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=7, ss=2, ao_amt=0.5, bg=(132, 132, 132))
            ims.append(im.crop((int(im.width * 0.12), 0, int(im.width * 0.88), int(im.height * 0.42))))
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((205, 35, 345, 150)), "컨셉 정면"), (mn.crop((400, 45, 610, 230)), "컨셉 메인"),
            (con.crop((625, 30, 765, 145)), "컨셉 옆"), (con.crop((1180, 35, 1320, 150)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max([refs[i][0].width] + [ims[i].width for _, ims in rend]) for i in range(4)]
    W = 230 + sum(cols) + 16 * 5
    allrows = [("컨셉", [c for c, _ in refs])] + rend
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 16) + 30), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 머리 r5 — 3면(가운데 앞면 + 양옆 45°)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(allrows):
        y0 = 60 + r * (H + 16); x = 230
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            sh.paste(im, (x + (cols[i] - im.width) // 2, y0)); x += cols[i] + 16
    x = 230
    for i, t in enumerate(["정면", "앞 3/4", "옆", "뒤 3/4"]):
        d.text((x + 6, 60 + len(allrows) * (H + 16) + 2), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_머리r5_3면_%s.png" % sel); sh.save(p); print(p, sh.size)
