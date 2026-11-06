"""
jet_r3.py — FalcoJet r3 = r2 + 흡기구 · 주황 발톱 · 윗면 흰 판 다듬기 (2026-11-06)

유저(r2 평): "흡기구가 컨셉보다 각진 상자 · 몸 위 흰 작은 판이 덜 들어감 → 개선 + 흡기구와 날개 옆 주황 발톱 같은 부분도 더 디테일하게".
컨셉 c1 큰 그림 확대 다시 읽음 [관찰]:
  - 흡기구 = 상자 하나가 아니라 겹: 앞 흰 덮개(앞 위가 크게 깎여 앞으로 숙인 어깨 모양 · 바깥 면에 짙은 판이 파여 있음)
    → 한 단 낮은 뒤 덮개 → 날개 뿌리 쪽 짙은 ㄷ자 틀(앞으로 열림).
  - 주황 발톱 2쌍: 안 = ㄷ자 틀 밑에서 앞·아래로 뻗는 계단식 쐐기 · 바깥 = 날개 밑 포드의 계단식 주황 코.
  - 안쪽 포드(흡기구 밑) 앞은 짙은 계단식 덩어리 + 옆 회색 줄(주황 아님).
  - 윗면: 짙은 몸 위에 흰 판이 띄엄띄엄(가운데 척추 · 엔진 사이 · 엔진 위 · 날개 뿌리 위) + V 팔 끝 주황 마개 + 흰 판 옆 주황 덩어리.
조종석 · 꼬리 · 부착점 · 판정 = r2 그대로(미사일 1·3 은 새 포드 앞 끝으로만 옮김).
"""
import numpy as np

import jet_r1 as R1
import jet_r2 as R2
from flag_vox import Model, box, cbox, poly, cyl

ORANGE, WHITE, FRAME, BLACK, GLOW, METAL, GREY = 1, 2, 3, 4, 6, 7, 10
TAG = "FalcoJet_r3_20261106"
HERE, Mm, T, STUD, HRP = R1.HERE, R1.Mm, R1.T, R1.STUD, R1.HRP
groove_glow = R2.groove_glow
LEAD, TRAIL, OUT_POD = R2.LEAD, R2.TRAIL, R2.OUT_POD
TOP_PLATES = True     # r3 윗면 흰 판·주황 조각. r4 = False(유저 "지저분해 보여 → 이전으로")


def mx(sx, a, b):
    """왼쪽(+X) 범위 (a, b) → 쪽 sx 의 범위."""
    return (a, b) if sx > 0 else (-b, -a)


def plate(p, G, sx, x, y, z, c=WHITE, ch=1):
    """돋을 판(위 면에 얹는 얇은 판, 모서리 1칸 모따기)."""
    p.add(cbox(G, mx(sx, *x), y, z, {"xy": ch}), c)


def claw(p, G, sx, xc, y_back, y_tip, z_top, z_bot, hw0=3):
    """계단식 주황 쐐기(발톱): 뒤 → 앞으로 3단 좁아지고 낮아짐. 각 단 앞 아래 45° 모따기."""
    L = y_back - y_tip
    steps = [(0.0, 0.45, hw0, 0), (0.45, 0.75, hw0 - 1, 1), (0.75, 1.0, hw0 - 2, 2)]    # (시작, 끝 비율, 반폭, 위에서 내려감)
    for a, b, hw, dz in steps:
        y1 = y_back - a * L + 1; y0 = y_back - b * L                     # +1 = 앞 단과 1칸 겹쳐 이음
        p.add(cbox(G, (sx * xc - hw, sx * xc + hw), (y0, y1), (z_bot + dz, z_top - dz),
                   {"-yz": min(2, hw), "xz": 1}), ORANGE)


# ------------------------------------------------------------------ 동체
def build_body(M):
    p = M.part("JetBody", (-52, -137, -26), (53, 90, 19), (0, 0, 0))
    G = p.g(); X, Y, Z = G
    AX = np.abs(X)
    # N 기수 · 용골 · 가운데 몸 = r2 와 같음
    nose = (poly(G, "z", [(0, -136), (3, -136), (8, -118), (10, -88), (0, -88)], sym=True)
            & poly(G, "x", [(-136, -7), (-136, -2), (-118, 4), (-88, 8), (-88, -12), (-118, -10)])
            & ((AX + np.abs(Z + 2)) <= 15))
    p.add(nose, WHITE)
    p.add(box(G, (-4, 4), (-92, -34), (-13, -10)), FRAME)
    p.paint(nose & (AX <= 2) & (Z >= 0), FRAME)
    p.paint(nose & (Z <= -8), FRAME)
    p.paint(nose & (Y <= -129), FRAME)
    core = cbox(G, (-14, 14), (-37, 84), (-16, 14), {"xz": 5, "-yz": 4})
    p.add(core, FRAME)
    p.paint(core & (Z <= -12), GREY)

    for sx in (1, -1):
        sg = "+" if sx > 0 else "-"
        side = (X * sx > 0)
        # I-a 앞 흰 덮개: 앞 위를 45° 로 크게 깎음(8칸) → 숙인 어깨 모양, 바깥 앞 모서리 둥글게 (1차 10:8 은 계단 줄무늬)
        fc = cbox(G, mx(sx, 14, 38), (-29, 4), (-14, 12),
                  {"-y+z": 8, "-y-z": 3, sg + "x+z": 6, sg + "x-z": 5, "-y" + sg + "x": 5})
        p.add(fc, WHITE)
        p.paint(fc & (Z <= -10), GREY)
        # 입: 깎인 앞면 아래쪽에 짙은 사각(깊이 8) + 안 위 경사판(짙은)
        mouth = box(G, None, (-29, -22), (-11, 2)) & (AX >= 19) & (AX <= 33) & side
        p.cut(mouth)
        p.add(box(G, None, (-21, -21), (-11, 2)) & (AX >= 19) & (AX <= 33) & side, BLACK)
        p.add(box(G, None, (-27, -21), (0, 2)) & (AX >= 19) & (AX <= 33) & side & (Y - 2 * Z <= -25), FRAME)
        p.add(box(G, None, (-28, -21), (-11, -10)) & (AX >= 19) & (AX <= 33) & side, FRAME)     # 아래 턱
        # 바깥 면 짙은 판(파임 1칸, 앞 위 모서리 1:1 로 깎은 사다리꼴)
        pan = (poly(G, "x", [(-26, -10), (2, -10), (2, 5), (-20, 5), (-26, -1)]) & (AX >= 35) & side)   # 앞 위 모서리 1:1 로 깎은 큰 판(옆 아래 절반)
        p.groove(pan, FRAME)
        # I-b 뒤 덮개: 한 단 낮고(위 z 10) 좁게, 뒤 바깥 비스듬히
        rc = cbox(G, mx(sx, 15, 35), (4, 30), (-14, 10), {sg + "x+z": 5, "+y" + sg + "x": 8, "+yz": 4})
        p.add(rc, WHITE)
        p.paint(rc & (Z <= -10), GREY)
        p.paint(fc & (AX <= 17) & (Z >= 9), ORANGE)                    # 안쪽 위 주황 줄(앞 덮개)
        if TOP_PLATES:
            plate(p, G, sx, (30, 35), (14, 24), (11, 12), ORANGE)      # 뒤 덮개 위 주황 덩어리(흰 판 옆)
            plate(p, G, sx, (17, 28), (8, 20), (11, 12))               # 뒤 덮개 위 흰 돋을 판
        # I-c 날개 뿌리 짙은 ㄷ자 틀(앞으로 열림) + 안 검정
        fr = cbox(G, mx(sx, 35, 45), (2, 16), (-12, 4), {"xz": 2})
        p.add(fr, FRAME)
        p.cut(box(G, mx(sx, 37, 43), (2, 12), (-10, 2)))
        p.add(box(G, mx(sx, 37, 43), (13, 13), (-10, 2)), BLACK)
        # 안 주황 발톱: ㄷ자 틀에서 앞으로, 날개 앞전(y ≈ −13)보다 13칸 더 나옴(1차는 날개 밑에 숨음)
        claw(p, G, sx, 44, 10, -26, -6, -13, hw0=4)
        # P 안쪽 미사일 포드: 짙은 통 + 옆 회색 줄 + 짙은 계단식 앞(주황 아님)
        cx = 31
        p.add(cbox(G, mx(sx, cx - 4, cx + 4), (-14, 30), (-24, -17), {"xz": 2}), FRAME)
        p.add(box(G, mx(sx, cx - 2, cx + 2), (-8, 24), (-17, -13)), FRAME)          # 포드 받침(흡기구 밑에 붙임)
        p.paint(box(G, None, (-12, 28), (-21, -20)) & (AX == cx + 4) & side, GREY)
        p.add(cbox(G, mx(sx, cx - 3, cx + 3), (-19, -14), (-23, -18), {"xz": 1}), FRAME)
        p.add(cbox(G, mx(sx, cx - 2, cx + 2), (-22, -19), (-22, -19), {"-yz": 1}), FRAME)
        p.add(box(G, mx(sx, cx - 1, cx + 1), (-19, -19), (-21, -20)), BLACK)     # 앞 끝 구멍 자리

    # V 등 V 발광(r2) + V 팔 끝 주황 마개(새)
    v = (np.abs((Y + 29) - 2 * AX) <= 8) & (AX <= 15) & (Z >= 12)
    groove_glow(p, v)
    p.add(box(G, (-3, 3), (-37, -30), (14, 16)), ORANGE)               # V1
    p.add(box(G, (-5, 5), (15, 27), (14, 15)), ORANGE)                 # V2
    for sx in (1, -1) if TOP_PLATES else ():
        p.add(cbox(G, mx(sx, 12, 17), (-6, 2), (13, 16), {"xz": 1, "-yz": 1}), ORANGE)   # V 팔 끝 주황 마개
    # 윗면 흰 판(띄엄띄엄 — 컨셉 큰 그림): 가운데 척추 2 · 엔진 사이 2쌍 · 엔진 위 2쌍
    p.add(cbox(G, (-9, 9), (28, 46), (14, 16), {"xz": 1}), WHITE)      # S
    if TOP_PLATES:
        p.add(cbox(G, (-7, 7), (50, 60), (15, 16), {"xy": 1}), WHITE)
    p.add(cbox(G, (-30, 30), (28, 72), (-8, 8), {"xz": 3}), FRAME)    # 엔진 사이 짙은 몸
    for sx in (1, -1) if TOP_PLATES else ():
        plate(p, G, sx, (16, 27), (34, 44), (9, 10))
        plate(p, G, sx, (18, 26), (50, 58), (9, 10))
        plate(p, G, sx, (22, 28), (60, 68), (9, 10), ORANGE)          # 꼬리 뿌리 앞 주황 조각

    # E 엔진(r2) — 위 흰 판 2장으로
    for sx in (1, -1):
        x0, x1 = mx(sx, 30, 48)
        nac = cbox(G, (x0, x1), (22, 76), (-12, 10), {"xz": 4, "-yz": 6})
        p.add(nac, FRAME)
        if TOP_PLATES:
            plate(p, G, sx, (32, 46), (28, 38), (11, 12))
            plate(p, G, sx, (34, 44), (42, 52), (11, 12))
        else:                                                          # r2 그대로: 엔진 위 흰 판 1장
            p.add(cbox(G, (x0 + 2, x1 - 2), (30, 44), (11, 12), {"xy": 1}), WHITE)
        cx = (x0 + x1) / 2
        p.cut(box(G, (cx - 5, cx + 5), (72, 76), (-8, 6)))
        p.add(box(G, (cx - 5, cx + 5), (71, 71), (-8, 6)), BLACK)
        p.add(box(G, (cx - 2, cx + 2), (71, 71), (-3, 1)), GLOW)
        for gx in (cx - 5, cx, cx + 5):
            groove_glow(p, box(G, (gx, gx), (58, 70), (9, 10)) & nac)
        xo = x1 if sx > 0 else x0
        groove_glow(p, box(G, (xo, xo), (58, 70), None) & ((Z == -3) | (Z == 3)) & nac)
    cen = cbox(G, (-11, 11), (30, 84), (-10, 15), {"xz": 4})
    p.add(cen, FRAME)
    p.cut(box(G, (-6, 6), (80, 84), (-6, 10)))
    p.add(box(G, (-6, 6), (79, 79), (-6, 10)), BLACK)
    p.add(box(G, (-2, 2), (79, 79), (0, 4)), GLOW)
    for gx in (-5, 0, 5):
        groove_glow(p, box(G, (gx, gx), (66, 78), (14, 15)) & cen)
    # K 기관포(r2)
    for sx in (1, -1):
        xs = mx(sx, 12, 16)
        p.add(box(G, xs, (-46, -34), (-10, -2)), ORANGE)
        p.cut(box(G, xs, (-44, -36), (-8, -4)) & (AX >= 15))
        p.add(box(G, xs, (-44, -36), (-8, -4)) & (AX == 14), BLACK)
        p.add(cyl(G, "y", (sx * 14, -6), 1.5, rng=(-53, -47)), METAL)
    p.trim()
    return p


# ------------------------------------------------------------------ 날개: r2 + 뿌리 위 흰 판 + 바깥 포드 계단식 주황 코
def build_wing(M):
    R2.build_wing(M)
    M.parts.pop("JetWingR")
    p = M.parts["JetWingL"]
    # 경계 넓히기(뿌리 위 판 z −1..0 · 포드 코 앞으로)
    lo, hi = np.array([28, -26, -14]), np.array([114, 50, 4])
    a = np.zeros(tuple(hi - lo), np.uint8); o = p.lo - lo
    a[o[0]:o[0] + p.a.shape[0], o[1]:o[1] + p.a.shape[1], o[2]:o[2] + p.a.shape[2]] = p.a
    p.a, p.lo, p.hi = a, lo, hi
    G = p.g(); X, Y, Z = G
    # 바깥 포드: r2 주황 코를 지우고 계단식 발톱으로
    p.cut(box(G, (OUT_POD - 4, OUT_POD + 4), (-14, -7), (-12, -6)))
    claw(p, G, 1, OUT_POD, -6, -24, -6, -12, hw0=4)
    p.paint(box(G, (OUT_POD + 3, OUT_POD + 3), (-4, 20), (-9, -8)), GREY)   # 포드 바깥 회색 줄
    # 뿌리 위 흰 돋을 판 2(흰 띠 위, 앞전과 나란히 계단)
    if TOP_PLATES:
        for x0, x1, y0, y1 in ((34, 44, LEAD(44) + 4, LEAD(44) + 16), (46, 56, LEAD(56) + 4, LEAD(56) + 14)):
            p.add(cbox(G, (x0, x1), (round(y0), round(y1)), (-1, 0), {"xy": 1}), WHITE)
        p.add(cbox(G, (36, 46), (round(LEAD(46)) + 18, round(LEAD(46)) + 26), (-1, 0), {"xy": 1}), ORANGE)  # 흰 판 뒤 주황 덩어리
    p.trim()
    M.mirror("JetWingL", "JetWingR", "JetBody")
    return p


SHIFT_Y = R2.SHIFT_Y


def build_all():
    M = Model()
    build_body(M); R2.build_cockpit(M); build_wing(M); R2.build_tail(M)
    for p in M.parts.values():
        p.lo = p.lo + np.array([0, SHIFT_Y, 0]); p.hi = p.hi + np.array([0, SHIFT_Y, 0])
        p.pivot = (p.pivot[0], p.pivot[1] + SHIFT_Y, p.pivot[2])
    return M


def attachments():
    A, Gl = R2.attachments()
    A["JetMissile1"] = ("JetBody", (31, -23 + SHIFT_Y, -20.5), "-Z")      # 안쪽 포드 앞 끝(계단 앞)
    A["JetMissile3"] = ("JetBody", (-31, -23 + SHIFT_Y, -20.5), "-Z")
    A["JetMissile2"] = ("JetWingL", (OUT_POD, -25 + SHIFT_Y, -9), "-Z")    # 바깥 발톱 끝
    A["JetMissile4"] = ("JetWingR", (-OUT_POD, -25 + SHIFT_Y, -9), "-Z")
    return A, Gl


hitbox = R2.hitbox
stats = R1.stats
world_cells = R1.world_cells

if __name__ == "__main__":
    import json
    import check_model as C
    M = build_all()
    C.check(M)
    st = stats(M)
    print(json.dumps({k: v for k, v in st.items() if k != "parts"}, ensure_ascii=False))
