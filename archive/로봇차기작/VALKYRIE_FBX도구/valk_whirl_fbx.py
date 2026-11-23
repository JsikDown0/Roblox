"""
valk_whirl_fbx.py — 11-04 16:2x 유저 Mixamo "Standing Melee Attack 360 High" FBX → VALKYRIE 회전베기(전체 3.17초 · 실제 전진).
  좌표: Mixamo(Y 위 · 캐릭터 앞 +Z · 캐릭터 왼쪽 +X · cm) → 기체(앞 −Z · 오른쪽 +X · 스터드) + 좌우 거울(칼 = 사람 오른손 → 기체 왼손)
        = 위치 p_m = s · C · p_h, 회전 R_m = C R_h C, C = diag(1, 1, −1), 이름 Left ↔ Right.  s = 기체 다리 13.7 / 사람 다리 88.9.
  본 → 관절: Hips → Root(회전 · 높이만 — 수평 이동은 HRP 를 실제로 움직임) · Spine2/Hips → Waist · Head/Spine2 → Neck ·
            팔 · 다리 = 손 · 발 자리(어깨 · 엉덩이 기준 방향 × 뻗은 비율 × 기체 팔다리 길이) IK + 팔꿈치 · 무릎 방향 + 칼 방향(사람 오른손 +X) · 발 = 평평 · 발끝 요만 따라감.
"""
import sys, json
import numpy as np
sys.path.insert(0, "/home/claude/valk/fbx")
import fbxanim
import valk_melee1 as V, valk_melee2 as K, valk_spin1 as S1
inv = np.linalg.inv
SP = S1.SP
FBX = sys.argv[1] if len(sys.argv) > 1 else "/mnt/user-data/attachments/45a5ff43-da6d-586c-af9c-a80fba67e5ee/b2263628-Standing_Melee_Attack_360_High.fbx"
OUT = sys.argv[2] if len(sys.argv) > 2 else "whirl_fbx.json"
TWO = len(sys.argv) > 3 and sys.argv[3] == "2h"   # 11-04 18:2x 두 손 FBX: 손잡이 = 사람 두 손 가운데(가슴 가운데 기준) · 두 어깨가 다 닿게 당김 · 오른손 = 지느러미
C = np.diag([1.0, 1.0, -1.0])
MX = fbxanim.load(FBX)
FPS = 30
T_END = None


def H(W, n): return W["mixamorig:" + n]


def jpos(Wm, n):
    p0, p1, c0, c1 = V.J[n]; return (Wm[p0] @ c0)[:3, 3]


W0 = V.fk({})
LEG_M = np.linalg.norm(jpos(W0, "KneeL") - jpos(W0, "HipL")) + np.linalg.norm(jpos(W0, "AnkleL") - jpos(W0, "KneeL"))
ARM_ML = np.linalg.norm(jpos(W0, "ElbowL") - jpos(W0, "ShoulderL")) + np.linalg.norm(jpos(W0, "SaberGrip") - jpos(W0, "ElbowL"))
gC0 = V.CF((0.28029, -2.70493, 0.0945))
_, _, c0e, c1e = V.J["ElbowR"]
ARM_MR = np.linalg.norm(jpos(W0, "ElbowR") - jpos(W0, "ShoulderR")) + np.linalg.norm((inv(c1e) @ gC0)[:3, 3])
Wh0 = fbxanim.world_at(MX, 0.0)
LEG_H = np.linalg.norm(H(Wh0, "RightLeg")[:3, 3] - H(Wh0, "RightUpLeg")[:3, 3]) + np.linalg.norm(H(Wh0, "RightFoot")[:3, 3] - H(Wh0, "RightLeg")[:3, 3])
ARM_H = np.linalg.norm(H(Wh0, "RightForeArm")[:3, 3] - H(Wh0, "RightArm")[:3, 3]) + np.linalg.norm(H(Wh0, "RightHand")[:3, 3] - H(Wh0, "RightForeArm")[:3, 3])
SCALE = LEG_M / LEG_H
HIP_REST_H = 104.2749
OTHER = {"Left": "Right", "Right": "Left"}


def rot_m(R): return C @ R[:3, :3] @ C
def vec_m(v): return C @ v


def solve_chain(Wm, Sjoint, Ejoint, Pend_c0, target, pole_w, bend_neg=True):
    """2마디 IK(V.solve_arm 과 같은 식) — 무릎은 음(−) 방향으로 굽음(기체 KneeL 키 −95 등)."""
    p0, p1, c0s, c1s = V.J[Sjoint]; _, _, c0e_, c1e_ = V.J[Ejoint]
    Sw = Wm[p0] @ c0s
    a = (inv(c1s) @ c0e_)[:3, 3]; b = (inv(c1e_) @ Pend_c0)[:3, 3]
    Rs, th = V.solve_arm(Sw, a, b, target, pole_w)
    return Rs, th


def frame(t):
    Wh = fbxanim.world_at(MX, t)
    P = {}
    # ---- Root: 엉덩이 회전(쉬는 자세 = PreRotation 만) · 높이
    Rh = H(Wh, "Hips")[:3, :3]
    Rrest = fbxanim.euler_xyz(MX_PRE["Hips"])
    Rr = rot_m(Rh @ inv(Rrest))
    dy = (H(Wh, "Hips")[1, 3] - HIP_REST_H) * SCALE
    R4 = np.eye(4); R4[:3, :3] = Rr; R4[1, 3] = dy
    P["Root"] = R4
    # ---- Waist · Neck (상대 회전)
    Rs2 = H(Wh, "Spine2")[:3, :3]; Rhd = H(Wh, "Head")[:3, :3]
    Rw = rot_m(inv(Rh) @ Rs2); Rn = rot_m(inv(Rs2) @ Rhd)
    P["Waist"] = np.eye(4); P["Waist"][:3, :3] = Rw
    P["Neck"] = np.eye(4); P["Neck"][:3, :3] = Rn
    Wm = V.fk(P)
    Tt = Wm["Torso"]
    # ---- 다리(사람 Left → 기체 Right 거울)
    for side_m in ("L", "R"):
        sh = "Right" if side_m == "L" else "Left"        # 거울: 기체 왼다리 = 사람 오른다리
        up, kn, ft, toe = (H(Wh, sh + n)[:3, 3] for n in ("UpLeg", "Leg", "Foot", "ToeBase"))
        d = vec_m(ft - up); r = np.linalg.norm(ft - up) / LEG_H
        hipw = jpos(Wm, "Hip" + side_m)
        target = hipw + d / np.linalg.norm(d) * r * LEG_M
        mid = (up + ft) / 2; pole = vec_m(kn - mid); pole = pole / (np.linalg.norm(pole) + 1e-9)
        _, _, c0a, c1a = V.J["Ankle" + side_m]
        Rs, th = solve_chain(Wm, "Hip" + side_m, "Knee" + side_m, c0a, target, pole)
        P["Hip" + side_m] = Rs; P["Knee" + side_m] = V.rx(np.degrees(th))
        Wm = V.fk(P)
        tv = vec_m(toe - ft); tv[1] = 0
        psi = np.arctan2(-tv[0], -tv[2]) if np.linalg.norm(tv) > 1e-6 else 0.0   # 기체 앞 −Z 기준 요
        Rdes = np.eye(4); Rdes[:3, :3] = V.ry(np.degrees(psi))[:3, :3]
        Wl = Wm["LowerLeg" + side_m]
        A = inv(Wl @ c0a) @ Rdes @ c1a; A[:3, 3] = 0
        P["Ankle" + side_m] = A
    Wm = V.fk(P)
    # ---- 칼 팔(기체 왼팔 = 사람 오른팔)
    sA, eA, hA = (H(Wh, "Right" + n)[:3, 3] for n in ("Arm", "ForeArm", "Hand"))
    Rhand = H(Wh, "RightHand")[:3, :3]
    d = vec_m(hA - sA); r = min(1.0, np.linalg.norm(hA - sA) / ARM_H)
    shw = jpos(Wm, "ShoulderL")
    gw = shw + d / np.linalg.norm(d) * r * ARM_ML
    blade = vec_m(Rhand[:, 0]); edge = vec_m(Rhand[:, 1])
    pole = vec_m(eA - (sA + hA) / 2); pole = pole / (np.linalg.norm(pole) + 1e-9)
    Ti = inv(Tt)
    p_loc = (Ti @ np.append(gw, 1))[:3]; d_loc = Ti[:3, :3] @ blade; e_loc = Ti[:3, :3] @ edge; pole_loc = Ti[:3, :3] @ pole
    Hw = Tt @ K.hilt_local(p_loc, d_loc, e_loc)
    if TWO:
        # 두 손: 사람 두 손 가운데 − 가슴 가운데(두 어깨 가운데) → × s → 기체 가슴 가운데에 더함. 기체 어깨가 사람보다 훨씬 넓어(팔 길이 대비)
        #   그대로면 반대 손이 못 닿음 [에디트 실측 어깨→지느러미 12.5 > 팔 8.84] → 손잡이를 통째로 옮겨 두 어깨에서 다 닿게(칼 방향은 그대로)
        hm = (hA + H(Wh, "LeftHand")[:3, 3]) / 2; cm = (sA + H(Wh, "LeftArm")[:3, 3]) / 2
        shl, shr2 = jpos(Wm, "ShoulderL"), jpos(Wm, "ShoulderR")
        g = (shl + shr2) / 2 + vec_m(hm - cm) * SCALE
        Hw = Tt @ K.hilt_local((Ti @ np.append(g, 1))[:3], d_loc, e_loc)
        RL, RR = ARM_ML * 0.97, ARM_MR * 0.95
        for _ in range(30):
            fin = (Hw @ np.append(K.FIN, 1))[:3]; hand = (Hw @ K.C1S)[:3, 3]
            moved = False
            for pt, sh, R in ((fin, shr2, RR), (hand, shl, RL)):
                v = pt - sh; dd = np.linalg.norm(v)
                if dd > R:
                    Hw = Hw.copy(); Hw[:3, 3] -= v / dd * (dd - R) * 0.6; moved = True
            if not moved: break
    P, eL, wr = K.solve_left(P, Hw, pole_loc)
    # ---- 반대 팔(기체 오른팔 = 사람 왼팔) — 주먹 자리
    sB, eB, hB = (H(Wh, "Left" + n)[:3, 3] for n in ("Arm", "ForeArm", "Hand"))
    d = vec_m(hB - sB); r = min(1.0, np.linalg.norm(hB - sB) / ARM_H)
    shr = jpos(Wm, "ShoulderR")
    fw = shr + d / np.linalg.norm(d) * r * ARM_MR * 0.98
    pole = vec_m(eB - (sB + hB) / 2); pole = pole / (np.linalg.norm(pole) + 1e-9)
    if TWO:
        P, eR, _ = K.solve_right(P, Ti[:3, :3] @ pole)   # 오른손 = 지느러미(화면은 axeRightHand IK 로 다시 풂)
        eL = max(eL, eR)
    else:
        P = S1.fist_right(P, (Ti @ np.append(fw, 1))[:3], Ti[:3, :3] @ pole)
    # ---- 수평 이동(HRP) = 엉덩이 수평 자리(첫 칸 기준) × s
    hp = vec_m(H(Wh, "Hips")[:3, 3]) * SCALE
    return P, hp, dict(eL=eL, wrist=wr)


MX_PRE = {}
for m in MX.values():
    nm = m["name"].replace("mixamorig:", "")
    MX_PRE[nm] = np.array(m["P"].get("PreRotation", (0, 0, 0))[:3], float)

if __name__ == "__main__":
    print("s", round(SCALE, 4), "arm L", round(ARM_ML, 2), "arm R", round(ARM_MR, 2), "human arm", round(ARM_H, 1))
    frames, roots, info = [], [], []
    T_END = fbxanim.span(MX)[1]
    n = int(round(T_END * FPS)) + 1
    for i in range(n):
        t = min(i / FPS, T_END)
        P, hp, inf = frame(t)
        frames.append({k: m.tolist() for k, m in P.items()}); roots.append(hp.tolist()); info.append(inf)
    r0 = np.array(roots[0]); roots = [(np.array(r) - r0).tolist() for r in roots]
    json.dump(dict(fps=FPS, frames=frames, root=roots), open(SP + OUT, "w"))
    print("frames", n, "max hand err", round(max(x["eL"] for x in info), 3), "max wrist", round(max(x["wrist"] for x in info)))
    R = np.array(roots); print("root motion max fwd(−z)", round(-R[:, 2].min(), 2), "x range", R[:, 0].min().round(2), R[:, 0].max().round(2))
