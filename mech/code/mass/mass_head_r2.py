"""양산형 머리 r2 (2026-11-02) — 유저 "아트랑 괴리감이 심해" → 그림 윤곽으로 다시.

방법(APIS 교훈): 삼면도 정면·옆 머리 윤곽 다각형(원본 픽셀)의 교집합으로 모양 → 영역별로 칠·파내기.
그림 → 칸: 정면 X = (x − 273) × 0.295 · z = (925 − y) × 0.295 · 옆 Y = (x − 641) × 0.295 − 15 (앞 끝 = 이마 처마 끝).
[읽기] 정면: 머리 x222~324 · 꼭대기 y44(손잡이) · 턱 y130 · 바이저 x250~297 y86~93(가운데가 낮은 ∪) · 귀 모듈 x312~324 y66~100.
       옆: 이마 처마 끝 (641,86) → 윗면이 뒤로 비스듬히(약 35°) (700,45) · 바이저 홈 x652 y90~97 · 턱 앞 (646,100)~(648,112) ·
           턱 밑 (660,123) · 귀 원반 중심 (697,82) r≈13px.
       뒤: 가운데 돋운 판 x1228~1268 y50~78 · 아래 테 y≈92.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import poly, cyl, box, cbox  # noqa: E402
import mass_r1 as r1  # noqa: E402

K = 0.295
FX = lambda x: (x - 273) * K
FZ = lambda y: (925 - y) * K
SY = lambda x: (x - 641) * K - 15
# [실측] 메인 그림 중간 밝기 평균: 헬멧 (95,89,75) · 가슴 (110,109,92) · 허벅지 (104,103,89) → r1 올리브(104,110,74)는 너무 초록
PAL = dict(r1.PAL); PAL[1] = (102, 103, 82)
# 정면 오른쪽 반(대칭) — (x, y) 원본 픽셀
# 껍데기만(귀 모듈 x312~324 는 따로 원통) — 위 평평 · 45° 깎은 어깨 · 아래로 좁아지는 턱
FRONT_R = [(273, 47), (287, 48), (304, 52), (311, 60), (312, 100), (309, 106), (305, 118), (295, 128), (273, 131)]
# 옆(앞 = 왼쪽) — 바이저 홈은 파내기로 따로
SIDE = [(641, 86), (668, 66), (700, 46), (735, 46), (746, 60), (749, 88), (741, 101), (722, 116), (700, 121), (662, 124),
        (649, 113), (645, 100), (646, 94)]


def build_head(M, parent="Torso", pivot_z=r1.NECK_Z):
    M.parts.pop("Head", None)
    H = M.part("Head", (-18, -17, 226), (19, 19, 262), pivot=(0, -3, pivot_z), parent=parent)
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    fr = [(FX(x), FZ(y)) for x, y in FRONT_R]
    fr = fr + [(-a, b) for a, b in fr[::-1]]
    sd = [(SY(x), FZ(y)) for x, y in SIDE]
    hull = poly(G, "y", fr) & poly(G, "x", sd)
    H.add(hull, 1)
    # 앞 모서리 깎기(정면에서 이마·턱이 가운데 평면 + 비스듬한 옆 면으로 보이게): |X|>6 에서 X 1칸당 0.7칸 뒤로
    H.cut((ax > 6) & (Y < -15 + (ax - 6) * 0.7))
    H.add(cyl(G, "z", (0, 1), 10, rng=(226, 236)) & ~hull, 3)                                 # 목
    # 바이저 홈: 이마 처마(z≥246.3)와 턱(z≤244) 사이, 앞에서 Y −11 까지 파냄 → 뒷벽 짙은 + 휜 발광 띠
    # 홈 = 가운데 높이 z243~247.5, 양끝(|X|>8)은 이마 처마가 아래로 감싸며 좁아짐 · 발광 띠 3칸 굵기, 가운데가 낮은 ∪
    top = 247.5 - np.clip(ax - 8, 0, None) * 0.8
    zc = 245.0 + 1.3 * (X / 8.0) ** 2
    slot = (ax <= 10.5) & (Z >= 243) & (Z <= top) & (Y <= -10.5 + np.clip(ax - 6, 0, None) * 0.7)
    H.cut(slot)
    wall = (ax <= 10.5) & (Z >= 243) & (Z <= top) & (np.abs(Y - (-10 + np.clip(ax - 6, 0, None) * 0.7)) <= 0.5)
    H.add(wall, 3)
    H.paint(wall & (ax <= 8) & (np.abs(Z - zc) <= 1.5), 6)
    # 이마 가운데 판: 1칸 돋움(윗면·앞면), 옆 면은 그대로 → 깎은 투구 면
    fore = (ax <= 5) & (Z >= 249) & (Z <= 258) & (Y <= 6)
    H.emboss(fore, 1)
    # 정수리 손잡이(ㄷ, 짙은): 기둥 2 + 위 막대(2칸 굵기, 절반 해상도에서 남게)
    for s in (1, -1):
        H.add(box(G, x=(min(2 * s, 4 * s), max(2 * s, 4 * s)), y=(-3, 4), z=(257, 259)), 3)
    H.add(box(G, x=(-4, 4), y=(-3, 4), z=(260, 261)), 3)
    # 귀 모듈(정면에서 가장 넓은 곳 x312~324 → |X| 10~15.5): 짙은 원통 + 바깥 테 + 가운데 원반(강철) 2칸 오목
    for s in (1, -1):
        lo_, hi_ = sorted((10 * s, 16 * s))
        H.add(cyl(G, "x", (1.5, 248.5), 5.6, rng=(lo_, hi_)), 3)
        H.groove(cyl(G, "x", (1.5, 248.5), 3.6) & ~cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 4)
        H.paint(cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 2)
    # 턱 아래 가운데 짙은 환기구 + 가로 홈 2
    H.paint((ax <= 4) & (Z >= 236) & (Z <= 240) & (Y <= -9), 3)
    for z in (237, 239):
        H.groove((ax <= 3) & (Z == z) & (Y <= -9), 4)
    # 뒤통수 가운데 돋운 판 + 아래 테 그늘
    H.emboss((ax <= 6) & (Z >= 250) & (Z <= 257) & (Y >= 10), 1)
    H.paint((Y >= 8) & (Z >= 241) & (Z <= 243), 3)
    H.trim()
    return H


def lower_neck_well(M, ws):
    """그림(메인): 가슴 위 가운데(고리 사이) 모서리가 턱보다 낮음(y≈140 → z≈230) → 목 우물을 z231 까지 낮춤."""
    T = M.parts["Torso"]; G = T.g(); X, Y, Z = G
    hw = round(16 * ws) if ws < 1 else 16
    T.cut((np.abs(X) <= hw) & (Y <= 10) & (Z >= 231))
    T.add(cbox(G, (-hw, hw), (-12, 10), (226, 230), {"xy": 4}), 3)


def build_all(ws=0.88):
    M = r1.build_all(ws)
    lower_neck_well(M, ws)
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
    for nm, M, pal in (("r1 (지금)", r1.build_all(0.88), r1.PAL), ("r2 (그림 윤곽 + 그림에서 잰 회올리브)", build_all(0.88), PAL)):
        p = M.parts["Head"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Head", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = []
        for y, pt, _ in specs:
            im = vp.render(M.blocks(), pal, r1.EMISSIVE, yaw=y, pitch=pt, ppc=9, ss=2, ao_amt=0.5, bg=(132, 132, 132))
            ims.append(im.crop((0, 0, im.width, int(im.height * 0.5))))
        rows.append((nm, ims))
    H = max(i.height for _, ims in rows for i in ims)
    refs = [(con.crop((205, 35, 345, 150)), "컨셉 정면"), (con.crop((625, 30, 765, 145)), "컨셉 옆"),
            (mn.crop((380, 40, 620, 260)), "컨셉 메인"), (con.crop((1180, 35, 1320, 150)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    W = max(sum(i.width for i in ims) for _, ims in rows) + 16 * 6
    W = max(W, sum(c.width for c, _ in refs) + 16 * 5)
    sh = Image.new("RGB", (W, 60 + 3 * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 머리 r2 — 그림 윤곽(정면 ∩ 옆)으로 다시", fill=(235, 235, 235), font=ft)
    allrows = [("컨셉", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rows]
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 16
        for im, t in zip(ims, labs):
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f)
            x += im.width + 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
    p = os.path.join(out, "시안_머리r2_윤곽.png"); sh.save(p); print(p, sh.size)
