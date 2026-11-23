"""export_studio.py — 승리포즈 A·B 를 Studio 관절 Transform(프레임별) + 카메라 + 이벤트로 내보내기 (2026-10-29)

규약(검증 대상):
  · 관절 Transform = 템플릿 축 회전(E = Ry·Rx·Rz). 팔은 Transform 0 = 팔 곧게(C1 = R_up, 팔꿈치 C0 = R_up·C1 = R_low).
  · Root = CFrame.new(RootT 스터드) * R.
  · WingJointL = Rx(−젖힘)·Rz(−펼침)·비틂(AXIS_T), R = 좌우 거울(diag(−1,1,1)).
  · Grip: 관절 틀(곧은 팔에서) = Rx(−90°) → T_grip = JRs^T · R_t · JRs  (R_t = 라이플의 곧은 아래팔 기준 회전, 템플릿 축).
  · PadL/R: 템플릿은 쉬는 자세(roty ∓3°)를 구워 둠 → T = P · R_rest^-1.
검증: 템플릿 규약으로 따로 짠 FK(쉬는 자세 = STANCE 로 구운 메시 + 위 C0/C1 식)와 미리보기 FK(복셀)의 기준점(두 주먹·총구·눈·발)이 같은지.
"""
import json, pickle, sys
import numpy as np
import aero_export as E_, aero_r1 as A1, vpose as V, aim as A, keys as K1, scene as S1
import vox_preview as vp

Mm = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
Ft = np.diag([-1.0, 1, 1])
JRs = V.Rx(-90)
M = V.model(saber=-1, rifle=True)
MR = E_.build()                                   # 쉬는 자세(템플릿에 구운 것) 기준
REST = E_.REST_POSE

def tv(R_v): return Mm @ R_v @ Mm.T               # 복셀 회전 → 템플릿
def pt(p_v): return Mm @ np.asarray(p_v, float) * 0.1
def wrest(name): return MR.world(name, REST)
def piv_rest(name):
    W = wrest(name); return pt(W[:3, :3] @ np.array(MR.parts[name].pivot) + W[:3, 3])
R_UP = {s: tv(wrest("UpperArm" + s)[:3, :3]) for s in "LR"}
R_LOW = {s: tv(wrest("LowerArm" + s)[:3, :3]) for s in "LR"}
R_PAD = {s: tv(REST["Shoulder" + s]) for s in "LR"}          # 어깨 장갑 쉬는 기울기(템플릿 축, 부모 기준)

JOINTS = ["Root", "Waist", "Neck", "ShoulderL", "ShoulderR", "ElbowL", "ElbowR", "PadL", "PadR", "HipL", "HipR", "KneeL", "KneeR",
          "AnkleL", "AnkleR", "SkirtJointFL", "SkirtJointFR", "SkirtJointSL", "SkirtJointSR", "WingJointL", "WingJointR", "Grip"]

def studio_transforms(P):
    out = {}
    for j in JOINTS:
        if j == "Root":
            R = np.asarray(P.get("Root", np.eye(3))); t = np.asarray(P.get("RootT", (0, 0, 0)), float)
            out[j] = (R, t)
        elif j in ("WingJointL", "WingJointR"):
            sp, bk, tw = P.get("Wings", (0, 0, 0))
            RL = V.wing_t(sp, bk, tw)
            out[j] = (RL if j.endswith("L") else Ft @ RL @ Ft, np.zeros(3))
        elif j == "Grip":
            Rt = tv(np.asarray(P.get("@RifleR", np.eye(3))))
            out[j] = (JRs.T @ Rt @ JRs, np.zeros(3))
        elif j in ("PadL", "PadR"):
            s = j[-1]
            out[j] = (np.asarray(P.get(j, np.eye(3))) @ R_PAD[s].T, np.zeros(3))
        else:
            out[j] = (np.asarray(P.get(j, np.eye(3))), np.zeros(3))
    return out

# ---------------------------------------------------------------- 템플릿 규약 FK(독립 검증)
def H(R=np.eye(3), t=(0, 0, 0)):
    m = np.eye(4); m[:3, :3] = R; m[:3, 3] = t; return m
def Tr(p): return H(t=p)
def Tn(p): return H(t=-np.asarray(p))

def studio_fk(T):
    G = {}
    R, t = T["Root"]; pp = piv_rest("Pelvis")
    G["Pelvis"] = Tr(pp) @ H(np.eye(3), t) @ H(R) @ Tn(pp)
    G["Torso"] = G["Pelvis"] @ Tr(piv_rest("Torso")) @ H(T["Waist"][0]) @ Tn(piv_rest("Torso"))
    G["Head"] = G["Torso"] @ Tr(piv_rest("Head")) @ H(T["Neck"][0]) @ Tn(piv_rest("Head"))
    for s in "LR":
        pu, pl = piv_rest("UpperArm" + s), piv_rest("LowerArm" + s)
        G["UpperArm" + s] = G["Torso"] @ Tr(pu) @ H(T["Shoulder" + s][0]) @ H(R_UP[s].T) @ Tn(pu)
        G["LowerArm" + s] = G["UpperArm" + s] @ Tr(pl) @ H(R_UP[s]) @ H(T["Elbow" + s][0]) @ H(R_LOW[s].T) @ Tn(pl)
        ph, pk, pa = piv_rest("UpperLeg" + s), piv_rest("LowerLeg" + s), piv_rest("Foot" + s)
        G["UpperLeg" + s] = G["Pelvis"] @ Tr(ph) @ H(T["Hip" + s][0]) @ Tn(ph)
        G["LowerLeg" + s] = G["UpperLeg" + s] @ Tr(pk) @ H(T["Knee" + s][0]) @ Tn(pk)
        G["Foot" + s] = G["LowerLeg" + s] @ Tr(pa) @ H(T["Ankle" + s][0]) @ Tn(pa)
    # 라이플: 관절 틀(쉬는 자세) = (오른 주먹, [gX gY gZ])
    Rr = MR.world("LowerArmR", REST)[:3, :3]
    gY = Mm @ Rr @ np.array([0, -1, 0.]); gZ = Mm @ Rr @ np.array([0, 0, 1.]); gX = np.cross(gY, gZ); gZ = np.cross(gX, gY)
    JR = H(np.stack([gX, gY, gZ], 1), pt(wrest("LowerArmR")[:3, :3] @ np.array([-40, 0, 125.]) + wrest("LowerArmR")[:3, 3]))
    G["RifleR"] = G["LowerArmR"] @ JR @ H(T["Grip"][0]) @ np.linalg.inv(JR)
    return G

LM = {"fistR": ("LowerArmR", (-40, 0, 125)), "fistL": ("LowerArmL", (40, 0, 125)), "muzzle": ("RifleR", tuple(A.MUZZLE)),
      "eye": ("Head", tuple(S1.EYE_LOCAL)), "toeL": ("FootL", (20, -55, 4)), "toeR": ("FootR", (-20, -55, 4)), "chest": ("Torso", (0, -30, 220))}

def check(P):
    T = studio_transforms(P)
    G = studio_fk(T)
    _, c = V.blocks(M, P)
    err = {}
    for k, (part, loc) in LM.items():
        a = pt(c[part][:3, :3] @ np.asarray(loc, float) + c[part][:3, 3])                 # 미리보기(곧은 기하 + 자세)
        W = wrest(part); rest = pt(W[:3, :3] @ np.asarray(loc, float) + W[:3, 3])         # 템플릿에 구운 자리
        b = (G[part] @ np.append(rest, 1))[:3]
        err[k] = float(np.linalg.norm(a - b))
    return err

# ---------------------------------------------------------------- 카메라(템플릿 스터드, 무대 원점 = 정지 B/A 의 발밑 가운데)
def cam_from_basis(yaw, pitch, pos_t=None, center_t=None, dist=None):
    d, f, r, u = vp._basis(yaw, pitch)
    ft = Mm @ f
    if pos_t is None:
        pos_t = center_t - ft * dist
    return pos_t, ft

def quat(R):
    w = np.sqrt(max(0, 1 + R[0, 0] + R[1, 1] + R[2, 2])) / 2
    x = np.sqrt(max(0, 1 + R[0, 0] - R[1, 1] - R[2, 2])) / 2
    y = np.sqrt(max(0, 1 - R[0, 0] + R[1, 1] - R[2, 2])) / 2
    z = np.sqrt(max(0, 1 - R[0, 0] - R[1, 1] + R[2, 2])) / 2
    x = np.copysign(x, R[2, 1] - R[1, 2]); y = np.copysign(y, R[0, 2] - R[2, 0]); z = np.copysign(z, R[1, 0] - R[0, 1])
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)

def build_clip(name):
    if name == "A":
        import anim5 as AN
        D = pickle.load(open("anim5_poses.pkl", "rb")); poses = D["poses"]
        cams = []
        for i in range(len(poses)):
            t = i / AN.FPS
            yaw, pit, c, w = AN.cam(t)
            Hh = w * AN.OH / AN.OW * 0.1                                    # 화면 반높이(스터드)
            # 원근: 가까이 잡을 때 50° 면 카메라가 총구에서 4 스터드 → 총구만 거대해짐. 망원(26°)으로 멀리서 같은 크기로 잡고 빠지며 40° 로
            u = min(1.0, max(0.0, (t - 1.4) / 1.4)); u = u * u * (3 - 2 * u)
            fov = 26 + (40 - 26) * u
            dist = Hh / np.tan(np.radians(fov / 2))
            pos, ft = cam_from_basis(yaw, pit, center_t=pt(c), dist=dist)
            cams.append((pos, ft, fov))
        ev = dict(shots=[[s, j % 2] for j, s in enumerate(AN.SHOTS)], eye=AN.T_EYE, flames=[[0, 0, 0]])
        fps, end = AN.FPS, AN.END
    else:
        import anim6 as AN
        D = pickle.load(open("anim6_poses.pkl", "rb")); poses = D["poses"]
        cams = []
        for i in range(len(poses)):
            pit, size, ppc = AN.cam(i)
            pos, ft = cam_from_basis(0.0, pit, pos_t=pt(AN.CAM))
            cams.append((pos, ft, 50.0))
        ts = np.arange(len(poses)) / AN.FPS
        fl = [[round(float(t), 3), *[round(float(v), 2) for v in AN.flames(t)]] for t in ts[::3]]
        ev = dict(shots=[[s, j % 2] for j, s in enumerate(AN.SHOTS)], eye=AN.T_EYE, flames=fl)
        fps, end = AN.FPS, AN.END
    worst = {}
    tracks = {j: [] for j in JOINTS}
    rootp = []
    for P in poses:
        e = check(P)
        for k, v in e.items():
            worst[k] = max(worst.get(k, 0), v)
        T = studio_transforms(P)
        for j in JOINTS:
            q = quat(T[j][0])
            if tracks[j] and q @ tracks[j][-1] < 0: q = -q                 # 부호 이어 붙이기(보간이 먼 길로 안 돌게)
            tracks[j].append(q)
        rootp.append(T["Root"][1])
    return dict(name=name, fps=fps, frames=len(poses), end=end, tracks=tracks, rootp=rootp, cams=cams, ev=ev), worst

def lua_num(x): return ("%.4f" % x).rstrip("0").rstrip(".") if abs(x) > 1e-9 else "0"

def to_lua(clips):
    L = ['-- VictoryPoseData (자동 생성: export_studio.py, 2026-10-29) — AELLO 승리포즈 A(서서 쏘다 무릎 쏴)·B(강하 사격 → 급제동)',
         '-- 관절 = AeroTemplate Motor6D 이름. q = 프레임별 쿼터니언 {x,y,z,w}(Transform 회전, 템플릿 축). Root 는 p(스터드)도.',
         '-- cam = 프레임별 {pos x,y,z, look x,y,z, fov} (무대 원점 기준, 템플릿 축: −Z 정면, fov = 세로 시야각).',
         '-- ev.shots = {시각, 총열(0 = Muzzle 위, 1 = Muzzle2 아래)} · ev.eye = 눈 번쩍 시각 · ev.flames = {시각, 등 노즐, 다리 부스터}(0~1)',
         'local D = {}']
    for c in clips:
        L.append('D.%s = { fps = %d, frames = %d, eye = %s,' % (c["name"], c["fps"], c["frames"], lua_num(c["ev"]["eye"])))
        L.append('\tshots = {' + ", ".join("{%s,%d}" % (lua_num(s), b) for s, b in c["ev"]["shots"]) + '},')
        L.append('\tflames = {' + ", ".join("{%s}" % ",".join(lua_num(v) for v in f) for f in c["ev"]["flames"]) + '},')
        L.append('\tq = {')
        for j in JOINTS:
            L.append('\t\t%s = {%s},' % (j, ",".join(lua_num(v) for q in c["tracks"][j] for v in q)))
        L.append('\t},')
        L.append('\trootp = {%s},' % ",".join(lua_num(v) for p in c["rootp"] for v in p))
        L.append('\tcam = {%s},' % ",".join(lua_num(v) for p, f, fv in c["cams"] for v in (*p, *f, fv)))
        L.append('}')
    L.append('return D')
    return "\n".join(L)

if __name__ == "__main__":
    clips = []
    for n in ("A", "B"):
        c, worst = build_clip(n)
        print(n, "frames", c["frames"], "worst landmark gap (studs):", {k: round(v, 4) for k, v in worst.items()})
        clips.append(c)
    src = to_lua(clips)
    open("VictoryPoseData.lua", "w").write(src)
    pickle.dump(clips, open("victory_clips.pkl", "wb"))
    print("lua chars", len(src))
