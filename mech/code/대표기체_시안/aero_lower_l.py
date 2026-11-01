"""
aero_lower_l.py — Aero 하체 1차: 고간부·스커트 재디자인 (2026-10-26 15:08~)

유저: "맨 위에 투구 꽁지 갈래를 빼고, 시안들 바탕으로 하체도 재디자인해줘. 특히 고간부와 스커트를 다시."
기체 = aero_colors.build()(상체 W1 + P1 얼굴 + T1 투구 띠 + 다리 색 규칙) − 투구 갈래(H_HelmFork).
관절(HIP·KNEE·ANKLE)·다리 골격은 그대로 — 리깅·스윕 표가 이 위치에 묶여 있음.

레퍼런스 하체 공통점 [관찰 — 흰/적 전신 · 주황/회색 전신 · 이전 주황 기체 레퍼런스들, 형태 언어만]:
  L1 고간부 = 가운데 방패판 한 장이 아래로 뾰족(V), 가운데 세로 능선, 끝만 강조색 · 주위로 짙은 프레임이 보임
  L2 앞 스커트 = 좁고 각진 판 두 장이 八 로 벌어짐, 아래 끝 뾰족, 뒤에 한 장 더 겹쳐 아래·바깥으로 비어져 나옴(깃털식)
  L3 옆 스커트 = 엉덩이 관절을 덮는 큰 판, 바깥으로 들림, 아래 끝 뾰족 · 바깥면 작은 등
  L4 뒤 스커트 = 엉덩이를 덮는 방패꼴 판 + 뒤 겹판
  L5 허벅지 = 앞·바깥 장갑판 + 안쪽 프레임 드러남 · 판을 단차로 쪼갬
  L6 무릎 = 뾰족한 무릎 보호대, 강조색은 끝에만(r1 은 무릎 전체가 주황 덩어리)
  L7 허리 = 가슴과 골반 사이 짙고 가는 마디
안: L1 긴 앞 스커트(깃털처럼 길게, 허벅지 중간까지) / L2 짧은 앞 스커트 + 큰 옆 스커트
    L3·L4(15:57 "스커트 앞면 다시. 양옆 스커트는 넓적, 고간부는 스커트보다 길게" + 흰/적 기체 하체 사진): 넓적한 앞 스커트 + 긴 고간부(끝 z136 / z128)
"""
import numpy as np

from flag_vox import box, cbox, poly, cyl, ell, rotx, roty, rotz
import aero_r1 as A
import aero_faces as F
import aero_colors as Cc

WHITE, LGRAY, FRAME, BLACK, ACC, GLOW, METAL = 2, 10, 3, 4, 1, 6, 7
LOWER = []


def _B(G):
    X, Y, Z = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    return lambda m: np.broadcast_to(m, shp)


def _light(p, G, B, face_axis, face_val, inward, m):
    """작은 등: 겉면 칸을 파고 한 칸 안쪽에 발광."""
    X, Y, Z = G
    A_ = {"x": X, "y": Y, "z": Z}[face_axis]
    p.cut(B(m & (A_ == face_val)))
    p.add(B(m & (A_ == face_val + inward)), GLOW)


# ------------------------------------------------------------------ 골반 + 고간부 (L1·L7)
def pelvis(M, kind):
    p = M.parts["Pelvis"]
    p.a[:] = 0
    G = p.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    p.add(cbox(G, (-14, 14), (-12, 12), (152, 182), {"xy": 4, "-zx": (10, 10)}), FRAME)        # 골반 속
    for s in (1, -1):                                                                          # 엉덩이 관절
        p.add(cyl(G, "x", (0, 166), 7, (s * 8, s * 24)), FRAME)
        p.add(cyl(G, "x", (0, 166), 3, (s * 6, s * 26)), METAL)
    p.add(cbox(G, (-16, 16), (-14, 13), (178, 186), {"xy": 4}), FRAME)                        # 허리 띠(짙게 — L7)
    p.add(cbox(G, (-12, 12), (-16, -14), (180, 185), {"x-y": 2}), LGRAY)                      # 띠 앞 얇은 판
    p.cut(B((ax <= 12) & (Y <= -15) & (Z == 182)))                                             # 띠 판 가로 단차
    # 고간 방패: 가운데 한 장, 아래 45° 로 모여 z150 에서 뾰족
    # v2: 방패를 스커트보다 2칸 앞(-22)으로, 양옆은 짙은 틈 — v1 은 흰 스커트와 한 면이 돼 흰 앞치마로 읽힘
    if kind in ("L3", "L4"):
        _crotch_long(p, G, B, 136 if kind == "L3" else 128)
        return
    shield = (ax <= np.minimum(7, (Z - 150) * 0.5)) & (Z <= 179) & (Y >= -22) & (Y <= -15)    # v3: 아래 V 를 1:2 로 길게(v2 = 넓은 사각 + 짧은 V = 문짝)
    shield &= ~((Y <= -22) & (Z >= 176))                                                       # 위 앞 모서리 한 칸(띠 밑으로 파고드는 느낌)
    p.add(B(shield), WHITE)
    # v3: 가운데 세로 능선 + 가로 홈 = 문짝·손잡이 → 안쪽에 같은 화살꼴 작은 판을 한 칸 앞에(화살 속 화살)
    ridge = (ax <= np.minimum(3, (Z - 154) * 0.5)) & (Z <= 175) & (Y == -23)
    p.add(B(ridge), WHITE)
    p.paint(B((shield | ridge) & (Z <= 157)), ACC)                                             # 끝만 강조색
    # v2: 가운데 등은 뺌(배꼽처럼 읽힘)
    # 방패 양옆: 짙은 프레임이 한 단 뒤에서 보임(방패·스커트가 따로 떨어진 덩어리로)
    side = (ax >= 8) & (ax <= 13) & (Z <= 179) & (Z >= 154 + (ax - 8)) & (Y >= -16) & (Y <= -13)
    p.add(B(side), FRAME)


def _crotch_long(p, G, B, tip):
    """L3·L4(유저 15:57 + 흰/적 기체 하체 사진): 고간부가 앞 스커트보다 길게 — 좁고 긴 판이 허벅지 사이로 내려옴.
    윗마디(반폭 7, 세로 슬릿 등) → 좁아지는 아랫마디(반폭 5, 앞으로 한 칸 더) → 1:2 V 끝(강조색). 가운데 돋은 띠."""
    X, Y, Z = G; ax = np.abs(X)
    up = (ax <= 7) & (Z >= 162) & (Z <= 179) & (Y >= -24) & (Y <= -15)
    up &= ~((Y <= -24) & (Z >= 177))                                                           # 위 앞 모서리(띠 밑으로)
    p.add(B(up), WHITE)
    back = -16 - np.clip(150 - Z, 0, None) * 0.5                                               # 아래로 갈수록 얇아짐
    lo = (ax <= np.minimum(5, (Z - tip) * 0.5)) & (Z >= tip) & (Z <= 161) & (Y >= -25) & (Y <= back)
    p.add(B(lo), WHITE)
    strip = (ax <= np.minimum(2, (Z - tip - 4) * 0.5)) & (Z <= 158) & (Y == -26)               # 가운데 돋은 띠(화살 속 화살)
    p.add(B(strip), WHITE)
    p.paint(B((lo | strip) & (Z <= tip + 5)), ACC)                                             # 끝만 강조색
    _light(p, G, B, "y", -24, 1, (ax < 1) & (Z >= 169) & (Z <= 173))                           # 윗마디 세로 슬릿 등(한 칸 폭 — 점이면 배꼽)
    p.add(B((ax <= 4) & (Y >= -16) & (Y <= -11) & (Z >= 148) & (Z <= 162)), FRAME)             # 아랫마디 뒤 경첩 뭉치(골반 속과 이음)
    side = (ax >= 8) & (ax <= 13) & (Z <= 179) & (Z >= 154 + (ax - 8)) & (Y >= -16) & (Y <= -13)
    p.add(B(side), FRAME)


# ------------------------------------------------------------------ 스커트 (L2·L3·L4)
def skirts(M, kind):
    long_f = kind == "L1"
    wide = kind in ("L3", "L4")
    # 앞 스커트: 좁은 각진 판(흰) + 뒤 겹판(밝은 회색)이 아래·바깥으로 비어져 나옴
    f = M.part("SkirtFL", (2, -32, 128), (42, -8, 190), pivot=(11, -19, 184), parent="Pelvis")
    G = f.g(); X, Y, Z = G; B = _B(G)
    if wide:
        _skirt_wide(f, G, B)
    else:
        _skirt_narrow(f, G, B, long_f)
    # 옆 스커트: 엉덩이 관절을 덮는 연(鳶)꼴 판, 바깥으로 들림
    _side_skirt(M, kind == "L2")
    _back_skirt(M)
    M.mirror("SkirtFL", "SkirtFR", "Pelvis")
    M.mirror("SkirtSL", "SkirtSR", "Pelvis")
    LOWER.extend(["SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR", "SkirtB"])


def _skirt_wide(f, G, B):
    """L3·L4: 넓적한 앞 스커트 — 위 넓게(x 9~31), 아래 변은 안쪽이 높고 바깥 아래가 가장 낮음(z150), 고간부보다 짧음.
    안·바깥 두 판(바깥 판 한 칸 뒤 단차) · 위 띠 단차 · 바깥 아래 끝만 강조색 · 짙은 뒤 겹판."""
    X, Y, Z = G
    main = poly(G, "y", [(9, 186), (31, 186), (33, 178), (33, 160), (28, 150), (9, 163)], rng=(-23, -20))
    f.add(B(main), WHITE)
    f.cut(B(main & (Z == 179) & (Y == -23)))                                                    # 위 띠 아래 단차 홈
    f.cut(B(main & (X >= 23) & (Z <= 178) & (Y == -23)))                                        # 바깥 판 한 칸 뒤(안·바깥 두 판)
    f.paint(B(main & (X >= 24) & (Z <= 156 + 0.6 * (X - 24))), ACC)                             # 바깥 아래 끝 삼각만 강조색
    back = poly(G, "y", [(12, 182), (33, 182), (35, 174), (35, 156), (30, 146), (12, 159)], rng=(-19, -18))
    f.add(B(back), FRAME)                                                                       # 앞 판 윤곽을 (2,-4) 옮긴 짙은 겹판
    f.add(B(poly(G, "y", [(12, 184), (30, 184), (30, 164), (12, 168)], rng=(-17, -16))), FRAME)
    f.rot = roty(-12) @ rotx(-11)


def _skirt_narrow(f, G, B, long_f):
    X, Y, Z = G
    zb = 146 if long_f else 160                                                                 # 아래 끝 높이
    main = poly(G, "y", [(12, 186), (25, 186), (25, zb + 10), (22, zb), (16, zb + 12), (12, zb + 22)], rng=(-23, -20))   # v2: 안쪽 변 9 → 12(방패와 틈)
    f.add(B(main), WHITE)
    f.add(B(main & (Z >= 180) & (Y == -23)), WHITE)
    f.cut(B(main & (Z == 179) & (Y == -23)))                                                    # 위 띠 아래 단차 홈
    f.paint(B(main & (Z <= zb + 6)), ACC)                                                       # 끝만 강조색
    back = poly(G, "y", [(15, 182), (28, 182), (28, zb + 5), (25, zb - 5), (19, zb + 7), (15, zb + 17)], rng=(-19, -18))   # v2: 앞 판 윤곽을 (3,-5) 옮긴 꼴 — 아래 가장자리만 띠로 보임(v1 은 허벅지 위 얼룩)
    f.add(B(back), FRAME)                                                                       # v3: 밝은 회색 겹판 = 흰 허벅지 위 얼룩 → 짙게(앞 판 밑 그늘 층)                                                                       # 깃털식 뒤 겹판
    f.add(B(poly(G, "y", [(14, 184), (24, 184), (24, zb + 14), (14, zb + 24)], rng=(-17, -16))), FRAME)   # 받침
    f.rot = roty(-10) @ rotx(-11)                                                               # v2: 八 더 벌림


def _side_skirt(M, big):
    s_ = M.part("SkirtSL", (18, -24, 120), (38, 24, 190), pivot=(27, 0, 184), parent="Pelvis")
    G = s_.g(); X, Y, Z = G; B = _B(G)
    zt = 136 if big else 146
    yw = 18 if big else 15
    kite = poly(G, "x", [(-yw, 186), (yw - 2, 186), (yw, 178), (yw - 4, zt + 12), (3, zt), (-8, zt + 10), (-yw, zt + 22)], rng=(27, 30))
    s_.add(B(kite), WHITE)
    s_.paint(B(kite & (Z <= zt + 22) & (Z >= zt + 5)), LGRAY)                                   # 아래쪽 판은 밝은 회색(단차 홈으로 나눔)
    s_.cut(B(kite & (X >= 30) & (Z == zt + 23)))
    s_.paint(B(kite & (Z < zt + 5)), ACC)                                                       # 끝만 강조색
    _light(s_, G, B, "x", 30, -1, (Y >= -9) & (Y <= -7) & (Z >= 176) & (Z <= 177))             # 바깥면 작은 등
    s_.add(B(poly(G, "x", [(-yw + 3, 184), (yw - 3, 184), (yw - 6, zt + 16), (-yw + 3, zt + 26)], rng=(24, 26))), FRAME)
    s_.rot = roty(-12)


def _back_skirt(M):
    # 뒤 스커트: 방패꼴(흰) + 뒤 겹판(밝은 회색)이 아래로 비어져 나옴
    t = M.part("SkirtB", (-18, 8, 120), (19, 30, 190), pivot=(0, 14, 184), parent="Pelvis")
    G = t.g(); X, Y, Z = G; B = _B(G)
    t.add(B(poly(G, "y", [(-0.6, 186), (13, 186), (13, 168), (5, 152), (-0.6, 150)], rng=(14, 17), sym=True)), WHITE)
    t.paint(B((Z <= 156)), ACC)
    t.cut(B((Z == 175) & (Y == 17)))                                                            # 가로 단차 홈
    t.add(B(poly(G, "y", [(-0.6, 180), (9, 180), (9, 160), (3, 144), (-0.6, 142)], rng=(18, 19), sym=True)), LGRAY)
    t.rot = rotx(18)                                                                            # (가운데 x=0 열: 다각형 꼭짓점을 -0.6 으로 — 0 이면 경계라 빠져 좌우 반쪽이 섬 2개)


# ------------------------------------------------------------------ 허벅지 (L5)
def thigh(M):
    t = M.parts["UpperLegL"]
    t.a[:] = 0
    G = t.g(); X, Y, Z = G; B = _B(G)
    t.add(ell(G, A.HIP, (9, 9, 9)), FRAME)
    t.add(cbox(G, (9, 25), (-8, 9), (110, 160), {"xy": 4}), FRAME)                             # 허벅지 뼈대(안쪽·뒤로 드러남)
    # 앞 장갑(흰): 아래 끝 V(무릎 쪽), 위 1/3 은 한 칸 앞 판(단차로 쪼갬)
    th = cbox(G, (8, 28), (-13, -3), (118, 156), {"x-y": 4, "-z-y": 5, "+z-y": 5, "-zx": (20, 3)})
    th &= Z >= 118 + np.abs(X - 18)
    t.add(B(th), LGRAY)                                                                         # v2: 아래쪽 밝은 회색(흰 스커트·흰 허벅지가 한 덩어리 → 두 톤)
    t.paint(B(th & (Z >= 144)), WHITE)
    up = cbox(G, (11, 25), (-14, -12), (145, 155), {"x-y": 2, "+z-y": 2})
    t.add(B(up), WHITE)                                                                         # 위 판(한 칸 앞)
    t.cut(B((Z == 143) & (Y <= -12) & (X >= 9) & (X <= 27)))                                    # 위 판 밑 단차 홈
    # 바깥 판(밝은 회색): 한 칸 뒤, 뒤 아래 45°, 작은 등
    out = poly(G, "x", [(-11, 156), (8, 156), (8, 134), (-1, 124), (-11, 130)], rng=(28, 30))
    t.add(B(out), LGRAY)
    _light(t, G, B, "x", 30, -1, (Y >= -7) & (Y <= -6) & (Z >= 136) & (Z <= 138))
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    LOWER.extend(["UpperLegL", "UpperLegR"])


# ------------------------------------------------------------------ 무릎·정강이 (L6)
def shin(M):
    s = M.parts["LowerLegL"]
    G = s.g(); X, Y, Z = G; B = _B(G)
    s.paint(B((s.a == ACC) & (Z <= 108)), WHITE)                                                # 무릎 보호대: 흰 판, 위 끝만 강조색
    s.cut(B((s.a == WHITE) & (Z == 52) & (Y <= -14)))                                           # 아래 정강이 보호대 가로 단차 홈
    _light(s, G, B, "y", -16, 1, (X >= 18) & (X <= 20) & (Z >= 60) & (Z <= 61))                # 정강이 작은 등(왼·오른 다리 하나씩)
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")


def build(kind="L1"):
    M = Cc.build()
    M.parts.pop("H_HelmFork", None)                                                            # 투구 갈래 뺌(유저 15:08)
    while "H_HelmFork" in F.HEAD_PARTS:
        F.HEAD_PARTS.remove("H_HelmFork")
    LOWER.clear()
    pelvis(M, kind)
    skirts(M, kind)
    thigh(M)
    shin(M)
    return M


def build_all():
    return build("L1")
