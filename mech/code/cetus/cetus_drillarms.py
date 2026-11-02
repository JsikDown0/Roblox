"""HT-02 CETUS — 드릴 팔 전체 비교안 1~5 (2026-11-02, 유저 "드릴 팔 전체를 말하는 거야")

위팔·팔꿈치·아래팔·드릴을 통째로 바꾼 5안. 머리·가슴·어깨(확정)와 왼팔(r7 그물 집게)은 공통.
궁극기 발광 = 색 8(평소 꺼진 짙은 호박 유리), 늘 오목한 곳에만. R5 호스 1줄(위팔 뒤)은 다섯 안 모두 유지.
1 컨셉형 깔때기 — 둥근 팔꿈치 공 → 아래로 벌어지는 큰 청록 몸통(황동 띠 3, 띠 사이 발광 창 6) → 짙은 계단 원뿔 6단
2 ref1 노출 프레임 — 짧은 위팔 → 받침판 + 피스톤 기둥 2 + 가운데 축이 보이는 뼈대 → 낮은 모터 북 + 감긴 관 → 나선 계단 드릴
3 건틀릿 + 쥔 드릴 — 각진 청록 건틀릿(바깥 뼈색 V 판) → 짙은 주먹이 손잡이를 쥠 → 가늘고 긴 드릴 5단
4 잠수복 주름 관절 — 위팔·팔꿈치가 고무 주름관 → 헬멧을 닮은 둥근 돔 하우징(현창 2) → 원뿔 5단
5 각진 굴착기 — 각진 위팔 → 긴 팔각 하우징(윗면 뼈색 테, 앞 환기 홈 = 궁극기 발광) + 등 쪽 배기통 2 → 짧고 넓은 원뿔 4단
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
import cetus_r6 as r6  # noqa: E402
import cetus_r7 as r7  # noqa: E402

PAL, EMISSIVE, PAL_ULT, EMISSIVE_ULT = r6.PAL, r6.EMISSIVE, r6.PAL_ULT, r6.EMISSIVE_ULT
cu = -r6.UP_X          # 위팔 축 x (−54)
cx = r6.DRILL_X        # 아래팔·드릴 축 x (−58)
EZ = r6.ELBOW_Z


# ---------------------------------------------------------------- 공통 도우미
def upper_part(M):
    U = M.part("UpperArmR", (cu - 34, -30, 160), (cu + 34, 34, 212), pivot=(-50, 0, 203), parent="Torso")
    return U, U.g()


def lower_part(M):
    D = M.part("LowerArmR", (cx - 46, -46, 20), (cx + 46, 50, 222), pivot=(cx, 0, EZ), parent="UpperArmR")
    G = D.g(); X, Y, Z = G
    return D, G, X, Y, Z, np.sqrt((X - cx) ** 2 + Y ** 2), np.arctan2(Y, X - cx)


def hose_r5(U, G):
    """R5 호스 1줄: 위팔 윗부분 안쪽 뒤에서 나와 위팔 옆을 따라 아래팔 뒤로."""
    path = [(cu + 7, 6, 200), (cu + 13, 15, 192), (cu + 9, 20, 181), (cu + 4, 21, 170)]
    t = r6.path_tube(G, path, 3.5) & ~(U.a > 0)
    U.add(t, 3)
    U.paint(t & fv.box(G, z=(186, 187)), 5)


def cable(D, G, end):
    """동력선 1줄: 어깨 뒤 위 → 바깥으로 휘어 → end(아래팔 바깥 뒤)."""
    pts = [(cx + 34, 34, 208), (cx + 14, 40, 204), (cx - 8, 36, 196), (cx - 22, 24, 186), end]
    t = r6.path_tube(G, pts, 4.5) & ~(D.a > 0)
    D.add(t, 3)
    for c in pts[1:4]:
        D.paint(t & r6.ball(G, c, 5.5), 5)


def tiers(D, Z, dist, top, rrs, h, step, c=3):
    """위가 넓고 아래가 좁은 계단 원뿔. rrs = 단마다 윗반지름, step = 단 안에서 줄어드는 칸(단 사이 감소보다 커야 턱이 생김)."""
    for i, rr in enumerate(rrs):
        zt = top - h * i; zb = zt - h + 1
        rad = np.maximum((rr - step) + step * (Z - zb) / (h - 1), 2.5)
        D.add((Z >= zb) & (Z <= zt) & (dist <= rad + 0.25), c)
    return top - h * len(rrs)


def tip(D, Z, dist, z0, r=5.5, h=12):
    D.add((Z <= z0) & (Z >= z0 - h) & (dist <= r * (Z - (z0 - h)) / h + 0.25), 7)


def seam(D, G, z, r_out, r_in):
    """궁극기 발광 이음새 고리(오목): 바깥 r_out 보다 안쪽에서만 빛남."""
    D.add(fv.cyl(G, "z", (cx, 0), r_out - 2, rng=(z, z + 1)) & ~fv.cyl(G, "z", (cx, 0), r_in), 8)
    D.add(fv.cyl(G, "z", (cx, 0), r_in, rng=(z, z + 1)), 3)


# ---------------------------------------------------------------- 1 컨셉형 깔때기
def arm_1(M):
    U, G = upper_part(M); X, Y, Z = G
    U.add(fv.cyl(G, "z", (cu, 0), 13, rng=(182, 202)), 3)
    U.add(fv.cyl(G, "z", (cu, 0), 14.5, rng=(193, 196)), 5)
    U.add(r6.ball(G, (cu, 0, 180), 15), 3)                                  # 팔꿈치 공
    hose_r5(U, G); U.trim()

    D, G, X, Y, Z, dist, ang = lower_part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 17, rng=(168, 178)), 3)                   # 팔꿈치 받이
    z0, z1, ra, rb = 172, 128, 23.0, 31.0                                    # 아래로 벌어지는 몸통
    rbody = ra + (rb - ra) * (z0 - Z) / (z0 - z1)
    D.add((Z >= z1) & (Z <= z0) & (dist <= rbody + 0.25), 1)
    for zb in (168, 148, 128):                                               # 황동 띠 3(2칸 돋움)
        D.add((Z >= zb) & (Z <= zb + 4) & (dist <= rbody + 2.25) & (dist > rbody - 0.5), 5)
    for zw in (155,):                                                        # 띠 사이 발광 창 6(1칸 오목)
        sect = np.abs(((ang * 6 / (2 * np.pi)) % 1) - 0.5) < 0.18
        w = sect & (Z >= zw - 3) & (Z <= zw + 3) & (dist > rbody - 1.5) & (dist <= rbody + 0.25)
        D.cut(w & (dist > rbody - 0.5)); D.paint(w, 8)
    end = tiers(D, Z, dist, 127, [29, 25, 21, 17, 13, 9], 12, 7)
    tip(D, Z, dist, end, r=6)
    cable(D, G, (cx - 22, 10, 170))
    D.trim()


# ---------------------------------------------------------------- 2 ref1 노출 프레임 + 나선 계단 드릴
def arm_2(M):
    U, G = upper_part(M); X, Y, Z = G
    U.add(fv.cyl(G, "z", (cu, 0), 12, rng=(181, 202)), 3)
    U.add(fv.cyl(G, "z", (cu, 0), 14, rng=(181, 185)), 5)
    hose_r5(U, G); U.trim()

    D, G, X, Y, Z, dist, ang = lower_part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 19, rng=(174, 180)), 3)                   # 받침판
    D.add(fv.cyl(G, "z", (cx, 0), 8, rng=(150, 174)), 3)                    # 가운데 축
    for sy in (-14, 14):                                                     # 피스톤 기둥 2(앞·뒤)
        D.add(fv.cyl(G, "z", (cx, sy), 4.5, rng=(150, 174)), 7)
        D.add(fv.cyl(G, "z", (cx, sy), 5.5, rng=(160, 163)), 5)
    seam(D, G, 152, 24, 20)
    D.add(fv.cyl(G, "z", (cx, 0), 27, rng=(126, 150)), 1)                   # 낮은 모터 북
    D.add(fv.cyl(G, "z", (cx, 0), 29, rng=(147, 150)), 5)
    D.add(fv.cyl(G, "z", (cx, 0), 29, rng=(126, 129)), 5)
    th = np.linspace(0, 2 * np.pi * 1.25, 40)                               # 북을 감는 관 1¼바퀴
    coil = [(cx + 30 * np.cos(a + 0.6), 30 * np.sin(a + 0.6), 145 - 13 * a / (2 * np.pi)) for a in th]
    t = r6.path_tube(G, coil, 3.2) & ~(D.a > 0)
    D.add(t, 3)
    for k in (8, 22, 36):
        D.paint(t & r6.ball(G, coil[k], 4.2), 5)
    # 나선 계단 드릴(ref1): 반지름이 나선을 따라 톱니처럼 꺾임 → 감아 올라가는 턱
    z0, z1, p = 125, 52, 12.0
    s = np.clip((Z - z1) / (z0 - z1), 0, 1)
    R = 6 + 20 * s
    frac = (((Z - z1) + p * ang / (2 * np.pi)) / p) % 1.0
    rad = R - 4.5 * (1 - frac)
    drill = (Z >= z1) & (Z <= z0) & (dist <= rad + 0.25)
    D.add(drill, 3)
    D.paint(drill & (frac > 0.82) & (dist > rad - 1.5), 7)                  # 턱 끝만 강철
    tip(D, Z, dist, z1, r=6)
    cable(D, G, (cx - 24, 12, 150))
    D.trim()


# ---------------------------------------------------------------- 3 건틀릿 + 쥔 드릴
def arm_3(M):
    U, G = upper_part(M); X, Y, Z = G
    U.add(fv.cyl(G, "z", (cu, 0), 13, rng=(182, 202)), 3)
    U.add(fv.cyl(G, "z", (cu, 0), 14.5, rng=(186, 189)), 5)
    hose_r5(U, G); U.trim()

    D, G, X, Y, Z, dist, ang = lower_part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 15, rng=(176, 184)), 3)
    D.add(fv.cbox(G, (cx - 20, cx + 20), (-20, 20), (148, 178), ch={"xy": 7, "+zx": 3, "+zy": 3}), 1)
    D.add(fv.cbox(G, (cx - 24, cx + 24), (-24, 24), (134, 150), ch={"xy": 9}), 1)   # 벌어진 손목 덮개
    D.add(fv.cbox(G, (cx - 25, cx + 25), (-25, 25), (147, 150), ch={"xy": 9}) & ~(D.a > 0), 5)
    vee = [(-14, 176), (-7, 176), (0, 163), (7, 176), (14, 176), (0, 153)]  # 바깥 옆 뼈색 V 판(가슴 갈매기 메아리)
    D.add(fv.poly(G, "x", vee, rng=(cx - 23, cx - 20)) & (Z >= 152), 2)
    D.add(fv.cbox(G, (cx - 16, cx + 16), (-17, 16), (120, 134), ch={"xy": 4, "-zx": 3, "-zy": 3}), 3)   # 주먹
    for k in range(4):                                                       # 앞 손가락 마디 4
        D.add(fv.cbox(G, (cx - 14 + 7 * k, cx - 9 + 7 * k), (-20, -15), (121, 132), ch={"-yz": 2}), 3)
    D.add(fv.cbox(G, (cx + 15, cx + 19), (-12, 4), (122, 131), ch={"+xz": 2}), 3)   # 엄지(안쪽)
    D.add(fv.cyl(G, "z", (cx, 0), 12, rng=(115, 120)), 5)                   # 손잡이 목
    seam(D, G, 113, 13, 9)
    D.add(fv.cyl(G, "z", (cx, 0), 12, rng=(107, 112)), 5)
    end = tiers(D, Z, dist, 106, [19, 16, 13, 10, 7], 12, 6)
    tip(D, Z, dist, end, r=4.5, h=11)
    cable(D, G, (cx - 21, 10, 166))
    D.trim()


# ---------------------------------------------------------------- 4 잠수복 주름 관절 + 돔 하우징
def bellows(G, c, z0, z1, r_lo, r_hi):
    X, Y, Z = G
    d = np.sqrt((X - c) ** 2 + Y ** 2)
    rad = np.where(((Z // 2) % 2) == 0, r_hi, r_lo)
    return (Z >= z0) & (Z <= z1) & (d <= rad + 0.25)


def arm_4(M):
    U, G = upper_part(M); X, Y, Z = G
    U.add(bellows(G, cu, 180, 199, 12, 14), 3)                               # 고무 주름관 위팔
    U.add(fv.cyl(G, "z", (cu, 0), 15.5, rng=(199, 203)), 5)
    hose_r5(U, G); U.trim()

    D, G, X, Y, Z, dist, ang = lower_part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 15.5, rng=(175, 179)), 5)
    D.add(bellows(G, cx, 162, 175, 12, 14), 3)                               # 팔꿈치 주름관
    dome = fv.ell(G, (cx, 0, 136), (30, 30, 28)) & (Z >= 124)
    D.add(dome, 1)                                                           # 헬멧을 닮은 돔 하우징
    D.add(fv.cyl(G, "z", (cx, 0), 31, rng=(120, 125)), 5)
    D.add(fv.ell(G, (cx, 0, 136), (31, 31, 29)) & (Z >= 158) & (Z <= 160) & ~dome, 5)   # 돔 위 황동 테
    for axis, c3 in (("x", (cx - 27, 0, 142)), ("y", (cx, -27, 142))):     # 현창 2(바깥 옆·앞), 유리 = 색 8
        if axis == "x":
            ring = fv.cyl(G, "x", (0, 142), 9, rng=(cx - 33, cx - 22)); glass = fv.cyl(G, "x", (0, 142), 6, rng=(cx - 33, cx - 22))
        else:
            ring = fv.cyl(G, "y", (cx, 142), 9, rng=(-33, -22)); glass = fv.cyl(G, "y", (cx, 142), 6, rng=(-33, -22))
        rim = ring & ~glass & (fv.ell(G, (cx, 0, 136), (32, 32, 30))) & ~fv.ell(G, (cx, 0, 136), (28, 28, 26))
        D.add(rim, 5)
        D.cut(glass & ~fv.ell(G, (cx, 0, 136), (28.5, 28.5, 26.5)))
        D.paint(glass & ~fv.ell(G, (cx, 0, 136), (27.5, 27.5, 25.5)), 8)
    end = tiers(D, Z, dist, 119, [25, 20, 15, 10, 6], 12, 8)
    tip(D, Z, dist, end, r=5)
    cable(D, G, (cx - 16, 8, 160))
    D.trim()


# ---------------------------------------------------------------- 5 각진 굴착기 + 배기통
def arm_5(M):
    U, G = upper_part(M); X, Y, Z = G
    U.add(fv.cbox(G, (cu - 14, cu + 14), (-14, 14), (180, 202), ch={"xy": 5}), 1)
    U.add(fv.cbox(G, (cu - 15, cu + 15), (-15, 15), (189, 192), ch={"xy": 5}), 5)
    hose_r5(U, G); U.trim()

    D, G, X, Y, Z, dist, ang = lower_part(M)
    D.add(fv.cyl(G, "z", (cx, 0), 14, rng=(176, 184)), 3)
    house = fv.cbox(G, (cx - 25, cx + 25), (-27, 25), (118, 178), ch={"xy": 10, "-zx": 5, "-zy": 5, "+zx": 4, "+zy": 4})
    D.add(house, 1)
    D.add(fv.cbox(G, (cx - 26, cx + 26), (-28, 26), (118, 122), ch={"xy": 10, "-zx": 3, "-zy": 3}), 5)
    D.add(fv.cbox(G, (cx - 26, cx + 26), (-28, 26), (170, 173), ch={"xy": 10}) & ~(D.a > 0), 5)
    for zg in range(142, 167, 5):                                            # 앞 환기 홈 5줄 = 궁극기 발광(오목)
        g = fv.box(G, x=(cx - 12, cx + 12), y=(-28, -26), z=(zg, zg + 1))
        D.cut(g & (Y <= -27)); D.paint(g, 8)
    D.paint(house & (Z >= 174), 2)                                           # 윗면 뼈색 테(어깨 띠 메아리)
    for sx in (-10, 10):                                                     # 배기통 2(등 쪽, 위로)
        D.add(fv.cyl(G, "z", (cx + sx, 29), 4.5, rng=(132, 214)), 3)
        D.add(fv.cyl(G, "z", (cx + sx, 29), 5.5, rng=(208, 213)), 5)
        D.add(fv.cyl(G, "z", (cx + sx, 29), 5.5, rng=(150, 152)), 5)
        D.cut(fv.cyl(G, "z", (cx + sx, 29), 2.5, rng=(206, 214)))
        D.add(fv.cyl(G, "z", (cx + sx, 29), 2.5, rng=(206, 206)), 4)
    end = tiers(D, Z, dist, 117, [26, 21, 16, 11], 12, 8)
    tip(D, Z, dist, end, r=6.5)
    D.trim()


VARIANTS = [("1", "컨셉형 깔때기", arm_1), ("2", "노출 프레임+나선 드릴", arm_2), ("3", "건틀릿+쥔 드릴", arm_3),
            ("4", "잠수복 주름관+돔", arm_4), ("5", "각진 굴착기+배기통", arm_5)]


def build_all(which="1"):
    M = r4.build_all()
    r6.build_upper(M, +1)
    dict((v[0], v[2]) for v in VARIANTS)[which](M)
    r7.build_claw(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    only = sys.argv[2] if len(sys.argv) > 2 else None
    cols = []
    for key, label, fn in VARIANTS:
        if only and key not in only:
            continue
        M = build_all(key)
        for n in ("UpperArmR", "LowerArmR"):
            p = M.parts[n]; _, k = ndimage.label(p.a > 0)
            print(key, n, p.count(), "섬", k - 1)
        B = M.blocks()
        a = vp.render(B, PAL, EMISSIVE, yaw=-35, pitch=6, ppc=2.6, ss=2, ao_amt=0.5)
        b = vp.render(B, PAL, EMISSIVE, yaw=-90, pitch=2, ppc=2.6, ss=2, ao_amt=0.5)
        c = vp.render(B, PAL_ULT, EMISSIVE_ULT, yaw=-35, pitch=6, ppc=1.3, ss=2, ao_amt=0.5)
        cols.append((key + " " + label, a, b, c))
    ha = max(c_[1].height for c_ in cols); hb = max(c_[2].height for c_ in cols)
    W = sum(max(c_[1].width, c_[2].width) for c_ in cols) + 16 * len(cols)
    sh = Image.new("RGB", (W, ha + hb + 60), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for lab, a, b, c in cols:
        w = max(a.width, b.width)
        d.text((x + 8, 8), lab, fill=(230, 230, 230), font=f)
        sh.paste(a, (x, 46)); sh.paste(b, (x, 46 + ha + 10))
        sh.paste(c, (x + w - c.width, 46 + ha + 10 + hb - c.height))
        x += w + 16
    sh.save(os.path.join(out, "cetus_drillarms_compare.png")); print(sh.size)
