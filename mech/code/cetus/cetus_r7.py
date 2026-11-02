"""HT-02 CETUS — r7 = r6 팔 수정 (2026-11-02, 유저: 케이지는 그물 느낌, 드릴은 디테일이 애매하고 과함 → 레퍼런스(ref1 워해머 드릴 팔) 참고)

- 드릴: 짧은 청록 하우징 + 황동 고리 1개 → 둥근 고리 8단이 일정하게 쌓인 원뿔(짙은 강철, 황동 테 없음) → 강철 끝.
  유압 실린더·황동 띠·단마다 테 제거. 궁극기 발광(색 8) = 하우징과 원뿔 사이 이음새 고리 한 줄.
  관: 동력선 1줄 + R5 호스(위팔) 유지 — 팔꿈치를 감는 굵은 관 역할.
- 케이지 → 그물: 북(청록 심) 위에 사선으로 엇갈린 밧줄(뼈색) + 매듭, 위·아래 밧줄 테.
- 집게(양옆 큰 갈고리 2 + 보조 1)·포신·위팔은 r6 그대로.
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

PAL, EMISSIVE, PAL_ULT, EMISSIVE_ULT = r6.PAL, r6.EMISSIVE, r6.PAL_ULT, r6.EMISSIVE_ULT
DRILL_X, CAGE_X, ELBOW_Z = r6.DRILL_X, r6.CAGE_X, r6.ELBOW_Z


def build_drill(M):
    cx = DRILL_X
    D = M.part("LowerArmR", (cx - 40, -34, 40), (cx + 34, 44, 212), pivot=(cx, 0, ELBOW_Z), parent="UpperArmR")
    G = D.g()
    X, Y, Z = G
    dist = np.sqrt((X - cx) ** 2 + Y ** 2)
    D.add(fv.cyl(G, "z", (cx, 0), 16, rng=(176, 187)), 3)                       # 팔꿈치 받침
    D.add(fv.cbox(G, (cx - 23, cx + 23), (-23, 23), (156, 178), ch={"xy": 8}), 1)  # 짧은 하우징(팔각)
    D.add(fv.cyl(G, "z", (cx, 0), 27, rng=(150, 156)), 5)                       # 황동 고리 1개
    D.add(fv.cyl(G, "z", (cx, 0), 25, rng=(148, 149)) & ~fv.cyl(G, "z", (cx, 0), 22), 8)   # 이음새 발광(궁극기)
    D.add(fv.cyl(G, "z", (cx, 0), 22, rng=(148, 149)), 3)
    # 원뿔: 둥근 고리 8단(각 단 가운데가 가장 두툼한 구슬 단면)
    top, h, n = 147, 11, 8
    for i in range(n):
        zt = top - h * i; zb = zt - h + 1
        rr = 25.0 - 2.4 * i
        k = (Z - zb) / (h - 1)                      # 0 아래 → 1 위
        bulge = 1.0 - (2 * k - 1) ** 2               # 가운데 1
        rad = (rr - 3.5) + 3.5 * bulge - 1.2 * (1 - k)
        D.add((Z >= zb) & (Z <= zt) & (dist <= rad + 0.25), 3)
    zt_end = top - h * n
    D.add((Z <= zt_end) & (Z >= zt_end - 12) & (dist <= 5.5 * (Z - (zt_end - 12)) / 12.0 + 0.25), 7)
    # 동력선(r6 와 같은 경로) — 하우징 바깥으로 들어감
    cable = [(cx + 34, 34, 208), (cx + 14, 40, 204), (cx - 8, 36, 196), (cx - 22, 22, 184), (cx - 24, 8, 172)]
    t = r6.path_tube(G, cable, 4.5) & ~(D.a > 0)
    D.add(t, 3)
    for c in cable[1:4]:
        D.paint(t & r6.ball(G, c, 5.5), 5)
    D.trim()
    return D


def build_claw(M):
    cx = CAGE_X
    C = M.part("LowerArmL", (cx - 34, -30, 78), (cx + 35, 30, 190), pivot=(cx, 0, ELBOW_Z), parent="UpperArmL")
    G = C.g()
    X, Y, Z = G
    dist = np.sqrt((X - cx) ** 2 + Y ** 2)
    ang = np.arctan2(Y, X - cx)
    C.add(fv.cyl(G, "z", (cx, 0), 22, rng=(152, 186)), 1)
    C.add(fv.cyl(G, "z", (cx, 0), 14, rng=(186, 187)), 3)
    # 그물: 북 겉 1~2칸에 사선 밧줄 두 방향(마름모 눈) + 매듭
    R, s = 23.0, 15.0
    u = ang * R
    a = ((u + Z) / s) % 1.0; a = np.minimum(a, 1 - a) * s
    b = ((u - Z) / s) % 1.0; b = np.minimum(b, 1 - b) * s
    shell = (dist > 22.2) & (dist <= 23.8) & (Z >= 155) & (Z <= 183)
    rope = shell & ((a <= 1.1) | (b <= 1.1))
    knot = (dist > 22.2) & (dist <= 24.8) & (Z >= 155) & (Z <= 183) & (a <= 2.2) & (b <= 2.2)
    C.add(rope | knot, 2)
    for z0 in (184, 152):                                                   # 위·아래 밧줄 테
        C.add(fv.cyl(G, "z", (cx, 0), 24.5, rng=(z0, z0 + 2)) & ~fv.cyl(G, "z", (cx, 0), 22), 2)
    # 주먹 + 포신 + 집게(r6 그대로)
    C.add(fv.cbox(G, (cx - 14, cx + 14), (-14, 14), (138, 152), ch={"xy": 4, "-zx": 3, "-zy": 3}), 3)
    C.add(fv.cyl(G, "z", (cx, 0), 5.5, rng=(118, 138)), 7)
    C.add(fv.cyl(G, "z", (cx, 0), 7, rng=(118, 120)), 5)
    C.cut(fv.cyl(G, "z", (cx, 0), 2.5, rng=(116, 124)))
    C.add(fv.cyl(G, "z", (cx, 0), 2.5, rng=(124, 124)), 4)
    for sgn in (+1, -1):
        cl = r6.claw_side(G, cx, sgn) & ~(C.a > 0)
        C.add(cl, 5)
        C.paint(cl & (Z <= 92), 7)
        C.add(fv.cyl(G, "y", (cx + sgn * 14, 142), 4, rng=(-7, 7)) & ~(C.a > 0), 3)
    ax = r6.claw_aux(G, cx) & ~(C.a > 0)
    C.add(ax, 5)
    C.paint(ax & (Z <= 104), 7)
    C.trim()
    return C


def build_all():
    M = r4.build_all()
    r6.build_upper(M, +1); r6.build_upper(M, -1)
    build_drill(M); build_claw(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    M = build_all()
    for n_, p in M.parts.items():
        print(n_, p.count())
    B = M.blocks()
    specs = [(-30, 6, PAL, EMISSIVE, "r7 앞 3/4"), (0, 4, PAL, EMISSIVE, "r7 정면"), (90, 2, PAL, EMISSIVE, "r7 옆(왼쪽)"),
             (-90, 2, PAL, EMISSIVE, "r7 옆(오른쪽)"), (150, 10, PAL, EMISSIVE, "r7 뒤 3/4"), (-30, 6, PAL_ULT, EMISSIVE_ULT, "궁극기 발광")]
    ims = [vp.render(B, pal, em, yaw=y, pitch=p, ppc=2.6, ss=2, ao_amt=0.5) for y, p, pal, em, _ in specs]
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    H = ims[0].height
    W = sum(i.width for i in ims) + 16 * len(ims)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in zip(ims, [s_[4] for s_ in specs]):
        sh.paste(im, (x, 0)); d.text((x + 8, H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_r7_compare.png")); print(sh.size)
