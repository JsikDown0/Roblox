"""anim5.py — 사격 승리포즈 A 수정판(16:20): 총구·얼굴이 카메라 정면인 채 2점사 × 2 → 카메라가 뒤로 빠지며
겨눔을 옆으로 돌려 무릎 쏴(AF) 전신 → 눈 번쩍. 다리는 처음부터 무릎 꿇음.
겨눔을 돌리는 동안(1.4~2.8초) 매 프레임 두 손 IK(앞 프레임 해에서 이어 풂) → 두 손이 총에서 안 떨어짐.
"""
import sys, os, pickle, numpy as np
from multiprocessing import Pool
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import vpose as V, aim as A, keys as K1, scene as S1
import vox_preview as vp
from keys import slerp_R

FPS = 24; OW, OH = 720, 540; END = 4.6
T_CAM = (1.4, 2.8); T_TURN = (1.9, 2.8); T_EYE = 3.0     # 카메라 1.4~2.8 빠짐 · 1.9 부터 앉으며 겨눔 돌림 → 둘 다 2.8 에 멈춤
SHOTS = [0.35, 0.47, 1.05, 1.17]
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
OS, OF = A.OPTS["AS2"], A.OPTS["AF"]
PS, IS = pickle.load(open("opt_AS2.pkl", "rb"))
PF, IF = pickle.load(open("opt_AF.pkl", "rb"))

_M = {}
def model():
    if not _M:
        _M[0] = V.model(saber=-1, rifle=True)
    return _M[0]

def sstep(a): a = min(1, max(0, a)); return a * a * (3 - 2 * a)
def lerp(a, b, u): return np.asarray(a, float) + (np.asarray(b, float) - np.asarray(a, float)) * u

def slerp_v(a, b, u):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    w = np.arccos(np.clip(a @ b, -1, 1))
    if w < 1e-6: return a
    return (np.sin((1 - u) * w) * a + np.sin(u * w) * b) / np.sin(w)

def body_blend(Ba, Bb, u):
    out = {}
    for j in set(Ba) | set(Bb):
        if j in ("RootT", "Wings"):
            out[j] = tuple(lerp(Ba.get(j, (0, 0, 0)), Bb.get(j, (0, 0, 0)), u))
        else:
            out[j] = slerp_R(np.asarray(Ba.get(j, np.eye(3))), np.asarray(Bb.get(j, np.eye(3))), u)
    return out

def recoil(t):
    return min(sum(np.exp(-(t - s) / 0.07) for s in SHOTS if t >= s), 1.4)

def precompute():
    M = model()
    N = int(END * FPS) + 1
    poses = []
    x = IS["x"]
    for i in range(N):
        t = i / FPS
        if t <= T_TURN[0]:
            P = dict(PS)
        elif t >= T_TURN[1]:
            P = dict(PF)
            P["Waist"] = P["Waist"] @ V.Rx(1.0 * (0.5 - 0.5 * np.cos((t - T_TURN[1]) / 1.8 * 2 * np.pi)))
        else:
            u = sstep((t - T_TURN[0]) / (T_TURN[1] - T_TURN[0]))
            body = body_blend(OS["body"], OF["body"], u)
            aimv = slerp_v(np.asarray(OS["aim"]), np.asarray(OF["aim"]), u)
            butt = lerp(OS["butt"], OF["butt"], u)
            Q, info = A.solve_two_hand(M, body, aimv, butt, poleR=OF["poleR"], poleL=OF["poleL"], x0=x)
            x = info["x"]
            P = K1.skirts(K1.pads(Q))
            P["RootT"] = A.ground(M, P, ("FootL", "FootR", "LowerLegR"))
            if i % 6 == 0: print("  turn %.2f errR %.2f errL %.2f ov %d" % (t, info["errR"], info["errL"], info["overlap"]), flush=True)
        r = recoil(t)
        if r > 0.01:
            P["Waist"] = P["Waist"] @ V.Rx(2.2 * r); P["Neck"] = P["Neck"] @ V.Rx(-1.0 * r)
        if t <= T_TURN[0]:
            P["RootT"] = A.ground(M, P, OS["ground"])
        elif t >= T_TURN[1]:
            P["RootT"] = A.ground(M, P, OF["ground"])
        poses.append(P)
    # 카메라 기준점 — 프레임마다 그 자세의 얼굴·총구·전신 가운데(카메라가 피사체를 따라감: 서 있다 앉는 동안 머리 안 잘림)
    heads, mzs, ctrs = [], [], []
    samp = {n: (np.argwhere(p.a > 0) + p.lo)[::40].astype(float) for n, p in M.parts.items()}
    for P in poses:
        _, c = V.blocks(M, P)
        heads.append(c["Head"][:3, :3] @ np.array([0, -4, 250.]) + c["Head"][:3, 3])
        mzs.append(c["RifleR"][:3, :3] @ A.MUZZLE + c["RifleR"][:3, 3])
        pts = np.concatenate([q @ c[n][:3, :3].T + c[n][:3, 3] for n, q in samp.items()])
        ctrs.append(0.5 * (pts.min(0) + pts.max(0)))
    pickle.dump(dict(poses=poses, head=np.array(heads), mz=np.array(mzs), ctr=np.array(ctrs)), open("anim5_poses.pkl", "wb"))

D = None
def data():
    global D
    if D is None:
        D = pickle.load(open("anim5_poses.pkl", "rb"))
    return D

def cam(t):
    d = data(); i = min(int(round(t * FPS)), len(d["poses"]) - 1)
    close = 0.5 * (d["head"][i] + d["mz"][i]) + np.array([0, 0, -10])
    body = d["ctr"][i]
    if t < T_CAM[0]:
        return 0.0, -3.0, close, 76 - 8 * sstep(t / T_CAM[0])
    u = sstep((t - T_CAM[0]) / (T_CAM[1] - T_CAM[0]))
    return 0.0, -3.0 - 7.0 * u, lerp(close, body, u), 68 + (178 - 68) * u

def window(yaw, pitch, c, w):
    d, f, r, u = vp._basis(yaw, pitch)
    sx, sy = c @ r, c @ u; h = w * OH / OW
    return ((sx - w, sx + w), (sy - h, sy + h))

MUZ = [A.MUZZLE, np.array([-40, -12.8, 31.3])]

def add_muzzle(im, p0, p1, k, s):
    L = Image.new("RGB", im.size, (0, 0, 0)); d = ImageDraw.Draw(L)
    x, y = p0; dx, dy = p1[0] - x, p1[1] - y; n = np.hypot(dx, dy)
    s = s * k
    # 카메라를 향한 총구 = 별 모양(사방으로) + 가운데 원, 옆으로 향하면 원뿔
    for a in np.arange(0, np.pi, np.pi / 4):
        L2 = 30 * s if int(round(a / (np.pi / 4))) % 2 == 0 else 16 * s
        d.line([(x - np.cos(a) * L2, y - np.sin(a) * L2), (x + np.cos(a) * L2, y + np.sin(a) * L2)], fill=(255, 235, 170), width=max(2, int(3 * s)))
    if n > 8:
        dx, dy = dx / n, dy / n
        d.polygon([(x + dx * 70 * s, y + dy * 70 * s), (x - dy * 14 * s, y + dx * 14 * s), (x + dy * 14 * s, y - dx * 14 * s)], fill=(255, 230, 150))
    d.ellipse((x - 13 * s, y - 13 * s, x + 13 * s, y + 13 * s), fill=(255, 250, 225))
    G = L.filter(ImageFilter.GaussianBlur(6 * s))
    a = np.asarray(im, np.float32) + np.asarray(L, np.float32) * 0.9 + np.asarray(G, np.float32) * 1.5
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

def job(i):
    t = i / FPS
    P = data()["poses"][i]; M = model()
    yaw, pit, c, w = cam(t)
    size = window(yaw, pit, c, w)
    ppc_t = OW / (2 * w); ppc = min(ppc_t, 3.0); ss = 2 if ppc <= 1.8 else 1
    B, cache = V.blocks(M, P)
    im = vp.render(B, V.PAL, V.EMIT, yaw=yaw, pitch=pit, ppc=ppc, ss=ss, size=size, ao_amt=0.5)
    sc = OW / im.width
    im = im.resize((OW, OH), Image.LANCZOS)
    def scr(p):
        x, y = V.project(p, yaw, pit, size, ppc); return x * sc, y * sc
    for j, s in enumerate(SHOTS):
        if 0 <= t - s < 0.06:
            R = cache["RifleR"]; m = R[:3, :3] @ MUZ[j % 2] + R[:3, 3]; ahead = m + R[:3, :3] @ np.array([0, 0, -12.0])
            im = add_muzzle(im, scr(m), scr(ahead), 1.0 - (t - s) / 0.06 * 0.5, ppc_t / 2.2)
    e = float(np.exp(-((t - T_EYE) / 0.09) ** 2)) if t < T_EYE else float(np.exp(-(t - T_EYE) / 0.3))
    if e > 0.02:
        T = cache["Head"]; pt = T[:3, :3] @ S1.EYE_LOCAL + T[:3, 3]
        im = S1.add_flare(im, *scr(pt), e, ppc_t)
    ImageDraw.Draw(im).text((14, 10), "A 서서 쏘다 무릎 쏴  %.2fs" % t, font=ImageFont.truetype(FONT, 18), fill=(200, 205, 214))
    out = "frames5_A/%04d.png" % i; im.save(out); return out

if __name__ == "__main__":
    if sys.argv[1] == "pre":
        precompute(); print("poses ok")
    else:
        os.makedirs("frames5_A", exist_ok=True)
        N = int(END * FPS) + 1
        idx = [int(x) for x in sys.argv[2].split(",")] if len(sys.argv) > 2 else list(range(N))
        with Pool(2) as pool:
            for j, _ in enumerate(pool.imap(job, idx)):
                if j % 30 == 0: print("A", j, len(idx), flush=True)
        print("done", len(idx))
