"""keys.py — AELLO 승리 포즈 키 자세 + 시각표 (2026-10-29)
자세 값 = Studio 관절 Transform(E = Ry·Rx·Rz, 도, 템플릿 축). 몸·다리는 손으로, 왼팔(사벨)은 '주먹 자리 + 날 방향' 목표를 IK 로 풂
(여러 시작점 → 몸과 겹침이 가장 적은 해). Grip(라이플)은 0 = 쉬는 자세 그대로(관절 틀이 템플릿 축이 아니라서 돌리지 않음).
"""
import numpy as np
from scipy.optimize import least_squares

import vpose as V
from vpose import E

# ---------------------------------------------------------------- 보조
def legs(hl, hr, kl, kr, al=None, ar=None, yl=0, yr=0, zl=0, zr=0):
    return {"HipL": E(hl, yl, zl), "HipR": E(hr, yr, zr), "KneeL": E(kl), "KneeR": E(kr),
            "AnkleL": E(-0.6 * (hl + kl) if al is None else al), "AnkleR": E(-0.6 * (hr + kr) if ar is None else ar)}


def slerp_R(A, B, a):
    R = A.T @ B
    ang = np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1))
    if ang < 1e-6:
        return A.copy()
    if ang > np.pi - 1e-4:
        w, v = np.linalg.eigh((R + R.T) / 2); ax = v[:, np.argmax(w)]
    else:
        ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * np.sin(ang))
    return A @ V.rot_axis(ax, np.degrees(ang) * a)


def euler_of(R):
    """R = Ry(y)·Rx(x)·Rz(z) → (x, y, z) 도 (CFrame:ToEulerAnglesYXZ 와 같은 순서)"""
    x = np.degrees(np.arcsin(np.clip(-R[1, 2], -1, 1)))
    y = np.degrees(np.arctan2(R[0, 2], R[2, 2]))
    z = np.degrees(np.arctan2(R[1, 0], R[1, 1]))
    return np.round([x, y, z], 1)


def pads(P):
    """어깨 장갑: 팔 회전의 45% 를 따라감 — 미리보기용 근사(게임은 MechClient 경첩 식) [추측]."""
    for s in "LR":
        if "Shoulder" + s in P:
            P["Pad" + s] = slerp_R(np.eye(3), P["Shoulder" + s], 0.45)
    return P


def skirts(P):
    """앞 스커트 = 허벅지 앞 들림의 70%, 옆 스커트 = 벌림의 60% (미리보기 근사)."""
    for s, sg in (("L", -1), ("R", 1)):
        x, y, z = euler_of(P.get("Hip" + s, np.eye(3)))
        P["SkirtJointF" + s] = E(max(0.0, x) * 0.7)
        P["SkirtJointS" + s] = E(0, 0, (z * 0.6) if z * sg > 0 else 0)
    return P


# ---------------------------------------------------------------- 키(몸·다리·오른팔)
BASE_ARMS = {"ShoulderL": E(4, 0, -9), "ElbowL": E(16), "ShoulderR": E(10, 0, 10), "ElbowR": E(40)}

BODY = {
    # K0 고개 숙인 대기(발광 낮춤)
    "K0": {"RootT": (0, -0.3, 0), "Waist": E(-7), "Neck": E(-24), **BASE_ARMS, **legs(5, 5, -10, -10), "Wings": (0, 0, 0)},
    # K1 눈 번쩍 + 고개 듦
    "K1": {"RootT": (0, 0, 0), "Waist": E(2), "Neck": E(5), **BASE_ARMS, **legs(3, 3, -6, -6), "Wings": (4, 0, 0)},
    # K2 왼손을 어깨 위 바깥으로(머리를 피해 칼자루로 가는 길)
    "K2": {"RootT": (0, -0.2, 0), "Waist": E(2, 10), "Neck": E(0, -10), "ShoulderR": E(12, 0, 16), "ElbowR": E(42),
           **legs(6, 4, -12, -9), "Wings": (4, 0, 0)},
    # K3 등 칼자루 잡기(날개는 아직 접힘 — 팔이 지나갈 자리)
    "K3": {"RootT": (0, -0.5, 0), "Waist": E(-2, 14), "Neck": E(0, -12), "ShoulderR": E(14, 0, 18), "ElbowR": E(44),
           **legs(10, 6, -18, -12), "Wings": (2, 0, 0)},
    # K4 뽑아 하늘로 + 점화(날개 펴기 시작)
    "K4": {"RootT": (0, -0.2, 0), "Waist": E(6, 20), "Neck": E(6, -14), "ShoulderR": E(16, 0, 26), "ElbowR": E(46),
           **legs(8, 4, -14, -10), "Wings": (28, 6, 4)},
    # K5 치켜든 채 날개 활짝 + 가슴 폄(멈춤 박자)
    "K5": {"RootT": (0, -0.1, 0), "Waist": E(9, 22), "Neck": E(8, -16), "ShoulderR": E(14, 0, 30), "ElbowR": E(44),
           **legs(6, 3, -12, -8), "Wings": (62, 14, 8)},
    # K6a 베는 중(경유): 앞 위 — 175° 휘두름을 몸 앞 수직 호로 지나가게
    "K6a": {"RootT": (0, -0.7, 0), "Waist": E(-8, 4), "Neck": E(8, -2), "ShoulderR": E(0, 0, 30), "ElbowR": E(48),
            **legs(18, 0, -32, -14), "Wings": (58, 18, 8)},
    # K6 왼쪽 앞으로 내려벰(몸 바깥 수직 베기)
    "K6": {"RootT": (0, -1.2, 0), "Waist": E(-18, -8), "Neck": E(10, 6), "ShoulderR": E(-8, 0, 30), "ElbowR": E(50),
           **legs(26, -4, -46, -18), "Wings": (54, 22, 8)},
    # K7 휘두름이 뒤로 빠지며 박차고 뜸
    "K7": {"RootT": (0, 2.4, 0), "Root": E(-8), "Waist": E(-10, 4), "Neck": E(8, 6), "ShoulderR": E(20, 0, 20), "ElbowR": E(34),
           **legs(36, -6, -70, -40), "Wings": (54, 24, 8)},
    # K8 결정 자세(공중 정지): 사벨 뒤로 길게 · 라이플 앞 아래 · 왼 무릎 앞
    "K8": {"Root": E(-14, 0, 3), "RootT": (0, 5.0, 0), "Waist": E(-4, 10), "Neck": E(10, 20), "ShoulderR": E(24, 0, 16), "ElbowR": E(28),
           **legs(56, -22, -104, -50, al=38, ar=34, zl=-6, zr=4), "Wings": (60, 20, 10)},
}
# 왼팔 목표(몸통 로컬 칸 · 몸통 로컬 방향). blade=None 이면 빈손(주먹 자리만)
ARM_T = {
    "K2": dict(fist=(66, -6, 300), blade=None, pole=(1, -0.2, -0.3)),
    "K3": dict(grab=True, pole=(0.7, -0.3, 0.6)),
    "K4": dict(fist=(30, 4, 322), blade=(-0.1, 0.35, 0.93), pole=(1, -0.3, 0)),
    "K5": dict(fist=(34, 10, 324), blade=(-0.12, 0.42, 0.9), pole=(1, -0.3, 0)),
    "K6a": dict(fist=(50, -82, 262), blade=(0.08, -0.9, 0.42), pole=(1, 0, -0.2)),
    "K6": dict(fist=(52, -70, 182), blade=(0.12, -0.62, -0.78), pole=(1, 0.2, -0.3)),
    "K7": dict(fist=(70, 28, 172), blade=(0.25, 0.72, -0.64), pole=(1, 0, -0.1)),
    "K8": dict(fist=(68, 48, 186), blade=(0.5, 0.86, -0.08), pole=(1, 0.1, 0.0)),
}
ORDER = ["K0", "K1", "K2", "K3", "K4", "K5", "K6a", "K6", "K7", "K8"]
LABEL = {"K0": "숙인 대기", "K1": "눈 번쩍·고개 듦", "K2": "손 올림", "K3": "칼자루 잡기", "K4": "뽑아 하늘로·점화",
         "K5": "날개 활짝", "K6a": "베는 중(경유)", "K6": "내려 베기", "K7": "뒤로 빠지며 뜸", "K8": "결정 자세(정지)"}
TIMES = {"K0": 0.0, "K1": 0.70, "K2": 1.05, "K3": 1.30, "K4": 1.70, "K5": 2.10, "K6a": 2.36, "K6": 2.50, "K7": 2.85, "K8": 3.35}
END = 4.6

# ---------------------------------------------------------------- 왼팔 IK
ARM_HITS = ("Head", "Torso", "ChestL", "ChestR", "Pelvis", "SkirtFL", "SkirtSL", "UpperLegL", "LowerLegL", "BinderL", "WingL")


def _fist_blade(c):
    S = c["Saber"]
    return S[:3, :3] @ np.array(V.FIST_L, float) + S[:3, 3], S[:3, :3] @ np.array([0, -1.0, 0]), S[:3, :3] @ np.array([0, 1.0, 0])


def _build(P, x):
    Q = dict(P)
    Q["ShoulderL"] = E(*x[0:3]); Q["ElbowL"] = E(x[3]); Q["SaberGrip"] = E(x[4], 0, 0)
    return Q


def solve_arm(M, P, spec, starts=24, seed=1):
    _, cache = V.blocks(M, P)
    Tt = cache["Torso"]
    if spec.get("grab"):
        Th = cache["SaberHolsterL"]
        tgt = Th[:3, :3] @ np.array([8, 29, 261.0]) + Th[:3, 3]
        want, wkey = Th[:3, :3] @ np.array([0, 0, 1.0]), "pom"          # 끝마개 = 칼집 위
    else:
        tgt = Tt[:3, :3] @ np.asarray(spec["fist"], float) + Tt[:3, 3]
        want = None if spec["blade"] is None else Tt[:3, :3] @ (np.asarray(spec["blade"], float) / np.linalg.norm(spec["blade"]))
        wkey = "blade"
    pw = Tt[:3, :3] @ (np.asarray(spec["pole"], float) / np.linalg.norm(spec["pole"]))

    def res(x):
        _, c = V.blocks(M, _build(P, x))
        fist, blade, pom = _fist_blade(c)
        r = list(fist - tgt)
        if want is not None:
            r += list(((pom if wkey == "pom" else blade) - want) * 40)
        else:
            r += [x[4] * 0.05]
        L = c["LowerArmL"]
        elbow = L[:3, :3] @ np.array([40, 0, 184.0]) + L[:3, 3]
        sh = c["UpperArmL"][:3, :3] @ np.array([40, 0, 228.0]) + c["UpperArmL"][:3, 3]
        v = elbow - (sh + fist) / 2; n = np.linalg.norm(v)
        r += list(((v / n) - pw) * 4) if n > 1e-6 else [0, 0, 0]
        r += [x[1] * 0.01]
        return r

    rng = np.random.default_rng(seed)
    cands = []
    for i in range(starts):
        x0 = np.array([rng.uniform(-90, 180), rng.uniform(-60, 60), rng.uniform(-90, 40), rng.uniform(10, 130), rng.uniform(-120, 60)])
        s = least_squares(res, x0, bounds=([-200, -180, -180, 0, -130], [200, 180, 180, 150, 70]))
        Q = _build(P, s.x)
        _, c = V.blocks(M, Q)
        fist, blade, pom = _fist_blade(c)
        err = np.linalg.norm(fist - tgt)
        if err > 2.0:
            continue
        movers = ["UpperArmL", "LowerArmL"] + (["Saber"] if not spec.get("grab") and spec.get("blade") is not None else [])
        hits = [n for n in ARM_HITS if n in M.parts]
        ov = V.overlaps(M, skirts(pads(dict(Q))), [(a, b) for a in movers for b in hits])
        cands.append((sum(ov.values()), s.cost, s.x, ov, err))
    cands.sort(key=lambda c: (c[0], c[1]))
    hit, cost, x, ov, err = cands[0]
    return _build(P, x), dict(x=np.round(x, 1), fist_err=round(float(err), 2), overlap=hit,
                             worst={"%s/%s" % k: v for k, v in sorted(ov.items(), key=lambda kv: -kv[1])[:3] if v})


SOLVED = {}
_CF = "solved.pkl"


def _sig(name):
    return repr((ARM_T[name], {k: (np.round(v, 4).tolist() if isinstance(v, np.ndarray) else v) for k, v in sorted(BODY[name].items())}))


def get(name, M):
    import os, pickle
    P = dict(BODY[name])
    if name in ARM_T:
        if name not in SOLVED:
            disk = pickle.load(open(_CF, "rb")) if os.path.exists(_CF) else {}
            if name in disk and disk[name][0] == _sig(name):
                SOLVED[name] = disk[name][1]
            else:
                SOLVED[name] = solve_arm(M, P, ARM_T[name])
                disk[name] = (_sig(name), SOLVED[name]); pickle.dump(disk, open(_CF, "wb"))
        P = dict(SOLVED[name][0])
    P = skirts(pads(P))
    if name in GROUND:
        P["RootT"] = ground(M, P)
    return P


GROUND = ("K0", "K1", "K2", "K3", "K4", "K5", "K6a", "K6")
_FOOT = {}


def ground(M, P):
    """발바닥 가장 낮은 점이 z=0 이 되게 Root 높이를 맞춤(게임은 웅크림 표가 같은 일을 함)."""
    _, c = V.blocks(M, P)
    lo = 1e9
    for n in ("FootL", "FootR"):
        if n not in _FOOT:
            p = M.parts[n]; _FOOT[n] = (np.argwhere(p.a > 0) + p.lo).astype(float)
        T = c[n]; lo = min(lo, float((_FOOT[n] @ T[:3, :3].T + T[:3, 3])[:, 2].min()))
    x, y, z = P.get("RootT", (0, 0, 0))
    return (x, round(y - lo / 10.0, 3), z)
