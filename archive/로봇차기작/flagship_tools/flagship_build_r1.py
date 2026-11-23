"""
flagship_build.py — 대표(마스코트) 기체 복셀 모델 (2026-10-25, v2: 상자+45° 모따기 문법)

칸 = 0.05 Blender (프로토의 절반). 머리 꼭대기 ≈ 262칸 ≈ 프로토 1.2배.
+X = 기체 왼쪽, -Y = 정면, +Z = 위. 좌우 대칭 i -> -i.
비스듬한 판(날개·스커트)은 똑바로 세워 만들고 관절(rot)로 기울인다 → 계단 무늬가 안 생긴다.
색 번호: 1 주장갑 2 보조장갑 3 프레임 4 검정(홈·밑창) 5 강조 줄 6 발광 7 금속(노즐·관절 캡)
"""
import numpy as np

import flag_vox as fv
from flag_vox import _dilate, box, cbox, poly, half, cyl, ell, band, slab, shift, local, rotx, roty, rotz


def _grow(m, n=1):
    for _ in range(n):
        m = _dilate(m)
    return m


# ------------------------------------------------------------------ 골반 + 스커트
def build_pelvis(M):
    p = M.part("Pelvis", (-32, -26, 126), (33, 24, 174), pivot=(0, 0, 158))
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cbox(G, (-20, 20), (-13, 13), (140, 170), {"xy": 4, "-zx": 6}), 3)
    cr = cbox(G, (-9, 9), (-20, -10), (132, 166), {"-zx": 8, "-z-y": 4, "x-y": 3})
    p.add(cr, 1)
    p.paint(cr & (Z >= 162), 2)
    p.groove(cr & (ax <= 0.5) & (Z < 161), 4)
    p.add(cbox(G, (-14, 14), (14, 18), (138, 166), {"-zx": 6}), 2)
    for s in (1, -1):
        p.add(cbox(G, (s * 19, s * 27), (-7, 7), (150, 166), {"xy": 2}), 3)

    # 앞 스커트: 위 경첩에서 앞으로 12° 들림
    f = M.part("SkirtFL", (6, -24, 134), (28, -16, 168), pivot=(16, -20, 166), parent="Pelvis")
    G = f.g(); X, Y, Z = G
    sk = cbox(G, (8, 25), (-22, -19), (138, 166), {"-z+x": (10, 9), "-z-x": (3, 3)})
    f.add(sk, 1)
    f.groove(sk & (np.abs(X - 16.5) <= 0.5) & (Z < 158), 4)
    f.rot = rotx(16)
    # 옆 스커트: 바깥으로 14° 벌어짐
    s_ = M.part("SkirtSL", (24, -18, 124), (33, 18, 168), pivot=(27, 0, 166), parent="Pelvis")
    G = s_.g(); X, Y, Z = G
    sk = cbox(G, (26, 30), (-15, 15), (128, 166), {"-zy": (8, 6), "+xy": 2})
    s_.add(sk, 2)
    s_.paint(sk & (Z >= 158), 1)
    s_.groove(sk & (np.abs(Z - 157) <= 0.5) & (X >= 29), 4)
    s_.groove(sk & (np.abs(Z - 142) <= 0.5) & (X >= 29), 4)
    s_.rot = roty(14)
    M.mirror("SkirtFL", "SkirtFR", "Pelvis")
    M.mirror("SkirtSL", "SkirtSR", "Pelvis")


# ------------------------------------------------------------------ 몸통
def build_torso(M):
    p = M.part("Torso", (-46, -38, 164), (47, 30, 252), pivot=(0, 0, 172), parent="Pelvis")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    ab = cbox(G, (-16, 16), (-12, 11), (166, 190), {"xy": 5})
    p.add(ab, 3)
    for z in (172, 178, 184):
        p.groove(ab & (np.abs(Z - z) <= 0.5) & (Y < -6), 4)
    abp = cbox(G, (-6, 6), (-15, -12), (170, 188), {"xy": 1})
    p.add(abp, 2)
    for z in (176, 182):
        p.groove(abp & (np.abs(Z - z) <= 0.5), 4)
    lc = cbox(G, (-25, 25), (-23, 19), (186, 202), {"x-y": 9, "-zx": 6, "-z-y": 4})
    p.add(lc, 2)
    ch = cbox(G, (-34, 34), (-30, 20), (198, 234), {"x-y": 12, "-zx": (16, 14), "+z-y": 8, "x+y": 6, "-z-y": 6})
    p.add(ch, 1)
    p.paint_s(ch & (Y < -14), 2)
    p.paint_s(ch & (Z >= 233), 2)
    # 대흉판: 2칸 돋을, 아래 모서리는 바깥으로 갈수록 내려감(1:3)
    pec = (ax >= 5) & (ax <= 31) & (Z <= 231) & (Z >= 216 - (ax - 5) / 3.0) & (Y < -8)
    p.emboss(pec, 1, h=2)
    # 용골 + 코어
    p.cut(box(G, (-3, 3), (-40, -27), (198, 231)))
    p.paint(box(G, (-4, 4), (-40, -25), (196, 232)) & (ax <= 4), 3)
    p.add(cbox(G, (-3, 3), (-31, -28), (218, 229), {"xz": 1}), 3)
    p.add(cbox(G, (-2, 2), (-32, -31), (220, 227), {"xz": 1}), 6)
    # ⚠ 윗가슴에 좌우 한 쌍(흡기·등)을 두면 코어와 함께 얼굴(눈·코·입)로 읽힌다 — 2026-10-25 재확인. 가슴 장식은 가운데 한 줄만.
    # 옆구리 흡기: 파고 살대
    # (가슴 아래 모따기 때문에 z<214 에선 옆면이 x<34 로 들어간다 → 흡기는 z 216~228, 살대는 바닥에 붙여서)
    p.cut(box(G, None, (-12, 6), (216, 228)) & (ax >= 31))
    p.paint(box(G, None, (-13, 7), (215, 229)) & (ax >= 29) & (ax <= 31), 4)
    for z in (218, 221, 224, 227):
        p.add(box(G, None, (-12, 6), (z, z)) & (ax >= 30) & (ax <= 32), 7)
    # 승모 경사 + 깃
    p.add(cbox(G, (-42, 42), (-18, 16), (228, 238), {"+zx": (7, 14), "x-y": 4}) & ~ch, 1)
    col = cbox(G, (-18, 18), (-6, 20), (232, 246), {"+z-y": 8, "+zx": 4, "x-y": 4})
    hole = cbox(G, (-11, 11), (-22, 9), (234, 252), {"x+y": 3})
    p.add(col & ~hole, 1)
    p.paint(col & ~hole & (Z >= 246), 5)
    p.add(cyl(G, "z", (0, -2), 6, (232, 238)), 3)
    p.add(cbox(G, (-24, 24), (18, 24), (190, 232), {"xy": 3}), 3)


# ------------------------------------------------------------------ 머리
def build_head(M):
    p = M.part("Head", (-18, -26, 232), (19, 28, 284), pivot=(0, -2, 241), parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cyl(G, "z", (0, -2), 6, (236, 245)), 3)
    hm = cbox(G, (-10, 10), (-15, 10), (243, 262), {"x-y": (6, 9), "+z-y": (7, 9), "+zx": 3, "-z-y": (5, 5), "x+y": 4, "+z+y": 5})
    p.add(hm, 1)
    p.paint(hm & (Y >= 3), 2)
    # 턱·뺨 가드(각지게)
    jaw = cbox(G, (-12, 12), (-12, 6), (243, 253), {"x-y": (5, 7), "+z-y": (4, 6), "-zx": 3}) & (ax >= 8)
    p.add(jaw, 2)
    fp = hm & (Y <= -9) & (Z <= 249) & (ax <= 6)
    p.paint(fp, 2)
    p.groove(fp & (ax <= 0.5) & (Z <= 247), 4)
    p.paint(hm & (Y <= -9) & (Z <= 245) & (ax <= 3), 3)
    # 바이저 한 줄 (얕은 V) — 눈썹판 그늘 아래
    vz0 = 250 + (ax >= 5) * 1
    slit = (Z >= vz0) & (Z <= vz0 + 1) & (ax <= 9) & (Y <= -6)
    p.cut(slit & (Y <= -11))
    p.add(slit & (Y >= -11) & (Y <= -10) & hm | (slit & (Y >= -11) & (Y <= -10) & (ax <= 8)), 6)
    # 눈썹판: 바이저 위로 튀어나와 그늘 — 엄한 인상
    brow = cbox(G, (-11, 11), (-18, -4), (253, 257), {"x-y": (7, 6), "-z-y": (2, 3), "+z-y": (2, 4)})
    p.add(brow, 1)
    # 볏: 낮게 뒤로 눕는 칼날
    crest = (ax <= 1) & poly(G, "x", [(-15, 256), (-10, 261), (2, 267), (17, 270), (22, 269), (8, 262), (-2, 258)])
    p.add(crest, 1)
    p.paint(crest & (Y >= 13), 2)
    ant = (ax >= 11) & (ax <= 12) & (Y >= 0) & (Y <= 16) & (Z >= 254 + np.floor(Y / 6)) & (Z <= 255 + np.floor(Y / 6))
    p.add(ant, 2)
    p.paint(ant & (Y >= 13), 5)
    p.add(cyl(G, "x", (-2, 249), 4, (-13, 13)) & (ax >= 10), 3)
    p.add(cyl(G, "x", (-2, 249), 2, (-14, 14)) & (ax >= 13), 7)


# ------------------------------------------------------------------ 팔
SHOULDER = (47, 0, 224)
ELBOW = (47, 0, 174)


def build_arm(M):
    p = M.part("ShoulderL", (34, -28, 204), (76, 34, 262), pivot=SHOULDER, parent="Torso")
    G = p.g(); X, Y, Z = G
    sh = cbox(G, (37, 68), (-22, 22), (210, 242),
              {"+z-x": (10, 16), "-z+x": (14, 10), "x-y": 6, "x+y": 6, "+z-y": 6, "+z+y": 6, "+z+x": 4})
    p.add(sh, 1)
    p.paint(sh & (Z <= 222), 2)
    cap = cbox(G, (46, 74), (-25, 25), (238, 246), {"+z-x": (6, 12), "x-y": 7, "x+y": 7, "+z-y": 3, "+z+y": 3, "-z+x": (4, 4)})
    p.add(cap, 1)
    p.groove(cap & (np.abs(Z - 240) <= 0.5) & (X >= 50), 4)
    p.groove(sh & (np.abs(Y + 0) <= 0.5) & (Z <= 236) & (Z >= 212) & (X >= 60), 4)
    up = cbox(G, (68, 72), (-18, 18), (226, 242), {"+x-y": 3, "+x+y": 3, "+x+z": 3, "+x-z": 3})
    lo = cbox(G, (66, 70), (-16, 16), (210, 224), {"+x-y": 3, "+x+y": 3, "+x+z": 2, "+x-z": 3})
    p.add(lo, 3)
    p.add(up, 1)
    p.paint(up & (Y <= -12) & (Z >= 232) & (Z <= 238), 5)
    for z in (213, 217, 221):
        p.groove(lo & (np.abs(Z - z) <= 0.5) & (X >= 70) & (np.abs(Y) <= 10), 6)
    nz = cyl(G, "y", (52, 226), 5, (22, 30)) & ~cyl(G, "y", (52, 226), 3, (26, 31))
    p.add(nz, 7)
    p.add(cyl(G, "y", (52, 226), 3, (26, 26)), 6)
    p.rot = roty(-12)          # 견갑 바깥 끝을 들어 올림(관절 기울기 — 계단 없음)

    a = M.part("UpperArmL", (34, -16, 166), (62, 16, 234), pivot=SHOULDER, parent="Torso")
    G = a.g(); X, Y, Z = G
    a.add(ell(G, (47, 0, 222), (10, 10, 10)), 3)
    a.add(cyl(G, "z", (47, 0), 8, (178, 220)), 3)
    bc = cbox(G, (37, 57), (-12, 10), (186, 208), {"xy": 5, "-zx": 3, "-zy": 3})
    a.add(bc, 1)
    a.paint(bc & (X <= 40), 2)
    a.groove(bc & (np.abs(Z - 197) <= 0.5), 4)
    a.add(cyl(G, "x", (0, 174), 8, (39, 55)), 3)
    a.add(cyl(G, "x", (0, 174), 4, (37, 57)), 7)

    f = M.part("LowerArmL", (30, -20, 84), (70, 28, 190), pivot=ELBOW, parent="UpperArmL")
    G = f.g(); X, Y, Z = G
    ga = cbox(G, (35, 59), (-14, 14), (140, 168), {"xy": 6, "-zx": 3, "-zy": 3, "+zx": 3, "+zy": 3})
    f.add(ga, 1)
    f.paint(ga & (X <= 39), 2)
    wg = cbox(G, (37, 57), (-12, 12), (124, 142), {"xy": 5, "-zx": 2, "-zy": 2})
    f.add(wg, 2)
    f.groove(wg & (np.abs(Z - 133) <= 0.5), 4)
    og = cbox(G, (58, 63), (-10, 20), (126, 184), {"+z-y": (16, 10), "-z+y": (10, 12), "+x-y": 2, "+x+y": 2})
    f.add(og, 1)
    for z0, z1 in ((136, 150), (154, 168)):
        f.paint(og & (X >= 63) & (Y >= -2) & (Y <= -1) & (Z >= z0) & (Z <= z1), 6)
    f.paint(og & (Y >= 17), 3)
    f.add(cyl(G, "z", (47, 0), 7, (118, 126)), 3)
    f.add(box(G, (40, 54), (-10, 10), (102, 120)), 3)
    f.add(cbox(G, (53, 57), (-11, 11), (104, 121), {"+xz": 2, "+xy": 2}), 1)
    for fy in (-9, -4, 1, 6):
        f.add(box(G, (42, 52), (fy, fy + 3), (90, 102)), 3)
        f.add(box(G, (51, 53), (fy, fy + 3), (94, 102)), 2)
        f.add(box(G, (42, 52), (fy, fy + 3), (89, 90)), 4)
    f.add(cbox(G, (37, 42), (-13, -8), (98, 114), {"xy": 1}), 3)
    M.mirror("ShoulderL", "ShoulderR", "Torso")
    M.mirror("UpperArmL", "UpperArmR", "Torso")
    M.mirror("LowerArmL", "LowerArmR", "UpperArmR")


# ------------------------------------------------------------------ 다리
HIP = (20, 0, 150)
KNEE = (21, -1, 98)
ANKLE = (22, 0, 18)


def build_leg(M):
    t = M.part("UpperLegL", (8, -18, 96), (38, 14, 162), pivot=HIP, parent="Pelvis")
    G = t.g(); X, Y, Z = G
    t.add(ell(G, (20, 0, 150), (9, 9, 9)), 3)
    t.add(cbox(G, (14, 28), (-9, 9), (102, 148), {"xy": 3}), 3)
    fp = cbox(G, (12, 30), (-15, -7), (110, 142), {"x-y": 4, "-z-y": (6, 4), "+z-y": 3})
    t.add(fp, 1)
    t.groove(fp & (np.abs(Z - 126) <= 0.5) & (Y < -12), 4)
    op = cbox(G, (28, 33), (-11, 9), (114, 144), {"+xy": 3, "+xz": 3})
    t.add(op, 2)
    t.add(cbox(G, (11, 14), (-8, 6), (118, 138), {"-xz": 2}), 2)

    s = M.part("LowerLegL", (2, -32, 10), (42, 32, 128), pivot=KNEE, parent="UpperLegL")
    G = s.g(); X, Y, Z = G
    s.add(cyl(G, "x", (-1, 98), 9, (12, 30)), 3)
    s.add(cyl(G, "x", (-1, 98), 4, (10, 32)), 7)
    s.add(cbox(G, (14, 28), (-9, 9), (22, 92)), 3)
    us = cbox(G, (9, 33), (-17, 13), (60, 90), {"x-y": 7, "+z-y": 6, "+zx": 3, "-z-y": 3})
    s.add(us, 1)
    ls = cbox(G, (11, 31), (-15, 11), (34, 62), {"x-y": 6, "-z-y": 3})
    s.add(ls, 1)
    bt = cbox(G, (8, 34), (-19, 15), (14, 38), {"x-y": 8, "+zx": 5, "+z-y": 6, "x+y": 4})
    s.add(bt, 1)
    s.groove(us & (np.abs(Z - 75) <= 0.5) & (Y < -10), 4)
    rg = cbox(G, (16, 26), (-20, -16), (40, 72), {"x-y": 2, "-z-y": (4, 2), "+z-y": (4, 2)})
    s.add(rg, 2)
    s.paint(ls & (Y >= -4), 2)
    cf = cbox(G, (12, 30), (10, 28), (44, 88), {"+y-z": (14, 16), "+y+z": (8, 10), "x+y": 4})
    s.add(cf, 2)
    for z in (60, 66, 72):
        s.groove(cf & (np.abs(Z - z) <= 0.5) & (Y >= 24) & (X >= 16) & (X <= 26), 6)
    sd = cbox(G, (33, 36), (-8, 8), (62, 88), {"+xz": 3, "+xy": 2})
    s.add(sd, 2)
    s.paint(sd & (X >= 36) & (np.abs(Y) <= 1) & (Z >= 66) & (Z <= 84), 6)
    kn = cbox(G, (11, 31), (-27, -13), (84, 124), {"+z-y": (14, 9), "x-y": 5, "-z-y": (8, 6), "+zx": 4})
    s.add(kn, 1)
    s.groove(kn & (np.abs(Z - 106) <= 0.5) & (Y <= -22), 4)
    s.paint(kn & (Z <= 92), 2)

    f = M.part("FootL", (4, -44, 0), (40, 28, 30), pivot=ANKLE, parent="LowerLegL")
    G = f.g(); X, Y, Z = G
    f.add(ell(G, (22, 0, 18), (8, 8, 8)), 3)
    f.add(cbox(G, (11, 33), (-38, 18), (0, 2), {"xy": 3}), 4)
    f.add(cbox(G, (12, 32), (-26, 14), (3, 12), {"+z-y": 8, "xy": 4}), 1)
    toe = cbox(G, (13, 31), (-40, -24), (2, 9), {"+z-y": 5, "x-y": 7})
    f.add(toe, 2)
    ins = cbox(G, (14, 30), (-20, -4), (12, 17), {"+z-y": 5, "xz": 2})
    f.add(ins, 1)
    f.groove(ins & (np.abs(Y + 12) <= 0.5), 4)
    f.add(cbox(G, (13, 31), (12, 20), (3, 13), {"+z+y": 5, "x+y": 3}), 2)
    f.add(cbox(G, (18, 26), (18, 25), (1, 7), {"+y+z": 3}), 3)
    for xr in ((9, 13), (31, 35)):
        ag = cbox(G, xr, (-8, 10), (6, 26), {"+zy": 4})
        f.add(ag, 1)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


# ------------------------------------------------------------------ 등짐 + 날개 바인더
WING_HINGE = (24, 40, 226)
WING_SPLAY = 30
WING_LEAN = 22


def build_back(M):
    b = M.part("Backpack", (-34, 16, 164), (35, 52, 242), pivot=(0, 24, 212), parent="Torso")
    G = b.g(); X, Y, Z = G; ax = np.abs(X)
    pk = cbox(G, (-22, 22), (20, 40), (182, 236), {"+yx": 6, "+y+z": 6, "+y-z": 8, "+zx": 4})
    b.add(pk, 1)
    b.paint(pk & (Y >= 36), 2)
    b.groove(pk & (ax <= 0.5) & (Y >= 33), 4)
    for s in (1, -1):
        nz = cyl(G, "z", (s * 11, 31), 6.5, (170, 183)) & ~cyl(G, "z", (s * 11, 31), 4, (170, 176))
        b.add(nz, 7)
        b.add(cyl(G, "z", (s * 11, 31), 4, (176, 177)), 6)
        b.add(cbox(G, (s * 18, s * 30), (30, 46), (216, 236), {"xy": 3}), 3)
    b.add(cyl(G, "y", (24, 226), 5, (28, 48), sym=True), 7)

    w = M.part("WingL", (6, 28, 176), (52, 52, 332), pivot=WING_HINGE, parent="Backpack")
    G = w.g(); X, Y, Z = G
    root = cbox(G, (16, 34), (34, 46), (196, 234), {"xy": 3, "-zx": 4, "+zx": 3})
    w.add(root, 3)
    w.groove(root & (np.abs(Z - 214) <= 0.5), 4)
    for x in (20, 30):
        nz = cyl(G, "z", (x, 40), 4, (186, 197)) & ~cyl(G, "z", (x, 40), 2.2, (186, 191))
        w.add(nz, 7)
        w.add(cyl(G, "z", (x, 40), 2.2, (191, 192)), 6)
    sub = cbox(G, (31, 44), (42, 46), (212, 300), {"+z-x": (12, 12), "-z+x": (8, 8)})
    w.add(sub, 2)
    w.groove(sub & (np.abs(Z - 262) <= 0.5), 4)
    blade = cbox(G, (16, 34), (37, 43), (228, 328), {"+z-x": (16, 16), "+z+x": (3, 3)})
    w.add(blade, 1)
    w.paint(blade & (Z <= 238), 2)
    w.paint(blade & (Z >= 239) & (Z <= 240), 5)
    face = (Y <= 37) | (Y >= 43)
    for z0, z1 in ((248, 266), (272, 290), (296, 308)):
        w.paint(blade & face & (X >= 19) & (X <= 20) & (Z >= z0) & (Z <= z1), 6)
    rib = cbox(G, (27, 30), (36, 44), (240, 304), {"+z-x": (6, 3)})
    w.add(rib, 3)
    w.rot = roty(WING_SPLAY) @ rotx(-WING_LEAN)
    M.mirror("WingL", "WingR", "Backpack")


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
    # A: 흰 + 짙은 회색 + 주황 발광
    "A": {1: (228, 230, 233), 2: (112, 117, 126), 3: (56, 59, 66), 4: (24, 25, 29), 5: (230, 108, 38), 6: (255, 150, 52), 7: (136, 140, 146)},
    # B: 흰 + 검정 + 초록 발광
    "B": {1: (234, 236, 238), 2: (62, 64, 70), 3: (34, 35, 39), 4: (14, 15, 17), 5: (56, 168, 100), 6: (120, 255, 165), 7: (122, 128, 134)},
    # C: 흰 + 남회색 + 청색 발광
    "C": {1: (226, 230, 236), 2: (104, 116, 136), 3: (46, 52, 64), 4: (20, 22, 28), 5: (54, 118, 226), 6: (92, 204, 255), 7: (122, 130, 142)},
}
EMISSIVE = {6}
VIEWS = ((0, 4, "front"), (32, 12, "3/4"), (90, 3, "side"), (150, 14, "back 3/4"))


POSE_A = {  # 미리보기용 자세: 팔 살짝 벌리고 팔꿈치 약간 굽힘, 다리 살짝 벌림
    "UpperArmL": roty(-7), "UpperArmR": roty(7), "ShoulderL": roty(-3), "ShoulderR": roty(3),
    "LowerArmL": rotx(-12), "LowerArmR": rotx(-12),
    "UpperLegL": roty(-3), "UpperLegR": roty(3), "FootL": roty(3), "FootR": roty(-3),
}


def preview(M, sch="A", out="/tmp/claude-0/flag.png", views=VIEWS, ppc=2.6, pose="A"):
    import vox_preview as vp
    B = M.blocks(pose=POSE_A if pose == "A" else pose)
    ims = [vp.render(B, SCHEMES[sch], EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2, ao_amt=0.4) for y, p, _ in views]
    vp.sheet(ims, [v[2] for v in views]).save(out)
    return out


if __name__ == "__main__":
    import sys, time
    t0 = time.time()
    M = build_all()
    print(M.stats(), "%.1fs" % (time.time() - t0))
    preview(M, sys.argv[1] if len(sys.argv) > 1 else "A", sys.argv[2] if len(sys.argv) > 2 else "/tmp/claude-0/flag.png")
    print("done %.1fs" % (time.time() - t0))
