"""aim.py — AELLO 승리포즈 B(사격) 후보 자세 (2026-10-29 15:55~)
유저 흐름: 얼굴 줌인 → 카메라가 천천히 앞 아래로 내려오며 기체는 사격 포즈 → 눈 번쩍 마무리.
조건: 스트라이크 시그니처(한 손 라이플 쭉 뻗고 공중 런지)와 다른 사격 포즈.

라이플 두 손 쥐기:
  1) 라이플 월드 틀 = 겨눔 방향(총구) + 위(가늠자) + 개머리판 끝 자리(몸통 로컬)로 먼저 정함
  2) 오른 주먹 = 그 틀의 손잡이 자리 → 오른팔 IK(자리만), 손목(Grip) = 아래팔⁻¹ · 라이플 틀(게임 twoHandPose 의 G = base⁻¹·RR 와 같은 생각)
  3) 왼 주먹 = 앞 손잡이(ForeGrip) 아래 → 왼팔 IK
  여러 시작점 → 몸과 겹침 가장 적은 해.
"""
import numpy as np
from scipy.optimize import least_squares

import vpose as V
import keys as K1
from vpose import E
from keys import legs, pads, skirts

FIST_R = np.array([-40, 0, 125.0])
FIST_L = np.array([40, 0, 125.0])
# 라이플 기준점(오른 아래팔 곧은 축, aero_rifle 설계 좌표 → 칸)
BUTT = np.array([-40, -16.2, 166.4])      # 개머리판 끝
FORE_HAND = np.array([-40, -1.35, 69.8])  # 앞 손잡이 아래 — 견착하면 왼팔이 안 닿음(팔 길이 103칸 < 왼 어깨→앞 손잡이 약 120칸)
LEFT_HAND = np.array([-40, -5.4, 92.8])   # 탄창 앞(템플릿 속성 LeftHand 와 같은 자리 [추측: 설계 좌표 a≈26, b≈−8])
MUZZLE = np.array([-40, -20.9, 24.4])
LENS = np.array([-40, -29.0, 96.8])
DIR_L = np.array([0, 0, -1.0])            # 총구 방향(곧은 팔에서 아래)
UP_L = np.array([0, -1.0, 0])             # 가늠자 쪽


def rifle_frame(aim, up_hint):
    """라이플 로컬 축(DIR_L, UP_L, X) → 월드(aim, up) 회전"""
    a = np.asarray(aim, float); a /= np.linalg.norm(a)
    u = np.asarray(up_hint, float); u = u - a * (u @ a); u /= np.linalg.norm(u)
    x = np.cross(u, a)
    Lm = np.stack([DIR_L, UP_L, np.cross(UP_L, DIR_L)], 1)
    Wm = np.stack([a, u, np.cross(u, a)], 1)
    return Wm @ Lm.T


def _arm(Q, side, x):
    Q["Shoulder" + side] = E(*x[0:3]); Q["Elbow" + side] = E(x[3])


def solve_two_hand(M, P, aim, butt_t, up=(0, 0, 1), poleR=(-1, 0, -0.5), poleL=(1, 0, -0.8), starts=20, seed=5, x0=None):
    """aim: 월드(칸 축) 총구 방향, butt_t: 개머리판 끝 자리(몸통 로컬 칸)."""
    _, cache = V.blocks(M, P)
    Tt = cache["Torso"]
    Rw = rifle_frame(aim, up)
    butt_w = Tt[:3, :3] @ np.asarray(butt_t, float) + Tt[:3, 3]
    # 라이플 = 오른 아래팔 자식(피벗 FIST_R). 월드 틀 Rw 일 때 FIST_R 의 월드 자리:
    fistR_w = butt_w + Rw @ (FIST_R - BUTT)
    pR = Tt[:3, :3] @ (np.asarray(poleR, float) / np.linalg.norm(poleR))
    pL = Tt[:3, :3] @ (np.asarray(poleL, float) / np.linalg.norm(poleL))

    def pole_res(c, side, fist, pw):
        L = c["LowerArm" + side]; U = c["UpperArm" + side]
        s = 1 if side == "L" else -1
        elbow = L[:3, :3] @ np.array([s * 40, 0, 184.0]) + L[:3, 3]
        sh = U[:3, :3] @ np.array([s * 40, 0, 228.0]) + U[:3, 3]
        v = elbow - (sh + fist) / 2; n = np.linalg.norm(v)
        return list(((v / n) - pw) * 3) if n > 1e-6 else [0, 0, 0]

    def build(x):
        Q = dict(P)
        _arm(Q, "R", x[0:4]); _arm(Q, "L", x[4:8])
        _, c = V.blocks(M, Q)
        Rf = c["LowerArmR"][:3, :3]
        Q["@RifleR"] = Rf.T @ Rw                 # 손목 = 아래팔⁻¹ · 라이플 틀
        return Q

    def res(x):
        Q = build(x)
        _, c = V.blocks(M, Q)
        LR = c["LowerArmR"]; fist = LR[:3, :3] @ FIST_R + LR[:3, 3]
        LL = c["LowerArmL"]; fistL = LL[:3, :3] @ FIST_L + LL[:3, 3]
        RR = c["RifleR"]; fore = RR[:3, :3] @ LEFT_HAND + RR[:3, 3]
        r = list(fist - fistR_w) + list(fistL - fore)
        r += pole_res(c, "R", fist, pR) + pole_res(c, "L", fistL, pL)
        # 손목 굽힘이 덜한 쪽(라이플 축과 아래팔이 너무 비틀리지 않게) — 약하게
        ang = np.degrees(np.arccos(np.clip((np.trace(Q["@RifleR"]) - 1) / 2, -1, 1)))
        r += [ang * 0.02, x[1] * 0.01, x[5] * 0.01]
        return r

    rng = np.random.default_rng(seed)
    hitsR = ("Head", "Torso", "ChestL", "ChestR", "Pelvis", "SkirtFR", "SkirtSR", "SkirtFL", "UpperLegR", "UpperLegL", "LowerLegL", "LowerLegR", "WingR", "WingL", "BinderR")
    cands = []
    warm = x0
    for i in range(1 if warm is not None else starts):
        x0 = np.asarray(warm, float) if warm is not None else np.concatenate([[rng.uniform(-30, 120), rng.uniform(-60, 60), rng.uniform(-20, 90), rng.uniform(10, 130)],
                             [rng.uniform(-30, 120), rng.uniform(-60, 60), rng.uniform(-90, 20), rng.uniform(10, 130)]])
        s = least_squares(res, x0, bounds=([-200, -180, -180, 0] * 2, [200, 180, 180, 150] * 2))
        Q = build(s.x)
        _, c = V.blocks(M, Q)
        LR = c["LowerArmR"]; eR = np.linalg.norm(LR[:3, :3] @ FIST_R + LR[:3, 3] - fistR_w)
        LL = c["LowerArmL"]; RR = c["RifleR"]
        eL = np.linalg.norm(LL[:3, :3] @ FIST_L + LL[:3, 3] - (RR[:3, :3] @ LEFT_HAND + RR[:3, 3]))
        bad = eR > 2.5 or eL > 3.0
        movers = ("UpperArmR", "LowerArmR", "UpperArmL", "LowerArmL", "RifleR")
        hits = [h for h in hitsR if h in M.parts]
        ov = V.overlaps(M, skirts(pads(dict(Q))), [(a, b) for a in movers for b in hits] + [("RifleR", "UpperArmL")])
        cands.append((sum(ov.values()) + (1e6 if bad else 0), s.cost, Q, ov, eR, eL, s.x))
    if not cands:
        raise RuntimeError("no IK solution")
    cands.sort(key=lambda c: (c[0], c[1]))
    hit, cost, Q, ov, eR, eL, xs = cands[0]
    wrist = np.degrees(np.arccos(np.clip((np.trace(Q["@RifleR"]) - 1) / 2, -1, 1)))
    return Q, dict(x=xs, overlap=hit, errR=round(float(eR), 2), errL=round(float(eL), 2), wrist=round(float(wrist), 1),
                   worst={"%s/%s" % k: v for k, v in sorted(ov.items(), key=lambda kv: -kv[1])[:4] if v})


def ground(M, P, parts=("FootL", "FootR")):
    _, c = V.blocks(M, P)
    lo = 1e9
    for n in parts:
        p = M.parts[n]; pts = (np.argwhere(p.a > 0) + p.lo).astype(float); T = c[n]
        lo = min(lo, float((pts @ T[:3, :3].T + T[:3, 3])[:, 2].min()))
    x, y, z = P.get("RootT", (0, 0, 0))
    return (x, round(y - lo / 10.0, 3), z)


def nrm(v):
    v = np.asarray(v, float); return v / np.linalg.norm(v)


# ---------------------------------------------------------------- 후보
OPTS = {
    "A": dict(name="A 무릎 쏴 — 한쪽 무릎 꿇고 견착, 묵직하게 멈춤",
              body={"Root": E(-4, -24, 0), "Waist": E(-6, 10), "Neck": E(-8, 16),
                    **legs(72, -6, -84, -112, al=12, ar=52, zl=-8, zr=6), "Wings": (30, 6, 6)},
              aim=nrm((0.30, -0.95, -0.06)), butt=(-26, -30, 222), ground=("FootL", "FootR", "LowerLegR"),
              poleR=(-1, 0.2, -0.3), poleL=(0.6, -0.2, -1)),
    "B": dict(name="B 급강하 사격 — 날개 활짝 젖히고 아래(카메라)로 겨눔",
              body={"Root": E(-46, 0, 0), "RootT": (0, 9.0, 0), "Waist": E(-2, -28), "Neck": E(14, 18),
                    **legs(-2, -14, -24, -8, al=34, ar=30, zl=-3, zr=3), "Wings": (50, 48, 14)},
              aim=nrm((0.10, -0.62, -0.78)), butt=(-26, -30, 222), ground=None, flames=True,
              poleR=(-1, 0.1, -0.5), poleL=(0.7, -0.2, -1)),
    "C": dict(name="C 대공 겨눔 — 넓게 버티고 하늘 위로 견착",
              body={"Root": E(0, -26, 0), "Waist": E(12, 10), "Neck": E(22, 16),
                    **legs(22, -10, -26, -12, zl=-14, zr=16), "Wings": (60, 8, 8)},
              aim=nrm((0.22, -0.72, 0.66)), butt=(-26, -28, 226), ground=("FootL", "FootR"),
              poleR=(-1, 0.2, -0.3), poleL=(0.6, -0.3, -1)),
}


# ---------------------------------------------------------------- 정면 카메라용(16:04 유저 "승리포즈는 항상 정면에서 보여야 해")
OPTS["AF"] = dict(name="A 무릎 쏴(정면용)",
                  body={"Root": E(-4, 0, 0), "Waist": E(-4, 20), "Neck": E(-4, -6),
                        **legs(60, -4, -76, -112, al=16, ar=52, zl=-34, zr=10), "Wings": (40, 6, 6)},
                  aim=nrm((0.86, -0.5, -0.08)), butt=(-26, -30, 222), ground=("FootL", "FootR", "LowerLegR"),
                  poleR=(-1, 0.2, -0.3), poleL=(0.6, -0.2, -1))
OPTS["BF"] = dict(name="B 급강하 사격(정면용)",
                  body={"Root": E(-24, 0, 0), "RootT": (0, 9.0, 0), "Waist": E(-2, 18), "Neck": E(10, -8),
                        **legs(-6, -16, -30, -14, al=30, ar=26, zl=-14, zr=14), "Wings": (72, 16, 12)},
                  aim=nrm((0.66, -0.3, -0.69)), butt=(-26, -30, 222), ground=None, flames=True,
                  poleR=(-1, 0.1, -0.5), poleL=(0.7, -0.2, -1))

# A 사격 구간(16:20 유저 "사격 시에는 총구와 얼굴이 정면에서 보이게"): 총구 = 카메라, 얼굴 정면. 다리는 AF 그대로(무릎 꿇음)
OPTS["AS"] = dict(name="A 사격(카메라 겨눔)",
                  body={"Root": E(-4, 0, 0), "Waist": E(-4, -36), "Neck": E(-4, 34),
                        **legs(60, -4, -76, -112, al=16, ar=52, zl=-34, zr=10), "Wings": (40, 6, 6)},
                  aim=nrm((0.0, -1.0, -0.05)), butt=(-26, -30, 222), ground=("FootL", "FootR", "LowerLegR"),
                  poleR=(-1, 0.2, -0.3), poleL=(0.6, -0.2, -1))

# A 수정(16:32 유저 "서서 사격하다가 카메라가 좀 멀어졌을 때 앉는 걸로"): 선 자세로 카메라 겨눔 — 다리째 오른쪽으로 틀어 견착(허리 비틀기 최소)
OPTS["AS2"] = dict(name="A 서서 사격(카메라 겨눔)",
                   body={"Root": E(-2, -30, 0), "Waist": E(-4, -6), "Neck": E(-4, 34),
                         **legs(10, -6, -14, -8, zl=-10, zr=8), "Wings": (40, 6, 6)},
                   aim=nrm((0.0, -1.0, -0.05)), butt=(-26, -30, 222), ground=("FootL", "FootR"),
                   poleR=(-1, 0.2, -0.3), poleL=(0.6, -0.2, -1))

# B 수정(16:39 유저): 위에서 아래로 강하하며 사격(카메라 쪽으로 빠르게 다가옴) → 뒤로 부스터 쏘며 급제동·후퇴 → 지금 B(BF)
OPTS["BD"] = dict(name="B 강하 사격", body={"Root": E(-50, -28, 0), "Waist": E(-2, -6), "Neck": E(30, 30),
                  **legs(-4, -16, -22, -10, al=34, ar=30, zl=-3, zr=3), "Wings": (46, 50, 14)},
                  aim=nrm((0.0, -0.75, -0.66)), butt=(-26, -30, 222), ground=None, poleR=(-1, 0.1, -0.5), poleL=(0.7, -0.2, -1))
OPTS["BR"] = dict(name="B 급제동", body={"Root": E(14, -24, 0), "Waist": E(2, -6), "Neck": E(-8, 22),
                  **legs(42, 24, -64, -44, al=12, ar=12, zl=-10, zr=10), "Wings": (70, 6, 26)},
                  aim=nrm((0.0, -0.93, -0.36)), butt=(-26, -30, 222), ground=None, poleR=(-1, 0.1, -0.5), poleL=(0.7, -0.2, -1))
