"""양산형 팔 r2 (2026-11-03) — 유저 "관절부가 너무 크고 도드라져. 형태도 다르고. SD 캐릭터에 어울리는 건담 앙상블식 관절"(사진 첨부).

[판단] r1 원인: 팔꿈치 원통(r5.5, X 33~55)+끝 원반(X 30·57)이 팔 폭(33~53) 밖으로 나옴 + 위팔/아래팔 사이 10칸 짙은 띠가 그대로 드러남 +
  손목 원통 r7 마디 띠가 아래팔만큼 굵음 + 어깨 관절 원통 r11 → 굵은 짙은 고리가 3단으로 쌓여 장난감(앙상블) 관절처럼 읽힘.
  스타일 가이드 1-4 "관절은 다리·팔 폭 안에서 끝낸다 · 옆으로 튀어나온 원판 허브는 종양처럼 보인다" 위반.
r2: 관절을 장갑 속에 숨김 — 위팔 장갑을 z190 까지 내려 팔꿈치 뒤·옆을 덮고, 아래팔 위 끝(z193)이 앞에서 겹쳐 올라감.
  팔꿈치 원통 r4 · X 36~50(폭 안) · 끝 원반 없앰 → 옆에서 얇은 짙은 틈만. 손목 = 아래팔 끝 소매(z156 까지)가 덮고 r5 짧게.
  어깨 관절 원통 r11 → r8(어깨 장갑 밑으로 숨음). 주먹 조금 작게(X 34~51, z134~151).
  1차 렌더 [관찰]: c·d 는 반대로 관절이 아예 안 보여 위팔·아래팔이 한 기둥(소시지)처럼 읽힘.
  → e  중간: 관절이 보이되 팔 폭보다 2칸 안쪽으로 들어간 짙은 기계부(높이 6, 경첩 2마디 + 가운데 피스톤 막대) ·
       위팔 상자 끝 z196 / 아래팔 상자 시작 z189 · 아래팔이 위팔보다 앞뒤·바깥 2칸 굵음(단차로 따로 읽힘) · 손목 짙은 띠 3칸, 2칸 안쪽.
  유저 e 평: "e 가 좋은데, 동그란 관절 연결부 외에도 직사각형 형태의 관절부가 같이 융합돼 있어" → [관찰: 메인·삼면도 팔꿈치 확대]
     2축 경첩 — 위 축(위팔 끝) + 아래 축(아래팔 끝), 양옆 둥근 축 끝(너클) + 가운데 직사각 연결 블록 + 그 양옆 얇은 강철 테 링크판.
  f  e + 2축 경첩(위 축 z195 · 아래 축 z188, 둥근 너클 4 + 가운데 직사각 블록 + 강철 링크판 2), 모두 팔 폭 안
  c  관절 숨김(그림)      d  c + 팔꿈치 바깥 덧판(위팔에서 내려온 짧은 팔꿈치 보호대 — 관절 바깥을 판으로)
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
import mass_shoulder_r1 as s1  # noqa: E402
import mass_shoulder_r3 as s3  # noqa: E402
import mass_arm_r1 as a1  # noqa: E402

PAL = h2.PAL
SH, EL, WR = (31, -1, 223), (43, -1, 191), (42, -1, 155)
NAMES = {"c": "c 관절 숨김", "d": "d c + 팔꿈치 바깥 덧판", "e": "e 안쪽으로 들어간 작은 관절", "f": "f e + 2축 경첩(직사각 블록)"}


def small_shoulder_joint(M):
    """어깨 관절 원통 r11 → r8."""
    for n, s in (("ShoulderL", 1), ("ShoulderR", -1)):
        P = M.parts[n]; G = P.g(); X, Y, Z = G
        old = cyl(G, "x", (SH[1], SH[2]), 11.6, rng=sorted((s * 28, s * 36))) & (P.a >= 3) & (P.a != 1)
        P.a[np.broadcast_to(old, P.a.shape) & (P.a != 2) | (np.broadcast_to(old, P.a.shape) & (P.a == 2) & np.broadcast_to(s * X >= 35, P.a.shape))] = 0
        P.add(cyl(G, "x", (SH[1], SH[2]), 8, rng=sorted((s * 28, s * 35))), 3)
        P.add(box(G, x=sorted((s * 29, s * 34)), y=(-5, 4), z=(229, 234)) & ~(P.a > 0), 3)       # 관절 ↔ 캡 이음(작아진 관절이 캡과 떨어지지 않게)


def build_arm(M, var="c"):
    U = M.part("UpperArmL", (28, -16, 186), (58, 14, 224), pivot=SH, parent="Torso")
    G = U.g(); X, Y, Z = G
    U.add(cbox(G, (33, 53), (-10, 9), (190, 222), {"xy": 3, "-zx": 2, "-z-y": 4}), 1)       # 아래 앞 모서리 크게 깎음 → 아래팔이 앞으로 올라올 자리
    U.emboss((X >= 36) & (X <= 50) & (Z >= 199) & (Z <= 212) & (Y < -4), 1)
    if var == "d":
        U.add(cbox(G, (51, 55), (-8, 8), (184, 200), {"+xz": 2, "-z+x": 2}), 1)             # 팔꿈치 바깥 보호대
    U.trim()
    Lw = M.part("LowerArmL", (26, -18, 150), (62, 14, 198), pivot=EL, parent="UpperArmL")
    G = Lw.g(); X, Y, Z = G
    Lw.add(cyl(G, "x", (EL[1], EL[2]), 4, rng=(36, 50)), 3)                                  # 팔꿈치(폭 안, 숨김)
    fr = [(31, 193), (52, 193), (52, 173), (48, 156), (35, 156), (32, 172)]                   # 위 끝 z193(앞에서 겹침) · 아래 소매 z156
    fa = poly(G, "y", fr) & (Y <= 9) & (Y >= -12 + np.clip(184 - Z, 0, None) * 0.25)
    fa &= cbox(G, (30, 53), (-12, 9), (155, 194), {"xy": 3, "+z-y": 3})
    fa &= ~((Y > -3) & (Z > 186))                                                             # 위 끝 뒤쪽은 비움(위팔 장갑 속 경첩 자리)
    Lw.add(fa, 1)
    Lw.emboss((X >= 34) & (X <= 48) & (Z >= 167) & (Z <= 186) & (Y < -6), 1)
    Lw.paint_s((Z <= 158) & (Z >= 156), 3)                                                    # 소매 끝 짙은 테
    Lw.trim()
    Hd = M.part("HandL", (28, -16, 130), (58, 14, 158), pivot=WR, parent="LowerArmL")
    G = Hd.g(); X, Y, Z = G
    Hd.add(cyl(G, "z", (WR[0], WR[1]), 5, rng=(150, 156)), 3)                                # 손목(소매 속)
    Hd.add(cbox(G, (34, 51), (-9, 8), (134, 151), {"xy": 3, "-zy": 3, "-zx": 2, "+zx": 2}), 2)
    Hd.groove((Z == 145) & (Y <= -7) & (X >= 36) & (X <= 49), 4)
    for x0 in (39, 42, 46):
        Hd.groove((X == x0) & (Y <= -7) & (Z <= 144) & (Z >= 136), 4)
    Hd.cut((Y <= -8) & (Z <= 136))
    Hd.add(cbox(G, (31, 35), (-8, -2), (139, 148), {"xz": 1}), 2)
    Hd.emboss((X >= 51) & (Z >= 138) & (Z <= 148) & (np.abs(Y + 0.5) <= 5), 3)
    Hd.trim()
    for n in ("UpperArmL", "LowerArmL", "HandL"):
        M.mirror(n, n[:-1] + "R")
    return M


def build_arm_e(M, hinge2=False):
    U = M.part("UpperArmL", (28, -16, 186), (58, 14, 224), pivot=SH, parent="Torso")
    G = U.g(); X, Y, Z = G
    U.add(cbox(G, (34, 52), (-9, 8), (196, 222), {"xy": 3, "-zx": 2, "-zy": 2}), 1)
    U.emboss((X >= 37) & (X <= 49) & (Z >= 200) & (Z <= 212) & (Y < -4), 1)
    U.trim()
    Lw = M.part("LowerArmL", (26, -18, 150), (62, 16, 198), pivot=EL, parent="UpperArmL")
    G = Lw.g(); X, Y, Z = G
    if hinge2:
        # 1차(축 간격 7칸)는 납작한 띠처럼 보임 → 틈을 z184~197 로 넓히고 축을 앞뒤로 엇갈림(그림: 위 축 뒤, 아래 축 앞 — 대각선 링크)
        for (yc_, zc_) in ((1.5, 194), (-2.5, 187)):
            Lw.add(cyl(G, "x", (yc_, zc_), 2.5, rng=(36, 50)), 4)
            for xa, xb in ((36, 39), (47, 50)):                                              # 둥근 너클(양옆)
                Lw.add(cyl(G, "x", (yc_, zc_), 4.2, rng=(xa, xb)), 3)
                Lw.groove(cyl(G, "x", (yc_, zc_), 4.6) & ~cyl(G, "x", (yc_, zc_), 2.8) & (X == (xa if xa < 43 else xb)), 4)
        Lw.add(cbox(G, (40, 46), (-6, 4), (184, 197), {"yz": 2}), 3)                       # 가운데 직사각 연결 블록
        Lw.groove((X >= 41) & (X <= 45) & (Y == -6) & ((Z == 189) | (Z == 192)), 4)
        for x0 in (39, 47):                                                                  # 양옆 강철 테 링크판(위·아래 축을 잇는 비스듬한 판)
            Lw.add(r1.seg(G, (x0, 1.5, 194), (x0, -2.5, 187), 2.6) & (X == x0), 7)
    else:
        for xa, xb in ((37, 41), (45, 49)):                                                  # 경첩 2마디(폭 안, 2칸 안쪽)
            Lw.add(cyl(G, "x", (EL[1], EL[2]), 4, rng=(xa, xb)), 3)
        Lw.add(cyl(G, "x", (EL[1], EL[2]), 2.5, rng=(36, 50)), 4)                            # 축
    Lw.add(r1.seg(G, (43, 3, 196), (43, 3, 186), 1.6), 7)                                   # 뒤 피스톤 막대(강철)
    zt = 184 if hinge2 else 189
    fr = [(32, zt), (54, zt), (54, 173), (50, 158), (35, 158), (32, 172)]
    fa = poly(G, "y", fr) & (Y <= 10) & (Y >= -12 + np.clip(184 - Z, 0, None) * 0.25)
    fa &= cbox(G, (31, 55), (-12, 10), (157, zt + 1), {"xy": 3, "+z-y": 2, "+zy": 2})
    Lw.add(fa, 1)
    Lw.emboss((X >= 35) & (X <= 50) & (Z >= 167) & (Z <= zt - 4) & (Y < -6), 1)
    Lw.trim()
    Hd = M.part("HandL", (28, -16, 130), (58, 14, 160), pivot=WR, parent="LowerArmL")
    G = Hd.g(); X, Y, Z = G
    Hd.add(cyl(G, "z", (WR[0], WR[1]), 6, rng=(151, 158)), 3)                                # 손목 짙은 띠(아래팔보다 2칸 안쪽)
    Hd.groove(cyl(G, "z", (WR[0], WR[1]), 6.5) & ~cyl(G, "z", (WR[0], WR[1]), 5) & (Z == 154), 4)
    Hd.add(cbox(G, (34, 51), (-9, 8), (134, 151), {"xy": 3, "-zy": 3, "-zx": 2, "+zx": 2}), 2)
    Hd.groove((Z == 145) & (Y <= -7) & (X >= 36) & (X <= 49), 4)
    for x0 in (39, 42, 46):
        Hd.groove((X == x0) & (Y <= -7) & (Z <= 144) & (Z >= 136), 4)
    Hd.cut((Y <= -8) & (Z <= 136))
    Hd.add(cbox(G, (31, 35), (-8, -2), (139, 148), {"xz": 1}), 2)
    Hd.emboss((X >= 51) & (Z >= 138) & (Z <= 148) & (np.abs(Y + 0.5) <= 5), 3)
    Hd.trim()
    for n in ("UpperArmL", "LowerArmL", "HandL"):
        M.mirror(n, n[:-1] + "R")
    return M


def build_all(var="c", ws=0.88):
    if var in "ef":
        M = s3.build_all(ws)
        small_shoulder_joint(M)
        return build_arm_e(M, hinge2=(var == "f"))
    M = s3.build_all(ws)
    small_shoulder_joint(M)
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
    bend = {"LowerArmL": rotx(-40), "LowerArmR": rotx(-40)}
    specs = [(0, 2, "정면", None), (-35, 8, "앞 3/4", None), (-90, 2, "옆", None), (150, 10, "뒤 3/4", None), (-60, 6, "팔꿈치 40° 굽힘", bend)]
    if len(sys.argv) > 3:                                                                    # 팔꿈치 확대 보기
        specs = [(0, 2, "정면", None), (-35, 8, "앞 3/4", None), (-90, 2, "옆", None), (150, 10, "뒤 3/4", None), (-60, 6, "팔꿈치 40° 굽힘", bend)]
    sel = sys.argv[2] if len(sys.argv) > 2 else "cd"
    rows = [("r1 a (전)", a1.build_all("a"))] + [(NAMES[v], build_all(v)) for v in sel]
    rend = []
    for nm, M in rows:
        for pn in ("ShoulderL", "ShoulderR", "UpperArmL", "LowerArmL", "HandL"):
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
    W = max(220 + sum(cols) + 16 * 6, 220 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 팔 r2 — 관절을 장갑 속에(팔 폭 안 · 끝 원반 없음 · 위아래 장갑 겹침 · 손목은 소매 속 · 어깨 관절 r8)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 220
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_팔r2_관절_%s.png" % sel); sh.save(p); print(p, sh.size)
