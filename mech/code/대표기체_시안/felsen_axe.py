"""
felsen_axe.py — HT-01 FELSEN 근접 무기 시안: 열선 도끼(택티컬 토마호크 + 앞날 열선) (2026-10-27 00:22~)

유저(00:22, 레퍼런스 = 애니 메카의 열 도끼 이미지 검색 + 실물 택티컬 토마호크 상품 사진): "택티컬 + 히트 호크(앞쪽은 열선)".
→ 쓰는 건 '역할'만: 택티컬 토마호크 계열(앞 날 + 턱 + 뒤 스파이크/망치, 무게 줄이는 구멍, 감은 손잡이) + 앞날이 달아오름.
   특정 작품·상품의 모양은 따라 하지 않고 FELSEN 의 각진 판·단차 문법으로 고유하게.
축(정준 좌표): x = 두께, y = 앞(−)·뒤(+), z = 손잡이 축(0 = 꼭지 끝, 위 = 머리). 칸 = 중장갑과 같은 0.05 Blender(템플릿 0.1 스터드).
길이 약 112칸 ≈ 11.2 스터드(기체 키 283칸의 약 40%) [제안].
색 = 중장갑 A: 1 아이보리 · 2 흑연 · 3 짙은 회색 · 4 검정 · 5 주황 · 6 발광(주황) · 7 금속 + 8 열선 백열(시안 그림 전용).
  X1 브리처: 턱 긴 앞 날 + 뒤 스파이크 + 구멍 3개(택티컬 기본형)
  X2 몰백: 짧은 턱 · 곧은 날 + 뒤 망치(두드리는 면) + 날 몸통 방열 슬롯 4줄 — 중장갑 '부수기'
  X3 파이크: 앞 날 + 위로 찌르는 창끝(열선) + 뒤 갈고리 — 찌르기·걸기
"""
import numpy as np
from matplotlib.path import Path

IVORY, GRAPH, DARK, BLACK, ORANGE, GLOW, METAL, HOT = 1, 2, 3, 4, 5, 6, 7, 8
PAL_EXTRA = {HOT: (255, 236, 170)}
EMISSIVE = {GLOW, HOT}
GRIP_Z = 24          # 손이 쥐는 자리(꼭지에서)


def _poly2(Yc, Zc, pts):
    shp = np.broadcast_shapes(Yc.shape, Zc.shape)
    yy = np.broadcast_to(Yc, shp).ravel(); zz = np.broadcast_to(Zc, shp).ravel()
    return Path(np.asarray(pts, float)).contains_points(np.stack([yy, zz], 1), radius=1e-9).reshape(shp)


def _dist_poly(Yc, Zc, line):
    """(y, z) 점에서 꺾은선까지 거리."""
    d = np.full(np.broadcast_shapes(Yc.shape, Zc.shape), np.inf)
    for (y0, z0), (y1, z1) in zip(line[:-1], line[1:]):
        vy, vz = y1 - y0, z1 - z0
        L2 = vy * vy + vz * vz
        t = np.clip(((Yc - y0) * vy + (Zc - z0) * vz) / L2, 0, 1)
        d = np.minimum(d, np.hypot(Yc - (y0 + t * vy), Zc - (z0 + t * vz)))
    return d


SPECS = {
    "X1": dict(
        blade=[(-5, 104), (-24, 109), (-36, 101), (-39, 74), (-31, 60), (-20, 58), (-5, 68)],
        edge=[(-24, 109), (-36, 101), (-39, 74), (-31, 60)],
        holes=[(-19, 95, 3.2), (-24, 83, 3.2), (-19, 71, 2.6)],
        back=("spike", [(5, 101), (23, 92), (5, 84)]),
        slots=[], spear=None),
    "X2": dict(
        blade=[(-5, 104), (-29, 106), (-34, 100), (-34, 72), (-25, 68), (-5, 76)],
        edge=[(-29, 106), (-34, 100), (-34, 72), (-25, 68)],
        holes=[],
        back=("poll", None),
        slots=[(78, -27, -12), (84, -27, -12), (90, -27, -12), (96, -27, -12)], spear=None),
    "X3": dict(
        blade=[(-5, 100), (-27, 101), (-32, 93), (-32, 75), (-24, 66), (-5, 73)],
        edge=[(-27, 101), (-32, 93), (-32, 75), (-24, 66)],
        holes=[(-18, 86, 3.0)],
        back=("hook", [(5, 99), (17, 96), (24, 86), (21, 82), (15, 88), (5, 88)]),
        slots=[], spear=[(-5, 104), (0, 128), (5, 104)]),
}


def axe_masks(kind, X, Y, Z):
    """정준 좌표 배열(X 두께, Y 앞뒤, Z 축) → {색: 마스크}."""
    S = SPECS[kind]
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    ax, ay = np.abs(X), np.abs(Y)
    out = {}
    # 손잡이: 7×7 모따기 각봉, 아래 감김(검정 고리) · 꼭지(금속 + 짧은 뾰족)
    haft = (ax <= 3) & (ay <= 3) & (ax + ay <= 5) & (Z >= 4) & (Z <= 106)
    wrap = haft & (Z >= 8) & (Z <= 48) & ((np.floor(Z) % 5) == 0)               # floor: 배율을 걸면 Z 가 정수가 아님
    pommel = (ax <= 4) & (ay <= 4) & (ax + ay <= 6) & (Z >= 0) & (Z <= 6)
    tip = (Z >= -6) & (Z < 0) & (ax + ay <= (Z + 6) * 0.6 + 0.5)
    collar = (ax <= 4) & (ay <= 4) & (Z >= 50) & (Z <= 53)                  # 손잡이 위 띠(주황)
    # 머리 소켓: 금속 몸 + 양 볼 아이보리 장갑판(주황 줄) + 방열 홈
    sock = (ax <= 4) & (Y >= -7) & (Y <= 7) & (Z >= 66) & (Z <= 108)
    cheek = (ax >= 4) & (ax <= 5) & (Y >= -6) & (Y <= 6) & (Z >= 70) & (Z <= 104) & ~((Y >= 5) & (Z >= 100))
    cheek_line = cheek & (Z >= 86) & (Z <= 87)
    # 앞 날: 몸 두께 5(|x|≤2) → 날 쪽 3·1 로 얇아짐(날 꺾은선까지 거리 기준)
    b2 = _poly2(Y, Z, S["blade"])
    d_edge = _dist_poly(Y, Z, S["edge"])
    thick = np.where(d_edge <= 3, 1, np.where(d_edge <= 7, 1.5, 2))
    blade = b2 & (ax <= thick)
    for (hy, hz, r) in S["holes"]:
        blade &= ~(((Y - hy) ** 2 + (Z - hz) ** 2) <= r * r)
    for (sz, y0, y1) in S["slots"]:
        blade &= ~((Z >= sz) & (Z <= sz + 1) & (Y >= y0) & (Y <= y1) & (d_edge > 4))
    hot = blade & (d_edge <= 1.2)
    glow = blade & (d_edge <= 3.2) & ~hot
    blade_body = blade & ~hot & ~glow
    # 뒤
    back = np.zeros(shp, bool); back_face = np.zeros(shp, bool)
    kindb, pts = S["back"]
    if kindb == "spike":
        b = _poly2(Y, Z, pts)
        back = b & (ax <= np.maximum(0.5, (23 - Y) * 0.18))                   # 끝으로 갈수록 얇은 각뿔
    elif kindb == "poll":
        back = (ax <= 5) & (Y >= 6) & (Y <= 18) & (Z >= 80) & (Z <= 100) & ~((Y >= 15) & ((Z <= 81) | (Z >= 99)))
        back_face = back & (Y >= 17)                                           # 두드리는 면(짙게)
    elif kindb == "hook":
        b = _poly2(Y, Z, pts)
        back = b & (ax <= 2)
    spear = np.zeros(shp, bool); spear_hot = np.zeros(shp, bool)
    if S["spear"]:
        sp = _poly2(Y, Z, S["spear"]) & (ax <= np.maximum(0.6, (128 - Z) * 0.12))
        ds = _dist_poly(Y, Z, [S["spear"][0], S["spear"][1], S["spear"][2]])
        spear_hot = sp & (ds <= 1.6)
        spear = sp & ~spear_hot
    out[GRAPH] = haft & ~wrap & ~collar
    out[BLACK] = wrap
    out[METAL] = pommel | tip | (sock & ~cheek) | blade_body | (back & ~back_face) | spear
    vents = cheek & (Z >= 73) & (Z <= 83) & ((np.floor(Z) % 3) == 0) & (ay <= 4)          # 볼 판 아래 방열 홈 4줄(열선 쪽 느낌)
    out[DARK] = back_face | vents
    out[IVORY] = cheek & ~cheek_line & ~vents
    out[ORANGE] = collar | cheek_line
    out[GLOW] = glow
    out[HOT] = hot | spear_hot
    return {k: np.broadcast_to(v, shp) for k, v in out.items()}


SCALE = 1.35   # [제안] 1.0 = 112칸(키의 40%)은 손도끼로 읽혀(00:3x 시안 r1) → 1.35 = 약 151칸 ≈ 15 스터드(키의 53%)


def add_axe(M, kind, name="Axe", pivot=(0, 0, 0), rot=None, parent=None, scale=SCALE):
    """정준 축 그대로 칸을 깔고(손 자리 GRIP_Z 가 pivot), rot 로 피벗 둘레 회전. 부모 없음 = 월드. scale = 정준 좌표 배율."""
    px, py, pz = pivot
    s = scale
    lo = (int(px - 8 * s), int(py - 42 * s), int(pz - (GRIP_Z + 8) * s))
    hi = (int(px + 9 * s) + 1, int(py + 26 * s) + 1, int(pz + (132 - GRIP_Z) * s) + 1)
    p = M.part(name, lo, hi, pivot=pivot, parent=parent)
    X, Y, Z = p.g()
    m = axe_masks(kind, (X - px) / s, (Y - py) / s, (Z - pz) / s + GRIP_Z)
    for c in (GRAPH, BLACK, METAL, DARK, IVORY, ORANGE, GLOW, HOT):
        p.add(m[c], c)
    if rot is not None:
        p.rot = rot
    return p


KINDS = ("X1", "X2", "X3")
LABELS = {"X1": "X1 breacher: long beard + back spike + 3 holes", "X2": "X2 maul-back: straight edge + hammer poll + heat slots",
          "X3": "X3 pike: blade + heated spear tip + back hook"}
