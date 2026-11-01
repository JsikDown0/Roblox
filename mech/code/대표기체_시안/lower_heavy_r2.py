"""
lower_heavy.py — r2 하체 리메이크: 청회색 개틀링 중장갑 레퍼런스 양식 (2026-10-26)

상체 확정: 머리 U2(뿔 20) + 흉부 안 1(H1) + 허리 W2(층층 배 장갑, 옆구리 제외) = waist_v1.build("W2 ...").
하체 양식(레퍼런스 분석):
  - 관절이 '드러난 둥근 기계'(허리·무릎·발목 옆에 큰 원판 허브 + 가운데 구멍) — 장갑판과 기계가 번갈아 보임.
  - 판은 모서리를 깎은 큰 육각 판, 안쪽 판 테두리 홈(2단 판), 모서리에 작은 주황 표식 몇 개(발광 아님).
  - 허벅지는 짧고 두껍게 장갑, 무릎 보호대가 크게 앞으로 튀어나옴.
  - 정강이는 아래로 갈수록 넓어지는 코끼리 다리(앞뒤·좌우 모두 벌어짐), 아래쪽 앞면에 주황 열 배출구.
  - 발은 낮고 넓게, 발끝은 두 덩어리로 갈라진 블록 + 뒤꿈치 블록.
  - 골반 옆 큰 육각 장갑(허벅지 윗부분을 덮음), 앞 스커트도 큰 육각 판.
관절 피벗(HIP/KNEE/ANKLE)·파트 이름·부모는 r2 그대로(리깅·자세 코드 재사용).
"""
import numpy as np

import flag_vox as fv
import flagship_heavy as fh
from flag_vox import box, cbox, poly, cyl
import waist_v1 as wv

HIP, KNEE, ANKLE = fh.HIP, fh.KNEE, fh.ANKLE        # (24,0,142) (24,-2,92) (26,0,22)
LOWER = ("UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR")


def hub(p, G, axis_x0, axis_x1, c, r, col=7, bore=True):
    """x 축 원판 허브(드러난 관절): 테두리 금속 + 가운데 짙은 구멍."""
    p.add(cyl(G, "x", c, r, (axis_x0, axis_x1)), col)
    if bore:
        x_out = axis_x1 if axis_x1 > axis_x0 else axis_x0
        p.cut(cyl(G, "x", c, r * 0.45, (x_out - 1.5, x_out)))
        p.add(cyl(G, "x", c, r * 0.45, (x_out - 2.5, x_out - 1.5)), 4)
        p.add(cyl(G, "x", c, r * 0.7, (x_out - 0.6, x_out)) & ~cyl(G, "x", c, r * 0.55, (x_out - 0.6, x_out)), 3)


def inset(p, G, region_outer, region_inner, col=2):
    p.paint_s(region_outer & ~region_inner, col)


def build_skirts(M):
    # 앞 스커트: 큰 육각 판(위가 넓고 아래 모서리 깎음), 살짝 앞으로 들림
    f = M.part("SkirtFL", (2, -42, 118), (36, -16, 174), pivot=(18, -28, 170), parent="Pelvis")
    G = f.g(); X, Y, Z = G
    pl = poly(G, "y", [(6, 170), (31, 170), (31, 144), (25, 130), (12, 130), (6, 140)], rng=(-35, -27))
    f.add(pl, 1)
    f.add(poly(G, "y", [(8, 168), (29, 168), (29, 146), (24, 133), (13, 133), (8, 142)], rng=(-27, -24)), 3)
    inner = poly(G, "y", [(7.4, 168.6), (29.6, 168.6), (29.6, 145), (24.2, 131.8), (12.8, 131.8), (7.4, 141)])
    inset(f, G, pl & (Y <= -33), inner)
    f.paint(pl & (Y <= -34) & (X >= 24) & (X <= 29) & (Z >= 131) & (Z <= 133.5), 5)       # 작은 주황 표식
    f.rot = fv.rotx(12)
    # 옆 골반 장갑: 큰 육각 판(허벅지 윗부분 덮음), 아래가 바깥으로 벌어짐
    s = M.part("SkirtSL", (30, -30, 106), (52, 30, 176), pivot=(36, 0, 172), parent="Pelvis")
    G = s.g(); X, Y, Z = G
    sp = poly(G, "x", [(-20, 172), (20, 172), (24, 160), (24, 128), (16, 114), (-16, 114), (-24, 128), (-24, 160)],
              rng=(38, 45))
    s.add(sp, 1)
    s.add(poly(G, "x", [(-16, 170), (16, 170), (20, 158), (20, 130), (13, 118), (-13, 118), (-20, 130), (-20, 158)],
               rng=(34, 38)), 3)
    inner = poly(G, "x", [(-18.6, 170.6), (18.6, 170.6), (22.6, 159), (22.6, 129), (15, 115.6), (-15, 115.6), (-22.6, 129), (-22.6, 159)])
    inset(s, G, sp & (X >= 43.5), inner)
    s.paint(sp & (X >= 44) & (Y >= -20) & (Y <= -15) & (Z >= 119) & (Z <= 122), 5)
    s.rot = fv.roty(14)
    M.mirror("SkirtFL", "SkirtFR", "Pelvis")
    M.mirror("SkirtSL", "SkirtSR", "Pelvis")


def build_legs(M):
    # ---- 허벅지
    t = M.part("UpperLegL", (0, -32, 92), (50, 28, 160), pivot=HIP, parent="Pelvis")
    G = t.g(); X, Y, Z = G
    t.add(cyl(G, "x", (0, 142), 12, (10, 38)), 3)                                   # 엉덩이 관절통
    hub(t, G, 38, 43, (0, 142), 9)
    t.add(cbox(G, (10, 38), (-15, 15), (100, 136), {"xy": 4}), 3)                   # 허벅지 뼈대
    tf = cbox(G, (8, 40), (-24, -11), (102, 132), {"x-y": (6, 6), "-z-y": (6, 5), "+z-y": (4, 4)})
    t.add(tf, 1)                                                                     # 앞 육각 판
    inset(t, G, tf & (Y <= -22), cbox(G, (10.6, 37.4), (-30, 0), (104.6, 130), {"x-y": (5, 5)}))
    to = cbox(G, (36, 45), (-14, 14), (104, 130), {"+x-y": (3, 3), "+x+y": (3, 3), "+x-z": (4, 4)})
    t.add(to, 1)                                                                     # 바깥 판
    t.add(cbox(G, (12, 36), (12, 21), (104, 132), {"x+y": (4, 4)}), 2)             # 뒤 판
    # ---- 무릎·정강이
    s = M.part("LowerLegL", (-6, -44, 14), (54, 40, 120), pivot=KNEE, parent="UpperLegL")
    G = s.g(); X, Y, Z = G
    s.add(cyl(G, "x", (-2, 92), 11, (10, 38)), 3)                                   # 무릎 관절통
    hub(s, G, 38, 44, (-2, 92), 8.5)
    # 정강이: 아래로 넓어지는 코끼리 다리(앞에서 사다리꼴 ∩ 옆에서 사다리꼴)
    front = poly(G, "y", [(11, 84), (37, 84), (45, 36), (45, 30), (3, 30), (3, 36)])
    side = poly(G, "x", [(-21, 84), (20, 84), (27, 30), (-29, 30)])
    shin = front & side
    edge = (np.minimum(X - 3 - (84 - Z) * 0.0, 45 - X) + 0 * Y)
    # 앞 세로 모서리 모따기(45°): 앞면에서 바깥·안쪽 모서리 깎기
    yfront = -21 - (84 - np.clip(Z, 30, 84)) * (8.0 / 54.0)
    xl = 11 - (84 - np.clip(Z, 30, 84)) * (8.0 / 54.0)
    xr = 37 + (84 - np.clip(Z, 30, 84)) * (8.0 / 54.0)
    cham = ((Y - yfront) + (X - xl) >= 4) & ((Y - yfront) + (xr - X) >= 4)
    s.add(shin & cham, 1)
    s.paint(shin & cham & (Y >= 12), 2)                                              # 종아리 뒤쪽 짙게
    # 앞 정강이 판 테두리 홈(2단 판)
    inner = poly(G, "y", [(13, 82), (35, 82), (40.5, 57), (7.5, 57)])
    inset(s, G, shin & cham & (Z >= 56) & (Z <= 82) & (Y <= yfront + 2), inner)
    # 아래 앞면 열 배출구: 우묵하게 파고 짙은 살 3줄 + 안쪽 주황
    vz0, vz1 = 36.0, 45.0
    vent = (X >= 16) & (X <= 32) & (Z >= vz0) & (Z <= vz1)
    s.cut(vent & (Y <= yfront + 5.0))
    s.add(vent & (Y > yfront + 5.0) & (Y <= yfront + 6.0), 4)
    s.add(vent & (X >= 19) & (X <= 29) & (Y > yfront + 4.0) & (Y <= yfront + 5.0) & (Z >= 37.5) & (Z <= 43.5), 6)
    for zz in (38.2, 40.6, 43.0):
        s.add(vent & (np.abs(Z - zz) <= 0.7) & (Y > yfront + 0.5) & (Y <= yfront + 4.0), 3)
    # 무릎 보호대: 크게 앞으로 튀어나온 육각 판
    kp = cbox(G, (7, 41), (-37, -14), (76, 112), {"x-y": (7, 7), "+z-y": (10, 9), "-z-y": (7, 8), "+zx": (3, 3)})
    s.add(kp, 1)
    inset(s, G, kp & (Y <= -35), cbox(G, (10, 38), (-45, 0), (81, 105), {"x-y": (6, 6)}))
    s.paint(kp & (Y <= -30) & (X >= 34) & (X <= 39) & (Z >= 78) & (Z <= 81), 5)          # 작은 주황 표식
    # 종아리 뒤 추진기(짧은 노즐 하나, 안쪽 주황)
    s.add(cyl(G, "y", (24, 62), 6, (24, 31)), 3)
    s.cut(cyl(G, "y", (24, 62), 3.5, (28, 31)))
    s.add(cyl(G, "y", (24, 62), 3.5, (27, 28)), 6)
    # ---- 발
    f = M.part("FootL", (-4, -60, 0), (56, 44, 40), pivot=ANKLE, parent="LowerLegL")
    G = f.g(); X, Y, Z = G
    f.add(cyl(G, "x", (0, 22), 10, (12, 40)), 3)                                    # 발목 관절통
    hub(f, G, 40, 46, (0, 22), 8)
    f.add(cbox(G, (3, 49), (-30, 30), (0, 12), {"xy": 6}), 2)                       # 발바닥 판
    f.add(cbox(G, (6, 46), (-26, 18), (10, 20), {"+z-y": (6, 6), "x-y": (3, 3)}), 1)  # 발등
    # 발끝 두 덩어리(안쪽이 조금 김), 윗면 앞으로 내려감
    f.add(cbox(G, (3, 24), (-52, -26), (0, 14), {"+z-y": (9, 10), "x-y": (4, 4), "-z-y": (1, 2)}), 1)
    f.add(cbox(G, (26, 49), (-47, -26), (0, 13), {"+z-y": (8, 9), "x-y": (4, 4), "-z-y": (1, 2)}), 1)
    f.paint(cbox(G, (3, 49), (-52, -26), (0, 2.5)), 2)                              # 발끝 밑창
    f.add(cbox(G, (8, 44), (24, 38), (0, 16), {"+z+y": (6, 6), "x+y": (4, 4)}), 1)   # 뒤꿈치
    f.paint(cbox(G, (40, 44), (-44, -40), (6, 9)), 5)                               # 작은 주황 표식
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


def build(variant="L1"):
    M = wv.build("W2 layered ab plates (recommended)")
    if variant == "L0":
        return M
    for n in LOWER:
        del M.parts[n]
    build_skirts(M)
    build_legs(M)
    return M


VARIANTS = {"r2 lower (before)": "L0", "L1 heavy lower remake": "L1"}

if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    out = sys.argv[1] if len(sys.argv) > 1 else "lower.png"
    A = fh.SCHEMES["A"]
    rows = []
    for name in (sys.argv[2:] or list(VARIANTS)):
        M = build(VARIANTS[name])
        Bf = M.blocks(pose=fh.STANCE)
        ims = [vp.render(Bf, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=2.2, ss=2, ao_amt=0.5)
               for y, pc in ((0, 4), (30, 6), (-30, 6), (90, 2), (150, 10))]
        B2 = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n in ("ShoulderL", "UpperArmL", "LowerArmL")])
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        rows.append(vp.sheet(ims, [name + "  front", "3/4", "3/4 (other side)", "side", "back 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
