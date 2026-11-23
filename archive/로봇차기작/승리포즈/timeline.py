"""timeline.py — 키 사이 보간 + 연출 상태(사벨 위치·점화, 불꽃, 눈 번쩍) (2026-10-29)"""
import numpy as np

import keys as K
import vpose as V

ORDER = K.ORDER
# 구간 이징: s = 부드럽게 · in = 가속(베기) · out = 감속(뜸·멈춤)
EASE = {"K0": "s", "K1": "s", "K2": "s", "K3": "s", "K4": "out", "K5": "in", "K6a": "out", "K6": "out", "K7": "out"}
GRAB_AT = K.TIMES["K3"]
IGNITE = (1.72, 1.84)        # 하늘로 치켜든 순간 점화(날이 0 → 다 나옴)
FLAME = (2.62, 2.80)         # 박차기 직전부터 불꽃
EYE = 0.70                   # 눈 번쩍 정점
BOB = (0.22, 1.6)            # 정지 자세 둥실(스터드, 주기 초)


def ease(a, kind):
    if kind == "in":
        return a ** 2.2
    if kind == "out":
        return 1 - (1 - a) ** 2.2
    return a * a * (3 - 2 * a)


def _blend(A, B, a):
    out = {}
    for j in set(A) | set(B):
        if j == "RootT":
            ta = np.asarray(A.get(j, (0, 0, 0)), float); tb = np.asarray(B.get(j, (0, 0, 0)), float)
            out[j] = tuple(ta + (tb - ta) * a)
        elif j == "Wings":
            wa = np.asarray(A.get(j, (0, 0, 0)), float); wb = np.asarray(B.get(j, (0, 0, 0)), float)
            out[j] = tuple(wa + (wb - wa) * a)
        else:
            out[j] = K.slerp_R(np.asarray(A.get(j, np.eye(3))), np.asarray(B.get(j, np.eye(3))), a)
    return out


_CACHE = {}


def key(name, M):
    if name not in _CACHE:
        _CACHE[name] = K.get(name, M)
    return _CACHE[name]


def state(t, M):
    """→ pose, saber(None=칼집 | 0..1 점화), flame(0..1), eye(0..1)"""
    times = [K.TIMES[k] for k in ORDER]
    if t >= times[-1]:
        P = dict(key(ORDER[-1], M))
        ph = (t - times[-1]) / BOB[1] * 2 * np.pi
        x, y, z = P.get("RootT", (0, 0, 0))
        P["RootT"] = (x, y + BOB[0] * np.sin(ph), z)
    else:
        i = max(i for i, tt in enumerate(times) if tt <= t)
        a = (t - times[i]) / (times[i + 1] - times[i])
        P = _blend(key(ORDER[i], M), key(ORDER[i + 1], M), ease(a, EASE[ORDER[i]]))
    saber = None if t < GRAB_AT else float(np.clip((t - IGNITE[0]) / (IGNITE[1] - IGNITE[0]), 0, 1))
    flame = float(np.clip((t - FLAME[0]) / (FLAME[1] - FLAME[0]), 0, 1))
    eye = float(np.exp(-((t - EYE) / 0.12) ** 2)) if t < EYE else float(np.exp(-(t - EYE) / 0.35))
    return P, saber, flame, eye
