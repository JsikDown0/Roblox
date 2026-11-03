"""양산형 팔 r1 (2026-11-03) — 윤곽 읽기 r3 답 [결정 11-03 "ㅇㅋ"]: 팔꿈치 끝 원반 넣음(양 끝) · 반쯤 쥔 주먹 · 팔 ×1.0 · 길이 그림 그대로.
왼팔(+X)을 만들고 거울 → 오른팔. 무장(라이플·왼팔뚝 방패) 없음.
[읽기 → 칸] 정면 X = (x − 273) × 0.295 · z = (925 − y) × 0.295
  A1 위팔 x92~163 → |X| 32~53, z214~196 (위는 어깨 장갑 밑으로 z222 까지) · 깊이 ±10 [판단]
  A2 팔꿈치 x82~160 → |X| 33~56, z196~186 → 가로 원통 r5.5 @ z191 + 마디 홈 + 양 끝 원반(A2b)
  A3 아래팔 위 x98~172 → |X| 30~52 (z186), 아래 |X| 35~48 (z163) · 앞면 아래로 갈수록 뒤로 1:4 · 앞 덧판 1칸
  A4 손목 x105~158 → |X| 34~49, z163~152 → 짙은 원통 r7 + 마디 홈
  A5 주먹 x95~165 → |X| 32~52, z152~131 → 짙은 쇠(2) 반쯤 쥔 주먹: 손등 + 앞 손가락 4(세로 홈) + 손가락 마디 가로 홈 + 안쪽 엄지
파트: UpperArmL(부모 Torso, 피벗 어깨 관절 (31,−1,223)) · LowerArmL(부모 UpperArmL, 피벗 팔꿈치 (43,−1,191)) ·
      HandL(부모 LowerArmL, 피벗 손목 (42,−1,158)) → 거울 R.
  1차 [실측: 겹침 검사] 쉬는 자세 = 위팔 윗부분만 어깨 장갑 속(보이지 않음) · 팔 앞 60° 이상 · 옆 35° 에서 위팔이 어깨 장갑/판을 파고듦
     → 게임에서 어깨 장갑(ShoulderL/R)이 팔을 일부 따라 돌아야 함(동작 단계 메모).
  a  그림 그대로     b  아래팔 바깥으로 3칸 더 굵게 + 위팔 앞뒤 2칸 더 두껍게(더 육중)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, poly, rotx, roty  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_shoulder_r3 as s3  # noqa: E402

PAL = h2.PAL
SH = (31, -1, 223)
EL = (43, -1, 191)
WR = (42, -1, 158)
NAMES = {"a": "a 그림 그대로", "b": "b 아래팔·위팔 더 굵게"}


def build_arm(M, var="a"):
    t = 2 if var == "b" else 0                      # 위팔 앞뒤 추가 두께
    fo = 3 if var == "b" else 0                     # 아래팔 바깥 추가 폭
    # ---- 위팔
    U = M.part("UpperArmL", (28, -16, 194), (58, 14, 224), pivot=SH, parent="Torso")
    G = U.g(); X, Y, Z = G
    U.add(cbox(G, (33, 53), (-10 - t, 9 + t), (197, 222), {"xy": 3, "-zx": 2}), 1)
    U.emboss((X >= 36) & (X <= 50) & (Z >= 199) & (Z <= 212) & (Y < -4), 1)               # 앞 덧판 1칸
    U.trim()
    # ---- 아래팔 + 팔꿈치
    Lw = M.part("LowerArmL", (26, -18, 160), (62, 14, 198), pivot=EL, parent="UpperArmL")
    G = Lw.g(); X, Y, Z = G
    Lw.add(cyl(G, "x", (EL[1], EL[2]), 5.5, rng=(33, 55)), 3)                                # 팔꿈치 경첩
    for x0 in (38, 44, 50):
        Lw.groove(cyl(G, "x", (EL[1], EL[2]), 6) & ~cyl(G, "x", (EL[1], EL[2]), 4.5) & (X == x0), 4)
    for xa, xb in ((30, 32), (56, 57)):                                                      # A2b 끝 원반(강철 테)
        Lw.add(cyl(G, "x", (EL[1], EL[2]), 4.5, rng=(xa, xb)), 2)
        Lw.add(cyl(G, "x", (EL[1], EL[2]), 2.0, rng=(xa - 1 if xa < 40 else xb, xa - 1 if xa < 40 else xb + 1)), 7)
    fr = [(30, 186), (52 + fo, 186), (52 + fo, 173), (48 + fo, 163), (35, 163), (32, 172)]
    fa = poly(G, "y", fr) & (Y <= 10) & (Y >= -12 + np.clip(184 - Z, 0, None) * 0.25)
    fa &= cbox(G, (29, 53 + fo), (-12, 10), (162, 187), {"xy": 3, "+z-y": 2})
    Lw.add(fa, 1)
    Lw.emboss((X >= 34) & (X <= 48 + fo) & (Z >= 167) & (Z <= 183) & (Y < -6), 1)            # 앞 비스듬한 덧판
    Lw.trim()
    # ---- 손목 + 주먹
    Hd = M.part("HandL", (26, -16, 128), (58, 14, 166), pivot=WR, parent="LowerArmL")
    G = Hd.g(); X, Y, Z = G
    Hd.add(cyl(G, "z", (WR[0], WR[1]), 7, rng=(151, 164)), 3)
    for z0 in (154, 157, 160):
        Hd.groove(cyl(G, "z", (WR[0], WR[1]), 7.5) & ~cyl(G, "z", (WR[0], WR[1]), 6) & (Z == z0), 4)
    fist = cbox(G, (32, 52), (-10, 9), (131, 152), {"xy": 3, "-zy": 3, "-zx": 2, "+zx": 2})
    Hd.add(fist, 2)
    Hd.groove((Z == 145) & (Y <= -8) & (X >= 34) & (X <= 50), 4)                             # 손등 / 손가락 경계
    for x0 in (38, 42, 46):
        Hd.groove((X == x0) & (Y <= -8) & (Z <= 144) & (Z >= 133), 4)                         # 손가락 4
    # (1차: 손가락 마디 가로 홈까지 넣었더니 정면에서 井 격자처럼 보여 뺌)
    Hd.cut((Y <= -9) & (Z <= 133))                                                            # 손가락 끝이 안으로 말림(아래 앞 모서리 한 칸 더)
    Hd.add(cbox(G, (29, 33), (-9, -2), (137, 148), {"xz": 1}), 2)                             # 엄지(안쪽)
    Hd.groove((X == 30) & (Y >= -8) & (Y <= -3) & (Z == 142), 4)
    Hd.emboss((X >= 52) & (Z >= 136) & (Z <= 149) & (np.abs(Y + 0.5) <= 6), 3)                 # 손 바깥 덧판(짙은)
    Hd.trim()
    for n in ("UpperArmL", "LowerArmL", "HandL"):
        M.mirror(n, n[:-1] + "R")
    return M


def build_all(var="a", ws=0.88):
    M = s3.build_all(ws)
    build_arm(M, var)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    Rr = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(Rr, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(Rr, "concept_v1_메인.png")).convert("RGB")
    raise_ = {"UpperArmL": rotx(-60), "UpperArmR": rotx(-60), "LowerArmL": rotx(-30), "LowerArmR": rotx(-30)}
    side_ = {"UpperArmL": roty(-35), "UpperArmR": roty(35)}
    specs = [(0, 2, "정면", None), (-35, 8, "앞 3/4", None), (-90, 2, "옆", None), (150, 10, "뒤 3/4", None),
             (-35, 8, "팔 앞으로 60° (겹침 검사)", raise_), (0, 2, "팔 옆으로 35°", side_)]
    rows = [(NAMES[v], build_all(v)) for v in "ab"]
    rend = []
    for nm, M in rows:
        for pn in ("UpperArmL", "LowerArmL", "HandL"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(pose=ps), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=2.8, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _, ps in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((0, 20, 580, 560)), "컨셉 정면"), (mn.crop((100, 40, 1000, 1000)), "컨셉 메인"),
            (con.crop((590, 20, 930, 560)), "컨셉 옆"), (con.crop((980, 20, 1510, 560)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(200 + sum(cols) + 16 * 7, 200 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 팔 r1 — 위팔 · 경첩 팔꿈치(끝 원반) · 굵은 아래팔 · 손목 마디 · 반쯤 쥔 주먹 (하체 전)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 200
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_팔r1.png"); sh.save(p); print(p, sh.size)
