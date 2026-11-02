"""HT-02 CETUS — 절반 해상도 정리판 (2026-11-02, [결정] 전투용 = 절반 해상도, 원본도 따로 저장)

1. cetus_final.build_all() = 원래 해상도 원본(24 파트, 섬 0) → CETUS_full.json 저장.
2. 파트마다 2×2×2 칸 → 1칸(가장 많은 색, 발광·궁극기 줄·밧줄 3배 · 홈·뼈색 2배 가중 = 가는 줄이 끊기지 않게).
3. 튀는 점 정리: 겉면 칸 중 같은 색 이웃(26방향)이 1개 이하인 장식색 칸 → 이웃 다수 색. 2번 반복. (발광·궁극기 줄·홈은 손대지 않음)
4. 섬: 1~2칸 조각은 지우고, 큰 조각은 면으로 잇기.
5. 보관·내보내기용으로 다시 2배(원래 격자) → CETUS_half.json. 삼각형은 절반 격자에서 셈(2배 격자와 같은 수).
"""
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import cetus_final as cf  # noqa: E402
from check_model import greedy_quads  # noqa: E402

PAL, EMISSIVE, METAL, PAL_ULT, EMISSIVE_ULT = cf.PAL, cf.EMISSIVE, cf.METAL, cf.PAL_ULT, cf.EMISSIVE_ULT
WEIGHT = {6: 3, 8: 3, 10: 3, 9: 3, 4: 2, 2: 2}
KEEP = {4, 6, 8, 10}


def down2(a, lo):
    o = np.array(lo) % 2
    a = np.pad(a, [(o[i], 0) for i in range(3)])
    sh = [(s + 1) // 2 * 2 for s in a.shape]
    b = np.zeros(sh, np.uint8); b[:a.shape[0], :a.shape[1], :a.shape[2]] = a
    v = b.reshape(sh[0] // 2, 2, sh[1] // 2, 2, sh[2] // 2, 2).transpose(0, 2, 4, 1, 3, 5).reshape(sh[0] // 2, sh[1] // 2, sh[2] // 2, 8)
    out = np.zeros(v.shape[:3], np.uint8); best = np.zeros(v.shape[:3], int)
    for c in range(1, 11):
        cnt = (v == c).sum(-1) * WEIGHT.get(c, 1)
        upd = cnt > best; out[upd] = c; best[upd] = cnt[upd]
    out[(v > 0).sum(-1) < 4] = 0
    return out, (np.array(lo) - o) // 2


def despeckle(a, rounds=2):
    for _ in range(rounds):
        P = np.pad(a, 1)
        filled = P > 0
        surf = (a > 0) & ~ndimage.binary_erosion(filled, structure=np.ones((3, 3, 3)))[1:-1, 1:-1, 1:-1]
        counts = np.zeros(a.shape + (11,), np.int16)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    if dx == dy == dz == 0:
                        continue
                    nb = P[1 + dx:P.shape[0] - 1 + dx, 1 + dy:P.shape[1] - 1 + dy, 1 + dz:P.shape[2] - 1 + dz]
                    for c in range(1, 11):
                        counts[..., c] += (nb == c)
        same = np.take_along_axis(counts, a[..., None].astype(np.int64), -1)[..., 0]
        maj = counts[..., 1:].argmax(-1) + 1
        fix = surf & (same <= 1) & ~np.isin(a, list(KEEP)) & (maj != a)
        if not fix.any():
            break
        a = a.copy(); a[fix] = maj[fix]
    return a


def fix_islands(a):
    lab, k = ndimage.label(a > 0)
    if k <= 1:
        return a
    sizes = np.bincount(lab.ravel())
    for i in range(1, k + 1):
        if sizes[i] <= 2:
            a[lab == i] = 0
    p = fv.Part("tmp", (0, 0, 0), a.shape); p.a = a
    cf.bridge_islands(p, max_cells=10 ** 6)
    return p.a


def _centers(lo2, shape):
    i, j, k = [np.arange(n)[s_] for n, s_ in zip(shape, (np.s_[:, None, None], np.s_[None, :, None], np.s_[None, None, :]))]
    return (lo2[0] + i) * 2 + 0.5, (lo2[1] + j) * 2 + 0.5, (lo2[2] + k) * 2 + 0.5


def redo_net(d, lo2):
    """왼팔 그물을 절반 격자에서 다시 그림(자동으로 줄이면 마름모가 십자로 뭉개짐). 눈 간격 16칸, 밧줄 1칸(절반)."""
    import cetus_r6 as r6
    X, Y, Z = _centers(lo2, d.shape)
    cx = r6.CAGE_X
    dist = np.sqrt((X - cx) ** 2 + Y ** 2); ang = np.arctan2(Y, X - cx)
    u = ang * 23.0; s = 16.0
    a = ((u + Z) / s) % 1.0; a = np.minimum(a, 1 - a) * s
    b = ((u - Z) / s) % 1.0; b = np.minimum(b, 1 - b) * s
    R = (dist > 21.0) & (dist <= 26.0) & (Z >= 155) & (Z <= 183)
    d = d.copy()
    d[R & (d == 9)] = 0                                                  # 자동으로 줄인 밧줄 지움
    d[R & (dist <= 22.6) & (d == 0)] = 1                                 # 북 겉면 메움
    rope = R & (dist > 22.0) & (dist <= 24.6) & ((a <= 1.7) | (b <= 1.7))
    d[rope] = 9
    return d


def redo_drill(d, lo2):
    """나선 드릴의 강철 턱 줄을 절반 격자에서 다시 칠함(자동으로 줄이면 점으로 끊김)."""
    import cetus_r6 as r6
    X, Y, Z = _centers(lo2, d.shape)
    cx, z1, p = r6.DRILL_X, 52, 12.0
    ang = np.arctan2(Y, X - cx)
    frac = (((Z - z1) + p * ang / (2 * np.pi)) / p) % 1.0
    m = np.isin(d, (3, 7)) & (Z <= 125) & (Z >= z1)
    d = d.copy()
    full = np.broadcast_to(frac, d.shape)
    d[m & (full > 0.7)] = 7
    d[m & (full <= 0.7)] = 3
    return d


def make_half(M):
    H = fv.Model()
    tri = {}
    for n, p in M.parts.items():
        d, lo2 = down2(p.a, p.lo)
        d = despeckle(d)
        if n == "LowerArmL":
            d = redo_net(d, lo2)
        if n == "DrillR":
            d = redo_drill(d, lo2)
        d = fix_islands(d)
        tri[n] = 2 * greedy_quads(d)
        q = H.part(n, tuple(lo2 * 2), tuple(lo2 * 2 + np.array(d.shape) * 2), p.pivot, p.parent); q.rot = p.rot
        q.a = np.repeat(np.repeat(np.repeat(d, 2, 0), 2, 1), 2, 2)
        q.half = d
    return H, tri


if __name__ == "__main__":
    out = sys.argv[1]
    save_dir = sys.argv[2] if len(sys.argv) > 2 else out
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    M = cf.build_all()
    M.save(os.path.join(save_dir, "CETUS_full.json"))
    H, tri = make_half(M)
    bad = []
    for n, q in H.parts.items():
        _, k = ndimage.label(q.half > 0)
        flag = ("  ⚠삼각형" if tri[n] >= 10000 else "") + ("  ⚠섬 %d" % (k - 1) if k > 1 else "")
        if flag:
            bad.append(n)
        print("%-13s 절반 칸 %6d  tris %6d%s" % (n, int((q.half > 0).sum()), tri[n], flag))
    print("총 삼각형 %d · %s" % (sum(tri.values()), "OK" if not bad else "고칠 것 %s" % bad))
    H.save(os.path.join(save_dir, "CETUS_half.json"))
    # 비교 그림: 원본 / 정리판 — 전신 앞·뒤 + 어깨·그물 확대
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    LB = (0.55, 0.75, 0.85)
    tiles = []
    for MM, lab in ((M, "원본"), (H, "절반 정리판")):
        B = MM.blocks()
        tiles.append((vp.render(B, PAL, EMISSIVE, yaw=-30, pitch=6, ppc=2.4, ss=2, ao_amt=0.5, metal=METAL), lab + " · 앞 3/4"))
        tiles.append((vp.render(B, PAL, EMISSIVE, yaw=155, pitch=8, ppc=2.4, ss=2, ao_amt=0.5, metal=METAL, light=LB), lab + " · 뒤 3/4"))
        up = MM.blocks(skip=[n for n in MM.parts if n not in ("Torso", "Collar", "Head", "ShoulderL", "ShoulderBaseL", "UpperArmL", "LowerArmL", "ClawL")])
        tiles.append((vp.render(up, PAL, EMISSIVE, yaw=40, pitch=8, ppc=4.0, ss=2, ao_amt=0.5, metal=METAL), lab + " · 왼어깨·그물"))
    Hh = max(t[0].height for t in tiles)
    W = max(sum(t[0].width + 16 for t in tiles[i:i + 3]) for i in (0, 3))
    sh = Image.new("RGB", (W, 2 * (Hh + 44)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for ri in range(2):
        x = 0; y0 = ri * (Hh + 44)
        for im, t in tiles[ri * 3:ri * 3 + 3]:
            sh.paste(im, (x, y0 + Hh - im.height)); d.text((x + 8, y0 + Hh + 8), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_half_clean.png")); print(sh.size)
