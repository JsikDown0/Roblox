"""view.py — 면 중심 스플랫 렌더(빠른 확인용). Blender 좌표, az0 = 정면(−Y 쪽에서 봄), az90 = +X 쪽에서 봄, az180 = 뒤."""
import numpy as np
from PIL import Image, ImageDraw

def vm(az, el):
    a, e = np.radians(az), np.radians(el)
    d = np.array([-np.sin(a) * np.cos(e), np.cos(a) * np.cos(e), -np.sin(e)])
    r = np.cross(d, [0, 0, 1.0]); r /= np.linalg.norm(r); u = np.cross(r, d)
    return np.stack([r, u, -d])

def render(C, N, col, az=0, el=0, W=500, H=640, cz=0.95, span=2.0, cx=0.0, light=(0.4, -0.6, 0.7), bg=(20, 20, 24), sp=2):
    R = vm(az, el); P = C @ R.T; n = N @ R.T
    s = H / span
    c0 = np.array([cx, 0, cz]) @ R.T
    px = ((P[:, 0] - c0[0]) * s + W / 2).astype(int); py = (H / 2 - (P[:, 1] - c0[1]) * s).astype(int)
    L = np.asarray(light, float); L /= np.linalg.norm(L)
    sh = 0.35 + 0.65 * np.clip(np.abs(N @ L), 0, 1)
    sh = np.where(n[:, 2] < 0, sh * 0.55, sh)
    c = np.clip(col * sh[:, None], 0, 255).astype(np.uint8)
    img = np.zeros((H, W, 3), np.uint8); img[:] = bg
    zb = np.full((H, W), -1e9)
    o = np.argsort(P[:, 2])
    for dy in range(sp):
        for dx in range(sp):
            x = px[o] + dx; y = py[o] + dy; ok = (x >= 0) & (x < W) & (y >= 0) & (y < H)
            xi, yi, zi, ci = x[ok], y[ok], P[o, 2][ok], c[o][ok]
            # 마지막 쓰기가 이김 → 깊이 오름차순이라 가장 가까운 게 남음, 단 이미 더 가까운 게 있으면 유지
            zz = zb[yi, xi]; m = zi >= zz
            img[yi[m], xi[m]] = ci[m]; zb[yi[m], xi[m]] = zi[m]
    return Image.fromarray(img)

def sheet(C, N, col, views, labels=None, **kw):
    ims = [render(C, N, col, a, e, **kw) for a, e in views]
    W, H = ims[0].size; out = Image.new("RGB", (W * len(ims), H))
    for i, im in enumerate(ims):
        ImageDraw.Draw(im).text((5, 4), labels[i] if labels else "az%d el%d" % views[i], fill=(255, 255, 0)); out.paste(im, (i * W, 0))
    return out

BARY = np.array([[1/3,1/3,1/3],[.7,.15,.15],[.15,.7,.15],[.15,.15,.7],[.45,.45,.1],[.1,.45,.45],[.45,.1,.45],[.9,.05,.05],[.05,.9,.05],[.05,.05,.9]])

def dense(V, F, N, col):
    """면마다 10점 샘플 → 스플랫 구멍 제거용"""
    T = V[F]; P = np.einsum("kj,njd->nkd", BARY, T).reshape(-1, 3)
    return P, np.repeat(N, len(BARY), 0), np.repeat(col, len(BARY), 0)

def face_geo(V, F):
    C = V[F].mean(1); n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    A = np.linalg.norm(n, axis=1); return C, n / (A[:, None] + 1e-15), A / 2
