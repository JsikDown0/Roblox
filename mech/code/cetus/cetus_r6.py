"""HT-02 CETUS — r6 = r4(헬멧·가슴·어깨 확정) + 팔 r2 (2026-11-02)

r5 → r6 (유저 11-02):
- 드릴 팔 훨씬 두껍게 · 기동부(팔꿈치 쪽)에 유압 실린더 6개 · 동력선 1줄 추가(등 위 → 기동부 바깥)
- 집게: 양옆 같은 크기 큰 초승달 갈고리 2개 + 가운데 아래(포신 앞) 작은 보조 집게 1개. 마디는 색 줄 대신 단(폭이 단계적으로 줄어듦)
- 왼팔 케이지: 굵고 짧은 북 모양, 고리·끈 더 두껍게 돋움
유지: 드릴 발광 틈 = 색 8(궁극기 때만), R5 호스 1줄, 가운데 포신.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import cetus_r3 as r3  # noqa: E402
import cetus_r4 as r4  # noqa: E402

PAL = dict(r3.PAL); PAL[8] = (92, 62, 30)
EMISSIVE = {6}
PAL_ULT = dict(PAL); PAL_ULT[8] = (255, 186, 84)
EMISSIVE_ULT = {6, 8}

UP_X = 54          # 위팔 중심 |x|
DRILL_X = -58      # 드릴 축 x
CAGE_X = 56        # 케이지 축 x
ELBOW_Z = 186


def path_tube(G, path, r):
    m = None
    for a, b in zip(path[:-1], path[1:]):
        t = r3.capsule(G, a, b, r)
        m = t if m is None else (m | t)
    return m


def ball(G, c, r):
    X, Y, Z = G
    return ((X - c[0]) ** 2 + (Y - c[1]) ** 2 + (Z - c[2]) ** 2) <= r * r + 0.25


def build_upper(M, side):
    name = "UpperArmL" if side > 0 else "UpperArmR"
    cx = side * UP_X
    U = M.part(name, (cx - 30, -24, 170), (cx + 31, 26, 206), pivot=(side * 50, 0, 203), parent="Torso")
    G = U.g()
    U.add(fv.cyl(G, "z", (cx, 0), 12, rng=(184, 201)), 3)
    U.add(fv.cyl(G, "z", (cx, 0), 13.5, rng=(193, 195)), 5)
    if side < 0:   # R5 호스: 오른 어깨 안쪽 뒤 → 위팔 옆 → 드릴 몸통 뒤
        path = [(cx + 20, 10, 202), (cx + 16, 15, 192), (cx + 10, 19, 182), (cx + 6, 19, 176)]
        t = path_tube(G, path, 3.5) & ~(U.a > 0)
        U.add(t, 3)
        U.paint(t & fv.box(G, z=(188, 189)), 5)
    U.trim()
    return U


def build_drill(M):
    cx = DRILL_X
    D = M.part("LowerArmR", (cx - 40, -34, 40), (cx + 34, 44, 212), pivot=(cx, 0, ELBOW_Z), parent="UpperArmR")
    G = D.g()
    X, Y, Z = G
    dist = np.sqrt((X - cx) ** 2 + Y ** 2)
    ang = np.arctan2(Y, X - cx)
    # 기동부(z 166~186): 짙은 심 + 유압 실린더 6개(축과 나란히) + 위 황동 깃
    D.add(fv.cyl(G, "z", (cx, 0), 19, rng=(166, 186)), 3)
    for k in range(6):
        a = np.pi / 6 + k * np.pi / 3
        px, py = cx + 21 * np.cos(a), 21 * np.sin(a)
        D.add(fv.cyl(G, "z", (px, py), 4, rng=(168, 184)), 7)
        D.add(fv.cyl(G, "z", (px, py), 4.6, rng=(168, 169)) | fv.cyl(G, "z", (px, py), 4.6, rng=(183, 184)), 5)
        D.add(fv.cyl(G, "z", (px, py), 2, rng=(185, 187)), 7)            # 피스톤 막대 끝
    D.add(fv.cyl(G, "z", (cx, 0), 23, rng=(186, 188)) & ~fv.cyl(G, "z", (cx, 0), 12), 5)
    # 몸통(z 126~166): 굵은 청록 원통 + 황동 띠 2줄(2칸 돋움) + 띠 앞 발광 틈(색 8)
    D.add(fv.cyl(G, "z", (cx, 0), 26, rng=(126, 166)), 1)
    D.add(fv.cyl(G, "z", (cx, 0), 25, rng=(166, 167)), 1)
    for z0 in (154, 132):
        D.add(fv.cyl(G, "z", (cx, 0), 28, rng=(z0, z0 + 6)) & ~fv.cyl(G, "z", (cx, 0), 26), 5)
        D.add(fv.box(G, x=(cx - 3, cx + 3), y=(-29, -27), z=(z0 + 2, z0 + 4)), 8)
    D.groove(fv.box(G, z=(145, 145)) & fv.cyl(G, "z", (cx, 0), 27), 4)
    # 원뿔 7단(z 126 → 63): 짙은 강철, 단 위 황동 테, 단마다 4칸 계단
    for i in range(7):
        zt = 126 - 9 * i; zb = zt - 9
        rr = 24.0 - 3.0 * i
        k = (Z - zb) / 9.0
        rad = (rr - 4.0) + 4.0 * k
        tier = (Z <= zt - 1) & (Z >= zb) & (dist <= rad + 0.25)
        D.add(tier, 3)
        D.paint(tier & (Z >= zt - 2), 5)
        if i in (1, 3, 5):
            D.add((np.abs(X - cx) <= 1) & (Y <= -(rr - 3.5)) & (Y >= -(rr - 1.5)) & (Z >= zb + 3) & (Z <= zb + 5), 8)
    D.add((Z < 63) & (Z >= 50) & (dist <= 3.4 * (Z - 50) / 13.0 + 0.25), 7)
    # 동력선 1줄: 등 위(어깨 뒤) → 바깥으로 크게 휘어 → 기동부 바깥쪽
    cable = [(cx + 34, 34, 208), (cx + 14, 40, 204), (cx - 8, 36, 196), (cx - 22, 22, 186), (cx - 25, 8, 177)]
    t = path_tube(G, cable, 4.5) & ~(D.a > 0)
    D.add(t, 3)
    for c in cable[1:4]:
        D.paint(t & ball(G, c, 5.5), 5)                                  # 황동 연결 고리
    D.trim()
    return D


def claw_side(G, cx, sgn):
    """양옆 큰 초승달 갈고리(x-z 평면에서 휨). 폭(y)은 마디마다 단계적으로 좁아짐."""
    X, Y, Z = G
    outer = [(13, 146), (25, 136), (31, 120), (29, 104), (22, 92), (12, 85)]
    inner = [(12, 85), (17, 95), (23, 106), (25, 119), (20, 131), (12, 139)]
    pts = [(cx + sgn * u, z) for u, z in outer + inner]
    m = fv.poly(G, "y", pts, rng=(-6, 6))
    w = np.where(Z > 121, 5.5, np.where(Z > 104, 4.5, 3.5))
    return m & (np.abs(Y) <= w)


def claw_aux(G, cx):
    """가운데 앞 아래 작은 보조 집게(y-z 평면에서 휨, 포구 앞)."""
    X, Y, Z = G
    pts = [(-7, 138), (-12, 129), (-14, 117), (-11, 106), (-6, 99), (-8, 108), (-9, 117), (-8, 127), (-6, 136)]
    m = fv.poly(G, "x", pts, rng=(cx - 3, cx + 3))
    return m & (np.abs(X - cx) <= np.where(Z > 116, 3, 2))


def build_claw(M):
    cx = CAGE_X
    C = M.part("LowerArmL", (cx - 34, -30, 78), (cx + 35, 30, 190), pivot=(cx, 0, ELBOW_Z), parent="UpperArmL")
    G = C.g()
    X, Y, Z = G
    dist = np.sqrt((X - cx) ** 2 + Y ** 2)
    ang = np.arctan2(Y, X - cx)
    # 짧고 굵은 북(z 152~186): 청록 심 + 두껍게 돋운 황동 고리 3줄(3칸) + 세로 끈 8줄(2.5칸)
    C.add(fv.cyl(G, "z", (cx, 0), 22, rng=(152, 186)), 1)
    C.add(fv.cyl(G, "z", (cx, 0), 14, rng=(186, 187)), 3)
    for z0 in (182, 167, 152):
        C.add(fv.cyl(G, "z", (cx, 0), 25, rng=(z0, z0 + 3)) & ~fv.cyl(G, "z", (cx, 0), 22), 5)
    for kk in range(8):
        a0 = kk * np.pi / 4 + np.pi / 8
        da = np.abs((ang - a0 + np.pi) % (2 * np.pi) - np.pi)
        C.add((da * 23 <= 1.6) & (dist > 22.2) & (dist <= 24.6) & (Z >= 152) & (Z <= 185), 5)
    # 주먹 + 가운데 포신(아래로)
    C.add(fv.cbox(G, (cx - 14, cx + 14), (-14, 14), (138, 152), ch={"xy": 4, "-zx": 3, "-zy": 3}), 3)
    C.add(fv.cyl(G, "z", (cx, 0), 5.5, rng=(118, 138)), 7)
    C.add(fv.cyl(G, "z", (cx, 0), 7, rng=(118, 120)), 5)
    C.cut(fv.cyl(G, "z", (cx, 0), 2.5, rng=(116, 124)))
    C.add(fv.cyl(G, "z", (cx, 0), 2.5, rng=(124, 124)), 4)
    # 집게: 양옆 큰 갈고리 2 + 보조 1, 경첩(짙은 원통)
    for sgn in (+1, -1):
        cl = claw_side(G, cx, sgn) & ~(C.a > 0)
        C.add(cl, 5)
        C.paint(cl & (Z <= 92), 7)
        C.add(fv.cyl(G, "y", (cx + sgn * 14, 142), 4, rng=(-7, 7)) & ~(C.a > 0), 3)
    ax = claw_aux(G, cx) & ~(C.a > 0)
    C.add(ax, 5)
    C.paint(ax & (Z <= 104), 7)
    C.trim()
    return C


def build_all():
    M = r4.build_all()
    build_upper(M, +1); build_upper(M, -1)
    build_drill(M); build_claw(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    M = build_all()
    for n, p in M.parts.items():
        print(n, p.count())
    B = M.blocks()
    specs = [(-30, 6, PAL, EMISSIVE, "r6 앞 3/4"), (0, 4, PAL, EMISSIVE, "r6 정면"), (90, 2, PAL, EMISSIVE, "r6 옆(왼쪽)"),
             (-90, 2, PAL, EMISSIVE, "r6 옆(오른쪽)"), (150, 10, PAL, EMISSIVE, "r6 뒤 3/4"), (-30, 6, PAL_ULT, EMISSIVE_ULT, "궁극기 발광")]
    ims = [vp.render(B, pal, em, yaw=y, pitch=p, ppc=2.6, ss=2, ao_amt=0.5) for y, p, pal, em, _ in specs]
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "CETUS", "concept_v1_GPT_후보.png")).convert("RGB").crop((0, 100, 1229, 960))
    H = ims[0].height
    con = con.resize((int(con.width * H / con.height), H), Image.LANCZOS)
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    W = con.width + sum(i.width for i in ims) + 16 * len(ims)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in [(con, "컨셉")] + list(zip(ims, [s[4] for s in specs])):
        sh.paste(im, (x, 0)); d.text((x + 8, H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_r6_compare.png")); print(sh.size)
