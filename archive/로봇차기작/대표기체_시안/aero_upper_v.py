"""
aero_upper_v.py — Aero 상체 2차: V 몸통 + 레퍼런스 공통 요소 (2026-10-26 13:31~)

유저: "가벼운 기체치곤 넓고 무거워 보여(상체 1차 K안). 아까 질문에서 말해 준 V자로 대표되는 레퍼런스의 공통적인 요소들로 다시 리메이크"
= 13:12 질문에 적었던 4묶음(유저가 질문은 건너뛰고 이걸로 지정):
  ① 가슴: 위가 넓고 허리로 확 좁아지는 V 몸통 · 가운데 셰브론을 크게 · 셰브론 아래 틈 속 발광
  ② 어깨: 판 2~3장이 겹친 큰 어깨 · 위 판이 뒤·위로 뾰족 · 판 사이 틈에 발광 줄
  ③ 등: 날개 뿌리에 큰 세로 바인더 블록 + 위쪽 추진기 노즐(날개가 바인더에서 뻗음)
  ④ 목·팔: 머리가 반쯤 묻히는 높은 목 깃 · 팔뚝에 큰 장갑판
얼굴 = P1. 다리·골반은 r1 그대로.
"""
import numpy as np

from flag_vox import box, cbox, poly, cyl, ell, rotx, roty, rotz
import aero_r1 as A
import aero_faces as F
import aero_faces_p as P

UPPER = []                 # 이 파일이 만든 파트(렌더 keep 용)
FOLD = 15                  # 셰브론 판 접힘(위에서 본 V)


def _B(G):
    X, Y, Z = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    return lambda m: np.broadcast_to(m, shp)


# ------------------------------------------------------------------ ① V 몸통 + ④ 높은 목 깃
def torso(M):
    M.parts.pop("ChestPlate", None)
    t = M.parts["Torso"]
    t.a[:] = 0
    G = t.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    t.add(cbox(G, (-11, 11), (-10, 11), (176, 200), {"xy": 4}), 3)                          # 허리 마디
    t.add(cbox(G, (-9, 9), (-15, -9), (179, 188), {"xy": 2, "-z-y": (3, 3)}), 3)             # 배 2단
    t.add(cbox(G, (-11, 11), (-17, -9), (188, 198), {"xy": 2, "-z-y": (3, 3)}), 3)
    # V 몸통 속(프레임): 아래 반폭 13 → z 212 부터 45° 로 벌어져 z 230 에서 31
    w = 13 + np.clip(Z - 212, 0, 18)
    core = (ax <= w) & cbox(G, (-31, 31), (-15, 16), (198, 238), {"x-y": 4, "x+y": 4, "+zx": 4})
    t.add(B(core), 3)
    t.add(cbox(G, (-34, 34), (-11, 13), (226, 236), {"+zx": 6, "xy": 3}), 3)                # 어깨 다리
    t.add(cbox(G, (-20, 20), (16, 22), (202, 236), {"xy": 3}), 3)                           # 등판
    # ④ 높은 목 깃: 뒤·옆 U자 벽(머리 아래 절반을 감쌈), 앞으로 45° 내려옴
    ztop = 249 - np.clip(-Y + 2, 0, None)                                                     # y≥-2 에서 249, 앞으로 45°
    wall = (ax <= 20) & (Y >= -14) & (Y <= 20) & (Z >= 232) & (Z <= ztop)
    wall &= ~((ax <= 15) & (Y <= 14))                                                         # 안쪽(목·머리 자리) 비움
    wall &= ~((ax >= 18) & (Z >= ztop - 2) & (Z >= 240))                                      # 바깥 위 모서리 모따기 느낌
    t.add(B(wall), 2)
    t.paint(B(wall & ((ax <= 16) | (Y >= 18))), 3)                                            # 안쪽 면은 짙게(깃 두께가 보이게)
    t.add(cyl(G, "z", (0, -2), 6, (230, 238)), 3)                                             # 목


def chest(M, kind):
    """① 큰 셰브론(아래 끝 45° V) + 위 V 홈 흰 윗가슴 + 셰브론 처마 밑 틈 속 발광. 반쪽을 세워 만들고 rotz 로 접음."""
    p = M.part("ChestL", (-2, -30, 186), (36, -12, 244), pivot=(0, -22, 214), parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    xin = X >= 0
    zlo = 198 + X                     # 셰브론 아래 변(45°)
    zhi = 222 + 0.5 * X               # 셰브론 윗 변(1:2)
    chev = xin & (X <= 30) & (Z >= zlo) & (Z <= zhi) & (Y >= -24) & (Y <= -20)
    p.add(B(chev), 1)
    # 위 흰 윗가슴(셰브론 위, 2칸 뒤): 윗변은 목 쪽 V 홈(턱과 안 부딪게)
    up = xin & (X <= 25) & (Z > zhi - 3) & (Z <= np.minimum(232 + 0.5 * X, 240 - np.clip(X - 19, 0, None))) & (Y >= -22) & (Y <= -18)
    p.add(B(up), 3 if kind == "U2" else 2)                                                     # U2: 짙은 윗가슴(흰 얼굴과 떨어지고 셰브론이 더 뜸)
    # 셰브론 처마 밑 짙은 띠 + 틈 속 발광(바깥쪽 두 줄만 — 가운데까지 이으면 웃는 입)
    under = xin & (X <= 27) & (Z >= zlo - 5) & (Z < zlo) & (Y >= -21) & (Y <= -17)
    p.add(B(under), 3)
    if True:
        gl = xin & (X >= 6) & (X <= 21) & (Z >= zlo - 4) & (Z <= zlo - 2)
        p.cut(B(gl & (Y <= -20)))
        p.add(B(gl & (Y >= -19) & (Y <= -19)), 6)
    p.rot = rotz(FOLD)
    M.mirror("ChestL", "ChestR", "Torso")
    UPPER.extend(["ChestL", "ChestR"])


# ------------------------------------------------------------------ ② 겹친 어깨
def shoulder(M, kind):
    sh = M.part("ShoulderL", (26, -24, 196), (64, 40, 262), pivot=A.SHOULDER, parent="Torso")
    G = sh.g(); X, Y, Z = G; B = _B(G)
    sh.add(cbox(G, (33, 42), (-12, 12), (210, 234), {"xy": 3}), 3)                           # 안쪽 받침
    # 판 C(맨 아래, 흰) → 판 B(가운데, 주황) → 판 A(위, 주황). 위 판이 아래 판의 윗변을 바깥에서 덮음(기와)
    plates = [
        ("C", (44, 53), (-10, 12), (202, 218), 2),
        ("B", (44, 55), (-13, 16), (214, 232), 2 if kind == "U3" else 1),
        ("A", (33, 57), (-16, 20), (228, 246), 1),
    ]
    for nm, x, y, z, c in plates:
        sh.add(B(cbox(G, x, y, z, {"+z+x": 5, "x-y": 4, "-z+x": 2, "+z-y": 3})), c)
    # 판 사이 틈 발광: 위 판 아랫변 바로 밑, 아래 판 바깥면을 한 칸 파고 깊은 곳만
    # v2: 틈 높이를 위 판 아랫변 바로 밑(B 226 · C 212)으로 — v1 은 위 판 속(229.5/215.5)에 묻혀 안 보였음
    for (zg, xo, y0, y1) in ((212, 53, -7, 10), (226, 55, -10, 13)):
        g = (Z == zg) & (Y >= y0) & (Y <= y1)
        sh.cut(B(g & (X >= xo - 1) & (X <= xo)))
        sh.add(B(g & (X == xo - 2)), 6)
    # 위 판 뒤 끝: 뒤·위로 뾰족(45° 로 오름)
    spike = poly(G, "x", [(14, 238), (14, 246), (24, 256), (30, 257), (26, 249), (20, 238)], rng=(37, 51))
    sh.add(B(spike & (Z <= 257 - np.clip(X - 46, 0, None))), 1)
    sh.rot = roty(-10)
    M.mirror("ShoulderL", "ShoulderR", "Torso")


# ------------------------------------------------------------------ ④ 팔뚝 큰 장갑판
def forearm(M):
    f = M.parts["LowerArmL"]
    f.a[:] = 0
    G = f.g(); X, Y, Z = G; B = _B(G)
    f.add(cbox(G, (34, 46), (-8, 8), (140, 178), {"xy": 3}), 3)                               # 팔뚝 뼈대
    # 큰 장갑판: 바깥+앞을 감싸는 한 덩어리(앞 바깥 모서리 45°), 위 끝이 팔꿈치 뒤로 솟는 날
    # v2: 앞면 폭 19 → 앞 안쪽 모서리 크게 깎아 정면 폭 ~11(v1 은 정면에서 주황 판자 — 다시 무거워 보임)
    arm = cbox(G, (34, 51), (-13, 9), (144, 180), {"+x-y": 5, "-x-y": (8, 8), "-z-y": 3, "+z-y": 4, "-zx": 3, "-x+y": 3})
    f.add(B(arm & ~((X <= 41) & (Y >= -7))), 1)                                               # 안쪽(몸통 쪽) 뒤는 비움 → 뼈대 보임
    blade = poly(G, "x", [(-6, 172), (9, 172), (22, 196), (16, 197), (-6, 180)], rng=(47, 51))
    f.add(B(blade), 1)
    f.paint_s(B((X >= 50) & (Z >= 150) & (Z <= 170) & (Y >= -8) & (Y <= 4)), 2)               # 바깥면 가운데 흰 판(큰 면 쪼개기)
    f.add(box(G, (34, 46), (-8, 8), (134, 140)), 3)                                           # 손목
    f.add(cbox(G, (33, 47), (-10, 12), (116, 135), {"xy": 3, "-zx": 2}), 3)
    f.add(cbox(G, (32, 48), (-12, -6), (120, 133), {"x-y": 2, "-z-y": 2}), 3)
    for fy in (-4, 1, 6):
        f.add(box(G, (35, 45), (fy, fy + 3), (113, 116)), 3)
    M.mirror("LowerArmL", "LowerArmR", "UpperArmR")


# ------------------------------------------------------------------ ③ 바인더 + 위 추진기
def back(M):
    bp = M.parts["Backpack"]
    G = bp.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    bp.cut(B((ax >= 14) & (Z >= 220)))                                                        # 옛 경첩 받침 걷음(바인더가 대신)
    b = M.part("BinderL", (8, 18, 186), (36, 52, 262), pivot=(22, 32, 236), parent="Backpack")
    G = b.g(); X, Y, Z = G; B = _B(G)
    body = cbox(G, (14, 30), (24, 44), (196, 250), {"+y+z": 8, "+y-z": (14, 6), "xy": 3, "+zx": 3})
    b.add(B(body), 3)                                                                          # v2: 몸체 짙게(v1 흰 몸체 = 등에 흰 상자)
    b.add(B(cbox(G, (30, 31), (27, 41), (204, 244), {"yz": 3})), 1)                          # 바깥 주황 판(한 칸 돋음)
    b.add(B(cbox(G, (13, 13), (27, 41), (210, 238), {"yz": 3})), 2)                          # 안쪽 흰 판
    b.add(B(cbox(G, (17, 27), (20, 24), (206, 244), {"xy": 2})), 3)                           # 등과 잇는 받침
    # 위 추진기 노즐 2개: 바인더 위쪽 뒤에서 뒤로 분사(v1 은 위를 향해 정면에서 머리 옆 돌기 = 귀처럼 보일 위험)
    for nz in (238, 247):
        ring = cyl(G, "y", (22, nz), 4, (42, 48)) & ~cyl(G, "y", (22, nz), 2, (45, 48))
        b.add(B(ring), 7)
        b.add(B(cyl(G, "y", (22, nz), 2, (44, 44))), 6)
    M.mirror("BinderL", "BinderR", "Backpack")
    UPPER.extend(["BinderL", "BinderR"])


def upper(M, kind="U1"):
    UPPER.clear()
    torso(M)
    chest(M, kind)
    shoulder(M, kind)
    forearm(M)
    back(M)


def build(kind="U1"):
    M = P.build("P1")
    upper(M, kind)
    return M


def build_all():
    return build("U1")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["U1"]
    sch = A.SCHEMES["A"] | {10: (186, 188, 190), 8: (164, 78, 26)}
    UP = {"Torso", "Pelvis", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
          "Backpack", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR"}
    rows = []
    for k in kinds:
        import aero_chest_k as K
        M = P.build("P1") if k == "r1" else (K.build(k) if k.startswith("K") else build(k))
        keep = UP | set(F.HEAD_PARTS) | set(UPPER) | {"ChestPlate", "ChestNew"}
        Bc = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        Bf = M.blocks(pose=A.STANCE)
        ims = [vp.render(Bc, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=4, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in ((0, 4, ((-70, 70), (150, 292))), (30, 8, ((-72, 72), (150, 294))),
                                (90, 2, ((-66, 66), (150, 294))), (150, 12, ((-72, 72), (150, 296))))]
        ims.append(vp.render(Bf, sch, A.EMISSIVE, yaw=30, pitch=6, ppc=1.5, ss=2, size=((-110, 110), (-10, 320)), ao_amt=0.5))
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back 3/4", "full 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
