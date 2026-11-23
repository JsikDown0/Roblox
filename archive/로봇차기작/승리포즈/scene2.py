"""scene2.py — v2 한 장면(칼자루 점화 단계, 등 노즐 불꽃, 발광 세기, 불똥, 눈 번쩍)"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import timeline2 as TL, vpose as V, vox_preview as vp, scene as S1

_M = {}
def model(lit, flame):
    k = (round(lit * 4) / 4, round(flame * 3) / 3)
    if k not in _M:
        _M[k] = V.model(saber=k[0], rifle=False, stowed=True, flames=k[1], legflames=False)
    return _M[k]

EMIT_L = np.array([40, -21, 125.0])     # 칼자루 노즐 끝(칼 로컬)

def frame(t, yaw, pitch, size, ppc=1.6, fx=True):
    P, lit, spark, eye, flame, glow = TL.state(t)
    M = model(lit, flame)
    save = dict(V.PAL); b6 = np.array(V.PAL[6], float)
    V.PAL[6] = tuple((b6 * (0.25 + 0.75 * glow)).astype(int))
    try:
        B, cache = V.blocks(M, P)
        im = vp.render(B, V.PAL, V.EMIT if glow > 0.5 else (V.EMIT - {6}), yaw=yaw, pitch=pitch, ppc=ppc, ss=2, size=size, ao_amt=0.5)
    finally:
        V.PAL.clear(); V.PAL.update(save)
    if fx:
        if eye > 0.02:
            T = cache["Head"]; pt = T[:3, :3] @ S1.EYE_LOCAL + T[:3, 3]
            im = S1.add_flare(im, *V.project(pt, yaw, pitch, size, ppc), eye, ppc)
        if spark >= 0 and spark > 0:
            T = cache["Saber"]; pt = T[:3, :3] @ EMIT_L + T[:3, 3]
            im = add_sparks(im, *V.project(pt, yaw, pitch, size, ppc), spark, ppc)
    return im, P

def add_sparks(im, x, y, k, ppc, n=18, seed=3):
    rng = np.random.default_rng(seed)
    L = Image.new("RGB", im.size, (0, 0, 0)); d = ImageDraw.Draw(L)
    fade = 1.0 - k
    for i in range(n):
        a = rng.uniform(0, 2 * np.pi); sp = rng.uniform(25, 70) * ppc
        r0 = sp * k * 0.7; r1 = sp * k
        g = 9 * ppc * k * k                                   # 살짝 떨어짐
        p0 = (x + np.cos(a) * r0, y - np.sin(a) * r0 + g * 0.6); p1 = (x + np.cos(a) * r1, y - np.sin(a) * r1 + g)
        c = (int(255 * fade + 60), int(170 * fade + 30), int(60 * fade))
        d.line([p0, p1], fill=c, width=max(1, int(ppc * 1.2)))
    d.ellipse((x - 5 * ppc, y - 5 * ppc, x + 5 * ppc, y + 5 * ppc), fill=(int(255 * (1 - k)), int(220 * (1 - k)), int(140 * (1 - k))))
    G = L.filter(ImageFilter.GaussianBlur(1.5 * ppc))
    a = np.asarray(im, np.float32) + np.asarray(L, np.float32) + np.asarray(G, np.float32) * 1.2
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
