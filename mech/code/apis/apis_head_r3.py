"""APIS 머리 r3 — 윤곽 그대로 깎기(정면 윤곽 ∩ 옆 윤곽) + 그림 색 옮겨 칠하기 (2026-11-02)

유저: "머리 읽기와 실제 사출이 달라서 당황스러워 … 주둥이는 오리 입, 흰 판은 왜 이렇게 많아" → 수식으로 모양을 다시 짜지 않고
1순위 삼면도의 정면·옆 머리 윤곽(원본 픽셀 다각형)을 그대로 써서 두 윤곽이 겹치는 칸만 남긴다(visual hull).
색 = 칸의 겉면 방향에 따라 정면 그림(앞면) / 옆 그림(옆·윗면)에서 같은 자리 픽셀을 읽어 팔레트로 분류(노랑·흰·짙은·청록).
청록 앞면 칸 = 바이저(따로 파트 Visor, 게임에서 표정을 그림 [결정]). 귀 원반 = 옆 그림 위치에 원통(가운데 청록 발광 [결정]).
배율 s: 1.0 = 그림 비율 그대로 · 1.3 = 머리를 키움(절반 해상도에서 디테일 유지 + 지원기 귀여움) [제안].
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import apis_r1 as r1  # noqa: E402

PAL, EMISSIVE = r1.PAL, r1.EMISSIVE
SRC = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "지원기", "concept_v1_삼면도.webp")
# 원본 픽셀 윤곽 [실측: 6배 확대 격자 hf_grid · hs_grid]
FRONT = [(243, 153), (258, 148), (300, 148), (312, 153), (316, 165), (318, 195), (312, 205), (304, 222), (300, 246),
         (254, 246), (250, 222), (242, 205), (236, 195), (237, 165)]
SIDE = [(612, 182), (622, 170), (640, 160), (666, 143), (690, 139), (712, 140), (716, 175), (712, 205), (700, 225),
        (662, 234), (634, 232), (628, 222), (630, 210), (626, 200), (618, 196), (612, 190)]
FX0, SX0, Y0 = 277, 614, 240        # 정면 가운데 x · 옆 코끝 x · 턱 밑 y
EAR = (684, 179, 16)                # 옆 그림 귀 원반 중심 x, y, 반지름(px)
ZB = 223


def poly_mask(size, pts):
    m = Image.new("L", size, 0); ImageDraw.Draw(m).polygon(pts, fill=1)
    return np.asarray(m, bool)


def classify(img):
    a = np.asarray(img).astype(int); r, g, b = a[..., 0], a[..., 1], a[..., 2]
    cls = np.full(r.shape, 3, np.uint8)                                          # 짙은
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    cls[(mn > 165) & (mx - mn < 45)] = 2                                          # 흰(밝고 무채색)
    cls[(r > 150) & (g > 110) & (r - b > 60)] = 1                                 # 노랑
    cls[((g > 150) & (b > 150) & (g - r > 60)) | ((g > 230) & (b > 230) & (g - r > 25))] = 6   # 청록(발광·하이라이트) — 회청색 주둥이는 제외
    out = cls.copy(); best = np.zeros(cls.shape, float)                           # 5×5 다수결
    for c in (1, 2, 3, 6):
        n = ndimage.uniform_filter((cls == c).astype(float), 5)
        upd = n > best; out[upd] = c; best[upd] = n[upd]
    return out


def build_head(M, s=1.0):
    M.parts.pop("Head", None); M.parts.pop("Visor", None)
    img = Image.open(SRC).convert("RGB")
    W, Hh = img.size
    fm = poly_mask((W, Hh), FRONT); sm = poly_mask((W, Hh), SIDE)
    cls = classify(img)
    k = 0.319 * s
    H = M.part("Head", (-24, -26, 214), (25, 22, 268 + int(12 * s)), pivot=(0, -2, r1.NECK_Z), parent="Torso")
    G = H.g(); X, Y, Z = G
    shp = H.a.shape
    Xb, Yb, Zb = [np.broadcast_to(A, shp) for A in G]
    py = np.round(Y0 - (Zb - ZB) / k).astype(int)
    pxf = np.round(FX0 + Xb / k).astype(int)
    pxs = np.round(SX0 + (Yb + 20) / k).astype(int)
    ok = (py >= 0) & (py < Hh) & (pxf >= 0) & (pxf < W) & (pxs >= 0) & (pxs < W)
    py_, pxf_, pxs_ = np.clip(py, 0, Hh - 1), np.clip(pxf, 0, W - 1), np.clip(pxs, 0, W - 1)
    hull = ok & fm[py_, pxf_] & sm[py_, pxs_]
    H.a[hull] = 1
    # 겉면 방향별 색
    filled = H.a > 0
    P = np.pad(filled, 1)
    front_open = ~P[1:-1, :-2, 1:-1] & filled          # −Y 이웃 빔
    side_open = (~P[2:, 1:-1, 1:-1] | ~P[:-2, 1:-1, 1:-1]) & filled
    top_open = ~P[1:-1, 1:-1, 2:] & filled
    back_open = ~P[1:-1, 2:, 1:-1] & filled
    col = np.full(shp, 1, np.uint8)
    cf = cls[py_, pxf_]; cs = cls[py_, pxs_]
    col[side_open | top_open] = cs[side_open | top_open]
    col[front_open] = cf[front_open]
    col[back_open & ~front_open & ~side_open] = 1
    col[(col == 6) & ~front_open & side_open] = np.where(cf[(col == 6) & ~front_open & side_open] == 6, 6, 3)
    H.a[filled] = col[filled]
    # 속 칸은 겉 칸 색을 따름(겉이 깎여 드러나도 자연스럽게) — 짙은 심
    inner = filled & ~(front_open | side_open | top_open | back_open | (~P[1:-1, 1:-1, :-2] & filled))
    H.a[inner] = 3
    H.add(fv.cyl(G, "z", (0, 2), 9 * s, rng=(214, ZB + 2)), 3)                    # 목
    # 귀 원반: 옆 그림 위치 → 머리 겉 바깥에 짙은 고리 + 가운데 청록 발광
    ey = (EAR[0] - SX0) * k - 20; ez = ZB + (Y0 - EAR[1]) * k; er = EAR[2] * k
    xs = np.argwhere(filled.any((1, 2)))[:, 0] + H.lo[0]
    xm = max(abs(xs.min()), abs(xs.max()))
    for sg in (1, -1):
        H.add(fv.cyl(G, "x", (ey, ez), er, rng=(sg * (xm - 3), sg * (xm + 2))), 3)
        H.groove(fv.cyl(G, "x", (ey, ez), er * 0.5, rng=(sg * (xm + 1), sg * (xm + 3))), 6)
    # 바이저 = 앞면 청록 칸(+ 바로 뒤 1칸) → 따로 파트
    vis = (H.a == 6) & front_open
    vis |= np.roll(vis, 1, axis=1) & (H.a == 6)
    V = M.part("Visor", tuple(H.lo), tuple(H.hi), pivot=(0, -20, ZB + 14 * s), parent="Head")
    V.a[vis] = 6; H.a[vis] = 0
    H.a[np.roll(vis, 1, axis=1) & (H.a == 0) & filled] = 3
    H.trim(); V.trim()
    return H, V


def build_all(s=1.0):
    M = r1.build_all()
    build_head(M, s)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import ImageFont
    import vox_preview as vp
    from check_model import greedy_quads
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    img = Image.open(SRC).convert("RGB")
    rows = []
    for s in (1.0, 1.3):
        M = build_all(s)
        for n in ("Head", "Visor"):
            p = M.parts[n]; _, kk = ndimage.label(p.a > 0)
            print(s, n, "tris", 2 * greedy_quads(p.a), "섬", kk - 1)
        B = M.blocks(skip=[n for n in M.parts if n not in ("Head", "Visor")])
        ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=9 / s, ss=2, ao_amt=0.5) for y, p in ((0, 3), (-90, 2), (-35, 10))]
        Bt = M.blocks()
        ims.append(vp.render(Bt, PAL, EMISSIVE, yaw=-30, pitch=8, ppc=4, ss=2, ao_amt=0.5))
        rows.append((s, ims))
    Hm = max(i.height for _, ims in rows for i in ims)
    refs = [img.crop((222, 130, 332, 250)), img.crop((598, 125, 728, 250))]
    refs = [r.resize((int(r.width * Hm / r.height), Hm)) for r in refs]
    Wt = max(sum(r.width + 16 for r in refs) + sum(i.width + 16 for i in ims) for _, ims in rows)
    sh = Image.new("RGB", (Wt, 2 * (Hm + 40)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for ri, (s, ims) in enumerate(rows):
        y0 = ri * (Hm + 40); x = 0
        for r, lab in zip(refs, ("원본 정면", "원본 옆")):
            sh.paste(r, (x, y0)); d.text((x + 6, y0 + Hm + 6), lab, fill=(200, 200, 200), font=f); x += r.width + 16
        for im, lab in zip(ims, ("정면", "옆", "앞 3/4", "가슴과 함께")):
            sh.paste(im, (x, y0 + Hm - im.height)); d.text((x + 6, y0 + Hm + 6), "×%.1f · %s" % (s, lab), fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "apis_head_r3.png")); print(sh.size)
