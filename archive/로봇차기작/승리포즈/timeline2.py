"""timeline2.py — v2 보간 + 연출 상태"""
import numpy as np
import keys2 as K
import keys as K1
import vpose as V
from keys import slerp_R

SEQ = []
for k in K.ORDER:
    SEQ.append((K.TIMES[k], k))
    if k in K.HOLD:
        SEQ.append((K.HOLD[k], k))
SEQ.sort()
# 구간 이징(구간 시작 키 기준): s 부드럽게 · in 가속 · out 감속
EASE = {0: "s", 1: "s", 2: "s", 3: "in", 4: "out", 5: "s", 6: "s", 7: "s", 8: "s", 9: "s"}
IGNITE = (1.55, 1.70)        # 반 바퀴 도는 중 점화
SPARK = (0.30, 0.62)         # 철컥 불똥
EYE = 0.74                   # 눈 번쩍 정점
FLAME = (1.95, 2.15)         # 날개 다 펴질 때 등 노즐 불꽃
BREATH = (0.12, 1.8)         # 정지 자세 숨(스터드, 주기)

_M = {}
def models():
    if not _M:
        _M["lit"] = V.model(saber=1.0, rifle=False, stowed=True)
        _M["hilt"] = V.model(saber=0.0, rifle=False, stowed=True)
    return _M

def ease(a, kind):
    if kind == "in": return a ** 2.0
    if kind == "out": return 1 - (1 - a) ** 2.0
    return a * a * (3 - 2 * a)

def _blend(A, B, a):
    out = {}
    for j in set(A) | set(B):
        if j in ("RootT", "Wings"):
            ta = np.asarray(A.get(j, (0, 0, 0)), float); tb = np.asarray(B.get(j, (0, 0, 0)), float)
            out[j] = tuple(ta + (tb - ta) * a)
        else:
            out[j] = slerp_R(np.asarray(A.get(j, np.eye(3))), np.asarray(B.get(j, np.eye(3))), a)
    return out

def pose_at(t):
    Ms = models()
    if t >= SEQ[-1][0]:
        P = K.get(SEQ[-1][1], Ms)
        br = 0.5 - 0.5 * np.cos((t - SEQ[-1][0]) / BREATH[1] * 2 * np.pi)          # 숨: 허리만 1.5° 오르내림
        P["Waist"] = P["Waist"] @ V.Rx(1.5 * br)
        return P
    i = max(i for i, (tt, _) in enumerate(SEQ) if tt <= t)
    (t0, a), (t1, b) = SEQ[i], SEQ[i + 1]
    u = (t - t0) / (t1 - t0)
    P = _blend(K.get(a, Ms), K.get(b, Ms), ease(u, EASE.get(i, "s")))
    P["RootT"] = K1.ground(Ms["lit"], P)                                            # 키 사이에도 발바닥 = 땅
    return P

def state(t):
    lit = float(np.clip((t - IGNITE[0]) / (IGNITE[1] - IGNITE[0]), 0, 1))
    spark = float(np.clip((t - SPARK[0]) / (SPARK[1] - SPARK[0]), 0, 1)) if SPARK[0] <= t <= SPARK[1] else (0.0 if t < SPARK[0] else -1)
    eye = float(np.exp(-((t - EYE) / 0.1) ** 2)) if t < EYE else float(np.exp(-(t - EYE) / 0.3))
    flame = float(np.clip((t - FLAME[0]) / (FLAME[1] - FLAME[0]), 0, 1))
    glow = 0.18 if t < EYE - 0.06 else 1.0
    return pose_at(t), lit, spark, eye, flame, glow
