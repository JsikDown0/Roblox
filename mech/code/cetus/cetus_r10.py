"""HT-02 CETUS — r10 = r9 하체의 무릎 아래 재작업 (2026-11-02)

유저 11-02: "짱구 캔탐 로봇 같아. 무릎까진 괜찮은데 그 아래부턴 디테일도 없고 너무 단순해" (무릎 위 = r9 그대로)
원본(concept_v1 확대 zoom_shin_foot)에서 다시 읽은 것:
- 무릎 방패 밑 ~ 정강이 판 사이에 짙은 기계(가로 롤러)가 드러남
- 정강이 판 = 매끈한 종이 아니라 각진 판(가운데 세로 능선) + 아래 황동 테에 볼트
- 정강이 옆·뒤로 굽은 관 · 짙은 원반 · 쌓인 판
- 발목 = 아치 띠가 3겹(짙은 쇠/청록/짙은 쇠 + 황동 테·볼트), 정면에 갓 램프
- 발목 옆 큰 원반(바퀴살) + 위아래 핀으로 이은 세로 연결대
- 발끝 강철 덮개 = 앞·뒤 두 장이 겹친 판 + 아래 앞 짙은 틈, 옆 받침 블록 모서리에 황동
정강이 판 2안: a 각진 V 능선 판 · b 위아래 두 장 겹친 판. 나머지(롤러·관·피스톤·발목·발)는 공통.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
from flag_vox import cbox, cyl, ell, box  # noqa: E402
import cetus_r6 as r6  # noqa: E402
import cetus_r8 as r8  # noqa: E402
import cetus_r9 as r9  # noqa: E402

PAL, EMISSIVE, METAL = r9.PAL, r9.EMISSIVE, r9.METAL
KNEE, ANKLE, DX = r9.KNEE, r9.ANKLE, r9.DX
porthole, CX = r9.porthole, 35


def bolts(P, G, ring_mask, cx, cy, n, z, phase=0.0, c=5):
    """링 바깥면에 1칸 돋운 볼트 n개(앞쪽 반원만)."""
    X, Y, Z = G
    ang = np.arctan2(Y - cy, X - cx)
    for k in range(n):
        a = -np.pi + phase + (k + 0.5) * np.pi / n            # 앞(−Y) 반원
        da = np.abs((ang - a + np.pi) % (2 * np.pi) - np.pi)
        P.add(ring_mask & (da < 0.07) & (np.abs(Z - z) <= 0.6), c)


def shell(G, cx, cy, r_out, r_in, z0, z1, front=4):
    X, Y, Z = G
    d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
    return (d <= r_out + 0.25) & (d > r_in) & (Y <= front) & (Z >= z0) & (Z <= z1)


# ------------------------------------------------------------------ 무릎·정강이
def build_shin(M, var="a"):
    L = M.part("LowerLegL", (4, -46, 14), (68, 30, 120), pivot=KNEE, parent="UpperLegL")
    G = L.g(); X, Y, Z = G
    ax = np.abs(X - CX)
    # 무릎(r9 그대로): 관절 · 둥근 방패 · 황동 상자 · G1
    L.add(cyl(G, "x", (-2, 100), 12, rng=(19, 51)), 3)
    for x0, x1 in ((17, 19), (51, 53)):
        L.add(cyl(G, "x", (-2, 100), 8, rng=(x0, x1)), 7)
    L.add(ell(G, (CX, -12, 102), (20, 21, 15)) & (Y <= -4), 1)
    L.add(cbox(G, (25, 45), (-36, -26), (99, 115), {"xy": 3, "-y+z": 3}), 5)
    w = box(G, x=(29, 41), y=(-37, -34), z=(102, 110))
    L.cut(w & (Y <= -36)); L.paint(w & (Y <= -35), 6)
    # 정강이 심 + 무릎 밑 가로 롤러 2(짙은 쇠, 강철 끝)
    L.add(cbox(G, (23, 47), (-14, 16), (28, 96), {"xy": 6}), 3)
    for yc, zc in ((-18, 87), (-12, 82)):
        L.add(cyl(G, "x", (yc, zc), 4.5, rng=(21, 49)), 3)
        L.add(cyl(G, "x", (yc, zc), 3, rng=(19, 51)) & ~cyl(G, "x", (yc, zc), 3, rng=(21, 49)), 7)
    # 정강이 판
    kz = np.clip((80 - Z) / 30.0, 0, 1)
    hw = 16 + 8 * kz
    if var == "a":     # 각진 V 능선 판(가운데 세로 능선이 앞으로 솟음)
        yf = -(26 + 5 * kz) + 0.85 * ax                                    # 가파른 V(평평한 두 면)
        S = (ax <= hw) & (Y >= yf) & (Y <= 8) & (Z >= 50) & (Z <= 80)
        L.add(S, 1)
        L.add((ax <= hw) & (Y >= yf - 1.2) & (Y < yf) & (ax <= 1.2) & (Z >= 52) & (Z <= 80), 1)   # 능선 1칸 돋움
        top = (ax <= hw + 1) & (Y >= yf - 1) & (Y <= 9) & (Z >= 79) & (Z <= 81)
        L.add(top & ~(L.a > 0), 1)
    else:              # 위아래 두 장 겹친 판: 아래 판이 1.5칸 더 크고 위 판 밑단이 아래 판 위로 겹침
        dy = 19 + 6 * kz
        up = (((X - CX) / hw) ** 2 + ((Y + 4) / dy) ** 2 <= 1.0) & (Y <= 8) & (Z >= 66) & (Z <= 82)
        lo = (((X - CX) / (hw + 1.5)) ** 2 + ((Y + 4) / (dy + 1.5)) ** 2 <= 1.0) & (Y <= 8) & (Z >= 50) & (Z <= 68)
        L.add(lo, 1); L.add(up, 1)
        lip = (((X - CX) / (hw + 2.5)) ** 2 + ((Y + 4) / (dy + 2.5)) ** 2 <= 1.0) & (Y <= 8) & (Z >= 67) & (Z <= 69)
        L.add(lip & ~(L.a > 0), 1)
        L.groove(lip & (Z == 68) & ~(((X - CX) / (hw + 1.6)) ** 2 + ((Y + 4) / (dy + 1.6)) ** 2 <= 1.0), 4)
    # 아래 황동 테 + 볼트
    rim_o = ((((X - CX) / (hw + 2)) ** 2 + ((Y + 4) / (26 + 2)) ** 2) <= 1.0) & (Y <= 9) & (Z >= 46) & (Z <= 51)
    L.add(rim_o & ~(L.a > 0), 5); L.paint(rim_o, 5)
    ring = (((X - CX) / (hw + 3)) ** 2 + ((Y + 4) / 29) ** 2 <= 1.0) & ~rim_o & (Y <= 9) & (Z >= 47) & (Z <= 50)
    bolts(L, G, ring, CX, -4, 7, 48.5)
    # G2 무릎 바깥 옆 쌍둥이 램프
    L.add(cbox(G, (53, 59), (-6, 12), (76, 100), {"+xz": 3, "+xy": 2}), 3)
    for zc in (93, 82):
        porthole(L, G, "x", (0, 3, zc), 3.5, 5.5, (58, 61), face=61)
    # 바깥 옆·뒤 굽은 관(황동 고리 2)
    path = [(50, 16, 98), (57, 19, 86), (59, 19, 68), (55, 17, 52), (49, 12, 42)]
    t = r6.path_tube(G, path, 3.0) & ~(L.a > 0)
    L.add(t, 3)
    for c in path[1:3]:
        L.paint(t & r6.ball(G, c, 4.0), 5)
    # 종아리 피스톤 2(뒤): 짙은 통 + 강철 막대 + 황동 깃
    L.add(cbox(G, (32, 38), (15, 19), (52, 80), {"xy": 2}), 5)
    for xp in (27, 43):
        L.add(cyl(G, "z", (xp, 18), 4, rng=(66, 92)), 3)
        L.add(cyl(G, "z", (xp, 18), 2.2, rng=(42, 66)), 7)
        L.add(cyl(G, "z", (xp, 18), 4.8, rng=(66, 68)), 5)
        L.add(cyl(G, "z", (xp, 18), 3.5, rng=(40, 43)), 3)
    # 발목 양옆 원반: 강철 테 + 바퀴살 4 + 강철 축 + 볼트 4
    for x0, x1, xo in ((3, 10, 3), (60, 67, 67)):                     # 아치 띠 바깥으로 튀어나오게
        L.add(cyl(G, "x", (0, 34), 7, rng=((x1, 23) if x0 < CX else (47, x0))), 3)   # 원반 축(정강이 심까지)
        disc = cyl(G, "x", (0, 34), 14, rng=(x0, x1))
        L.add(disc, 3)
        L.add(disc & ~cyl(G, "x", (0, 34), 11), 7)
        face = disc & (X == xo) & cyl(G, "x", (0, 34), 11)
        L.cut(face)                                                      # 안쪽 면 1칸 오목
        spoke = cyl(G, "x", (0, 34), 11, rng=(x0, x1)) & ((np.abs(Y) <= 1.2) | (np.abs(Z - 34) <= 1.2)) & (X == xo)
        L.add(spoke, 7)
        L.add(cyl(G, "x", (0, 34), 5, rng=(x0 - 1, x1 + 1)), 7)
        for by, bz in ((8.5, 42.5), (-8.5, 42.5), (8.5, 25.5), (-8.5, 25.5)):
            xb = xo + (1 if xo > CX else -1)                             # 바깥으로 1칸 돋은 볼트
            L.add(cyl(G, "x", (by, bz), 1.2, rng=(xb, xb)), 5)
    # 세로 연결대(앞 양옆): 황동 막대 + 위아래 둥근 핀(강철)
    for xr in ((6, 10), (60, 64)):                                     # 아치 띠 바깥 앞 양옆
        L.add(box(G, x=xr, y=(-24, -20), z=(24, 50)), 3)
        L.add(box(G, x=xr, y=(-24, -12), z=(32, 36)), 3)                # 원반에 잇는 팔
        for zc in (48, 24):
            L.add(cyl(G, "x", (-22, zc), 3.5, rng=(xr[0] - 1, xr[1] + 1)), 5)
    L.trim()
    return L


# ------------------------------------------------------------------ 발(잠수 장화)
def build_foot(M):
    F = M.part("FootL", (-2, -50, 0), (74, 42, 52), pivot=ANKLE, parent="LowerLegL")
    G = F.g(); X, Y, Z = G
    ax, ay = CX, -6
    F.add(cyl(G, "z", (ax, 0), 18, rng=(8, 46)), 3)
    # 바닥·옆·뒤 받침(짙은 쇠) + 옆 블록 앞 모서리 황동 덮개
    F.add(cbox(G, (3, 67), (-46, 34), (0, 8), {"xy": 12, "+zy": 3, "+zx": 3}), 3)
    for x0, x1, sg in ((0, 10, "-x"), (60, 70, "+x")):
        F.add(cbox(G, (x0, x1), (-16, 28), (0, 21), {sg + "+z": 6, "yz": 3}), 3)
        F.add(cbox(G, (x0 - 1, x1 + 1), (-18, -10), (0, 14), {sg + "+z": 4, "-yz": 2}), 5)
        F.groove(box(G, x=(x0 - 1, x1 + 1), y=(4, 4), z=(1, 20)), 4)
    F.add(cbox(G, (14, 56), (16, 37), (0, 25), {"+y+z": 9, "xy": 4}), 3)
    F.add(cbox(G, (20, 50), (36, 39), (4, 14), {"xz": 2}), 5)                # 뒤꿈치 황동 띠
    # 발끝 강철 덮개 = 뒤 판 + 앞 판(1칸 더 크게 겹침) + 사이 짙은 홈 + 아래 앞 짙은 틈
    rear = ell(G, (ax, -12, 6), (27, 30, 21)) & (Z >= 6) & (Y <= 6) & (Y >= -26)
    frt = ell(G, (ax, -14, 6), (28.5, 32.5, 20)) & (Z >= 6) & (Y < -26)
    F.add(rear, 7); F.add(frt, 7)
    F.groove(ell(G, (ax, -14, 6), (29, 33, 21)) & (Y >= -27) & (Y <= -26) & (Z >= 6), 4)
    F.cut(box(G, x=(ax - 9, ax + 9), y=(-50, -38), z=(6, 12)))
    F.add(box(G, x=(ax - 9, ax + 9), y=(-42, -38), z=(6, 12)) & ~(F.a > 0), 4)
    for sx in (-14, 14):                                                       # 앞 판 볼트
        F.add(ell(G, (ax + sx, -40, 13), (1.4, 1.6, 1.4)) & ~(F.a > 0), 5)
    # 발목 아치 띠 3겹(앞 반원): 아래 청록 · 가운데 짙은 쇠 + 황동 테·볼트 · 위 짙은 쇠
    F.add(shell(G, ax, ay, 30, 20, 18, 24), 1)
    F.add(shell(G, ax, ay, 31, 20, 24, 25), 5)
    F.add(shell(G, ax, ay, 28, 18, 26, 35), 3)
    F.add(shell(G, ax, ay, 29, 18, 35, 37), 5)
    bolts(F, G, shell(G, ax, ay, 30, 29.3, 35, 37), ax, ay, 6, 36)
    F.add(shell(G, ax, ay, 25, 16, 38, 45), 3)
    F.add(shell(G, ax, ay, 26, 16, 44, 45), 7)
    # G3 갓 램프(가운데 띠 정면)
    yc = ay - 27
    porthole(F, G, "y", (ax, 0, 30), 4.5, 6.5, (yc - 3, yc + 2), face=yc - 3)
    F.add((box(G, x=(ax - 1, ax + 1), y=(yc - 5, yc - 3), z=(24, 36)) | box(G, x=(ax - 6, ax + 6), y=(yc - 5, yc - 3), z=(29, 31))), 5)
    F.trim()
    return F


def build_legs(M, var="a"):
    r9.build_pelvis(M)
    r9._shift(r9.build_thigh(M), DX)
    r9._shift(build_shin(M, var), DX + 2)
    r9._shift(build_foot(M), DX + 4)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


def build_all(var="a"):
    M = r8.build_all()
    build_legs(M, var)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    tiles = []
    for var in ("a", "b"):
        M = build_all(var)
        print("== 안", var); check_model.check(M)
        low = M.blocks(skip=[n for n in M.parts if n not in ("LowerLegL", "FootL")])
        tiles.append((vp.render(low, PAL, EMISSIVE, yaw=-25, pitch=8, ppc=5, ss=2, ao_amt=0.5, metal=METAL), var + " 무릎 아래 앞 3/4"))
        if var == "a":
            tiles.append((vp.render(low, PAL, EMISSIVE, yaw=60, pitch=6, ppc=5, ss=2, ao_amt=0.5, metal=METAL), "a 무릎 아래 바깥 옆"))
            Ma = M
    for var, M in (("a", Ma), ("b", M)):
        tiles.append((vp.render(M.blocks(), PAL, EMISSIVE, yaw=-30, pitch=6, ppc=2.3, ss=2, ao_amt=0.5, metal=METAL), var + " 전신"))
    H = max(t[0].height for t in tiles)
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "CETUS", "concept_v1_GPT_후보.png")).convert("RGB").crop((640, 840, 1150, 1250))
    con = con.resize((int(con.width * H / con.height), H), Image.LANCZOS)
    tiles.insert(0, (con, "컨셉 무릎 아래(왼다리)"))
    W = sum(t[0].width + 16 for t in tiles)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in tiles:
        sh.paste(im, (x, H - im.height)); d.text((x + 8, H + 8), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_r10_compare.png")); print(sh.size)
