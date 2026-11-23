"""
valk_melee1.py — VALKYRIE 두 손 블레이드 전용 동작 설계 도구 (2026-11-03) · 유저 20:36 "빔사벨 동작을 아예 새 전용 동작으로 ·
  블레이드 전환 때는 두 손을 모아 검을 켜고 · 두 손으로 휘두르게".
  Studio ValkyrieTemplate 관절 틀(C0/C1 · 쉬는 자세 파트 CFrame, 에디트 실측 11-03 20:4x)을 그대로 옮긴 FK + 오른팔 IK(MechPoses solveArm 이식)
  + 복셀 렌더/겹침. Transform 규약 = MechClient(E(x, y, z) = Ry·Rx·Rz, 도) · 좌표 = Studio(스터드, 정면 −Z).
  복셀 ↔ Studio: s = (−x, z, y) × 0.1 (템플릿 = 가져온 자리 × 2, 칸 0.05 → 0.1 스터드). 팔은 복셀 격자 = 곧은 팔 = 템플릿 쉬는 자세.
"""
import io, contextlib
import numpy as np
with contextlib.redirect_stdout(io.StringIO()):
    import valk_guard2 as G2, valk_hilt2 as HL
    import vox_preview as Vp, hview as H


def CF(p, rows=None):
    m = np.eye(4); m[:3, 3] = p
    if rows is not None: m[:3, :3] = np.array(rows, float)
    return m


RUP_L = [[0.99027, 0.13917, 0], [-0.13917, 0.99027, 0], [0, 0, 1]]
RUP_R = [[0.99027, -0.13917, 0], [0.13917, 0.99027, 0], [0, 0, 1]]
J = {   # 움직이는 관절만(나머지 고정 파트는 부모를 따라감)
    "Root": ("HumanoidRootPart", "Pelvis", CF((0, 0, 0)), CF((0, 0.65, -0.15))),
    "Waist": ("Pelvis", "Torso", CF((0, 3.05, -0.15)), CF((0, -1.4, -0.2))),
    "Neck": ("Torso", "Head", CF((0, 2.4, -0.1)), CF((0, -0.55, -0.2))),
    "PadL": ("Torso", "ShoulderPadL", CF((-3.3, 1.4, 0.1)), CF((0.45, -0.4, 0.15))),
    "PadR": ("Torso", "ShoulderPadR", CF((3.3, 1.4, 0.1)), CF((-0.45, -0.4, 0.15))),
    "ShoulderL": ("Torso", "UpperArmL", CF((-3.3, 1.4, 0.1)), CF((0.26603, 1.832, 0.05), RUP_L)),
    "ElbowL": ("UpperArmL", "LowerArmL", CF((0.26603, -1.068, 0.05), RUP_L), CF((1.00071, 3.09112, 0.15), RUP_L)),
    "SaberGrip": ("LowerArmL", "SaberHilt", CF((-0.28029, -2.70493, 0.0945), RUP_L), CF((0, -1.4, 0), [[1, 0, 0], [0, 0, -1], [0, 1, 0]])),
    "ShoulderR": ("Torso", "UpperArmR", CF((3.3, 1.4, 0.1)), CF((-0.26603, 1.832, 0.05), RUP_R)),
    "ElbowR": ("UpperArmR", "LowerArmR", CF((-0.26603, -1.068, 0.05), RUP_R), CF((-1.00071, 3.09112, 0.15), RUP_R)),
    "Grip": ("LowerArmR", "Rifle", CF((0.28029, -2.70493, 0.0945), [[0.99027, 0, -0.13917], [0.13917, 0, 0.99027], [0, -1, 0]]),
             CF((0.96, -2.78, 0), [[0, -1, 0], [0, 0, 1], [-1, 0, 0]])),          # 사격 손(지느러미 쥠) — Studio 실측 11-03
    "HipL": ("Pelvis", "UpperLegL", CF((-2.1, -1.65, -0.25)), CF((0, 2.55, 0.4))),
    "KneeL": ("UpperLegL", "LowerLegL", CF((0, -3.75, 0.4)), CF((0.1, 3.45, 0.3))),
    "AnkleL": ("LowerLegL", "FootL", CF((0.1, -3.95, 0.3)), CF((0, 0.55, 1.55))),
    "HipR": ("Pelvis", "UpperLegR", CF((2.1, -1.65, -0.25)), CF((0, 2.55, 0.4))),
    "KneeR": ("UpperLegR", "LowerLegR", CF((0, -3.75, 0.4)), CF((-0.1, 3.45, 0.3))),
    "AnkleR": ("LowerLegR", "FootR", CF((-0.1, -3.95, 0.3)), CF((0, 0.55, 1.55))),
}
REST = {
    "HumanoidRootPart": CF((0, 17.6, -0.6)), "Pelvis": CF((0, 16.95, -0.45)), "Torso": CF((0, 21.4, -0.4)), "Head": CF((0, 24.35, -0.3)),
    "ShoulderPadL": CF((-3.75, 23.2, -0.45)), "ShoulderPadR": CF((3.75, 23.2, -0.45)),
    "UpperArmL": CF((-3.30848, 20.9488, -0.35), np.array(RUP_L).T), "LowerArmL": CF((-3.45718, 16.72791, -0.45), np.array(RUP_L).T),
    "UpperArmR": CF((3.30848, 20.9488, -0.35), np.array(RUP_R).T), "LowerArmR": CF((3.45718, 16.72791, -0.45), np.array(RUP_R).T),
    "UpperLegL": CF((-2.1, 12.75, -1.1)), "LowerLegL": CF((-2.2, 5.55, -1)), "FootL": CF((-2.1, 1.05, -2.25)),
    "UpperLegR": CF((2.1, 12.75, -1.1)), "LowerLegR": CF((2.2, 5.55, -1)), "FootR": CF((2.1, 1.05, -2.25)),
    "SaberHilt": CF((-3.3583, 14.0103, -1.7555), [[1, 0, 0], [0, 0, 1], [0, -1, 0]]),
    "Rifle": CF((3.3583, 16.7903, -1.3155), [[0, 0, -1], [0, 1, 0], [1, 0, 0]]),
}
VH_IN_HILT = CF((0, -1.9, -0.05), [[0, 0, -1], [0, -1, 0], [-1, 0, 0]])   # Saber.InHand VBladeHilt ↔ SaberHilt (용접, 실측)
BLADE_IN_RIFLE = None
BLADE_IN_HILT = CF((0, 1.1, 0), [[0, 0, -1], [0, -1, 0], [-1, 0, 0]])   # 칼 좌표(×2, 칼끝 −Y · 등 −X) → 사벨 손잡이 로컬
# 복셀 파트 → 따라가는 Studio 파트(고정 파트 포함)
FOLLOW = {"Head": "Head", "CrestB": "Head", "HornAL": "Head", "HornRootL": "Head", "FinC2L": "Head", "HornAR": "Head", "HornRootR": "Head", "FinC2R": "Head",
          "FaceL": "Head", "FaceR": "Head", "Torso": "Torso", "BackPlate": "Torso", "PackCore": "Torso",
          "ShoulderL": "ShoulderPadL", "PadGoldL": "ShoulderPadL", "PadFinL": "ShoulderPadL", "ShoulderR": "ShoulderPadR", "PadGoldR": "ShoulderPadR", "PadFinR": "ShoulderPadR",
          "UpperArmL": "UpperArmL", "LowerArmL": "LowerArmL", "UpperArmR": "UpperArmR", "LowerArmR": "LowerArmR",
          "Pelvis": "Pelvis", "Tail": "Pelvis", "ThighL": "UpperLegL", "ShinL": "LowerLegL", "FootL": "FootL", "ThighR": "UpperLegR", "ShinR": "LowerLegR", "FootR": "FootR"}
for n in ("MountBaseL", "MountL", "ShieldL", "MountBaseR", "MountR", "ShieldR", "Rail1L", "Rail2L", "Rail3L", "KnuckleL", "Rail1R", "Rail2R", "Rail3R", "KnuckleR"):
    FOLLOW[n] = "Torso"
STRAIGHT = {"UpperArmL", "LowerArmL", "UpperArmR", "LowerArmR"}   # 복셀 격자 = 곧은 팔(템플릿 쉬는 자세)
BLADE_IN_RIFLE = None
A3 = np.array([[-1.0, 0, 0], [0, 0, 1], [0, 1, 0]])
MS = np.eye(4); MS[:3, :3] = A3 * 0.1                              # 복셀 칸 → Studio
MB = np.linalg.inv(MS)


def rx(a): a = np.radians(a); c, s = np.cos(a), np.sin(a); m = np.eye(4); m[1:3, 1:3] = [[c, -s], [s, c]]; return m
def ry(a): a = np.radians(a); c, s = np.cos(a), np.sin(a); m = np.eye(4); m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, s, -s, c; return m
def rz(a): a = np.radians(a); c, s = np.cos(a), np.sin(a); m = np.eye(4); m[0:2, 0:2] = [[c, -s], [s, c]]; return m
def E(x=0, y=0, z=0): return ry(y) @ rx(x) @ rz(z)
def T(x=0, y=0, z=0): m = np.eye(4); m[:3, 3] = [x, y, z]; return m
inv = np.linalg.inv


PAD = dict(hingeX=0.9, hingeY=2.0, z0=15)   # SHAPES.Valkyrie.pad


def pad_transform(sh, side):
    """MechPoses padTransform 이식: 어깨 Transform → 어깨 장갑 Transform(side 1 = 왼 · −1 = 오른)."""
    d = sh[:3, :3] @ np.array([0, -1.0, 0])
    th = np.arctan2(-d[2], -d[1])
    if th < -np.radians(120): th += 2 * np.pi
    ph = np.degrees(np.arcsin(np.clip(-side * d[0], -1, 1)))
    lat = np.radians(max(0, ph - PAD["z0"]))
    h = np.array([side * PAD["hingeX"], PAD["hingeY"], 0])
    return rx(np.degrees(th)) @ T(*h) @ rz(np.degrees(-side * lat)) @ T(*(-h))


def fk(P, root=None):
    P = dict(P)
    for sd, sg in (("L", 1), ("R", -1)):
        if "Pad" + sd not in P and "Shoulder" + sd in P: P["Pad" + sd] = pad_transform(P["Shoulder" + sd], sg)
    W = {"HumanoidRootPart": root if root is not None else REST["HumanoidRootPart"]}
    ch = True
    while ch:
        ch = False
        for n, (p0, p1, c0, c1) in J.items():
            if p0 in W and p1 not in W:
                W[p1] = W[p0] @ c0 @ P.get(n, np.eye(4)) @ inv(c1); ch = True
    return W


def solve_arm(S, a, b, target, poleW):
    """MechPoses solveArm 이식(Luau 와 같은 식). S = 어깨 관절 틀(월드 4x4)."""
    t = (inv(S) @ np.append(target, 1))[:3]
    d = np.linalg.norm(t)
    K = (d * d - a @ a - b @ b) / 2 - a[0] * b[0]
    P1 = a[1] * b[1] + a[2] * b[2]; Q1 = a[2] * b[1] - a[1] * b[2]
    R = np.hypot(P1, Q1)
    th = np.arctan2(Q1, P1) + np.arccos(np.clip(K / R, -1, 1))
    v = a + np.array([b[0], b[1] * np.cos(th) - b[2] * np.sin(th), b[1] * np.sin(th) + b[2] * np.cos(th)])
    X1 = v / np.linalg.norm(v)
    hinge = np.array([1.0, 0, 0]) - X1 * X1[0]
    Y1 = np.cross(X1, hinge); Y1 /= np.linalg.norm(Y1)
    X2 = t / np.linalg.norm(t)
    p = S[:3, :3].T @ poleW
    Y2 = p - X2 * (p @ X2); Y2 /= np.linalg.norm(Y2)
    F1 = np.eye(4); F1[:3, :3] = np.stack([X1, Y1, np.cross(X1, Y1)], 1)
    F2 = np.eye(4); F2[:3, :3] = np.stack([X2, Y2, np.cross(X2, Y2)], 1)
    return F2 @ inv(F1), th


def right_hand(P, rh, pole_local):
    """MechPoses axeRightHand 와 같은 식: 사벨 손잡이 로컬 (0, rh, 0) 에 오른 주먹(Grip 관절 점). pole = 몸통 로컬."""
    W = fk(P)
    Tt = W["Torso"]
    target = (W["SaberHilt"] @ np.array([0, rh, 0, 1.0]))[:3]
    _, _, c0s, c1s = J["ShoulderR"]; _, _, c0e, c1e = J["ElbowR"]
    gC0 = CF((0.28029, -2.70493, 0.0945))
    S = Tt @ c0s
    a = (inv(c1s) @ c0e)[:3, 3]
    b = (inv(c1e) @ gC0)[:3, 3]
    Rs, th = solve_arm(S, a, b, target, Tt[:3, :3] @ np.array(pole_local, float))
    Q = dict(P); Q["ShoulderR"] = Rs; Q["ElbowR"] = rx(np.degrees(th))
    W2 = fk(Q)
    fist = (W2["LowerArmR"] @ gC0)[:3, 3]
    return Q, float(np.linalg.norm(fist - target))


# ---------------- 복셀 ----------------
_MODEL = {}
def model():
    if not _MODEL:
        with contextlib.redirect_stdout(io.StringIO()):
            M, info = G2.build()
            B, h = HL.build(); HL.blade_fx(B)
        _MODEL["M"], _MODEL["B"] = M, B
    return _MODEL["M"], _MODEL["B"]


def weapon_frame(W, weapon):
    if weapon == "rifle": return W["Rifle"] @ inv(VH_IN_HILT) @ BLADE_IN_HILT
    return W["SaberHilt"] @ BLADE_IN_HILT


def blocks(P, blade=True, beam=True, skip=(), weapon="saber"):
    M, B = model()
    W = fk(P)
    out = []
    for n, p in M.parts.items():
        f = FOLLOW.get(n)
        if f is None or n in skip: continue
        D = W[f] @ inv(REST[f])
        Wb = np.eye(4) if n in STRAIGHT else M.world(n)
        out.append((p.lo, p.a, MB @ D @ MS @ Wb))
    if blade:
        for n, p in B.parts.items():
            if n == "BladeFX" and not beam: continue
            out.append((p.lo, p.a, MB @ weapon_frame(W, weapon) @ MS @ B.world(n)))
    return out


def cells(P, which):
    """which: 'blade' · 'beam' · 'body' · 'armL' · 'armR' → 월드 복셀 칸(정수) 집합."""
    M, B = model()
    W = fk(P); s = set()
    if which in ("blade", "beam"):
        for n, p in B.parts.items():
            if (n == "BladeFX") != (which == "beam"): continue
            ijk = np.argwhere(p.a > 0) + p.lo
            Tm = MB @ W["SaberHilt"] @ BLADE_IN_HILT @ MS @ B.world(n)
            s |= set(map(tuple, np.round(ijk @ Tm[:3, :3].T + Tm[:3, 3]).astype(int)))
        return s
    names = {"armL": ("UpperArmL", "LowerArmL"), "armR": ("UpperArmR", "LowerArmR")}.get(which)
    for n, p in M.parts.items():
        f = FOLLOW.get(n)
        if f is None: continue
        if names is not None and n not in names: continue
        if names is None and n in ("UpperArmL", "LowerArmL", "UpperArmR", "LowerArmR"): continue
        D = W[f] @ inv(REST[f]); Wb = np.eye(4) if n in STRAIGHT else M.world(n)
        Tm = MB @ D @ MS @ Wb
        ijk = np.argwhere(p.a > 0) + p.lo
        s |= set(map(tuple, np.round(ijk @ Tm[:3, :3].T + Tm[:3, 3]).astype(int)))
    return s


def render(P, yaw=30, pitch=10, ppc=1.6, light=None, **kw):
    M, B = model()
    pal = dict(G2.B.PAL); pal.update(HL.PAL)
    k = dict(light=light) if light else {}
    return Vp.render(blocks(P, **kw), pal, G2.B.EMISSIVE, yaw=yaw, pitch=pitch, ppc=ppc, bg=H.BG, ground=True, shadow_res=6, shadow_k=6, **k)
