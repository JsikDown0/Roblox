"""양산형 머리 r3 (2026-11-02) — r2 + 유저 "1번(판 이음매·면 분할) 진행, 입은 아예 지우자".

r2 와 다른 점:
- 입(턱 아래 짙은 환기구 + 가로 홈 2) 지움 → 턱은 매끈한 올리브 판.
- 판 나눔을 줄이 아니라 1칸 단차로(스타일 가이드 1-4):
  · 이마 가운데 판 = 아래로 넓어지는 사다리꼴(위 |X|≤5 → 아래 |X|≤6.5), 1칸 돋움(r2 는 직사각)
  · 이마 처마 아래 끝 1칸 더 앞으로(처마 두께) · 턱 윗입술(바이저 바로 밑 z241~243) 1칸 돋움 = 턱판이 따로 겹친 판
  · 옆 판(귀 둘레 아래, 정수리 판 아래) 1칸 안으로 → 정수리 판이 옆을 덮는 처마
  · 정수리 판 = 위 평면 가운데 1칸 돋움(손잡이 받침), 뒤통수 판은 r2 그대로
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

PAL = h2.PAL


def build_head(M, parent="Torso", pivot_z=r1.NECK_Z):
    M.parts.pop("Head", None)
    H = M.part("Head", (-18, -18, 226), (19, 19, 263), pivot=(0, -3, pivot_z), parent=parent)
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    fr = [(h2.FX(x), h2.FZ(y)) for x, y in h2.FRONT_R]
    fr = fr + [(-a, b) for a, b in fr[::-1]]
    sd = [(h2.SY(x), h2.FZ(y)) for x, y in h2.SIDE]
    hull = poly(G, "y", fr) & poly(G, "x", sd)
    H.add(hull, 1)
    H.cut((ax > 6) & (Y < -15 + (ax - 6) * 0.7))
    H.add(cyl(G, "z", (0, 3), 7, rng=(226, 236)) & ~hull, 3)                                 # 목(가늘고 뒤로 → 턱 밑에서 안 보이게)
    # 옆 판 1칸 안으로(정수리 판 아래 · 귀 둘레): 겉면 한 겹을 걷어냄
    side = (ax >= 9) & (Z >= 238) & (Z <= 252) & (Y >= -6)
    H.cut(side & H.surface())
    # 바이저 홈 + 발광(r2 와 같음)
    top = 247.5 - np.clip(ax - 8, 0, None) * 0.8
    zc = 245.0 + 1.3 * (X / 8.0) ** 2
    back = lambda: -10.5 + np.clip(ax - 6, 0, None) * 0.7
    H.cut((ax <= 10.5) & (Z >= 243) & (Z <= top) & (Y <= back()))
    wall = (ax <= 10.5) & (Z >= 243) & (Z <= top) & (np.abs(Y - (back() + 0.5)) <= 0.5)
    H.add(wall, 3)
    H.paint(wall & (ax <= 8) & (np.abs(Z - zc) <= 1.5), 6)
    # 처마 아래 끝 두께: 바이저 위 z248~249 앞으로 1칸
    H.emboss((ax <= 10) & (Z >= 248) & (Z <= 249) & (Y <= -12), 1)
    # 턱 윗입술: 바이저 바로 밑 1칸 돋움(턱판이 따로 겹친 판)
    H.emboss((ax <= 9) & (Z >= 241) & (Z <= 242.5) & (Y <= -10), 1)
    # 이마 가운데 판: 아래로 넓어지는 사다리꼴, 1칸 돋움
    H.emboss((ax <= 5 + (258 - Z) * 0.16) & (Z >= 250) & (Z <= 258) & (Y <= 6), 1)
    # 정수리 판 가운데 1칸 돋움(손잡이 받침) + 손잡이(ㄷ)
    H.emboss((ax <= 6) & (Y >= -4) & (Y <= 8) & (Z >= 257), 1)
    for s in (1, -1):
        H.add(box(G, x=(min(2 * s, 4 * s), max(2 * s, 4 * s)), y=(-3, 4), z=(258, 260)), 3)
    H.add(box(G, x=(-4, 4), y=(-3, 4), z=(261, 262)), 3)
    # 귀 모듈(r2 와 같음)
    for s in (1, -1):
        lo_, hi_ = sorted((10 * s, 16 * s))
        H.add(cyl(G, "x", (1.5, 248.5), 5.6, rng=(lo_, hi_)), 3)
        H.groove(cyl(G, "x", (1.5, 248.5), 3.6) & ~cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 4)
        H.paint(cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 2)
    # 뒤통수 돋운 판 + 아래 테 그늘(r2 와 같음)
    H.emboss((ax <= 6) & (Z >= 250) & (Z <= 257) & (Y >= 10), 1)
    H.paint((Y >= 8) & (Z >= 241) & (Z <= 243), 3)
    H.trim()
    return H


def collar_lip(M, ws):
    """입 지우기: 턱 밑 짙은 목 우물(정면에서 이빨처럼 보임)을 가슴 앞 올리브 깃(z≤233)으로 가림."""
    T = M.parts["Torso"]; G = T.g(); X, Y, Z = G
    hw = round(16 * ws)
    T.add((np.abs(X) <= hw) & (Y >= -20) & (Y <= -12) & (Z >= 226) & (Z <= 233), 1)


def build_all(ws=0.88):
    M = r1.build_all(ws)
    h2.lower_neck_well(M, ws)
    collar_lip(M, ws)
    build_head(M)
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
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 4, "정면"), (-35, 12, "앞 3/4"), (-90, 3, "옆"), (150, 12, "뒤 3/4")]
    rows = []
    for nm, M in (("r2", h2.build_all(0.88)), ("r3 (판 단차 + 입 지움)", build_all(0.88))):
        p = M.parts["Head"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Head", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = []
        for y, pt, _ in specs:
            im = vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=9, ss=2, ao_amt=0.5, bg=(132, 132, 132))
            ims.append(im.crop((0, 0, im.width, int(im.height * 0.5))))
        rows.append((nm, ims))
    H = max(i.height for _, ims in rows for i in ims)
    refs = [(con.crop((205, 35, 345, 150)), "컨셉 정면"), (con.crop((625, 30, 765, 145)), "컨셉 옆"),
            (mn.crop((380, 40, 620, 260)), "컨셉 메인"), (con.crop((1180, 35, 1320, 150)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    W = max(max(sum(i.width for i in ims) for _, ims in rows), sum(c.width for c, _ in refs)) + 16 * 6
    sh = Image.new("RGB", (W, 60 + 3 * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 머리 r3 — 판 단차 + 입 지움", fill=(235, 235, 235), font=ft)
    allrows = [("컨셉", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rows]
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 16
        for im, t in zip(ims, labs):
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f)
            x += im.width + 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
    p = os.path.join(out, "시안_머리r3_판단차.png"); sh.save(p); print(p, sh.size)
