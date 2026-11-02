"""APIS 머리 r6 (2026-11-02) — 크기 ×1.0 확정 + 외부 피드백 판정 1·2·3·5·6 반영 [결정 11-02 "1. 동의 2. 1.0"]

r5 와 다른 점: 모든 앞면 부품을 "기둥마다 가장 앞 칸(jf)" 기준으로 직접 쌓는다(emboss·방향별 덮어칠하기 대신 → 깊이가 일정).
1 바이저: 원본 휜 띠(양끝이 위로 올라감) 그대로 — 기둥마다 jf 에서 2칸 파고 그 뒤 칸 = Visor. (r5 는 양끝이 잘려 V자)
2 턱판: 마스크(2칸 돋움)와 따로, 한 평면(마스크 앞면보다 1칸 더)의 판 + 위·옆 짙은 틈.
3 흰 이마판: 1칸 돋운 판 + 통풍구 = 가로 홈 2줄. (윗면 흰 띠는 유저가 뺀 대로 없음)
5 노랑 관자놀이 판: 흰 판 양옆 1칸 돋움, 흰 판과 사이 1칸 짙은 틈(겹친 장갑).
6 귀 청록 가운데: 반지름 비 0.5 → 0.4.
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
import apis_head_r4 as h4  # noqa: E402

PAL, EMISSIVE = h4.PAL, h4.EMISSIVE
S_ = 1.0
TEMPLE_F = [(238, 160), (256, 160), (256, 199), (238, 197)]          # 흰 판 왼쪽(그림) 노랑 관자놀이 판
TEMPLE_F2 = [(298, 160), (316, 160), (316, 197), (298, 199)]


def build_head(M, s=S_):
    M.parts.pop("Head", None); M.parts.pop("Visor", None)
    img = Image.open(h3.SRC).convert("RGB"); Wd, Hd = img.size
    pm = lambda pts: h3.poly_mask((Wd, Hd), pts)
    fm, sm = pm(h3.FRONT), pm(h3.SIDE)
    R = {n: pm(p) for n, p in (("vis", h4.VISOR_F), ("mask", h4.MASK_F), ("white", h4.WHITE_F), ("vent", h4.VENT_F),
                                ("nose", h4.NOSE_S), ("masks", h4.MASK_S), ("chin", h4.CHIN_F),
                                ("tl", TEMPLE_F), ("tr", TEMPLE_F2))}
    k = 0.319 * s
    H = M.part("Head", (-26, -32, 212), (27, 24, 268 + int(12 * s)), pivot=(0, -2, r1.NECK_Z), parent="Torso")
    G = H.g(); shp = H.a.shape
    Xb, Yb, Zb = [np.broadcast_to(A, shp) for A in G]
    py = np.clip(np.round(h3.Y0 - (Zb - h3.ZB) / k).astype(int), 0, Hd - 1)
    pxf = np.clip(np.round(h3.FX0 + Xb / k).astype(int), 0, Wd - 1)
    pxs = np.clip(np.round(h3.SX0 + (Yb + 20) / k).astype(int), 0, Wd - 1)
    F2 = lambda n: R[n][py[:, 0, :], pxf[:, 0, :]]                               # (x, z) 기둥
    S = lambda n: R[n][py, pxs]
    hull = fm[py, pxf] & sm[py, pxs]
    hull |= np.broadcast_to(F2("mask")[:, None, :], shp) & (S("masks") | sm[py, pxs]) & fm[py, pxf]
    hull |= np.broadcast_to(F2("mask")[:, None, :], shp) & fm[py, pxf] & (Yb >= -18) & (Yb <= -8)   # 마스크 아랫부분: 옆 윤곽보다 아래로(정면 그림대로 턱 끝까지), 앞쪽 10칸 두께
    H.a[hull] = 1
    filled = H.a > 0
    has = filled.any(1)
    jf = np.where(has, filled.argmax(1), -1)                                       # 기둥마다 가장 앞 칸
    nx, ny, nz = shp
    # ---- 겉색(옆·윗·아래): 옆 = 코끝 흰 · 마스크 회청 · 나머지 노랑
    P = np.pad(filled, 1)
    side = (~P[2:, 1:-1, 1:-1] | ~P[:-2, 1:-1, 1:-1]) & filled
    bot = ~P[1:-1, 1:-1, :-2] & filled
    surf = side | bot | ~P[1:-1, 1:-1, 2:] & filled | ~P[1:-1, 2:, 1:-1] & filled | ~P[1:-1, :-2, 1:-1] & filled
    H.a[filled & ~surf] = 3
    H.a[side & (S("masks") | (np.broadcast_to(F2("mask")[:, None, :], shp) & (Yb <= -8)))] = 8   # 마스크 옆면도 회청
    H.a[side & S("nose")] = 2
    H.a[bot & ~side] = 3

    def col(i, kz, j, c):
        if 0 <= j < ny:
            H.a[i, j, kz] = c
    vis2, white2, vent2, mask2, chin2 = F2("vis"), F2("white"), F2("vent"), F2("mask"), F2("chin")
    temple2 = (F2("tl") | F2("tr")) & ~white2 & ~vis2
    seam2 = ndimage.binary_dilation(white2, structure=np.ones((3, 1))) & ~white2 & temple2   # 흰 판 옆 1칸 틈
    temple2 &= ~seam2
    # 앞면 바탕색(돋움 없는 칸)
    for i, kz in np.argwhere(has):
        j = jf[i, kz]
        H.a[i, j, kz] = 8 if mask2[i, kz] else (3 if seam2[i, kz] else 1)
    # 1 바이저: 기둥마다 2칸 파고 그 뒤 칸 = 바이저 화면
    visor_cells = []
    vv = vis2 & has
    for i, kz in np.argwhere(vv):
        j = jf[i, kz]
        H.a[i, j:j + 2, kz] = 0
        nb = [jf[a, b] for a, b in ((i - 1, kz), (i + 1, kz), (i, kz - 1), (i, kz + 1))
              if 0 <= a < nx and 0 <= b < nz and vv[a, b]]
        j1 = max([j] + nb)                                                         # 이웃 기둥과 깊이가 겹치게(면으로 이어짐)
        for jj in range(j + 2, j1 + 3):
            visor_cells.append((i, jj, kz))
    # 3 흰 이마판 1칸 돋움 + 통풍구 가로 홈 2줄
    vent_rows = sorted(set(np.argwhere(vent2)[:, 1].tolist()))
    groove_rows = set(vent_rows[1::2][:2]) if len(vent_rows) >= 3 else set(vent_rows[:1])
    for i, kz in np.argwhere(white2 & has & ~vis2):
        j = jf[i, kz]
        H.a[i, j, kz] = 2
        if vent2[i, kz] and kz in groove_rows:
            H.a[i, j, kz] = 4                                                      # 홈(돋움 없음)
        else:
            col(i, kz, j - 1, 2)
    # 5 노랑 관자놀이 판 1칸 돋움
    for i, kz in np.argwhere(temple2 & has):
        col(i, kz, jf[i, kz] - 1, 1)
    # 마스크 2칸 돋움(턱판 자리 빼고)
    for i, kz in np.argwhere(mask2 & has & ~chin2 & ~vis2):
        j = jf[i, kz]
        col(i, kz, j - 1, 8); col(i, kz, j - 2, 8)
    # 2 턱판: 한 평면(마스크 앞면보다 1칸 더 앞) + 위·옆 짙은 틈
    cc = np.argwhere(chin2 & has)
    if len(cc):
        jc = min(jf[i, kz] for i, kz in cc) - 3
        top = max(kz for _, kz in cc)
        xs = [i for i, _ in cc]
        for i, kz in cc:
            j = jf[i, kz]
            edge = kz == top or i in (min(xs), max(xs))
            for jj in range(max(jc, 0), j):
                H.a[i, jj, kz] = 8
            if edge:
                H.a[i, max(jc, 0), kz] = 4
    # 목
    H.add(fv.cyl(G, "z", (0, 2), 9 * s, rng=(212, h3.ZB + 2)), 3)
    # 6 귀 원반(가운데 청록 0.4)
    ey = (h3.EAR[0] - h3.SX0) * k - 20; ez = h3.ZB + (h3.Y0 - h3.EAR[1]) * k; er = h3.EAR[2] * k
    xs_ = np.argwhere((H.a > 0).any((1, 2)))[:, 0] + H.lo[0]
    xm = max(abs(xs_.min()), abs(xs_.max()))
    for sg in (1, -1):
        H.add(fv.cyl(G, "x", (ey, ez), er, rng=(sg * (xm - 3), sg * (xm + 2))), 3)
        H.groove(fv.cyl(G, "x", (ey, ez), er * 0.4, rng=(sg * (xm + 1), sg * (xm + 3))), 6)
    # 바이저 파트
    V = M.part("Visor", tuple(H.lo), tuple(H.hi), pivot=(0, -18, h3.ZB + 14 * s), parent="Head")
    for i, j, kz in visor_cells:
        if j < ny:
            V.a[i, j, kz] = 6; H.a[i, j, kz] = 0
    for i, j, kz in visor_cells:                                                   # 화면 바로 뒤는 짙은 벽
        if j + 1 < ny and H.a[i, j + 1, kz] == 0 and V.a[i, j + 1, kz] == 0:
            H.a[i, j + 1, kz] = 3
    H.trim(); V.trim()
    return H, V


def build_all(s=S_):
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
    import apis_head_r4 as old
    for lab0, M in (("r5", old.build_all(1.0)), ("r6", build_all())):
        for n in ("Head", "Visor"):
            p = M.parts[n]; _, kk = ndimage.label(p.a > 0)
            print(lab0, n, "tris", 2 * greedy_quads(p.a), "섬", kk - 1)
        V = M.parts["Visor"]
        print(lab0, "visor rows", [(int(V.lo[2] + z), int((V.a[:, :, z] > 0).any(1).sum())) for z in range(V.a.shape[2])][::-1])
        B = M.blocks(skip=[n for n in M.parts if n not in ("Head", "Visor")])
        ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=9, ss=2, ao_amt=0.5) for y, p in ((0, 3), (-90, 2), (-35, 10))]
        ims.append(vp.render(M.blocks(), PAL, EMISSIVE, yaw=-30, pitch=8, ppc=4, ss=2, ao_amt=0.5))
        rows.append((lab0, ims))
    Hm = max(i.height for _, ims in rows for i in ims)
    refs = [img.crop((222, 130, 332, 250)), img.crop((598, 125, 728, 250))]
    refs = [r.resize((int(r.width * Hm / r.height), Hm)) for r in refs]
    Wt = max(sum(r.width + 16 for r in refs) + sum(i.width + 16 for i in ims) for _, ims in rows)
    sh = Image.new("RGB", (Wt, 2 * (Hm + 40)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for ri, (lab0, ims) in enumerate(rows):
        y0 = ri * (Hm + 40); x = 0
        for r, lab in zip(refs, ("원본 정면", "원본 옆")):
            sh.paste(r, (x, y0)); d.text((x + 6, y0 + Hm + 6), lab, fill=(200, 200, 200), font=f); x += r.width + 16
        for im, lab in zip(ims, ("정면", "옆", "앞 3/4", "가슴과 함께")):
            sh.paste(im, (x, y0 + Hm - im.height)); d.text((x + 6, y0 + Hm + 6), "%s · %s" % (lab0, lab), fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "apis_head_r6.png")); print(sh.size)
