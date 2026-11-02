"""양산형 r1 — 머리·가슴(+등·허리) (2026-11-02)

윤곽 읽기: mech/docs/레퍼런스/양산형/윤곽읽기_r1_부품지도.png · 결정기록 8절.
그림 → 칸: X = (x − 273) × 0.295 · z = (925 − y) × 0.295 (삼면도 정면, 머리 꼭대기 y44 → z260).
뒤: X = (1247 − x) × 0.295 (뒤 그림 왼쪽 = 기체 왼쪽 +X).
답 [결정 11-02]: 체형 폭 ×0.88(키·두께 그대로, 머리는 그대로) · 줄무늬·리벳·문자 없음(데칼 자리만 평평) · 발광 = 바이저만 ·
                 등 둥근 노즐 2 그대로 · 무장·크레인·어깨판 뒤 원통 뺌(어깨 방패판은 남김 — 어깨 단계).
색: 1 올리브(주장갑) · 2 짙은 쇠 회색 판 · 3 짙은 프레임 · 4 검정 · 5 노랑(피스톤 띠) · 6 주황 발광 · 7 강철.
쓰기: python3 mass_r1.py <출력폴더>
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cbox, cyl, box  # noqa: E402

PAL = {1: (104, 110, 74), 2: (88, 90, 90), 3: (52, 54, 56), 4: (20, 21, 23), 5: (206, 168, 46),
       6: (255, 168, 60), 7: (150, 152, 150)}
EMISSIVE = {6}
NECK_Z = 233


def seg(G, a, b, r):
    """a→b 선분 둘레 반지름 r 막대(비스듬한 피스톤)."""
    X, Y, Z = G
    a = np.asarray(a, float); b = np.asarray(b, float); d = b - a; L2 = d @ d
    t = np.clip(((X - a[0]) * d[0] + (Y - a[1]) * d[1] + (Z - a[2]) * d[2]) / L2, 0, 1)
    return (X - a[0] - t * d[0]) ** 2 + (Y - a[1] - t * d[1]) ** 2 + (Z - a[2] - t * d[2]) ** 2 <= r * r + 0.25


def rng(a, b, s=1.0):
    """X 범위를 폭 배율 s 로."""
    return (round(a * s), round(b * s))


def build_torso(M, ws):
    T = M.part("Torso", (-40, -30, 165), (41, 42, 250), pivot=(0, 0, 190))
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    w = round(29 * ws)
    # 가슴통: 위 앞면은 수직(z214~243), 아래 띠(z197~214)는 뒤로 비스듬 + 아래 옆 모서리 크게 깎음 = 처마
    chest = cbox(G, (-w, w), (-20, 16), (197, 243), {"-y-z": (4, 5), "-zx": (round(10 * ws), 17),
                                                      "+z-y": 2, "+zx": 2, "+zy": 3, "+yx": 4})
    T.add(chest, 1)
    T.cut(box(G, y=(-20, -20), z=(197, 213)))                                                # 아래 띠 1칸 뒤로(위 판이 덮는 단차)
    # 앞 흉판: 옆 판보다 1칸 돋운 큰 판(위 z214~241, 옆 끝 3칸 안쪽) — 테두리 줄 대신 단차
    T.add(box(G, x=(-w + 3, w - 3), y=(-21, -21), z=(215, 240)) & ~box(G, x=(-15, 15), z=(232, 250)), 1)
    T.add(box(G, x=(-w + 3, w - 3), y=(-21, -21), z=(214, 214)), 3)                         # 처마 밑 그늘
    # 목 우물: 어깨 쪽 위 모서리(z243)만 남기고 가운데를 낮춤(머리가 반쯤 묻힘)
    T.cut(box(G, x=(-15, 15), y=(-21, 10), z=(233, 250)))
    T.add(cbox(G, (-15, 15), (-12, 10), (228, 233), {"xy": 4}), 3)                          # 목 받침(짙은)
    # 위 앞 모서리 고리 2(강철, 앞을 향함) + 받침
    for s in (1, -1):
        xc = s * round(19 * ws)
        T.add(cbox(G, (xc - 4, xc + 4), (-22, -18), (231, 236), {"-yz": 1}), 3)
        ring = cyl(G, "y", (xc, 236), 3.8, rng=(-23, -22)) & ~cyl(G, "y", (xc, 236), 1.8)
        T.add(ring & (Z >= 233), 2)
    # 겨드랑이 짙은 프레임 + 어깨 관절 축(어깨 단계에서 덮음)
    T.add(cbox(G, (-w - 3, w + 3), (-12, 10), (210, 236), {"xz": 4}), 3)
    T.add(cyl(G, "x", (-1, 226), 8, rng=(-w - 7, w + 7)), 3)
    # 허리: 짙은 프레임(마디 홈) + 피스톤 4(강철, 노랑 띠) + 검정 호스 2
    T.add(cbox(G, (-14, 14), (-11, 10), (172, 198), {"xy": 3}), 3)
    for z in (178, 184, 190):
        T.groove(box(G, x=(-14, 14), y=(-12, -10), z=(z, z)), 4)
    for s in (1, -1):
        for xt, xb, yc in ((s * 20, s * 13, -6), (s * 11, s * 7, -10)):                       # 위 바깥 → 아래 안쪽
            xt, xb = round(xt * ws), round(xb * ws)
            T.add(seg(G, (xb, yc, 174), (xt, yc, 199), 2.0), 7)                                 # 로드
            xm = xb + (xt - xb) * 0.55
            T.add(seg(G, (xm, yc, 188), (xt, yc, 199), 3.0), 3)                                 # 실린더
            T.add(seg(G, (xm, yc, 188), (xm + (xt - xb) * 0.04, yc, 189), 3.3), 5)              # 노랑 띠(얇게)
        T.add(seg(G, (s * round(24 * ws), -2, 199), (s * round(18 * ws), -4, 176), 2.4), 4)     # 검정 호스(바깥)
    # ---- 등 상자(O): 가슴보다 좁지 않게, 뒤로 12칸
    wb = round(27 * ws)
    back = cbox(G, (-wb, wb), (14, 28), (196, 245), {"+y+z": 4, "+yx": 4, "-zx": 3})
    T.add(back, 3)
    T.paint(back & (Y >= 25) & (Z >= 216), 1)                                                # 등 윗판 = 올리브
    T.paint(back & (ax >= wb - 2) & (Z >= 216), 1)
    # 통풍 격자 3: 양옆 세로(X ±17~24) + 가운데 가로(X ±8)
    for s in (1, -1):
        x0, x1 = sorted((s * round(16 * ws), s * round(23 * ws)))
        T.cut(box(G, x=(x0, x1), y=(27, 29), z=(224, 240)))
        T.add(box(G, x=(x0, x1), y=(26, 26), z=(224, 240)), 4)
        for z in range(225, 240, 3):
            T.add(box(G, x=(x0, x1), y=(27, 27), z=(z, z)), 3)
    T.cut(box(G, x=(-8, 8), y=(27, 29), z=(235, 241)))
    T.add(box(G, x=(-8, 8), y=(26, 26), z=(235, 241)), 4)
    for z in (236, 238, 240):
        T.add(box(G, x=(-8, 8), y=(27, 27), z=(z, z)), 3)
    # 둥근 노즐 2(그대로, 발광 없음): 짙은 쇠 테 + 검정 속
    for s in (1, -1):
        xc = s * round(15.6 * ws)
        T.add(cyl(G, "y", (xc, 208), 10, rng=(28, 34)), 2)
        T.add(cyl(G, "y", (xc, 208), 11, rng=(28, 29)), 3)
        T.cut(cyl(G, "y", (xc, 208), 7.5, rng=(30, 35)))
        T.add(cyl(G, "y", (xc, 208), 7.5, rng=(30, 30)), 4)
    T.add(cbox(G, (-4, 4), (28, 31), (197, 230), {"+yx": 1}), 3)                            # 노즐 사이 기둥
    # 척추 마디(O3)
    for z0 in range(171, 196, 5):
        T.add(cbox(G, (-6, 6), (6, 15), (z0, z0 + 3), {"+yx": 2}), 3)
    T.trim()
    return T


def build_head(M):
    H = M.part("Head", (-18, -22, 226), (19, 18, 262), pivot=(0, -3, NECK_Z), parent="Torso")
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    H.add(cyl(G, "z", (0, -2), 10, rng=(226, 236)), 3)                                       # 목 고리
    # 헬멧: 각진 투구(폭 29 · 깊이 28), 위로 좁아짐
    dome = cbox(G, (-14, 14), (-15, 13), (234, 256), {"+zx": 5, "+zy": 5, "-yx": 4, "-zy": 2, "+yx": 3})
    H.add(dome, 1)
    # 정수리 능선판(A2)
    H.add(cbox(G, (-4, 4), (-12, 9), (256, 259), {"+zx": 1, "-y+z": 2}), 1)
    # 얼굴: 이마 처마(z247~256) 아래 바이저 띠 1칸 오목 발광 → 짙은 얼굴판 + 앞으로 나온 턱
    zc = 245.5 - 0.035 * X ** 2
    H.cut(box(G, x=(-7, 7), y=(-16, -14), z=(241, 247)) & (Z >= zc - 2) & (Z <= zc + 1.5))
    H.add(box(G, x=(-7, 7), y=(-14, -14), z=(241, 247)) & (Z >= zc - 2) & (Z <= zc + 1.5), 6)
    face = box(G, x=(-10, 10), y=(-16, -13), z=(234, 242))
    H.paint(face, 3)
    for xv in (-4, 0, 4):
        H.groove(box(G, x=(xv, xv), y=(-16, -14), z=(236, 240)), 4)                           # 얼굴판 세로 홈
    H.add(cbox(G, (-6, 6), (-19, -10), (231, 237), {"-yz": 2, "-yx": 2}), 2)                  # 턱
    # 귀 블록(짙은)
    for s in (1, -1):
        H.add(cbox(G, (min(s * 13, s * 17), max(s * 13, s * 17)), (-7, 6), (236, 250), {"xz": 2, "xy": 2}), 3)
    H.trim()
    return H


def build_all(ws=0.88):
    M = fv.Model()
    build_torso(M, ws)
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
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형", "concept_v1_삼면도.png")).convert("RGB")
    rows = []
    for ws, nm in ((1.0, "폭 ×1.0(그림 그대로)"), (0.88, "폭 ×0.88(기본안)")):
        M = build_all(ws)
        for n, p in M.parts.items():
            _, k = ndimage.label(p.a > 0)
            print(nm, n, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        B = M.blocks()
        specs = [(0, 4, "정면"), (-35, 10, "앞 3/4"), (-90, 3, "옆"), (145, 10, "뒤 3/4"), (180, 4, "뒤")]
        ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=5, ss=2, ao_amt=0.5, bg=(132, 132, 132)) for y, p, _ in specs]
        rows.append((nm, ims, [s[2] for s in specs]))
    H = max(i.height for _, ims, _ in rows for i in ims)
    c1 = con.crop((150, 30, 400, 340)); c1 = c1.resize((int(c1.width * H / c1.height), H))
    c2 = con.crop((1110, 30, 1385, 340)); c2 = c2.resize((int(c2.width * H / c2.height), H))
    W = c1.width + c2.width + sum(i.width for i in rows[0][1]) + 16 * 8
    sh = Image.new("RGB", (W, 60 + len(rows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 r1 — 머리·가슴·등·허리 (어깨·팔·다리는 다음 단계)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(rows):
        y0 = 60 + r * (H + 50); x = 16
        for im, t in [(c1, "컨셉 정면")] + list(zip(ims, labs)) + [(c2, "컨셉 뒤")]:
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f)
            x += im.width + 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
    p = os.path.join(out, "시안_r1_머리가슴.png"); sh.save(p); print(p, sh.size)
