"""HT-02 CETUS — 머리 진중한 버전 비교 (2026-11-02, 유저 "머리가 동글동글해서 귀여운 느낌 → 진중한 느낌 몇 개")

귀여워 보이는 원인 [판단]: 완전한 공 모양 돔 · 큰 둥근 창 + 십자 창살(커다란 눈 하나처럼 읽힘) · 정수리 고리 손잡이.
공통으로 유지: 잠수 헬멧 · 호박색 발광 창 · 관자놀이 못 · 머리 크기(어깨 사이에 묻힌 정도).
0 지금(r3b)
1 눈썹 처마 투구 — 같은 돔 + 창 윗부분을 덮는 비스듬한 짙은 쇠 판 두 장("\\ /" 찡그림) → 빛이 그늘 밑에서 나옴 · 고리 → 낮은 강철 능선
2 각진 투구 — 깎은 팔각 돔 + 평평한 얼굴판 + 가로 틈 창(세로 창살 3) + 턱 가리개 · 강철 능선
3 묻힌 철창 투구 — 돔을 4칸 낮추고 납작하게 + 뒤·옆을 높게 감싼 청록 목가리개 + 둥근 창에 세로 철창 4
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cbox, cyl, ell, box  # noqa: E402
import cetus_r3 as r3  # noqa: E402
import cetus_r10 as r10  # noqa: E402

PAL, EMISSIVE, METAL = r10.PAL, r10.EMISSIVE, r10.METAL


def new_head(M):
    M.parts.pop("Head", None)
    H = M.part("Head", (-34, -30, 212), (35, 30, 272), pivot=(0, -1, r3.NECK_Z), parent="Torso")
    G = H.g()
    return H, G, G[0], G[1], G[2]


def spikes(H, G, wz, y0=-5):
    X, Y, Z = G
    ax = np.abs(X)
    d2 = (Y - y0) ** 2 + (Z - wz) ** 2
    H.add((ax >= 15) & (ax <= 23) & (d2 <= 2.6 ** 2 + 0.25) & ~(H.a > 0), 5)
    H.add((ax >= 22) & (ax <= 23) & (d2 <= 3.6 ** 2 + 0.25), 5)
    rr = 2.6 * (30 - ax) / 7.0
    H.add((ax > 23) & (ax <= 30) & (d2 <= rr ** 2 + 0.25), 7)


def crest(H, G, c, r, z0):
    """정수리 앞뒤로 낮은 강철 능선(두께 3칸, 돔에서 2칸 솟음)."""
    X, Y, Z = G
    H.add(ell(G, c, (r + 2, r + 2, r + 2)) & ~ell(G, c, (r - 1, r - 1, r - 1)) & (np.abs(X) <= 1) & (Z >= z0) & (Y >= -15), 7)


def round_window(H, G, wz, r_glass=8, r_ring=11, y_ring=(-22, -15), y_glass=-17):
    H.cut(cyl(G, "y", (0, wz), r_glass, rng=(-28, y_glass - 1)))
    H.add(cyl(G, "y", (0, wz), r_ring, rng=y_ring) & ~cyl(G, "y", (0, wz), r_glass), 5)
    H.add(cyl(G, "y", (0, wz), r_glass, rng=(y_glass, y_glass + 1)), 6)


def head_0(M):
    M.parts.pop("Head", None)
    r3.build_head(M)


def head_1(M):
    H, G, X, Y, Z = new_head(M)
    c, wz = (0, -1, 240), 237
    H.add(ell(G, c, (19, 19, 19)) & (Z >= 221), 1)
    round_window(H, G, wz)
    H.add((box(G, x=(-1, 0)) | box(G, z=(wz - 1, wz))) & cyl(G, "y", (0, wz), 8, rng=(-19, -18)), 5)
    # 이마 처마: 창 위를 덮는 두 장의 비스듬한 짙은 쇠 판("\ /" 찡그린 눈썹), 돔에서 4칸 돋움, 위 테 황동
    ax = np.abs(X)
    zb = 242 + 0.5 * ax                                                    # 아래 끝: 가운데가 가장 낮음(창 윗부분을 가림)
    brow = ell(G, c, (23.5, 24, 23.5)) & ~ell(G, c, (18.5, 18.5, 18.5)) & (Y <= -6) & (ax <= 15) & (Z >= zb) & (Z <= zb + 6)
    H.add(brow, 3)
    H.paint(brow & (Z >= zb + 5), 5)
    crest(H, G, c, 19, 250)
    spikes(H, G, wz)
    H.trim()


def head_2(M):
    H, G, X, Y, Z = new_head(M)
    c, wz = (0, -1, 240), 238
    dome = cbox(G, (-19, 19), (-20, 18), (221, 260), {"xy": 7, "+zx": 10, "+zy": 9}) & ell(G, (0, -1, 238), (23, 23, 23))
    H.add(dome, 1)
    # 평평한 얼굴판(황동 테) + 가로 틈 창(2칸 오목, 세로 창살 3)
    face = cbox(G, (-13, 13), (-22, -18), (227, 249), {"xz": 4, "-y+z": 2})
    H.add(face, 3)
    H.paint(face & ~cbox(G, (-11, 11), (-23, -18), (229, 247), {"xz": 3}), 5)
    slit = box(G, x=(-10, 10), y=(-24, -20), z=(235, 241))
    H.cut(slit); H.add(box(G, x=(-10, 10), y=(-20, -20), z=(235, 241)), 6)
    for bx in (-6, 0, 5):
        H.add(box(G, x=(bx, bx + 1), y=(-22, -21), z=(235, 241)), 3)
    # 턱 가리개: 얼굴판 아래로 뾰족하게 내려오는 짙은 판
    jaw = fv.poly(G, "x", [(-23, 228), (-14, 228), (-12, 219), (-19, 216)], rng=(-12, 12))
    jaw &= (np.abs(X) <= 12 - 0.5 * np.maximum(0, 228 - Z))
    H.add(jaw, 3)
    crest(H, G, (0, -1, 238), 21, 249)
    spikes(H, G, wz, y0=-4)
    H.trim()


def head_3(M):
    H, G, X, Y, Z = new_head(M)
    c, wz = (0, -1, 236), 235
    H.add(ell(G, c, (20, 19, 17)) & (Z >= 220), 1)
    round_window(H, G, wz, r_glass=7, r_ring=10)
    for bx in (-5, -2, 1, 4):                                              # 세로 철창 4(짙은 쇠, 2칸 돋움)
        H.add(box(G, x=(bx, bx + 1), y=(-21, -19), z=(wz - 7, wz + 7)) & cyl(G, "y", (0, wz), 9.5), 3)
    # 높은 목가리개: 뒤·옆을 감싸고 앞으로 갈수록 낮아짐(청록 + 황동 윗테), 두께 4칸
    d = np.sqrt(X ** 2 + (Y + 1) ** 2)
    gor = (d <= 26.25) & (d > 21) & (Y >= -15) & (Z >= 219) & (Z <= 232 + 0.4 * (Y + 15))
    H.add(gor, 1)
    H.paint(gor & (Z >= 230 + 0.4 * (Y + 15)), 5)
    spikes(H, G, wz, y0=-6)
    H.trim()


VARIANTS = [("0", "지금 r3b", head_0), ("1", "눈썹 처마 투구", head_1), ("2", "각진 투구", head_2), ("3", "묻힌 철창 투구", head_3)]


def build_all(which="0"):
    M = r10.build_all("a")
    dict((v[0], v[2]) for v in VARIANTS)[which](M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    up = ("Torso", "Head", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR")
    cols = []
    for key, label, fn in VARIANTS:
        M = build_all(key)
        h = M.parts["Head"]; _, k = ndimage.label(h.a > 0)
        print(key, "Head cells", h.count(), "tris", 2 * greedy_quads(h.a), "섬", k - 1)
        U = M.blocks(skip=[n for n in M.parts if n not in up])
        a = vp.render(U, PAL, EMISSIVE, yaw=-30, pitch=8, ppc=4.0, ss=2, ao_amt=0.5, metal=METAL)
        b = vp.render(U, PAL, EMISSIVE, yaw=0, pitch=4, ppc=4.0, ss=2, ao_amt=0.5, metal=METAL)
        c = vp.render(M.blocks(), PAL, EMISSIVE, yaw=-30, pitch=6, ppc=1.5, ss=2, ao_amt=0.5, metal=METAL)
        cols.append((key + " " + label, a, b, c))
    ha = max(t[1].height for t in cols); hb = max(t[2].height for t in cols); hc = max(t[3].height for t in cols)
    wcol = max(max(t[1].width, t[2].width, t[3].width) for t in cols)
    sh = Image.new("RGB", ((wcol + 16) * len(cols), ha + hb + hc + 80), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for i, (lab, a, b, c) in enumerate(cols):
        x = i * (wcol + 16)
        d.text((x + 8, 6), lab, fill=(230, 230, 230), font=f)
        sh.paste(a, (x, 40)); sh.paste(b, (x, 40 + ha + 10)); sh.paste(c, (x + (wcol - c.width) // 2, 40 + ha + hb + 20))
    sh.save(os.path.join(out, "cetus_heads_compare.png")); print(sh.size)
