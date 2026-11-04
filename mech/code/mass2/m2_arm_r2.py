"""새 표준 양산기 ST-10 팔 r2 (2026-11-04) — 유저 r1 표시(사진):
  파랑 = 가로줄(위팔 z198 · 아래팔 z154) 뜻 모름 → 가로줄 전부 뺌
  빨강 위 = 어깨 바로 밑 관절 표현 없음 → 위팔 위에 관절을 드러냄
  빨강 아래 = 팔꿈치: 바이슨 관절 표현(원형 너클 + 직사각 블록, mass_arm_r2 f) 그대로
  흰 표시 = 회색 손목도 관절 표현 부족 → 원형 못 + 직사각 블록
바이슨 f 문법: 위팔·아래팔 사이 틈 12칸 · 위 축 뒤(Y+1.5) · 아래 축 앞(Y−2.5) · 양옆 둥근 너클 4(r4.2) · 가운데 직사각 블록 ·
  양옆 강철 링크판(비스듬) · 뒤 강철 피스톤 막대 · 모두 팔 폭 안.
높이 다시 나눔: 어깨 관절 z204~213 · 위팔 z191~205 · 팔꿈치 z179~191 · 아래팔 z142~178 · 손목 z135~141 · 손 z114~135.
  A = 어깨도 같은 너클 경첩(축 X 하나, 앞뒤로 흔듦) · B = 어깨는 돌림 고리(짙은 원통) + 앞 직사각 블록 + 원형 못."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
sys.path.insert(0, os.path.join(HERE, "..", "mass"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, cbox  # noqa: E402
import m2_shoulder_r1 as sh  # noqa: E402
from mass_r1 import seg  # noqa: E402

PAL, EMISSIVE = sh.PAL, sh.EMISSIVE
AX = 44
SHO = (AX, 0, 227)
ELB = (AX, -0.5, 185)
WRI = (AX, 0, 138)


def knuckle_hinge(P, G, axes, zr, block_y=(-6, 4), links=True):
    """바이슨 f 경첩: axes = [(Y, Z), ...] X 축 · 양옆 너클(AX±4~7) · 가운데 직사각 블록(AX±3) · 강철 링크판."""
    X, Y, Z = G
    for (yc, zc) in axes:
        P.add(cyl(G, "x", (yc, zc), 2.5, rng=(AX - 8, AX + 8)), 4)                                    # 축
        for xa, xb in ((AX - 7, AX - 4), (AX + 4, AX + 7)):
            P.add(cyl(G, "x", (yc, zc), 4.2, rng=(xa, xb)), 3)                                      # 둥근 너클
            P.groove(cyl(G, "x", (yc, zc), 4.6) & ~cyl(G, "x", (yc, zc), 2.8) & (X == (xa if xa < AX else xb)), 4)
    P.add(cbox(G, (AX - 3, AX + 3), block_y, zr, {"yz": 2}), 3)                                    # 가운데 직사각 블록
    if links and len(axes) == 2:
        (y0, z0), (y1, z1) = axes
        for x0 in (AX - 4, AX + 4):
            P.add(seg(G, (x0, y0, z0), (x0, y1, z1), 2.6) & (X == x0), 7)                           # 강철 링크판


def upper_arm(M, var="A"):
    U = M.part("UpperArmL", (30, -14, 186), (62, 14, 234), pivot=SHO, parent="Torso")
    G = U.g(); X, Y, Z = G
    U.add(cyl(G, "x", (0, 227), 6.5, rng=(34, 52)), 2)                                                # 어깨 축(장갑 속)
    U.add(cbox(G, (AX - 5, AX + 5), (-6, 6), (213, 226), {"xy": 2}), 3)                               # 위 목(장갑 속)
    if var == "A":
        knuckle_hinge(U, G, [(0, 209)], (204, 213), block_y=(-5, 4), links=False)
    else:
        U.add(cyl(G, "z", (AX, 0), 7, rng=(205, 213)), 3)                                             # 돌림 고리
        U.add(cyl(G, "z", (AX, 0), 7.6, rng=(208, 209)) & ~cyl(G, "z", (AX, 0), 6.6, rng=(208, 209)), 3)
        U.add(cbox(G, (AX - 3, AX + 3), (-9, -6), (205, 212), {"yz": 1}), 3)                          # 앞 직사각 블록
        U.add(cyl(G, "y", (AX, 208.5), 1.8, rng=(-10, -9)), 4)                                        # 원형 못
    U.add(cbox(G, (AX - 9, AX + 9), (-9, 9), (191, 205), {"xy": 3, "xz": 2, "yz": 2}), 1)             # 위팔 상자(가로줄 없음) — 1차 z193~204 는 관절 사이 구슬처럼 짧음
    U.emboss((np.abs(X - AX) <= 6) & (Z >= 194) & (Z <= 202) & (Y < -8), 1)                          # 앞 덧판 1칸
    U.trim()
    return U


WRISTS = {
    "W0": "r2: 짙은 띠 + 양옆 원형 못 + 앞 직사각 블록",
    "W1": "바이슨식 짧은 띠(아래팔보다 4칸 안쪽 · 가운데 홈 고리)",
    "W2": "소매: 아래팔 끝이 손목을 통째로 덮음(손이 소매에서 나옴)",
    "W3": "작은 너클 경첩(어깨 A · 팔꿈치와 같은 문법, 축 하나)",
    "W4": "양옆 직사각 브래킷 + 바깥 원형 못(축) + 가운데 짙은 심",
}


def wrist_joint(L, G, wrist, final=False):
    X, Y, Z = G; dx = np.abs(X - AX)
    if wrist == "W0":
        L.add(cyl(G, "z", (AX, 0), 7, rng=(135, 141)), 3)
        for sx in (1, -1):
            L.add(cyl(G, "x", (0, 138), 2.2, rng=sorted((AX + sx * 6, AX + sx * 8))), 4)
        L.add(cbox(G, (AX - 3, AX + 3), (-9, -6), (135, 141), {"yz": 1}), 3)
    elif wrist == "W1":
        L.add(cyl(G, "z", (AX, 0), 6, rng=(135, 141)), 3)
        L.groove(cyl(G, "z", (AX, 0), 6.5) & ~cyl(G, "z", (AX, 0), 5.0) & (Z == 138), 4)
    elif wrist == "W2":
        # 1차: 짧은 소매(z137~142) + 공 → 공은 손등에 가려 안 보이고 소매 턱이 가로줄처럼 읽힘
        # → 아래팔 끝을 그대로 z133 까지 이어 손목을 통째로 덮음(손이 소매에서 나옴) · 속은 짙은 심
        cuff = (dx <= 9.5) & (np.abs(Y) <= 8) & (Z >= 133) & (Z <= 142) & (dx + np.abs(Y) <= 14)
        L.add(cuff & ~((dx <= 7) & (np.abs(Y) <= 6) & (Z <= 139)), 1)
        L.add(cyl(G, "z", (AX, 0), 5, rng=(134, 141)), 3)
        if final:
            # [결정 11-04 "W2 로 가되 손목부에 관절을 표현한 검정 작은 판 하나만 파서 넣어줘"] 소매 앞면에 1칸 파인 검정 판(6×5)
            plate = (dx <= 3) & (Z >= 135) & (Z <= 139) & (Y <= -7)
            L.cut(plate & (Y == -8)); L.add(plate & (Y == -7), 4)
    elif wrist == "W3":
        knuckle_hinge(L, G, [(0, 138)], (135, 141), block_y=(-5, 4), links=False)
    elif wrist == "W4":
        L.add(cyl(G, "z", (AX, 0), 5, rng=(134, 142)), 3)                                             # 가운데 심
        for sx in (1, -1):
            L.add(cbox(G, sorted((AX + sx * 5, AX + sx * 7)), (-5, 5), (133, 143), {"yz": 2}), 2)     # 직사각 브래킷
            L.add(cyl(G, "x", (0, 138), 2.4, rng=sorted((AX + sx * 7, AX + sx * 8))), 4)             # 원형 못(축 끝)


def lower_arm(M, wrist="W0", final=False):
    L = M.part("LowerArmL", (28, -16, 132), (62, 16, 196), pivot=ELB, parent="UpperArmL")
    G = L.g(); X, Y, Z = G; dx = np.abs(X - AX)
    knuckle_hinge(L, G, [(1.5, 188), (-2.5, 182)], (179, 191))
    L.add(seg(G, (AX, 4, 191), (AX, 4, 179), 1.6), 7)                                                 # 뒤 피스톤 막대
    w = 13.0 - np.clip(Z - 176, 0, None) * 1.0 - np.clip(149 - Z, 0, None) / 2.0                     # 1차: 위 45° 5칸 → 항아리 → 2칸
    d = 11.0 - np.clip(Z - 176, 0, None) * 1.0 - np.clip(149 - Z, 0, None) / 2.0
    fa = (dx <= w) & (np.abs(Y) <= d) & (Z >= 142) & (Z <= 178)
    fa &= (dx + np.abs(Y) <= np.maximum(w, d) + np.minimum(w, d) - 4)
    L.add(fa & ~(L.a > 0), 1)
    L.emboss((dx <= 8) & (Z >= 152) & (Z <= 173) & (Y < -10), 1)                                       # 앞 덧판 1칸(세로 판 — 가로줄 없음)
    wrist_joint(L, G, wrist, final)
    L.trim()
    return L


def hand(M):
    """r1 주먹을 3칸 내림(손목 z135)."""
    Hn = M.part("HandL", (30, -14, 108), (58, 12, 137), pivot=WRI, parent="LowerArmL")
    G = Hn.g(); X, Y, Z = G
    Hn.add(cbox(G, (AX - 7, AX + 7), (-8, 8), (123, 134), {"xy": 2, "+xz": 2, "yz": 2}), 2)
    fing = cbox(G, (AX - 8, AX + 3), (-8, 8), (114, 124), {"-xz": 4, "+xz": 2, "yz": 1})
    Hn.add(fing & ~(Hn.a > 0), 3)
    for yc in (-4, 0, 4):
        Hn.groove(fing & (Y == yc), 4)
    Hn.add(cbox(G, (AX - 6, AX + 1), (-11, -8), (119, 130), {"yz": 2, "-xy": 2}) & ~(Hn.a > 0), 2)    # 엄지
    Hn.emboss((X >= AX + 7) & (Z >= 125) & (Z <= 133) & (np.abs(Y) <= 6), 2)                          # 손등 판
    Hn.trim()
    return Hn


def build_all(var="A", wrist="W0", final=False):
    """final=True → 팔 확정 [결정 11-04] = 어깨 밑 관절 A · 바이슨식 팔꿈치 · 손목 W2 소매 + 앞 검정 판."""
    if final:
        var, wrist = "A", "W2"
    M = sh.build_all(final=True)
    upper_arm(M, var); lower_arm(M, wrist, final); hand(M)
    for n in ("UpperArmL", "LowerArmL", "HandL"):
        M.mirror(n, n[:-1] + "R")
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 22); ft = ImageFont.truetype(FN, 26)
    V = ((0, 3), (-35, 8), (-90, 3), (150, 8))
    rows = []
    for v, lab in (("A", "A  어깨 = 팔꿈치와 같은 너클 경첩"), ("B", "B  어깨 = 돌림 고리 + 앞 직사각 블록 + 원형 못")):
        M = build_all(v); cm.check(M)
        ims = [vp.render(M.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=3, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in V]
        # 팔만 확대(정면 · 3/4)
        sk = [n for n in M.parts if n not in ("UpperArmL", "LowerArmL", "HandL")]
        ims += [vp.render(M.blocks(skip=sk), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=6, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in ((0, 3), (-40, 8))]
        rows.append((lab + " · 팔꿈치 = 바이슨 2축 경첩 · 손목 = 원형 못 + 직사각 블록 · 가로줄 없음", ims))
    H = max(i.height for _, r in rows for i in r)
    W = max(sum(i.width + 16 for i in r) for _, r in rows) + 32
    sht = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sht)
    d.text((16, 14), "새 양산기 팔 r2 — 가로줄 뺌 · 어깨 밑 관절 · 바이슨식 팔꿈치 · 손목 관절 (오른쪽 2장 = 왼팔 확대)", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((16, y), t, fill=(240, 200, 120), font=f); x = 16; y += 32
        for im in r:
            sht.paste(im, (x, y + (H - im.height) // 2)); x += im.width + 16
        y += H + 12
    p = os.path.join(out, "시안_팔r2.png"); sht.save(p); print(p, sht.size)
