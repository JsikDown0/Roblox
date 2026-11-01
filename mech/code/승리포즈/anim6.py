"""anim6.py — 사격 승리포즈 B 수정판(16:39): 위에서 아래로 강하하며 사격 → 카메라 쪽으로 빠르게 다가옴 →
뒤로 부스터를 쏘며 급제동·후퇴(뒤돌지 않음) → 지금 B 자세(BF) → 눈 번쩍.
카메라: 정면 아래 한자리(C), 고개(pitch)만 기체를 따라감. 원근 근사 = 기체 몸 가운데까지의 거리에 비례해 화면 폭을 정함
(약한 원근: 한 기체 안의 앞뒤 원근은 없음). 세로 시야각 50°.
"""
import sys, os, pickle, numpy as np
from multiprocessing import Pool
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import vpose as V, aim as A, keys as K1, scene as S1
import vox_preview as vp
from keys import slerp_R

FPS = 24; OW, OH = 720, 540; END = 4.6
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
TANV = np.tan(np.radians(25))
CAM = np.array([0, -470, 120.0])                 # 카메라 자리(칸) — 마지막 B 를 아래 정면에서 올려다보는 자리
SHOTS = [0.42, 0.54, 0.80, 0.92]                 # 강하 중 2점사 × 2(가까워진 뒤)
T_EYE = 2.55
KEYS = [(0.0, "BD"), (1.0, "BD"), (1.32, "BR"), (2.3, "BF")]
EASE = ["const", "s", "out"]

# 몸 자리(복셀 칸, 최종 B 정지 위치 기준): 시각, 자리, 속도
PATH = [(0.0, (0, 430, 560), (0, -340, -470)),     # 위 멀리서 가파르게 내리꽂음
        (1.05, (0, -205, -10), (0, -230, -130)),      # 가장 가까움 직전(아직 다가오는 중)
        (1.45, (0, -175, 40), (0, 250, 170)),        # 급제동 → 뒤로·위로 물러나기 시작
        (2.35, (0, 0, 0), (0, 0, 0))]

def hermite(t):
    for (t0, p0, v0), (t1, p1, v1) in zip(PATH[:-1], PATH[1:]):
        if t0 <= t <= t1:
            h = t1 - t0; u = (t - t0) / h
            h00 = 2 * u ** 3 - 3 * u ** 2 + 1; h10 = u ** 3 - 2 * u ** 2 + u; h01 = -2 * u ** 3 + 3 * u ** 2; h11 = u ** 3 - u ** 2
            return h00 * np.array(p0, float) + h10 * h * np.array(v0, float) + h01 * np.array(p1, float) + h11 * h * np.array(v1, float)
    return np.zeros(3) if t > PATH[-1][0] else np.array(PATH[0][1], float)

def sstep(a): a = min(1, max(0, a)); return a * a * (3 - 2 * a)
def ease_out(a): a = min(1, max(0, a)); return 1 - (1 - a) ** 2.5

def flames(t):
    """(등 노즐, 다리 부스터) 세기"""
    if t < 1.0: return 0.75, 0.0
    if t < 1.6: return 0.5, 1.0
    u = sstep((t - 1.6) / 0.6)
    return 0.5 + 0.25 * u, 1.0 - 0.25 * u

_M = {}
def model(fb, fl):
    k = (round(fb * 4) / 4, round(fl * 4) / 4)
    if k not in _M:
        M = V.model(saber=-1, rifle=True)
        for s, side in ((1, "L"), (-1, "R")):
            if k[1] > 0:
                V.add_flame(M, "FlameLeg" + side, "LowerLeg" + side, (s * 36, 6, 44), (0, 0.15, -1), int(40 * k[1]), 3.2)
            if k[0] > 0:
                for j, z in enumerate((247, 238)):
                    V.add_flame(M, "FlameBack%s%d" % (side, j), "Backpack", (s * 22, 50, z), (0, 1, -0.15), int(34 * k[0]), 2.6)
        _M[k] = M
    return _M[k]

def body_blend(Ba, Bb, u):
    out = {}
    for j in set(Ba) | set(Bb):
        if j in ("RootT", "Wings"):
            a = np.asarray(Ba.get(j, (0, 0, 0)), float); b = np.asarray(Bb.get(j, (0, 0, 0)), float); out[j] = tuple(a + (b - a) * u)
        else:
            out[j] = slerp_R(np.asarray(Ba.get(j, np.eye(3))), np.asarray(Bb.get(j, np.eye(3))), u)
    return out

def slerp_v(a, b, u):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b); w = np.arccos(np.clip(a @ b, -1, 1))
    return a if w < 1e-6 else (np.sin((1 - u) * w) * a + np.sin(u * w) * b) / np.sin(w)

def recoil(t):
    return min(sum(np.exp(-(t - s) / 0.07) for s in SHOTS if t >= s), 1.4)

def precompute():
    M = model(0, 0)
    SOL = {k: pickle.load(open("opt_%s.pkl" % k, "rb")) for k in ("BD", "BR", "BF")}
    N = int(END * FPS) + 1
    poses, x = [], SOL["BD"][1]["x"]
    finalT = np.array(A.OPTS["BF"]["body"]["RootT"], float)
    for i in range(N):
        t = i / FPS
        seg = max(j for j, (tk, _) in enumerate(KEYS) if tk <= t + 1e-9)
        if t >= KEYS[-1][0]:
            P = dict(SOL["BF"][0])
        elif EASE[seg] == "const":
            P = dict(SOL[KEYS[seg][1]][0])
        else:
            (t0, ka), (t1, kb) = KEYS[seg], KEYS[seg + 1]
            u = (t - t0) / (t1 - t0); u = sstep(u) if EASE[seg] == "s" else ease_out(u)
            oa, ob = A.OPTS[ka], A.OPTS[kb]
            body = body_blend(oa["body"], ob["body"], u)
            body.pop("RootT", None)
            aimv = slerp_v(np.asarray(oa["aim"]), np.asarray(ob["aim"]), u)
            Q, info = A.solve_two_hand(M, body, aimv, oa["butt"], poleR=ob["poleR"], poleL=ob["poleL"], x0=x)
            x = info["x"]; P = K1.skirts(K1.pads(Q))
            if i % 4 == 0: print("  %.2f %s→%s errR %.2f errL %.2f ov %d" % (t, ka, kb, info["errR"], info["errL"], info["overlap"]), flush=True)
        r = recoil(t)
        if r > 0.01:
            P["Waist"] = P["Waist"] @ V.Rx(2.5 * r); P["Neck"] = P["Neck"] @ V.Rx(-1.0 * r)
        off = hermite(t)                                     # 복셀 (x, 깊이, 높이)
        bob = 0.22 * np.sin((t - KEYS[-1][0]) / 1.5 * 2 * np.pi) if t > KEYS[-1][0] else 0.0
        P["RootT"] = (finalT[0] - off[0] / 10, finalT[1] + off[2] / 10 + bob, finalT[2] + off[1] / 10)
        poses.append(P)
    # 몸 가운데·최저점(땅 뚫림 검사)
    samp = {n: (np.argwhere(p.a > 0) + p.lo)[::40].astype(float) for n, p in M.parts.items()}
    ctr, low = [], []
    for P in poses:
        _, c = V.blocks(M, P)
        pts = np.concatenate([q @ c[n][:3, :3].T + c[n][:3, 3] for n, q in samp.items()])
        ctr.append(0.5 * (pts.min(0) + pts.max(0))); low.append(pts[:, 2].min())
    print("lowest point over clip: %.0f 칸" % min(low))
    pickle.dump(dict(poses=poses, ctr=np.array(ctr)), open("anim6_poses.pkl", "wb"))

D = None
def data():
    global D
    if D is None: D = pickle.load(open("anim6_poses.pkl", "rb"))
    return D

def cam(i):
    """pitch 는 몸 가운데를 따라감(조금 부드럽게) · 화면 반폭 = 거리 × tan(25°) × 4/3"""
    d = data()
    lo, hi = max(0, i - 3), min(len(d["ctr"]), i + 4)
    c = d["ctr"][lo:hi].mean(0)
    v = c - CAM
    elev = np.degrees(np.arctan2(v[2], v[1]))
    pitch = -(14.0 + 0.7 * (elev - 14.0))          # 70% 만 따라감 → 화면 위에서 내려오는 게 보이고, 가장 가까울 때 머리가 덜 잘림
    dd, f, r, u = vp._basis(0.0, pitch)
    z = v @ f
    H = z * TANV; W = H * OW / OH
    cx, cy = CAM @ r, CAM @ u
    return float(pitch), ((float(cx - W), float(cx + W)), (float(cy - H), float(cy + H))), float(OW / (2 * W))

MUZ = [A.MUZZLE, np.array([-40, -12.8, 31.3])]

def add_muzzle(im, p0, p1, k, s):
    L = Image.new("RGB", im.size, (0, 0, 0)); d = ImageDraw.Draw(L)
    x, y = p0; dx, dy = p1[0] - x, p1[1] - y; n = np.hypot(dx, dy); s = s * k
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
    P = data()["poses"][i]; M = model(*flames(t))
    pitch, size, ppc_t = cam(i)
    ppc = min(ppc_t, 3.0); ss = 2 if ppc <= 1.8 else 1
    B, cache = V.blocks(M, P)
    im = vp.render(B, V.PAL, V.EMIT, yaw=0.0, pitch=pitch, ppc=ppc, ss=ss, size=size, ao_amt=0.5)
    sc = OW / im.width
    im = im.resize((OW, OH), Image.LANCZOS)
    def scr(p):
        x, y = V.project(p, 0.0, pitch, size, ppc); return x * sc, y * sc
    for j, s in enumerate(SHOTS):
        if 0 <= t - s < 0.06:
            R = cache["RifleR"]; m = R[:3, :3] @ MUZ[j % 2] + R[:3, 3]; ahead = m + R[:3, :3] @ np.array([0, 0, -12.0])
            im = add_muzzle(im, scr(m), scr(ahead), 1.0 - (t - s) / 0.06 * 0.5, ppc_t / 2.2)
    e = float(np.exp(-((t - T_EYE) / 0.09) ** 2)) if t < T_EYE else float(np.exp(-(t - T_EYE) / 0.3))
    if e > 0.02:
        T = cache["Head"]; pt = T[:3, :3] @ S1.EYE_LOCAL + T[:3, 3]
        im = S1.add_flare(im, *scr(pt), e, ppc_t)
    ImageDraw.Draw(im).text((14, 10), "B 강하 사격 → 급제동  %.2fs" % t, font=ImageFont.truetype(FONT, 18), fill=(200, 205, 214))
    out = "frames6_B/%04d.png" % i; im.save(out); return out

if __name__ == "__main__":
    if sys.argv[1] == "pre":
        precompute(); print("poses ok")
    else:
        os.makedirs("frames6_B", exist_ok=True)
        N = int(END * FPS) + 1
        idx = [int(x) for x in sys.argv[2].split(",")] if len(sys.argv) > 2 else list(range(N))
        with Pool(2) as pool:
            for j, _ in enumerate(pool.imap(job, idx)):
                if j % 30 == 0: print("B", j, len(idx), flush=True)
        print("done", len(idx))
