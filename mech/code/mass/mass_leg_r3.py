"""양산형 하체 r3 (2026-11-03) — 무릎 아래 리메이크. 유저 r2b 평: "무릎까진 오케이. 그 아래는 여전히 마음에 안 듦 —
  발과 발목이 떨어져 있는 느낌 · 옆에서 볼 때 다리~허벅지 굴곡이 전혀 없음 · 피스톤이 피스톤이 아니라 융합된 장식 → 리메이크".

[관찰: 메인·옆 확대] 정강이 앞이 열려 있음(양옆 장갑 껍데기 사이로 짙은 프레임 + 드러난 피스톤: 굵은 실린더 위 · 강철 로드 아래 · 노랑 띠) ·
  정강이 아래 = 발목 앞을 감싸는 넓은 각진 띠(커프)가 발등 위를 덮음 · 발등이 발목 쪽으로 솟아 커프 밑으로 들어감 ·
  발목 옆(뒤쪽) 큰 둥근 원반 · 종아리 바깥 호스 · 옆에서 무릎이 살짝 앞(다리 전체가 굽은 선).
[판단] r2 원인: ① 정강이 아래 끝(z46)과 발 윗면(z≤29) 사이 17칸이 가는 짙은 기계부뿐 → 떨어져 보임
  ② 허벅지·정강이·발을 모두 수직으로 쌓아 옆이 일자 ③ 피스톤이 앞판 홈(폭 ±4) 속 반지름 2.3 → 판과 붙은 무늬.
r3 (무릎 위 = r2b A 그대로):
  · 쉬는 자세 굽힘(파트 rot 에 구움): 허벅지 rotx −6(무릎 앞으로) · 정강이 +10 · 발 −4(바닥에 평평) — FELSEN STANCE 와 같은 방식
  · 정강이: 종아리 뒤로 불룩(45° 로 나갔다 들어옴) · 앞 아래가 앞으로(1:2) → 옆 실루엣이 곡선
  · 발목 커프: 정강이 아래 앞·옆을 감싸는 넓은 각진 띠(z44~58), 발 혀(tongue) 위를 덮음 · 발: 발등이 발목으로 솟는 혀 + 양옆 발목 가드
  · 발목 옆 큰 둥근 원반(뒤쪽, 바깥) — 발 파트(발목 축 중심이라 돌아도 그대로)
  D  홈형 피스톤   앞판에 넓은 홈(±6, 깊이 7) + 짙은 뒷벽, 피스톤이 홈 속에 떠 있음(양옆 틈 2칸)
  E  열린 앞     정강이 앞을 양옆 껍데기로 가르고(±7 열림) 짙은 프레임 + 굵은 피스톤이 무릎 아래~커프까지 드러남 + 종아리 바깥 호스
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
import mass_leg_r2 as l2  # noqa: E402

PAL = l2.PAL
CX, KNEE, ANK = l2.CX, l2.KNEE, l2.ANK
BEND = dict(U=-6, L=10, F=-4)
NAMES = {"D": "D 홈형 피스톤", "E": "E 열린 앞 + 호스"}


def build_lower(M, v="E", piston=True, hose_out=0, toe="groove"):
    for n in ("LowerLegL", "LowerLegR", "FootL", "FootR"):
        M.parts.pop(n, None)
    L = M.part("LowerLegL", (-8, -34, 30), (54, 36, 128), pivot=KNEE, parent="UpperLegL")
    G = L.g(); X, Y, Z = G
    ky, kz = KNEE[1], KNEE[2]
    # 무릎(r2b 그대로): 너클 ±16 · 축 · 뒷면 직사각 블록 · 짙은 쇠 회색 무릎판
    for xa, xb in ((CX - 16, CX - 10), (CX + 10, CX + 16)):
        L.add(cyl(G, "x", (ky, kz), 8, rng=(xa, xb)), 3)
        xe = xa if xa < CX else xb
        L.groove(cyl(G, "x", (ky, kz), 8.5) & ~cyl(G, "x", (ky, kz), 5.5) & (X == xe), 4)
        L.paint(cyl(G, "x", (ky, kz), 2.5) & (X == xe), 2)
    L.add(cyl(G, "x", (ky, kz), 4, rng=(CX - 10, CX + 10)), 4)
    L.add(cbox(G, (CX - 7, CX + 7), (4, 12), (99, 118), {"+yz": 2}), 3)
    for z0 in (104, 109, 114):
        L.groove((np.abs(X - CX) <= 6) & (Y == 12) & (Z == z0), 4)
    L.add(cbox(G, (CX - 12, CX + 12), (-11, 10), (90, 100), {"xy": 3}), 3)
    L.add(cbox(G, (CX - 12, CX + 12), (-21, -10), (90, 124), {"xz": 7, "x-y": 3, "+z-y": 4, "-z-y": 3}), 2)
    L.emboss((np.abs(X - CX) <= 8 - np.clip(np.abs(Z - 107) - 9, 0, None)) & (Z >= 94) & (Z <= 120) & (Y < -20), 2)
    # 정강이 껍데기: 폭은 아래로 조금 넓게, 뒤(종아리)는 45° 로 불룩했다 들어옴, 앞 아래는 1:2 로 앞으로
    ax_ = np.abs(X - CX)
    w = 14 + np.clip(96 - Z, 0, None) * 0.05
    yb = 11 + np.minimum(np.clip(96 - Z, 0, 7), np.clip(Z - 52, 0, None) * 0.5) + np.clip(np.minimum(96 - Z, Z - 52) - 7, 0, None) * 0
    yb = 11 + np.minimum(np.minimum(np.clip(96 - Z, 0, None), 8), np.clip(Z - 50, 0, None) / 2.0)
    yf = -13 - np.clip(66 - Z, 0, None) / 2.0
    sh = (ax_ <= w) & (Y >= yf) & (Y <= yb) & (Z >= 56) & (Z <= 97)
    sh &= ((w - ax_) + (Y - yf) >= 4) & ((w - ax_) + (yb - Y) >= 4)
    sh &= (Z <= 97 - np.clip(ax_ - (w - 4), 0, None))
    L.add(sh, 1)
    L.add(cbox(G, (CX - 10, CX + 10), (-8, 9), (40, 98), {"xy": 3}), 3)                         # 속 프레임(짙은)
    # 발목 커프: 정강이 아래 앞·옆을 감싸는 넓은 각진 띠(z44~58), 앞으로 나와 발 혀 위를 덮음
    cuff = cbox(G, (CX - 16, CX + 16), (-24, 10), (44, 58), {"x-y": 6, "+z-y": 4, "-z-y": 3, "x+y": 3})
    L.add(cuff, 1)
    L.paint(cuff & (Z <= 45), 3)
    L.emboss((ax_ <= 10) & (Z >= 47) & (Z <= 55) & (Y < -23), 1)                               # 커프 앞 2단 판(데칼 면)
    # 피스톤: 무릎 밑 짙은 받침(위) → 실린더(짙은 쇠) → 강철 로드 → 커프 위 받침(아래)
    py = -15.5 if v == "E" else -12.5
    if v == "D":
        ch = (ax_ <= 6) & (Z >= 60) & (Z <= 91)
        L.cut(ch & (Y < -7))
        L.add(ch & (Y == -7), 4)
    else:
        op = (ax_ <= 7) & (Z >= 59) & (Z <= 92)
        L.cut(op & (Y < -8))
        L.add(op & (Y == -8), 3)                                                              # 열린 앞 속 짙은 프레임
        for z0 in (66, 74, 82):
            L.groove(op & (Y == -8) & (Z == z0), 4)
    if piston:
        rr = 3.6 if v == "E" else 3.0
        L.add(cbox(G, (CX - 4, CX + 4), (py - 3, -7), (89, 93), {"xy": 1}), 3)                     # 위 받침
        L.add(cyl(G, "z", (CX, py), rr, rng=(76, 90)), 2)                                          # 실린더
        L.add(cyl(G, "z", (CX, py), rr + 0.6, rng=(86, 88)), 3)                                    # 실린더 위 테
        L.add(cyl(G, "z", (CX, py), rr - 1.3, rng=(60, 76)), 7)                                    # 로드(강철)
        L.add(cyl(G, "z", (CX, py), rr + 0.3, rng=(79, 81)), 5)                                    # 노랑 띠
        L.add(cbox(G, (CX - 4, CX + 4), (py - 3, -7), (57, 61), {"xy": 1}), 3)                     # 아래 받침(커프 위)
    if v == "E":                                                                               # 종아리 바깥 호스(검정)
        o = hose_out
        pts = [(CX + 14, 6, 94), (CX + 18 + o, 10 + o * 0.5, 78), (CX + 17 + o, 6 + o * 0.5, 60), (CX + 14, 2, 50)]
        for a_, b_ in zip(pts[:-1], pts[1:]):
            L.add(r1.seg(G, a_, b_, 1.8), 4)
        if o:                                                                                 # 양끝 죔쇠(짙은) — 호스가 판에서 떨어져 나왔다 들어감
            for c_ in (pts[0], pts[-1]):
                L.add(cbox(G, (c_[0] - 2, c_[0] + 1), (c_[1] - 2, c_[1] + 2), (c_[2] - 2, c_[2] + 2), {"xy": 1}), 3)
    L.rot = rotx(BEND["L"])
    L.trim()
    # ---- 발: 한 덩어리 + 발목으로 솟는 혀 + 양옆 발목 가드 + 바깥 큰 원반
    F = M.part("FootL", (-4, -50, 0), (48, 40, 46), pivot=ANK, parent="LowerLegL")
    G = F.g(); X, Y, Z = G; ax_ = np.abs(X - CX)
    prof = [(-38, 3), (-38, 9), (-30, 16), (-18, 20), (-10, 26), (14, 26), (22, 20), (27, 13), (27, 3)]
    F.add(poly(G, "x", prof) & cbox(G, (CX - 14, CX + 14), (-40, 30), (0, 28), {"x-y": 5, "x+y": 3, "+zx": 3}), 1)
    F.add(cbox(G, (CX - 15, CX + 15), (-40, 29), (0, 3), {"xy": 4}), 3)
    F.add(cbox(G, (CX - 13, CX + 13), (-41, -31), (2, 12), {"-y+z": 4, "x-y": 4}), 2)
    if toe == "split":                                                                        # 실제로 살짝 갈라진 발끝(3칸 틈, 앞 13칸)
        F.cut((np.abs(X - CX) <= 1) & (Y <= -28))
    else:
        F.groove((X == CX) & (Y <= -20) & (Z >= 3), 4)
    F.add(cbox(G, (CX - 12, CX + 12), (22, 31), (2, 16), {"+y+z": 4, "x+y": 3}), 1)
    F.add(cbox(G, (CX - 9, CX + 9), (-20, -4), (20, 40), {"-y+z": 5, "xy": 2}), 1)              # 혀(발등 → 발목, 커프 밑으로)
    F.add(cbox(G, (CX - 8, CX + 8), (-7, 9), (24, 44), {"xy": 3}), 3)                           # 발목 짙은 블록
    for sg in (1, -1):
        F.add(cbox(G, sorted((CX + sg * 10, CX + sg * 14)), (-10, 12), (14, 38), {"+zy": 5, "-y+z": 3}), 1)   # 발목 가드
    F.add(cyl(G, "x", (3, ANK[2] - 6), 8, rng=(CX + 14, CX + 17)), 2)                          # 바깥 큰 원반(뒤쪽)
    F.groove(cyl(G, "x", (3, ANK[2] - 6), 8.5) & ~cyl(G, "x", (3, ANK[2] - 6), 6) & (X == CX + 17), 4)
    F.paint(cyl(G, "x", (3, ANK[2] - 6), 2.5) & (X == CX + 17), 3)
    F.rot = rotx(BEND["F"])
    F.trim()
    M.parts["UpperLegL"].rot = rotx(BEND["U"])
    M.parts["UpperLegR"].rot = rotx(BEND["U"])
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")
    return M


def build_all(v="E", ws=0.88):
    M = l2.build_all("A", ws)
    build_lower(M, v)
    return M


def ground(M):
    """발바닥 최저 z(월드)."""
    zs = []
    for n in ("FootL", "FootR"):
        p = M.parts[n]; T = M.world(n); ijk = np.argwhere(p.a > 0) + p.lo
        zs.append((ijk @ T[:3, :3].T + T[:3, 3])[:, 2].min())
    return min(zs)


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
    AS = l2.ARM_SPLAY
    walk = dict(AS, UpperLegL=rotx(-25), LowerLegL=rotx(30), UpperLegR=rotx(20), LowerLegR=rotx(10))
    specs = [(0, 2, "정면", AS), (-35, 8, "앞 3/4", AS), (-90, 2, "옆", AS), (150, 10, "뒤 3/4", AS), (-90, 2, "걷기", walk)]
    rows = [("r2b A (전)", l2.build_all("A"))] + [(NAMES[v], build_all(v)) for v in "DE"]
    rend = []
    for nm, M in rows:
        for pn in ("LowerLegL", "FootL"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        print(nm, "바닥 z", round(float(ground(M)), 1), "겹침", l2.overlaps(M, AS), "걷기", l2.overlaps(M, walk))
        ims = [vp.render(M.blocks(pose=ps), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=1.9, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _, ps in specs]
        lo = [vp.render(M.blocks(pose=AS), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=4.2, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                        light=(-0.75, -0.55, 0.6)) for y, pt in ((-30, 6), (-90, 2))]
        lo = [i.crop((0, int(i.height * 0.62), i.width, i.height)) for i in lo]
        rend.append((nm, ims + lo))
    labs = [s[2] for s in specs] + ["무릎 아래 확대 3/4", "무릎 아래 확대 옆"]
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((0, 20, 560, 935)), "컨셉 정면"), (mn.crop((60, 0, 1000, 1536)), "컨셉 메인"),
            (con.crop((580, 20, 920, 935)), "컨셉 옆"), (con.crop((980, 20, 1510, 935)), "컨셉 뒤"),
            (mn.crop((600, 1000, 900, 1520)), "메인 정강이 확대"), (con.crop((620, 560, 900, 930)), "옆 정강이 확대")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(labs))]
    W = max(200 + sum(cols) + 16 * 8, 200 + sum(c.width for c, _ in refs) + 16 * 7)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, labs) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 하체 r3 — 무릎 아래 리메이크: 쉬는 자세 굽힘 · 종아리 곡선 · 발목 커프 + 발 혀 · 드러난 피스톤", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, lb) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 200
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, lb)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0 + (H - im.height) // 2)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_하체r3_무릎아래.png"); sh.save(p); print(p, sh.size)
