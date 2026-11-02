"""SP-? APIS(지원기) — r1 머리·가슴 (2026-11-02)

윤곽 읽기: mech/docs/레퍼런스/지원기/윤곽읽기_r1_부품지도.png · 윤곽읽기_r2_머리가슴.png · 결정기록 7절.
답 [결정 11-02]: 헬멧 위 짙은 혹 2(곰 귀) 넣음 · 머리 = 어깨 사이 낮게 + 앞으로 · 바이저 = 양끝 처진 호(그림대로).
칸 0.05 · +X = 기체 왼쪽 · −Y = 정면 · +Z = 위. 그림 → 칸: X = (x − 276) × 0.319 · z = (950 − y) × 0.319.
게임은 절반 해상도로 쓰므로(결정 11-02) 장식은 2칸 이상 굵기로.
색: 1 노랑(주장갑) · 2 흰(보조) · 3 짙은 회색 프레임 · 4 검정 · 5 밝은 강철 · 6 청록 발광 · 7 금속.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cbox, cyl, ell, box  # noqa: E402

PAL = {1: (232, 186, 46), 2: (228, 228, 222), 3: (54, 56, 60), 4: (16, 17, 19), 5: (156, 160, 164),
       6: (90, 236, 240), 7: (120, 122, 126)}
EMISSIVE = {6}
NECK_Z = 224


def build_torso(M):
    T = M.part("Torso", (-34, -28, 166), (35, 26, 236), pivot=(0, 0, 190))
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    # 가슴통(옆·뒤 = 노랑 장갑): 폭 53 · 깊이 38 · 위 모서리 깎음
    body = cbox(G, (-26, 26), (-18, 18), (196, 229), {"xy": 7, "+zx": 6, "+zy": 5, "-zy": 3})
    T.add(body, 1)
    # 앞 흰 가슴판(2칸 돋움): 위는 V 로 파인 목깃 밑, 아래 끝은 가운데로 뾰족, 모서리 깎음
    plate = cbox(G, (-25, 25), (-21, -15), (198, 225), {"xz": 6, "-y+z": 2, "-yx": 3})
    plate &= (Z >= 199 + 0.3 * ax) & (Z <= 224 - np.maximum(0, 6 - ax) * 0.9)
    T.add(plate, 2)
    T.groove(box(G, x=(0, 0), y=(-23, -16), z=(201, 222)), 4)                                # 가운데 세로 홈
    T.groove(plate & (Z == 213) & (ax >= 8), 4)                                               # 가로 판 나눔
    # 노랑 목깃 띠: 가슴판 위 2칸, 가운데 V
    collar = cbox(G, (-24, 24), (-20, 14), (224, 230), {"xy": 6, "-y+z": 3}) & ~((ax <= 7 - (230 - Z) * 1.2) & (Y < -8))
    T.add(collar, 1)
    T.add(cbox(G, (-21, 21), (-15, 14), (180, 199), {"xy": 5}), 3)                           # 짙은 허리
    # 배: 짙은 틀 + 청록 코어(1칸 오목) + 노랑 옆 블록(각지게)
    T.add(cbox(G, (-9, 9), (-19, -11), (173, 188), {"xz": 2}), 3)
    T.groove(box(G, x=(-5, 5), y=(-20, -18), z=(177, 183)), 6)
    for s in (1, -1):
        T.add(cbox(G, (min(s * 10, s * 20), max(s * 10, s * 20)), (-17, -6), (174, 187), {"xz": 3, "-yx": 2, "-yz": 2}), 1)
    T.add(cyl(G, "z", (0, -2), 11, rng=(228, 231)), 3)                                       # 목 받침
    T.trim()
    return T


def build_head(M):
    H = M.part("Head", (-18, -26, 218), (19, 22, 266), pivot=(0, -4, NECK_Z), parent="Torso")
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    H.add(cyl(G, "z", (0, -3), 10, rng=(222, 229)), 3)                                       # 목 고리
    # 헬멧: 깎은 상자 ∩ 타원(각진 투구) — 앞이 낮고 뒤가 높음, 앞으로 나옴
    dome = cbox(G, (-13, 13), (-19, 14), (227, 258), {"xy": 5, "+zx": 6, "+zy": (7, 9), "-zy": 3}) & ell(G, (0, -2, 240), (15, 20, 19))
    dome &= (Z <= 257 + 0.28 * (Y - 12))
    H.add(dome, 1)
    # 흰 얼굴판(이마~바이저 위) + 이마 가로 홈 + 바이저(양끝 처진 호, 1칸 오목 발광) + 짙은 턱
    front = dome & (Y <= -12)
    H.paint(front & (Z >= 236) & (ax <= 9), 2)
    H.groove(box(G, x=(-3, 3), y=(-22, -12), z=(246, 247)), 4)
    zc = 239 - 0.045 * X ** 2
    H.groove(front & (ax <= 10) & (Z >= zc - 1.6) & (Z <= zc + 1.6), 6)
    H.add(cbox(G, (-8, 8), (-19, -8), (225, 232), {"xz": 2, "-y-z": 3}), 3)
    for s in (1, -1):
        H.add(cbox(G, (min(s * 11, s * 15), max(s * 11, s * 15)), (-17, 4), (228, 241), {"-yz": 3, "+zy": 2}), 1)   # 노랑 볼판
        H.add(cyl(G, "z", (s * 9, 6), 2.6, rng=(250, 259)), 3)                                # 곰 귀 혹
        H.add(cyl(G, "z", (s * 9, 6), 3.2, rng=(258, 259)), 3)
    H.trim()
    return H


def build_all():
    M = fv.Model()
    build_torso(M)
    build_head(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    M = build_all()
    for n, p in M.parts.items():
        _, k = ndimage.label(p.a > 0)
        print(n, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
    B = M.blocks()
    specs = [(0, 4, "r1 정면"), (-30, 8, "r1 앞 3/4"), (-90, 2, "r1 옆")]
    ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=5, ss=2, ao_amt=0.5) for y, p, _ in specs]
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "지원기", "concept_v1_삼면도.webp")).convert("RGB")
    H = max(i.height for i in ims)
    c1 = con.crop((185, 120, 370, 420)); c1 = c1.resize((int(c1.width * H / c1.height), H))
    c2 = con.crop((585, 120, 770, 345)); c2 = c2.resize((int(c2.width * H / c2.height), H))
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    tiles = [(c1, "컨셉 정면")] + list(zip(ims, [s[2] for s in specs])) + [(c2, "컨셉 옆")]
    W = sum(i.width + 16 for i, _ in tiles)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in tiles:
        sh.paste(im, (x, H - im.height)); d.text((x + 8, H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "apis_r1_compare.png")); print(sh.size)
