"""APIS 머리 r4 = r3(윤곽 교집합 모양) + 바이저·마스크 다시 + 색 정리 (2026-11-02)

유저 r3 평: "머리 모양 자체는 이전보다 그럴듯해. 근데 색이 얼룩덜룩하고, 바이저와 마스크는 거의 없는 수준.
귀 밑에서부터 이어지는 마스크와 바이저를 다시 그려봐" + 원본 정면에 직접 그린 표시(초록 = 바이저 넓은 띠, 파랑 = 귀 밑에서 턱을 감싸는 U 마스크).
→ 색을 픽셀마다 읽지 않고, 원본 그림 위 영역 다각형(유저 표시를 원본 픽셀로 옮김)으로 칠한다:
   정면: 바이저(청록, 1~2칸 파고 안쪽 = Visor 파트) · 마스크(회청색 새 색 8, 2칸 돋움 + 옆으로 감김) · 가운데 흰 판 · 통풍구 · 나머지 노랑.
   옆: 코끝 흰 · 바이저 끝 · 마스크(귀 밑 → 턱) · 나머지 노랑. 윗면: 앞쪽 가운데 흰 줄, 나머지 노랑.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import apis_r1 as r1  # noqa: E402
import apis_head_r3 as h3  # noqa: E402

PAL = dict(r1.PAL); PAL[8] = (92, 122, 130)          # 8 = 마스크 회청색(원본 주둥이 (87,136,144) 근처)
EMISSIVE = r1.EMISSIVE
# 원본 픽셀 영역 [유저 표시를 원본 좌표로 옮김: 정면 패널 3.14배 · 원점 (222,130)]
VISOR_F = [(245, 197), (262, 201), (277, 204), (292, 201), (309, 197), (308, 207), (296, 216), (277, 221), (258, 216), (246, 207)]   # 띠 두께 ≈ 원본 발광 띠(가운데 17px → 끝 10px)
MASK_F = [(232, 206), (246, 213), (258, 222), (277, 226), (296, 222), (308, 213), (320, 205), (318, 222), (306, 240), (292, 249),
          (262, 249), (248, 240), (236, 224)]
WHITE_F = [(256, 163), (298, 163), (305, 176), (301, 197), (277, 200), (253, 197), (249, 176)]
VENT_F = [(271, 184), (285, 184), (285, 190), (271, 190)]
NOSE_S = [(610, 176), (622, 168), (640, 158), (664, 146), (668, 152), (645, 166), (632, 178), (630, 196), (612, 194)]
VISOR_S = [(616, 184), (632, 182), (652, 186), (656, 200), (646, 210), (626, 208), (618, 198)]
MASK_S = [(620, 200), (640, 208), (662, 200), (690, 196), (704, 206), (700, 224), (668, 236), (632, 234), (624, 222)]


def build_head(M, s=1.3):
    M.parts.pop("Head", None); M.parts.pop("Visor", None)
    img = Image.open(h3.SRC).convert("RGB"); Wd, Hd = img.size
    pm = lambda pts: h3.poly_mask((Wd, Hd), pts)
    fm, sm = pm(h3.FRONT), pm(h3.SIDE)
    R = {n: pm(p) for n, p in (("vis", VISOR_F), ("mask", MASK_F), ("white", WHITE_F), ("vent", VENT_F),
                                ("nose", NOSE_S), ("viss", VISOR_S), ("masks", MASK_S))}
    k = 0.319 * s
    H = M.part("Head", (-26, -30, 212), (27, 24, 268 + int(12 * s)), pivot=(0, -2, r1.NECK_Z), parent="Torso")
    G = H.g(); shp = H.a.shape
    Xb, Yb, Zb = [np.broadcast_to(A, shp) for A in G]
    py = np.clip(np.round(h3.Y0 - (Zb - h3.ZB) / k).astype(int), 0, Hd - 1)
    pxf = np.clip(np.round(h3.FX0 + Xb / k).astype(int), 0, Wd - 1)
    pxs = np.clip(np.round(h3.SX0 + (Yb + 20) / k).astype(int), 0, Wd - 1)
    F = lambda n: R[n][py, pxf]                                                   # 정면 영역(앞뒤로 기둥)
    S = lambda n: R[n][py, pxs]                                                   # 옆 영역(좌우로 기둥)
    hull = fm[py, pxf] & sm[py, pxs]
    # 마스크가 옆 윤곽 밑으로 잘리지 않게: 마스크 기둥은 옆 윤곽 대신 마스크 옆 영역으로 허용
    hull |= F("mask") & (S("masks") | sm[py, pxs]) & fm[py, pxf]
    H.a[hull] = 1

    def faces():
        P = np.pad(H.a > 0, 1); f = H.a > 0
        return dict(front=~P[1:-1, :-2, 1:-1] & f, side=(~P[2:, 1:-1, 1:-1] | ~P[:-2, 1:-1, 1:-1]) & f,
                    top=~P[1:-1, 1:-1, 2:] & f, bot=~P[1:-1, 1:-1, :-2] & f, back=~P[1:-1, 2:, 1:-1] & f)
    # 마스크 2칸 돋움(정면 영역 기둥 안 빈칸 → 앞·옆·아래로 감쌈)
    H.emboss(F("mask") & ~F("vis"), 8, h=2)
    # 바이저: 정면 바이저 영역 앞면을 2칸 파냄
    for _ in range(2):
        fc = faces()
        H.a[fc["front"] & F("vis")] = 0
    fc = faces()
    # 색: 속 = 짙은, 겉 = 방향별 영역
    filled = H.a > 0
    col = np.full(shp, 1, np.uint8)
    side_c = np.where(S("nose"), 2, np.where(S("viss"), 6, np.where(S("masks"), 8, 1)))
    front_c = np.where(F("vis"), 6, np.where(F("mask"), 8, np.where(F("vent"), 3, np.where(F("white"), 2, 1))))
    top_c = np.where((np.abs(Xb) <= 12 * s * 0.319 / 0.319 * 0.32 * 3.1) & S("nose") | (np.abs(Xb) <= 4 * s) & (pxs < 650), 2, 1)
    col = np.where(fc["side"], side_c, col)
    col = np.where(fc["top"], top_c, col)
    col = np.where(fc["front"], front_c, col)
    col = np.where(fc["bot"] & ~fc["front"], 3, col)
    col = np.where(H.a == 8, 8, col)                                              # 돋운 마스크 칸은 그대로
    surf = fc["front"] | fc["side"] | fc["top"] | fc["bot"] | fc["back"]
    H.a[filled] = np.where(surf, col, 3)[filled]
    # 바이저 안쪽 면 = Visor 파트(청록 앞면 칸)
    vis = fc["front"] & F("vis") & filled
    # 작은 얼룩 정리: 겉면에서 같은 색 이웃이 1칸 이하인 노랑/흰 칸 → 이웃 다수
    for _ in range(2):
        a = H.a
        for c in (1, 2):
            m = (a == c) & surf
            nb = ndimage.convolve((a == c).astype(int), np.ones((3, 3, 3)), mode="constant") - 1
            other = np.where(c == 1, 2, 1)
            a[m & (nb <= 1) & (ndimage.convolve((a == other).astype(int), np.ones((3, 3, 3)), mode="constant") >= 3)] = other
    H.add(fv.cyl(G, "z", (0, 2), 9 * s, rng=(212, h3.ZB + 2)), 3)                 # 목
    # 귀 원반(가운데 청록 발광)
    ey = (h3.EAR[0] - h3.SX0) * k - 20; ez = h3.ZB + (h3.Y0 - h3.EAR[1]) * k; er = h3.EAR[2] * k
    xs = np.argwhere((H.a > 0).any((1, 2)))[:, 0] + H.lo[0]
    xm = max(abs(xs.min()), abs(xs.max()))
    for sg in (1, -1):
        H.add(fv.cyl(G, "x", (ey, ez), er, rng=(sg * (xm - 3), sg * (xm + 2))), 3)
        H.groove(fv.cyl(G, "x", (ey, ez), er * 0.5, rng=(sg * (xm + 1), sg * (xm + 3))), 6)
    V = M.part("Visor", tuple(H.lo), tuple(H.hi), pivot=(0, -20, h3.ZB + 14 * s), parent="Head")
    V.a[vis] = 6; H.a[vis] = 0
    lab, kk = ndimage.label(V.a > 0)                                              # 바이저 본체만 남기고 자투리는 머리로(발광 그대로)
    if kk > 1:
        main = np.argmax(np.bincount(lab.ravel())[1:]) + 1
        stray = (lab > 0) & (lab != main)
        H.a[stray] = 6; V.a[stray] = 0; vis = vis & ~stray
    behind = np.roll(vis, 1, axis=1)
    H.a[behind & (H.a == 0)] = 3
    H.trim(); V.trim()
    return H, V


def build_all(s=1.3):
    M = r1.build_all()
    build_head(M, s)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import ImageDraw, ImageFont
    import vox_preview as vp
    from check_model import greedy_quads
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    img = Image.open(h3.SRC).convert("RGB")
    rows = []
    for s in (1.3, 1.0):
        M = build_all(s)
        for n in ("Head", "Visor"):
            p = M.parts[n]; _, kk = ndimage.label(p.a > 0)
            print(s, n, "tris", 2 * greedy_quads(p.a), "섬", kk - 1)
        B = M.blocks(skip=[n for n in M.parts if n not in ("Head", "Visor")])
        ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=9 / s, ss=2, ao_amt=0.5) for y, p in ((0, 3), (-90, 2), (-35, 10))]
        ims.append(vp.render(M.blocks(), PAL, EMISSIVE, yaw=-30, pitch=8, ppc=4, ss=2, ao_amt=0.5))
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
    sh.save(os.path.join(out, "apis_head_r4.png")); print(sh.size)
