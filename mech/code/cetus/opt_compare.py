"""CETUS 최적화 2·3안 비교 (2026-11-02, 유저 "2,3번 보여줄래?")

2안 각지게: 두 방향으로 휜 타원 돔(fv.ell)을 모서리 깎은 상자(다면체)로 바꿔 다시 조립.
   |u|,|v|,|w| ≤ 1 (u = dx/rx …) + 모서리 깎기 |u|+|v| ≤ C2 (세 축 쌍) + 꼭짓점 깎기 |u|+|v|+|w| ≤ C3.
   평면이라 계단이 한 방향으로만 생겨 길게 합쳐짐. 나선 드릴·종 모양 정강이는 그대로.
3안 섞기: 두 방향 곡면이 많은 파트만 절반 해상도(2×2×2 → 1칸), 머리·가슴·목깃·등·집게팔·위팔은 원래 해상도.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from check_model import greedy_quads  # noqa: E402

C2, C3 = 1.42, 1.95
HALF_PARTS = ("ShoulderL", "ShoulderR", "ShoulderBaseL", "ShoulderBaseR", "LowerArmR", "DrillR", "Pelvis", "BoosterMain",
              "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "KneeL", "KneeR", "FootL", "FootR")


def facet_ell(G, c, r, sym=False):
    X, Y, Z = G
    if sym:
        X = np.abs(X)
    u, v, w = np.abs((X - c[0]) / r[0]), np.abs((Y - c[1]) / r[1]), np.abs((Z - c[2]) / r[2])
    return (u <= 1) & (v <= 1) & (w <= 1) & (u + v <= C2) & (u + w <= C2) & (v + w <= C2) & (u + v + w <= C3)


def build_faceted():
    import cetus_final as cf
    orig = fv.ell
    small = lambda G, c, r, sym=False: (orig(G, c, r, sym) if max(r) < 8 else facet_ell(G, c, r, sym))   # 볼트·등불 같은 작은 건 그대로
    mods = [m for m in list(sys.modules.values()) if m and getattr(m, "__file__", "") and "cetus" in os.path.basename(getattr(m, "__file__", "") or "")]
    patched = []
    for m in mods + [fv]:
        if getattr(m, "ell", None) is orig:
            setattr(m, "ell", small); patched.append(m)
    try:
        M = cf.build_all()
    finally:
        for m in patched:
            setattr(m, "ell", orig)
    return M


def down2(a, lo):
    o = np.array(lo) % 2
    a = np.pad(a, [(o[i], 0) for i in range(3)])
    sh = [(s + 1) // 2 * 2 for s in a.shape]
    b = np.zeros(sh, np.uint8); b[:a.shape[0], :a.shape[1], :a.shape[2]] = a
    v = b.reshape(sh[0] // 2, 2, sh[1] // 2, 2, sh[2] // 2, 2).transpose(0, 2, 4, 1, 3, 5).reshape(sh[0] // 2, sh[1] // 2, sh[2] // 2, 8)
    out = np.zeros(v.shape[:3], np.uint8); best = np.zeros(v.shape[:3], int)
    pri = {6: 3, 10: 3, 8: 3, 4: 2}
    for c in range(1, 11):
        cnt = (v == c).sum(-1) * pri.get(c, 1)
        upd = cnt > best; out[upd] = c; best[upd] = cnt[upd]
    out[(v > 0).sum(-1) < 4] = 0
    return out, np.array(lo) - o


def half_parts(M, names):
    """names 파트를 절반 해상도로(보기용으로 다시 2배 늘려 같은 격자에). 반환: 파트별 실제 삼각형."""
    t = {}
    for n in names:
        p = M.parts[n]
        d, lo = down2(p.a, p.lo)
        t[n] = 2 * greedy_quads(d)
        p.a = np.repeat(np.repeat(np.repeat(d, 2, 0), 2, 1), 2, 2); p.lo = lo; p.hi = lo + np.array(p.a.shape)
    return t


def total(M, override=None):
    override = override or {}
    return sum(override.get(n, 2 * greedy_quads(p.a)) for n, p in M.parts.items())


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import cetus_final as cf
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    M0 = fv.Model.load(os.path.join(out, "cetus_final.json"))
    t0 = total(M0)
    M2 = build_faceted(); t2 = total(M2)
    M3 = fv.Model.load(os.path.join(out, "cetus_final.json")); o3 = half_parts(M3, HALF_PARTS); t3 = total(M3, o3)
    print("원래", t0, "· 2안 각지게", t2, "· 3안 섞기", t3)
    for n in M2.parts:
        print("  %-13s 원래 %6d  각지게 %6d  섞기 %6d" % (n, 2 * greedy_quads(M0.parts[n].a), 2 * greedy_quads(M2.parts[n].a), o3.get(n, 2 * greedy_quads(M3.parts[n].a))))
    tiles = []
    for M, lab in ((M0, "원래 %s" % format(t0, ",")), (M2, "2 각지게 %s" % format(t2, ",")), (M3, "3 섞기 %s" % format(t3, ","))):
        B = M.blocks()
        tiles.append((vp.render(B, cf.PAL, cf.EMISSIVE, yaw=-30, pitch=6, ppc=2.4, ss=2, ao_amt=0.5, metal=cf.METAL), lab + " · 앞 3/4"))
        tiles.append((vp.render(B, cf.PAL, cf.EMISSIVE, yaw=155, pitch=8, ppc=2.4, ss=2, ao_amt=0.5, metal=cf.METAL, light=(0.55, 0.75, 0.85)), lab + " · 뒤 3/4"))
    H = max(t[0].height for t in tiles); W = max(sum(t[0].width + 16 for t in tiles[i:i + 2]) for i in (0, 2, 4)) * 3 // 1
    W = sum(t[0].width + 16 for t in tiles)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in tiles:
        sh.paste(im, (x, H - im.height)); d.text((x + 8, H + 8), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_opt_23.png")); print(sh.size)
