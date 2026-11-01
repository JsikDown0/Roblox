"""
[M2 갱신 2026-10-26 01:25] 유저: 발가락 갈라진 것 별로 / 무릎 아래는 원래 r2 디자인이 낫다, 뒤 원형 부스트 구멍 2개만 추가 /
스커트는 커져도 되지만 판 테두리 줄은 그리지 말 것. → 발 가르기 삭제, 스커트는 L1 크기·모양에 줄·표식 없이,
무릎 아래는 r2 그대로(M2b) 또는 r2 모양 그대로 두께만(M2a) 두 가지로 비교.

legs_mix.py — 하체 섞기: 원래 r2 하체(상체 확정본과 함께 본 '위쪽 줄')를 바탕으로 L1 에서 마음에 든 것만 가져옴 (2026-10-26)

유저 요청:
  1) 종아리 뒤 부스트(추진기) 2개 — 가져옴
  2) 무릎 보호대 아래쪽 주황 데칼 2개 — 가져옴(발광 아님, 색 5)
  3) 하체가 두꺼워진 것 — 가져옴: r2 다리 모양 그대로, 다리 축(x24, y0) 기준 좌우 1.15배·앞뒤 1.12배
  4) 뒤 3/4 에서 발 부위가 또렷이 나뉘어 보이는 것 — 가져오되 발 모양 자체는 거의 그대로:
     발 크기는 좌우 1.06배만, 모양은 r2 그대로. 대신 밑창 띠(짙게) + 뒤꿈치·발끝 사이 틈 + 발끝 두 덩어리로 가름.
  ⚠ 무릎 관절은 두껍게 하지 않음(L1 의 옆으로 튀어나온 원판 허브 없음 — "종양 붙은 것처럼" 보임). r2 무릎 그대로 비례만 커짐.
골반 옆 스커트는 두꺼워진 허벅지가 뚫고 나오지 않게 바깥으로 옮김. 피벗·이름·부모는 r2 그대로.
"""
import numpy as np

import flagship_heavy as fh
from flag_vox import box, cbox, cyl, ell
import waist_v1 as wv

HIP, KNEE, ANKLE = fh.HIP, fh.KNEE, fh.ANKLE
LEG_SX, LEG_SY = 1.15, 1.12
FOOT_SX, FOOT_SY = 1.06, 1.0
SKIRT_OUT = 7


def sgrid(part, cx, sx, sy, cy=0.0):
    X, Y, Z = part.g()
    return (cx + (X - cx) / sx, cy + (Y - cy) / sy, Z)


def build_legs_mix(M, leg_s=(LEG_SX, LEG_SY), shin_s=(LEG_SX, LEG_SY), foot_s=(FOOT_SX, FOOT_SY),
                   foot_parts=True, shift_skirts=True):
    for n in ("UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR"):
        del M.parts[n]
    # ---- 허벅지(r2 모양, 두껍게)
    t = M.part("UpperLegL", (0, -32, 88), (50, 28, 160), pivot=HIP, parent="Pelvis")
    G = sgrid(t, 24, *leg_s); X, Y, Z = G
    t.add(ell(G, (24, 0, 142), (13, 13, 13)), 3)
    t.add(cbox(G, (12, 36), (-14, 14), (98, 140), {"xy": 5}), 3)
    t.add(cbox(G, (10, 38), (-21, -10), (104, 136), {"x-y": 5, "-z-y": (8, 6), "+z-y": 3}), 1)
    t.add(cbox(G, (35, 41), (-14, 12), (106, 138), {"+xy": 4, "+xz": 4}), 2)
    t.add(cbox(G, (14, 34), (12, 18), (106, 132), {"x+y": 3}), 2)
    # ---- 정강이(r2 모양, 두껍게)
    s = M.part("LowerLegL", (-4, -44, 12), (52, 46, 126), pivot=KNEE, parent="UpperLegL")
    G = sgrid(s, 24, *shin_s); X, Y, Z = G
    s.add(cyl(G, "x", (-2, 92), 13, (11, 37)), 3)
    s.add(cyl(G, "x", (-2, 92), 6, (10, 38)), 7)                 # 축 끝은 다리 폭 안에서 끝남(튀어나오지 않게)
    s.add(cbox(G, (10, 38), (-18, 22), (24, 90), {"xy": 6}), 2)
    sp = cbox(G, (8, 40), (-25, -15), (50, 86), {"x-y": 6, "+z-y": (6, 4), "-z-y": (4, 4)})
    s.add(sp, 1)
    bt = cbox(G, (5, 43), (-26, 26), (16, 50), {"x-y": 10, "x+y": 8, "+zx": (6, 6), "+z-y": (6, 6)})
    s.add(bt, 1)
    s.paint(bt & ((Z <= 27) | (Y >= 10)), 2)
    cf = cbox(G, (12, 36), (18, 33), (40, 84), {"+y-z": (12, 14), "+y+z": (8, 10), "x+y": 5})
    s.add(cf, 2)
    s.add(cyl(G, "z", (24, 12), 3, (78, 100)), 7)
    kn = cbox(G, (10, 38), (-33, -14), (78, 118), {"+z-y": (16, 12), "x-y": 6, "-z-y": (8, 6), "+zx": 5})
    s.add(kn, 1)
    s.add(cyl(G, "x", (0, 22), 10, (14, 38)), 3)
    # (2) 무릎 보호대 아래 바깥 모서리 주황 데칼
    s.paint_s(kn & (X >= 31) & (X <= 36.5) & (Z >= 79) & (Z <= 84) & (Y <= -24), 5)
    # (1) 종아리 뒤 추진기: 짧은 노즐 + 안쪽 주황
    s.add(cyl(G, "y", (24, 63), 5.5, (31, 37)), 3)
    s.cut(cyl(G, "y", (24, 63), 3.2, (34.5, 37)))
    s.add(cyl(G, "y", (24, 63), 3.2, (33.5, 34.5)), 6)
    # ---- 발(r2 모양 거의 그대로, 부위만 또렷하게)
    f = M.part("FootL", (0, -50, 0), (52, 32, 40), pivot=ANKLE, parent="LowerLegL")
    G = sgrid(f, 26, *foot_s); X, Y, Z = G
    f.add(ell(G, (26, 0, 22), (10, 10, 10)), 3)
    f.add(cbox(G, (8, 44), (-44, 26), (0, 3), {"xy": 4}), 4)
    f.add(cbox(G, (9, 43), (-34, 22), (4, 16), {"+z-y": (8, 10), "xy": 5}), 2)
    f.add(cbox(G, (10, 42), (-47, -26), (2, 12), {"+z-y": (6, 8), "x-y": 8}), 1)
    f.add(cbox(G, (12, 40), (16, 29), (3, 16), {"+z+y": (6, 6), "x+y": 4}), 1)
    f.add(cbox(G, (14, 38), (-24, -4), (15, 21), {"+z-y": (5, 5)}), 1)
    for xr in ((5, 10), (42, 47)):
        f.add(cbox(G, xr, (-12, 14), (8, 34), {"+zy": (6, 6)}), 1)
    # (4) 부위 가르기: 밑창 띠 짙게(z≤4) / 뒤꿈치 앞 틈 / 발끝 뒤 틈 / 발끝 두 덩어리
    if foot_parts:
        f.paint((Z <= 4.2) & np.ones_like(X, bool), 3)
        f.cut((Y >= 14.6) & (Y <= 15.8) & (Z >= 4.6) & (Z <= 17) & (np.abs(X - 26) <= 13))
        f.cut((Y >= -27.2) & (Y <= -26.0) & (Z >= 4.6) & (Z <= 13) & (np.abs(X - 26) <= 15))
        f.cut((np.abs(X - 26) <= 0.6) & (Y <= -26) & (Z >= 4.6))
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")
    # 옆 스커트를 바깥으로(두꺼운 허벅지가 뚫고 나오지 않게) — r2 스커트를 쓸 때만
    for n, sg in ((("SkirtSL", 1), ("SkirtSR", -1)) if shift_skirts else ()):
        p = M.parts[n]
        p.lo = p.lo + np.array([sg * SKIRT_OUT, 0, 0])
        p.hi = p.hi + np.array([sg * SKIRT_OUT, 0, 0])
        p.pivot = (p.pivot[0] + sg * SKIRT_OUT, p.pivot[1], p.pivot[2])


def build_skirts_clean(M):
    """L1 스커트 크기·모양(앞 큰 육각 판, 옆 큰 육각 골반 장갑) — 판 테두리 줄·주황 표식 없이."""
    import flag_vox as fv
    from flag_vox import poly
    for n in ("SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR"):
        del M.parts[n]
    f = M.part("SkirtFL", (2, -42, 118), (36, -16, 174), pivot=(18, -28, 170), parent="Pelvis")
    G = f.g()
    f.add(poly(G, "y", [(6, 170), (31, 170), (31, 144), (25, 130), (12, 130), (6, 140)], rng=(-35, -27)), 1)
    f.add(poly(G, "y", [(8, 168), (29, 168), (29, 146), (24, 133), (13, 133), (8, 142)], rng=(-27, -24)), 3)
    f.rot = fv.rotx(12)
    s = M.part("SkirtSL", (30, -30, 106), (52, 30, 176), pivot=(36, 0, 172), parent="Pelvis")
    G = s.g()
    s.add(poly(G, "x", [(-20, 172), (20, 172), (24, 160), (24, 128), (16, 114), (-16, 114), (-24, 128), (-24, 160)],
               rng=(38, 45)), 1)
    s.add(poly(G, "x", [(-16, 170), (16, 170), (20, 158), (20, 130), (13, 118), (-13, 118), (-20, 130), (-20, 158)],
               rng=(34, 38)), 3)
    s.rot = fv.roty(14)
    M.mirror("SkirtFL", "SkirtFR", "Pelvis")
    M.mirror("SkirtSL", "SkirtSR", "Pelvis")


def build(variant="M2a"):
    M = wv.build("W2 layered ab plates (recommended)")
    if variant == "M1":
        build_legs_mix(M)
    elif variant in ("M2a", "M2b"):
        build_skirts_clean(M)
        shin = (LEG_SX, LEG_SY) if variant == "M2a" else (1.0, 1.0)
        foot = (FOOT_SX, FOOT_SY) if variant == "M2a" else (1.0, 1.0)
        build_legs_mix(M, shin_s=shin, foot_s=foot, foot_parts=False, shift_skirts=False)
    return M


VARIANTS = {"r2 lower (base)": "L0",
            "M2a big skirts + thick legs (r2 shape) + calf boosters + knee decals": "M2a",
            "M2b same, but below knee = r2 exact": "M2b"}
LEGS = ("UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR")

if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    out = sys.argv[1] if len(sys.argv) > 1 else "legs_mix.png"
    A = fh.SCHEMES["A"]

    def frame(M, yaw, pitch, names=LEGS, mx=10, top=6, bot=4):
        d, f, r, u = vp._basis(yaw, pitch)
        P = []
        for n in names:
            q = M.parts[n]
            Q = np.argwhere(q.a > 0) + q.lo
            T = M.world(n, fh.STANCE)
            P.append(Q @ T[:3, :3].T + T[:3, 3])
        P = np.concatenate(P)
        sx, sy = P @ r, P @ u
        cx = (sx.min() + sx.max()) / 2
        hh = (sy.max() + top) - (sy.min() - bot)
        half = max((sx.max() - sx.min()) / 2 + mx, hh * 0.45)
        return ((cx - half, cx + half), (sy.min() - bot, sy.max() + top))

    rows = []
    for name in (sys.argv[2:] or list(VARIANTS)):
        M = build(VARIANTS[name])
        Bf = M.blocks(pose=fh.STANCE)
        ims = [vp.render(Bf, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=2.2, ss=2, ao_amt=0.5)
               for y, pc in ((0, 4), (30, 6), (90, 2), (150, 10))]
        Bl = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n in ("ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR",
                                                                         "LowerArmL", "LowerArmR")])
        ims.append(vp.render(Bl, A, fh.EMISSIVE, yaw=150, pitch=14, ppc=4.0, ss=2, ao_amt=0.5, size=frame(M, 150, 14)))
        ims.append(vp.render(Bl, A, fh.EMISSIVE, yaw=28, pitch=8, ppc=4.0, ss=2, ao_amt=0.5, size=frame(M, 28, 8)))
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        rows.append(vp.sheet(ims, [name + "  front", "3/4", "side", "back 3/4", "legs back 3/4", "legs 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
