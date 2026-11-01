"""
sniper_v1.py — 저격 기체(Rodin Sniper3)를 펠젠·아엘로 방식 복셀로 이식 (2026-10-29~)

유저(11:32): "Rodin 현버전을 펠젠식으로 이식해줄래? 디테일도 최대한 다 살리고싶어." · 비율 ③ = 다리 1.4배(다리 56%), 머리 꼭대기 268칸.
참고: ref/ref_mesh.npz(Rodin 을 칸 좌표로 옮기고 다리·팔뚝을 곧게 편 것) · 설계도 bp.py · 비교 cmp.py.
방식: Rodin 판 배치·실루엣·색 위치를 따르되, 판마다 칸 정렬 모따기 덩어리로 다시 만든다.
      비스듬한 큰 판·칼날 깃은 똑바로 만들어 파트 회전(rot)으로 기울인다(면에 계단이 안 생김). AI 잡티(두께 불균일·좌우 불균형·얼룩 색)는 따르지 않는다.
변경: 팔이 Rodin 그대로면 손이 엉덩이 높이(어깨→주먹 70칸, 키의 26%)라 위팔 +13 · 팔뚝 +10 → 87칸(HORKOS 108·AELLO 118).
색: 1 흰 주장갑 · 2 짙은 보조 · 3 프레임 · 4 검정 홈 · 5 초록 표식 · 6 초록 발광 · 7 금속 · 8 밝은 회색(옆면)
"""
import numpy as np
import flag_vox as fv
from flag_vox import box, cbox, poly, cyl, ell, rotx, roty, rotz

W1, DK, FR, BK, GM, GL, MT, LG = 1, 2, 3, 4, 5, 6, 7, 8
# 관절(칸) — ref/joints.json 바탕 + 팔 늘림
HIP = (21, -7, 153); KNEE = (21, -7, 90); ANKLE = (21, -7, 16)
WAIST = (0, -6, 200); NECK = (0, -4, 238); PELV = (0, -6, 176)
SHOULDER = (29, -1, 221); ELBOW = (29, -1, 194); WRIST = (29, -1, 150)


def unit(v):
    v = np.asarray(v, float); return v / np.linalg.norm(v)


def frame_from(root, tip, nhint):
    """로컬 +Y = root→tip, 로컬 +X = nhint(직교화), 로컬 +Z = X×Y."""
    ey = unit(np.subtract(tip, root)); ex = np.asarray(nhint, float); ex = unit(ex - (ex @ ey) * ey); ez = np.cross(ex, ey)
    return np.stack([ex, ey, ez], 1), float(np.linalg.norm(np.subtract(tip, root)))


def blade(M, name, parent, root, tip, nhint, prof, thick=2, color=W1, ridge=None, back=None):
    """칼날 판: 로컬 (y=길이 방향, z=폭 방향) 다각형 prof(길이·폭은 0~1 비율 → 실제 길이·폭은 L·w) 을 x 로 thick 칸 밀어냄 → 회전 파트."""
    R, L = frame_from(root, tip, nhint)
    root = np.round(root).astype(int)
    pts = [(root[1] + u * L, root[2] + v) for u, v in prof]
    ys = [q[0] for q in pts]; zs = [q[1] for q in pts]
    x0, x1 = root[0], root[0] + thick - 1
    p = M.part(name, (x0 - 1, int(min(ys)) - 2, int(min(zs)) - 2), (x1 + 3, int(max(ys)) + 3, int(max(zs)) + 3), pivot=tuple(root), parent=parent)
    G = p.g(); X, Y, Z = G
    m = poly(G, "x", pts, rng=(x0, x1))
    p.add(m, color)
    if ridge is not None:      # 바깥면 가운데 한 줄 돋음(접힌 능선)
        rr = [(root[1] + u * L, root[2] + v) for u, v in ridge]
        p.emboss(poly(G, "x", rr, rng=(x1 + 1, x1 + 1)), color)
    if back is not None:       # 안쪽 면에 짙은 판 한 겹(두 장 겹친 칼날)
        rb = [(root[1] + u * L, root[2] + v) for u, v in back]
        p.add(poly(G, "x", rb, rng=(x0 - 1, x0 - 1)), back_color)
    p.rot = R
    return p


back_color = FR


def pair(M, name, fn, *a, **k):
    """왼쪽(L) 만들고 거울로 R."""
    p = fn(M, name + "L", *a, **k)
    par = p.parent
    M.mirror(name + "L", name + "R", par[:-1] + "R" if par and par.endswith("L") else par)
    return p


# ================================================================== 머리
def build_head(M):
    h = M.part("Head", (-14, -24, 226), (15, 16, 262), pivot=NECK, parent="Torso")
    G = h.g(); X, Y, Z = G; ax = np.abs(X)
    h.add(cyl(G, "z", (0, -3), 4.5, (227, 240)), FR)                                          # 목
    h.add(cbox(G, (-8, 8), (-13, 8), (238, 255), {"xy": 3, "+zx": 2}), FR)                     # 속 뼈대
    # 투구(흰): 위가 둥근 돔 — 옆·뒤·앞 위 모서리를 크게 깎음
    h.add(cbox(G, (-9, 9), (-15, 9), (247, 259), {"+zx": 4, "+z-y": 4, "+z+y": 5, "xy": 3, "y+z": 2}), W1)
    h.paint_s((Z >= 257) & (ax <= 2), W1)
    # 이마 가운데 낮은 능선(앞 → 정수리)
    h.emboss((ax <= 1) & (Y <= 2) & (Z >= 252), W1)
    # 바이저 하우징(검정): 앞과 옆을 감쌈, 앞 모서리 45°
    h.add(cbox(G, (-10, 10), (-20, -5), (238, 249), {"x-y": 5, "-z-y": 2, "+z-y": 1}), BK)
    # 큰 조준경(발광): 앞에서 타원 rx 5 · rz 4, 하우징 안에 한 칸 박힘 + 금속 테
    lens = ((X / 5.2) ** 2 + ((Z - 243.5) / 4.2) ** 2 <= 1.0)
    rim = ((X / 6.4) ** 2 + ((Z - 243.5) / 5.4) ** 2 <= 1.0) & ~lens
    h.add(rim & (Y >= -21) & (Y <= -20), FR)
    h.cut(lens & (Y <= -20))
    h.add(lens & (Y >= -20) & (Y <= -19), GL)
    # 턱 판(흰, 조준경 아래)
    h.add(cbox(G, (-4, 4), (-18, -11), (232, 238), {"-z-y": 2, "x-y": 2}), W1)
    # 볼 판(흰): 하우징 옆을 덮는 판, 뒤로 갈수록 높아짐
    h.add(cbox(G, (9, 11), (-13, 3), (237, 249), {"-z-y": 4, "+z-y": 2, "-z+y": 2}) & (Z <= 249 - np.maximum(0, -Y - 6) * 0.5), W1)
    h.add(cbox(G, (-11, -9), (-13, 3), (237, 249), {"-z-y": 4, "+z-y": 2, "-z+y": 2}) & (Z <= 249 - np.maximum(0, -Y - 6) * 0.5), W1)
    # 귀 원판(프레임 + 금속 심) + 뒤쪽 초록 장식
    for s in (1, -1):
        h.add(cyl(G, "x", (-3, 247), 3.5, (11, 12) if s > 0 else (-12, -11)), FR)
        h.add(cyl(G, "x", (-3, 247), 1.6, (13, 13) if s > 0 else (-13, -13)), MT)
        h.add(box(G, (9, 10) if s > 0 else (-10, -9), (5, 7), (243, 248)), FR)
        h.groove(box(G, (10, 10) if s > 0 else (-10, -10), (5, 6), (244, 247)), GL)
    # 뒷머리: 짙은 판 + 가로 홈
    h.add(cbox(G, (-6, 6), (8, 11), (240, 253), {"+y+z": 3, "+yx": 2}), DK)
    h.groove(box(G, (-4, 4), (11, 11), (246, 246)), BK)
    # 깃: 위 긴 칼날 + 아래 짧은 칼날 (뒤·위·바깥)
    FIN = [(0, -2.5), (0, 2.5), (0.55, 1.6), (1.0, 0.0), (0.7, -1.2)]
    FINR = [(0.05, -0.5), (0.05, 0.5), (0.8, 0.3), (0.8, -0.3)]
    for s, sx in (("L", 1), ("R", -1)):
        blade(M, "HFinA" + s, "Head", (7 * sx, -9, 255), (14 * sx, 22, 268), (sx, 0, 0.35), FIN, 2, W1, ridge=FINR)
        blade(M, "HFinB" + s, "Head", (9 * sx, -5, 251), (16 * sx, 15, 258), (sx, 0, 0.3), [(0, -2), (0, 2), (0.6, 1.2), (1, 0), (0.6, -1)], 2, W1)


# ================================================================== 몸통
def build_torso(M):
    t = M.part("Torso", (-26, -28, 198), (27, 16, 246), pivot=WAIST, parent="Pelvis")
    G = t.g(); X, Y, Z = G; ax = np.abs(X)
    t.add(cbox(G, (-12, 12), (-15, 9), (200, 238), {"xy": 4}), FR)                            # 속 뼈대
    t.add(cbox(G, (-8, 8), (-12, 5), (199, 212), {"xy": 3}), DK)                               # 허리(짙은 판)
    t.groove(box(G, (-6, 6), (-13, -12), (204, 204)), BK)
    # 가슴 V 판(흰): 앞에서 윗변 z 233 · 옆 z 218 → 아래 V 꼭지 (0,207). 옆에서 앞면 y -24, 위·아래로 물러남
    front = poly(G, "y", [(0, 207), (16, 219), (17, 233), (6, 235), (0, 233)], sym=True)
    side = poly(G, "x", [(-24, 214), (-24, 228), (-20, 234), (-6, 236), (-6, 207), (-17, 207)])
    t.add(front & side, W1)
    # 안쪽 V 단(한 칸 돋음) + 초록 역삼각 코어(홈 속 발광)
    inner = poly(G, "y", [(0, 211), (10, 220), (10, 229), (0, 230)], sym=True)
    t.emboss(inner & (Y <= -18), W1)
    core = poly(G, "y", [(0, 218), (5, 225), (5, 226), (0, 226)], sym=True) & (Y <= -18)
    t.groove(core, GL)
    t.groove(core & (Y <= -18), GL)
    # 가슴 옆판(짙은) — 어깨 쪽으로 꺾여 들어감
    t.add(cbox(G, (14, 21), (-18, 4), (214, 236), {"-zx": 4, "+zx": 3, "x-y": 3}), DK)
    t.add(cbox(G, (-21, -14), (-18, 4), (214, 236), {"-zx": 4, "+zx": 3, "-x-y": 3}), DK)
    # 어깨 소켓(옆 원판)
    for s in (1, -1):
        t.add(cyl(G, "x", (-4, 225), 8, (21, 23) if s > 0 else (-23, -21)), FR)
        t.add(cyl(G, "x", (-4, 225), 4.5, (24, 24) if s > 0 else (-24, -24)), BK)
    # 깃(흰): 목 옆에서 솟는 판 두 장, 앞은 V 로 열림
    t.add(poly(G, "y", [(5, 233), (13, 236), (13, 243), (9, 245), (5, 239)], sym=True) & (Y >= -15) & (Y <= -2), W1)
    t.add(cbox(G, (-12, 12), (-2, 9), (234, 243), {"+zx": 3, "+z+y": 2}) & (ax >= 5), W1)
    # 등판(흰) + 긴 초록 홈
    bp = poly(G, "z", [(-8, 6), (8, 6), (7, 12), (-7, 12)]) & poly(G, "y", [(0, 206), (8, 214), (8, 236), (0, 238)], sym=True)
    t.add(bp, W1)
    t.groove((ax <= 1.5) & (Z >= 212) & (Z <= 227) & (Y >= 11), GL)
    t.add(cbox(G, (8, 18), (3, 9), (216, 236), {"+zx": 3, "-zx": 3}), W1)                     # 견갑 판
    t.add(cbox(G, (-18, -8), (3, 9), (216, 236), {"+z-x": 3, "-z-x": 3}), W1)


def build_back_fins(M):
    """등 칼날 깃: 한쪽에 큰 날 2 + 작은 날 1 (뒤·바깥·아래로 부채꼴)."""
    PROF = [(0, -3.5), (0, 3.5), (0.45, 3.0), (1.0, 0.0), (0.55, -2.0)]
    RID = [(0.05, -0.6), (0.05, 0.6), (0.75, 0.4), (0.75, -0.4)]
    for s, sx in (("L", 1), ("R", -1)):
        blade(M, "BFinA" + s, "Torso", (10 * sx, 9, 230), (16 * sx, 44, 238), (sx, 0, 0.4), PROF, 2, W1, ridge=RID)
        blade(M, "BFinB" + s, "Torso", (13 * sx, 7, 225), (31 * sx, 34, 216), (sx * 0.3, 0, 1.0), PROF, 2, W1, ridge=RID)
        blade(M, "BFinC" + s, "Torso", (15 * sx, 4, 218), (31 * sx, 18, 208), (sx * 0.2, 0, 1.0), [(0, -2.5), (0, 2.5), (0.6, 1.8), (1, 0), (0.6, -1.2)], 2, W1)


# ================================================================== 어깨 장갑 · 팔
def build_arm(M):
    # 어깨 장갑(흰): 큰 상자 + 바깥 칼날 하나
    s = M.part("ShoulderL", (14, -16, 210), (46, 18, 246), pivot=SHOULDER, parent="Torso")
    G = s.g(); X, Y, Z = G
    s.add(cbox(G, (19, 41), (-13, 14), (214, 242), {"+zx": 6, "-zx": 4, "x-y": 4, "x+y": 4, "+z-y": 3}), W1)
    s.add(cbox(G, (20, 36), (-11, 12), (211, 215), {"xy": 3}), FR)                              # 아래 짙은 테
    s.groove(box(G, (25, 41), (-14, 14), (226, 226)), FR)                                       # 위·아래 판 경계
    s.add(cbox(G, (36, 43), (-6, 6), (217, 236), {"+zx": 3, "-zx": 3}), DK)                    # 바깥 짙은 판
    s.groove(box(G, (44, 44), (-1, 1), (221, 231)), GL)                                         # 바깥 발광 틈
    blade(M, "SFinL", "ShoulderL", (38, 6, 236), (46, 30, 222), (1, 0, 0.6),
          [(0, -3), (0, 3), (0.5, 2.2), (1, 0), (0.5, -2)], 2, W1, ridge=[(0.05, -0.5), (0.05, 0.5), (0.7, 0.3), (0.7, -0.3)])
    # 위팔: 짙은 관절 + 흰 판
    u = M.part("UpperArmL", (20, -11, 188), (39, 10, 224), pivot=SHOULDER, parent="Torso")
    G = u.g(); X, Y, Z = G
    u.add(cbox(G, (24, 34), (-6, 5), (194, 220), {"xy": 3}), FR)
    u.add(cbox(G, (23, 35), (-9, 8), (199, 214), {"xy": 3, "-zx": 2, "+zx": 2}), W1)
    u.add(cyl(G, "x", (-1, 194), 5.5, (23, 35)), FR)                                            # 팔꿈치 축
    # 팔뚝: 큰 흰 판(바깥 초록 점 2) + 짙은 손목 + 흰 소매 + 손
    f = M.part("LowerArmL", (19, -13, 126), (42, 12, 200), pivot=ELBOW, parent="UpperArmL")
    G = f.g(); X, Y, Z = G
    f.add(cbox(G, (23, 35), (-6, 6), (150, 194), {"xy": 3}), FR)
    f.add(cbox(G, (22, 38), (-11, 9), (160, 191), {"xy": 4, "+z-y": 3, "-zx": 3, "-z-y": 2}), W1)
    f.add(cbox(G, (38, 39), (-7, 6), (163, 188), {"y+z": 2, "y-z": 2}), W1)                      # 바깥 한 단
    f.groove(box(G, (22, 39), (-12, 10), (176, 176)), FR)                                        # 판 경계
    for zc in (183, 170):
        f.groove(((Y + 1) ** 2 + (Z - zc) ** 2 <= 4.5) & (X >= 39), GL)
    f.add(cbox(G, (24, 34), (-9, 7), (143, 152), {"xy": 3, "-z-y": 2}), W1)                      # 소매(흰)
    f.add(cbox(G, (25, 33), (-6, 5), (139, 144), {"xy": 2}), FR)                                 # 손목
    f.add(cbox(G, (24, 34), (-8, 6), (127, 140), {"xy": 3, "-zx": 2, "-z-y": 2}), FR)            # 주먹
    f.add(cbox(G, (23, 35), (-10, -6), (129, 138), {"x-y": 2}), BK)                              # 손가락 마디
    for n in ("ShoulderL", "UpperArmL", "LowerArmL", "SFinL"):
        pass
    M.mirror("ShoulderL", "ShoulderR", "Torso"); M.mirror("SFinL", "SFinR", "ShoulderR")
    M.mirror("UpperArmL", "UpperArmR", "Torso"); M.mirror("LowerArmL", "LowerArmR", "UpperArmR")


def build_pelvis_stub(M):
    p = M.part("Pelvis", (-20, -20, 170), (21, 12, 202), pivot=PELV)
    G = p.g()
    p.add(cbox(G, (-12, 12), (-14, 8), (176, 200), {"xy": 4}), FR)


def build_upper():
    M = fv.Model()
    build_pelvis_stub(M); build_torso(M); build_head(M); build_back_fins(M); build_arm(M)
    return M


PAL = {1: (226, 228, 232), 2: (66, 70, 78), 3: (40, 43, 50), 4: (16, 17, 20), 5: (40, 160, 96), 6: (90, 255, 160), 7: (140, 146, 156), 8: (180, 184, 192)}
EMISSIVE = {6}
