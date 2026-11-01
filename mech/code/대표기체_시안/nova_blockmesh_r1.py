"""
nova_mesh.py — PROJECT : NOVA 재현 (모따기 블록 메시, 2026-10-25 20:47~)  v2: 덩어리 블록 질감

컨셉 시트(GPT 생성, 샌드웨이퍼 제공)의 정면 직교도에서 잰 비율(1.545칸/px, 머리 꼭대기 258 기준):
  안테나 끝 274 · 어깨 꼭대기 ≈ 머리 꼭대기 · 어깨 바깥 ±62 · 가슴 위 249 · 허리 196~212 ·
  가랑이 아래 146 · 엉덩이 관절 166 · 무릎 100 · 발목 34
칸 = 0.05 Blender. +X = 기체 왼쪽, -Y = 정면, +Z = 위.
색: 1 웜 화이트 2 웜 그레이 3 건메탈 4 남흑 5 헬멧 쿨그레이 6 주황 발광 7 총 회색 8 총 짙은 회색
"""
import numpy as np

import blockmesh as bm
from blockmesh import rotx, roty, rotz

F = np.diag([-1.0, 1, 1])


def _mir_kw(kw):
    kw2 = dict(kw)
    if kw2.get("R") is not None:
        kw2["R"] = F @ kw2["R"] @ F
    if kw2.get("about") is not None:
        a = kw2["about"]; kw2["about"] = (-a[0], a[1], a[2])
    for key in ("top", "front"):
        if kw2.get(key) is not None:
            t = list(kw2[key]) + [0, 0]
            kw2[key] = (t[0], t[1], -t[2], t[3])
    if kw2.get("out") is not None:
        o = kw2["out"]; kw2["out"] = (-o[0], o[1], o[2])
    return kw2


def sym(p, x, y, z, **kw):
    """좌우 한 쌍(+x 쪽 좌표로 주면 -x 쪽을 거울로)."""
    p.box(x, y, z, **kw)
    p.box((-x[1], -x[0]), y, z, **_mir_kw(kw))


TEX = dict(notch=0.45, step=0.45, gap=1.7, var=0.4, alt=2, alt_p=0.22)


def ch(p, x, y, z, **kw):
    k = dict(TEX); k.update(kw)
    return p.chunk(x, y, z, **k)


def symchunk(p, x, y, z, **kw):
    k = dict(TEX); k.update(kw); kw = k
    made = p.chunk(x, y, z, **kw)
    for blk in made:
        p.blocks.append(bm.Block(blk.pts * np.array([-1, 1, 1]), blk.col))


# ------------------------------------------------------------------ 골반
def build_pelvis(M):
    p = M.part("Pelvis", pivot=(0, 0, 176))
    p.box((-14, 14), (-11, 11), (156, 200), col=4, b=2)
    p.box((-5, 5), (-22, -9), (146, 186), col=1, b=2.2, top=(2.2, 1.0))          # 가랑이: 아래로 좁아짐
    p.box((-3, 3), (-23.5, -21), (160, 176), col=3, b=0.8)
    p.box((-13, 13), (-20, -9), (186, 198), col=2, b=1.6)
    symchunk(p, (11, 25), (-20, -12), (168, 198), col=1, b=1.6, n=(1, 1, 2), seed=3, R=roty(-10) @ rotx(-8), jit=1.0)
    symchunk(p, (25, 34), (-15, 13), (158, 198), col=1, b=1.8, n=(1, 2, 2), seed=4, out=(1, 0, 0), alt=2, alt_p=0.35, R=roty(-12))
    p.box((-12, 12), (10, 20), (160, 197), col=2, b=1.8, R=rotx(8))


# ------------------------------------------------------------------ 몸통 (v4: 폭 ±28, 아래로 V 테이퍼, 어깨와 틈)
def build_torso(M):
    p = M.part("Torso", pivot=(0, 0, 198), parent="Pelvis")
    p.box((-12, 12), (-11, 11), (190, 212), col=4, b=2)
    p.box((-7, 7), (-15, -10), (192, 200), col=3, b=1.2)
    p.box((-8.5, 8.5), (-16.5, -10), (200, 209), col=1, b=1.3)
    sym(p, (8, 16), (-13, 8), (194, 210), col=3, b=1.2, R=rotz(6))
    p.box((-22, 22), (-18, 18), (206, 246), col=3, b=3, top=(1.25, 1.0))            # 가슴 속: 아래가 좁음(V)
    # 흉판: 바깥 끝 뒤로, 아래 안쪽으로
    symchunk(p, (4, 27), (-28, -13), (220, 247), col=1, b=2.6, n=(1, 1, 1), seed=11, jit=1.5, tilt=3, gap=1.6, notch=0.0, step=1.0, alt=None,
             R=rotz(12) @ rotx(-6), about=(16, -20, 232), top=(1, 1))
    symchunk(p, (4, 20), (-25, -13), (206, 220), col=1, b=2.0, n=(1, 1, 1), seed=14, jit=1.2, tilt=3, R=rotz(12) @ roty(-14),
             about=(12, -19, 213), alt=None)
    # 가운데 코어: 짙은 홈 + 세로 주황, 위아래 흰 장갑
    p.box((-5, 5), (-27, -14), (208, 238), col=4, b=1.2)
    p.box((-2.3, 2.3), (-28.4, -26), (212, 235), col=6, b=0.5)
    p.box((-6, 6), (-29, -23), (203, 211), col=1, b=1.6, front=(0.7, 1.0))
    p.box((-5, 5), (-28, -24), (236, 241), col=1, b=1.2)
    # 깃(머리 양옆, 낮게)·목
    p.box((-6, 6), (-8, 8), (240, 250), col=4, b=1.5)
    sym(p, (8, 18), (-13, 8), (238, 245), col=1, b=1.6, R=rotz(-12))
    symchunk(p, (17, 28), (-17, 15), (232, 249), col=1, b=2.2, n=(1, 2, 1), seed=13, out=(0, 0, 1), jit=1.4, alt=2, alt_p=0.3)
    sym(p, (22, 28), (-12, 12), (208, 232), col=3, b=1.5)
    p.box((-20, 20), (14, 22), (206, 246), col=3, b=2)


# ------------------------------------------------------------------ 머리 (v4: 크게 — 폭 19 · 높이 30, 턱 232)
def build_head(M):
    p = M.part("Head", pivot=(0, -2, 236), parent="Torso")
    p.box((-5, 5), (-12, 4), (232, 256), col=4, b=1.2)
    hb = len(p.blocks)
    p.box((-8.5, 8.5), (-11, 9), (255, 269), col=5, b=2.6, top=(0.8, 0.85, 0, 1))      # 헬멧
    p.box((-7, 7), (-16.5, -8), (262, 269), col=5, b=1.6, top=(0.65, 0.5, 0, 1.8))     # 이마
    p.box((-5.5, 5.5), (-15.5, -8), (252, 262), col=4, b=1.4, front=(0.55, 1.0))      # 얼굴판
    p.box((-3, 3), (-17.5, -12), (251, 257), col=1, b=1.0, front=(0.45, 0.75))        # 턱 가드
    sym(p, (1.4, 6.2), (-16.2, -15.2), (259.6, 260.5), col=6, b=0.2, R=roty(-22))     # 비스듬한 눈
    sym(p, (5.5, 9.5), (-13, -3), (253, 262), col=5, b=1.2, R=rotz(-16))              # 뺨
    sym(p, (8.5, 10.5), (-6, 4), (256, 266), col=3, b=1.0)
    sym(p, (2.8, 4.6), (-13.6, -10.4), (265, 282), col=1, b=0.6, R=roty(14), about=(3.7, -12, 265))   # 안테나 두 가닥(위가 바깥으로)
    sym(p, (1.0, 4.4), (-14.2, -10), (264, 268.5), col=5, b=0.8)
    p.box((-11.5, -9.2), (-4, 0), (260, 276), col=1, b=0.7, R=roty(36), about=(-10, -2, 260))          # 옆 뿔(오른쪽만)
    p.box((-1.6, 1.6), (4, 14), (262, 271), col=5, b=1.2, top=(1, 0.5, 0, 3))
    # 원래 크기(턱 251 · 꼭대기 269) → 1.55배, 턱이 234 에 오게
    o = np.array([0, -3, 251.0])
    for bl in p.blocks[hb:]:
        bl.pts = (bl.pts - o) * 1.55 + np.array([0, -11, 246.0])


# ------------------------------------------------------------------ 팔
SHOULDER = (42, 0, 234)
ELBOW = (50, 0, 182)
GRIP_R = (-50, -4, 138)


def build_arm(M):
    # 어깨: 가슴과 틈을 둔 세로로 긴 판(폭 26 · z 196~262), 위 안쪽 앞에 주황 등
    s = M.part("ShoulderL", pivot=SHOULDER, parent="Torso")
    s.cyl("x", (0, 234), 9, (26, 38), col=4)
    s.box((37, 59), (-15, 13), (200, 256), col=3, b=2.5)
    ch(s, (35, 61), (-19, 17), (222, 262), col=1, b=2.6, n=(1, 2, 2), seed=21, out=(0, -1, 0.2), jit=1.6, tilt=4, gap=1.4)
    ch(s, (36, 61), (-17, 15), (198, 222), col=1, b=2.4, n=(1, 1, 1), seed=24, out=(1, 0, 0), jit=1.0, tilt=3, alt=2, alt_p=0.5)
    ch(s, (58, 64), (-12, 10), (214, 254), col=2, b=1.8, n=(1, 1, 2), seed=22, out=(1, 0, 0), jit=1.0)
    s.box((37, 44), (-21.4, -18.8), (248, 257), col=6, b=0.5)
    s.box((40, 54), (16, 21), (220, 252), col=2, b=1.4)
    s.box((46, 52), (20.5, 22), (228, 244), col=6, b=0.4)

    a = M.part("UpperArmL", pivot=SHOULDER, parent="Torso")
    a.box((43, 57), (-9, 9), (180, 226), col=3, b=2)
    ch(a, (43, 58), (-12, 10), (186, 204), col=1, b=2.2, n=(1, 1, 1), seed=31, out=(1, -0.5, 0), jit=1.2)
    a.cyl("x", (0, 182), 9, (42, 58), col=4)

    f = M.part("LowerArmL", pivot=ELBOW, parent="UpperArmL")
    f.box((42, 60), (-12, 12), (146, 178), col=3, b=2)
    ch(f, (39, 63), (-15, 15), (150, 182), col=1, b=2.6, n=(1, 1, 2), seed=41, out=(1, -0.6, 0), jit=2.0, tilt=4, gap=1.6, var=0.3)
    f.box((61, 67), (-11, 12), (154, 180), col=2, b=1.5)
    f.box((66.5, 68), (-2, 2), (160, 176), col=6, b=0.3)
    f.box((40, 47), (10, 18), (164, 186), col=2, b=1.2)
    f.box((44, 56), (-7, 7), (141, 152), col=4, b=1.2)
    f.box((41, 59), (-11, 10), (126, 144), col=3, b=2.6)
    f.box((42, 58), (-14.5, -10), (129, 142), col=4, b=1.0)
    for fx in (44.5, 49.5, 54.5):
        f.box((fx - 2, fx + 2), (-15.2, -13.6), (130, 141), col=3, b=0.5)
    f.box((58, 61.5), (-8, 6), (129, 144), col=1, b=1.0)
    for nm_, o in (("UpperArmL", SHOULDER), ("LowerArmL", SHOULDER)):
        for bl in M.parts[nm_].blocks:
            bl.pts = (bl.pts - np.array(o)) * np.array([1.05, 1.08, 1.0]) + np.array(o)
    M.mirror("ShoulderL", "ShoulderR", "Torso")
    M.mirror("UpperArmL", "UpperArmR", "Torso")
    M.mirror("LowerArmL", "LowerArmR", "UpperArmR")

    # 오른손 라이플(굵고 긴 덩어리 총): 세로로 만들고 관절에서 바깥으로 기울임
    w = M.part("Rifle", pivot=GRIP_R, parent="LowerArmR")
    xc, yc, z0 = -50, -18, 138
    w.box((xc - 7, xc + 7), (yc - 8, yc + 8), (z0 - 36, z0 + 14), col=8, b=2.0)            # 기관부
    ch(w, (xc - 4.5, xc + 4.5), (yc - 11, yc - 6), (z0 - 30, z0 + 10), col=7, b=1.0, n=(1, 1, 3), seed=51, out=(0, -1, 0), jit=0.8)
    w.box((xc - 4.5, xc + 4.5), (yc - 3, yc + 15), (z0 - 30, z0 - 14), col=3, b=1.4)       # 탄창
    ch(w, (xc - 7.5, xc + 7.5), (yc - 7.5, yc + 7.5), (z0 - 114, z0 - 34), col=7, b=2.0, n=(1, 1, 4), seed=52, out=(-1, -1, 0), jit=1.0, tilt=1.5, notch=0.5, step=0.4)
    w.box((xc - 6.6, xc - 5.6), (yc - 1.2, yc + 1.2), (z0 - 98, z0 - 80), col=6, b=0.2)
    w.box((xc - 6.6, xc - 5.6), (yc - 1.2, yc + 1.2), (z0 - 60, z0 - 46), col=6, b=0.2)
    w.box((xc - 3, xc + 3), (yc - 3, yc + 3), (z0 - 168, z0 - 112), col=8, b=1.0)          # 총열
    w.box((xc - 4.4, xc + 4.4), (yc - 4.4, yc + 4.4), (z0 - 176, z0 - 164), col=3, b=1.0)  # 소염기
    w.box((xc - 4, xc + 4), (yc - 4, yc + 4), (z0 - 136, z0 - 128), col=3, b=0.8)
    ch(w, (xc - 5.5, xc + 5.5), (yc - 6, yc + 6), (z0 + 14, z0 + 78), col=8, b=1.6, n=(1, 1, 3), seed=53, out=(0, 1, 0), jit=0.8)   # 개머리
    w.box((xc - 5, xc + 5), (yc - 7, yc + 7), (z0 + 78, z0 + 86), col=3, b=1.0)
    w.rot = roty(17) @ rotx(-8)


# ------------------------------------------------------------------ 다리
HIP = (24, 0, 166)
KNEE = (25, -3, 100)
ANKLE = (25, 0, 34)


def build_leg(M):
    t = M.part("UpperLegL", pivot=HIP, parent="Pelvis")
    t.cyl("x", (0, 166), 10, (13, 33), col=4)
    t.box((15, 33), (-11, 11), (108, 162), col=3, b=2, top=(1.1, 1.1))
    ch(t, (13, 35), (-18, -7), (110, 158), col=1, b=2.2, n=(1, 1, 2), seed=61, jit=2.2, tilt=4, gap=1.6, var=0.3)
    ch(t, (32, 37), (-6, 13), (116, 156), col=1, b=1.8, n=(1, 1, 2), seed=62, out=(1, 0, 0), jit=1.0, alt=2, alt_p=0.35)
    t.box((32, 36), (-12, -5), (112, 150), col=3, b=1.2)
    t.box((16, 32), (7, 16), (114, 154), col=2, b=2.0)
    t.box((11, 16), (-9, 9), (116, 150), col=3, b=1.2)

    s = M.part("LowerLegL", pivot=KNEE, parent="UpperLegL")
    s.cyl("x", (-3, 100), 10, (13, 37), col=4)
    s.box((14, 36), (-24, -9), (88, 124), col=1, b=3.0, top=(0.85, 0.75, 0, 1.6))       # 무릎 장갑
    s.box((20.5, 29.5), (-25.6, -22.5), (95, 113), col=4, b=0.6)
    s.box((22.2, 27.8), (-26.3, -24.6), (97, 111), col=6, b=0.4)
    s.box((16, 34), (-13, 13), (36, 92), col=3, b=2, top=(1.05, 1.1))
    s.box((16, 34), (8, 26), (52, 84), col=3, b=3)                           # 종아리 속(불룩)
    ch(s, (15, 35), (-20, -10), (58, 90), col=1, b=2.4, n=(1, 1, 2), seed=71, jit=2.4, tilt=4, gap=1.6)
    ch(s, (16, 34), (-18, -10), (38, 58), col=1, b=2.2, n=(1, 1, 2), seed=74, jit=1.6, tilt=3, top=(1.1, 1))
    ch(s, (33, 38.5), (-4, 12), (50, 88), col=1, b=1.8, n=(1, 1, 2), seed=72, out=(1, 0, 0), jit=1.2)
    s.box((33, 37), (-11, -3), (44, 84), col=3, b=1.2)
    s.cyl("z", (24, 14), 2.5, (84, 104), col=7)
    ch(s, (15, 35), (18, 30), (54, 88), col=1, b=2.6, n=(1, 1, 2), seed=73, out=(0, 1, 0), jit=1.5, top=(1, 0.8, 0, -2))
    s.box((12, 16), (-9, 11), (48, 86), col=2, b=1.5)
    s.box((15, 35), (-11, 11), (30, 44), col=4, b=1.6)

    f = M.part("FootL", pivot=ANKLE, parent="LowerLegL")
    f.box((10, 40), (-37, 27), (0, 9), col=4, b=2)
    ch(f, (11, 39), (-44, -14), (2, 19), col=1, b=2.6, n=(2, 2, 1), seed=81, jit=1.2, out=(0, -0.5, 1), top=(0.95, 0.7, 0, 2))
    f.box((13, 37), (-47, -36), (1, 10), col=2, b=2)
    f.box((13, 37), (-18, 6), (10, 29), col=1, b=2.5, top=(0.9, 0.75, 0, 2))
    ch(f, (12, 38), (10, 31), (2, 21), col=1, b=2.4, n=(2, 1, 1), seed=82, out=(0, 1, 0), jit=1.0, top=(0.9, 0.8, 0, -2))
    f.box((7, 12.5), (-11, 13), (11, 37), col=1, b=1.6)
    f.box((37.5, 43), (-11, 13), (11, 37), col=1, b=1.6)
    for bl in M.parts["FootL"].blocks:
        bl.pts = (bl.pts - np.array([25, 0, 0])) * np.array([1.12, 1.18, 1.1]) + np.array([25, -2, 0])
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


# ------------------------------------------------------------------ 등짐 · 마스트 · 바인더 · 에너지 블레이드
def build_back(M):
    b = M.part("Backpack", pivot=(0, 20, 226), parent="Torso")
    b.box((-20, 20), (16, 34), (200, 250), col=3, b=3)
    sym(b, (3, 12), (32, 34.6), (206, 246), col=4, b=0.8)
    sym(b, (5, 10), (34.2, 35.4), (209, 243), col=6, b=0.4)
    symchunk(b, (12, 22), (20, 36), (212, 250), col=1, b=2.2, n=(1, 1, 2), seed=91, out=(0, 1, 0), jit=1.2)
    sym(b, (18, 28), (24, 38), (244, 256), col=3, b=1.6)
    for sx in (1, -1):
        b.cyl("z", (sx * 10, 26), 4.5, (192, 202), col=7)

    q = M.part("FinL", pivot=(24, 36, 250), parent="Backpack")
    q.box((18, 30), (26, 46), (244, 322), col=3, b=2, top=(0.8, 0.6, 0, -4))
    ch(q, (29, 34), (28, 45), (252, 308), col=1, b=1.2, n=(1, 1, 3), seed=95, out=(1, 0, 0), jit=1.0, notch=0.2, step=0.2)
    ch(q, (17, 31), (24, 30), (262, 300), col=2, b=1.2, n=(1, 1, 2), seed=96, out=(0, -1, 0), jit=0.6, notch=0.3, step=0)
    q.box((21, 27), (23.2, 24.6), (282, 288), col=6, b=0.3)
    q.rot = roty(8) @ rotx(-6)

    d = M.part("BinderL", pivot=(34, 36, 248), parent="Backpack")
    d0 = len(d.blocks)
    d.box((28, 42), (36, 42), (128, 256), col=3, b=1.6, top=(1.25, 1))
    for (za, zb, c, w0) in ((218, 256, 1, 9), (186, 216, 1, 8), (154, 184, 2, 6.5)):
        ch(d, (35 - w0, 35 + w0), (29, 36.5), (za, zb), col=c, b=1.6, n=(1, 1, 1), seed=int(za), jit=1.0, tilt=2.0, step=0.6, notch=0.4)
    for (za, zb) in ((188, 212), (222, 250)):
        d.box((33.6, 36.4), (29.0, 30.4), (za, zb), col=6, b=0.3)
    d.box((30, 40), (34, 44), (118, 131), col=3, b=1.4)                   # 블레이드 손잡이
    d.box((32.5, 37.5), (36.5, 41.5), (110, 119), col=7, b=0.8)
    d.box((33.4, 36.6), (37.4, 40.6), (40, 110), col=6, b=0.6)              # 에너지 블레이드(왼쪽만)
    for bl in d.blocks[d0:]:
        bl.pts = bl.pts + np.array([4, 4, 0])
    d.rot = rotz(10) @ roty(-14) @ rotx(26)
    e = M.mirror("BinderL", "BinderR", "Backpack")
    e.blocks = [bl for bl in e.blocks if bl.col != 6 or bl.pts[:, 2].min() > 120]


def build_all():
    M = bm.Model()
    build_pelvis(M)
    build_torso(M)
    build_head(M)
    build_arm(M)
    build_leg(M)
    build_back(M)
    return M


PAL = {1: (228, 222, 214), 2: (168, 163, 160), 3: (80, 80, 90), 4: (40, 42, 52), 5: (196, 200, 212),
       6: (255, 140, 50), 7: (112, 112, 120), 8: (66, 66, 74)}
EMISSIVE = (6,)

POSE_ORTHO = {
    "UpperArmL": roty(-8), "UpperArmR": roty(8), "LowerArmL": rotx(-6), "LowerArmR": rotx(-6),
    "UpperLegL": roty(-10), "UpperLegR": roty(10), "FootL": roty(10), "FootR": roty(-10),
}
POSE_HERO = {
    "UpperArmL": roty(-10), "LowerArmL": rotx(-10), "UpperArmR": roty(9) @ rotx(-4), "LowerArmR": rotx(-8),
    "UpperLegL": roty(-11) @ rotx(5), "LowerLegL": rotx(4), "FootL": roty(11) @ rotx(-9),
    "UpperLegR": roty(12) @ rotx(-8), "LowerLegR": rotx(8), "FootR": roty(-12),
    "Head": rotz(-14) @ rotx(4), "Torso": rotz(-10),
}
