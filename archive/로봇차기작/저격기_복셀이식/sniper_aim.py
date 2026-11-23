"""
sniper_aim.py — 저격기 기본 사격 자세 = 두 손 견착 (2026-10-29 21:37 유저: "기본 사격 자세가 양손 사격이어야 함")

선례 = 승리포즈 aim.py(AELLO 두 손 쥐기) · 게임 줌 자세(현재상태_20261025 4-5e):
  1) 라이플 월드 틀 = 겨눔 방향 + 위 + 개머리판 끝 자리(몸통 로컬)로 먼저 정함
  2) 오른 주먹 = 그 틀의 손잡이 자리 → 오른팔 IK(자리만), 손목(라이플 파트) = 아래팔⁻¹ · 라이플 틀
  3) 왼 주먹 = 라이플의 받침 자리 → 왼팔 IK. 견착하면 팔 길이(어깨→주먹 약 88칸)로 총열 덮개까지 못 닿으므로
     게임과 같이 상체를 오른쪽으로 틀고(왼 어깨가 앞) 머리는 되돌림, 왼손은 탄창 앞 기관부 밑.
  여러 시작점 → 몸과 겹침 가장 적은 해.
조준 사격이라 머리 조준경(HeadScope)은 펼침(10-29 21:27 유저 "렌즈 전개는 조준 사격할 때").
"""
import numpy as np
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation as Rot

import sniper_v2 as S
import sniper_rifle as R
from flag_vox import rotx, rotz

SH = {"R": np.array([-27, -2, 224.0]), "L": np.array([27, -2, 224.0])}
EL = {"R": np.array([-28, -1, 196.0]), "L": np.array([28, -1, 196.0])}
FIST = {"R": np.array([-29, -1, 135.5]), "L": np.array([29, -1, 135.5])}


def rest_pt(a, b, c=0, scale=None):
    """라이플 설계 좌표(a, b, c) → 쥔 상태 쉬는 자세 칸 좌표(sniper_rifle.attach 와 같은 식)."""
    sa, sb, sc = scale or R.SCALE
    fx, fy, fz = R.FIST_R; ag, bg = R.GRIP_AB
    return np.array([fx + c * sc, fy - (b - bg) * sb, fz - (a - ag) * sa])


BUTT = rest_pt(-46, -2)          # 개머리판 끝(어깨에 닿는 자리)
SUPPORT = rest_pt(30, -11)       # 왼손: 탄창 앞 · 기관부 밑
DIR_L = np.array([0, 0, -1.0])   # 쉬는 자세 라이플 앞(총열 아래)
UP_L = np.array([0, -1.0, 0])    # 쉬는 자세 라이플 위(앞)


def rifle_frame(aim, up=(0, 0, 1)):
    a = np.asarray(aim, float); a /= np.linalg.norm(a)
    u = np.asarray(up, float); u = u - a * (u @ a); u /= np.linalg.norm(u)
    Lm = np.stack([DIR_L, UP_L, np.cross(UP_L, DIR_L)], 1)
    Wm = np.stack([a, u, np.cross(u, a)], 1)
    return Wm @ Lm.T


def W(M, name, P):
    return M.world(name, P)


def tp(T, p):
    return T[:3, :3] @ p + T[:3, 3]


def slide_scope(M):
    p = M.parts["HeadScope"]; d = np.array(M.extra["slide"]["HeadScope"])
    p.lo = p.lo + d; p.hi = p.hi + d; p.pivot = tuple(np.array(p.pivot) + d)


def overlaps(M, P, movers, others):
    """움직이는 파트 칸이 다른 파트 칸과 겹치는 수(월드 칸 반올림)."""
    occ = {}
    for n in others:
        if n not in M.parts: continue
        p = M.parts[n]; T = W(M, n, P)
        pts = (np.argwhere(p.a > 0) + p.lo).astype(float) @ T[:3, :3].T + T[:3, 3]
        occ[n] = set(map(tuple, np.round(pts).astype(int)))
    out = {}
    for m in movers:
        p = M.parts[m]; T = W(M, m, P)
        pts = set(map(tuple, np.round((np.argwhere(p.a > 0) + p.lo).astype(float) @ T[:3, :3].T + T[:3, 3]).astype(int)))
        for n, s in occ.items():
            k = len(pts & s)
            if k: out[(m, n)] = k
    return out


def pads(P):
    """어깨 장갑(ShoulderL/R, 몸통 자식) = 위팔 회전의 45% 를 따라감 — 승리포즈 keys.pads 와 같은 미리보기 근사 [추측: 게임 경첩 식은 리깅 때]."""
    for s in "LR":
        if "UpperArm" + s in P:
            P["Shoulder" + s] = Rot.from_rotvec(Rot.from_matrix(P["UpperArm" + s]).as_rotvec() * 0.45).as_matrix()
    return P


def solve(M, body, aim=(0, -1, 0), butt_t=(-15, -30, 222), support=None, poleR=(-1, 0.3, -0.6), poleL=(0.6, -0.2, -1), starts=16, seed=3):
    """body: 몸 자세(Torso·Head 등 회전). butt_t: 개머리판 끝 자리(몸통 쉬는 좌표). support: 왼손 자리(쉬는 자세 칸, 기본 SUPPORT)."""
    Rw = rifle_frame(aim)
    Tt = W(M, "Torso", body)
    butt_w = tp(Tt, np.asarray(butt_t, float))
    fistR_w = butt_w + Rw @ (FIST["R"] - BUTT)
    sup_w = butt_w + Rw @ ((SUPPORT if support is None else np.asarray(support, float)) - BUTT)
    pole = {"R": Tt[:3, :3] @ (np.asarray(poleR, float) / np.linalg.norm(poleR)),
            "L": Tt[:3, :3] @ (np.asarray(poleL, float) / np.linalg.norm(poleL))}

    def build(x):
        P = dict(body)
        for i, s in enumerate("RL"):
            P["UpperArm" + s] = Rot.from_rotvec(np.radians(x[4 * i:4 * i + 3])).as_matrix()
            P["LowerArm" + s] = rotx(x[4 * i + 3])
        TL = W(M, "LowerArmR", P)
        P["SniperRifleR"] = TL[:3, :3].T @ Rw          # 손목 = 아래팔⁻¹ · 라이플 틀
        return pads(P)

    def res(x):
        P = build(x)
        r = []
        for s, tgt in (("R", fistR_w), ("L", sup_w)):
            TL = W(M, "LowerArm" + s, P); TU = W(M, "UpperArm" + s, P)
            f = tp(TL, FIST[s]); e = tp(TU, EL[s]); sh = tp(TU, SH[s])
            r += list(f - tgt)
            v = e - (sh + f) / 2; n = np.linalg.norm(v)
            r += list(((v / n) - pole[s]) * 3) if n > 1e-6 else [0, 0, 0]
        return r

    rng = np.random.default_rng(seed)
    movers = ("UpperArmR", "LowerArmR", "UpperArmL", "LowerArmL", "SniperRifleR")
    others = [n for n in M.parts if n not in movers and not n.startswith(("UpperLeg", "LowerLeg", "Foot", "ShinBlade"))]
    base = overlaps(M, {}, movers, others)             # 쉬는 자세에서도 겹치는 칸(어깨 관절 속 등)은 빼고 셈
    cands = []
    for i in range(starts):
        x0 = np.concatenate([[rng.uniform(-120, 30), rng.uniform(-60, 60), rng.uniform(-60, 60), rng.uniform(-130, -10)],
                             [rng.uniform(-120, 30), rng.uniform(-60, 60), rng.uniform(-60, 60), rng.uniform(-130, -10)]])
        sol = least_squares(res, x0, bounds=([-180, -180, -180, -150] * 2, [180, 180, 180, 0] * 2))
        P = build(sol.x)
        eR = np.linalg.norm(tp(W(M, "LowerArmR", P), FIST["R"]) - fistR_w)
        eL = np.linalg.norm(tp(W(M, "LowerArmL", P), FIST["L"]) - sup_w)
        bad = eR > 2.5 or eL > 3.0
        ov = {k: v - base.get(k, 0) for k, v in overlaps(M, P, movers, others).items() if v - base.get(k, 0) > 0}
        cands.append((sum(ov.values()) + (1e6 if bad else 0), sol.cost, P, ov, eR, eL, sol.x))
    cands.sort(key=lambda c: (c[0], c[1]))
    hit, cost, P, ov, eR, eL, xs = cands[0]
    return P, dict(overlap=hit, errR=round(float(eR), 2), errL=round(float(eL), 2), x=np.round(xs, 1).tolist(),
                   worst={"%s/%s" % k: v for k, v in sorted(ov.items(), key=lambda kv: -kv[1])[:5]})


# 몸: 상체 오른쪽으로 틀기(왼 어깨 앞, 게임 ZOOM_TWIST 25° 와 같은 형태) · 머리는 되돌려 정면
def stance(twist=-25, head_tilt=0):
    return {"Torso": rotz(twist), "Head": rotz(-twist) @ rotx(head_tilt)}


def build():
    M = R.build_all()
    slide_scope(M)
    return M
