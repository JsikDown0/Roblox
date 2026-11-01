"""keys2.py — AELLO 승리 포즈 v2: 유저 해석대로 (2026-10-29 15:38)
흐름(유저): 고개 숙인 로봇 → 칼에서 스파크 튀며 철컥 → 고개 들고 눈 번쩍 → 칼을 반 바퀴 반대편으로 돌림 + 빈손은 카메라로
            (에일로 = 주먹 쭉 내밀기, 15:38 결정) → 자세 고쳐 잡고 칼을 앞으로 들어 보이며 마무리.
에일로 옮김: 왼손 = 빔 꺼진 칼자루(처음부터 쥠) · 라이플은 허리 뒤(게임 사벨 상태와 같음) → 오른손 빈손.
자세 값 = Studio 관절 Transform(E = Ry·Rx·Rz, 도). 팔은 '주먹 자리(몸통 로컬 칸) + 날 방향' 목표를 IK 로(겹침 가장 적은 해).
"""
import os
import pickle

import numpy as np
from scipy.optimize import least_squares

import keys as K1
import vpose as V
from keys import legs, pads, skirts, slerp_R, euler_of
from vpose import E

FIST_R = (-40, 0, 125)

BODY = {
    # K0 고개 숙인 대기 — 꺼진 칼자루를 몸 앞에 비스듬히(레퍼런스 0.1초: 큰 칼을 몸 앞 대각선으로)
    "K0": {"Waist": E(-8), "Neck": E(-26), "ShoulderR": E(4, 0, 8), "ElbowR": E(18), **legs(6, 6, -12, -12), "Wings": (0, 0, 0)},
    # K1 철컥 + 불똥 — 칼자루를 짧게 튕겨 올림(머리는 아직 숙임)
    "K1": {"Waist": E(-6), "Neck": E(-24), "ShoulderR": E(4, 0, 8), "ElbowR": E(18), **legs(6, 6, -12, -12), "Wings": (0, 0, 0)},
    # K2 고개 듦 + 눈 번쩍
    "K2": {"Waist": E(2), "Neck": E(4), "ShoulderR": E(4, 0, 10), "ElbowR": E(20), **legs(4, 4, -8, -8), "Wings": (6, 0, 0)},
    # K3 반 바퀴 중간 — 날이 앞 아래를 지나며 점화(레퍼런스 1.9~2.2초 빔이 회전 중에 켜짐) · 날개 펴짐
    "K3": {"Waist": E(-4, 14), "Neck": E(2, -8), "ShoulderR": E(8, 0, 14), "ElbowR": E(26), **legs(10, 6, -18, -12), "Wings": (40, 8, 6)},
    # K4 반 바퀴 끝 — 날이 반대편(왼쪽 뒤 위)
    "K4": {"Waist": E(2, 24), "Neck": E(4, -14), "ShoulderR": E(10, 0, 16), "ElbowR": E(30), **legs(10, 4, -18, -10), "Wings": (60, 14, 8)},
    # K5 빈 오른주먹을 카메라 쪽으로 쭉(레퍼런스 2.67초 손바닥)
    "K5": {"Waist": E(-2, -22), "Neck": E(2, 10), **legs(14, 2, -24, -10), "Wings": (60, 16, 8)},
    # K6 자세 고쳐 잡기 — 주먹 거두고 칼을 앞 위로 높이(레퍼런스 3.07초)
    "K6": {"Waist": E(4, 4), "Neck": E(6, 0), **legs(18, -8, -30, -10, zr=6), "Wings": (60, 18, 8)},
    # K7 마무리 — 낮고 넓게 벌림(왼발 앞), 칼끝 머리 높이로 앞을 겨눔, 오른주먹 허리 뒤(레퍼런스 3.33~4.67초)
    "K7": {"Root": E(-8, -22, 0), "Waist": E(-6, 12), "Neck": E(10, 12), **legs(62, -34, -66, -12, ar=8, zl=-6, zr=10), "Wings": (62, 20, 10)},
}
L_T = {   # 왼팔(칼): 몸통 로컬 주먹 자리 · 날 방향 · 팔꿈치 쪽
    "K0": dict(fist=(36, -50, 168), blade=(-0.55, -0.35, 0.76), pole=(1, 0, -0.4)),
    "K1": dict(fist=(30, -48, 168), blade=(-0.6, -0.4, 0.69), pole=(1, 0, -0.4)),
    "K2": dict(fist=(32, -48, 170), blade=(-0.6, -0.4, 0.69), pole=(1, 0, -0.4)),
    "K3": dict(fist=(58, -58, 176), blade=(0.25, -0.75, -0.6), pole=(1, 0.2, -0.3)),
    "K4": dict(fist=(92, -34, 222), blade=(0.45, -0.2, 0.87), pole=(1, 0.1, 0.1)),
    "K5": dict(fist=(94, -28, 226), blade=(0.45, -0.1, 0.89), pole=(1, 0.1, 0.1)),
    "K6": dict(fist=(40, -78, 282), blade=(-0.05, -0.55, 0.84), pole=(1, -0.2, -0.3)),
    "K7": dict(fist=(34, -96, 250), blade=(-0.1, -0.97, 0.2), pole=(1, 0, -0.5)),
}
R_T = {   # 오른팔(빈손): 몸통 로컬 주먹 자리 · 팔꿈치 쪽
    "K5": dict(fist=(-30, -100, 238), pole=(-1, 0, -0.6)),
    "K6": dict(fist=(-52, -30, 176), pole=(-1, 0.3, -0.5)),
    "K7": dict(fist=(-62, -30, 168), pole=(-1, 0.3, -0.3)),
}
ORDER = ["K0", "K1", "K2", "K3", "K4", "K5", "K6", "K7"]
LABEL = {"K0": "고개 숙인 대기", "K1": "철컥 + 불똥", "K2": "고개 듦·눈 번쩍", "K3": "반 바퀴 중(점화)", "K4": "반 바퀴 끝",
         "K5": "주먹 쭉(카메라로)", "K6": "고쳐 잡기(칼 위로)", "K7": "마무리 — 앞으로 겨눔"}
TIMES = {"K0": 0.0, "K1": 0.38, "K2": 0.72, "K3": 1.75, "K4": 2.15, "K5": 2.55, "K6": 3.15, "K7": 3.45}
END = 4.7
HOLD = {"K2": 1.30, "K5": 2.85}      # 이 시각까지 그 키 자세를 유지(작은 숨)
UNLIT = ("K0", "K1", "K2")          # 빔 꺼진 키(풀이·겹침은 칼자루만)

# ---------------------------------------------------------------- 오른팔 IK(빈손)
R_HITS = ("Head", "Torso", "ChestL", "ChestR", "Pelvis", "SkirtFR", "SkirtSR", "UpperLegR", "LowerLegR", "BinderR", "WingR", "RifleStowed")


def _buildR(P, x):
    Q = dict(P)
    Q["ShoulderR"] = E(*x[0:3]); Q["ElbowR"] = E(x[3])
    return Q


def solve_right(M, P, spec, starts=16, seed=2):
    _, cache = V.blocks(M, P)
    Tt = cache["Torso"]
    tgt = Tt[:3, :3] @ np.asarray(spec["fist"], float) + Tt[:3, 3]
    pw = Tt[:3, :3] @ (np.asarray(spec["pole"], float) / np.linalg.norm(spec["pole"]))

    def res(x):
        _, c = V.blocks(M, _buildR(P, x))
        L = c["LowerArmR"]
        fist = L[:3, :3] @ np.array(FIST_R, float) + L[:3, 3]
        elbow = L[:3, :3] @ np.array([-40, 0, 184.0]) + L[:3, 3]
        sh = c["UpperArmR"][:3, :3] @ np.array([-40, 0, 228.0]) + c["UpperArmR"][:3, 3]
        v = elbow - (sh + fist) / 2; n = np.linalg.norm(v)
        return list(fist - tgt) + (list(((v / n) - pw) * 4) if n > 1e-6 else [0, 0, 0]) + [x[1] * 0.01]

    rng = np.random.default_rng(seed)
    cands = []
    for i in range(starts):
        x0 = np.array([rng.uniform(-90, 180), rng.uniform(-60, 60), rng.uniform(-40, 90), rng.uniform(5, 130)])
        s = least_squares(res, x0, bounds=([-200, -180, -180, 0], [200, 180, 180, 150]))
        Q = _buildR(P, s.x)
        _, c = V.blocks(M, Q)
        L = c["LowerArmR"]
        err = np.linalg.norm(L[:3, :3] @ np.array(FIST_R, float) + L[:3, 3] - tgt)
        if err > 2.0:
            continue
        hits = [n for n in R_HITS if n in M.parts]
        ov = V.overlaps(M, skirts(pads(dict(Q))), [(a, b) for a in ("UpperArmR", "LowerArmR") for b in hits])
        cands.append((sum(ov.values()), s.cost, s.x, ov, err))
    cands.sort(key=lambda c: (c[0], c[1]))
    hit, cost, x, ov, err = cands[0]
    return _buildR(P, x), dict(x=np.round(x, 1), fist_err=round(float(err), 2), overlap=hit,
                              worst={"%s/%s" % k: v for k, v in sorted(ov.items(), key=lambda kv: -kv[1])[:3] if v})


# ---------------------------------------------------------------- 키 꺼내기(풀이 캐시)
_CF = "solved2.pkl"
SOLVED = {}


def _sig(name):
    return repr((L_T.get(name), R_T.get(name), {k: (np.round(v, 4).tolist() if isinstance(v, np.ndarray) else v) for k, v in sorted(BODY[name].items())}))


def get(name, Ms):
    """Ms = {"lit": 빔 켠 모델, "hilt": 칼자루만}"""
    M = Ms["hilt"] if name in UNLIT else Ms["lit"]
    if name not in SOLVED:
        disk = pickle.load(open(_CF, "rb")) if os.path.exists(_CF) else {}
        if name in disk and disk[name][0] == _sig(name):
            SOLVED[name] = disk[name][1]
        else:
            P = dict(BODY[name]); info = {}
            if name in L_T:
                P, info["L"] = K1.solve_arm(M, P, L_T[name])
            if name in R_T:
                P, info["R"] = solve_right(M, P, R_T[name])
            P = skirts(pads(P))
            P["RootT"] = K1.ground(M, P)
            SOLVED[name] = (P, info)
            disk[name] = (_sig(name), SOLVED[name]); pickle.dump(disk, open(_CF, "wb"))
    return dict(SOLVED[name][0])
