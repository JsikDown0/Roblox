"""양산형 하체 r2 (2026-11-03) — 유저 r1 평: "골반이 너무 넓고, 다리도 곧지 못하고 삐뚤빼뚤. 전반적으로 조악 → 리메이크, 방향 여러 개".

[판단] r1 원인
  ① 골반 옆 장갑이 |X| 14~39 → 허리(±14)보다 훨씬 넓은 판이 골반에 붙어 하체 위가 넓은 상자.
  ② 부위마다 정면 그림 윤곽을 따로 따서 중심이 제각각(허벅지 X 24.5 · 무릎판 32.6 · 정강이 30 · 발 35) → 다리가 지그재그.
     그림 윤곽 자체도 손그림이라 울퉁불퉁(정강이 안쪽 235 → 240 → 225).
  ③ 상자 + 그림 다각형을 섞어 면 문법(45° 모따기 · 2단 판 · 처마)이 머리·가슴·팔과 다름.
r2: FELSEN 다리(final_m2b) 문법 — 다리 축 하나(X 22, 곧게)에 모든 부위를 같은 중심으로 쌓음 · 모서리 45° 모따기 · 앞 2단 판 ·
    무릎판이 정강이 위를 덮는 처마 · 그림에선 부품 구성·색·비율만(윤곽 다각형은 쓰지 않음).
  공통 부품(r4 읽기 답): 좁은 골반(짙은 뼈대 ±18 + 샅판 ±11 · 둥근 구멍, 고리 없음) · 허벅지 장갑 + 앞 데칼 판 ·
    무릎 = 양옆 둥근 너클(다리 폭 안) + 뒷면 직사각 블록 · 짙은 쇠 회색 무릎판(육각, 2단) · 정강이 앞 피스톤 홈 · 종아리 뒤 격자 ·
    발목 짙은 기계부 · 발 한 덩어리(발끝 짙은 덮개 + 가운데 홈 · 뒤꿈치 블록 = 데칼 면).
  A  기둥형     곧은 다리, 정강이 아래로 조금 벌어짐(컨셉 비율)
  B  육중 정강이  허벅지 조금 좁게 + 정강이가 종 모양으로 크게 벌어지고 종아리 뒤로(무게가 아래)
  C  A자 벌림   A 를 고관절에서 4° 벌림(발은 바닥에 평평하게 되돌림) — 컨셉 정면의 벌린 자세
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, ell, roty, rotx  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_arm_r2 as a2  # noqa: E402

PAL = h2.PAL
CX = 22                                                           # 다리 축(곧게)
HIP, KNEE, ANK = (CX, 0, 155), (CX, -1, 108), (CX, 0, 40)
NAMES = {"A": "A 기둥형", "B": "B 육중 정강이", "C": "C A자 벌림(4°)"}
SPEC = {"A": dict(tw=15, k=0.05, kb=0.10, kf=0.03, ft=1.0, splay=0),
        "B": dict(tw=13, k=0.12, kb=0.20, kf=0.08, ft=1.12, splay=0),
        "C": dict(tw=15, k=0.05, kb=0.10, kf=0.03, ft=1.0, splay=4)}
ARM_SPLAY = {"UpperArmL": roty(-9), "UpperArmR": roty(9)}


def build_pelvis(M):
    P = M.part("Pelvis", (-24, -18, 140), (25, 16, 178), pivot=(0, 0, 160))
    G = P.g(); X, Y, Z = G; ax = np.abs(X)
    P.add(cbox(G, (-18, 18), (-10, 11), (146, 175), {"xy": 3, "-zx": 4}), 3)                   # 짙은 골반 뼈대
    cr = cbox(G, (-11, 11), (-15, -8), (148, 174), {"-zx": (6, 10), "x-y": 2, "-z-y": (3, 4)})
    P.add(cr, 1)                                                                              # 샅판(아래 좁아지는 육각)
    P.emboss((ax <= 8) & (Z >= 153) & (Z <= 171) & (Y < -13), 1)                               # 2단 판
    P.groove(cyl(G, "y", (0, 163), 3.2) & (Y <= -13), 4)                                       # 둥근 구멍
    P.add(cbox(G, (-14, 14), (9, 14), (150, 172), {"x+y": 3}), 3)                             # 뒤 판(짙은)
    P.trim()
    M.parts["Torso"].parent = "Pelvis"


def build_leg(M, v):
    sp = SPEC[v]; tw = sp["tw"]
    # ---- 허벅지
    U = M.part("UpperLegL", (0, -22, 108), (44, 20, 168), pivot=HIP, parent="Pelvis")
    G = U.g(); X, Y, Z = G
    U.add(ell(G, HIP, (10, 10, 10)), 3)                                                        # 고관절 공(장갑 속)
    U.add(cbox(G, (CX - 10, CX + 10), (-10, 10), (112, 150), {"xy": 3}), 3)                    # 짙은 뼈대
    U.add(cbox(G, (CX - tw, CX + tw), (-15, 15), (121, 153), {"xy": 4, "+zx": 3, "+zy": 3, "-z-y": 3}), 1)
    U.add(cbox(G, (CX - tw + 4, CX + tw - 4), (-17, -15), (126, 149), {"x-y": 2, "-z-y": 2}), 1)   # 앞 데칼 판(2단)
    U.add(cbox(G, (CX - tw + 5, CX + tw - 5), (15, 17), (126, 147), {"x+y": 2}), 2)             # 뒤 판(짙은 쇠)
    U.rot = roty(-sp["splay"])
    U.trim()
    # ---- 정강이 + 무릎
    L = M.part("LowerLegL", (-6, -30, 28), (52, 32, 128), pivot=KNEE, parent="UpperLegL")
    G = L.g(); X, Y, Z = G
    ky, kz = KNEE[1], KNEE[2]
    for xa, xb in ((CX - 14, CX - 10), (CX + 10, CX + 14)):                                    # 둥근 너클(다리 폭 안, 옆에서 크게)
        L.add(cyl(G, "x", (ky, kz), 8, rng=(xa, xb)), 3)
        xe = xa if xa < CX else xb
        L.groove(cyl(G, "x", (ky, kz), 8.5) & ~cyl(G, "x", (ky, kz), 5.5) & (X == xe), 4)
        L.paint(cyl(G, "x", (ky, kz), 2.5) & (X == xe), 2)
    L.add(cyl(G, "x", (ky, kz), 4, rng=(CX - 10, CX + 10)), 4)
    L.add(cbox(G, (CX - 7, CX + 7), (4, 12), (99, 118), {"+yz": 2}), 3)                       # 뒷면 직사각 블록
    for z0 in (104, 109, 114):
        L.groove((np.abs(X - CX) <= 6) & (Y == 12) & (Z == z0), 4)
    # 정강이: 곧은 축, 아래로 벌어짐(k) · 종아리 뒤로(kb) · 앞 아래로(kf)
    d = np.clip(96 - Z, 0, None)
    w = 14 + d * sp["k"]; yf = -13 - d * sp["kf"]; yb = 11 + d * sp["kb"]
    ax_ = np.abs(X - CX)
    sh = (ax_ <= w) & (Y >= yf) & (Y <= yb) & (Z >= 46) & (Z <= 97)
    sh &= ((w - ax_) + (Y - yf) >= 4) & ((w - ax_) + (yb - Y) >= 4)                            # 세로 모서리 45°
    sh &= (Z <= 97 - np.clip(ax_ - (w - 4), 0, None))                                          # 위 옆 모서리
    L.add(sh, 1)
    L.add(cbox(G, (CX - 12, CX + 12), (-11, 10), (90, 100), {"xy": 3}), 3)                     # 무릎 밑 짙은 이음
    # 무릎판(짙은 쇠 회색 육각, 정강이 위를 덮는 처마)
    kp = cbox(G, (CX - 12, CX + 12), (-21, -10), (90, 124), {"xz": 7, "x-y": 3, "+z-y": 4, "-z-y": 3})
    L.add(kp, 2)
    L.emboss((np.abs(X - CX) <= 8 - np.clip(np.abs(Z - 107) - 9, 0, None)) & (Z >= 94) & (Z <= 120) & (Y < -20), 2)
    # 앞 피스톤 홈
    ch = (ax_ <= 4) & (Z >= 58) & (Z <= 89)
    L.cut(ch & (Y < yf + 3))
    L.add(ch & (np.abs(Y - (yf + 3)) <= 0.5), 3)
    py = -13 - 74 * sp["kf"] * 0 + 1.5
    L.add(cyl(G, "z", (CX, -11.5), 2.3, rng=(60, 89)), 7)
    L.add(cyl(G, "z", (CX, -11.5), 3.0, rng=(78, 89)), 2)
    L.add(cyl(G, "z", (CX, -11.5), 2.8, rng=(72, 73)), 5)
    # 종아리 뒤 격자
    gr = (ax_ <= 5) & (Z >= 62) & (Z <= 86)
    L.cut(gr & (Y > yb - 2))
    L.add(gr & (np.abs(Y - (yb - 2)) <= 0.5), 4)
    for z0 in range(63, 86, 3):
        L.add(gr & (Z == z0) & (np.abs(Y - (yb - 1)) <= 0.5), 3)
    # 발목: 정강이 끝 테(짙은) + 짙은 기계부
    L.paint_s((Z >= 46) & (Z <= 48), 3)
    L.add(cbox(G, (CX - 9, CX + 9), (-8, 9), (32, 47), {"xy": 3}), 3)
    L.trim()
    # ---- 발
    s_ = sp["ft"]
    F = M.part("FootL", (-2, -50, 0), (46, 40, 36), pivot=ANK, parent="LowerLegL")
    G = F.g(); X, Y, Z = G
    fw = round(14 * s_)
    prof = [(-38 * s_, 3), (-38 * s_, 9), (-30 * s_, 16), (-14, 21), (-8, 29), (12, 29), (20, 22), (27 * s_, 14), (27 * s_, 3)]
    from flag_vox import poly
    F.add(poly(G, "x", prof) & cbox(G, (CX - fw, CX + fw), (-40, 32), (0, 30), {"x-y": 5, "x+y": 3, "+zx": 3}), 1)
    F.add(cbox(G, (CX - fw - 1, CX + fw + 1), (round(-40 * s_), round(29 * s_)), (0, 3), {"xy": 4}), 3)   # 발바닥(짙은)
    F.add(cbox(G, (CX - fw + 1, CX + fw - 1), (round(-41 * s_), round(-31 * s_)), (2, 12), {"-y+z": 4, "x-y": 4}), 2)   # 발끝 덮개
    F.groove((X == CX) & (Y <= -20) & (Z >= 3), 4)                                              # 가운데 홈
    F.add(cbox(G, (CX - fw + 2, CX + fw - 2), (round(22 * s_), round(31 * s_)), (2, 16), {"+y+z": 4, "x+y": 3}), 1)   # 뒤꿈치(데칼 면)
    F.rot = roty(sp["splay"])
    F.trim()
    for n in ("UpperLegL", "LowerLegL", "FootL"):
        M.mirror(n, n[:-1] + "R")
    return M


def build_all(v="A", ws=0.88):
    M = a2.build_all("f", ws)
    build_pelvis(M)
    build_leg(M, v)
    return M


def overlaps(M, pose=None):
    def cells(n):
        p = M.parts[n]; T = M.world(n, pose); ijk = np.argwhere(p.a > 0) + p.lo
        return set(map(tuple, np.round(ijk @ T[:3, :3].T + T[:3, 3]).astype(int)))
    legs = cells("UpperLegL") | cells("LowerLegL")
    return {"손∩다리": len(cells("HandL") & legs), "아래팔∩다리": len(cells("LowerArmL") & legs),
            "정강이∩허벅지": len(cells("LowerLegL") & cells("UpperLegL")), "좌∩우 다리": len((cells("UpperLegL") | cells("LowerLegL") | cells("FootL")) & (cells("UpperLegR") | cells("LowerLegR") | cells("FootR")))}


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
    walk = dict(ARM_SPLAY, UpperLegL=rotx(-25), LowerLegL=rotx(30), UpperLegR=rotx(20), LowerLegR=rotx(10))
    specs = [(0, 2, "정면", ARM_SPLAY), (-35, 8, "앞 3/4", ARM_SPLAY), (-90, 2, "옆", ARM_SPLAY), (150, 10, "뒤 3/4", ARM_SPLAY),
             (-90, 2, "걷기 자세(겹침 확인)", walk)]
    rend = []
    for v in "ABC":
        M = build_all(v)
        for pn in ("Pelvis", "UpperLegL", "LowerLegL", "FootL"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(v, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        print(v, "겹침", overlaps(M, ARM_SPLAY), "걷기", overlaps(M, walk))
        ims = [vp.render(M.blocks(pose=ps), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=1.9, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _, ps in specs]
        rend.append((NAMES[v], ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((0, 20, 560, 935)), "컨셉 정면"), (mn.crop((60, 0, 1000, 1536)), "컨셉 메인"),
            (con.crop((580, 20, 920, 935)), "컨셉 옆"), (con.crop((980, 20, 1510, 935)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(200 + sum(cols) + 16 * 6, 200 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 하체 r2 — 리메이크: 다리 축 하나(곧게) · 좁은 골반 · FELSEN 다리 문법(45° 모따기 · 2단 판 · 무릎판 처마)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 200
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_하체r2_리메이크.png"); sh.save(p); print(p, sh.size)
