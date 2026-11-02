"""HT-02 CETUS — 드릴 오른팔 비교안 A~E (2026-11-02, 유저 "드릴이 맘에 안 드는데 여러 개 만들면 고를게")

공통: 위팔·R5 호스(r6) · 동력선 · 궁극기 발광 이음새(색 8). 드릴 부분만 다름.
A 지금 r7(짧은 하우징 + 둥근 고리 8단) · B 컨셉형(큰 몸통 + 황동 띠 2 + 계단 원뿔, 황동 테 2단마다)
C 나선 오거(나선 날 2줄) · D 세로 날 4줄(살짝 비틂) + 배기관 2 · E 짧고 뚱뚱한 해머 드릴(냉각핀 + 4단)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import cetus_r4 as r4  # noqa: E402
import cetus_r6 as r6  # noqa: E402
import cetus_r7 as r7  # noqa: E402

cx = r6.DRILL_X


def _part(M):
    D = M.part("LowerArmR", (cx - 42, -36, 36), (cx + 36, 46, 212), pivot=(cx, 0, r6.ELBOW_Z), parent="UpperArmR")
    G = D.g(); X, Y, Z = G
    return D, G, X, Y, Z, np.sqrt((X - cx) ** 2 + Y ** 2), np.arctan2(Y, X - cx)


def _common(D, G, seam_z):
    D.add(fv.cyl(G, "z", (cx, 0), 16, rng=(176, 187)), 3)
    D.add(fv.cyl(G, "z", (cx, 0), 25, rng=(seam_z, seam_z + 1)) & ~fv.cyl(G, "z", (cx, 0), 22), 8)
    D.add(fv.cyl(G, "z", (cx, 0), 22, rng=(seam_z, seam_z + 1)), 3)
    cable = [(cx + 34, 34, 208), (cx + 14, 40, 204), (cx - 8, 36, 196), (cx - 22, 22, 184), (cx - 25, 8, 172)]
    t = r6.path_tube(G, cable, 4.5) & ~(D.a > 0)
    D.add(t, 3)
    for c in cable[1:4]:
        D.paint(t & r6.ball(G, c, 5.5), 5)


def _tip(D, Z, dist, z0, r=5.5, h=12):
    D.add((Z <= z0) & (Z >= z0 - h) & (dist <= r * (Z - (z0 - h)) / h + 0.25), 7)


def drill_A(M):
    return r7.build_drill(M)


def drill_B(M):
    D, G, X, Y, Z, dist, ang = _part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 26, rng=(132, 176)), 1)
    for z0 in (164, 140):
        D.add(fv.cyl(G, "z", (cx, 0), 28, rng=(z0, z0 + 5)) & ~fv.cyl(G, "z", (cx, 0), 26), 5)
    _common(D, G, 130)
    for i in range(7):
        zt = 129 - 10 * i; zb = zt - 9
        rr = 24.0 - 2.8 * i
        rad = (rr - 4.0) + 4.0 * (Z - zb) / 9.0
        tier = (Z <= zt) & (Z >= zb) & (dist <= rad + 0.25)
        D.add(tier, 3)
        if i % 2 == 0:
            D.paint(tier & (Z >= zt - 1), 5)
    _tip(D, Z, dist, 59)
    D.trim(); return D


def drill_C(M):
    D, G, X, Y, Z, dist, ang = _part(M)
    D.add(fv.cbox(G, (cx - 24, cx + 24), (-24, 24), (150, 178), ch={"xy": 8}), 1)
    D.add(fv.cyl(G, "z", (cx, 0), 27, rng=(144, 150)), 5)
    _common(D, G, 142)
    z0, z1 = 141, 62
    k = np.clip((Z - z1) / (z0 - z1), 0, 1)
    rc = 6 + 16 * k                                                     # 심 반지름
    core = (Z <= z0) & (Z >= z1) & (dist <= rc + 0.25)
    D.add(core, 3)
    phase = 2 * ang - Z * 2 * np.pi / 26.0                              # 나선 날 2줄, 피치 26칸
    flight = (Z <= z0) & (Z >= z1) & (np.cos(phase) > 0.55) & (dist <= rc + 4.5 + 0.25) & ~core
    D.add(flight, 7)
    _tip(D, Z, dist, z1, r=6)
    D.trim(); return D


def drill_D(M):
    D, G, X, Y, Z, dist, ang = _part(M)
    D.add(fv.cbox(G, (cx - 25, cx + 25), (-25, 25), (142, 178), ch={"xy": 9, "-zx": 4, "-zy": 4}), 1)
    D.add(fv.cyl(G, "z", (cx, 0), 27, rng=(138, 142)), 5)
    for sx in (-9, 9):                                                  # 배기관 2(뒤, 위로)
        D.add(fv.cyl(G, "z", (cx + sx, 27), 3.5, rng=(146, 192)), 3)
        D.add(fv.cyl(G, "z", (cx + sx, 27), 4.2, rng=(188, 192)), 5)
    _common(D, G, 136)
    z0, z1 = 135, 60
    k = np.clip((Z - z1) / (z0 - z1), 0, 1)
    rc = 5 + 17 * k
    core = (Z <= z0) & (Z >= z1) & (dist <= rc + 0.25)
    D.add(core, 3)
    twist = (z0 - Z) / (z0 - z1) * (np.pi / 4)
    da = np.abs(((ang - twist) * 2 + np.pi) % (np.pi) - np.pi / 2)    # 4줄(90° 간격)
    blade = (Z <= z0) & (Z >= z1) & (da < 0.22) & (dist <= rc + 4 + 0.25) & ~core
    D.add(blade, 7)
    _tip(D, Z, dist, z1, r=5)
    D.trim(); return D


def drill_E(M):
    D, G, X, Y, Z, dist, ang = _part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 27, rng=(122, 178)), 1)
    fin = (np.abs(((ang * 12 / np.pi) % 2) - 1) < 0.35) & (dist > 27) & (dist <= 30) & (Z >= 128) & (Z <= 172)
    D.add(fin, 3)                                                       # 세로 냉각핀 12줄
    D.add(fv.cyl(G, "z", (cx, 0), 30, rng=(172, 176)), 5)
    D.add(fv.cyl(G, "z", (cx, 0), 30, rng=(122, 126)), 5)
    _common(D, G, 120)
    for i in range(4):
        zt = 119 - 11 * i; zb = zt - 10
        rr = 26.0 - 5.0 * i
        rad = (rr - 5.0) + 5.0 * (Z - zb) / 10.0
        D.add((Z <= zt) & (Z >= zb) & (dist <= rad + 0.25), 3)
    _tip(D, Z, dist, 75, r=7, h=12)
    D.trim(); return D


VARIANTS = [("A", "지금 r7: 짧은 하우징+고리 8단", drill_A), ("B", "컨셉형: 큰 몸통+띠 2+계단", drill_B),
            ("C", "나선 오거", drill_C), ("D", "세로 날 4+배기관", drill_D), ("E", "짧고 뚱뚱한 해머", drill_E)]


def build_all(which="A"):
    M = r4.build_all()
    r6.build_upper(M, +1); r6.build_upper(M, -1)
    dict((v[0], v[2]) for v in VARIANTS)[which](M)
    r7.build_claw(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    cols = []
    for key, label, fn in VARIANTS:
        M = build_all(key)
        print(key, M.parts["LowerArmR"].count())
        keep = ("Torso", "Head", "ShoulderR", "UpperArmR", "LowerArmR")
        B = M.blocks(skip=[n for n in M.parts if n not in keep])
        a = vp.render(B, r6.PAL, r6.EMISSIVE, yaw=-35, pitch=6, ppc=3.0, ss=2, ao_amt=0.5)
        b = vp.render(B, r6.PAL, r6.EMISSIVE, yaw=-90, pitch=2, ppc=3.0, ss=2, ao_amt=0.5)
        cols.append((key + " " + label, a, b))
    H = max(c[1].height for c in cols) + max(c[2].height for c in cols) + 70
    W = sum(max(c[1].width, c[2].width) for c in cols) + 16 * len(cols)
    sh = Image.new("RGB", (W, H), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for lab, a, b in cols:
        w = max(a.width, b.width)
        d.text((x + 8, 8), lab, fill=(230, 230, 230), font=f)
        sh.paste(a, (x, 40)); sh.paste(b, (x, 40 + a.height + 10))
        x += w + 16
    sh.save(os.path.join(out, "cetus_drills_compare.png")); print(sh.size)
