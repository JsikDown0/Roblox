"""ZERDA(ST-10) 골격 표준 — 1단계 [유저 11-05 "1~2단계 해봐"] (모듈화: 골격·관절 · 장착점).

목적: 새 양산 시리즈 = 이 골격(관절 · 회전 중심 · 부모 관계)을 그대로 쓰고 겉 장갑만 새로 / 바리에이션 = 장착점에 장비만 끼움
(GAT-01 스트라이크 대거 + 런처 팩, 짐 + 등 발사기처럼).

1) RIG       — 회전 중심(피벗)과 부모 관계. 왼쪽(+X)만 적고 오른쪽은 거울(M.mirror).
2) 관절 함수  — 겉 장갑과 따로 부르는 관절 부품. 각 빌더(m2_shoulder · m2_arm_r2 · m2_leg_r1)가 같은 순서로 부른다
               (정리 전후 ZERDA 가 칸 하나까지 같음 = 회귀 검사 `tools/../scratchpad cmp`).
3) HARDPOINTS — 장비를 붙이는 자리: 부모 파트 · 원점(쉬는 자세 월드 칸) · 바깥 방향 n · 위 방향 u.
               attach() 가 그 자리 좌표계(a = n 바깥, b = u 위, c = 옆)로 장비 마스크를 그려 새 파트를 만든다.
4) build_frame() — 관절만 모은 골격 모델(겉 장갑 없음) = 새 시리즈의 출발점.
색: 2 짙은 회색 · 3 짙은 프레임 · 4 검정 · 7 강철."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
sys.path.insert(0, os.path.join(HERE, "..", "mass"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, cbox  # noqa: E402
from mass_r1 import seg  # noqa: E402

# ---------------------------------------------------------------- 1) RIG (왼쪽 +X, 칸 단위 · 쉬는 자세)
AX = 44                       # 팔 축 X
CX = 23                       # 다리 축 X
SJ = (32, 0, 227)             # 어깨 관절 원통(몸통 옆)
RIG = {
    "Pelvis": dict(pivot=(0, 0, 160), parent=None),
    "Torso": dict(pivot=(0, 0, 200), parent="Pelvis"),
    "Head": dict(pivot=(0, 0, 236), parent="Torso"),
    "ShoulderJointL": dict(pivot=SJ, parent="Torso"),
    "ShoulderArmorL": dict(pivot=SJ, parent="Torso"),          # 어깨 장갑은 몸통에 고정(팔은 그 밑에서 돎)
    "UpperArmL": dict(pivot=(AX, 0, 227), parent="Torso"),
    "LowerArmL": dict(pivot=(AX, -0.5, 185), parent="UpperArmL"),
    "HandL": dict(pivot=(AX, 0, 138), parent="LowerArmL"),
    "UpperLegL": dict(pivot=(CX, 0, 152), parent="Pelvis"),
    "LowerLegL": dict(pivot=(CX, -1, 108), parent="UpperLegL"),
    "FootL": dict(pivot=(CX, 0, 36), parent="LowerLegL"),
}
SHO, ELB, WRI = RIG["UpperArmL"]["pivot"], RIG["LowerArmL"]["pivot"], RIG["HandL"]["pivot"]
HIP, KNEE, ANK = RIG["UpperLegL"]["pivot"], RIG["LowerLegL"]["pivot"], RIG["FootL"]["pivot"]


# ---------------------------------------------------------------- 2) 관절 함수
def shoulder_joint(M, s, sj=SJ):
    """어깨 관절 원통(X 축, 짙은 회색) + 테 1칸 + 끝 홈 — 몸통 옆에서 바깥으로. 파트 ShoulderJointL/R."""
    nm = "ShoulderJointL" if s > 0 else "ShoulderJointR"
    J = M.part(nm, (-40, -12, 215), (41, 12, 240), pivot=(s * sj[0], 0, sj[2]), parent="Torso")
    G = J.g(); X, Y, Z = G
    xr = (26, 36) if s > 0 else (-36, -26)
    J.add(cyl(G, "x", (0, sj[2]), 8.5, rng=xr), 2)
    J.add(cyl(G, "x", (0, sj[2]), 9.5, rng=(xr[0] + 2, xr[0] + 3) if s > 0 else (xr[1] - 3, xr[1] - 2)), 2)
    J.groove(cyl(G, "x", (0, sj[2]), 5.5, rng=(-40, 40)) & ~cyl(G, "x", (0, sj[2]), 4.5, rng=(-40, 40)) & (np.abs(X) >= 34), 3)
    J.trim()
    return J


def knuckle_hinge(P, G, axes, zr, block_y=(-6, 4), links=True, x0=AX):
    """BISON f 경첩: axes = [(Y, Z), ...] X 축 · 양옆 둥근 너클(x0±4~7) · 가운데 직사각 블록(x0±3) · 2축이면 강철 링크판."""
    X, Y, Z = G
    for (yc, zc) in axes:
        P.add(cyl(G, "x", (yc, zc), 2.5, rng=(x0 - 8, x0 + 8)), 4)
        for xa, xb in ((x0 - 7, x0 - 4), (x0 + 4, x0 + 7)):
            P.add(cyl(G, "x", (yc, zc), 4.2, rng=(xa, xb)), 3)
            P.groove(cyl(G, "x", (yc, zc), 4.6) & ~cyl(G, "x", (yc, zc), 2.8) & (X == (xa if xa < x0 else xb)), 4)
    P.add(cbox(G, (x0 - 3, x0 + 3), block_y, zr, {"yz": 2}), 3)
    if links and len(axes) == 2:
        (y0, z0), (y1, z1) = axes
        for xl in (x0 - 4, x0 + 4):
            P.add(seg(G, (xl, y0, z0), (xl, y1, z1), 2.6) & (X == xl), 7)


def upper_arm_root(U, G, x0=AX, z=227):
    """위팔 뿌리: 어깨 축(장갑 속, 짙은 회색) + 위 목(짙은 프레임)."""
    U.add(cyl(G, "x", (0, z), 6.5, rng=(34, 52)), 2)
    U.add(cbox(G, (x0 - 5, x0 + 5), (-6, 6), (213, 226), {"xy": 2}), 3)


def shoulder_hinge(U, G, x0=AX):
    """어깨 밑 관절 A [결정 11-04] = 축 하나 너클 경첩(z204~213)."""
    knuckle_hinge(U, G, [(0, 209)], (204, 213), block_y=(-5, 4), links=False, x0=x0)


def elbow_joint(L, G, x0=AX):
    """팔꿈치 = BISON f 2축 경첩(위 축 뒤 · 아래 축 앞 · 링크판) + 뒤 강철 피스톤 막대."""
    knuckle_hinge(L, G, [(1.5, 188), (-2.5, 182)], (179, 191), x0=x0)
    L.add(seg(G, (x0, 4, 191), (x0, 4, 179), 1.6), 7)


def wrist_core(L, G, x0=AX):
    """손목 속 짙은 심(W2 소매 안)."""
    L.add(cyl(G, "z", (x0, 0), 5, rng=(134, 141)), 3)


def hip_frame(U, G, x0=CX):
    """허벅지 속 짙은 뼈대(고관절 ~ 무릎)."""
    U.add(cbox(G, (x0 - 7, x0 + 7), (-7, 7), (116, 150), {"xy": 2}), 3)


def hip_housing(U, G, cut, x0=CX):
    """고관절 하우징 [결정 11-04 r5]: 허벅지 장갑 안쪽 위 45° 틈(cut 밖)을 꽉 채우는 짙은 덩어리. 장갑을 그린 뒤 부른다."""
    U.add(cbox(G, (x0 - 16, x0 + 2), (-12, 11), (138, 161), {"xy": 3, "-x-z": 3}) & ~cut & ~(U.a > 0), 3)


def knee_joint(L, G, x0=CX, knee=KNEE):
    """무릎: 양옆 둥근 너클(정강이보다 2칸 바깥) + 축 + 뒤 홈 드럼(톱니 홈 12)."""
    X, Y, Z = G; dx = np.abs(X - x0)
    ky, kz = knee[1], knee[2]
    for xa, xb in ((x0 - 17, x0 - 11), (x0 + 11, x0 + 17)):
        L.add(cyl(G, "x", (ky, kz), 7.5, rng=(xa, xb)), 3)
        xe = xa if xa < x0 else xb
        L.groove(cyl(G, "x", (ky, kz), 8) & ~cyl(G, "x", (ky, kz), 5.5) & (X == xe), 4)
        L.paint(cyl(G, "x", (ky, kz), 2.5) & (X == xe), 2)
    L.add(cyl(G, "x", (ky, kz), 4, rng=(x0 - 11, x0 + 11)), 4)
    drum = cyl(G, "x", (ky + 3, kz - 1), 8, rng=(x0 - 9, x0 + 9))
    L.add(drum, 3)
    ang = np.arctan2(np.broadcast_to(Z - (kz - 1), L.a.shape), np.broadcast_to(Y - (ky + 3), L.a.shape))
    L.groove(drum & (np.abs(((ang / (np.pi / 6)) % 1.0) - 0.5) < 0.18) & np.broadcast_to(dx <= 8, L.a.shape), 4)


def ankle_joint(F, G, x0=CX, ank=ANK):
    """발목: 양옆 둥근 원판(홈 고리) + 축 + 발로 내려가는 짙은 기둥."""
    X, Y, Z = G
    for sx in (1, -1):
        F.add(cyl(G, "x", (0, ank[2]), 6, rng=sorted((x0 + sx * 11, x0 + sx * 14))), 3)
        F.groove(cyl(G, "x", (0, ank[2]), 6.4) & ~cyl(G, "x", (0, ank[2]), 4) & (X == x0 + sx * 14), 4)
    F.add(cyl(G, "x", (0, ank[2]), 4, rng=(x0 - 11, x0 + 11)), 4)
    F.add(cbox(G, (x0 - 8, x0 + 8), (-7, 9), (16, ank[2] + 2), {"xy": 3}), 3)


# ---------------------------------------------------------------- 3) 장착점
# 원점 = 쉬는 자세 월드 칸(왼쪽은 그대로, 오른쪽 R 은 X 부호 반대) · n = 바깥(장비가 뻗는 쪽) · u = 장비의 위
HARDPOINTS = {
    "BackUpper":  dict(parent="Torso",     origin=(0, 19, 220),   n=(0, 1, 0),  u=(0, 0, 1), note="등 위(가슴 뒤 z196~243) — 백팩 자리 · 지금은 카빈 수납 S1"),
    "BackLower":  dict(parent="Pelvis",    origin=(0, 19, 183),   n=(0, 1, 0),  u=(0, 0, 1), note="허리 뒤 — 부스터 P1"),
    "ShoulderTopL": dict(parent="Torso",   origin=(44, 0, 254),   n=(0, 0, 1),  u=(0, -1, 0), note="왼 어깨 돔 위 — 미사일 포드·캐논 받침"),
    "ShoulderTopR": dict(parent="Torso",   origin=(-43, 0, 243),  n=(0, 0, 1),  u=(0, -1, 0), note="오른 어깨 상자 위"),
    "ForearmL":   dict(parent="LowerArmL", origin=(58, 0, 160),   n=(1, 0, 0),  u=(0, 0, 1), note="왼 아래팔 바깥 — 소형 방패·아대"),
    "ForearmR":   dict(parent="LowerArmR", origin=(-58, 0, 160),  n=(-1, 0, 0), u=(0, 0, 1), note="오른 아래팔 바깥"),
    "HipL":       dict(parent="Pelvis",    origin=(30, 0, 172),   n=(1, 0, 0),  u=(0, 0, 1), note="왼 허리 옆 — 나이프 홀스터"),
    "HipR":       dict(parent="Pelvis",    origin=(-32, 0, 170),  n=(-1, 0, 0), u=(0, 0, 1), note="오른 허리 옆 블록 바깥"),
    "ThighL":     dict(parent="UpperLegL", origin=(39, 0, 138),   n=(1, 0, 0),  u=(0, 0, 1), note="왼 허벅지 바깥 — 탄창·예비 무장(BISON 라이플 수납 자리)"),
    "ThighR":     dict(parent="UpperLegR", origin=(-39, 0, 138),  n=(-1, 0, 0), u=(0, 0, 1), note="오른 허벅지 바깥"),
    "CalfL":      dict(parent="LowerLegL", origin=(23, 16, 79),   n=(0, 1, 0),  u=(0, 0, 1), note="왼 종아리 뒤 — 보조 부스터 P3"),
    "CalfR":      dict(parent="LowerLegR", origin=(-23, 16, 79),  n=(0, 1, 0),  u=(0, 0, 1), note="오른 종아리 뒤"),
    "HandL":      dict(parent="HandL",     origin=(42, 0, 122),   n=(0, -0.866, -0.5), u=(0, -0.5, 0.866), note="왼 주먹 속 — 나이프"),
    "HandR":      dict(parent="HandR",     origin=(-43, 1, 124),  n=(0, -0.5, -0.866), u=(0, -0.866, 0.5), note="오른 주먹 속 — 카빈(총구 아래·앞 60°)"),
}


def hp(name):
    h = HARDPOINTS[name]
    return np.array(h["origin"], float), np.array(h["n"], float), np.array(h["u"], float)


def frame_at(P, O, a_, b_):
    """파트 P 격자를 장착 좌표(a = a_ 쪽, b = b_ 쪽, c = a × b)로 — 카빈·나이프의 _frame 과 같은 식."""
    a_ = np.asarray(a_, float); a_ /= np.linalg.norm(a_)
    b_ = np.asarray(b_, float); b_ = b_ - a_ * (a_ @ b_); b_ /= np.linalg.norm(b_)
    c_ = np.cross(a_, b_)
    X, Y, Z = P.g(); dx, dy, dz = X - O[0], Y - O[1], Z - O[2]
    f = lambda e: e[0] * dx + e[1] * dy + e[2] * dz
    return [np.broadcast_to(v, P.a.shape) for v in (f(a_), f(b_), f(c_))]


def attach(M, hpname, name, masks, offset=(0, 0, 0), a_=None, b_=None, size=60, order=(2, 3, 1, 4, 7, 6)):
    """장착점 hpname 에 장비 파트 name 을 붙인다.
    masks(a, b, c) → {색: 마스크}. offset = 장착점 좌표계(n, u, c)로 원점에서 옮김.
    a_/b_ 를 주면 장비 축(기본: a = 바깥 n, b = 위 u)을 월드 방향으로 바꿈."""
    O, n, u = hp(hpname)
    c = np.cross(n / np.linalg.norm(n), u / np.linalg.norm(u))
    O = O + offset[0] * n + offset[1] * u + offset[2] * c
    a_ = n if a_ is None else np.asarray(a_, float); b_ = u if b_ is None else np.asarray(b_, float)
    P = M.part(name, tuple((O - size).astype(int)), tuple((O + size).astype(int)), pivot=tuple(O), parent=HARDPOINTS[hpname]["parent"])
    a, b, cc = frame_at(P, O, a_, b_)
    m = masks(a, b, cc)
    for col in order:
        if col in m:
            P.add(m[col], col)
    P.trim()
    return P


# ---------------------------------------------------------------- 4) 골격만
def build_frame():
    """관절만(겉 장갑 없음) — 몸통 속은 짙은 상자 자리 표시만. 새 시리즈를 이 위에 입힘."""
    M = fv.Model()
    P = M.part("Pelvis", (-34, -20, 130), (35, 18, 192), pivot=RIG["Pelvis"]["pivot"])
    G = P.g()
    P.add(cbox(G, (-14, 14), (-9, 10), (174, 189), {"xy": 3}), 3)                                       # 배 심
    P.add(cyl(G, "x", (0, 152), 6, rng=(-11, 11)), 3)                                                   # 고관절 축
    P.add(cbox(G, (-7, 7), (-12, 8), (134, 153), {"xz": 3, "-yz": 3, "+yz": 2}), 2)                     # 샅
    P.add(cbox(G, (-5, 5), (-5, 5), (153, 174), {"xy": 2}), 3)                                          # 허리 기둥(배 ↔ 샅, 골격만 볼 때 섬 방지)
    P.trim()
    T = M.part("Torso", (-36, -32, 182), (37, 28, 250), pivot=RIG["Torso"]["pivot"], parent="Pelvis")
    G = T.g(); T.add(cbox(G, (-24, 24), (-12, 16), (188, 234), {"xy": 4}), 3); T.trim()                 # 몸통 속 프레임
    H = M.part("Head", (-14, -14, 226), (15, 15, 246), pivot=RIG["Head"]["pivot"], parent="Torso")
    G = H.g(); H.add(cyl(G, "z", (0, 0), 8, rng=(226, 241)), 3); H.trim()                               # 목
    shoulder_joint(M, 1)
    U = M.part("UpperArmL", (30, -14, 186), (62, 14, 234), pivot=SHO, parent="Torso"); G = U.g()
    upper_arm_root(U, G); shoulder_hinge(U, G)
    U.add(cbox(G, (AX - 5, AX + 5), (-5, 5), (191, 204), {"xy": 2}), 3); U.trim()                       # 위팔 뼈(장갑 자리)
    L = M.part("LowerArmL", (28, -16, 132), (62, 16, 196), pivot=ELB, parent="UpperArmL"); G = L.g()
    elbow_joint(L, G); L.add(cbox(G, (AX - 5, AX + 5), (-5, 5), (142, 179), {"xy": 2}), 3); wrist_core(L, G); L.trim()
    Hn = M.part("HandL", (30, -14, 108), (58, 12, 137), pivot=WRI, parent="LowerArmL"); G = Hn.g()
    Hn.add(cbox(G, (AX - 6, AX + 6), (-7, 7), (116, 134), {"xy": 2, "xz": 2}), 3); Hn.trim()             # 손 자리
    U2 = M.part("UpperLegL", (0, -22, 112), (46, 20, 166), pivot=HIP, parent="Pelvis"); G = U2.g()
    hip_frame(U2, G); hip_housing(U2, G, np.zeros(U2.a.shape, bool)); U2.trim()
    L2 = M.part("LowerLegL", (-8, -32, 26), (54, 34, 130), pivot=KNEE, parent="UpperLegL"); G = L2.g()
    knee_joint(L2, G); L2.add(cbox(G, (CX - 6, CX + 6), (-6, 6), (40, 100), {"xy": 2}), 3); L2.trim()   # 정강이 뼈
    F = M.part("FootL", (-6, -46, 0), (52, 36, 44), pivot=ANK, parent="LowerLegL"); G = F.g()
    ankle_joint(F, G); F.add(cbox(G, (CX - 10, CX + 10), (-30, 20), (0, 16), {"xy": 4, "-y+z": 6}), 3); F.trim()   # 발 자리(발목 기둥 z16 까지)
    for n in ("ShoulderJointL", "UpperArmL", "LowerArmL", "HandL", "UpperLegL", "LowerLegL", "FootL"):
        if n != "ShoulderJointL":
            M.mirror(n, n[:-1] + "R")
    shoulder_joint(M, -1)
    return M


def hp_markers(M, names=None, col=6, tip=5):
    """장착점 표시(시트용): 원점에 청록 3칸 상자 + 바깥 방향 6칸 빨강 막대."""
    for nm in names or HARDPOINTS:
        def mk(a, b, c):
            return {col: (np.abs(a) <= 1.5) & (np.abs(b) <= 1.5) & (np.abs(c) <= 1.5),
                    tip: (a > 1.5) & (a <= 8) & (np.abs(b) <= 0.6) & (np.abs(c) <= 0.6)}
        attach(M, nm, "HP_" + nm, mk, size=12, order=(col, tip))
    return M
