"""
vrt.py — 복셀 격자 레이트레이서 (numba)

조명을 '복셀 면' 단위로 미리 굽고(노이즈 없음), 픽셀은 광선 DDA 로 첫 면만 찾아 조회한다.
  면마다 미리 굽기: 중거리 AO(면 위 여러 점에서 반구 광선) / 발광 빛 번짐(가림 판정 포함)
  픽셀마다: 키 라이트 그림자 광선(부드럽게 흔듦) / 꼭짓점 AO(이웃 3칸, 면 안에서 보간) / 하이라이트
후처리: 이음선(블록 경계) · 외곽선 · 블룸 · ACES 톤매핑.

render(G, PAL, EMIS, yaw, pitch, height=900, ss=2, fov=None, ...) -> PIL.Image
EMIS 는 (번호, ...) 또는 {번호: 밝기 배율}.
"""
import numpy as np
from numba import njit, prange
from PIL import Image, ImageDraw
from scipy import ndimage


def _lin(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def _aces(x):
    return np.clip(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), 0, 1)


def basis(yaw, pitch):
    y, p = np.radians(yaw), np.radians(pitch)
    d = np.array([np.sin(y) * np.cos(p), -np.cos(y) * np.cos(p), np.sin(p)])   # 대상 → 카메라
    f = -d
    r = np.cross(f, [0, 0, 1.0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return d, f, r, u


@njit(cache=True, fastmath=True)
def _dda(occ, ox, oy, oz, dx, dy, dz, tmax):
    nx, ny, nz = occ.shape
    t0 = 0.0; t1 = tmax; ax0 = 0
    o = (ox, oy, oz); d = (dx, dy, dz); nn = (nx, ny, nz)
    for a in range(3):
        if abs(d[a]) < 1e-12:
            if o[a] < 0.0 or o[a] > nn[a]:
                return False, 0, 0, 0, 0.0, 0, 0
        else:
            ta = (0.0 - o[a]) / d[a]; tb = (nn[a] - o[a]) / d[a]
            if ta > tb:
                ta, tb = tb, ta
            if ta > t0:
                t0 = ta; ax0 = a
            if tb < t1:
                t1 = tb
    if t0 > t1:
        return False, 0, 0, 0, 0.0, 0, 0
    t = t0
    px = ox + dx * (t + 1e-7); py = oy + dy * (t + 1e-7); pz = oz + dz * (t + 1e-7)
    i = min(max(int(np.floor(px)), 0), nx - 1)
    j = min(max(int(np.floor(py)), 0), ny - 1)
    k = min(max(int(np.floor(pz)), 0), nz - 1)
    sx = 1 if dx > 0 else -1; sy = 1 if dy > 0 else -1; sz = 1 if dz > 0 else -1
    inf = 1e30
    tdx = abs(1.0 / dx) if abs(dx) > 1e-12 else inf
    tdy = abs(1.0 / dy) if abs(dy) > 1e-12 else inf
    tdz = abs(1.0 / dz) if abs(dz) > 1e-12 else inf
    tmx = (((i + 1) - ox) / dx if dx > 0 else (i - ox) / dx) if abs(dx) > 1e-12 else inf
    tmy = (((j + 1) - oy) / dy if dy > 0 else (j - oy) / dy) if abs(dy) > 1e-12 else inf
    tmz = (((k + 1) - oz) / dz if dz > 0 else (k - oz) / dz) if abs(dz) > 1e-12 else inf
    ax = ax0
    while True:
        if occ[i, j, k] > 0:
            sg = -(sx if ax == 0 else (sy if ax == 1 else sz))
            return True, i, j, k, t, ax, sg
        if tmx < tmy and tmx < tmz:
            t = tmx; tmx += tdx; i += sx; ax = 0
            if i < 0 or i >= nx:
                break
        elif tmy < tmz:
            t = tmy; tmy += tdy; j += sy; ax = 1
            if j < 0 or j >= ny:
                break
        else:
            t = tmz; tmz += tdz; k += sz; ax = 2
            if k < 0 or k >= nz:
                break
        if t > t1:
            break
    return False, 0, 0, 0, 0.0, 0, 0


@njit(cache=True)
def _occ(occ, i, j, k):
    nx, ny, nz = occ.shape
    if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz:
        return 0
    return 1 if occ[i, j, k] > 0 else 0


@njit(parallel=True, fastmath=True, cache=True)
def _bake(occ, emis, F, LP, LC, aoK, aoR, spK, spR0, spL, seed):
    """F (n,5) = i,j,k,ax,sg 면 목록 → aoM (n,), spill (n,3)"""
    n = F.shape[0]
    aoM = np.ones(n); spill = np.zeros((n, 3))
    nL = LP.shape[0]
    for q in prange(n):
        np.random.seed(seed + q)
        i, j, k, ax, sg = F[q, 0], F[q, 1], F[q, 2], F[q, 3], F[q, 4]
        a1 = (ax + 1) % 3; a2 = (ax + 2) % 3
        base = np.array([i + 0.5, j + 0.5, k + 0.5])
        base[ax] += sg * (0.5 + 1e-3)
        nv = np.zeros(3); nv[ax] = sg
        occs = 0.0
        for s in range(aoK):
            p = base.copy()
            p[a1] += np.random.random() * 0.9 - 0.45; p[a2] += np.random.random() * 0.9 - 0.45
            r1 = np.random.random(); r2 = np.random.random()
            ph = 6.283185 * r1; sr = np.sqrt(r2)
            v = np.zeros(3)
            v[a1] = sr * np.cos(ph); v[a2] = sr * np.sin(ph); v[ax] = sg * np.sqrt(1 - r2)
            h, _a, _b, _c, th, _x, _s = _dda(occ, p[0], p[1], p[2], v[0], v[1], v[2], aoR)
            if h:
                occs += 1.0 - 0.5 * th / aoR
        aoM[q] = 1.0 - occs / aoK
        # 발광 번짐
        if nL == 0:
            continue
        tot = np.zeros(3); wsum = 0.0
        cw = np.zeros(nL)
        for m in range(nL):
            vx = LP[m, 0] - base[0]; vy = LP[m, 1] - base[1]; vz = LP[m, 2] - base[2]
            d2 = vx * vx + vy * vy + vz * vz
            dl = np.sqrt(d2) + 1e-6
            cs = (nv[0] * vx + nv[1] * vy + nv[2] * vz) / dl
            if cs <= 0:
                continue
            w = cs / (d2 + spR0 * spR0) * np.exp(-dl / spL)
            tot[0] += LC[m, 0] * w; tot[1] += LC[m, 1] * w; tot[2] += LC[m, 2] * w
            cw[m] = w * (LC[m, 0] + LC[m, 1] + LC[m, 2])
            wsum += cw[m]
        if wsum <= 0:
            continue
        vis = 0.0
        for s in range(spK):
            target = np.random.random() * wsum; acc = 0.0; sel = nL - 1
            for m in range(nL):
                acc += cw[m]
                if acc >= target:
                    sel = m
                    break
            p = base.copy()
            p[a1] += np.random.random() * 0.8 - 0.4; p[a2] += np.random.random() * 0.8 - 0.4
            vx = LP[sel, 0] - p[0]; vy = LP[sel, 1] - p[1]; vz = LP[sel, 2] - p[2]
            dl = np.sqrt(vx * vx + vy * vy + vz * vz)
            h, hi_, hj_, hk_, th, _x, _s = _dda(occ, p[0], p[1], p[2], vx / dl, vy / dl, vz / dl, dl)
            if (not h) or emis[occ[hi_, hj_, hk_]] > 0:
                vis += 1.0
        vis /= spK
        spill[q, 0] = tot[0] * vis; spill[q, 1] = tot[1] * vis; spill[q, 2] = tot[2] * vis
    return aoM, spill


@njit(parallel=True, fastmath=True, cache=True)
def _trace(occ, bidg, fid, aoM, spill, pal, emis, RO, RD, L, Lsoft, F, prm, AC, seed):
    H, W = RO.shape[0], RO.shape[1]
    out = np.zeros((H, W, 3)); eb = np.zeros((H, W, 3))
    idb = np.full((H, W), -1, np.int32); zb = np.full((H, W), np.inf)
    amb, key, fill, spec, spow, egain, spk, vao_k = prm[0], prm[1], prm[2], prm[3], prm[4], prm[5], prm[6], prm[7]
    for y in prange(H):
        np.random.seed(seed + y * 7919)
        for x in range(W):
            ox, oy, oz = RO[y, x, 0], RO[y, x, 1], RO[y, x, 2]
            dx, dy, dz = RD[y, x, 0], RD[y, x, 1], RD[y, x, 2]
            hit, i, j, k, t, ax, sg = _dda(occ, ox, oy, oz, dx, dy, dz, 1e9)
            if not hit:
                continue
            c = occ[i, j, k]
            idb[y, x] = bidg[i, j, k]; zb[y, x] = t
            if emis[c] > 0:
                for q in range(3):
                    v = pal[c, q] * egain * emis[c]
                    out[y, x, q] = v; eb[y, x, q] = v
                continue
            nv = np.zeros(3); nv[ax] = sg
            px = ox + dx * t; py = oy + dy * t; pz = oz + dz * t
            pp = np.array([px, py, pz])
            # 키 라이트 + 그림자
            ndl = nv[0] * L[0] + nv[1] * L[1] + nv[2] * L[2]
            vis = 0.0
            if ndl > 0:
                for sh in range(2):
                    lx = L[0] + Lsoft * (np.random.random() * 2 - 1)
                    ly = L[1] + Lsoft * (np.random.random() * 2 - 1)
                    lz = L[2] + Lsoft * (np.random.random() * 2 - 1)
                    ln = np.sqrt(lx * lx + ly * ly + lz * lz)
                    h2, _a, _b, _c, _t, _x, _s = _dda(occ, px + nv[0] * 1e-3, py + nv[1] * 1e-3, pz + nv[2] * 1e-3,
                                                      lx / ln, ly / ln, lz / ln, 800.0)
                    vis += 0.0 if h2 else 0.5
            else:
                ndl = 0.0
            # 꼭짓점 AO (이웃 칸 3개) → 면 안 보간
            a1 = (ax + 1) % 3; a2 = (ax + 2) % 3
            lay = np.array([i, j, k]); lay[ax] += sg
            fu = pp[a1] - np.floor(pp[a1]); fv = pp[a2] - np.floor(pp[a2])
            if fu < 0: fu = 0.0
            if fv < 0: fv = 0.0
            cv = np.zeros(4)
            idx = 0
            for du in (-1, 1):
                for dv in (-1, 1):
                    s1 = lay.copy(); s1[a1] += du
                    s2 = lay.copy(); s2[a2] += dv
                    s3 = lay.copy(); s3[a1] += du; s3[a2] += dv
                    o1 = _occ(occ, s1[0], s1[1], s1[2]); o2 = _occ(occ, s2[0], s2[1], s2[2]); o3 = _occ(occ, s3[0], s3[1], s3[2])
                    if o1 == 1 and o2 == 1:
                        cv[idx] = 0.0
                    else:
                        cv[idx] = 3.0 - (o1 + o2 + o3)
                    idx += 1
            # cv: (-,-),(-,+),(+,-),(+,+)
            va = (cv[0] * (1 - fu) * (1 - fv) + cv[1] * (1 - fu) * fv + cv[2] * fu * (1 - fv) + cv[3] * fu * fv) / 3.0
            vao = 1.0 - vao_k * (1.0 - va)
            f_ = fid[(ax * 2 + (1 if sg > 0 else 0)), i, j, k]
            am_ = aoM[f_] if f_ >= 0 else 1.0
            sky = 0.55 + 0.45 * nv[2]
            fl = nv[0] * F[0] + nv[1] * F[1] + nv[2] * F[2]
            if fl < 0:
                fl = 0.0
            hx = L[0] - dx; hy = L[1] - dy; hz = L[2] - dz
            hn = np.sqrt(hx * hx + hy * hy + hz * hz)
            nh = (nv[0] * hx + nv[1] * hy + nv[2] * hz) / hn
            sp = spec * (nh ** spow if nh > 0 else 0.0) * vis
            occf = am_ * vao
            lit = key * ndl * vis * (0.7 + 0.3 * occf) + fill * fl * occf
            am = amb * sky * occf
            for q in range(3):
                sv = spill[f_, q] * spk if f_ >= 0 else 0.0
                out[y, x, q] = pal[c, q] * (lit + am * AC[q] + sv * (0.5 + 0.5 * vao)) + sp
    return out, eb, idb, zb


def _faces(occ):
    o = occ > 0
    p = np.pad(o, 1)
    nx, ny, nz = o.shape
    fid = np.full((6, nx, ny, nz), -1, np.int32)
    lst = []
    nb = {0: (p[:-2, 1:-1, 1:-1], p[2:, 1:-1, 1:-1]), 1: (p[1:-1, :-2, 1:-1], p[1:-1, 2:, 1:-1]), 2: (p[1:-1, 1:-1, :-2], p[1:-1, 1:-1, 2:])}
    n0 = 0
    for ax in range(3):
        for s_i, sg in enumerate((-1, 1)):
            m = o & ~nb[ax][s_i]
            idx = np.argwhere(m)
            fid[ax * 2 + s_i][m] = np.arange(n0, n0 + len(idx))
            n0 += len(idx)
            lst.append(np.concatenate([idx, np.full((len(idx), 1), ax), np.full((len(idx), 1), sg)], 1))
    return np.concatenate(lst).astype(np.int64), fid


def _lights(G, emis, binsz=2):
    E = np.argwhere(emis[G.col] > 0)
    if len(E) == 0:
        return np.zeros((0, 3)), np.zeros(0, np.int64), E
    key = E // binsz
    uk, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    cnt = np.bincount(inv).astype(float)
    pos = np.stack([np.bincount(inv, E[:, a] + 0.5) for a in range(3)], 1) / cnt[:, None]
    return pos, inv, E


def bake(G, PAL, EMIS, aoK=40, aoR=12.0, spK=20, spR0=3.0, spL=7.0, seed=7):
    """면 조명 굽기(모델이 바뀔 때 한 번). 결과는 G 에 붙여 둔다."""
    pal = np.zeros((256, 3))
    for k_, c_ in PAL.items():
        pal[int(k_)] = _lin(c_)
    emis = np.zeros(256)
    for k_ in EMIS:
        emis[int(k_)] = (EMIS[k_] if isinstance(EMIS, dict) else 1.0)
    F, fid = _faces(G.col)
    pos, inv, E = _lights(G, emis)
    LC = np.zeros((len(pos), 3))
    if len(pos):
        cc = pal[G.col[E[:, 0], E[:, 1], E[:, 2]]] * emis[G.col[E[:, 0], E[:, 1], E[:, 2]]][:, None]
        for a in range(3):
            LC[:, a] = np.bincount(inv, cc[:, a])
    aoM, spill = _bake(G.col, emis, F, pos, LC, aoK, aoR / G.vs, spK, spR0 / G.vs, spL / G.vs, seed)
    G.baked = (fid, aoM, spill, pal, emis)
    return G


def keylight(yaw, pitch, side=-0.75, up=0.8, front=0.5):
    d, f, r, u = basis(yaw, pitch)
    L = side * r + up * u + front * d
    return L / np.linalg.norm(L)


def render(G, PAL, EMIS, yaw=0, pitch=5, height=900, ss=2, fov=None, frame=None, margin=0.05, light=None,
           soft=0.06, amb=0.42, key=1.25, fill=0.10, spec=0.22, spow=40, egain=3.0, spill=1.4, vao=0.22,
           seams=0.30, outline=0.45, bloom=0.8, exposure=1.0, bg=(9, 10, 14), seed=1,
           return_frame=False, amb_col=(0.84, 0.93, 1.12)):
    """height = 결과 이미지 높이(px). frame = 축척을 맞출 때 쓰는 화면 범위."""
    if not hasattr(G, "baked"):
        bake(G, PAL, EMIS)
    fid, aoM, spl, pal, emis = G.baked
    d, f, r, u = basis(yaw, pitch)
    occ = G.col; vs = G.vs
    S = np.argwhere(occ > 0)
    Pw = G.org + (S + 0.5) * vs
    if fov is None:
        sx = Pw @ r; sy = Pw @ u
        if frame is None:
            x0, x1, y0, y1 = sx.min(), sx.max(), sy.min(), sy.max()
            m = (y1 - y0) * margin
            frame = (x0 - m, x1 + m, y0 - m, y1 + m)
        x0, x1, y0, y1 = frame
        Hh = int(height * ss); scale = Hh / (y1 - y0)
        Ww = int((x1 - x0) * scale)
        gx = x0 + (np.arange(Ww) + 0.5) / scale
        gy = y1 - (np.arange(Hh) + 0.5) / scale
        c0 = Pw.mean(0)
        D = np.linalg.norm(Pw.max(0) - Pw.min(0)) * 2
        RO = (c0 - (c0 @ r) * r - (c0 @ u) * u)[None, None, :] + gx[None, :, None] * r + gy[:, None, None] * u - f * D
        RD = np.broadcast_to(f, RO.shape).copy()
    else:
        lo, hi = Pw.min(0), Pw.max(0)
        c0 = (lo + hi) / 2
        rad = np.linalg.norm(hi - lo) / 2
        dist = rad / np.tan(np.radians(fov) / 2)
        Cam = c0 + d * dist
        rel = Pw - Cam
        zc = rel @ f
        xs = (rel @ r) / zc; ys = (rel @ u) / zc
        if frame is None:
            x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
            m = (y1 - y0) * margin
            frame = (x0 - m, x1 + m, y0 - m, y1 + m)
        x0, x1, y0, y1 = frame
        Hh = int(height * ss); scale = Hh / (y1 - y0)
        Ww = int((x1 - x0) * scale)
        gx = x0 + (np.arange(Ww) + 0.5) / scale
        gy = y1 - (np.arange(Hh) + 0.5) / scale
        RD = f[None, None, :] + gx[None, :, None] * r + gy[:, None, None] * u
        RD /= np.linalg.norm(RD, axis=-1, keepdims=True)
        RO = np.broadcast_to(Cam, RD.shape).copy()
    ROg = (RO - G.org) / vs
    L = keylight(yaw, pitch) if light is None else np.asarray(light, float) / np.linalg.norm(light)
    Fv = 0.7 * r - 0.1 * u + 0.5 * d; Fv /= np.linalg.norm(Fv)
    prm = np.array([amb, key, fill, spec, spow, egain, spill, vao], float)
    out, eb, idb, zb = _trace(occ, G.bid, fid, aoM, spl, pal, emis, ROg, np.ascontiguousarray(RD), L, soft, Fv, prm,
                              np.asarray(amb_col, float), seed)
    hit = idb >= 0
    img = out * exposure
    isem = eb.sum(-1) > 0
    if seams > 0:
        e = np.zeros(hit.shape, bool)
        a = (idb[:, 1:] != idb[:, :-1]) & hit[:, 1:] & hit[:, :-1]
        e[:, 1:] |= a
        b = (idb[1:, :] != idb[:-1, :]) & hit[1:, :] & hit[:-1, :]
        e[1:, :] |= b
        e &= ~isem
        img[e] *= (1 - seams)
    if outline > 0:
        D = np.where(hit, zb, 1e9)
        o = np.zeros(hit.shape, bool)
        th = 2.5
        o[:, 1:] |= np.abs(D[:, 1:] - D[:, :-1]) > th
        o[1:, :] |= np.abs(D[1:, :] - D[:-1, :]) > th
        o &= hit & ~isem
        img[o] *= (1 - outline)
    bgl = _lin(bg)
    yy = np.linspace(1.25, 0.8, img.shape[0])[:, None]
    xx = np.linspace(-1, 1, img.shape[1])[None, :]
    vig = (1 - 0.3 * xx ** 2)
    img = np.where(hit[..., None], img, bgl[None, None, :] * (yy * vig)[..., None])
    if bloom and isem.any():
        bl = np.zeros_like(eb)
        kp = ss * height / 900.0
        for sig, w in ((1.5 * kp, 0.45), (5 * kp, 0.3), (14 * kp, 0.14)):
            bl += w * np.stack([ndimage.gaussian_filter(eb[..., i], sig) for i in range(3)], -1)
        img = img + bloom * bl
    img = _aces(img)
    outp = (_srgb(img) * 255 + 0.5).astype(np.uint8)
    im = Image.fromarray(outp)
    if ss > 1:
        im = im.resize((im.width // ss, im.height // ss), Image.LANCZOS)
    if return_frame:
        return im, frame
    return im


def sheet(images, labels=None, bg=(9, 10, 14), pad=14):
    h = max(i.height for i in images)
    w = sum(i.width for i in images) + pad * (len(images) + 1)
    S = Image.new("RGB", (w, h + pad * 2 + (22 if labels else 0)), bg)
    dr = ImageDraw.Draw(S)
    x = pad
    for k, im in enumerate(images):
        S.paste(im, (x, pad + (h - im.height)))
        if labels:
            dr.text((x + 4, pad + h + 4), labels[k], fill=(170, 175, 185))
        x += im.width + pad
    return S
