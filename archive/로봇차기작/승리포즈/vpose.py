"""vpose.py — AELLO 승리 포즈 작업 도구 (2026-10-29)

자세는 Studio 관절 이름 + Studio 규약으로 적는다 → 나중에 MechClient 표로 그대로 옮긴다.
  E(x, y, z) = Ry·Rx·Rz (도, 템플릿 축 = Studio 축: X 오른쪽(기체 왼쪽이 −X), Y 위, −Z 정면) — heavy_rig.E 와 같음
  관절 Transform 은 부모 쪽 '곧은 자세' 축 기준 회전(팔은 Transform 0 = 팔 곧게, aello_template_build 주석).
  복셀(Blender 칸) 축으로는 R_v = Mm^T · R_t · Mm (aello_wing_view 와 같은 변환).
  Root 이동 t 는 스터드(템플릿) — 1 스터드 = 10 칸.
"""
import numpy as np

import aero_export as E_
import aero_colors as Cc
import aero_r1 as A
import vox_preview as vp
from flag_vox import cyl, box

Mm = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
F = np.diag([-1.0, 1, 1])


def Rx(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def E(x=0, y=0, z=0):
    return Ry(y) @ Rx(x) @ Rz(z)


def rot_axis(ax, deg):
    ax = np.asarray(ax, float); ax = ax / np.linalg.norm(ax); a = np.radians(deg)
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    return np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K


AXIS_T = np.array([0.057, -0.964, 0.262])   # 왼 날개 긴 축(aello_wing_view)


def wing_t(spread, back, twist=0):
    """왼 날개 Transform(템플릿 축). 오른쪽은 거울."""
    return Rx(-back) @ Rz(-spread) @ rot_axis(AXIS_T, twist)


# Studio 관절 → 복셀 파트
J2P = {"Root": "Pelvis", "Waist": "Torso", "Neck": "Head",
       "ShoulderL": "UpperArmL", "ShoulderR": "UpperArmR", "ElbowL": "LowerArmL", "ElbowR": "LowerArmR",
       "PadL": "ShoulderL", "PadR": "ShoulderR",
       "HipL": "UpperLegL", "HipR": "UpperLegR", "KneeL": "LowerLegL", "KneeR": "LowerLegR", "AnkleL": "FootL", "AnkleR": "FootR",
       "SkirtJointFL": "SkirtFL", "SkirtJointFR": "SkirtFR", "SkirtJointSL": "SkirtSL", "SkirtJointSR": "SkirtSR",
       "WingJointL": "WingL", "WingJointR": "WingR", "SaberGrip": "Saber", "Grip": "RifleR", "Pack": "Backpack"}

# 팔레트: 게임 색 C1 + 사벨
PAL = dict(Cc.SCHEMES[E_.SCHEME])
PAL[11] = (255, 205, 40)      # 빔사벨 노랑(MechConfig Aero.SaberColor)
PAL[12] = (255, 248, 215)     # 날 심(SaberBlade)
PAL[13] = (120, 200, 255)     # 추진 불꽃(파랑 — 게임 Flame 색은 미확인 [추측])
PAL[14] = (255, 255, 255)
EMIT = {6, 11, 12, 13, 14}

FIST_L = (40, 0, 125)          # aero_rifle.FIST_R 거울 = 왼 주먹 가운데(곧은 팔 칸)
HILT_HALF, BLADE_TIP = 19, 144  # 칼자루 3.8 스터드 · 손→날끝 14.4 스터드(현재상태_20261026)


def add_saber(M, lit=1.0):
    """왼손 빔사벨. 곧은 팔에서 날 = 정면(−Y 칸). lit = 날 길이 비율(점화 연출)."""
    fx, fy, fz = FIST_L
    tip = int(round(HILT_HALF + 1 + (BLADE_TIP - HILT_HALF - 1) * lit)) if lit > 0 else HILT_HALF
    p = M.part("Saber", (fx - 6, fy - BLADE_TIP - 4, fz - 6), (fx + 7, fy + HILT_HALF + 3, fz + 7), pivot=FIST_L, parent="LowerArmL")
    G = p.g(); X, Y, Z = G
    p.add(cyl(G, "y", (fx, fz), 2.6, (fy - HILT_HALF, fy + HILT_HALF)), 4)                 # 손잡이(검정)
    p.add(cyl(G, "y", (fx, fz), 3.0, (fy + HILT_HALF - 3, fy + HILT_HALF)), 7)             # 끝마개
    p.add(cyl(G, "y", (fx, fz), 3.2, (fy - HILT_HALF, fy - HILT_HALF + 4)), 7)             # 노즐
    p.add(cyl(G, "y", (fx, fz), 3.4, (fy - HILT_HALF + 1, fy - HILT_HALF + 1)), 1)         # 주황 고리
    if lit > 0:
        r = 2.4
        taper = np.clip((tip - (fy - Y) - 0) / 12.0, 0.25, 1.0)                            # 끝 12칸 가늘어짐
        blade = ((X - fx) ** 2 + (Z - fz) ** 2 <= (r * taper) ** 2 + 0.25) & (Y <= fy - HILT_HALF - 1) & (Y >= fy - tip)
        p.add(blade, 11)
    return p


def add_flame(M, name, parent, origin, direction, length=30, r0=2.6):
    """origin(부모 곧은 자세 칸), direction(부모 곧은 축) 원뿔 불꽃."""
    o = np.asarray(origin, float); d = np.asarray(direction, float); d /= np.linalg.norm(d)
    pts = [o + d * t for t in np.arange(1, length)]
    lo = np.floor(np.min(pts, 0) - r0 - 2).astype(int); hi = np.ceil(np.max(pts, 0) + r0 + 2).astype(int)
    q = M.part(name, tuple(lo), tuple(hi), pivot=tuple(o), parent=parent)
    G = q.g(); X, Y, Zg = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Zg.shape)
    m = np.zeros(shp, bool); core = np.zeros(shp, bool)
    for i, pt in enumerate(pts):
        f = i / len(pts)
        r = r0 * (1 - f) + 0.6
        d2 = (X - pt[0]) ** 2 + (Y - pt[1]) ** 2 + (Zg - pt[2]) ** 2
        m |= d2 <= r * r
        if f < 0.35:
            core |= d2 <= (r * 0.5) ** 2
    q.add(m, 13)
    return q


def model(saber=0.0, rifle=True, stowed=False, flames=0.0, legflames=True):
    M = E_.build()
    for n in ("Grenade",):
        M.parts.pop(n, None)
    if not stowed:
        M.parts.pop("RifleStowed", None)
    if not rifle:
        M.parts.pop("RifleR", None)
    if saber is not None and saber >= 0:
        add_saber(M, saber)
    if flames > 0:
        L = flames
        # 다리 보조 부스터(아래), BoostL 로컬 (36, 6, 46.5) — aello_template_data legNozzles
        for s, side in ((1, "L"), (-1, "R")):
            if legflames:
                add_flame(M, "FlameLeg" + side, "LowerLeg" + side, (s * 36, 6, 44), (0, 0.15, -1), int(34 * L), 3.0)
            # 바인더 노즐(뒤): (±22, 48.5, 247/238)
            for k, z in enumerate((247, 238)):
                add_flame(M, "FlameBack%s%d" % (side, k), "Backpack", (s * 22, 50, z), (0, 1, -0.15), int(30 * L), 2.4)
    return M


def to_vox(Rt):
    return Mm.T @ Rt @ Mm


def mats(pose):
    """pose(Studio 관절 이름 → 3x3 템플릿 회전 | ('wing', spread, back, twist) ...) → 복셀 파트 이름 → 4x4(칸)"""
    out = {}
    for j, v in pose.items():
        if j == "RootT":
            continue
        if j.startswith("@"):                      # 복셀 축 직접 회전(부모 곧은 축 기준) — 라이플 손목 등
            out[j[1:]] = _m4(np.asarray(v, float))
            continue
        if j == "Wings":
            sp, bk, tw = v
            RtL = wing_t(sp, bk, tw)
            out["WingL"] = _m4(to_vox(RtL))
            out["WingR"] = _m4(F @ to_vox(RtL) @ F)
            continue
        part = J2P[j]
        out[part] = _m4(to_vox(np.asarray(v, float)))
    if "RootT" in pose:
        t = Mm.T @ np.asarray(pose["RootT"], float) * 10.0
        m = out.get("Pelvis", np.eye(4)).copy(); m[:3, 3] = t
        out["Pelvis"] = m
    return out


def _m4(R):
    m = np.eye(4); m[:3, :3] = R; return m


def world(M, name, P4, cache):
    if name in cache:
        return cache[name]
    p = M.parts[name]
    Q = P4.get(name, np.eye(4))
    R = Q[:3, :3] @ p.rot
    T = np.eye(4); T[:3, :3] = R
    pv = np.array(p.pivot)
    T[:3, 3] = pv - R @ pv + Q[:3, 3]
    if p.parent and p.parent in M.parts:
        T = world(M, p.parent, P4, cache) @ T
    cache[name] = T
    return T


def blocks(M, pose, skip=()):
    P4 = mats(pose); cache = {}
    out = []
    for n, p in M.parts.items():
        if n in skip:
            continue
        T = world(M, n, P4, cache)
        out.append((p.lo, p.a, T))
    return out, cache


def point(M, pose, part, local):
    _, cache = blocks(M, pose)
    T = cache[part]
    return T[:3, :3] @ np.asarray(local, float) + T[:3, 3]


# ------------------------------------------------------------------ 겹침 검사(칸)
MOVING = ("UpperArmL", "LowerArmL", "UpperArmR", "LowerArmR", "Saber", "RifleR", "UpperLegL", "LowerLegL", "FootL",
          "UpperLegR", "LowerLegR", "FootR", "WingL", "WingR")
BODY = ("Pelvis", "Torso", "Head", "Backpack", "BinderL", "BinderR", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR", "SkirtB",
        "ShoulderL", "ShoulderR", "ChestL", "ChestR", "WingL", "WingR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
        "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR", "RifleR", "Saber", "BoostL", "BoostR", "SpikeL1", "SpikeL2", "SpikeR1", "SpikeR2")
# 관절로 원래 붙어 있는 짝(겹침이 정상) — 쉬는 자세 기준선을 빼서 판단
_PTS = {}


def _local_pts(M, n):
    if n not in _PTS:
        p = M.parts[n]
        _PTS[n] = (np.argwhere(p.a > 0) + p.lo).astype(np.float32)
    return _PTS[n]


def cellset(M, cache, n):
    T = cache[n]
    P = _local_pts(M, n) @ T[:3, :3].T.astype(np.float32) + T[:3, 3].astype(np.float32)
    k = np.round(P).astype(np.int64)
    return np.unique((k[:, 0] + 2000) * 16000000 + (k[:, 1] + 2000) * 4000 + (k[:, 2] + 2000))


def overlaps(M, pose, pairs):
    _, cache = blocks(M, pose)
    S = {}
    res = {}
    for a, b in pairs:
        for n in (a, b):
            if n not in S:
                S[n] = cellset(M, cache, n)
        res[(a, b)] = len(np.intersect1d(S[a], S[b], assume_unique=True))
    return res


def check_pairs(M):
    present = [n for n in MOVING if n in M.parts]
    body = [n for n in BODY if n in M.parts]
    pairs = set()
    for a in present:
        for b in body:
            if a == b:
                continue
            k = tuple(sorted((a, b)))
            pairs.add(k)
    # 같은 사슬로 붙은 짝은 뺌(관절 겹침 정상)
    chain = {("LowerArmL", "UpperArmL"), ("LowerArmR", "UpperArmR"), ("Torso", "UpperArmL"), ("Torso", "UpperArmR"),
             ("ShoulderL", "UpperArmL"), ("ShoulderR", "UpperArmR"), ("LowerArmL", "Saber"), ("LowerArmR", "RifleR"),
             ("Pelvis", "UpperLegL"), ("Pelvis", "UpperLegR"), ("LowerLegL", "UpperLegL"), ("LowerLegR", "UpperLegR"),
             ("FootL", "LowerLegL"), ("FootR", "LowerLegR"), ("BoostL", "LowerLegL"), ("BoostR", "LowerLegR"),
             ("Backpack", "WingL"), ("Backpack", "WingR"), ("BinderL", "WingL"), ("BinderR", "WingR")}
    return sorted(k for k in pairs if tuple(sorted(k)) not in {tuple(sorted(c)) for c in chain})


# ------------------------------------------------------------------ 렌더
def render(M, pose, yaw, pitch, ppc=1.6, size=None, bloom=1.0, ao=0.5, skip=()):
    B, cache = blocks(M, pose, skip)
    im = vp.render(B, PAL, EMIT, yaw=yaw, pitch=pitch, ppc=ppc, ss=2, size=size, ao_amt=ao, bloom=bloom)
    return im, cache


def project(pt, yaw, pitch, size, ppc):
    d, f, r, u = vp._basis(yaw, pitch)
    (x0, x1), (y0, y1) = size
    return ((pt @ r - x0) * ppc, (y1 - pt @ u) * ppc)
