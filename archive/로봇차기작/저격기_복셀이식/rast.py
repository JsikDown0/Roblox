"""rast.py — numba 삼각형 래스터라이저(직교, z-버퍼, 면 단색 + 램버트). Blender 좌표, az0=정면(−Y에서)."""
import numpy as np, numba
from PIL import Image, ImageDraw
from view import vm

@numba.njit(cache=True)
def _raster(X, Y, Z, col, W, H, img, zb):
    for i in range(X.shape[0]):
        x0, x1, x2 = X[i, 0], X[i, 1], X[i, 2]; y0, y1, y2 = Y[i, 0], Y[i, 1], Y[i, 2]
        minx = max(int(np.floor(min(x0, min(x1, x2)))), 0); maxx = min(int(np.ceil(max(x0, max(x1, x2)))), W - 1)
        miny = max(int(np.floor(min(y0, min(y1, y2)))), 0); maxy = min(int(np.ceil(max(y0, max(y1, y2)))), H - 1)
        if minx > maxx or miny > maxy: continue
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-12: continue
        for py in range(miny, maxy + 1):
            for px in range(minx, maxx + 1):
                cx = px + 0.5; cy = py + 0.5
                w0 = ((y1 - y2) * (cx - x2) + (x2 - x1) * (cy - y2)) / den
                w1 = ((y2 - y0) * (cx - x2) + (x0 - x2) * (cy - y2)) / den
                w2 = 1.0 - w0 - w1
                if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6: continue
                z = w0 * Z[i, 0] + w1 * Z[i, 1] + w2 * Z[i, 2]
                if z > zb[py, px]:
                    zb[py, px] = z
                    img[py, px, 0] = col[i, 0]; img[py, px, 1] = col[i, 1]; img[py, px, 2] = col[i, 2]

def render(V, F, col, az=0, el=0, W=600, H=600, center=(0, 0, 0.95), span=2.0, light=(0.4, -0.6, 0.7), bg=(20, 20, 24)):
    R = vm(az, el); P = V @ R.T; c0 = np.asarray(center, float) @ R.T
    s = H / span
    X = ((P[:, 0] - c0[0]) * s + W / 2)[F]; Y = (H / 2 - (P[:, 1] - c0[1]) * s)[F]; Z = P[:, 2][F]
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]); n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-15
    L = np.asarray(light, float); L /= np.linalg.norm(L)
    sh = 0.35 + 0.65 * np.abs(n @ L)
    facing = (n @ R.T)[:, 2]
    sh = np.where(facing < 0, sh * 0.6, sh)
    c = np.clip(col * sh[:, None], 0, 255).astype(np.float64)
    img = np.zeros((H, W, 3)); img[:] = bg; zb = np.full((H, W), -1e18)
    _raster(X, Y, Z, c, W, H, img, zb)
    return Image.fromarray(img.astype(np.uint8))

def sheet(V, F, col, views, labels=None, **kw):
    ims = [render(V, F, col, a, e, **kw) for a, e in views]
    W, H = ims[0].size; out = Image.new("RGB", (W * len(ims), H))
    for i, im in enumerate(ims):
        ImageDraw.Draw(im).text((5, 4), labels[i] if labels else "az%d el%d" % tuple(views[i]), fill=(255, 255, 0)); out.paste(im, (i * W, 0))
    return out
