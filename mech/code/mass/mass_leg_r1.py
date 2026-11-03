"""양산형 하체 r1 (2026-11-03) — 윤곽 읽기 r4 답 [결정 11-03]:
  ① 무릎 = 2축 경첩이되 이번엔 **둥근 너클이 주로 보이고**, 직사각 블록은 **뒷면에서만** 보임 ② 정강이 앞 피스톤(홈 속) ③ 종아리 뒤 통풍 격자
  ④ 발 = 한 덩어리 + 가운데 홈 · 길이 그림대로 ⑤ 샅 아래 고리 = 뺌 ⑥ 다리 폭 ×1.0.
왼다리(+X)를 만들고 거울. 정면 그림(기체 오른다리 = 그림 왼쪽) → X = (273 − x) × 0.295 · z = (925 − y) × 0.295.
옆 그림은 원근이 있어 다리 축(x≈760)을 Y 0 으로 두고 상대 길이만 씀.
[읽기 → 칸]
  P1 샅판 x228~322 → |X| ≤ 14, z175~149, 가운데 둥근 구멍 · H 골반 옆 장갑 x140~225 → X 14~39, z159~176
  T 허벅지 장갑 x135~245 → X 8~41, z125~159 · 앞 판 T1 = 데칼 면(평평)
  K 무릎판 x120~205 → X 20~45, z93~126, 짙은 쇠 회색 육각 · 무릎 축 z110
  S 정강이 x100~240 → 위 X 11~48 / 아래 X 10~51, z49~93, 뒤로 벌어진 종아리 · S1 앞 피스톤 홈(X 30~39) · S2 뒤 격자
  A 발목 z37~49 · F 발 X 17~52, 옆 길이 77(발끝 −43 ~ 뒤꿈치 +34), z0~37
파트: Pelvis(뿌리, Torso 의 부모) · UpperLegL(피벗 고관절 (24,0,155)) · LowerLegL(피벗 무릎 (32,0,110)) · FootL(피벗 발목 (33,0,43)) → 거울.
  a  너클 바깥 면이 다리 폭과 같음      b  너클 2칸 더 바깥으로(더 도드라짐)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, poly, roty  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_arm_r2 as a2  # noqa: E402

PAL = h2.PAL
K = 0.295
FX = lambda x: (273 - x) * K
FZ = lambda y: (925 - y) * K
HIP, KNEE, ANK = (24, 0, 155), (32, 0, 110), (33, 0, 43)
NAMES = {"a": "a 너클 = 다리 폭", "b": "b 너클 2칸 더 바깥"}
ARM_SPLAY = {"UpperArmL": roty(-9), "UpperArmR": roty(9)}       # 쉬는 자세 팔 벌림(주먹이 허벅지에 닿지 않게) [판단]


def build_pelvis(M):
    P = M.part("Pelvis", (-42, -20, 140), (43, 20, 180), pivot=(0, 0, 160))
    G = P.g(); X, Y, Z = G; ax = np.abs(X)
    P.add(cbox(G, (-18, 18), (-10, 11), (148, 174), {"xy": 3}), 3)                            # 짙은 골반 뼈대
    sp = [(FX(x), FZ(y)) for x, y in ((273, 330), (228, 330), (220, 395), (250, 420), (273, 420))]
    sp = [(abs(a), b) for a, b in sp]
    crotch = poly(G, "y", sp + [(-a, b) for a, b in sp[::-1]]) & (Y >= -14) & (Y <= -6)
    crotch &= (Y >= -14 + np.clip(160 - Z, 0, None) * 0.3)                                     # 아래가 뒤로
    P.add(crotch, 1)
    P.groove(cyl(G, "y", (0, 165), 3.2) & (Y <= -10), 4)                                       # 가운데 둥근 구멍
    for s in (1, -1):
        hp = cbox(G, sorted((s * 14, s * 39)), (-12, 11), (159, 176), {"+z-y": 3, "xy": 3})
        hp &= (s * X <= 39 - np.clip(165 - Z, 0, None) * 0.6)                                  # 바깥 아래 모서리 깎음
        P.add(hp, 1)
        P.add(cyl(G, "x", (0, 155), 6, rng=sorted((s * 14, s * 20))), 3)                      # 고관절 축(장갑 속)
    P.trim()
    M.parts["Torso"].parent = "Pelvis"


def build_leg(M, var="a"):
    out_k = 2 if var == "b" else 0
    # ---- 허벅지
    U = M.part("UpperLegL", (4, -22, 112), (48, 24, 160), pivot=HIP, parent="Pelvis")
    G = U.g(); X, Y, Z = G
    U.add(cbox(G, (14, 34), (-8, 10), (114, 154), {"xy": 3}), 3)                               # 짙은 허벅지 뼈대
    U.add(cbox(G, (8, 41), (-17, 19), (125, 158), {"xy": 4, "-zy": 3, "+zx": 2}), 1)          # 허벅지 장갑
    U.emboss((X >= 12) & (X <= 37) & (Z >= 130) & (Z <= 152) & (Y < -12), 1)                   # 앞 판 T1(데칼 면)
    U.trim()
    # ---- 정강이 + 무릎
    L = M.part("LowerLegL", (0, -26, 28), (60, 30, 128), pivot=KNEE, parent="UpperLegL")
    G = L.g(); X, Y, Z = G
    for xa, xb in ((17, 21), (43, 47 + out_k)):                                                # 둥근 너클(양옆, 크게 보임)
        xa2 = xa if xa < 30 else xa
        L.add(cyl(G, "x", (KNEE[1], KNEE[2]), 9, rng=(xa2, xb)), 3)
        L.groove(cyl(G, "x", (KNEE[1], KNEE[2]), 9.5) & ~cyl(G, "x", (KNEE[1], KNEE[2]), 6.5) & (X == (xa if xa < 30 else xb)), 4)
        L.paint(cyl(G, "x", (KNEE[1], KNEE[2]), 3) & (X == (xa if xa < 30 else xb)), 2)
    L.add(cyl(G, "x", (KNEE[1], KNEE[2]), 5, rng=(21, 43)), 4)                                # 축
    L.add(cbox(G, (24, 40), (3, 13), (100, 120), {"+yz": 2}), 3)                              # 뒷면 직사각 블록(뒤에서만 보임)
    for z0 in (104, 110, 116):
        L.groove((X >= 25) & (X <= 39) & (Y == 13) & (Z == z0), 4)
    # 무릎판: 짙은 쇠 회색 육각, 앞(Y −20 ~ −8)
    kp = [(FX(x), FZ(y)) for x, y in ((120, 500), (195, 495), (205, 545), (195, 610), (120, 610), (112, 560))]
    L.add(poly(G, "y", kp) & (Y >= -20) & (Y <= -8) & (Y >= -20 + np.clip(Z - 120, 0, None) * 0.5), 2)
    L.emboss(poly(G, "y", [(a - np.sign(a - 32) * 3, b) for a, b in kp]) & (Y < -18), 2)         # 2단 판
    # 정강이: 아래로 벌어지고 종아리 뒤로 불룩
    sp = [(FX(x), FZ(y)) for x, y in ((110, 610), (235, 610), (240, 700), (225, 760), (100, 760), (100, 680))]
    yb = 13 + np.clip(95 - Z, 0, None) * 0.25
    yf = -15 - np.clip(80 - Z, 0, None) * 0.08
    sh = poly(G, "y", sp) & (Y >= yf) & (Y <= yb) & (Z <= 96)
    sh &= cbox(G, (8, 53), (-20, 25), (48, 97), {"xy": 4, "+z+y": 4})
    L.add(sh, 1)
    # S1 앞 피스톤 홈 + 피스톤
    L.cut((X >= 30) & (X <= 39) & (Z >= 62) & (Z <= 92) & (Y <= yf + 3))
    L.add((X >= 30) & (X <= 39) & (Z >= 62) & (Z <= 92) & (np.abs(Y - (yf + 4)) <= 0.5), 3)
    L.add(cyl(G, "z", (34.5, -14), 2.6, rng=(64, 92)), 7)
    L.add(cyl(G, "z", (34.5, -14), 3.4, rng=(80, 92)), 2)
    L.add(cyl(G, "z", (34.5, -14), 3.0, rng=(76, 77)), 5)
    # S2 뒤 세로 통풍 격자
    L.cut((X >= 24) & (X <= 35) & (Z >= 66) & (Z <= 88) & (Y >= yb - 1))
    L.add((X >= 24) & (X <= 35) & (Z >= 66) & (Z <= 88) & (np.abs(Y - (yb - 2)) <= 0.5), 4)
    for z0 in range(67, 88, 3):
        L.add((X >= 24) & (X <= 35) & (Z == z0) & (np.abs(Y - (yb - 1)) <= 0.5), 3)
    # 발목 띠 + 짙은 기계부
    L.add(cbox(G, (12, 50), (-16, 18), (45, 50), {"xy": 3}), 1)
    L.add(cbox(G, (20, 44), (-8, 10), (30, 46), {"xy": 2}), 3)                                # 짙은 발목 기계부(발등 위로 보임)
    L.trim()
    # ---- 발
    F = M.part("FootL", (10, -48, 0), (58, 40, 44), pivot=ANK, parent="LowerLegL")
    G = F.g(); X, Y, Z = G
    # 1차는 발등이 z37 로 평평해 큰 장화 덩어리처럼 보임 → 발끝은 낮게(z≤20) 발목 쪽만 높게, 45°·1:2 경사
    side = [(-40, 0), (-40, 7), (-33, 14), (-20, 20), (-10, 31), (14, 31), (26, 20), (32, 12), (32, 0)]
    ft = poly(G, "x", side) & cbox(G, (19, 50), (-41, 33), (0, 32), {"xy": 4, "+zx": 3})
    F.add(ft, 1)
    F.paint((Z <= 4), 3)                                                                       # 발바닥 테(짙은)
    F.add(cbox(G, (20, 49), (-43, -34), (0, 10), {"-y+z": 3, "xy": 2}), 2)                     # 발끝 짙은 쇠 덮개
    F.groove((X == 34) & (Y <= -20) & (Z >= 2), 4)                                             # 발끝 가운데 홈(한 덩어리)
    F.add(cbox(G, (21, 48), (24, 34), (0, 16), {"+y+z": 3, "xy": 2}), 1)                      # 뒤꿈치 블록(H2 데칼 면)
    F.trim()
    for n in ("UpperLegL", "LowerLegL", "FootL"):
        M.mirror(n, n[:-1] + "R")
    return M


def build_all(var="a", ws=0.88):
    M = a2.build_all("f", ws)
    build_pelvis(M)
    build_leg(M, var)
    return M


def overlaps(M, pose=None):
    def cells(n):
        p = M.parts[n]; T = M.world(n, pose); ijk = np.argwhere(p.a > 0) + p.lo
        return set(map(tuple, np.round(ijk @ T[:3, :3].T + T[:3, 3]).astype(int)))
    body = set().union(*(cells(n) for n in ("Torso", "Pelvis")))
    out = {}
    for n in ("UpperLegL", "LowerLegL", "FootL", "HandL", "LowerArmL"):
        others = body if not n.startswith(("Hand", "LowerArm")) else cells("UpperLegL") | cells("LowerLegL")
        out[n] = len(cells(n) & others)
    return out


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
    specs = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-90, 2, "옆"), (150, 10, "뒤 3/4"), (180, 2, "뒤")]
    rows = [(NAMES[v], build_all(v)) for v in "ab"]
    rend = []
    for nm, M in rows:
        for pn in ("Pelvis", "UpperLegL", "LowerLegL", "FootL"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        print(nm, "겹침(쉬는 자세, 팔 9° 벌림)", overlaps(M, ARM_SPLAY), "팔 안 벌림", overlaps(M))
        ims = [vp.render(M.blocks(pose=ARM_SPLAY), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=1.9, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((0, 20, 560, 935)), "컨셉 정면"), (mn.crop((60, 0, 1000, 1536)), "컨셉 메인"),
            (con.crop((580, 20, 920, 935)), "컨셉 옆"), (con.crop((980, 20, 1510, 935)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(200 + sum(cols) + 16 * 6, 200 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 하체 r1 — 전신 (머리 A · 가슴 r4a · 어깨 r3 · 팔 f · 하체 r1)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 200
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_하체r1.png"); sh.save(p); print(p, sh.size)
