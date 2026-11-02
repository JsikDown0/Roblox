"""HT-02 CETUS — r9 = r8(헬멧·가슴·어깨·팔 확정) + 하체 r1 (2026-11-02)

하체 읽기: mech/docs/레퍼런스/CETUS/윤곽읽기_r5_하체.png · 결정기록 5-7
답 [결정 11-02]: ① 발광 더 늘림 → G1 무릎 창 · G2 무릎 옆 쌍둥이 램프 · G3 발목 갓 램프 모두 발광(색 6, 오목한 곳)
② 허리 호스 = 원본대로(황동 상자에서 양옆 아래로 내려가 엉덩이 뒤로) ③ ▲ 표시 뺌, 대신 데칼 자리(평평한 면) 확보
④ T1 허벅지 윗판·F 발끝 덮개 = 강철 7 ⑤ X 발목 뒤 지느러미 뺌
파트: Pelvis · UpperLegL/R(엉덩이) · LowerLegL/R(무릎) · FootL/R(발목). 왼쪽을 만들고 거울.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cbox, cyl, ell, box  # noqa: E402
import cetus_r6 as r6  # noqa: E402
import cetus_r8 as r8  # noqa: E402

PAL, EMISSIVE, METAL = r8.PAL, r8.EMISSIVE, r8.METAL
PAL_ULT, EMISSIVE_ULT = r8.PAL_ULT, r8.EMISSIVE_ULT
HX = 30                      # 엉덩이 |x|
HIP = (HX, 0, 140)
KNEE = (33, -2, 100)
DX = 3                       # 다리 전체를 바깥으로(엉덩이 원반은 골반이 받음)
ANKLE = (35, 0, 36)
DECAL_T1 = "허벅지 앞 강철 윗판 앞면: x 21~45 · z 126~144 · y −27 (평평한 면)"


def porthole(P, G, axis, c, r_glass, r_ring, rng_ring, face, depth=1, glow=6):
    """둥근 창: 황동 테(돋움) + 안쪽으로 들어간 유리. axis 방향으로 face(바깥 면 좌표, 부호 포함)."""
    if axis == "y":
        ring = cyl(G, "y", (c[0], c[2]), r_ring, rng=rng_ring); glass = cyl(G, "y", (c[0], c[2]), r_glass, rng=rng_ring)
    else:
        ring = cyl(G, "x", (c[1], c[2]), r_ring, rng=rng_ring); glass = cyl(G, "x", (c[1], c[2]), r_glass, rng=rng_ring)
    P.add(ring & ~glass, 5)
    P.add(glass, 3)
    X, Y, Z = G
    A = Y if axis == "y" else X
    sgn = 1 if face > 0 else -1
    P.cut(glass & (A * sgn > face * sgn - depth))
    P.paint(glass & (A * sgn > face * sgn - depth - 1), glow)


# ------------------------------------------------------------------ 골반
def build_pelvis(M):
    P = M.part("Pelvis", (-44, -42, 122), (45, 30, 180), pivot=(0, 0, 150))
    G = P.g(); X, Y, Z = G
    P.add(cbox(G, (-26, 26), (-24, 22), (134, 176), {"xy": 8, "-zx": 8, "-zy": 5}), 3)
    for s in (1, -1):                                                        # 엉덩이 원반 받침(짙은 원반 2겹)
        P.add(cyl(G, "x", (0, 140), 16, rng=(s * 18, s * 26)), 3)
        P.add(cyl(G, "x", (0, 140), 12, rng=(s * 26, s * 29)), 4)
    # W2 샅 청록 판(세로 직사각) + 한 칸 테
    P.add(cbox(G, (-10, 10), (-29, -22), (128, 156), {"-zx": 3, "xy": 2, "-z-y": 3}), 1)
    P.groove(box(G, x=(-8, 8), y=(-30, -28), z=(131, 131)), 4)
    # W1 허리 앞 황동 상자(가슴 립 바로 밑)
    P.add(cbox(G, (-12, 12), (-38, -24), (152, 168), {"xy": 3, "+z-y": 3, "-z-y": 2}), 5)
    P.groove(box(G, x=(-12, 12), y=(-39, -36), z=(160, 160)), 4)
    # H 허리 호스(원본대로): 황동 상자 양옆에서 나와 아래·옆으로 처져 엉덩이 뒤로 들어감
    for s in (1, -1):
        path = [(s * 10, -33, 160), (s * 20, -32, 155), (s * 31, -26, 150), (s * 37, -12, 150), (s * 34, 6, 155), (s * 26, 16, 160)]
        t = r6.path_tube(G, path, 4.0) & ~(P.a > 0)
        P.add(t, 3)
        for c in path[1:3]:
            P.paint(t & r6.ball(G, c, 5.0), 5)                                 # 황동 고리
    P.trim()
    return P


# ------------------------------------------------------------------ 허벅지
def build_thigh(M):
    U = M.part("UpperLegL", (8, -32, 100), (58, 26, 158), pivot=HIP, parent="Pelvis")
    G = U.g(); X, Y, Z = G
    U.add(cyl(G, "x", (0, 140), 15, rng=(26, 38)), 3)                       # 엉덩이 원반(관절)
    U.add(cyl(G, "x", (0, 140), 11, rng=(38, 41)), 7)
    U.add(cyl(G, "z", (34, 2), 13, rng=(102, 140)), 3)                      # 허벅지 심(뒤·안쪽은 드러남)
    # T 청록 장갑: 앞·바깥을 감싸는 껍데기(뒤는 열림), 아래 끝은 무릎 위에서 끊김
    T = ell(G, (35, -5, 134), (19, 21, 20)) & (Z >= 114) & (Z <= 151) & (Y <= 10)   # 불룩한 둥근 껍데기
    U.add(T & ~cbox(G, (14, 30), (-10, 12), (110, 152)), 1)                 # 안쪽 뒤는 비워 심이 보이게
    U.groove(box(G, x=(16, 53), z=(124, 124)) & T, 4)
    # T1 앞 강철 윗판(평평한 데칼 자리) — 앞으로 3칸 돋움, 위·바깥 모서리 깎음
    U.add(cbox(G, (21, 47), (-28, -24), (127, 148), {"+zx": 5, "+z-y": 2, "x-y": 2}), 7)
    U.trim()
    return U


# ------------------------------------------------------------------ 무릎·정강이
def build_shin(M):
    L = M.part("LowerLegL", (6, -44, 14), (66, 28, 120), pivot=KNEE, parent="UpperLegL")
    G = L.g(); X, Y, Z = G
    L.add(cyl(G, "x", (-2, 100), 12, rng=(19, 51)), 3)                      # 무릎 관절(양옆 드러남)
    for x0, x1 in ((17, 19), (51, 53)):
        L.add(cyl(G, "x", (-2, 100), 8, rng=(x0, x1)), 7)
    L.add(cbox(G, (23, 47), (-14, 16), (28, 96), {"xy": 6}), 3)             # 정강이 심
    L.add(cbox(G, (25, 45), (14, 19), (52, 78), {"xy": 3, "+y+z": 2, "+y-z": 2}), 5)   # 종아리 황동 판(뒤)
    L.groove(box(G, x=(25, 45), y=(18, 20), z=(65, 65)), 4)
    # K 무릎 청록 방패(앞만) + K1 황동 상자 + G1 발광 창
    K = ell(G, (35, -12, 102), (20, 21, 15)) & (Y <= -4)                     # 앞으로 불룩한 둥근 방패
    L.add(K, 1)
    L.add(cbox(G, (25, 45), (-36, -26), (99, 115), {"xy": 3, "-y+z": 3}), 5)
    w = box(G, x=(29, 41), y=(-37, -34), z=(102, 110))
    L.cut(w & (Y <= -36)); L.paint(w & (Y <= -35), 6)                      # G1(1칸 오목, 발광)
    # S 정강이 청록 판(앞·옆, 뒤는 열림) + 아래 황동 테
    kz = np.clip((84 - Z) / 34.0, 0, 1)                                      # 위 0 → 아래 1: 아래로 벌어지는 종 모양
    hw, dy = 16 + 9 * kz, 19 + 7 * kz
    S = (((X - 35) / hw) ** 2 + ((Y + 4) / dy) ** 2 <= 1.0) & (Y <= 8) & (Z >= 50) & (Z <= 84)
    L.add(S, 1)
    rim = (((X - 35) / (hw + 1.5)) ** 2 + ((Y + 4) / (dy + 1.5)) ** 2 <= 1.0) & (Y <= 9) & (Z >= 47) & (Z <= 52)
    L.add(rim & ~(L.a > 0), 5); L.paint(rim, 5)
    L.groove(box(G, x=(13, 58), z=(68, 68)) & S, 4)
    # G2 무릎 바깥 옆 쌍둥이 램프(위아래 2개, 짙은 받침 위)
    L.add(cbox(G, (53, 59), (-6, 12), (76, 100), {"+xz": 3, "+xy": 2}), 3)
    for zc in (93, 82):
        porthole(L, G, "x", (0, 3, zc), 3.5, 5.5, (58, 61), face=61)
    # D 발목 양옆 원반 + R 세로 황동 연결대(앞, 양옆)
    for x0, x1 in ((15, 21), (49, 55)):
        L.add(cyl(G, "x", (0, 34), 14, rng=(x0, x1)), 3)
        L.add(cyl(G, "x", (0, 34), 14, rng=(x0, x1)) & ~cyl(G, "x", (0, 34), 11), 7)
        L.add(cyl(G, "x", (0, 34), 5, rng=(x0 - 1, x1 + 1)), 7)
    for xr in ((17, 20), (50, 53)):
        L.add(box(G, x=xr, y=(-19, -15), z=(20, 48)) & ~(L.a > 0), 5)
    L.trim()
    return L


# ------------------------------------------------------------------ 발(잠수 장화)
def build_foot(M):
    F = M.part("FootL", (0, -48, 0), (72, 40, 50), pivot=ANKLE, parent="LowerLegL")
    G = F.g(); X, Y, Z = G
    ax, ay = ANKLE[0], -6
    F.add(cyl(G, "z", (ax, 0), 18, rng=(8, 44)), 3)                         # 발목 깃(심)
    # B 바닥·옆·뒤 짙은 받침
    F.add(cbox(G, (3, 67), (-46, 34), (0, 8), {"xy": 12, "+zy": 3, "+zx": 3}), 3)
    for x0, x1, sg in ((0, 10, "-x"), (60, 70, "+x")):
        F.add(cbox(G, (x0, x1), (-14, 26), (0, 20), {sg + "+z": 6, "yz": 3}), 3)
    F.add(cbox(G, (14, 56), (16, 36), (0, 24), {"+y+z": 9, "xy": 4}), 3)    # 뒤꿈치
    # F 발끝 둥근 덮개(강철) + 아래 앞 짙은 틈
    toe = ell(G, (ax, -14, 6), (28, 32, 21)) & (Z >= 6) & (Y <= 6)
    F.add(toe, 7)
    F.cut(box(G, x=(ax - 8, ax + 8), y=(-48, -36), z=(6, 11)))
    F.add(box(G, x=(ax - 8, ax + 8), y=(-41, -36), z=(6, 11)) & ~(F.a > 0), 4)
    # A 발목 아치 띠 2줄(앞쪽 반원): 아래 청록 띠 · 위 짙은 쇠 띠 + 황동 테
    dist = np.sqrt((X - ax) ** 2 + (Y - ay) ** 2)
    front = Y <= 4
    F.add((dist <= 29.25) & (dist > 20) & front & (Z >= 18) & (Z <= 25), 1)
    F.add((dist <= 27.25) & (dist > 18) & front & (Z >= 26) & (Z <= 36), 3)
    F.add((dist <= 28.25) & (dist > 18) & front & (Z >= 36) & (Z <= 38), 5)
    F.add((dist <= 30.25) & (dist > 20) & front & (Z >= 25) & (Z <= 26), 5)
    # G3 발목 앞 갓 씌운 램프(위 띠 정면)
    yc = ay - 27
    porthole(F, G, "y", (ax, 0, 31), 4.5, 6.5, (yc - 3, yc + 2), face=yc - 3)
    F.add((box(G, x=(ax - 1, ax + 1), y=(yc - 5, yc - 3), z=(25, 37)) | box(G, x=(ax - 6, ax + 6), y=(yc - 5, yc - 3), z=(30, 32))), 5)
    F.trim()
    return F


def _shift(p, dx):
    p.lo[0] += dx; p.hi[0] += dx
    p.pivot = (p.pivot[0] + dx, p.pivot[1], p.pivot[2])


def build_legs(M):
    build_pelvis(M)
    for fn, dx in ((build_thigh, DX), (build_shin, DX + 2), (build_foot, DX + 4)):   # 아래로 갈수록 살짝 벌림
        _shift(fn(M), dx)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


def build_all():
    M = r8.build_all()
    build_legs(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model
    M = build_all()
    check_model.check(M)
    B = M.blocks()
    specs = [(-30, 6, "r9 앞 3/4"), (0, 4, "r9 정면"), (90, 2, "r9 옆(왼쪽)"), (160, 8, "r9 뒤 3/4")]
    ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=2.5, ss=2, ao_amt=0.5, metal=METAL) for y, p, _ in specs]
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "CETUS", "concept_v1_GPT_후보.png")).convert("RGB").crop((0, 100, 1229, 1280))
    H = ims[0].height
    con = con.resize((int(con.width * H / con.height), H), Image.LANCZOS)
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    tiles = [(con, "컨셉")] + list(zip(ims, [s[2] for s in specs]))
    W = sum(i.width for i, _ in tiles) + 16 * len(tiles)
    sh = Image.new("RGB", (W, H + 44), (18, 19, 22)); d = ImageDraw.Draw(sh); x = 0
    for im, t in tiles:
        sh.paste(im, (x, H - im.height)); d.text((x + 8, H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_r9_compare.png")); print(sh.size)
