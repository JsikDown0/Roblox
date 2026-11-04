"""새 표준 양산기 ST-10 팔 r1 (2026-11-04). 어깨 확정(m2_shoulder_r1.build_all(final=True)) 아래에.
[읽기: 삼면도 원본 px · z = (943 − y) × 0.301 · 폭 ×0.92 · 머리 가운데 x≈263]
  팔 축 X ±46(정면 오른팔 가운데 x≈90)
  위팔(모래): y230~310 → z215~191 · 폭 70px → ±9.5 · 짧은 상자, 모서리 깎음, 아래쪽 가로 이음매 · 위는 어깨 장갑 속
  팔꿈치(짙은 회색): y302~350 → z193~178 · 가로축(X) 드럼 + 겉에 세로 홈(톱니처럼, 정면에서 가로줄로 보임)
  아래팔(모래): y312~490 → z190~136 · 폭 97px → ±13.5(위팔보다 굵음) · 위는 드럼을 감싸는 홈(가운데 파임) · 가운데 가장 넓고 손목으로 좁아짐
    손목 짙은 회색 띠
  손(짙은 회색 주먹): y490~560 → z136~116
판단: 어깨 장갑은 몸통에 둠(팔은 장갑 밑에서 돎) — 큰 돔이 팔 따라 돌면 머리·가슴을 뚫음.
  a = 아래팔 8각(모서리 4) · b = 아래팔 앞에 덧판 1칸(2단 장갑) + 모서리 6.
색: 1 모래 · 2 짙은 회색 · 3 짙은 프레임 · 4 검정."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, cbox  # noqa: E402
import m2_shoulder_r1 as sh  # noqa: E402

PAL, EMISSIVE = sh.PAL, sh.EMISSIVE
AX = 44                       # 팔 축 X(1차 46 → 원본보다 몸에서 멀어 44)
SHO = (AX, 0, 227)            # 어깨 회전 중심(어깨 관절 높이)
ELB = (AX, 0, 186)            # 팔꿈치
WRI = (AX, 0, 138)            # 손목


def upper_arm(M):
    U = M.part("UpperArmL", (30, -14, 180), (62, 14, 232), pivot=SHO, parent="Torso")
    G = U.g(); X, Y, Z = G
    U.add(cyl(G, "x", (0, 227), 6.5, rng=(34, 52)), 2)                                                # 어깨 축(장갑 속)
    U.add(cbox(G, (AX - 6, AX + 6), (-7, 7), (205, 226), {"xy": 2}), 2)                               # 위 목(장갑 속, 짙은)
    U.add(cbox(G, (AX - 9, AX + 9), (-9, 9), (192, 215), {"xy": 3, "xz": 2, "yz": 2}), 1)             # 위팔 상자
    U.groove((Z == 198) & (np.abs(X - AX) <= 9), 4)                                                    # 아래 가로 이음매
    U.add(cbox(G, (AX - 6, AX + 6), (-6, 6), (188, 192), {}) & ~(U.a > 0), 2)                         # 드럼 받침
    U.trim()
    return U


def lower_arm(M, var="a"):
    L = M.part("LowerArmL", (28, -16, 132), (64, 16, 196), pivot=ELB, parent="UpperArmL")
    G = L.g(); X, Y, Z = G; dx = np.abs(X - AX)
    # 팔꿈치 드럼(X 축) + 세로 홈 8(톱니처럼)
    drum = cyl(G, "x", (ELB[1], ELB[2]), 7.5, rng=(AX - 8, AX + 8))
    L.add(drum, 2)
    ang = np.arctan2(np.broadcast_to(Z - ELB[2], L.a.shape), np.broadcast_to(Y - ELB[1], L.a.shape))
    teeth = (np.abs(((ang / (np.pi / 6)) % 1.0) - 0.5) < 0.18) & np.broadcast_to(dx <= 7, L.a.shape)
    L.groove(teeth & drum, 3)
    L.add(cyl(G, "x", (ELB[1], ELB[2]), 8.5, rng=(AX - 9, AX - 8)) | cyl(G, "x", (ELB[1], ELB[2]), 8.5, rng=(AX + 8, AX + 9)), 3)   # 드럼 양끝 테
    # 아래팔: z150~182 ±13 거의 곧은 굵은 상자 · 위 바깥 모서리만 45° · 아래 1:2 로 3칸 좁아짐(손목 ±10)
    # 1차: 가운데만 넓고 위아래로 좁아져 원뿔·항아리처럼 보임
    w = 13.0 - np.clip(Z - 177, 0, None) * 1.0 - np.clip(150 - Z, 0, None) / 2.0
    d = 11.0 - np.clip(Z - 178, 0, None) * 1.0 - np.clip(150 - Z, 0, None) / 2.0
    ch_ = 4 if var == "a" else 6
    fa = (dx <= w) & (np.abs(Y) <= d) & (Z >= 144) & (Z <= 182)                                       # 2차: 위 z187 은 드럼을 덮어 팔꿈치가 안 보임 → z182(드럼 아래 반만 감쌈)
    fa &= (dx + np.abs(Y) <= np.maximum(w, d) + np.minimum(w, d) - ch_)
    L.add(fa & ~(L.a > 0), 1)
    L.cut(cyl(G, "x", (ELB[1], ELB[2]), 9.0, rng=(AX - 9, AX + 9)) & (L.a == 1))                         # 드럼 자리 파임(위 홈)
    if var == "b":
        L.emboss((np.abs(Y) <= 7) & (Z >= 150) & (Z <= 176) & (Y < -6) & (dx <= 9), 1)                # 앞 덧판 1칸
        L.groove((Z == 152) & (Y < 0) & (dx <= 12), 4)
    else:
        L.groove((Z == 154) & (dx <= 14), 4)                                                            # 아래 가로 이음매
    L.add(cbox(G, (AX - 9, AX + 9), (-8, 8), (139, 143), {"xy": 2}), 2)                                # 손목 띠
    L.trim()
    return L


def hand(M):
    """짙은 회색 주먹(1차: 작은 상자 + 옆으로 삐져나온 손가락 → 손목 띠만큼 굵은 덩어리 + 홈으로 나눈 손가락).
    손등 = 바깥(+X) · 손가락 4 = 몸 쪽 아래로 말려 앞뒤(Y)로 줄 · 엄지 = 앞."""
    Hn = M.part("HandL", (30, -14, 112), (58, 12, 140), pivot=WRI, parent="LowerArmL")
    G = Hn.g(); X, Y, Z = G
    Hn.add(cbox(G, (AX - 7, AX + 7), (-8, 8), (126, 138), {"xy": 2, "+xz": 2, "yz": 2}), 2)              # 손바닥·손등
    fing = cbox(G, (AX - 8, AX + 3), (-8, 8), (117, 127), {"-xz": 4, "+xz": 2, "yz": 1})              # 말린 손가락 덩어리(몸 쪽 아래)
    Hn.add(fing & ~(Hn.a > 0), 3)
    for yc in (-4, 0, 4):
        Hn.groove(fing & (Y == yc), 4)                                                                 # 손가락 사이 홈 3 → 4개
    Hn.groove((Z == 126) & (X <= AX + 3) & (Hn.a == 3), 4)                                             # 첫째 마디 홈
    Hn.add(cbox(G, (AX - 6, AX + 1), (-11, -8), (122, 133), {"yz": 2, "-xy": 2}) & ~(Hn.a > 0), 2)    # 엄지(앞)
    Hn.emboss((X >= AX + 7) & (Z >= 128) & (Z <= 136) & (np.abs(Y) <= 6), 2)                          # 손등 판 1칸
    Hn.trim()
    return Hn


def build_all(var="a"):
    M = sh.build_all(final=True)
    upper_arm(M); lower_arm(M, var); hand(M)
    for n in ("UpperArmL", "LowerArmL", "HandL"):
        M.mirror(n, n[:-1] + "R")
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import m2_head_trace as ht
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 22); ft = ImageFont.truetype(FN, 26)
    V = ((0, 3), (-35, 8), (-90, 3), (150, 8))
    rows = []
    for v, lab in (("a", "a  아래팔 8각(모서리 4) · 가로 이음매"), ("b", "b  아래팔 앞 덧판 1칸(2단) · 모서리 6")):
        M = build_all(v); cm.check(M)
        rows.append((lab, [vp.render(M.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=3, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in V]))
    con = Image.open(ht.SRC).convert("RGB")
    H = max(i.height for _, r in rows for i in r)
    refs = [con.crop((0, 80, 540, 620)), con.crop((560, 80, 920, 620)), con.crop((990, 80, 1530, 620))]
    refs = [x.resize((int(x.width * H / x.height), H)) for x in refs]
    rows.insert(0, ("원본 아트(정면 · 옆 · 뒤 — 방패는 뺌)", refs))
    W = max(sum(i.width + 16 for i in r) for _, r in rows) + 32
    sht = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sht)
    d.text((16, 14), "새 양산기 팔 r1 — 위팔 · 톱니 드럼 팔꿈치 · 굵은 아래팔 · 주먹", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((16, y), t, fill=(240, 200, 120), font=f); x = 16; y += 32
        for im in r:
            sht.paste(im, (x, y)); x += im.width + 16
        y += H + 12
    p = os.path.join(out, "시안_팔r1.png"); sht.save(p); print(p, sht.size)
