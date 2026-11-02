"""HT-02 CETUS — r4 = 헬멧·가슴 r3b(확정) + 어깨 r1 (2026-11-02)

어깨 읽기: mech/docs/레퍼런스/CETUS/윤곽읽기_r3_어깨.png · 결정기록 5-5·다음 세션 시작점
- 좌우 공통: 청록 돔 + 위(안쪽) 뼈색 띠 + 아래 뼈색 테(황동 가는 테두리), 좌우 같은 크기
- 오른쪽만: R4 바깥 황동 마개 · 왼쪽만: L4 아래 안쪽 황동 죔쇠, L5 둥근 창(발광 없음), L6 바깥 큰 호스 고리
- R5 오른 어깨 안쪽 호스 = 팔 단계에서
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import cetus_r3 as base  # noqa: E402

PAL, EMISSIVE = base.PAL, base.EMISSIVE
SH_X, SH_Z, SH_R = 50, 223, (25, 24, 26)     # 어깨 돔 중심 |x| · z, 반지름


def shell_band(G, c, n, lo, hi):
    """돔 중심 c 에서 방향 n 으로 잰 거리가 lo~hi 인 띠(어깨 위 띠·아래 테에 씀)."""
    X, Y, Z = G
    n = np.asarray(n, float); n /= np.linalg.norm(n)
    d = n[0] * (X - c[0]) + n[1] * (Y - c[1]) + n[2] * (Z - c[2])
    return (d >= lo) & (d <= hi)


def build_shoulder(M, side):
    """side = +1 왼쪽(+X) · -1 오른쪽."""
    name = "ShoulderL" if side > 0 else "ShoulderR"
    cx = side * SH_X
    lo = (cx - 50, -36, 180) if side > 0 else (cx - 32, -36, 180)
    hi = (cx + 52, 34, 256) if side > 0 else (cx + 33, 34, 256)
    S = M.part(name, lo, hi, pivot=(side * 42, 0, 216), parent="Torso")
    G = S.g()
    X, Y, Z = G
    c = (cx, 0, SH_Z)
    dome = fv.ell(G, c, SH_R) & fv.box(G, z=(201, 260))
    S.add(dome, 1)
    S.add(fv.cyl(G, "z", (cx, 0), 15, rng=(192, 201)), 3)          # 아래 어깨 관절 받침(짙은 프레임)
    solid = S.a > 0
    out1 = fv.ell(G, c, (SH_R[0] + 1.6, SH_R[1] + 1.6, SH_R[2] + 1.6)) & ~solid
    # 위(안쪽) 뼈색 띠: 안쪽·위를 향한 축 둘레 고리 → 앞에서 뒤로 정수리 안쪽을 가로지르는 띠
    top_n = (-side * 0.55, 0, 0.83)
    band_top = shell_band(G, c, top_n, 13, 20) & out1
    S.add(band_top, 2)
    S.paint(band_top & (shell_band(G, c, top_n, 13, 14) | shell_band(G, c, top_n, 19, 20)), 5)
    # 아래 뼈색 테: 돔 아래 가장자리 둘레(바깥·앞쪽이 두껍게 보이도록 바깥쪽으로 1칸)
    rim = fv.box(G, z=(201, 207)) & out1
    S.add(rim, 2)
    S.paint(rim & fv.box(G, z=(201, 201)), 5)
    S.paint(rim & fv.box(G, z=(207, 207)), 5)
    if side < 0:
        # R4 바깥 황동 마개(x 축 원통 + 짙은 가운데)
        S.add(fv.cyl(G, "x", (0, 223), 4.5, rng=(cx - 29, cx - 24)), 5)
        S.add(fv.cyl(G, "x", (0, 223), 2, rng=(cx - 30, cx - 29)), 3)
    else:
        # L4 아래 안쪽·앞 황동 죔쇠(겉면에 2칸 돋움) + 볼트
        clamp = fv.box(G, x=(cx - 22, cx - 10), y=(-30, -14), z=(207, 213))
        S.emboss(clamp, 5, h=2)
        S.add(fv.box(G, x=(cx - 17, cx - 15), y=(-30, -26), z=(209, 211)) & ~(S.a > 0), 3)
        # L5 둥근 창: 앞·바깥·위 방향 겉면, 황동 테 + 안으로 들어간 어두운 유리(발광 없음)
        dvec = np.array([0.55, -0.72, 0.42]); dvec /= np.linalg.norm(dvec)
        p0 = np.array(c, float) + dvec * 24.5
        s = (X - p0[0]) * dvec[0] + (Y - p0[1]) * dvec[1] + (Z - p0[2]) * dvec[2]
        rx, ry, rz = X - p0[0] - s * dvec[0], Y - p0[1] - s * dvec[1], Z - p0[2] - s * dvec[2]
        rad = np.sqrt(rx ** 2 + ry ** 2 + rz ** 2)
        S.cut((rad <= 4.5) & (s >= -3) & (s <= 3))
        S.add((rad <= 4.5) & (s >= -3) & (s <= -2), 4)
        S.add((rad > 4.5) & (rad <= 7) & (s >= -1.5) & (s <= 1.5), 5)
        # L6 바깥 큰 호스 고리(옆·약간 뒤): 어깨 바깥 위에서 나와 고리 → 아래에서 다시 들어감
        path = [(cx + 22, 5, 230), (cx + 33, 7, 236), (cx + 41, 7, 228), (cx + 42, 7, 210), (cx + 36, 5, 198), (cx + 24, 3, 195)]
        tube = None
        for a, b in zip(path[:-1], path[1:]):
            t = base.capsule(G, a, b, 4)
            tube = t if tube is None else (tube | t)
        tube &= ~(S.a > 0)
        S.add(tube, 3)
        for (px, py, pz) in (path[0], path[-1]):
            S.paint(tube & (((X - px) ** 2 + (Y - py) ** 2 + (Z - pz) ** 2) <= 30), 5)   # 끝 황동 고리
    S.trim()
    return S


def build_all():
    M = base.build_all()
    build_shoulder(M, +1)
    build_shoulder(M, -1)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    M = build_all()
    for n, p in M.parts.items():
        print(n, p.count())
    B = M.blocks()
    ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=3.6, ss=2, ao_amt=0.5) for y, p in ((-30, 6), (0, 4), (90, 2), (150, 10))]
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "CETUS", "concept_v1_GPT_후보.png")).convert("RGB").crop((290, 110, 1140, 560))
    H = ims[0].height
    con = con.resize((int(con.width * H / con.height), H), Image.LANCZOS)
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    W = con.width + sum(i.width for i in ims) + 20 * len(ims)
    sh = Image.new("RGB", (W, H + 50), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in [(con, "컨셉")] + list(zip(ims, ["r4 앞 3/4", "r4 정면", "r4 옆", "r4 뒤 3/4"])):
        sh.paste(im, (x, 0)); d.text((x + 10, H + 12), t, fill=(220, 220, 220), font=f); x += im.width + 20
    sh.save(os.path.join(out, "cetus_r4_compare.png")); print(sh.size)
