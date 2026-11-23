"""
aero_upper_w.py — Aero 상체 3차: 레퍼런스 공통점 기반 (2026-10-26 13:43~)

유저: "(U1·U2) 좀 유치하고 아동용 만화 로봇 같아. 레퍼런스들의 공통점을 분석하고 이를 바탕으로 유사한 느낌의 상체를 만들어줘"
+ 레퍼런스 4장(흰/청 발광 흉상 2 · 주황/회색 전신 1 · 흰/적 전신 1).

유치해 보인 원인 [관찰, U1·U2 렌더 대조]:
  X1 큰 면이 원색 주황 한 판(셰브론·어깨·팔뚝) — 장난감 색 배분. 레퍼런스는 흰·밝은 회색 + 짙은 프레임이 몸이고 색은 일부 판에만
  X2 모든 모서리를 같은 45° 로 깎은 둥근 상자 — 말랑한 블록. 레퍼런스는 판 끝이 예각·비대칭 사다리꼴, 판이 여러 겹
  X3 큰 판에 쪼갬이 없음(디테일 밀도 낮음). 레퍼런스는 가슴·어깨에 단차·작은 등·통풍구가 몰려 있고 큰 바인더 판만 조용함
  X4 발광이 가는 선 두 줄뿐 — 레퍼런스는 가슴 발광이 기체 전체에서 가장 밝은 덩어리

레퍼런스 공통점 [관찰 — 형태 언어만, 특정 기체 복제 아님]:
  C1 가슴 가로 발광 띠: 가슴 폭 80~90% 를 가로지르는 얕은 V, 양 끝이 위로 꺾여 올라감. 위·아래 판 사이 홈 속에서 빛남
  C2 가슴 3단: 밝은 윗가슴 판 → 발광 띠 → 아래로 좁아지는 V 아랫가슴(짙은 회색 또는 강조색) → 가는 허리(드러난 짙은 프레임·마디)
  C3 색: 흰·밝은 회색 주장갑 + 짙은 건메탈 프레임 + 강조색(주황·적·청)은 판 몇 장 + 작은 등(발광 점)
  C4 어깨: 여러 판이 겹친 각진 어깨, 위 판 끝이 바깥·위로 뾰족, 바깥면 아래쪽 작은 등
  C5 머리가 낮게 앉음: 목 깃·어깨 판이 머리 옆을 감쌈, 머리 폭 ≈ 가슴 폭의 40~45%
  C6 디테일은 가슴·어깨·머리에 몰리고, 큰 판(바인더·날개)은 넓고 조용함
안: W1 아랫가슴 짙은 회색(흉상 2장 계열) / W2 아랫가슴 주황(전신 2장 계열). 나머지 같음.
"""
import numpy as np

from flag_vox import box, cbox, poly, cyl, rotx, roty, rotz
import aero_r1 as A
import aero_faces as F
import aero_faces_p as P

UPPER = []
FOLD = 12
WHITE, LGRAY, FRAME, BLACK, ACC, GLOW, METAL = 2, 10, 3, 4, 1, 6, 7


def _B(G):
    X, Y, Z = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    return lambda m: np.broadcast_to(m, shp)


def _child(M, name, lo, hi, pivot, parent, rot):
    p = M.part(name, lo, hi, pivot=pivot, parent=parent)
    p.rot = rot
    UPPER.append(name)
    return p


# ------------------------------------------------------------------ 몸통 프레임 · 가는 허리 · 목 깃 (C2·C5)
def torso(M):
    M.parts.pop("ChestPlate", None)
    t = M.parts["Torso"]
    t.a[:] = 0
    G = t.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    t.add(cbox(G, (-10, 10), (-9, 10), (176, 202), {"xy": 3}), FRAME)                        # 허리 기둥
    # 배 마디 3단(아래가 좁음) — 사이 1칸 틈이 짙게 보임
    for z0, z1, hw in ((180, 185, 6), (187, 192, 7), (194, 199, 8)):
        t.add(cbox(G, (-hw, hw), (-14, -9), (z0, z1), {"x-y": 2, "-z-y": 1}), LGRAY)
    # 갈비 프레임: 반폭 12(z≤206) → 45° 로 벌어져 z224 에서 30
    w = 12 + np.clip(Z - 206, 0, 18)
    core = (ax <= w) & cbox(G, (-30, 30), (-14, 15), (200, 238), {"x-y": 3, "x+y": 4, "+zx": 4})
    t.add(B(core), FRAME)
    for zr in (212, 216, 220):                                                                 # 옆구리 갈비 살(금속) — 벌어지는 면 위
        rib = (ax >= w - 3) & (ax <= w) & (Z == zr) & (Y >= -14) & (Y <= -6)
        t.add(B(rib), METAL)
    t.add(cbox(G, (-34, 34), (-11, 13), (226, 236), {"+zx": 6, "xy": 3}), FRAME)             # 어깨 다리
    t.add(cbox(G, (-20, 20), (15, 21), (202, 236), {"xy": 3}), FRAME)                        # 등판
    # 목 깃: 뒤·옆 U자 벽, 바깥 밝은 회색 판 + 안쪽 짙게, 앞으로 45° 내려옴
    ztop = 249 - np.clip(-Y + 2, 0, None)
    wall = (ax <= 20) & (Y >= -14) & (Y <= 20) & (Z >= 232) & (Z <= ztop) & ~((ax <= 15) & (Y <= 14))
    t.add(B(wall), FRAME)
    t.paint_s(B(wall & (ax >= 19) & (Z <= ztop - 1)), LGRAY)
    t.add(cyl(G, "z", (0, -2), 6, (230, 238)), FRAME)


# ------------------------------------------------------------------ 가슴 (C1·C2·C6)
def chest(M, kind):
    p = _child(M, "ChestL", (-2, -30, 194), (36, -12, 244), (0, -22, 220), "Torso", rotz(FOLD))
    G = p.g(); X, Y, Z = G; B = _B(G)
    xin = X >= 0
    zc = np.where(X <= 20, 216 + 0.5 * X, 226 + (X - 20))          # 발광 띠 중심선: 얕은 V(1:2) → 바깥 끝 45° 로 꺾여 올라감
    face = (Y >= -23) & (Y <= -20)
    # 윗가슴(흰): 윗변은 목 쪽 V 홈(턱과 띄움) → 평평 → 바깥 위 45°
    ztop = np.minimum(np.minimum(233 + 0.5 * X, 240), 240 - np.clip(X - 25, 0, None))
    up = xin & (X <= 31) & (Z <= ztop) & (Z >= zc + 2.5) & face
    p.add(B(up), WHITE)
    p.cut(B(up & (X >= 17) & (Y <= -23)))                            # 바깥 판 한 칸 뒤 → 판 두 장(단차로 쪼갬, 테두리 줄 없이)
    p.add(B(xin & (X >= 21) & (X <= 25) & (Z >= 236) & (Z <= 237) & (Y == -23)), ACC)          # 바깥 판 작은 강조 탭
    for zv in (231, 233):                                                                        # 바깥 판 통풍구 2줄(짧게)
        p.cut(B(xin & (X >= 25) & (X <= 28) & (Z == zv) & (Y <= -22)))
        p.add(B(xin & (X >= 25) & (X <= 28) & (Z == zv) & (Y == -21)), BLACK)
    # 발광 띠: 짙은 입술(판 면에서 1칸 들어감) 속 3칸 띠, 2칸 더 깊음
    lip = xin & (X <= 28) & (np.abs(Z - zc) <= 2.5) & (Y >= -22) & (Y <= -19)
    p.add(B(lip), FRAME)
    gl = xin & (X <= 27) & (np.abs(Z - zc) <= 1.5)
    p.cut(B(gl & (Y <= -21)))
    p.add(B(gl & (Y == -20)), GLOW)
    # 아랫가슴: 띠 밑에서 아래로 45° 모이는 V
    lo = xin & (X <= 23) & (Z >= 202 + X) & (Z <= zc - 2.5) & face
    p.add(B(lo), ACC if kind == "W2" else FRAME)
    p.paint_s(B(lo & (Z >= 202 + X) & (Z <= 203 + X) & (Y == -23)), LGRAY if kind == "W2" else METAL)   # 아래 변 한 줄 밝게(판 끝이 보이게)
    M.mirror("ChestL", "ChestR", "Torso")
    UPPER.append("ChestR")


# ------------------------------------------------------------------ 어깨 (C4)
def shoulder(M):
    """v2: v1 은 정면에서 짙은 속 뭉치가 세로 상자로 보이고(앞을 덮는 판 없음), 비스듬한 윗판 = 납작한 날개, 깃 = 정면에서 가는 막대.
    → 앞 판·바깥 판·윗판이 속을 감싸는 껍데기, 판 사이는 한 칸 단차, 깃은 정면을 보는 판(정면에서 날 모양이 보이게)."""
    sh = M.part("ShoulderL", (26, -24, 196), (66, 40, 270), pivot=A.SHOULDER, parent="Torso")
    G = sh.g(); X, Y, Z = G; B = _B(G)
    sh.add(cbox(G, (36, 50), (-10, 12), (212, 240), {"xy": 3}), FRAME)                       # 속 뭉치(가려짐)
    # 앞 판(흰): 위가 넓고 바깥 아래로 모이는 각진 판 — 바깥 끝 아래가 예각
    front = poly(G, "y", [(35, 243), (53, 246), (53, 226), (49, 209), (44, 213), (41, 226), (35, 230)], rng=(-15, -11))
    sh.add(B(front), WHITE)
    sh.paint(B(front & (Z <= 217)), ACC)                                                       # 아래 끝만 강조색
    # 바깥 판(밝은 회색): 앞 판보다 한 칸 뒤에서 시작(모서리에 단차), 뒤 아래 45°
    outer = poly(G, "x", [(-13, 246), (17, 244), (17, 226), (9, 212), (-6, 208), (-13, 216)], rng=(54, 57))
    sh.add(B(outer), LGRAY)
    sh.cut(B((X >= 57) & (Z == 222) & (Y >= -10) & (Y <= 15)))                                  # 바깥 판 가로 단차 홈
    sh.cut(B((X >= 57) & (Z >= 215) & (Z <= 216) & (Y >= -6) & (Y <= -3)))                      # 작은 등
    sh.add(B((X == 56) & (Z >= 215) & (Z <= 216) & (Y >= -6) & (Y <= -3)), GLOW)
    # 윗판(밝은 회색): 앞 판 윗변 뒤를 덮는 지붕, 한 칸 위로 좁은 판 하나 더
    sh.add(B(cbox(G, (35, 56), (-12, 16), (244, 247), {"+z+x": 2, "x+y": 4})), LGRAY)
    sh.add(B(cbox(G, (38, 50), (-8, 12), (248, 248), {"xy": 2})), WHITE)
    # 깃(강조색): 정면을 보는 판, 어깨 끝에서 바깥·위로 뾰족(두 겹)
    # v3: 깃을 낮추고 더 눕힘(머리 볏과 합쳐 위로 솟은 게 넷 → 정면이 산만 · v2 는 266 까지 솟음)
    sh.add(B(poly(G, "y", [(46, 246), (54, 247), (64, 259), (61, 260), (49, 251)], rng=(0, 3))), ACC)
    sh.add(B(poly(G, "y", [(49, 246), (54, 247), (58, 253), (51, 250)], rng=(-1, -1))), WHITE)
    sh.add(B(cbox(G, (36, 52), (-8, 10), (202, 214), {"-z+x": 3, "x-y": 2})), FRAME)           # 밑 받침(위팔과 이음)
    sh.rot = roty(-8)
    M.mirror("ShoulderL", "ShoulderR", "Torso")


# ------------------------------------------------------------------ 팔뚝 (C3·C6)
def forearm(M):
    f = M.parts["LowerArmL"]
    f.a[:] = 0
    G = f.g(); X, Y, Z = G; B = _B(G)
    f.add(cbox(G, (34, 46), (-8, 8), (140, 178), {"xy": 3}), FRAME)
    # 바깥 장갑판(흰): 앞 끝이 아래로 뾰족한 사다리꼴, 위 끝은 팔꿈치 뒤로 솟는 날
    plate = poly(G, "x", [(-13, 178), (-13, 150), (-7, 140), (6, 140), (9, 150), (9, 172), (22, 196), (16, 197), (4, 180)], rng=(47, 50))
    f.add(B(plate), WHITE)
    f.paint(B(plate & (Z >= 178)), ACC)                                                         # 날 끝만 강조색
    f.cut(B((X >= 50) & (Z == 166) & (Y >= -12) & (Y <= 8)))                                    # 단차 홈(판 쪼갬)
    f.cut(B((X >= 50) & (Z >= 155) & (Z <= 156) & (Y >= -9) & (Y <= -6)))                      # 작은 등
    f.add(B((X == 49) & (Z >= 155) & (Z <= 156) & (Y >= -9) & (Y <= -6)), GLOW)
    f.add(B(cbox(G, (35, 47), (-13, -9), (146, 176), {"-x-y": 4, "-z-y": 3})), LGRAY)        # 앞 판(한 칸 뒤, 밝은 회색)
    f.add(box(G, (34, 46), (-8, 8), (134, 140)), FRAME)
    f.add(cbox(G, (33, 47), (-10, 12), (116, 135), {"xy": 3, "-zx": 2}), FRAME)
    f.add(cbox(G, (32, 48), (-12, -6), (120, 133), {"x-y": 2, "-z-y": 2}), FRAME)
    for fy in (-4, 1, 6):
        f.add(box(G, (35, 45), (fy, fy + 3), (113, 116)), FRAME)
    M.mirror("LowerArmL", "LowerArmR", "UpperArmR")


# ------------------------------------------------------------------ 등 바인더 (U 와 같은 자리, 색만 C3)
def back(M):
    bp = M.parts["Backpack"]
    G = bp.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    bp.cut(B((ax >= 14) & (Z >= 220)))
    bp.paint(B(bp.a > 0), FRAME)
    bp.paint_s(B((ax <= 18) & (Y >= 35) & (Z >= 200) & (Z <= 240)), LGRAY)
    b = M.part("BinderL", (8, 18, 186), (36, 52, 262), pivot=(22, 32, 236), parent="Backpack")
    G = b.g(); X, Y, Z = G; B = _B(G)
    b.add(B(cbox(G, (14, 30), (24, 44), (196, 250), {"+y+z": 8, "+y-z": (14, 6), "xy": 3, "+zx": 3})), FRAME)
    b.add(B(cbox(G, (30, 31), (27, 41), (204, 244), {"yz": 3})), WHITE)
    b.add(B(box(G, (31, 31), (27, 41), (232, 233))), ACC)
    b.add(B(cbox(G, (17, 27), (20, 24), (206, 244), {"xy": 2})), FRAME)
    for nz in (238, 247):
        b.add(B(cyl(G, "y", (22, nz), 4, (42, 48)) & ~cyl(G, "y", (22, nz), 2, (45, 48))), METAL)
        b.add(B(cyl(G, "y", (22, nz), 2, (44, 44))), GLOW)
    M.mirror("BinderL", "BinderR", "Backpack")
    UPPER.extend(["BinderL", "BinderR"])


def upper(M, kind="W1"):
    UPPER.clear()
    torso(M)
    chest(M, kind)
    shoulder(M)
    forearm(M)
    back(M)
    ua = M.parts["UpperArmL"]                                     # 위팔 보조장갑 흰 → 밝은 회색(흰 면적 줄임)
    ua.paint(ua.a == WHITE, LGRAY)
    M.mirror("UpperArmL", "UpperArmR", "Torso")


def build(kind="W1"):
    M = P.build("P1")
    upper(M, kind)
    return M


def build_all():
    return build("W1")


SCH = A.SCHEMES["A"] | {10: (186, 188, 190), 8: (164, 78, 26)}

if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["W1"]
    UP = {"Torso", "Pelvis", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
          "Backpack", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR"}
    rows = []
    for k in kinds:
        import aero_upper_v as U
        M = U.build(k) if k.startswith("U") else build(k)
        keep = UP | set(F.HEAD_PARTS) | set(UPPER) | set(U.UPPER)
        Bc = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        Bf = M.blocks(pose=A.STANCE)
        ims = [vp.render(Bc, SCH, A.EMISSIVE, yaw=y, pitch=p, ppc=4, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in ((0, 4, ((-70, 70), (150, 292))), (30, 8, ((-72, 72), (150, 294))),
                                (90, 2, ((-66, 66), (150, 294))), (150, 12, ((-72, 72), (150, 296))))]
        ims.append(vp.render(Bf, SCH, A.EMISSIVE, yaw=30, pitch=6, ppc=1.5, ss=2, size=((-110, 110), (-10, 320)), ao_amt=0.5))
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back 3/4", "full 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
