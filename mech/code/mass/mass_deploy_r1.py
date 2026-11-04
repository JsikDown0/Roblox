"""BISON 공병형 설치물 r1 (2026-11-04) — 에너지 방벽 · 자동 포탑 · 운반 상자. 답 [결정 11-04]:
  ① 방벽은 메카보다 좀 더 크게(키 266 → 방벽 300) · 아군 공격은 통과(게임 판정, 메모) ② 사격 홈 없음 ③ 포탑 총구 = 가운데 굵은 총구 1개(아래 2개 지움)
  ④ 포탑 발광 없음 — 켜짐 표시는 Studio 상태등 ⑤ 접힌 운반 상자도 모델링.
에너지판 = 복셀 아님 → Studio 반투명 파트(Neon/ForceField + 육각 텍스처). 여기선 자리 표시용 파트 EnergyP1~3(색 10 호박, extra.studio_only).
축: 정면 = −Y, 바닥 z 0, 칸 0.05.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_eng_r1 as e1  # noqa: E402
import mass_final as MF  # noqa: E402

PAL = e1.pal("c"); PAL[10] = (255, 170, 60)
METAL = MF.METAL
WALL_H = 300
PX = (-135, -45, 45, 135)                                     # 기둥 X
PY = {-135: -10, -45: 0, 45: 0, 135: -10}                     # 바깥 기둥이 앞으로(오목한 3판)


def pillar(P, x, y):
    G = P.g(); X, Y, Z = G
    P.add(cbox(G, (x - 8, x + 8), (y - 8, y + 8), (6, WALL_H - 6), {"xy": 2}), 3)            # 짙은 기둥
    for z0, z1 in ((0, 40), (WALL_H - 44, WALL_H)):                                           # 위·아래 올리브 장갑 덮개
        P.add(cbox(G, (x - 11, x + 11), (y - 11, y + 11), (z0, z1), {"xy": 4, "+zx": 3, "-zx": 2}), 9)
    P.add(cbox(G, (x - 14, x + 14), (y - 16, y + 14), (0, 8), {"xy": 4}), 3)                  # 발판
    P.add(cyl(G, "z", (x, y - 9), 4.5, rng=(70, 230)), 2)                                    # 앞 유압 실린더(통)
    P.add(cyl(G, "z", (x, y - 9), 3.0, rng=(230, 252)), 8)                                   # 크롬 로드
    P.add(cyl(G, "z", (x, y - 9), 5.0, rng=(150, 154)), 5)                                   # 노랑 띠
    for sx in (-1, 1):                                                                         # 옆 에미터 홈(판이 나오는 곳)
        P.groove((X == x + sx * 8) & (np.abs(Y - y) <= 3) & (Z >= 44) & (Z <= WALL_H - 48), 4)
    # 뒤 받침 다리(기둥 중간 → 뒤 바닥)
    P.add(r1.seg(G, (x, y + 8, 150), (x, y + 70, 10), 4.0), 9)
    P.add(r1.seg(G, (x, y + 8, 150), (x, y + 40, 80), 2.2) & ~(P.a > 0), 8)
    P.add(cyl(G, "x", (y + 70, 10), 7, rng=(x - 7, x + 7)), 3)                                # 다리 발 관절
    P.add(cbox(G, (x - 10, x + 10), (y + 62, y + 80), (0, 6), {"xy": 3}), 3)


def build_wall():
    M = fv.Model()
    for i, x in enumerate(PX):                                                                 # 기둥마다 따로 파트(삼각형 1만 미만 + 펼침 동작)
        W = M.part("WallPillar%d" % (i + 1), (x - 24, -40, 0), (x + 25, 100, WALL_H + 2), pivot=(x, PY[x], 0))
        pillar(W, x, PY[x])
        W.trim()
    for i, (a, b) in enumerate(zip(PX[:-1], PX[1:])):                                         # 에너지판 자리(Studio 반투명)
        E = M.part("EnergyP%d" % (i + 1), (a - 2, -16, 40), (b + 3, 6, WALL_H - 40), parent="WallPillar%d" % (i + 1))
        G = E.g(); X, Y, Z = G
        ya, yb = PY[a] - 3, PY[b] - 3
        t = (X - a) / (b - a); yc = ya + (yb - ya) * t - 4 * np.sin(np.pi * t)
        E.add((X >= a + 9) & (X <= b - 9) & (np.abs(Y - yc) <= 0.6) & (Z >= 46) & (Z <= WALL_H - 48), 10)
        E.trim()
    M.extra["studio_only"] = ["EnergyP1", "EnergyP2", "EnergyP3"]
    return M


def build_turret():
    M = fv.Model()
    T = M.part("TurretBase", (-70, -70, 0), (71, 71, 80), pivot=(0, 0, 72))
    G = T.g(); X, Y, Z = G
    T.add(cyl(G, "z", (0, 0), 16, rng=(62, 72)), 3)                                          # 회전 받침(아래)
    T.add(cyl(G, "z", (0, 0), 18, rng=(66, 68)), 5)                                          # 노랑 띠
    T.add(cbox(G, (-9, 9), (-9, 9), (40, 64), {"xy": 3}), 3)                                  # 몸 기둥
    T.trim()
    for k in range(3):                                                                         # 접이 다리 3(120°) — 다리마다 따로 파트(삼각형 · 펼침 동작)
        a = np.radians(90 + 120 * k); d = np.array((np.cos(a), np.sin(a), 0))
        T = M.part("TurretLeg%d" % (k + 1), (-70, -70, 0), (71, 71, 80), pivot=tuple(np.array((0, 0, 58)) + d * 10), parent="TurretBase")
        G = T.g()
        hip = np.array((0, 0, 58)) + d * 10; knee = np.array((0, 0, 70)) + d * 38; foot = np.array((0, 0, 4)) + d * 58
        T.add(r1.seg(G, hip, knee, 5.0), 9)
        T.add(r1.seg(G, knee, foot, 4.5), 9)
        T.add(r1.seg(G, knee + (0, 0, -6), foot + d * -6 + (0, 0, 18), 1.8) & ~(T.a > 0), 8)   # 유압
        T.add(cyl(G, "z", (knee[0], knee[1]), 6.5, rng=(knee[2] - 4, knee[2] + 4)), 3)        # 무릎 관절
        T.add(cyl(G, "z", (foot[0], foot[1]), 8, rng=(0, 6)), 3)                              # 발
        T.trim()
    H = M.part("TurretHead", (-28, -40, 72), (29, 30, 112), pivot=(0, 0, 72), parent="TurretBase")
    G = H.g(); X, Y, Z = G
    H.add(cbox(G, (-22, 22), (-20, 22), (74, 104), {"xy": 5, "+zx": 4, "+zy": 4, "-zy": 3}), 9)
    H.add(cbox(G, (-16, 16), (-23, -19), (78, 100), {"xz": 3}), 2)                            # 정면 판(짙은 쇠)
    H.add(cyl(G, "y", (0, 89), 6.5, rng=(-28, -23)), 3)                                      # 가운데 굵은 총구 받침
    H.add(cyl(G, "y", (0, 89), 4.0, rng=(-38, -28)), 2)                                      # 총열
    H.add(cyl(G, "y", (0, 89), 5.0, rng=(-38, -35)), 3)                                      # 소염기
    H.cut(cyl(G, "y", (0, 89), 2.0, rng=(-39, -34)))
    H.add(box(G, x=(-10, 10), y=(-6, 6), z=(105, 107)) & ~box(G, x=(-8, 8), y=(-4, 4), z=(104, 106)), 3)   # 위 손잡이(크레인 집는 곳)
    H.add(cbox(G, (-14, 14), (22, 27), (78, 98), {"xy": 2}), 3)                               # 뒤 상자
    H.trim()
    return M


def build_crates():
    M = fv.Model()
    C = M.part("WallCrate", (-60, -32, 0), (61, 33, 70))
    G = C.g(); X, Y, Z = G
    C.add(cbox(G, (-56, 56), (-28, 28), (0, 62), {"xy": 4, "xz": 4, "yz": 4}), 9)
    C.paint_s((np.abs(X) >= 54) | (Z <= 2) | (Z >= 60) | (np.abs(Y) >= 26) & ((np.abs(X) >= 52) | (Z <= 4) | (Z >= 58)), 3)
    for s in (1, -1):
        C.add(box(G, x=sorted((s * 30, s * 38)), y=(-31, -29), z=(40, 54)), 3)                 # 잠금쇠
        C.add(box(G, x=sorted((s * 57, s * 59)), y=(-8, 8), z=(26, 40)) & ~box(G, x=sorted((s * 57, s * 57)), y=(-6, 6), z=(28, 38)), 3)
    C.trim()
    T = M.part("TurretCrate", (72, -22, 0), (129, 23, 40))
    G = T.g(); X, Y, Z = G
    T.add(cbox(G, (76, 124), (-18, 18), (0, 32), {"xy": 3, "xz": 3, "yz": 3}), 9)
    T.paint_s((Z <= 2) | (Z >= 30), 3)
    T.add(cyl(G, "y", (100, 16), 3.5, rng=(-22, -18)), 2)                                    # 총구 끝(접힘)
    T.add(box(G, x=(92, 108), y=(-4, 4), z=(33, 35)) & ~box(G, x=(94, 106), y=(-2, 2), z=(32, 34)), 3)
    T.trim()
    return M


def place(blocks, dx=0, dy=0):
    O = np.eye(4); O[:3, 3] = (dx, dy, 0)
    return [(lo, a, O @ (T if T is not None else np.eye(4))) for lo, a, T in blocks]


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    mdir = sys.argv[2] if len(sys.argv) > 2 else None
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import mass_leg_r4 as l4
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    Wm, Tm, Cm = build_wall(), build_turret(), build_crates()
    for nm, M in (("방벽", Wm), ("포탑", Tm), ("상자", Cm)):
        print("==", nm); cm.check(M)
    Me = e1.build_all("c", "N2", big=True)
    mech = place(Me.blocks(pose=l4.aim(Me, MF.REST_POSE)[0], skip=("RifleStowed",)), -230, 0)
    R = lambda B, y, p, ppc: vp.render(B, PAL, MF.EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=METAL)
    scene = mech + Wm.blocks() + place(Tm.blocks(), 230, -40)
    rows = [("크기 비교: 공병형 · 에너지 방벽(높이 300, 판 = 자리 표시) · 포탑", [R(scene, 0, 4, 1.2), R(scene, -30, 10, 1.2)]),
            ("에너지 방벽 (정면 · 뒤 3/4 · 옆 · 위)", [R(Wm.blocks(), y, p, 1.3) for y, p in ((0, 2), (150, 12), (-90, 2))] + [R(Wm.blocks(), 0, 85, 1.3)]),
            ("포탑 (정면 · 앞 3/4 · 옆 · 위)", [R(Tm.blocks(), y, p, 3.0) for y, p in ((0, 4), (-35, 12), (-90, 4), (0, 85))]),
            ("접힌 운반 상자 (방벽 · 포탑)", [R(place(Cm.blocks(), 0, 0), -35, 15, 2.4)])]
    H = [max(i.height for i in ims) for _, ims in rows]
    W = max(sum(i.width for i in ims) + 16 * (len(ims) + 1) for _, ims in rows)
    sh = Image.new("RGB", (W, 60 + sum(h + 46 for h in H)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "BISON 공병형 설치물 r1 — 에너지 방벽 · 자동 포탑 · 운반 상자", fill=(235, 235, 235), font=ft)
    y0 = 60
    for (nm, ims), h in zip(rows, H):
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f); x = 16
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
        y0 += h + 46
    p = os.path.join(out, "시안_설치물r1.png"); sh.save(p); print(p, sh.size)
    if mdir:
        Wm.save(os.path.join(mdir, "BISON_E_Wall.json")); Tm.save(os.path.join(mdir, "BISON_E_Turret.json")); Cm.save(os.path.join(mdir, "BISON_E_Crates.json"))
