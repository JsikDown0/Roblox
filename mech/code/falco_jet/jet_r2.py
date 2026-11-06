"""
jet_r2.py — FalcoJet r2: 유저 컨셉 c1(레퍼런스/FALCO/concept_jet_c1.png) + 윤곽 읽기 r1 확인 [결정 11-06 "이대로 · 제안값으로"] (2026-11-06)

읽기 값(윤곽읽기_jet_r1.png, 날개 폭 21.7 기준 1px = 0.537칸)을 칸으로 옮김. 위 그림 px → 칸: x = (px − 1310)·0.537 · y = −135 + (998 − py)·0.537.
답: 1 뒷전 = 컨셉대로 곧게 · 2 P = 미사일 포드(안 = 흡기구 밑 → JetBody, 바깥 = 날개 밑) · 3 K = 기관포 → JetMuzzle ·
    4 날씬한 몸 유지(판정은 JetHitBox, HRP 는 위아래로 튀어나옴) · 5 가운데 엔진 = 발광만(불꽃 부착점 없음) ·
    6 겉면 발광(C1 · W4 · F1 · E1) = 1칸 홈 속 · 7 상반각 = 평평(판정 불가 → 정수비 안 되는 각 대신 0, DIHEDRAL 로 바꿈).
카나드 = 컨셉에 없음 → 뺌. 칸·축·색 번호 = r1(jet_r1.py) 과 같음.
"""
import numpy as np

import jet_r1 as R1
from flag_vox import Model, box, cbox, poly, cyl, roty

ORANGE, WHITE, FRAME, BLACK, GLOW, METAL, GREY = 1, 2, 3, 4, 6, 7, 10
TAG = "FalcoJet_r2_20261106"
HERE, Mm, T, STUD, HRP = R1.HERE, R1.Mm, R1.T, R1.STUD, R1.HRP
TAIL_CANT = float(np.degrees(np.arctan(1 / 3)))   # 1:3 (18.4°) — 정면 읽기 17°
DIHEDRAL = 0.0


def groove_glow(p, m):
    p.groove(m, GLOW)


# ------------------------------------------------------------------ 동체
def build_body(M):
    p = M.part("JetBody", (-50, -137, -26), (51, 90, 18), (0, 0, 0))
    G = p.g(); X, Y, Z = G
    AX = np.abs(X)
    # N 기수(끝 ~ 조종석 앞): 위 실루엣 · 옆 실루엣 · 모따기
    nose = (poly(G, "z", [(0, -136), (3, -136), (8, -118), (10, -88), (0, -88)], sym=True)
            & poly(G, "x", [(-136, -7), (-136, -2), (-118, 4), (-88, 8), (-88, -12), (-118, -10)])
            & ((AX + np.abs(Z + 2)) <= 15))
    p.add(nose, WHITE)
    p.add(box(G, (-4, 4), (-92, -34), (-13, -10)), FRAME)              # 조종석 밑 용골(기수 ↔ 몸 이음, 조종석 속에 묻힘)
    p.paint(nose & (AX <= 2) & (Z >= 0), FRAME)                       # 위 가운데 짙은 줄
    p.paint(nose & (Z <= -8), FRAME)                                   # 아랫면 짙은
    p.paint(nose & (Y <= -129), FRAME)                                 # 끝 짙은 덩어리
    # 가운데 몸(짙은 척추): 조종석 뒤 ~ 가운데 엔진
    core = cbox(G, (-14, 14), (-37, 84), (-16, 14), {"xz": 5, "-yz": 4})
    p.add(core, FRAME)
    p.paint(core & (Z <= -12), GREY)
    # I 흡기구 2(흰 덮개 · 앞 짙은 입 · 안쪽 위 주황 줄)
    for sx in (1, -1):
        sg = "+" if sx > 0 else "-"
        ik = cbox(G, (14, 38) if sx > 0 else (-38, -14), (-29, 30), (-16, 12),
                  {"-y+z": 4, sg + "x+z": 5, sg + "x-z": 4, "+y" + sg + "x": 8, "+yz": 4})
        p.add(ik, WHITE)
        p.paint(ik & (Z <= -10), GREY)
        mouth = box(G, None, (-29, -24), (-13, 8)) & (AX >= 20) & (AX <= 34) & (X * sx > 0)
        p.cut(mouth)
        p.add(box(G, None, (-23, -23), (-13, 8)) & (AX >= 20) & (AX <= 34) & (X * sx > 0), BLACK)
        p.paint(ik & (AX <= 17) & (Z >= 9) & (Y <= 10), ORANGE)       # 안쪽 위 주황 줄(위 그림 x 1320~1336)
    # V 등 V 발광: 꼭짓점 (0, −29) · 팔 끝 (±14, −1) = 1:2, 홈 속
    v = (np.abs((Y + 29) - 2 * AX) <= 8) & (AX <= 15) & (Z >= 12)      # 팔 굵기 약 7칸(컨셉은 척추 폭을 채우는 큰 V)
    groove_glow(p, v)
    p.add(box(G, (-3, 3), (-37, -30), (14, 16)), ORANGE)               # V1 앞 주황 볏
    p.add(box(G, (-5, 5), (15, 27), (14, 15)), ORANGE)                 # V2 뒤 주황 조각
    p.add(cbox(G, (-9, 9), (28, 46), (14, 16), {"xz": 1}), WHITE)      # S 가운데 흰 판
    # 엔진 사이 짙은 몸(빈틈 없게)
    p.add(cbox(G, (-30, 30), (28, 72), (-8, 8), {"xz": 3}), FRAME)
    # E 옆 엔진 2 + 가운데 1: 짙은 덩어리, 뒤 끝 = 오목 입(안쪽 가운데만 발광), 위·바깥 면 가로 홈 발광(E1)
    for sx in (1, -1):
        x0, x1 = (30, 48) if sx > 0 else (-48, -30)
        nac = cbox(G, (x0, x1), (22, 76), (-12, 10), {"xz": 4, "-yz": 6})
        p.add(nac, FRAME)
        p.add(cbox(G, (x0 + 2, x1 - 2), (30, 44), (11, 12), {"xy": 1}), WHITE)   # 위 흰 판
        cx = (x0 + x1) / 2
        p.cut(box(G, (cx - 5, cx + 5), (72, 76), (-8, 6)))
        p.add(box(G, (cx - 5, cx + 5), (71, 71), (-8, 6)), BLACK)
        p.add(box(G, (cx - 2, cx + 2), (71, 71), (-3, 1)), GLOW)
        for gx in (cx - 5, cx, cx + 5):                                # 위 면 세로 홈 3
            groove_glow(p, box(G, (gx, gx), (58, 70), (9, 10)) & nac)
        xo = x1 if sx > 0 else x0                                      # 바깥 면 가로 홈 2
        groove_glow(p, box(G, (xo, xo), (58, 70), None) & ((Z == -3) | (Z == 3)) & nac)
    cen = cbox(G, (-11, 11), (30, 84), (-10, 15), {"xz": 4})
    p.add(cen, FRAME)
    p.cut(box(G, (-6, 6), (80, 84), (-6, 10)))
    p.add(box(G, (-6, 6), (79, 79), (-6, 10)), BLACK)
    p.add(box(G, (-2, 2), (79, 79), (0, 4)), GLOW)
    for gx in (-5, 0, 5):
        groove_glow(p, box(G, (gx, gx), (66, 78), (14, 15)) & cen)
    # K 기관포: 기수 옆 주황 테 사각 + 짙은 구멍 + 짧은 강철 총열(앞)
    for sx in (1, -1):
        xs = (12, 16) if sx > 0 else (-16, -12)
        p.add(box(G, xs, (-46, -34), (-10, -2)), ORANGE)
        p.cut(box(G, xs, (-44, -36), (-8, -4)) & (AX >= 15))
        p.add(box(G, xs, (-44, -36), (-8, -4)) & (AX == 14), BLACK)
        p.add(cyl(G, "y", (sx * 14, -6), 1.5, rng=(-53, -47)), METAL)
    # P 안쪽 미사일 포드(흡기구 밑): 짙은 통 + 주황 뾰족 앞
    for sx in (1, -1):
        cx = sx * 33
        p.add(cbox(G, (cx - 4, cx + 4), (-14, 30), (-24, -17), {"xz": 2}), FRAME)
        p.add(cbox(G, (cx - 4, cx + 4), (-22, -15), (-24, -17), {"-yx": 3, "-yz": 3}), ORANGE)
    p.trim()
    return p


# ------------------------------------------------------------------ C 조종석(머리 자리)
def build_cockpit(M):
    p = M.part("JetCockpit", (-14, -89, -14), (15, -35, 19), (0, -62, 0), "JetBody")
    G = p.g(); X, Y, Z = G
    AX = np.abs(X)
    hull = (poly(G, "z", [(0, -88), (10, -88), (12, -60), (13, -36), (0, -36)], sym=True)
            & poly(G, "x", [(-88, -12), (-88, 8), (-80, 14), (-60, 17), (-36, 16), (-36, -14)])
            & ((AX + np.abs(Z)) <= 21))
    p.add(hull, WHITE)
    p.paint(hull & (AX <= 7) & (Z >= 9), FRAME)                        # 긴 짙은 캐노피
    p.paint(hull & (Z <= -8), FRAME)
    groove_glow(p, (X == 0) & (Y >= -80) & (Y <= -46) & (Z >= 12))     # C1 가운데 노랑 선(홈 속)
    p.trim()
    return p


# ------------------------------------------------------------------ W 주날개(곧은 뒷전) + 바깥 미사일 포드
WING_PIVOT = (30, 14, -4)
LEAD = lambda x: -12 + (x - 47) * 0.4          # 앞전 5:2 — 읽기 (1398,768)→(1500,726)
TRAIL = lambda x: 40 - (x - 47) * 18 / 55      # 뒷전 ≈ 3:1 — 읽기 (1398,672)→(1500,703)
OUT_POD = 54


def build_wing(M):
    p = M.part("JetWingL", (28, -26, -14), (114, 50, 4), WING_PIVOT, "JetBody")
    G = p.g(); X, Y, Z = G
    plan = poly(G, "z", [(30, LEAD(30)), (102, LEAD(102)), (102, TRAIL(102)), (30, TRAIL(30))])
    wing = plan & (Z >= -5) & (Z <= -2)
    p.add(wing, ORANGE)
    chord = TRAIL(X) - LEAD(X)
    p.paint(wing & (Y <= LEAD(X) + 0.35 * chord), WHITE)                # W1 앞전 흰 띠(시위 35%)
    # W2 끝 짙은 덩어리(+ 뒤 오목 입 = 날개 끝 노즐)
    p.add(cbox(G, (101, 111), (-9, 31), (-7, 2), {"xz": 2, "-yx": 4, "yz": 2}), FRAME)
    p.cut(box(G, (103, 109), (28, 31), (-4, -1)))
    p.add(box(G, (103, 109), (27, 27), (-4, -1)), BLACK)
    p.add(box(G, (105, 107), (27, 27), (-3, -2)), GLOW)
    p.add(cbox(G, (88, 97), (16, 25), (-1, 0), {"xy": 1}), ORANGE)     # W3 끝 앞 주황 돋을 판
    groove_glow(p, box(G, (54, 60), (-6, -3), (-2, -2)) & wing)        # W4 흰 띠 위 발광 점(홈)
    # P 바깥 미사일 포드(날개 밑)
    p.add(cbox(G, (OUT_POD - 3, OUT_POD + 3), (-6, 22), (-11, -6), {"xz": 1}), FRAME)
    p.add(cbox(G, (OUT_POD - 3, OUT_POD + 3), (-12, -7), (-11, -6), {"-yx": 2, "-yz": 2}), ORANGE)
    p.trim()
    if DIHEDRAL:
        p.rot = roty(-DIHEDRAL)                                          # +X 날개: 끝이 위로
    M.mirror("JetWingL", "JetWingR", "JetBody")
    return p


# ------------------------------------------------------------------ F 꼬리 2(긴 칼날, 바깥 1:3)
TAIL_PIVOT = (25, 62, 9)


def build_tail(M):
    p = M.part("JetTailL", (21, 38, 8), (29, 120, 45), TAIL_PIVOT, "JetBody")
    G = p.g(); X, Y, Z = G
    prof = poly(G, "x", [(40, 9), (108, 43), (118, 43), (84, 9)])     # 앞전 2:1 · 뒷전 1:1
    fin = prof & (X >= 23) & (X <= 27)                                 # 두께 5(정면에서 막대로 안 보이게)
    p.add(fin, ORANGE)
    p.add(box(G, (22, 28), (42, 86), (8, 10)), FRAME)                  # 뿌리 받침
    p.paint(fin & (Y >= 104) & (Z >= 37), FRAME)                       # F1 끝 짙은
    groove_glow(p, (X == 27) & (Z >= 39) & (Z <= 40) & (Y >= 108) & (Y <= 116))   # F1 발광(바깥 면 홈)
    p.trim()
    p.rot = roty(TAIL_CANT)
    M.mirror("JetTailL", "JetTailR", "JetBody")
    return p


SHIFT_Y = -10      # 칸 분포 무게 중심을 원점 쪽으로(앞으로 10칸 = 1 스터드). 부착점도 같이 옮김


def build_all():
    M = Model()
    build_body(M); build_cockpit(M); build_wing(M); build_tail(M)
    for p in M.parts.values():
        p.lo = p.lo + np.array([0, SHIFT_Y, 0]); p.hi = p.hi + np.array([0, SHIFT_Y, 0])
        p.pivot = (p.pivot[0], p.pivot[1] + SHIFT_Y, p.pivot[2])
    return M


def _sh(d):
    return {k: (v[0], (v[1][0], v[1][1] + SHIFT_Y, v[1][2])) + tuple(v[2:]) for k, v in d.items()}


def attachments():
    A = {}
    for s, sx in (("L", 1), ("R", -1)):
        A["JetNozzle" + s] = ("JetBody", (sx * 39, 77, -1), "+Z")             # 옆 엔진(주 엔진)
        A["JetWingNozzle" + s] = ("JetWing" + s, (sx * 106, 32, -2.5), "+Z")  # 날개 끝 덩어리 뒤
        A["JetMuzzle" + s] = ("JetBody", (sx * 14, -54, -6), "-Z")            # K 기관포
    # 미사일: 1 = 왼 안(흡기구 밑, JetBody) · 2 = 왼 바깥(날개 밑) · 3 = 오른 안 · 4 = 오른 바깥
    A["JetMissile1"] = ("JetBody", (33, -23, -20.5), "-Z")
    A["JetMissile2"] = ("JetWingL", (OUT_POD, -13, -8.5), "-Z")
    A["JetMissile3"] = ("JetBody", (-33, -23, -20.5), "-Z")
    A["JetMissile4"] = ("JetWingR", (-OUT_POD, -13, -8.5), "-Z")
    A["JetFlashAtt"] = ("JetBody", (0, 0, 0), None)
    Gl = {
        "GlowLightAtt_Visor": ("JetCockpit", (0, -63, 16)),
        "GlowLightAtt_Chest": ("JetBody", (0, -20, 15)),
        "GlowLightAtt_NozzleL": ("JetBody", (39, 70, -1)),
        "GlowLightAtt_NozzleR": ("JetBody", (-39, 70, -1)),
        "GlowLightAtt_NozzleC": ("JetBody", (0, 78, 2)),
    }
    A = _sh(A); A["JetFlashAtt"] = ("JetBody", (0, 0, 0), None)       # 섬광 = 원점(HRP 중심) 그대로
    return A, _sh(Gl)


def hitbox(M):
    """JetHitBox = 동체(기수 ~ 가운데 엔진) 길이 × 폭 7.6(흡기구 바깥) × 높이 4.0, 몸 높이 가운데(z −2)."""
    P = np.vstack([R1.world_cells(M, n)[0] for n in ("JetBody", "JetCockpit")])
    y0, y1 = P[:, 1].min() - 0.5, P[:, 1].max() + 0.5
    return (7.6, 4.0, round((y1 - y0) * STUD, 2)), T((0, (y0 + y1) / 2, -2)).round(3).tolist()


stats = R1.stats
world_cells = R1.world_cells

if __name__ == "__main__":
    import json
    import check_model as C
    M = build_all()
    C.check(M)
    st = stats(M)
    print(json.dumps({k: v for k, v in st.items() if k != "parts"}, ensure_ascii=False))
    for n, v in st["parts"].items():
        print(n, v)
