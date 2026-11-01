"""
flagship_heavy.py — 대표 기체 r2: 육중한 전투용 메카 (2026-10-25 19:42~)

GPT 피드백 반영: ① 긴 V 날개 → 낮고 두꺼운 장갑 등짐 ② 넓고 깊은 흉갑 + 갑주에 묻힌 작은 머리
③ 허리·관절 노출 줄이고 허벅지·무릎·정강이 크게 ④ 잔 홈 대신 큰 판이 겹치고 그 틈에 어두운 기계 구조
⑤ 발광은 코어·바이저·추진기만, 무게중심 낮게.
칸 = 0.05 Blender. +X = 기체 왼쪽, -Y = 정면, +Z = 위. 색: 1 주장갑 2 보조(넓은 짙은 구조) 3 프레임 4 검정 5 표식 6 발광 7 금속
"""
import numpy as np

import flag_vox as fv
from flag_vox import box, cbox, poly, cyl, ell, rotx, roty


# ------------------------------------------------------------------ 골반
def build_pelvis(M):
    p = M.part("Pelvis", (-40, -34, 118), (41, 30, 176), pivot=(0, 0, 150))
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cbox(G, (-24, 24), (-18, 16), (136, 170), {"xy": 5, "-zx": 8}), 3)
    p.add(cbox(G, (-30, 30), (-24, 22), (160, 172), {"xy": 8}), 2)            # 허리 띠(넓은 짙은 구조)
    cr = cbox(G, (-11, 11), (-27, -16), (130, 166), {"-zx": (10, 8), "x-y": 4, "-z-y": (4, 4)})
    p.add(cr, 1)
    p.paint(cr & (Z >= 160), 2)
    p.add(cbox(G, (-20, 20), (18, 24), (132, 166), {"-zx": 8}), 2)            # 뒤 스커트
    for s in (1, -1):
        p.add(cbox(G, (s * 22, s * 32), (-10, 10), (146, 166), {"xy": 3}), 3)  # 엉덩이 축 받침
        p.add(cyl(G, "x", (-9, 150), 4, (s * 14, s * 30)), 7)                    # 엉덩이 유압
    f = M.part("SkirtFL", (6, -36, 124), (32, -20, 172), pivot=(19, -27, 168), parent="Pelvis")
    G = f.g()
    f.add(cbox(G, (10, 28), (-31, -26), (134, 168), {"-z+x": (12, 10), "-z-x": (3, 3), "+zx": 2}), 1)
    f.add(cbox(G, (12, 26), (-26, -24), (138, 166)), 3)
    f.rot = rotx(14)
    s_ = M.part("SkirtSL", (26, -22, 116), (40, 22, 172), pivot=(31, 0, 168), parent="Pelvis")
    G = s_.g(); X, Y, Z = G
    sk = cbox(G, (31, 37), (-19, 19), (124, 168), {"-zy": (10, 8), "+xz": 3, "+xy": 3})
    s_.add(sk, 1)
    s_.add(cbox(G, (29, 31), (-15, 15), (128, 164)), 3)
    s_.paint(sk & (Z <= 133), 2)
    s_.rot = roty(10)
    M.mirror("SkirtFL", "SkirtFR", "Pelvis")
    M.mirror("SkirtSL", "SkirtSR", "Pelvis")


# ------------------------------------------------------------------ 몸통
def build_torso(M):
    p = M.part("Torso", (-54, -42, 164), (55, 34, 256), pivot=(0, 0, 172), parent="Pelvis")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cbox(G, (-22, 22), (-18, 16), (166, 194), {"xy": 6}), 3)
    p.add(cbox(G, (-17, 17), (-24, -17), (169, 181), {"xy": 3, "-zx": 3}), 2)   # 배 장갑 2단(위가 덮음)
    p.add(cbox(G, (-19, 19), (-26, -17), (179, 193), {"xy": 3}), 2)
    # 몸통 속(짙은 구조). 앞면은 1:2 로 뒤로 누움 — 그 앞을 흉판 한 장이 덮는다
    ch = cbox(G, (-38, 38), (-30, 24), (188, 238), {"x-y": 12, "-zx": (14, 12), "+z-y": (38, 19), "x+y": 8, "-z-y": 6})
    p.add(ch, 2)
    # ⚠ 흉판을 가로로 나누면(위 판 + 아래 띠 + 가운데 등) 눈썹·입이 있는 얼굴로 읽혔다(r2 2판) → 세로 홈 하나 + 세로 발광 틈
    p.paint(ch & (ax <= 3) & (Y <= -10), 3)
    p.paint(ch & (ax <= 1) & (Y <= -10) & (Z >= 204) & (Z <= 222), 6)
    # 배 옆 피스톤(드러난 기계)
    for sx in (1, -1):
        p.add(cyl(G, "z", (sx * 25, -8), 3, (168, 196)), 7)
        p.add(cyl(G, "z", (sx * 25, -8), 4, (192, 197)), 3)
    # 옆구리 측면 장갑판
    for sx in (1, -1):
        p.add(cbox(G, (sx * 36, sx * 41), (-18, 14), (196, 228), {"xz": 3, "xy": 3}) & (np.abs(X) >= 36), 1)
    # 높은 깃(머리가 묻히는 자리)
    col = cbox(G, (-21, 21), (-6, 24), (232, 251), {"+z-y": (10, 12), "+zx": (10, 8), "x-y": 5})
    hole = cbox(G, (-12, 12), (-30, 12), (238, 262), {"x+y": 3})
    p.add(col & ~hole, 1)
    p.paint(col & ~hole & (Y >= 16), 2)
    # 승모 장갑(어깨로 이어짐)
    p.add(cbox(G, (-52, 52), (-24, 22), (230, 242), {"+zx": (8, 16), "x-y": 6, "x+y": 6}) & ~ch, 2)
    p.add(cyl(G, "z", (0, -2), 7, (232, 240)), 3)
    p.add(cbox(G, (-30, 30), (24, 30), (192, 236), {"xy": 4}), 3)
    # 앞으로 누운 흉판(글라시스): 세워서 만들고 관절로 35° 눕힘 → 큰 평면이 계단 없이
    g = M.part("ChestPlate", (-40, -42, 190), (41, -28, 248), pivot=(0, -34, 196), parent="Torso")
    G = g.g(); X, Y, Z = G
    plate = poly(G, "y", [(3, 196), (22, 196), (34, 232), (34, 238), (30, 242), (3, 242)], rng=(-40, -34), sym=True)
    g.add(plate, 1)
    g.paint(plate & (Z <= 201), 2)
    g.add(box(G, (-3, 3), (-35, -34), (196, 242)), 3)          # 홈 뒤 등뼈(두 쪽을 한 덩어리로)
    g.add(box(G, (-1, 1), (-35, -35), (206, 226)), 6)          # 세로 발광 틈(유일한 가슴 발광)
    g.rot = rotx(-25)


# ------------------------------------------------------------------ 머리 (작게, 깃 속에)
def build_head(M):
    p = M.part("Head", (-16, -22, 230), (16, 16, 272), pivot=(0, -4, 238), parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cyl(G, "z", (0, -2), 6, (234, 243)), 3)
    hd = cbox(G, (-9, 9), (-16, 8), (240, 256), {"x-y": (5, 7), "+z-y": (5, 6), "+zx": 3, "-z-y": (4, 4), "x+y": 3})
    p.add(hd, 1)
    p.paint(hd & (Y >= 2), 2)
    p.paint(hd & (Y <= -10) & (Z <= 246) & (ax <= 5), 2)
    slit = (Z >= 248) & (Z <= 249) & (ax <= 7) & (Y <= -6)
    p.cut(slit & (Y <= -12))
    p.add(slit & (Y >= -12) & (Y <= -11), 6)
    p.add(cbox(G, (-11, 11), (-8, 2), (244, 252), {"xz": 1}) & (ax >= 9), 3)
    # 한쪽(오른쪽)에만 안테나 막대 — 비대칭
    p.add(box(G, (-11, -10), (2, 3), (250, 268)), 3)
    p.add(box(G, (-11, -10), (2, 3), (268, 269)), 4)


# ------------------------------------------------------------------ 팔
SHOULDER = (54, 0, 224)
ELBOW = (54, 0, 176)


def build_arm(M):
    p = M.part("ShoulderL", (38, -34, 190), (86, 32, 258), pivot=SHOULDER, parent="Torso")
    G = p.g(); X, Y, Z = G
    sh = cbox(G, (42, 78), (-28, 26), (202, 248),
              {"+z-x": (8, 14), "-z+x": (16, 12), "x-y": 8, "x+y": 8, "+z-y": 6, "+z+y": 6})
    p.add(sh, 1)
    p.paint(sh & (Z <= 214), 2)
    lw = cbox(G, (70, 82), (-24, 22), (208, 226), {"+x-y": 4, "+x+y": 4, "-z+x": (4, 4), "+z+x": (3, 3)})
    lw2 = cbox(G, (68, 80), (-22, 20), (194, 210), {"+x-y": 4, "+x+y": 4, "-z+x": (6, 6)})
    p.add(cbox(G, (66, 72), (-20, 18), (196, 224)), 3)
    p.add(lw2, 1)
    p.add(lw, 1)
    cap = cbox(G, (52, 80), (-30, 28), (245, 252), {"+z-x": (4, 10), "x-y": 8, "x+y": 8, "-z+x": (3, 3)})
    p.add(cap, 1)
    p.add(box(G, (74, 80), (-31, -31), (240, 246)) & cbox(G, (52, 80), (-31, 28), (240, 252), {"x-y": 8}), 5)
    p.cut(box(G, (40, 48), None, (200, 240)) & ~cap)
    p.rot = roty(-6)

    a = M.part("UpperArmL", (38, -20, 160), (72, 20, 240), pivot=SHOULDER, parent="Torso")
    G = a.g(); X, Y, Z = G
    a.add(ell(G, (54, 0, 222), (13, 13, 13)), 3)
    a.add(cyl(G, "z", (54, 0), 11, (180, 220)), 3)
    bc = cbox(G, (42, 66), (-15, 13), (184, 212), {"xy": 6, "-zx": 4, "-zy": 4})
    a.add(bc, 1)
    a.paint(bc & (X <= 46), 2)
    a.add(cyl(G, "x", (0, 176), 11, (43, 65)), 3)
    a.add(cyl(G, "x", (0, 176), 5, (41, 67)), 7)

    f = M.part("LowerArmL", (36, -24, 80), (78, 28, 188), pivot=ELBOW, parent="UpperArmL")
    G = f.g(); X, Y, Z = G
    fa = cbox(G, (42, 66), (-16, 16), (126, 170), {"xy": 7, "-zx": 4, "-zy": 4, "+zx": 4, "+zy": 4})
    f.add(fa, 2)
    f.add(cbox(G, (41, 67), (-21, -14), (132, 168), {"x-y": 5, "-z-y": (4, 3), "+z-y": (3, 3)}), 1)
    f.add(cbox(G, (65, 72), (-14, 16), (128, 168), {"+x-y": 3, "+x+y": 3, "+x-z": 4, "+x+z": 3}), 1)
    f.add(cyl(G, "z", (54, 18), 3, (164, 186)), 7)          # 팔꿈치 뒤 피스톤
    f.add(cbox(G, (45, 63), (12, 22), (160, 184), {"+y+z": (8, 8), "x+y": 3}), 2)
    f.add(cyl(G, "z", (54, 0), 9, (118, 128)), 3)
    f.add(box(G, (46, 62), (-12, 12), (98, 120)), 3)
    f.add(cbox(G, (61, 66), (-13, 13), (100, 122), {"+xz": 3, "+xy": 3}), 1)
    for fy in (-11, -5, 1, 7):
        f.add(box(G, (48, 60), (fy, fy + 4), (86, 99)), 3)
        f.add(box(G, (59, 61), (fy, fy + 4), (90, 99)), 2)
    f.add(cbox(G, (42, 47), (-16, -10), (94, 112), {"xy": 1}), 3)
    M.mirror("ShoulderL", "ShoulderR", "Torso")
    M.mirror("UpperArmL", "UpperArmR", "Torso")
    M.mirror("LowerArmL", "LowerArmR", "UpperArmR")


# ------------------------------------------------------------------ 다리 (굵게, 아래로 넓게)
HIP = (24, 0, 142)
KNEE = (24, -2, 92)
ANKLE = (26, 0, 22)


def build_leg(M):
    t = M.part("UpperLegL", (6, -26, 90), (44, 22, 158), pivot=HIP, parent="Pelvis")
    G = t.g(); X, Y, Z = G
    t.add(ell(G, (24, 0, 142), (13, 13, 13)), 3)
    t.add(cbox(G, (12, 36), (-14, 14), (98, 140), {"xy": 5}), 3)
    t.add(cbox(G, (10, 38), (-21, -10), (104, 136), {"x-y": 5, "-z-y": (8, 6), "+z-y": 3}), 1)
    t.add(cbox(G, (35, 41), (-14, 12), (106, 138), {"+xy": 4, "+xz": 4}), 2)
    t.add(cbox(G, (14, 34), (12, 18), (106, 132), {"x+y": 3}), 2)

    s = M.part("LowerLegL", (0, -38, 12), (48, 38, 126), pivot=KNEE, parent="UpperLegL")
    G = s.g(); X, Y, Z = G
    s.add(cyl(G, "x", (-2, 92), 13, (11, 37)), 3)
    s.add(cyl(G, "x", (-2, 92), 6, (9, 39)), 7)
    s.add(cbox(G, (10, 38), (-18, 22), (24, 90), {"xy": 6}), 2)
    sp = cbox(G, (8, 40), (-25, -15), (50, 86), {"x-y": 6, "+z-y": (6, 4), "-z-y": (4, 4)})
    s.add(sp, 1)
    bt = cbox(G, (5, 43), (-26, 26), (16, 50), {"x-y": 10, "x+y": 8, "+zx": (6, 6), "+z-y": (6, 6)})
    s.add(bt, 1)
    s.paint(bt & ((Z <= 27) | (Y >= 10)), 2)
    cf = cbox(G, (12, 36), (18, 33), (40, 84), {"+y-z": (12, 14), "+y+z": (8, 10), "x+y": 5})
    s.add(cf, 2)
    s.add(cyl(G, "z", (24, 12), 3, (78, 100)), 7)       # 무릎 뒤 피스톤
    kn = cbox(G, (10, 38), (-33, -14), (78, 118), {"+z-y": (16, 12), "x-y": 6, "-z-y": (8, 6), "+zx": 5})
    s.add(kn, 1)
    s.add(cyl(G, "x", (0, 22), 10, (14, 38)), 3)

    f = M.part("FootL", (2, -50, 0), (50, 32, 40), pivot=ANKLE, parent="LowerLegL")
    G = f.g(); X, Y, Z = G
    f.add(ell(G, (26, 0, 22), (10, 10, 10)), 3)
    f.add(cbox(G, (8, 44), (-44, 26), (0, 3), {"xy": 4}), 4)
    f.add(cbox(G, (9, 43), (-34, 22), (4, 16), {"+z-y": (8, 10), "xy": 5}), 2)
    f.add(cbox(G, (10, 42), (-47, -26), (2, 12), {"+z-y": (6, 8), "x-y": 8}), 1)
    f.add(cbox(G, (12, 40), (16, 29), (3, 16), {"+z+y": (6, 6), "x+y": 4}), 1)
    f.add(cbox(G, (14, 38), (-24, -4), (15, 21), {"+z-y": (5, 5)}), 1)
    for xr in ((5, 10), (42, 47)):
        f.add(cbox(G, xr, (-12, 14), (8, 34), {"+zy": (6, 6)}), 1)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


# ------------------------------------------------------------------ 등짐 (낮고 두껍게)
def build_back(M):
    b = M.part("Backpack", (-50, 22, 176), (51, 62, 266), pivot=(0, 28, 212), parent="Torso")
    G = b.g(); X, Y, Z = G; ax = np.abs(X)
    b.add(cbox(G, (-28, 28), (26, 50), (184, 238), {"+yx": (8, 8), "+y+z": (10, 10), "+y-z": (10, 10), "+zx": 6}), 2)
    b.add(cbox(G, (-22, 22), (49, 54), (194, 230), {"+yx": (3, 3), "+yz": (3, 3)}), 1)
    for s in (1, -1):
        pod = cbox(G, (s * 26, s * 44), (30, 58), (198, 244), {"+z-y": (10, 12), "xy": 4, "+zx": 4, "-z+y": (6, 6)})
        b.add(pod, 2)
        b.paint(pod & (Y >= 50) & (Z >= 210), 1)
        nz = cyl(G, "z", (s * 35, 42), 7, (186, 199)) & ~cyl(G, "z", (s * 35, 42), 4.5, (186, 193))
        b.add(nz, 7)
        b.add(cyl(G, "z", (s * 35, 42), 4.5, (193, 194)), 6)
        b.add(cbox(G, (s * 24, s * 27), (34, 48), (204, 250)), 3)


def build_all():
    M = fv.Model()
    build_pelvis(M)
    build_torso(M)
    build_head(M)
    build_arm(M)
    build_leg(M)
    build_back(M)
    return M


SCHEMES = {
    "A": {1: (206, 204, 196), 2: (78, 82, 88), 3: (46, 48, 52), 4: (22, 23, 25), 5: (214, 110, 34), 6: (255, 150, 60), 7: (122, 126, 130)},
    "B": {1: (176, 168, 140), 2: (84, 80, 70), 3: (48, 46, 42), 4: (22, 21, 19), 5: (200, 60, 40), 6: (255, 170, 70), 7: (120, 118, 112)},
    "C": {1: (128, 134, 142), 2: (58, 62, 70), 3: (38, 40, 46), 4: (18, 19, 22), 5: (220, 190, 60), 6: (255, 70, 60), 7: (130, 136, 144)},
}
EMISSIVE = {6}
STANCE = {   # 미리보기 자세: 팔은 부피 때문에 벌어지고 무릎 살짝 굽힌 버팀 자세
    "UpperArmL": roty(-11), "UpperArmR": roty(11), "ShoulderL": roty(-4), "ShoulderR": roty(4),
    "LowerArmL": rotx(-16), "LowerArmR": rotx(-12),
    "UpperLegL": roty(-4) @ rotx(-8), "UpperLegR": roty(4) @ rotx(-6),
    "LowerLegL": rotx(14), "LowerLegR": rotx(10), "FootL": roty(4) @ rotx(-6), "FootR": roty(-4) @ rotx(-4),
}
VIEWS = ((0, 4, "front"), (30, 6, "3/4"), (90, 2, "side"), (150, 12, "back 3/4"))


def preview(M, sch="A", out="/tmp/claude-0/heavy.png", views=VIEWS, ppc=2.7, pose="S", ao=0.5):
    import vox_preview as vp
    B = M.blocks(pose=STANCE if pose == "S" else pose)
    ims = [vp.render(B, SCHEMES[sch], EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2, ao_amt=ao) for y, p, _ in views]
    vp.sheet(ims, [v[2] for v in views]).save(out)
    return out


if __name__ == "__main__":
    import sys, time
    t0 = time.time()
    M = build_all()
    preview(M, sys.argv[1] if len(sys.argv) > 1 else "A")
    print("done %.1fs" % (time.time() - t0))
