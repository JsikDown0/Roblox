"""HT-02 CETUS — r5 = r4(헬멧·가슴·어깨 확정) + 팔 r1 (2026-11-02)

팔 읽기: mech/docs/레퍼런스/CETUS/윤곽읽기_r4_팔.png · 결정기록 5-6
- 쉬는 자세 = 팔 곧게 내림. 위팔 짧고 굵게(짙은 프레임).
- 오른팔: 드릴 몸통(청록 원통 + 황동 띠 2줄) → 원뿔 7단(강철 + 단마다 황동 테) → 끝.
  드릴 발광 틈 = 색 8(평소 꺼진 짙은 호박 유리) — 궁극기 때만 켬(게임에서 SurfaceAppearance/색 교체).
  R5 호스 1줄: 오른 어깨 안쪽 뒤 → 위팔 옆 → 드릴 몸통 뒤.
- 왼팔: 케이지 아래팔(청록 원통 + 돋운 황동 고리 3줄·세로 끈 8줄) → 짙은 주먹 → 집게 3갈래(2마디, 안으로 굽음) + 가운데 포신.
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

PAL = dict(r3.PAL); PAL[8] = (92, 62, 30)        # 8 = 꺼진 발광 유리(궁극기 때만 켬)
EMISSIVE = {6}
PAL_ULT = dict(PAL); PAL_ULT[8] = (255, 186, 84)  # 궁극기 미리보기
EMISSIVE_ULT = {6, 8}

ARM_X = 52           # 위팔·아래팔 중심 |x|
ELBOW_Z = 186


def tube_path(G, path, r):
    m = None
    for a, b in zip(path[:-1], path[1:]):
        t = r3.capsule(G, a, b, r)
        m = t if m is None else (m | t)
    return m


def build_upper(M, side):
    name = "UpperArmL" if side > 0 else "UpperArmR"
    cx = side * ARM_X
    U = M.part(name, (cx - 30, -24, 170), (cx + 31, 26, 206), pivot=(side * 50, 0, 203), parent="Torso")
    G = U.g()
    U.add(fv.cyl(G, "z", (cx, 0), 11, rng=(184, 201)), 3)
    U.add(fv.cyl(G, "z", (cx, 0), 12.5, rng=(193, 195)), 5)          # 위팔 황동 고리
    if side < 0:   # R5 호스: 어깨 안쪽 뒤 → 위팔 옆 → 드릴 몸통 뒤
        path = [(cx + 18, 10, 202), (cx + 14, 15, 192), (cx + 9, 18, 182), (cx + 4, 18, 176)]
        t = tube_path(G, path, 3.5) & ~(U.a > 0)
        U.add(t, 3)
        U.paint(t & fv.box(G, z=(188, 189)), 5)
    U.trim()
    return U


def build_drill(M):
    cx = -ARM_X
    D = M.part("LowerArmR", (cx - 25, -25, 56), (cx + 26, 26, 188), pivot=(cx, 0, ELBOW_Z), parent="UpperArmR")
    G = D.g()
    X, Y, Z = G
    D.add(fv.cyl(G, "z", (cx, 0), 20, rng=(140, 186)), 1)            # D1 몸통
    D.add(fv.cyl(G, "z", (cx, 0), 14, rng=(186, 187)), 3)            # 뒤 마개
    for z0 in (174, 150):                                             # 황동 띠 2줄(2칸 돋움)
        D.add(fv.cyl(G, "z", (cx, 0), 22, rng=(z0, z0 + 5)) & ~fv.cyl(G, "z", (cx, 0), 20), 5)
        D.add(fv.box(G, x=(cx - 3, cx + 3), y=(-23, -21), z=(z0 + 2, z0 + 3)), 8)   # 앞쪽 발광 틈
    D.groove(fv.box(G, z=(162, 162)) & fv.cyl(G, "z", (cx, 0), 21), 4)
    # D2 원뿔 7단: 단마다 위가 넓고 아래가 좁은 짧은 원뿔(계단), 위 테 황동
    r_top = 18.0
    for i in range(7):
        zt = 140 - 10 * i; zb = zt - 10
        rr = r_top - 2.2 * i
        k = (Z - zb) / 10.0
        rad = (rr - 3.6) + 3.6 * k                                       # 단마다 3.6칸 계단
        dist = np.sqrt((X - cx) ** 2 + Y ** 2)
        tier = (Z <= zt - 1) & (Z >= zb) & (dist <= rad + 0.25)
        D.add(tier, 3)                                                   # 짙은 강철(프레임색)
        D.paint(tier & (Z >= zt - 2), 5)
        if i in (1, 3, 5):
            D.add((np.abs(X - cx) <= 1) & (Y <= -(rr - 2.5)) & (Y >= -(rr - 0.5)) & (Z >= zb + 3) & (Z <= zb + 5), 8)
    dist = np.sqrt((X - cx) ** 2 + Y ** 2)
    D.add((Z < 70) & (Z >= 58) & (dist <= 3.2 * (Z - 58) / 12.0 + 0.25), 7)   # 끝
    D.trim()
    return D


def build_claw(M):
    cx = ARM_X
    C = M.part("LowerArmL", (cx - 32, -32, 72), (cx + 33, 33, 188), pivot=(cx, 0, ELBOW_Z), parent="UpperArmL")
    G = C.g()
    X, Y, Z = G
    C.add(fv.cyl(G, "z", (cx, 0), 19, rng=(140, 186)), 1)            # C1 케이지 원통
    C.add(fv.cyl(G, "z", (cx, 0), 13, rng=(186, 187)), 3)
    for z0 in (180, 163, 146):                                        # 돋운 황동 고리 3줄
        C.add(fv.cyl(G, "z", (cx, 0), 21, rng=(z0, z0 + 2)) & ~fv.cyl(G, "z", (cx, 0), 19), 5)
    ang = np.arctan2(Y, X - cx)
    dist = np.sqrt((X - cx) ** 2 + Y ** 2)
    for kk in range(8):                                               # 세로 끈 8줄(1칸 돋움)
        a0 = kk * np.pi / 4
        da = np.abs((ang - a0 + np.pi) % (2 * np.pi) - np.pi)
        C.add((da * 20 <= 1.6) & (dist > 19.2) & (dist <= 20.6) & (Z >= 142) & (Z <= 184), 5)
    C.add(fv.cbox(G, (cx - 13, cx + 13), (-13, 13), (126, 140), ch={"xy": 4, "-zx": 3, "-zy": 3}), 3)   # C2 주먹
    # C4 가운데 포신(아래로) + 황동 포구 테 + 구멍
    C.add(fv.cyl(G, "z", (cx, 0), 5, rng=(110, 126)), 7)
    C.add(fv.cyl(G, "z", (cx, 0), 6.5, rng=(110, 112)), 5)
    C.cut(fv.cyl(G, "z", (cx, 0), 2.5, rng=(108, 116)))
    C.add(fv.cyl(G, "z", (cx, 0), 2.5, rng=(116, 116)), 4)
    # C3 집게 3갈래(앞·뒤좌·뒤우), 2마디: 주먹 테 → 바깥 아래 → 안쪽 끝
    for th in (-np.pi / 2, np.pi / 2 + np.pi / 3, np.pi / 2 - np.pi / 3):
        ux, uy = np.cos(th), np.sin(th)
        p0 = (cx + 12 * ux, 12 * uy, 131)
        p1 = (cx + 23 * ux, 23 * uy, 104)
        p2 = (cx + 9 * ux, 9 * uy, 80)
        seg1 = r3.capsule(G, p0, p1, 4.6)
        seg2 = r3.capsule(G, p1, p2, 3.4)
        C.add((seg1 | seg2) & ~(C.a > 0), 5)
        C.paint(r3.capsule(G, p1, p2, 3.4) & (Z <= 88), 7)          # 끝 강철
        C.add((((X - p1[0]) ** 2 + (Y - p1[1]) ** 2 + (Z - p1[2]) ** 2) <= 5.4 ** 2 + 0.25) & ~(C.a > 0), 3)   # 마디
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
    specs = [(-30, 6, PAL, EMISSIVE, "r5 앞 3/4"), (0, 4, PAL, EMISSIVE, "r5 정면"), (90, 2, PAL, EMISSIVE, "r5 옆"),
             (150, 10, PAL, EMISSIVE, "r5 뒤 3/4"), (-30, 6, PAL_ULT, EMISSIVE_ULT, "궁극기 발광")]
    ims = [vp.render(B, pal, em, yaw=y, pitch=p, ppc=2.6, ss=2, ao_amt=0.5) for y, p, pal, em, _ in specs]
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "CETUS", "concept_v1_GPT_후보.png")).convert("RGB").crop((0, 100, 1229, 960))
    H = ims[0].height
    con = con.resize((int(con.width * H / con.height), H), Image.LANCZOS)
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    W = con.width + sum(i.width for i in ims) + 16 * len(ims)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in [(con, "컨셉")] + list(zip(ims, [s[4] for s in specs])):
        sh.paste(im, (x, 0)); d.text((x + 8, H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_r5_compare.png")); print(sh.size)
