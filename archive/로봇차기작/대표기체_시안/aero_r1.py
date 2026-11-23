"""
aero_r1.py — Aero 리메이크 r1: 맹금형 경량 기체 + 접힌 칼날 날개 (2026-10-26)

결정(10-26 11:44): 등 = 접힌 칼날 날개(엔진 포드 대체) · 체형 = 새처럼 다리를 길게.
규칙 메모 = docs/aero_r1.md 1절(레퍼런스 R1~R8) + 기체디자인_스타일가이드.md.
칸 = 0.05 Blender. +X = 기체 왼쪽 · −Y = 정면 · +Z = 위 · 바닥 z=0.
색: 1 주장갑(큰 판) · 2 보조장갑 · 3 프레임 · 4 검정(홈) · 5 강조 표식 · 6 발광 · 7 금속

형태 원칙(판 a·b 에서 배움):
  - 큰 면은 축에 맞춰 평평하게, 경사는 45° 모따기만. 1:2 경사를 큰 면에 쓰면 계단 줄무늬가 된다(판 b 정강이·가슴).
  - 비스듬한 판(가슴 셰브론·날개·스커트·어깨)은 세워 만들고 파트 회전으로 기울인다 → 면이 평평하게 남는다.
  - 날개는 가는 깃 여러 장 = 고드름처럼 지저분(판 b) → 넓은 칼날 두 장, 긴 변은 직선, 끝만 비스듬히.
"""
import numpy as np

import flag_vox as fv
from flag_vox import box, cbox, poly, cyl, ell, rotx, roty, rotz

# 관절 (칸) — 엉덩이 64% · 정강이 > 허벅지
HIP = (17, 0, 166)
KNEE = (19, -2, 104)
ANKLE = (20, 0, 26)
SHOULDER = (40, 0, 228)
ELBOW = (40, 0, 184)
WING = (22, 32, 236)

WING_ROT = roty(4) @ rotx(14) @ rotz(38)


# ------------------------------------------------------------------ 골반
def build_pelvis(M):
    p = M.part("Pelvis", (-34, -30, 128), (35, 30, 188), pivot=(0, 0, 172))
    G = p.g(); X, Y, Z = G
    p.add(cbox(G, (-14, 14), (-13, 13), (150, 182), {"xy": 4, "-zx": (12, 12)}), 3)
    for s in (1, -1):
        p.add(cyl(G, "x", (0, 166), 7, (s * 8, s * 24)), 3)
        p.add(cyl(G, "x", (0, 166), 3, (s * 6, s * 26)), 7)
    p.add(cbox(G, (-19, 19), (-16, 15), (174, 184), {"xy": 5, "-zx": (3, 3)}), 2)          # 허리띠
    p.add(cbox(G, (-6, 6), (-18, -12), (152, 180), {"-zx": (6, 6), "x-y": 2, "-z-y": (3, 3)}), 3)   # 가운데 앞 가리개
    # 앞 스커트: 길고 좁은 칼날 — 세워 만들고 八 로 기울임
    f = M.part("SkirtFL", (0, -30, 120), (26, -8, 184), pivot=(11, -19, 180), parent="Pelvis")
    G = f.g()
    f.add(poly(G, "y", [(5, 180), (17, 180), (17, 158), (11, 146), (5, 158)], rng=(-22, -19)), 1)
    f.add(poly(G, "y", [(7, 178), (15, 178), (15, 160), (11, 152), (7, 160)], rng=(-18, -17)), 3)
    f.rot = roty(-7) @ rotx(-10)
    # 옆 스커트: 엉덩이 바깥 작은 판
    s_ = M.part("SkirtSL", (20, -18, 136), (36, 20, 184), pivot=(27, 0, 180), parent="Pelvis")
    G = s_.g()
    s_.add(poly(G, "x", [(-11, 180), (11, 180), (11, 160), (4, 146), (-11, 160)], rng=(27, 29)), 2)
    s_.add(poly(G, "x", [(-8, 178), (8, 178), (8, 162), (-8, 162)], rng=(25, 26)), 3)
    s_.rot = roty(-10)
    M.mirror("SkirtFL", "SkirtFR", "Pelvis")
    M.mirror("SkirtSL", "SkirtSR", "Pelvis")
    # 뒤 스커트: 꼬리 깃 한 장(가운데)
    t = M.part("SkirtB", (-14, 6, 118), (15, 30, 186), pivot=(0, 14, 180), parent="Pelvis")
    G = t.g()
    t.add(poly(G, "y", [(0, 140), (10, 150), (10, 180), (0, 180)], rng=(14, 16), sym=True), 2)
    t.add(poly(G, "y", [(0, 130), (6, 142), (6, 176), (0, 176)], rng=(17, 18), sym=True), 1)
    t.rot = rotx(24)


# ------------------------------------------------------------------ 몸통
def build_torso(M):
    p = M.part("Torso", (-42, -40, 172), (43, 36, 252), pivot=(0, 0, 182), parent="Pelvis")
    G = p.g(); X, Y, Z = G
    p.add(cbox(G, (-11, 11), (-10, 11), (176, 200), {"xy": 4}), 3)                       # 허리 마디
    p.add(cbox(G, (-9, 9), (-15, -9), (179, 188), {"xy": 2, "-z-y": (3, 3)}), 3)          # 배 2단(위가 덮음, 짙게 → V 몸통)
    p.add(cbox(G, (-11, 11), (-17, -9), (188, 198), {"xy": 2, "-z-y": (3, 3)}), 3)
    for s in (1, -1):
        p.add(cbox(G, (s * 10, s * 15), (-6, 8), (184, 202), {"xy": 2}), 3)               # 옆구리 프레임
    core = cbox(G, (-23, 23), (-16, 17), (198, 238), {"x-y": 6, "x+y": 6, "-zx": (14, 8), "+zx": 4})
    p.add(core, 3)                                                                          # 몸통 속 = 프레임(짙게)
    for s in (1, -1):
        p.add(cbox(G, (s * 15, s * 25), (-12, 13), (208, 234), {"xy": 3, "-zx": 3}), 2)   # 옆구리 판(팔 밑)
    p.add(cbox(G, (-14, 14), (-21, -14), (222, 240), {"x-y": 3, "+z-y": 3}), 2)          # 셰브론 V 홈 속 윗가슴
    col = cbox(G, (-15, 15), (-6, 18), (234, 246), {"+z-y": (8, 8), "+zx": 5, "x-y": 4})
    hole = cbox(G, (-8, 8), (-30, 12), (238, 256), {"x+y": 3})
    p.add(col & ~hole, 2)                                                                   # 목 깃(뒤가 높음)
    p.add(cbox(G, (-34, 34), (-12, 14), (226, 236), {"+zx": 6, "xy": 3}) & ~core, 3)        # 어깨 다리
    p.add(cbox(G, (-22, 22), (18, 24), (200, 236), {"xy": 3}), 3)                         # 등판
    # 가슴 셰브론: 평평한 판 두 장을 용골 선에서 만나게(위에서 V), 위는 뒤로 누움
    # 앞면은 평평(축 정렬) — 1:2 쐐기면은 줄무늬가 됐다(판 b). V 는 판의 윤곽(변)으로만, 용골은 가운데 한 칸 돋을 줄로
    g = M.part("ChestPlate", (-30, -30, 200), (31, -12, 246), pivot=(0, -22, 220), parent="Torso")
    G = g.g(); X, Y, Z = G; ax = np.abs(X)
    band = (Z >= 205 + 0.5 * ax) & (Z <= 225 + 0.5 * ax) & (ax <= 27) & (Y >= -25) & (Y <= -17)
    band &= cbox(G, (-27, 27), (-25, -17), (200, 246), {"x-y": 5})
    g.add(band, 1)
    g.add(band & (ax <= 1) & (Y <= -25), 1)
    g.emboss(box(G, (-1, 1), (-27, -26), (200, 246)), 1)                                   # 용골(가운데 돋을 줄)


# ------------------------------------------------------------------ 머리 (작은 쐐기 + 부리 마스크 + 뒤로 누운 볏)
def build_head(M):
    p = M.part("Head", (-16, -36, 232), (17, 44, 276), pivot=(0, -4, 240), parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cyl(G, "z", (0, -2), 5, (236, 246)), 3)
    side = poly(G, "x", [(8, 242), (8, 258), (2, 262), (-12, 262), (-16, 258), (-14, 255), (-26, 249), (-12, 242), (4, 241)])
    taper = ax <= 10.5 - 0.5 * np.maximum(0, -Y - 8)         # 위에서 1:2 로 좁아져 부리 끝
    chin = ax <= 10.5 - np.maximum(0, 251 - Z)                # 앞에서 아래가 45° 로 모이는 V 턱
    hd = side & taper & chin
    p.add(hd, 2)
    p.paint(hd & (Z >= 257) & (Y >= -4), 3)       # 정수리 뒤쪽만 짙게(윗면 전체를 칠하면 모자로 읽힘 — 판 f)
    p.paint(hd & (Y >= 4), 3)                      # 뒤통수 프레임
    eye = (ax >= 2) & (ax <= 7) & (Z >= 251 + 0.5 * (ax - 2)) & (Z <= 252.5 + 0.5 * (ax - 2))
    p.cut(eye & (Y <= -10))
    p.add(eye & (Y >= -11) & (Y <= -10) & hd, 6)
    # 옆 볏: 머리 옆면에 붙어 뒤로 수평으로 뻗음 — 머리 윗선 위로 안 솟게(솟으면 귀, 가이드 1-5 / 판 a~e 에서 재확인)
    for s in (1, -1):
        rng = (9, 11) if s > 0 else (-11, -9)
        p.add(poly(G, "x", [(-12, 260), (24, 258), (30, 254), (-8, 252)], rng=rng), 1)


# ------------------------------------------------------------------ 팔
def build_arm(M):
    sh = M.part("ShoulderL", (26, -24, 198), (62, 40, 262), pivot=SHOULDER, parent="Torso")
    G = sh.g()
    # 작고 단단한 덩어리 + 바깥 위 45° + 뒤 위 모서리를 뒤로 뺀 끝. 바깥이 들리게 12°
    blk = cbox(G, (33, 53), (-14, 22), (216, 244), {"+z+x": 8, "x-y": 4, "-z+y": (16, 14), "-zx": 4, "+z-y": 4})
    sh.add(blk, 1)
    sh.add(cbox(G, (44, 54), (-11, 11), (206, 218), {"xy": 3, "-z+x": 4}), 2)
    sh.add(cbox(G, (33, 42), (-12, 12), (212, 232), {"xy": 3}), 3)
    sh.rot = roty(-12)

    a = M.part("UpperArmL", (28, -14, 176), (53, 14, 240), pivot=SHOULDER, parent="Torso")
    G = a.g()
    a.add(ell(G, SHOULDER, (9, 9, 9)), 3)
    a.add(cyl(G, "z", (40, 0), 7, (190, 222)), 3)
    a.add(cbox(G, (31, 49), (-10, 9), (194, 214), {"xy": 4, "-zx": 3, "-zy": 3}), 2)
    a.add(cyl(G, "x", (0, 184), 8, (33, 47)), 3)
    a.add(cyl(G, "x", (0, 184), 4, (31, 49)), 7)

    f = M.part("LowerArmL", (28, -16, 110), (54, 30, 200), pivot=ELBOW, parent="UpperArmL")
    G = f.g()
    f.add(cbox(G, (34, 46), (-8, 8), (140, 178), {"xy": 3}), 3)
    f.add(cbox(G, (33, 47), (-11, 6), (146, 176), {"xy": 4, "-zx": 2, "-z-y": 4}), 2)
    # 팔뚝 칼깃: 바깥면에 붙어 팔꿈치 뒤로 솟는 날(긴 변 직선, 끝만 비스듬)
    f.add(poly(G, "x", [(-8, 146), (4, 146), (22, 192), (14, 192), (-8, 160)], rng=(47, 50)), 1)
    f.add(box(G, (34, 46), (-8, 8), (134, 142)), 3)                          # 손목
    f.add(cbox(G, (33, 47), (-10, 12), (116, 135), {"xy": 3, "-zx": 2}), 3)
    f.add(cbox(G, (32, 48), (-12, -6), (120, 133), {"x-y": 2, "-z-y": 2}), 3)  # 손등 판(프레임색 — 손은 기계로)
    for fy in (-4, 1, 6):
        f.add(box(G, (35, 45), (fy, fy + 3), (113, 116)), 3)
    M.mirror("ShoulderL", "ShoulderR", "Torso")
    M.mirror("UpperArmL", "UpperArmR", "Torso")
    M.mirror("LowerArmL", "LowerArmR", "UpperArmR")


# ------------------------------------------------------------------ 다리 (길고 가늘게, 무릎·발끝 뾰족)
def build_leg(M):
    t = M.part("UpperLegL", (2, -22, 98), (34, 20, 178), pivot=HIP, parent="Pelvis")
    G = t.g(); X, Y, Z = G
    t.add(ell(G, HIP, (9, 9, 9)), 3)
    t.add(cbox(G, (9, 25), (-9, 9), (110, 160), {"xy": 4}), 3)
    th = cbox(G, (6, 29), (-13, 2), (118, 158), {"xy": 4, "-z-y": 6, "+z-y": 6, "+zx": 3, "-zx": (24, 3)})
    th &= Z >= 118 + np.abs(X - 17.5)                                                      # 아래 끝을 무릎 쪽 V 로
    t.add(th, 2)
    t.add(poly(G, "x", [(-10, 152), (8, 152), (8, 134), (-10, 125)], rng=(28, 30)), 1)    # 바깥 깃판

    s = M.part("LowerLegL", (2, -36, 20), (38, 32, 136), pivot=KNEE, parent="UpperLegL")
    G = s.g(); X, Y, Z = G
    s.add(cyl(G, "x", (-2, 104), 9, (10, 28)), 3)
    s.add(cyl(G, "x", (-2, 104), 4, (8, 30)), 7)
    s.add(cbox(G, (12, 26), (-9, 8), (34, 100), {"xy": 3}), 3)                              # 정강이 뼈대(옆으로 드러남)
    s.add(cbox(G, (10, 28), (-14, -7), (64, 94), {"x-y": 4, "-z-y": 3, "+z-y": 4}), 2)       # 윗 정강이 판
    lo = cbox(G, (9, 29), (-16, -8), (40, 70), {"x-y": 4, "+z-y": 3}) & (Z <= 70 - np.abs(X - 19))
    s.add(lo, 1)                                                                            # 아래 정강이 보호대(위가 뾰족, 한 단 앞)
    s.add(cbox(G, (11, 27), (4, 20), (44, 96), {"+y+z": (14, 8), "+y-z": (10, 6), "x+y": 4}), 2)   # 종아리(뒤로 불룩)
    s.cut(box(G, (14, 24), (16, 20), (52, 58)))                                            # 종아리 추진기 홈
    s.add(box(G, (15, 23), (15, 15), (53, 57)), 6)
    kn = poly(G, "x", [(-11, 90), (-19, 98), (-28, 116), (-26, 117), (-17, 112), (-10, 105)], rng=(10, 28))
    kn = kn & (np.abs(X - 19) <= 9 - np.maximum(0, -Y - 20))                               # 앞에서 45° 로 모임
    s.add(kn, 1)
    s.add(cbox(G, (7, 31), (-15, 15), (22, 42), {"xy": 5, "+zx": (6, 3), "+z-y": 3}), 2)     # 발목 덮개(아래로 벌어짐)
    s.add(cyl(G, "x", (0, 26), 7, (12, 28)), 3)

    f = M.part("FootL", (4, -54, 0), (36, 32, 36), pivot=ANKLE, parent="LowerLegL")
    G = f.g(); X, Y, Z = G
    f.add(ell(G, ANKLE, (7, 7, 7)), 3)
    f.add(cbox(G, (9, 31), (-40, 24), (0, 3), {"xy": 3, "x-y": (6, 10)}), 4)
    f.add(cbox(G, (9, 31), (-28, 20), (3, 16), {"+z-y": 8, "x-y": 4, "+zx": 3}), 2)
    toe = poly(G, "z", [(9, -30), (20, -52), (31, -30), (31, -20), (9, -20)], rng=(2, 11))
    toe = toe & (Z <= 11 - 0.5 * np.maximum(0, -Y - 30))
    f.add(toe, 1)
    f.add(cbox(G, (14, 26), (16, 29), (2, 14), {"+z+y": (8, 10), "x+y": 4}), 1)            # 뒤꿈치 박차
    f.add(cbox(G, (12, 28), (-22, -2), (14, 20), {"+z-y": 5}), 1)                          # 발등
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


# ------------------------------------------------------------------ 등짐 + 날개
def build_back(M, wing_rot=None):
    b = M.part("Backpack", (-30, 14, 176), (31, 50, 262), pivot=(0, 22, 214), parent="Torso")
    G = b.g()
    b.add(cbox(G, (-20, 20), (18, 36), (190, 246), {"+yx": 6, "+y-z": 8, "+y+z": 6, "+zx": 6}), 2)
    b.add(cbox(G, (-5, 5), (34, 40), (200, 244), {"+yx": 3, "+y-z": 6, "+y+z": 4}), 1)      # 등 용골(가운데 한 줄)
    for s in (1, -1):
        b.add(cyl(G, "z", (s * 11, 28), 6, (182, 192)) & ~cyl(G, "z", (s * 11, 28), 4, (182, 189)), 7)
        b.add(cyl(G, "z", (s * 11, 28), 4, (189, 190)), 6)                                # 노즐 깊은 속만 발광
        b.add(cbox(G, (s * 16, s * 27), (24, 40), (228, 244), {"xy": 2}), 3)              # 날개 경첩 받침
        b.add(cyl(G, "y", (s * 22, 236), 4, (22, 42)), 7)

    # 날개: 넓은 칼날 두 장(앞 = 주 날, 뒤 = 보조 날이 바깥·아래로 비어져 나옴)
    w = M.part("WingL", (14, 26, 80), (60, 44, 280), pivot=WING, parent="Backpack")
    G = w.g()
    w.add(poly(G, "y", [(28, 250), (50, 262), (50, 140), (28, 86)], rng=(36, 39)), 1)        # 뒤 판 = 주 날(등 카메라가 보는 면)
    w.add(poly(G, "y", [(20, 250), (36, 262), (36, 160), (20, 112)], rng=(33, 35)), 2)       # 앞 판 = 덮깃
    w.add(cbox(G, (18, 30), (30, 39), (232, 254), {"+zx": 4, "xy": 2}), 3)                # 날개 손목(경첩 뭉치)
    w.add(box(G, (22, 25), (36, 38), (150, 236)), 3)                                       # 날개 뼈대(뒤 판 안쪽)
    w.rot = wing_rot if wing_rot is not None else WING_ROT
    M.mirror("WingL", "WingR", "Backpack")


def build_all(wing_rot=None):
    M = fv.Model()
    build_pelvis(M)
    build_torso(M)
    build_head(M)
    build_arm(M)
    build_leg(M)
    build_back(M, wing_rot)
    return M


SCHEMES = {
    "A": {1: (222, 118, 40), 2: (226, 226, 222), 3: (64, 68, 76), 4: (20, 21, 24), 5: (200, 40, 48), 6: (255, 214, 90), 7: (138, 144, 150)},
    "B": {1: (228, 228, 224), 2: (222, 118, 40), 3: (64, 68, 76), 4: (20, 21, 24), 5: (200, 40, 48), 6: (255, 214, 90), 7: (138, 144, 150)},
    "C": {1: (206, 204, 196), 2: (78, 82, 88), 3: (46, 48, 52), 4: (22, 23, 25), 5: (214, 110, 34), 6: (255, 150, 60), 7: (122, 126, 130)},
}
EMISSIVE = {6}
STANCE = {
    "UpperArmL": roty(-9), "UpperArmR": roty(9), "ShoulderL": roty(-3), "ShoulderR": roty(3),
    "LowerArmL": rotx(-14), "LowerArmR": rotx(-10),
    "UpperLegL": roty(-3) @ rotx(-6), "UpperLegR": roty(3) @ rotx(-4),
    "LowerLegL": rotx(10), "LowerLegR": rotx(8), "FootL": rotx(-4), "FootR": rotx(-4),
}
VIEWS = ((0, 4, "front"), (30, 6, "3/4"), (90, 2, "side"), (150, 12, "back 3/4"), (180, 14, "back"))


def preview(M, sch="A", out="aero.png", views=VIEWS, ppc=2.6, pose=None, ao=0.5, skip=()):
    import vox_preview as vp
    B = M.blocks(pose=STANCE if pose is None else pose, skip=skip)
    ims = [vp.render(B, SCHEMES[sch], EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2, ao_amt=ao) for y, p, _ in views]
    vp.sheet(ims, [v[2] for v in views]).save(out)
    return out


if __name__ == "__main__":
    import sys, time
    t0 = time.time()
    M = build_all()
    preview(M, sys.argv[2] if len(sys.argv) > 2 else "A", sys.argv[1] if len(sys.argv) > 1 else "aero.png")
    print("done %.1fs" % (time.time() - t0))
