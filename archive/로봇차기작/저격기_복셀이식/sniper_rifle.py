"""
sniper_rifle.py — 저격기 전용 무기: 롱 스나이퍼 라이플 r1 (2026-10-29 21:27~)

유저: "이제 전용 무기 스나이퍼를 만들어볼까해." + 컨셉 아트 1장(흰·검정·초록 롱라이플).
선례 = aero_rifle.py(AELLO 라이플): 설계 좌표 마스크 rifle_masks(a, b, c) → rifle_only()(혼자) / attach()(오른손 쥠, LowerArmR 자식).
  a = 앞(총구 +) · b = 위 · c = 옆. 쥔 자리 = 손잡이 가운데(GRIP_AB)가 오른 주먹 가운데.
  쉬는 자세 기준 총열 = 아래(−Z) · 라이플 위 = 앞(−Y) — AELLO 와 같은 방향(팔을 앞으로 90° 들면 정면 조준).
컨셉에서 옮긴 것(길이 비율은 개머리 끝 0 · 총구 1 기준 눈대중 [추측]):
  뼈대형 개머리(검정 위 막대 + 사선 버팀 + 흰 개머리 판, 위 막대 옆 흰 판 + 초록 틈) 0~0.2 ·
  손잡이(검정 + 흰 옆 판)·방아쇠울 0.2~0.3 · 기관부(검정 + 번개꼴 흰 옆 판) 0.2~0.45 ·
  조준경(흰 접안부 · 검정 몸통 + 회색 다이얼 · 흰 대물부 + 검정 링 · 초록 렌즈) 0.25~0.5 ·
  위 레일(톱니) 0.25~0.95 · 총열 덮개(검정 각통 + 흰 판 4장 + 옆 초록 띠, 마디 끊김) 0.45~0.97 ·
  가운데 죔쇠 + 접힌 양각대 · 흰 총구(앞면 초록 사각 + 옆 구멍).
길이 202칸(쥔 자리 기준 뒤 36 · 앞 166) = 기체 키 268 의 0.75 [제안: 게임 중장갑 저격총/키 0.83 · AELLO 라이플/키 0.49 사이].
"""
import numpy as np
from matplotlib.path import Path

import flag_vox as fv
from flag_vox import rotx, roty
from sniper_v1 import W1, DK, FR, BK, GM, GL, MT, LG, PAL, EMISSIVE

GRIP_AB = (-10, -14)        # 손잡이 가운데(설계 a, b) = 주먹 가운데
FIST_R = (-29, -1, 135.5)   # 오른 주먹 가운데(쉬는 자세 칸) — sniper_v2 LowerArmL 주먹 cbox (25..33, −7..5, 128..143) 의 거울 [실측]
SCALE = (1.0, 1.0, 1.0)     # (길이, 높이, 폭)


def _pg(a, b, pts):
    """(a, b) 평면 다각형 안(칸 중심)."""
    A, B = np.broadcast_arrays(a, b)
    inside = Path(np.asarray(pts, float)).contains_points(np.stack([A.ravel(), B.ravel()], 1), radius=1e-9)
    return inside.reshape(A.shape)


def _seg(a, b, p0, p1, w):
    """(a, b) 평면 선분 p0→p1 에서 거리 w 이내."""
    p0 = np.asarray(p0, float); d = np.asarray(p1, float) - p0
    t = np.clip(((a - p0[0]) * d[0] + (b - p0[1]) * d[1]) / (d @ d), 0, 1)
    return (a - p0[0] - t * d[0]) ** 2 + (b - p0[1] - t * d[1]) ** 2 <= w * w


def rifle_masks(a, b, c):
    """색 → bool 마스크. a 앞 · b 위 · c 옆(정수 칸). 'cut' = 마지막에 비움, 'glow_in' = 비운 뒤 발광."""
    ac = np.abs(c)
    m = {k: False for k in (W1, DK, FR, BK, MT, LG, GL, "cut", "glow_in")}
    # ── 기관부(검정): 뒤 −14 · 앞 42 · 높이 −6~7 · 폭 9, 위 모서리 한 칸 깎음
    recv = (a >= -14) & (a <= 42) & (b >= -6) & (b <= 7) & (ac <= 4) & ~((b >= 7) & (ac >= 4))
    m[FR] = m[FR] | recv
    # 번개꼴 흰 옆 판(한 칸 돋음) + 끝 초록 틈
    zplate = _pg(a, b, [(-12.5, -0.5), (2.5, -0.5), (8.5, 4.5), (28.5, 4.5), (32.5, 0.5), (42.5, 0.5), (42.5, -3.5),
                        (30.5, -3.5), (26.5, 1.5), (10.5, 1.5), (4.5, -4.5), (-12.5, -4.5)]) & (ac == 5)
    m[W1] = m[W1] | zplate
    m["cut"] = m["cut"] | (zplate & (a >= 34) & (a <= 39) & (b == -2))
    m["glow_in"] = m["glow_in"] | ((ac == 4) & (a >= 34) & (a <= 39) & (b == -2))
    # ── 위 레일(톱니): 기관부 위 · 덮개 위
    rail = ((a >= -10) & (a <= 40) & (b >= 8) & (b <= 9) & (ac <= 2)) | ((a >= 44) & (a <= 144) & (b >= 6) & (b <= 7) & (ac <= 2))
    teeth = rail & (((b == 9) & (a <= 40)) | ((b == 7) & (a >= 44))) & (np.mod(a, 3) == 0)
    m[FR] = m[FR] | (rail & ~teeth)
    # ── 개머리(뼈대형)
    top = (a >= -42) & (a < -14) & (b >= 1) & (b <= 6) & (ac <= 3)
    strut = _seg(a, b, (-40, -15), (-15, -5), 1.7) & (ac <= 2)
    post = (a >= -42) & (a <= -39) & (b >= -16) & (b <= 6) & (ac <= 3)
    m[FR] = m[FR] | top | strut | post
    spanel = (a >= -38) & (a <= -18) & (b >= 2) & (b <= 6) & (ac == 4)                     # 위 막대 옆 흰 판
    m[W1] = m[W1] | spanel
    m["cut"] = m["cut"] | (spanel & (b == 4) & (a >= -34) & (a <= -22))
    m["glow_in"] = m["glow_in"] | ((ac == 3) & (b == 4) & (a >= -34) & (a <= -22))
    butt = (a >= -46) & (a <= -43) & (b >= -19) & (b <= 8) & (ac <= 4) & ~((a == -46) & ((b <= -18) | (b >= 7)))
    m[W1] = m[W1] | butt
    m[BK] = m[BK] | (butt & (a == -46) & (b >= -14) & (b <= 3) & (ac <= 2))                 # 개머리 끝 검정 패드
    # ── 손잡이(뒤로 기욺) + 흰 옆 판 · 방아쇠울 · 방아쇠
    k = np.clip(-6 - b, 0, None) * 0.35
    grip = (b < -6) & (b >= -22) & (a >= -11 - k) & (a <= -4 - k) & (ac <= 2)
    m[FR] = m[FR] | grip
    m[W1] = m[W1] | ((b <= -9) & (b >= -19) & (a >= -10 - k) & (a <= -5 - k) & (ac == 3))
    m[BK] = m[BK] | (grip & (b <= -21))
    guard = (((b == -12) & (a >= -3) & (a <= 9)) | ((a == 9) & (b >= -12) & (b < -6)) | ((a == -3) & (b >= -12) & (b < -6))) & (ac <= 1)
    m[FR] = m[FR] | guard
    m[BK] = m[BK] | ((a >= 1) & (a <= 2) & (b >= -10) & (b < -6) & (ac == 0))
    # ── 탄창(짧음, 앞으로 기욺) + 흰 바닥
    km = np.clip(-6 - b, 0, None) * 0.25
    mag = (b < -6) & (b >= -16) & (a >= 13 + km) & (a <= 23 + km) & (ac <= 3)
    m[FR] = m[FR] | mag
    m[W1] = m[W1] | (mag & (b <= -15))
    # ── 조준경(축 = a, 가운데 b 15 · c 0)
    sb, r = b - 15, np.sqrt((b - 15) ** 2 + c ** 2)
    eye = (a >= 2) & (a <= 15) & (r <= 4.6)
    body = (a >= 16) & (a <= 40) & (r <= 3.4)
    obj = ((a >= 41) & (a <= 48) & (r <= 4.6)) | ((a == 49) & (r <= 5.0)) | ((a >= 50) & (a <= 58) & (r <= 5.6))
    m[W1] = m[W1] | eye | obj
    m[FR] = m[FR] | body
    m[BK] = m[BK] | (((a == 16) | (a == 17) | (a == 39) | (a == 40)) & (r <= 4.2)) | ((a == 49) & (r <= 5.0)) | \
        ((a == 2) & (r <= 4.6)) | ((a == 58) & (r > 4.2) & (r <= 5.6))
    m["cut"] = m["cut"] | ((a == 58) & (r <= 4.2)) | ((a == 2) & (r <= 3.0))
    m["glow_in"] = m["glow_in"] | ((a == 57) & (r <= 4.2))
    tur = ((a - 28) ** 2 + c ** 2 <= 6.5) & (sb >= 3) & (sb <= 6)                            # 위 다이얼
    m[MT] = m[MT] | tur | (((a - 28) ** 2 + sb ** 2 <= 4.5) & (ac >= 3) & (ac <= 5))          # 옆 다이얼
    m[LG] = m[LG] | (((a - 28) ** 2 + c ** 2 <= 3.5) & (sb == 7))
    mount = (((a >= 10) & (a <= 13)) | ((a >= 35) & (a <= 38))) & (((r > 3.4) & (r <= 5.4) & (sb >= -1)) | ((b >= 9) & (b <= 12) & (ac <= 3)))
    m[FR] = m[FR] | mount
    # ── 총열 덮개(검정 각통 · 높이 −4~5 · 폭 7, 위 모서리 깎음) + 옆 초록 띠(마디)
    shr = (a > 42) & (a <= 146) & (b >= -4) & (b <= 5) & (ac <= 3) & ~((b >= 5) & (ac >= 3))
    m[FR] = m[FR] | shr
    strip = shr & (ac == 3) & (b >= -1) & (b <= 0) & (a >= 48) & (a <= 140) & (np.mod(a - 48, 8) != 7)
    m["cut"] = m["cut"] | strip
    m["glow_in"] = m["glow_in"] | ((ac == 2) & (b >= -1) & (b <= 0) & (a >= 48) & (a <= 140) & (np.mod(a - 48, 8) != 7))
    # 흰 판 4장(한 칸 돋음) — 위·아래 번갈아
    for pts in ([(45.5, 5.5), (62.5, 5.5), (66.5, 1.5), (66.5, -1.5), (58.5, -1.5), (54.5, 2.5), (45.5, 2.5)],
                [(83.5, -4.5), (100.5, -4.5), (104.5, -0.5), (104.5, 2.5), (96.5, 2.5), (92.5, -1.5), (83.5, -1.5)],
                [(111.5, 5.5), (122.5, 5.5), (124.5, 3.5), (124.5, 1.5), (111.5, 1.5)],
                [(134.5, -4.5), (146.5, -4.5), (146.5, 5.5), (139.5, 5.5), (134.5, 1.5)]):
        m[W1] = m[W1] | (_pg(a, b, pts) & (ac == 4))
    # 죔쇠 + 접힌 양각대
    clamp = (a >= 70) & (a <= 75) & (b >= -7) & (b <= 7) & (ac <= 5) & ~((ac >= 5) & ((b <= -7) | (b >= 7)))
    m[FR] = m[FR] | clamp
    m[BK] = m[BK] | (clamp & (ac == 5) & ((b == 4) | (b == -4)) & ((a == 71) | (a == 74)))
    legs = (a >= 76) & (a <= 112) & (b >= -6) & (b <= -5) & (ac == 2)
    m[FR] = m[FR] | legs
    m[BK] = m[BK] | ((a >= 110) & (a <= 112) & (b >= -7) & (b <= -5) & (ac >= 1) & (ac <= 3))
    # ── 총구(흰): 앞면 초록 사각(한 칸 들어감) + 옆 구멍
    muz = (a > 146) & (a <= 156) & (b >= -5) & (b <= 6) & (ac <= 4) & ~(((b >= 6) | (b <= -5)) & (ac >= 4))
    m[W1] = m[W1] | muz
    m[BK] = m[BK] | (muz & (a == 156) & ~((b >= -2) & (b <= 3) & (ac <= 2)))
    m["cut"] = m["cut"] | ((a == 156) & (b >= -2) & (b <= 3) & (ac <= 2)) | (muz & (ac == 4) & (b >= 0) & (b <= 2) & (a >= 149) & (a <= 152))
    m["glow_in"] = m["glow_in"] | ((a == 155) & (b >= -2) & (b <= 3) & (ac <= 2))
    m[BK] = m[BK] | (muz & (ac == 3) & (b >= 0) & (b <= 2) & (a >= 149) & (a <= 152))     # 옆 구멍 속
    return m


ORDER = (FR, W1, DK, MT, LG, BK)


def _paint(p, m):
    shp = p.a.shape
    for col in ORDER:
        p.add(np.broadcast_to(m[col], shp), col)
    p.cut(np.broadcast_to(m["cut"], shp))
    p.add(np.broadcast_to(m["glow_in"], shp) & (p.a > 0), GL)


def rifle_only():
    """라이플 혼자: 앞 = −Y, 위 = +Z, 옆 = X (손잡이 가운데가 원점)."""
    M = fv.Model()
    ag, bg = GRIP_AB
    p = M.part("SniperRifle", (-8, -(160 - ag), -12), (9, 50 + ag, 40), pivot=(0, 0, 0))   # Z = b − bg(b −23~22 → Z −9~36)
    X, Y, Z = p.g()
    _paint(p, rifle_masks(-Y + ag, Z + bg, X))
    return M


def attach(M, scale=None, name="SniperRifleR"):
    """오른손(LowerArmR)에 쥠. 손잡이 가운데(GRIP_AB) = 주먹 가운데. 배율은 쥔 자리 기준(설계 좌표를 반올림해 다시 읽음)."""
    sa, sb, sc = scale or SCALE
    fx, fy, fz = FIST_R
    ag, bg = GRIP_AB
    lo = (int(fx - 9 * sc) - 1, int(fy - (26 - bg) * sb) - 1, int(fz - (160 - ag) * sa) - 1)
    hi = (int(fx + 9 * sc) + 2, int(fy + (-24 - bg) * sb * -1) + 2, int(fz + (50 + ag) * sa) + 2)
    p = M.part(name, lo, hi, pivot=FIST_R, parent="LowerArmR")
    X, Y, Z = p.g()
    a = np.round((fz - Z) / sa) + ag
    b = np.round((fy - Y) / sb) + bg
    c = np.round((X - fx) / sc)
    _paint(p, rifle_masks(a, b, c))
    return p


def build_all(scale=None):
    import sniper_v2 as S
    M = S.build_all()
    attach(M, scale)
    return M


# 미리보기 자세(r1 크기 확인용): 한 손 조준 · 낮춰 듦(팔은 쉬고 총만 앞 아래로 20°)
# 기본 사격 자세 = 두 손 견착 → sniper_aim.py (10-29 21:37 유저 "기본 사격 자세가 양손 사격이어야 함")
AIM = {"UpperArmR": rotx(-86) @ roty(4)}
LOW = {"SniperRifleR": rotx(-70)}
