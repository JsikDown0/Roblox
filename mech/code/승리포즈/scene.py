"""scene.py — 시각 t 의 한 장면 그리기(사벨 칼집/손·점화, 불꽃, 발광 세기, 눈 번쩍) (2026-10-29)"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import timeline as TL
import vpose as V
import vox_preview as vp

_M = {}
_B = []


def base():
    if not _B:
        _B.append(V.model(saber=1.0))
    return _B[0]


def model(saber, flame):
    """saber: None(칼집) | 0..1, flame: 0..1 — 단계로 묶어 캐시"""
    s = None if saber is None else round(saber * 4) / 4
    f = round(flame * 3) / 3
    k = (s, f)
    if k not in _M:
        _M[k] = V.model(saber=(-1 if s is None else s), flames=f)
    return _M[k]


def skip_for(saber):
    return ("Saber",) if saber is None else ("SaberHolsterL",)


EYE_LOCAL = np.array([0, -18, 251.0])          # 머리 로컬: 눈 줄(색 6) 가운데 바로 앞


def frame(t, yaw, pitch, size, ppc=1.6, glow=None, flare=True):
    P, saber, flame, eye = TL.state(t, base())
    M = model(saber, flame)
    lvl = glow if glow is not None else (0.18 if t < TL.EYE - 0.08 else 1.0)
    pal_save = dict(V.PAL)
    base6 = np.array(V.PAL[6], float)
    V.PAL[6] = tuple((base6 * (0.25 + 0.75 * lvl)).astype(int))
    try:
        B, cache = V.blocks(M, P, skip_for(saber))
        im = vp.render(B, V.PAL, V.EMIT if lvl > 0.5 else (V.EMIT - {6}), yaw=yaw, pitch=pitch, ppc=ppc, ss=2, size=size, ao_amt=0.5)
    finally:
        V.PAL.clear(); V.PAL.update(pal_save)
    if flare and eye > 0.02:
        T = cache["Head"]
        pt = T[:3, :3] @ EYE_LOCAL + T[:3, 3]
        x, y = V.project(pt, yaw, pitch, size, ppc)
        im = add_flare(im, x, y, eye, ppc)
    return im, P, saber, flame


def add_flare(im, x, y, k, ppc):
    """눈 번쩍: 가로 줄 + 작은 별 + 번짐(가산)."""
    W, H = im.size
    L = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(L)
    col = (255, 226, 120)
    w = 90 * ppc * k
    for i, (ww, hh, a) in enumerate(((w, 1.2 * ppc, 1.0), (w * 0.45, 2.4 * ppc, 0.8), (6 * ppc, 6 * ppc, 1.0))):
        c = tuple(int(v * a * min(1, k * 1.2)) for v in col)
        d.ellipse((x - ww, y - hh, x + ww, y + hh), fill=c)
    d.line((x, y - 18 * ppc * k, x, y + 18 * ppc * k), fill=tuple(int(v * 0.6 * k) for v in col), width=max(1, int(ppc)))
    G = L.filter(ImageFilter.GaussianBlur(3 * ppc))
    a = np.asarray(im, np.float32) + np.asarray(G, np.float32) * 1.4 + np.asarray(L, np.float32) * 0.6
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
