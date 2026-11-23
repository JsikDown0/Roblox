"""
vox_preview.py — 컨테이너 쪽 복셀 미리보기 렌더러 (numpy 점 찍기 + z버퍼)

render(blocks, palette, yaw, pitch) -> PIL.Image
  blocks : [(lo(xyz 칸), uint8 배열), ...]  (같은 칸이면 뒤의 것이 덮음)
  palette: {n: (r,g,b)}, emissive: 발광 번호 집합
  yaw    : 0 = 정면(-Y 쪽 카메라), 90 = 기체 왼쪽(+X), 180 = 뒤
  pitch  : 카메라 높이각(도)
칸 중심 = 정수 좌표, 칸 = ±0.5.
조명: 키(그림자 맵) + 하늘 + 반대편 보조광 + 모서리 AO, 발광은 음영 없이 + 번짐(bloom).
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage


def _lin(c):
    c = np.asarray(c, np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def merge(blocks):
    lo = np.min([b[0] for b in blocks], 0) - 2
    hi = np.max([np.array(b[0]) + np.array(b[1].shape) for b in blocks], 0) + 2
    G = np.zeros(tuple(hi - lo), np.uint8)
    for l, a in blocks:
        o = np.array(l) - lo
        sl = tuple(slice(o[i], o[i] + a.shape[i]) for i in range(3))
        sub = G[sl]
        sub[a > 0] = a[a > 0]
    return lo, G


def _basis(yaw, pitch):
    y, p = np.radians(yaw), np.radians(pitch)
    d = np.array([np.sin(y) * np.cos(p), -np.cos(y) * np.cos(p), np.sin(p)])   # 물체 → 카메라
    f = -d
    r = np.cross(f, [0, 0, 1.0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return d, f, r, u


AX = [np.array(v) for v in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]


def _faces(O, d, k):
    """d 쪽을 보는 드러난 면의 표본점. -> P(N,3 float32), n(N,3), ao(N), col_idx(N,3 int 셀)"""
    out = []
    t = (np.arange(k) + 0.5) / k - 0.5
    TU, TW = np.meshgrid(t, t, indexing="ij")
    TU, TW = TU.ravel(), TW.ravel()
    Pd = np.pad(O, 1)
    for a in range(3):
        for s in (1, -1):
            n = AX[a] * s
            if np.dot(n, d) <= 1e-6:
                continue
            nb = np.roll(Pd, -s, axis=a)[1:-1, 1:-1, 1:-1]
            ex = O & ~nb
            cells = np.argwhere(ex)
            if len(cells) == 0:
                continue
            u, w = (a + 1) % 3, (a + 2) % 3
            A = cells + n                       # 앞 빈칸
            def occ(q):
                q = q + 1
                return Pd[q[:, 0], q[:, 1], q[:, 2]]
            eu, ew = AX[u], AX[w]
            ao = np.zeros((len(cells), 4), np.float32)
            for ci, (su, sw) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
                s1 = occ(A + su * eu); s2 = occ(A + sw * ew); c3 = occ(A + su * eu + sw * ew)
                v = np.where(s1 & s2, 0, 3 - (s1.astype(int) + s2 + c3))
                ao[:, ci] = v
            ctr = cells + 0.5 * n
            P = (ctr[:, None, :] + TU[None, :, None] * eu + TW[None, :, None] * ew).reshape(-1, 3).astype(np.float32)
            fu = np.tile(TU + 0.5, len(cells)); fw = np.tile(TW + 0.5, len(cells))
            aoe = np.repeat(ao, len(TU), axis=0)
            aov = (aoe[:, 0] * (1 - fu) * (1 - fw) + aoe[:, 1] * fu * (1 - fw) + aoe[:, 2] * (1 - fu) * fw + aoe[:, 3] * fu * fw)
            out.append((P, np.repeat(n[None], len(P), 0).astype(np.float32), aov.astype(np.float32), np.repeat(cells, len(TU), 0)))
    P = np.concatenate([o[0] for o in out]); N = np.concatenate([o[1] for o in out])
    AO = np.concatenate([o[2] for o in out]); C = np.concatenate([o[3] for o in out])
    return P, N, AO, C


def _zbuf(sx, sy, dep, W, H):
    ok = (sx >= 0) & (sx < W) & (sy >= 0) & (sy < H)
    idx = np.nonzero(ok)[0]
    pix = sy[idx].astype(np.int64) * W + sx[idx]
    order = np.lexsort((dep[idx], pix))
    ps = pix[order]
    first = np.ones(len(ps), bool); first[1:] = ps[1:] != ps[:-1]
    win = idx[order[first]]
    return pix[order[first]], win


def _groups(blocks):
    """같은 변환(None=그대로)끼리 합쳐 격자 하나로 → (lo, G, T)"""
    plain = [(b[0], b[1]) for b in blocks if len(b) < 3 or b[2] is None]
    out = []
    if plain:
        lo, G = merge(plain)
        out.append((lo, G, None))
    for b in blocks:
        if len(b) >= 3 and b[2] is not None:
            lo, G = merge([(b[0], b[1])])
            out.append((lo, G, np.asarray(b[2], float)))
    return out


def _gather(groups, d, k):
    Ps, Ns, AOs, cols = [], [], [], []
    for lo, G, T in groups:
        O = G > 0
        R = np.eye(3) if T is None else T[:3, :3]
        dl = R.T @ d
        try:
            P, N, AO, C = _faces(O, dl, k if T is None else k + 3)
        except ValueError:
            continue
        col = G[C[:, 0], C[:, 1], C[:, 2]]
        P = P + lo
        if T is not None:
            P = (P @ R.T + T[:3, 3]).astype(np.float32)
            N = (N @ R.T).astype(np.float32)
        Ps.append(P); Ns.append(N); AOs.append(AO); cols.append(col)
    return np.concatenate(Ps), np.concatenate(Ns), np.concatenate(AOs), np.concatenate(cols)


def render(blocks, palette, emissive=(), yaw=0, pitch=8, ppc=3.0, ss=2, size=None, bg=(13, 14, 17),
           light=(-0.55, -0.75, 0.85), samples=None, bloom=1.0, shadow=True, outline=True, ground=True, ao_amt=0.55):
    groups = _groups(blocks)
    d, f, r, u = _basis(yaw, pitch)
    k = samples or int(np.ceil(ppc * ss * 1.25)) + 1
    Pw, N, AO, COL = _gather(groups, d, k)
    sxw = Pw @ r; syw = Pw @ u; dep = Pw @ f
    kp = ppc * ss
    if size is None:
        x0, x1 = sxw.min() - 6, sxw.max() + 6; y0, y1 = syw.min() - 6, syw.max() + 6
    else:
        (x0, x1), (y0, y1) = size
    W = int((x1 - x0) * kp); H = int((y1 - y0) * kp)
    ix = ((sxw - x0) * kp).astype(np.int64); iy = ((y1 - syw) * kp).astype(np.int64)
    pix, win = _zbuf(ix, iy, dep, W, H)

    col = COL[win]
    n = N[win]; ao = AO[win]; pw = Pw[win]
    L = np.array(light, float); L /= np.linalg.norm(L)
    lam = np.clip(n @ L, 0, 1)

    sh = np.ones(len(win), np.float32)
    if shadow:
        ld = L
        lf = -ld
        lr = np.cross(lf, [0, 0, 1.0]); lr /= np.linalg.norm(lr)
        lu = np.cross(lr, lf)
        Ps, _, _, _ = _gather(groups, ld, 3)
        ks = 2.5
        lx = Ps @ lr; ly = Ps @ lu; ldp = Ps @ lf
        lx0, ly1 = lx.min() - 2, ly.max() + 2
        LW = int((lx.max() + 2 - lx0) * ks) + 1; LH = int((ly1 - (ly.min() - 2)) * ks) + 1
        jx = ((lx - lx0) * ks).astype(np.int64); jy = ((ly1 - ly) * ks).astype(np.int64)
        lpix, lwin = _zbuf(jx, jy, ldp, LW, LH)
        zmap = np.full(LW * LH, np.inf, np.float32); zmap[lpix] = ldp[lwin]
        qx = ((pw @ lr - lx0) * ks).astype(np.int64); qy = ((ly1 - pw @ lu) * ks).astype(np.int64)
        okq = (qx >= 0) & (qx < LW) & (qy >= 0) & (qy < LH)
        zq = np.full(len(win), np.inf, np.float32)
        zq[okq] = zmap[qy[okq] * LW + qx[okq]]
        lit = (pw @ lf) <= zq + 1.6 + 1.6 * (1 - np.clip(n @ L, 0, 1))
        sh = np.where(lit, 1.0, 0.0).astype(np.float32)

    pal = np.zeros((256, 3), np.float32)
    for kk, c in palette.items():
        pal[int(kk)] = _lin(c)
    base = pal[col]
    fill = np.array([0.6, -0.3, 0.2]); fill /= np.linalg.norm(fill)
    sky = 0.5 + 0.5 * n[:, 2]
    aof = (1 - ao_amt + ao_amt * (ao / 3.0)) ** 1.2
    light_amt = (0.20 + 0.14 * sky) * aof + 0.95 * lam * sh * (0.75 + 0.25 * aof) + 0.18 * np.clip(n @ fill, 0, 1) * aof
    rim = np.clip(1 - np.abs(n @ d), 0, 1) * 0.0
    shade = base * light_amt[:, None] + rim[:, None]
    em = np.isin(col, list(emissive))
    shade[em] = base[em] * 1.35

    img = np.zeros((H * W, 3), np.float32)
    bgl = _lin(bg)
    # 배경 세로 그라데이션
    gy = np.linspace(1.15, 0.75, H)[:, None, None]
    img[:] = (np.broadcast_to(bgl[None, None, :] * gy, (H, W, 3))).reshape(-1, 3)
    img[pix] = shade
    img = img.reshape(H, W, 3)
    depth = np.full(H * W, np.inf, np.float32); depth[pix] = dep[win]; depth = depth.reshape(H, W)

    if outline:
        D = depth.copy(); D[~np.isfinite(D)] = 1e6
        e = np.zeros((H, W), bool)
        th = 2.5
        e[:, 1:] |= np.abs(D[:, 1:] - D[:, :-1]) > th
        e[1:, :] |= np.abs(D[1:, :] - D[:-1, :]) > th
        # 경계의 앞쪽(가까운) 픽셀만 칠하지 않고 양쪽 다 → 두께 ~ss
        e = ndimage.binary_dilation(e, iterations=max(1, ss // 2))
        img[e] = img[e] * 0.25 + _lin((8, 9, 11)) * 0.75

    if bloom and em.any():
        emimg = np.zeros((H * W, 3), np.float32)
        emimg[pix[em]] = base[em]
        emimg = emimg.reshape(H, W, 3)
        bl = np.zeros_like(emimg)
        for sig, wgt in ((kp * 0.8, 0.55), (kp * 2.5, 0.35), (kp * 6, 0.25)):
            bl += wgt * np.stack([ndimage.gaussian_filter(emimg[..., i], sig) for i in range(3)], -1)
        img = img + bloom * bl

    out = (_srgb(img) * 255 + 0.5).astype(np.uint8)
    im = Image.fromarray(out)
    if ss > 1:
        im = im.resize((W // ss, H // ss), Image.LANCZOS)
    return im


def sheet(images, labels=None, bg=(13, 14, 17), pad=16, title=None):
    h = max(i.height for i in images)
    w = sum(i.width for i in images) + pad * (len(images) + 1)
    top = 40 if title else 0
    S = Image.new("RGB", (w, h + pad * 2 + top + (24 if labels else 0)), bg)
    dr = ImageDraw.Draw(S)
    x = pad
    if title:
        dr.text((pad, 12), title, fill=(220, 224, 230))
    for i, im in enumerate(images):
        S.paste(im, (x, top + pad + (h - im.height)))
        if labels:
            dr.text((x + 4, top + pad + h + 4), labels[i], fill=(170, 175, 185))
        x += im.width + pad
    return S
