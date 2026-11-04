"""새 표준 양산기 ST-10 다리 r1 (2026-11-04). 허리 확정(m2_waist_r1.build_all(final=True)) 아래에.
[읽기: 삼면도 정면 · 옆 · 뒤 + 메인 · z = (943 − y) × 0.301]
  허벅지(모래) z163~122 · 무릎판(짙은 회색 육각, 위 붉은 줄 = 데칼) z127~83 · 무릎 양옆 둥근 원판 z≈111 · 뒤 = 홈 파인 드럼
  정강이(모래) z100~53 — 종아리 뒤로 불룩, 아래 발목 쪽 좁아짐 · 바깥 옆 짙은 작은 블록 + 밝은 못
  발목 장갑(짙은) z58~33 아래로 퍼짐 · 양옆 둥근 원판 z≈39 · 발등 덮개(모래) z39~22 · 발(짙은 회색, 각진 큰 덩어리) z25~0
바이슨 다리 r2 교훈: 다리 축 하나(곧게)에 모든 부위를 같은 중심으로 쌓음 · 그림 윤곽 다각형은 쓰지 않음(지그재그) ·
  모서리 45° · 정수 기울기(1:2 · 45°)만 · 너클은 정강이 폭보다 조금만 바깥.
  팔 문법과 맞춤: 정강이 옆 = 원형 못 + 직사각 블록(팔 손목·팔꿈치와 같은 말).
쉬는 자세 팔 9° 벌림 [판단] — 허벅지가 굵어 안 벌리면 주먹이 허벅지에 파고듦(BISON 과 같음).
  a = 종아리 보통(원본 비율) · b = 종아리 더 불룩 + 발 1.1배(무게가 아래).
색: 1 모래 · 2 짙은 회색 · 3 짙은 프레임 · 4 검정 · 5 빨강(데칼 미리보기만) · 7 강철."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, cbox, poly, roty  # noqa: E402
import m2_waist_r1 as wr  # noqa: E402
import m2_shoulder_r1 as sh  # noqa: E402

PAL, EMISSIVE = wr.PAL, wr.EMISSIVE
CX = 23
HIP, KNEE, ANK = (CX, 0, 152), (CX, -1, 108), (CX, 0, 36)
SPLAY = 3                     # 고관절에서 바깥으로 3°(원본 정면의 벌린 자세), 발은 바닥에 평평하게 되돌림
ARM_SPLAY = {"UpperArmL": roty(-9), "UpperArmR": roty(9)}
R2 = False                    # r2 [유저 11-04 표시 4곳]: 고관절 작게 · 무릎판 = 위아래 잇는 부품 · 발목 장갑 작게 + 양옆 모래 사이 · 발 세로 홈 뺌
SPEC = {"a": dict(bulge=3, back=5, ft=1.0), "b": dict(bulge=4, back=8, ft=1.1)}


def upper_leg(M):
    U = M.part("UpperLegL", (0, -22, 112), (46, 20, 166), pivot=HIP, parent="Pelvis")
    G = U.g(); X, Y, Z = G; dx = np.abs(X - CX)
    if R2:
        # 파랑 [유저 "골반 관절이 원본은 두껍고 크지 않았어. 살짝 노출돼서 다리와 골반을 잇는 느낌"]: 공 r9 → r6 · 뼈대 ±10 → ±7 · 장갑 위 끝 z147 → 153(치마 밑으로 짙은 관절이 조금만 드러남)
        U.add(sh.facet_ellipsoid(G, HIP, (6, 6, 6), sh.DIRS_A), 3)
        U.add(cbox(G, (CX - 7, CX + 7), (-7, 7), (116, 150), {"xy": 2}), 3)
        U.add(cbox(G, (CX - 15, CX + 15), (-15, 14), (122, 153), {"xy": 5, "+zx": 4, "+zy": 3, "-zy": 3, "-zx": 2}), 1)
    else:
        U.add(sh.facet_ellipsoid(G, HIP, (9, 9, 9), sh.DIRS_A), 3)                                   # 고관절 공(장갑 속)
        U.add(cbox(G, (CX - 10, CX + 10), (-10, 10), (116, 150), {"xy": 3}), 3)                       # 짙은 뼈대
        U.add(cbox(G, (CX - 15, CX + 15), (-15, 14), (122, 147), {"xy": 5, "+zx": 4, "+zy": 3, "-zy": 3, "-zx": 2}), 1)   # 허벅지 장갑
    U.emboss((dx <= 10) & (Z >= 127) & (Z <= 143) & (Y < -14) & (dx <= 10 - np.clip(129 - Z, 0, None)), 1)          # 앞 덧판 1칸
    U.add(cbox(G, (CX - 9, CX + 9), (14, 16), (126, 146), {"x+y": 2}) & ~(U.a > 0), 2)               # 뒤 판(짙은)
    U.rot = roty(-SPLAY)
    U.trim()


def lower_leg(M, v):
    sp = SPEC[v]
    L = M.part("LowerLegL", (-8, -32, 26), (54, 34, 130), pivot=KNEE, parent="UpperLegL")
    G = L.g(); X, Y, Z = G; dx = np.abs(X - CX)
    ky, kz = KNEE[1], KNEE[2]
    # 무릎 관절: 양옆 둥근 너클(정강이 폭보다 2칸 바깥) + 축 + 뒤 홈 드럼
    for xa, xb in ((CX - 17, CX - 11), (CX + 11, CX + 17)):
        L.add(cyl(G, "x", (ky, kz), 7.5, rng=(xa, xb)), 3)
        xe = xa if xa < CX else xb
        L.groove(cyl(G, "x", (ky, kz), 8) & ~cyl(G, "x", (ky, kz), 5.5) & (X == xe), 4)
        L.paint(cyl(G, "x", (ky, kz), 2.5) & (X == xe), 2)
    L.add(cyl(G, "x", (ky, kz), 4, rng=(CX - 11, CX + 11)), 4)
    drum = cyl(G, "x", (ky + 3, kz - 1), 8, rng=(CX - 9, CX + 9))                                      # 뒤 드럼(그림 뒤 무릎)
    L.add(drum, 3)
    ang = np.arctan2(np.broadcast_to(Z - (kz - 1), L.a.shape), np.broadcast_to(Y - (ky + 3), L.a.shape))
    L.groove(drum & (np.abs(((ang / (np.pi / 6)) % 1.0) - 0.5) < 0.18) & np.broadcast_to(dx <= 8, L.a.shape), 4)
    # 정강이: 곧은 축 · 무릎 밑에서 불룩(옆 1:2) · 종아리 뒤로 45° · 아래 1:2 로 발목 쪽 좁아짐
    b = sp["bulge"]; bk = sp["back"]
    w = 12 + np.minimum(np.clip(98 - Z, 0, None) / 2.0, b) - np.clip(64 - Z, 0, None) / 2.0
    yf = -12 - np.minimum(np.clip(98 - Z, 0, None) / 2.0, 1.5) + np.clip(62 - Z, 0, None) / 2.0
    yb = 10 + np.minimum(np.clip(96 - Z, 0, None), bk) - np.clip(68 - Z, 0, None) / 2.0
    if R2:
        # 초록 [유저 "좀 크고, 양옆 모래 부분에 낀 느낌"]: 정강이 양옆을 z40 까지 내려(가운데 ±8 은 비움) 짙은 발목 판이 그 사이에 끼게
        w = np.maximum(w, 11.0)
        yf = -13.5 + np.clip(58 - Z, 0, None) / 2.0
        yb = np.maximum(yb, 8.0)
        shin = (dx <= w) & (Y >= yf) & (Y <= yb) & (Z <= 98) & ((Z >= 52) | ((Z >= 40) & ((dx > 8) | (Y > 4))))
    else:
        shin = (dx <= w) & (Y >= yf) & (Y <= yb) & (Z >= 52) & (Z <= 98)
    shin &= ((w - dx) + (Y - yf) >= 4) & ((w - dx) + (yb - Y) >= 5)                                  # 세로 모서리 45°
    L.add(shin & ~(L.a > 0), 1)
    L.add(cbox(G, (CX - 11, CX + 11), (-10, 10), (92, 102), {"xy": 3}) & ~(L.a > 0), 3)               # 무릎 밑 짙은 이음
    # 무릎판: 짙은 회색 육각 · 정강이 위를 덮는 처마 · 2단
    if R2:
        # 빨강 [유저 "위아래를 잇는 부분인데 무릎 위에 덧댄 보호대처럼 보여"]: 앞으로 8칸 튀어나온 판(z86~126) → 허벅지 끝(z122)과 정강이 위(z98) 사이를
        # 채우는 무릎 마디 — 폭 ±10 · 앞면 Y−16(허벅지 앞면과 같은 높이) · 위아래로 2칸씩 겹쳐 들어감 · 2단 판 뺌
        kp = cbox(G, (CX - 10, CX + 10), (-16, -6), (95, 124), {"xz": 4, "x-y": 3, "+z-y": 2, "-z-y": 3})
        L.add(kp, 2)
    else:
        kp = cbox(G, (CX - 12, CX + 12), (-21, -11), (86, 126), {"xz": 7, "x-y": 3, "+z-y": 4, "-z-y": 3})
        L.add(kp, 2)
        L.emboss((dx <= 8 - np.clip(np.abs(Z - 106) - 12, 0, None)) & (Z >= 91) & (Z <= 121) & (Y < -20), 2)
    # 정강이 바깥 옆: 원형 못 + 직사각 블록(팔 관절과 같은 말)
    xo = CX + 12 + b
    L.add(cbox(G, (xo - 1, xo + 2), (-5, 3), (66, 78), {"xz": 1, "xy": 1}) & ~((X < xo) & (L.a > 0)), 2)
    L.add(cyl(G, "x", (-1, 72), 1.8, rng=(xo + 2, xo + 3)), 7)
    # 발목 장갑(짙은): 1차 갓 모양(아래로 크게 퍼짐) → 옆은 곧게 ±11 + 아래 4칸만 1:2 로 ±13 · 앞은 1:2 로 앞·아래로 기울어 발등 위를 덮음
    if R2:
        yfa = -12 - np.clip(50 - Z, 0, None) / 2.0                                                    # 앞은 1:2 로 앞·아래(발등 위)
        ank = (dx <= 8) & (Z >= 34) & (Z <= 56) & (Y >= yfa) & (Y <= 4)
        ank &= ((8 - dx) + (Y - yfa) >= 3)
        L.add(ank & ~(L.a > 0), 2)
        L.add(cbox(G, (CX - 11, CX + 11), (-4, 8), (36, 40), {"xy": 2}) & ~(L.a > 0), 3)              # 정강이 양옆 끝을 잇는 짙은 바닥
    else:
        wa = 11 + np.clip(38 - Z, 0, None) / 2.0
        yfa = -11 - np.clip(52 - Z, 0, None) / 2.0
        ank = (dx <= wa) & (Z >= 30) & (Z <= 56) & (Y >= yfa) & (Y <= 11)
        ank &= ((wa - dx) + (Y - yfa) >= 4) & ((wa - dx) + (11 - Y) >= 4)
        L.add(ank & ~(L.a > 0), 2)
        L.paint_s((Z >= 52) & (Z <= 53) & (L.a == 1), 3)                                              # 정강이 끝 짙은 테
    L.trim()


def foot(M, v):
    """1차: 발목 원판·축이 발과 떨어져 섬 · 발이 낮고 납작(z0~16) → 발목 속 짙은 기둥으로 이음 · 발 z0~20 굵게."""
    s = SPEC[v]["ft"]
    F = M.part("FootL", (-6, -46, 0), (52, 36, 44), pivot=ANK, parent="LowerLegL")
    G = F.g(); X, Y, Z = G; dx = np.abs(X - CX)
    fw = round(15 * s); yt = round(-34 * s); yh = round(24 * s)
    for sx in (1, -1):                                                                                # 발목 원판(둥근, 양옆)
        F.add(cyl(G, "x", (0, ANK[2]), 6, rng=sorted((CX + sx * 11, CX + sx * 14))), 3)
        F.groove(cyl(G, "x", (0, ANK[2]), 6.4) & ~cyl(G, "x", (0, ANK[2]), 4) & (X == CX + sx * 14), 4)
    F.add(cyl(G, "x", (0, ANK[2]), 4, rng=(CX - 11, CX + 11)), 4)
    F.add(cbox(G, (CX - 8, CX + 8), (-7, 9), (16, ANK[2] + 2), {"xy": 3}), 3)                         # 발목 속 짙은 기둥(원판 ↔ 발)
    base = cbox(G, (CX - fw, CX + fw), (yt, yh), (0, 20), {"xy": 5, "+zx": 3, "-y+z": 6, "+y+z": 4})
    F.add(base, 2)
    F.add(cbox(G, (CX - fw + 3, CX + fw - 3), (yt - 3, yt + 8), (0, 11), {"x-y": 3, "-y+z": 4}) & ~(F.a > 0), 2)   # 발끝 앞 단
    if not R2:
        F.groove((X == CX) & (Y <= yt + 6) & (Z >= 2), 4)                                            # 발끝 가운데 홈(r2: 뺌 [유저 "발쪽 세로 갈라짐 없애자"])
    F.add(cbox(G, (CX - fw - 1, CX + fw + 1), (yt + 1, yh + 1), (0, 2), {"xy": 6}), 3)               # 발바닥(짙은 프레임)
    F.add(cbox(G, (CX - 11, CX + 11), (-24, -2), (18, 31), {"xy": 4, "-y+z": 5, "x+z": 3}) & ~(F.a > 0), 1)   # 발등 덮개(모래)
    F.rot = roty(SPLAY)
    F.trim()


def build_all(v="a", r2=False):
    global R2
    R2 = r2
    M = wr.build_all(final=True)
    upper_leg(M); lower_leg(M, v); foot(M, v)
    for n in ("UpperLegL", "LowerLegL", "FootL"):
        M.mirror(n, n[:-1] + "R")
    return M


def paint_knee_stripe(M):
    """데칼 미리보기: 무릎판 위 붉은 띠."""
    for n in ("LowerLegL", "LowerLegR"):
        L = M.parts[n]; G = L.g(); X, Y, Z = G
        L.paint_s((Z >= 118) & (Z <= 121) & (Y <= -15) & (L.a == 2), 5)


def overlaps(M, pose=None):
    def cells(n):
        p = M.parts[n]; T = M.world(n, pose); ijk = np.argwhere(p.a > 0) + p.lo
        return set(map(tuple, np.round(ijk @ T[:3, :3].T + T[:3, 3]).astype(int)))
    legs = set().union(*(cells(n) for n in ("UpperLegL", "LowerLegL", "FootL")))
    arm = set().union(*(cells(n) for n in ("LowerArmL", "HandL")))
    legR = set().union(*(cells(n) for n in ("UpperLegR", "LowerLegR", "FootR")))
    armR = set().union(*(cells(n) for n in ("LowerArmR", "HandR")))
    return {"팔∩다리": len(arm & legs), "오른팔∩오른다리": len(armR & legR), "좌∩우 다리": len(legs & legR), "골반∩허벅지": len(cells("Pelvis") & cells("UpperLegL")),
            "칼집∩허벅지": len((cells("KnifeHolster") | cells("KnifeStowed")) & cells("UpperLegL"))}


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import m2_head_trace as ht
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 24); ft = ImageFont.truetype(FN, 28)
    V = ((0, 3), (-35, 8), (-90, 3), (150, 8))
    rows = []
    for v, lab in (("a", "a  종아리 보통(원본 비율)"), ("b", "b  종아리 더 불룩 + 발 1.1배")):
        M = build_all(v); cm.check(M)
        print(v, "겹침(팔 9° 벌림)", overlaps(M, ARM_SPLAY), "안 벌림", overlaps(M))
        paint_knee_stripe(M)
        ims = [vp.render(M.blocks(pose=ARM_SPLAY), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=2.2, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in V]
        sk = [n for n in M.parts if not n.endswith("LegL") and n != "FootL"]
        ims += [vp.render(M.blocks(skip=sk), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=3.5, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in ((-40, 8), (-90, 3))]
        rows.append((lab + " · 팔 9° 벌림 · 무릎 붉은 줄 = 데칼 미리보기 · 오른쪽 2장 = 왼다리만", ims))
    con = Image.open(ht.SRC).convert("RGB")
    H = max(i.height for _, r in rows for i in r)
    refs = [con.crop((0, 40, 540, 980)), con.crop((560, 40, 900, 980)), con.crop((990, 40, 1530, 980))]
    refs = [x.resize((int(x.width * H / x.height), H)) for x in refs]
    rows.insert(0, ("원본(정면 · 옆 · 뒤)", refs))
    W = max(sum(i.width + 14 for i in r) for _, r in rows) + 20
    sht = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sht)
    d.text((14, 14), "새 양산기 다리 r1 — 허벅지 · 육각 무릎판 + 너클 + 뒤 드럼 · 불룩 종아리 + 옆 못·블록 · 퍼진 발목 · 각진 발", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((14, y), t, fill=(240, 200, 120), font=f); x = 14; y += 36
        for im in r:
            sht.paste(im, (x, y + (H - im.height) // 2)); x += im.width + 14
        y += H + 8
    p = os.path.join(out, "시안_다리r1.png"); sht.save(p); print(p, sht.size)
