"""
jet_r1.py — FALCO(MechType "Aero") 비행기 형태 "FalcoJet" r1 (2026-11-06)

변신 = 교체형 + 짧은 전조(C안, 결정). 인간형 부품을 접지 않고 별도 모델로 바꿔 끼운다 → "같은 기체"로 보이게 FALCO 디자인 요소를 이어 씀:
  - 날개 W2 문법: 테이퍼 · 뒷전 깃 3단(1:2 / 2:1 톱니) · 끝 노즐(짙은 덩어리 + 오목한 안쪽 발광) · 앞쪽 흰 덮깃 + 뒤 주황 판
  - 머리 → 기수/조종석(JetCockpit): 쐐기 머리통 + 가운데 볏(H_HelmRidge) + 좁은 V 바이저 = 캐노피 발광
  - 어깨 패드 → 동체 옆 흡기구 덩어리(흰 상자 + 앞 짙은 입) · 가슴 V 발광 → 동체 등 V 홈 발광
  - 등 백팩·바인더 → 뒤 엔진 나셀 2(짙은 색) + 위 흰 바인더 판(꼬리날개 받침)
  - 머리 주황 뿔(Fin) → 카나드(주황 작은 후퇴익)
색 번호 = 인간형과 같음(2 흰 · 10 밝은 회색 · 3 프레임 · 4 검정 · 1 주황 · 6 발광 · 7 금속) → 팔레트 텍스처 그대로.

좌표(복셀 칸, Blender 축): +X = 기체 왼쪽 · −Y = 앞 · +Z = 위 · 원점 = HumanoidRootPart 중심 자리.
템플릿(로블록스) = (−x, z, y) × 0.1 스터드 → 앞 = −Z, 위 = +Y (인간형 AELLO 와 같은 규약, aello_glow_data.Mm).

  python3 jet_r1.py OUTDIR        → 시트 PNG · GLB · parts.json · Studio 조립 Lua 데이터
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path[:0] = [os.path.join(ROOT, "flagship_tools"), os.path.join(ROOT, "대표기체_시안")]

from flag_vox import Model, box, cbox, poly, half, cyl, roty   # noqa: E402

ORANGE, WHITE, FRAME, BLACK, GLOW, METAL, GREY = 1, 2, 3, 4, 6, 7, 10
TAG = "FalcoJet_r1_20261106"
STUD = 0.1                                     # 칸 → 스터드 (칸 0.05 Blender × 템플릿 ×2)
Mm = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)   # Blender 칸 → 템플릿 축
HRP = (7.44, 7.44, 4.96)                       # 템플릿 X(폭) · Y(높이) · Z(앞뒤)
TAIL_CANT = float(np.degrees(np.arctan(0.5)))  # 1:2 (26.57°) — 정수비 기울기


def T(p):
    """Blender 칸 좌표 → 템플릿 스터드(원점 기준)."""
    return (Mm @ np.asarray(p, float)) * STUD


# ------------------------------------------------------------------ 동체
def build_body(M):
    p = M.part("JetBody", (-62, -104, -34), (63, 126, 34), (0, 0, 0))
    G = p.g(); X, Y, Z = G
    AX = np.abs(X)
    # 중앙 동체: 위(평면) · 옆 실루엣 교집합 + 팔각 단면(45° 모서리)
    top = poly(G, "z", [(0, -102), (20, -102), (34, -72), (40, -44), (40, 64), (34, 96), (0, 96)], sym=True)
    side = poly(G, "x", [(-102, -14), (-102, 10), (-72, 24), (-44, 32), (64, 32), (96, 22), (96, -22), (64, -32), (-44, -32), (-72, -24)])
    octa = (AX + np.abs(Z)) <= 60
    hull = top & side & octa
    p.add(hull, WHITE)
    p.paint(hull & (Z <= -12), GREY)                                   # 아랫배 = 보조 장갑
    # 가슴 V → 등 V 홈(발광은 홈 바닥에만): 앞을 가리키는 V, 두 팔 1:1
    v = (np.abs((Y + 64) - AX) <= 2) & (AX <= 22) & (Z >= 26)
    p.groove(v, GLOW)
    # 뒤 윗면 = 백팩(짙은 덩어리): 흰 가슴 판 뒤로 한 칸 높은 짙은 덱, 앞 끝 45° 모따기
    deck = cbox(G, (-30, 30), (8, 92), (28, 34), {"-yz": 6, "xz": 4}) & top
    p.add(deck, FRAME)
    p.add(box(G, (-30, 30), (8, 8), (28, 30)) & top & octa, BLACK)     # 가슴 판 ↔ 백팩 덱 사이 그늘 줄

    # 흡기구 = 어깨 패드 덩어리(흰 상자, 앞 위 모따기, 아래 회색)
    intake = cbox(G, (40, 60), (-56, 0), (-22, 16), {"-y+z": 8, "+x+z": 4, "+x-z": 4, "+y+x": 6, "+yz": 6}) & (X > 0)
    intake = intake | (cbox(G, (-60, -40), (-56, 0), (-22, 16), {"-y+z": 8, "-x+z": 4, "-x-z": 4, "+y-x": 6, "+yz": 6}) & (X < 0))
    p.add(intake, WHITE)
    p.paint(intake & (Z <= -10), GREY)
    mouth = box(G, None, (-56, -50), (-16, 10)) & (AX >= 44) & (AX <= 56)
    p.cut(mouth)
    p.add(box(G, None, (-49, -48), (-16, 10)) & (AX >= 44) & (AX <= 56), BLACK)   # 입 안 = 검정
    p.add(box(G, None, (-50, -48), (-4, -2)) & (AX >= 44) & (AX <= 56), FRAME)    # 가운데 가로 살 1(흡기 칸막이)
    # 기관포(흡기구 아래 바깥): 강철 총열
    for sx in (1, -1):
        p.add(cyl(G, "y", (sx * 52, -25), 3, rng=(-68, -44)), METAL)
        p.add(box(G, (sx * 52 - 4, sx * 52 + 4), (-48, -24), (-28, -22)), FRAME)  # 총 받침

    # 뒤 엔진 나셀 2(백팩·바인더 → 짙은 색) + 둥근 노즐(안쪽 깊은 곳만 발광)
    for sx in (1, -1):
        cx = sx * 22
        nac = cyl(G, "y", (cx, -2), 17, rng=(40, 112))
        p.add(nac, FRAME)
        noz = cyl(G, "y", (cx, -2), 15, rng=(112, 125))
        p.add(noz, FRAME)
        p.cut(cyl(G, "y", (cx, -2), 10, rng=(116, 125)))
        p.add(cyl(G, "y", (cx, -2), 10, rng=(115, 115)), BLACK)
        p.add(cyl(G, "y", (cx, -2), 5, rng=(115, 115)), GLOW)          # 깊은 안쪽 가운데만 발광
        p.add(cyl(G, "y", (cx, -2), 12, rng=(112, 113)) & ~cyl(G, "y", (cx, -2), 11, rng=(112, 113)), METAL)  # 노즐 목 강철 테
        # 바인더 판(흰, 꼬리날개 받침) — 나셀 위
        p.add(cbox(G, (cx - 12, cx + 12), (46, 104), (12, 21), {"yz": 5, "xz": 3}), WHITE)
    p.add(box(G, (-6, 6), (90, 112), (-14, 12)), FRAME)               # 나셀 사이 척추
    p.trim()
    return p


# ------------------------------------------------------------------ 조종석(머리)
def build_cockpit(M):
    p = M.part("JetCockpit", (-20, -140, -18), (21, -88, 26), (0, -92, 0), "JetBody")
    G = p.g(); X, Y, Z = G
    AX = np.abs(X)
    top = poly(G, "z", [(0, -138), (8, -138), (18, -118), (18, -90), (0, -90)], sym=True)
    side = poly(G, "x", [(-138, -8), (-138, 2), (-120, 14), (-100, 22), (-90, 22), (-90, -16), (-120, -14)])
    hull = top & side & ((AX + np.abs(Z - 2)) <= 30)
    p.add(hull, WHITE)
    p.paint(hull & (Z <= -6), GREY)
    p.paint(hull & (Y <= -133) & (Z >= -4) & (Z <= 0) & (AX <= 3), FRAME)   # 기수 끝 작은 센서(정면 "입"으로 안 읽히게 작게)
    # 좁은 V 바이저 = 캐노피: 앞이 뾰족한 V, 두 팔 1:2(좁고 높은 V), 1칸 파서 바닥만 발광
    vis = (np.abs((Y + 122) - 2 * AX) <= 2) & (AX <= 9) & (Z >= 8)
    p.groove(vis, GLOW)
    # 가운데 볏(투구 능선) — 주황 끝
    p.add(box(G, (-2, 2), (-116, -92), (22, 25)), FRAME)
    p.add(box(G, (-2, 2), (-116, -108), (22, 25)), ORANGE)
    p.trim()
    return p


# ------------------------------------------------------------------ 주날개(W2 문법)
PYLONS = ((58, 22), (80, 44))                 # 미사일 받침 (x, 앞 끝 y) — 앞전(y = x − 42)보다 6칸 뒤
WING_PIVOT = (40, 46, 0)
WING_TOP = [(34, -6), (36, -6), (100, 58), (100, 78), (84, 70), (76, 86), (60, 78), (52, 94), (36, 86), (34, 98)]
#            뿌리 앞전 ── 앞전 45°(1:1) ── 끝 시위 ── 깃 1(2:1 / 1:2) ── 깃 2 ── 깃 3 ── 뿌리 뒷전


def build_wing(M):
    p = M.part("JetWingL", (30, -10, -12), (112, 102, 8), WING_PIVOT, "JetBody")
    G = p.g(); X, Y, Z = G
    plan = poly(G, "z", WING_TOP)
    p.add(plan & (Z >= -2) & (Z <= 1), ORANGE)                         # 주황 주 날(뒤 판 = 펼치면 보이는 면)
    cov = plan & (Y <= X - 42 + 16) & (X <= 94) & (Z >= 2) & (Z <= 3)   # 흰 덮깃: 앞전에서 30칸 폭, 끝 노즐 전까지
    p.add(cov, WHITE)
    p.add(plan & (Y <= X - 42 + 4) & (Z >= -2) & (Z <= 1) & (X <= 94), WHITE)   # 앞전 6칸 = 흰(앞에서 보이는 면)
    # 뿌리 경첩 뭉치(짙은)
    p.add(cbox(G, (32, 44), (20, 72), (-5, 5), {"xz": 2, "yz": 3}), FRAME)
    # 끝 노즐: 짙은 덩어리 + 뒤 오목 안쪽 발광
    p.add(cbox(G, (96, 108), (48, 86), (-5, 5), {"xz": 2, "-yx": 4, "yz": 2}), FRAME)
    p.cut(box(G, (99, 105), (82, 86), (-2, 2)))
    p.add(box(G, (99, 105), (81, 81), (-2, 2)), GLOW)
    # 미사일 받침 2(날개 아래, 짙은 레일)
    for x0, y0 in PYLONS:
        p.add(cbox(G, (x0 - 3, x0 + 3), (y0, y0 + 26), (-8, -3), {"-yz": 3}), FRAME)
    p.trim()
    M.mirror("JetWingL", "JetWingR", "JetBody")
    return p


# ------------------------------------------------------------------ 꼬리날개(바깥으로 1:2 기울인 수직미익 2 = V 꼬리)
TAIL_PIVOT = (22, 84, 21)


def build_tail(M):
    p = M.part("JetTailL", (19, 62, 20), (26, 112, 50), TAIL_PIVOT, "JetBody")
    G = p.g(); X, Y, Z = G
    prof = poly(G, "x", [(64, 20), (92, 48), (108, 48), (108, 20)])     # 앞전 1:1 · 뒷전 수직
    p.add(prof & (X >= 21) & (X <= 23), ORANGE)
    p.paint(prof & (Y - 64 <= Z - 20 + 5), WHITE)                     # 앞전 5칸 = 흰(날개 덮깃과 같은 규칙)
    p.add(box(G, (20, 24), (66, 106), (20, 22)), FRAME)                # 뿌리 받침
    p.trim()
    p.rot = roty(TAIL_CANT)                                            # +X 파트: 위가 바깥으로
    M.mirror("JetTailL", "JetTailR", "JetBody")
    return p


# ------------------------------------------------------------------ 카나드(머리 주황 뿔 문법)
CANARD_PIVOT = (24, -86, 10)


def build_canard(M):
    p = M.part("JetCanardL", (20, -100, 8), (46, -70, 12), CANARD_PIVOT, "JetBody")
    G = p.g(); X, Y, Z = G
    pl = poly(G, "z", [(20, -98), (44, -86), (44, -78), (20, -72)])    # 앞전 2:1 후퇴
    p.add(pl & (Z >= 9) & (Z <= 10), ORANGE)
    p.add(box(G, (20, 26), (-92, -76), (8, 11)), FRAME)                # 뿌리
    p.trim()
    M.mirror("JetCanardL", "JetCanardR", "JetBody")
    return p


def build_all():
    M = Model()
    build_body(M); build_cockpit(M); build_wing(M); build_tail(M); build_canard(M)
    return M


# ------------------------------------------------------------------ 부착점 (Blender 칸, 방향은 템플릿 축)
def attachments():
    A = {}
    for s, sx in (("L", 1), ("R", -1)):
        A["JetNozzle" + s] = ("JetBody", (sx * 22, 126, -2), "+Z")              # 주 엔진, 뒤로 분사
        A["JetWingNozzle" + s] = ("JetWing" + s, (sx * 102, 87, 0), "+Z")
        A["JetMuzzle" + s] = ("JetBody", (sx * 52, -67, -25), "-Z")             # 기관포 총구, 앞
    # 미사일: 1·2 = 왼 날개(안 · 바깥), 3·4 = 오른 날개(안 · 바깥)
    for i, (sx, (x0, y0)) in enumerate([(1, PYLONS[0]), (1, PYLONS[1]), (-1, PYLONS[0]), (-1, PYLONS[1])], 1):
        A["JetMissile%d" % i] = ("JetWing" + ("L" if sx > 0 else "R"), (sx * x0, y0 - 1, -10), "-Z")
    A["JetFlashAtt"] = ("JetBody", (0, 0, 0), None)
    G = {
        "GlowLightAtt_Visor": ("JetCockpit", (0, -118, 20)),
        "GlowLightAtt_Chest": ("JetBody", (0, -54, 33)),
        "GlowLightAtt_NozzleL": ("JetBody", (22, 119, -2)),
        "GlowLightAtt_NozzleR": ("JetBody", (-22, 119, -2)),
        "GlowLightAtt_WingTipL": ("JetWingL", (102, 84, 0)),
        "GlowLightAtt_WingTipR": ("JetWingR", (-102, 84, 0)),
    }
    return A, G


# ------------------------------------------------------------------ 숫자
def world_cells(M, name):
    p = M.parts[name]
    ijk = np.argwhere(p.a > 0).astype(float) + p.lo
    W = M.world(name)
    return ijk @ W[:3, :3].T + W[:3, 3], p.a[p.a > 0]


def stats(M):
    allp = []
    out = {"parts": {}}
    for n in M.parts:
        P, _ = world_cells(M, n)
        allp.append(P)
        lo, hi = P.min(0) - 0.5, P.max(0) + 0.5
        tl, th = np.sort(np.stack([T(lo), T(hi)]), axis=0)
        out["parts"][n] = dict(cells=len(P), size=(th - tl).round(2).tolist(), center=((tl + th) / 2).round(2).tolist())
    P = np.vstack(allp)
    lo, hi = P.min(0) - 0.5, P.max(0) + 0.5
    tl, th = np.sort(np.stack([T(lo), T(hi)]), axis=0)
    out["bbox_min"], out["bbox_max"] = tl.round(2).tolist(), th.round(2).tolist()
    out["size"] = (th - tl).round(2).tolist()
    com = T(P.mean(0))
    out["com"] = com.round(3).tolist(); out["com_dist"] = round(float(np.linalg.norm(com)), 3)
    # HRP 상자(원점) 안 칸 중 동체가 차지한 비율
    hx, hz, hy = HRP[0] / 2 / STUD, HRP[1] / 2 / STUD, HRP[2] / 2 / STUD   # Blender 축: x 폭 · z 높이 · y 앞뒤
    body, _ = world_cells(M, "JetBody")
    occ = set(map(tuple, np.round(body).astype(int)))
    xs = np.arange(-int(hx) + 0.5, hx, 1.0); ys = np.arange(-int(hy) + 0.5, hy, 1.0); zs = np.arange(-int(hz) + 0.5, hz, 1.0)
    tot = hit = 0
    for x in xs[::2]:
        for y in ys[::2]:
            for z in zs[::2]:
                tot += 1; hit += (int(round(x)), int(round(y)), int(round(z))) in occ
    out["hrp_fill"] = round(hit / tot, 3)
    return out


def hitbox(M):
    """JetHitBox = 동체(+조종석) 길이 × 폭 8 × 높이 6, 원점 높이·옆 가운데."""
    P = np.vstack([world_cells(M, n)[0] for n in ("JetBody", "JetCockpit")])
    y0, y1 = P[:, 1].min() - 0.5, P[:, 1].max() + 0.5
    size = (8.0, 6.0, round((y1 - y0) * STUD, 2))
    center = T((0, (y0 + y1) / 2, 0)).round(3).tolist()
    return size, center


if __name__ == "__main__":
    M = build_all()
    print(json.dumps(stats(M), ensure_ascii=False, indent=1))
