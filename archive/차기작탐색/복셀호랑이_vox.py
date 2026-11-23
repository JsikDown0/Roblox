"""복셀 호랑이 시안 — SDF 프리미티브를 격자에 찍고, 보이는 면만 투영해 그린다.
좌표: x = 앞(머리 쪽 +), y = 위, z = 옆(오른쪽 +). 단위는 '미터 비슷한 값', s = 복셀 한 칸 크기.
"""
import math
import numpy as np
from PIL import Image, ImageDraw

# ---------- SDF ----------
def sd_ellipsoid(p, c, r):
    q = (p - c) / r
    k = np.sqrt((q * q).sum(-1))
    return (k - 1.0) * r.min()

def sd_capsule(p, a, b, ra, rb=None):
    rb = ra if rb is None else rb
    pa, ba = p - a, b - a
    h = np.clip((pa * ba).sum(-1) / (ba * ba).sum(), 0, 1)
    r = ra + (rb - ra) * h
    return np.sqrt(((pa - ba * h[..., None]) ** 2).sum(-1)) - r

def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)

V = lambda *a: np.array(a, dtype=float)

# ---------- 색 ----------
ORANGE = (222, 128, 38)
ORANGE_D = (196, 104, 28)
CREAM = (238, 226, 204)
BLACK = (34, 28, 26)
EYE = (236, 186, 40)
PUPIL = (20, 16, 14)
NOSE = (214, 140, 132)
WHITE = (250, 248, 242)


def build(P):
    """P: 비율 파라미터. 반환: occ(bool 격자), col(색 격자), 원점, s"""
    s = P["s"]
    parts = []  # (이름, sdf 함수)
    L = P["body_len"]; H = P["leg_h"]; R = P["body_r"]
    hx = L / 2
    # 몸통: 가슴 · 엉덩이 · 허리
    chest_c = V(hx * 0.62, H + R * 0.95, 0)
    rump_c = V(-hx * 0.62, H + R * 0.85, 0)
    parts.append(("body", lambda p: smin(smin(
        sd_ellipsoid(p, chest_c, V(R * 1.15, R * 1.05, R * 0.82)),
        sd_ellipsoid(p, rump_c, V(R * 1.1, R * 0.98, R * 0.8)), R * 0.5),
        sd_ellipsoid(p, V(0, H + R * 0.88, 0), V(hx * 0.9, R * 0.86, R * 0.74)), R * 0.4)))
    # 목 + 머리
    hr = P["head_r"]
    head_c = chest_c + V(R * 0.95 + hr * 0.55, R * 0.35 + P["head_up"], 0)
    parts.append(("neck", lambda p: sd_capsule(p, chest_c + V(R * 0.4, R * 0.2, 0), head_c - V(hr * 0.3, 0, 0), R * 0.68, hr * 0.85)))
    parts.append(("head", lambda p: sd_ellipsoid(p, head_c, V(hr * 1.0, hr * 0.95, hr * 0.95))))
    rf = P.get("ruff", 1.0)
    parts.append(("ruff", lambda p: sd_ellipsoid(p, head_c + V(-hr * 0.15, -hr * 0.2, 0), V(hr * 0.7 * rf, hr * 0.8 * rf, hr * 1.25 * rf))))
    mz = head_c + V(hr * 0.85, -hr * 0.28, 0)
    parts.append(("muzzle", lambda p: sd_ellipsoid(p, mz, V(hr * 0.5 * P["muzzle"], hr * 0.42, hr * 0.55))))
    for sz in (-1, 1):
        ec = head_c + V(-hr * 0.2, hr * 0.78, sz * hr * 0.58)
        parts.append((f"ear{sz}", lambda p, ec=ec: sd_ellipsoid(p, ec, V(hr * P.get("ear_t", 0.24), hr * 0.3 * P["ear"], hr * 0.27 * P["ear"]))))
    # 다리
    lr = P["leg_r"]
    for fx, top_c, kn in ((1, chest_c, 1.0), (-1, rump_c, -1.0)):
        for sz in (-1, 1):
            top = top_c + V(fx * R * 0.1, -R * 0.2, sz * R * 0.48)
            knee = V(top[0] + kn * lr * 0.4 - (0 if fx > 0 else lr * 0.6), H * 0.45, sz * R * 0.5)
            foot = V(top[0] + (lr * 0.5 if fx > 0 else -lr * 0.2), lr * P["paw"] * 0.55, sz * R * 0.5)
            parts.append((f"leg{fx}{sz}", lambda p, a=top, b=knee, c=foot: smin(
                sd_capsule(p, a, b, lr * (1.45 if fx < 0 else 1.25), lr * 1.0),
                sd_capsule(p, b, c, lr * 1.0, lr * 0.95), lr * 0.4)))
            parts.append((f"paw{fx}{sz}", lambda p, c=foot: sd_ellipsoid(p, c + V(lr * 0.35, 0, 0), V(lr * 1.35 * P["paw"], lr * 0.62 * P["paw"], lr * 1.08 * P["paw"]))))
    # 꼬리 (아래로 늘어졌다가 끝이 살짝 올라감)
    tl = P["tail_len"]; tr = P["tail_r"]
    pts = []
    for i in range(9):
        t = i / 8
        pts.append(rump_c + V(-R * 0.9 - tl * t, R * 0.3 - tl * 0.85 * math.sin(t * 1.35) + tl * 0.25 * max(0, t - 0.75) * 4, 0))
    def tail_sdf(p, pts=pts):
        d = None
        for i in range(len(pts) - 1):
            r0 = tr * (1 - 0.25 * i / 8); r1 = tr * (1 - 0.25 * (i + 1) / 8)
            di = sd_capsule(p, pts[i], pts[i + 1], r0, r1)
            d = di if d is None else np.minimum(d, di)
        return d
    parts.append(("tail", tail_sdf))

    # 격자
    lo = V(-hx - R - tl * 1.1, 0, -R - hr * 1.3)
    hi = V(head_c[0] + hr * 1.8, head_c[1] + hr * 1.6, R + hr * 1.3)
    n = np.ceil((hi - lo) / s).astype(int)
    xs = lo[0] + (np.arange(n[0]) + 0.5) * s
    ys = lo[1] + (np.arange(n[1]) + 0.5) * s
    zs = lo[2] + (np.arange(n[2]) + 0.5) * s
    p = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1)
    ds = np.stack([f(p) for _, f in parts], -1)
    # 머리 쪽 부드럽게 붙이기
    names = [nm for nm, _ in parts]
    d = ds.min(-1)
    occ = d < 0
    who = np.array(names)[ds.argmin(-1)]

    # ---------- 칠하기 ----------
    col = np.zeros(occ.shape + (3,), dtype=np.uint8)
    col[...] = ORANGE
    X, Y, Z = p[..., 0], p[..., 1], p[..., 2]
    is_head = np.isin(who, ["head", "muzzle", "ruff"])
    is_leg = np.char.startswith(who.astype(str), "leg") | np.char.startswith(who.astype(str), "paw")
    is_tail = who == "tail"
    is_ear = np.char.startswith(who.astype(str), "ear")

    # 배 · 가슴 아래 · 다리 안쪽 크림색
    belly = (who == "body") & (Y < H + R * 0.55 - np.abs(Z) * 0.35)
    belly |= (who == "neck") & (Y < chest_c[1] - R * 0.1)
    belly |= is_leg & (np.abs(Z) < R * 0.5 - lr * 0.2) & (Y > H * 0.3)
    belly |= np.char.startswith(who.astype(str), "paw") & (Y < lr * P["paw"] * 0.25)
    col[belly] = CREAM

    # 몸통 줄무늬: 등에서 내려오는 띠, 등선에서 V자로 만남, 배 쪽으로 가늘어짐
    body_like = np.isin(who, ["body", "neck"]) | (is_leg & (Y > H * 0.35))
    f = P["stripe_f"]
    phase = X * f + np.abs(Z) * f * 0.6 + 0.35 * np.sin(Y * 7)
    height_t = np.clip((Y - (H + R * 0.2)) / (R * 1.4), 0, 1)  # 0=배 1=등
    thr = P.get("stripe_thr", 0.62) + (1 - height_t) * 0.3
    stripe = body_like & (np.sin(phase) > thr) & ~belly
    col[stripe] = BLACK
    # 다리 바깥 가로 줄
    legstripe = is_leg & (Y > lr * P["paw"]) & (np.sin(Y * f * 1.3 + X * 2) > 0.8) & ~belly & (np.abs(Z) >= R * 0.5 - lr * 0.2)
    col[legstripe] = BLACK

    # 꼬리 고리 + 검은 끝
    tdist = np.abs(X - pts[0][0])
    tail_ring = is_tail & (np.sin(tdist / tl * P["tail_rings"] * math.pi * 2) > 0.45)
    col[is_tail] = ORANGE
    col[tail_ring] = BLACK
    col[is_tail & (tdist > tl * 0.88)] = BLACK

    # 얼굴: 주둥이·뺨·턱 흰색, 이마 줄무늬, 눈, 코
    hx_, hy_ = X - head_c[0], Y - head_c[1]
    face_white = is_head & ((who == "muzzle") | ((who == "ruff") & (hy_ < -hr * 0.18)) | ((who == "head") & (hy_ < -hr * 0.42)))
    # 눈 위 흰 눈썹 점
    for sz in (-1, 1):
        bc = head_c + V(hr * 0.66, hr * 0.5, sz * hr * 0.42)
        face_white |= is_head & (np.sqrt(((p - bc) ** 2).sum(-1)) < hr * 0.12)
    col[face_white] = WHITE if P.get("white_face", True) else CREAM
    brow = (who == "head") & (hy_ > hr * 0.45) & (np.sin(hy_ / hr * 10 + np.abs(Z) / hr * 4) > 0.8) & (hx_ > hr * 0.1)
    if P.get("brow", True):
        col[brow] = BLACK
    cheek = (who == "ruff") & (np.sin((hx_ * 1.5 + hy_) / hr * 8) > 0.82) & (hy_ > -hr * 0.3) & (np.abs(Z) > hr * 0.75)
    if P.get("cheek_stripes", True):
        col[cheek] = BLACK
    # 귀: 뒤 검정 + 흰 점
    col[is_ear] = ORANGE
    ear_back = is_ear & (X < head_c[0] - hr * 0.3)
    col[ear_back] = BLACK
    if P.get("ear_inner", True):
        col[is_ear & (X > head_c[0] - hr * 0.1) & (np.abs(np.abs(Z) - hr * 0.58) < hr * 0.12)] = CREAM
    # 눈 (표면 바로 위 칸)
    eye_c = []
    for sz in (-1, 1):
        ec = head_c + V(hr * 0.72, hr * 0.3, sz * hr * 0.44)
        eye_c.append(ec)
        m = is_head & (np.sqrt(((p - ec) ** 2).sum(-1)) < hr * P["eye"])
        col[m] = EYE
        pm = is_head & (np.sqrt(((p - (ec + V(hr * 0.05, 0, 0))) ** 2).sum(-1)) < hr * P["eye"] * 0.45)
        col[pm] = PUPIL
    nose = (who == "muzzle") & (np.sqrt(((p - (mz + V(hr * 0.45 * P["muzzle"], hr * 0.15, 0))) ** 2).sum(-1)) < hr * 0.2)
    col[nose] = NOSE

    # 같은 색 덩어리가 너무 평평하지 않게 주황만 아주 살짝 얼룩
    rng = np.random.default_rng(3)
    jitter = (rng.random(occ.shape) < P.get('jitter', 0.0)) & np.all(col == ORANGE, -1)
    col[jitter] = ORANGE_D
    return occ, col, s


# ---------- 렌더 ----------
FACES = [  # 법선, 꼭짓점 4개(단위 큐브 기준)
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]
LIGHT = np.array([0.45, 0.8, 0.4]); LIGHT /= np.linalg.norm(LIGHT)


def render(occ, col, yaw_deg, pitch_deg, px, size=(520, 400), bg=(118, 120, 124), outline=True):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    Ry = np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]])
    R = Rx @ Ry
    idx = np.argwhere(occ)
    pad = np.pad(occ, 1)
    polys = []
    for nrm, verts in FACES:
        nb = pad[idx[:, 0] + 1 + nrm[0], idx[:, 1] + 1 + nrm[1], idx[:, 2] + 1 + nrm[2]]
        vis_idx = idx[~nb]
        nw = R @ np.array(nrm, float)
        if nw[2] <= 0:  # 카메라는 +z 쪽에서 본다 → 등을 돌린 면 버림
            continue
        shade = 0.55 + 0.45 * max(0.0, float(np.dot(np.array(nrm, float), LIGHT)))
        for v in vis_idx:
            corners = (np.array(verts, float) + v) @ R.T
            depth = corners[:, 2].mean()
            c = col[tuple(v)]
            polys.append((depth, corners[:, :2], tuple(int(min(255, ch * shade)) for ch in c)))
    allc = np.concatenate([q[1] for q in polys])
    mn, mx = allc.min(0), allc.max(0)
    W, Hh = size
    sc = px
    off = np.array([W / 2, Hh / 2]) - (mn + mx) / 2 * sc * np.array([1, -1])
    img = Image.new("RGB", size, bg)
    dr = ImageDraw.Draw(img)
    polys.sort(key=lambda t: t[0])  # 먼 것부터
    for depth, xy, c in polys:
        pts = [(off[0] + x * sc, off[1] - y * sc) for x, y in xy]
        if outline:
            oc = tuple(int(ch * 0.82) for ch in c)
            dr.polygon(pts, fill=c, outline=oc)
        else:
            dr.polygon(pts, fill=c)
    return img
