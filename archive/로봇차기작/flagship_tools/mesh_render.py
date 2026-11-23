"""
mesh_render.py — 블록 메시 미리보기 렌더러 (numpy, 직교 카메라)

삼각형 z버퍼 래스터 → 픽셀별 법선·색·블록번호 → 조명:
  키 라이트(그림자 맵) + 반대편 보조광 + 하늘/땅 환경광 × SSAO(깊이 기반) + Blinn 하이라이트 + 림 라이트
  블록 경계는 얇은 이음선, 실루엣은 외곽선, 발광은 번짐(bloom). ss 배로 그려서 줄임(계단 완화).
render(V, N, C, B, palette, emissive, yaw, pitch, ppc, ...) -> PIL.Image
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage


def _lin(c):
    c = np.asarray(c, np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def basis(yaw, pitch):
    y, p = np.radians(yaw), np.radians(pitch)
    d = np.array([np.sin(y) * np.cos(p), -np.cos(y) * np.cos(p), np.sin(p)])
    f = -d
    r = np.cross(f, [0, 0, 1.0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return d, f, r, u


def raster(S, Z, W, H, ids=None):
    """S (N,3,2) 픽셀 좌표, Z (N,3) 깊이 → zbuf (H,W), idbuf (H,W)"""
    zb = np.full((H, W), np.inf, np.float32)
    ib = np.full((H, W), -1, np.int32)
    xmin = np.floor(S[:, :, 0].min(1)).astype(int); xmax = np.ceil(S[:, :, 0].max(1)).astype(int)
    ymin = np.floor(S[:, :, 1].min(1)).astype(int); ymax = np.ceil(S[:, :, 1].max(1)).astype(int)
    xmin = np.clip(xmin, 0, W); xmax = np.clip(xmax, 0, W); ymin = np.clip(ymin, 0, H); ymax = np.clip(ymax, 0, H)
    for i in range(len(S)):
        xa, xb, ya, yb = xmin[i], xmax[i], ymin[i], ymax[i]
        if xb <= xa or yb <= ya:
            continue
        (x0, y0), (x1, y1), (x2, y2) = S[i]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        px = np.arange(xa, xb, dtype=np.float32)[None, :] + 0.5
        py = np.arange(ya, yb, dtype=np.float32)[:, None] + 0.5
        w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area
        w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area
        w2 = 1.0 - w0 - w1
        e = -1e-4
        inside = (w0 >= e) & (w1 >= e) & (w2 >= e)
        if not inside.any():
            continue
        z = w0 * Z[i, 0] + w1 * Z[i, 1] + w2 * Z[i, 2]
        sub = zb[ya:yb, xa:xb]
        m = inside & (z < sub)
        sub[m] = z[m]
        if ids is not None:
            ib[ya:yb, xa:xb][m] = ids[i]
    return zb, ib


def render(V, N, C, B, palette, emissive=(6,), yaw=0, pitch=5, ppc=2.5, ss=2, bg=(13, 15, 21),
           light=(-0.55, -0.8, 0.9), frame=None, margin=8, ao=0.9, seams=0.30, spec=0.22, rim=0.30, bloom=1.0,
           fov=None, target=None, dist_mul=1.0, amb=1.0, fill_amt=0.20, exposure=1.0):
    """fov(도)를 주면 원근 카메라: target(기본 = 경계 중심)을 바라보고, 거리 = 경계 반지름/tan(fov/2)·dist_mul.
    ppc 는 target 거리에서 칸당 픽셀."""
    d, f, r, u = basis(yaw, pitch)
    kp = ppc * ss
    if fov is None:
        keep = (N @ d) > 1e-4
        Vk, Nk, Ck, Bk = V[keep], N[keep], C[keep], B[keep]
        sx = Vk @ r; sy = Vk @ u; dz = Vk @ f
        if frame is None:
            x0, x1 = sx.min() - margin, sx.max() + margin
            y0, y1 = sy.min() - margin, sy.max() + margin
        else:
            (x0, x1), (y0, y1) = frame
        W = int((x1 - x0) * kp); H = int((y1 - y0) * kp)
        S = np.stack([(sx - x0) * kp, (y1 - sy) * kp], -1)
        zb, ib = raster(S, dz, W, H, np.arange(len(Vk)))
        hit = ib >= 0
        gx = (np.arange(W) + 0.5) / kp + x0
        gy = y1 - (np.arange(H) + 0.5) / kp
        P = gx[None, :, None] * r + gy[:, None, None] * u + np.where(hit, zb, 0)[:, :, None] * f
        view = np.broadcast_to(d, P.shape)
    else:
        allp = V.reshape(-1, 3)
        lo, hi = allp.min(0), allp.max(0)
        c = (lo + hi) / 2 if target is None else np.asarray(target, float)
        rad = np.linalg.norm(hi - lo) / 2
        dist = rad / np.tan(np.radians(fov) / 2) * dist_mul
        Cam = c + d * dist
        focal = kp * dist
        rel = V - Cam                                   # (N,3,3)
        zc = rel @ f
        keep = ((V[:, 0, :] - Cam) * N).sum(-1) < -1e-6
        keep &= (zc > 1).all(1)
        Vk, Nk, Ck, Bk = V[keep], N[keep], C[keep], B[keep]
        zc = zc[keep]
        xs = (rel[keep] @ r) / zc * focal; ys = (rel[keep] @ u) / zc * focal
        if frame is None:
            x0, x1 = xs.min() - margin * kp, xs.max() + margin * kp
            y0, y1 = ys.min() - margin * kp, ys.max() + margin * kp
        else:
            (x0, x1), (y0, y1) = frame
        W = int(x1 - x0); H = int(y1 - y0)
        S = np.stack([xs - x0, y1 - ys], -1)
        zb, ib = raster(S, -1.0 / zc, W, H, np.arange(len(Vk)))
        hit = ib >= 0
        depth = np.where(hit, -1.0 / np.where(hit, zb, -1.0), 0)
        gx = ((np.arange(W) + 0.5) + x0) / focal
        gy = (y1 - (np.arange(H) + 0.5)) / focal
        ray = f[None, None, :] + gx[None, :, None] * r + gy[:, None, None] * u
        P = Cam + depth[..., None] * ray
        view = -ray / np.linalg.norm(ray, axis=-1, keepdims=True)
        zb = np.where(hit, depth, np.inf).astype(np.float32)
    tid = np.where(hit, ib, 0)
    n = Nk[tid]                                   # (H,W,3)
    col = Ck[tid]
    blk = np.where(hit, Bk[tid], -1)

    L = np.array(light, float); L /= np.linalg.norm(L)
    # ---- 그림자 맵
    dl, fl, rl, ul = L, -L, None, None
    rl = np.cross(fl, [0, 0, 1.0]); rl /= np.linalg.norm(rl); ul = np.cross(rl, fl)
    keepL = (N @ L) > 1e-4
    VL = V[keepL]
    lx = VL @ rl; ly = VL @ ul; ld = VL @ fl
    ks = 2.2
    lx0, lx1, ly0, ly1 = lx.min() - 2, lx.max() + 2, ly.min() - 2, ly.max() + 2
    LW, LH = int((lx1 - lx0) * ks) + 1, int((ly1 - ly0) * ks) + 1
    zl, _ = raster(np.stack([(lx - lx0) * ks, (ly1 - ly) * ks], -1), ld, LW, LH)
    qx = ((P @ rl - lx0) * ks).astype(int); qy = ((ly1 - P @ ul) * ks).astype(int)
    ok = hit & (qx >= 0) & (qx < LW) & (qy >= 0) & (qy < LH)
    zq = np.full((H, W), np.inf, np.float32)
    zq[ok] = zl[qy[ok], qx[ok]]
    ndl = np.clip((n * L).sum(-1), 0, 1)
    shadow = np.where((P @ fl) <= zq + 1.2 + 2.0 * (1 - ndl), 1.0, 0.0).astype(np.float32)
    shadow = ndimage.uniform_filter(shadow, size=max(1, ss + 1))  # 가장자리 살짝 부드럽게

    # ---- SSAO (깊이 기반)
    occ = np.zeros((H, W), np.float32)
    cnt = 0
    zz = np.where(hit, zb, np.inf)
    for rad_c in (1.5, 4.0, 9.0):
        rp = max(1, int(round(rad_c * kp)))
        for k in range(10):
            a = 2 * np.pi * (k + 0.37 * (rad_c > 3)) / 10
            ox, oy = int(round(np.cos(a) * rp)), int(round(np.sin(a) * rp))
            nb = np.full_like(zz, np.inf)
            ys = slice(max(0, oy), H + min(0, oy)); yd = slice(max(0, -oy), H + min(0, -oy))
            xs = slice(max(0, ox), W + min(0, ox)); xd = slice(max(0, -ox), W + min(0, -ox))
            nb[yd, xd] = zz[ys, xs]
            with np.errstate(invalid="ignore"):
                diff = zz - nb                               # 이웃이 더 가까우면 +
            w = np.clip(diff / (rad_c * 1.2), 0, 1) * (diff < rad_c * 4)
            occ += np.where(np.isfinite(diff), w, 0)
            cnt += 1
    aof = 1 - ao * np.clip(occ / cnt * 1.6, 0, 1)
    aof = np.where(hit, aof, 1)

    pal = np.zeros((32, 3), np.float32)
    for k, c in palette.items():
        pal[int(k)] = _lin(c)
    base = pal[col]
    fill = np.array([0.7, -0.25, 0.15]); fill /= np.linalg.norm(fill)
    sky = 0.55 + 0.45 * n[..., 2]
    amb_ = amb * (0.16 + 0.16 * sky) * aof
    key = 1.05 * ndl * shadow * (0.65 + 0.35 * aof)
    fl_ = fill_amt * np.clip((n * fill).sum(-1), 0, 1) * aof
    hv = L[None, None, :] + view; hv = hv / np.linalg.norm(hv, axis=-1, keepdims=True)
    sp = spec * np.clip((n * hv).sum(-1), 0, 1) ** 36 * shadow
    rimv = np.array([0.2, 0.9, 0.5]); rimv /= np.linalg.norm(rimv)
    rm = rim * np.clip((n * rimv).sum(-1), 0, 1) ** 2 * (1 - np.clip((n * view).sum(-1), 0, 1)) ** 0.5
    shade = base * (amb_ + key + fl_)[..., None] + (sp[..., None] * 0.9) + (rm[..., None] * (0.35 + 0.65 * base))
    shade = shade * exposure
    em = np.isin(col, list(emissive)) & hit
    shade[em] = base[em] * 1.7

    # 배경: 남색 그라데이션 + 가장자리 어둡게
    bgl = _lin(bg)
    yy = np.linspace(1.15, 0.7, H)[:, None]
    xx = np.linspace(-1, 1, W)[None, :]
    vig = (1 - 0.25 * xx ** 2)
    img = np.where(hit[..., None], shade, (bgl[None, None, :] * (yy * vig)[..., None]))

    # 이음선(블록 경계) + 외곽선(깊이 차)
    if seams > 0:
        e = np.zeros((H, W), bool)
        e[:, 1:] |= (blk[:, 1:] != blk[:, :-1]) & hit[:, 1:] & hit[:, :-1]
        e[1:, :] |= (blk[1:, :] != blk[:-1, :]) & hit[1:, :] & hit[:-1, :]
        img[:, 1:][e[:, 1:]] *= (1 - seams)
        img[1:, :][e[1:, :] & ~e[:, :][1:, :]] *= (1 - seams)
    D = np.where(hit, zb, 1e6)
    o = np.zeros((H, W), bool)
    o[:, 1:] |= np.abs(D[:, 1:] - D[:, :-1]) > 6
    o[1:, :] |= np.abs(D[1:, :] - D[:-1, :]) > 6
    o &= True
    img[o] *= 0.35

    if bloom and em.any():
        emimg = np.zeros((H, W, 3), np.float32); emimg[em] = base[em]
        bl = np.zeros_like(emimg)
        for sig, wgt in ((kp * 0.7, 0.6), (kp * 2.2, 0.4), (kp * 6, 0.3)):
            bl += wgt * np.stack([ndimage.gaussian_filter(emimg[..., i], sig) for i in range(3)], -1)
        img = img + bloom * bl
    out = (_srgb(img) * 255 + 0.5).astype(np.uint8)
    im = Image.fromarray(out)
    if ss > 1:
        im = im.resize((W // ss, H // ss), Image.LANCZOS)
    return im


def sheet(images, labels=None, bg=(13, 15, 21), pad=14):
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
