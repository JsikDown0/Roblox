"""양산형 가슴 r3 (2026-11-03) — 유저 "r2 둘 다 아쉬움. 펠젠 상체를 참고해서 다시. 각진 육덕 형태".

FELSEN 흉부 문법 [실측: 대표기체_시안/chest_heavy_r2.py, final_m2b]:
  흉판이 몸통보다 크게 앞으로(앞면 Y −44, 몸통 −42 · 폭 ±41) · 윗면 평평 + 앞 윗모서리 45° · 아랫단 45° 로 파고드는 처마 +
  그 밑 짙은 받침(깊은 그늘) · 배 = 좁고 짙은 마디 판이 층층이 → 넓은 가슴 / 좁은 배 대비가 묵직함.
양산형 컨셉에 입힘: 사다리꼴 흉판(아래 모서리 1:2 로 좁아짐) · 머리 A 와 같은 3면(옆 면 45°) · 고리 2 = 윗면 ·
  꺾임선 z214 아래 = 45° 처마 → z203 · 그 밑 짙은 받침 z197~203 · 허리 = 가운데 짙은 마디 판(층층) + 피스톤(노랑 띠 하나만, 낮게) + 검정 호스.
  가슴은 폭 배율(0.88)을 빼고 그대로 — 등·허리는 ×0.88 이라 가슴이 몸통보다 넓게 튀어나옴(육덕).
  1차 렌더 [관찰]: 흉판이 앞으로 나오자 머리가 깊은 우물에 묻히고, 목 우물 U 홈이 흉판 앞면을 파서 양동이처럼 보임.
  → [관찰: 메인] 흉판 앞 윗모서리는 고리 받침 높이에서 **곧게 한 줄**, 목은 그 뒤 · 어깨 쪽 높은 몸통(z243)은 흉판 뒤 한 단(요크).
  → 흉판 윗면 z237 곧게(45° 3칸) · 목 우물은 흉판 뒤에서만 · 머리를 앞 6칸·위 2칸 [판단](흉판이 앞으로 나온 만큼).
  a  앞면 Y −26 · 폭 ±29
  b  앞면 Y −30 · 폭 ±32 (더 묵직)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_head_r3 as h3  # noqa: E402
import mass_head_r5 as h5  # noqa: E402

PAL = h2.PAL
VARS = {"a": dict(yf=-26, w=29), "b": dict(yf=-30, w=32)}
NAMES = {"a": "r3 a 앞 −26 · 폭 ±29", "b": "r3 b 앞 −30 · 폭 ±32"}


def grow(T, lo, hi):
    lo = np.minimum(T.lo, lo); hi = np.maximum(T.hi, hi)
    a = np.zeros(tuple(hi - lo), np.uint8); o = T.lo - lo
    a[o[0]:o[0] + T.a.shape[0], o[1]:o[1] + T.a.shape[1], o[2]:o[2] + T.a.shape[2]] = T.a
    T.a, T.lo, T.hi = a, np.array(lo), np.array(hi)


def rebuild(M, var="a", ws=0.88):
    yf, w = VARS[var]["yf"], VARS[var]["w"]
    T = M.parts["Torso"]
    grow(T, (-w - 8, yf - 4, 165), (w + 9, 42, 256))
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    # r1 가슴 앞 + 허리 앞(피스톤·호스) 걷어냄 — 등 상자(Y≥14)·척추(Y 6~15)·겨드랑이·어깨 축은 남김
    T.cut((ax <= w + 2) & (Y <= -8) & (Z >= 196))
    T.cut((ax <= 30) & (Y <= 5) & (Z >= 165) & (Z <= 199))
    zc, ze = 214, 203                                                                        # 꺾임선 · 처마 아래 끝
    zt = 237                                                                                  # 흉판 윗면(곧은 한 줄)
    s = (ax <= w) & (Y >= yf) & (Y <= -6) & (Z >= ze) & (Z <= zt)
    s &= Y >= yf + np.clip(ax - (w - 6), 0, None)                                             # 옆 면 45°(바깥 6칸)
    s &= Y >= yf + np.clip(Z - (zt - 3), 0, None)                                             # 위 앞 모서리 45° 3칸
    s &= Y >= yf + np.clip(zc - Z, 0, None)                                                   # 아랫단 45° 처마
    s &= ax <= w - np.clip(222 - Z, 0, None) / 2.0                                            # 아래 모서리 1:2 로 좁아짐(사다리꼴)
    T.add(s, 1)
    # 윗면 2단 판: 안쪽 판 테두리 홈(FELSEN) — 목 우물 밖 양쪽
    rim = (ax >= 15) & (ax <= w - 3) & (Y >= yf + 5) & (Y <= 8)
    inner = (ax >= 16.5) & (ax <= w - 4.5) & (Y >= yf + 6.5) & (Y <= 6.5)
    T.paint_s((rim & ~inner) & (Z >= zt - 1) & (Z <= zt), 3)
    # 처마 밑 짙은 받침(깊은 그늘)
    T.add((ax <= w - 10) & (Y >= yf + 10) & (Y <= 4) & (Z >= 197) & (Z < ze) & ~(T.a > 0), 3)
    # 고리 2: 윗면 앞쪽
    for sg in (1, -1):
        xc = sg * round(w * 0.66)
        T.add(box(G, x=(xc - 3, xc + 3), y=(yf + 5, yf + 10), z=(zt + 1, zt + 2)), 3)
        T.add(cyl(G, "y", (xc, zt + 6), 4.0, rng=(yf + 6, yf + 8)) & ~cyl(G, "y", (xc, zt + 6), 2.0) & (Z >= zt + 2), 2)
    # 목 우물: 흉판 뒤에서만(앞 윗모서리는 곧게 남김)
    T.cut((ax <= 14) & (Y >= yf + 9) & (Y <= 10) & (Z >= 231))
    T.add(cbox(G, (-14, 14), (yf + 9, 10), (226, 230), {"xy": 3}) & ~(T.a > 0), 3)
    # 허리: 가운데 짙은 코어 + 층층 마디 판(위가 앞, 아래로 1칸씩 물러남, 45° 옆 모서리)
    T.add(cbox(G, (-12, 12), (-10, 8), (170, 198), {"xy": 3}), 3)
    for k, z0 in enumerate(range(191, 170, -5)):
        yk = -15 + k
        T.add(cbox(G, (-11 + k, 11 - k), (yk, -9), (z0, z0 + 3), {"x-y": (2, 2)}), 3 if k % 2 == 0 else 2)
    # 피스톤(양쪽 하나씩, 굵게): 짙은 쇠 실린더 + 강철 로드, 노랑 띠는 아래 하나만 · 바깥 검정 호스
    for sg in (1, -1):
        xt, xb = sg * round(19 * ws), sg * round(14 * ws)
        T.add(r1.seg(G, (xt, -6, 199), (xb, -6, 172), 2.2), 7)
        T.add(r1.seg(G, (xt, -6, 199), (xt + (xb - xt) * 0.45, -6, 187), 3.4), 2)
        T.add(r1.seg(G, (xt + (xb - xt) * 0.62, -6, 182), (xt + (xb - xt) * 0.66, -6, 181), 2.8), 5)
        T.add(r1.seg(G, (sg * round(25 * ws), -1, 199), (sg * round(23 * ws), -3, 186), 2.4) |
              r1.seg(G, (sg * round(23 * ws), -3, 186), (sg * round(16 * ws), -4, 174), 2.4), 4)


def build_all(var="a", ws=0.88):
    M = r1.build_all(ws)
    rebuild(M, var, ws)
    H = h5.build_head(M, "A")
    d = np.array((0, -6, 2))                                                                  # 머리 앞 6 · 위 2 [판단]
    H.lo = H.lo + d; H.hi = H.hi + d; H.pivot = tuple(np.array(H.pivot) + d)
    M.parts["Torso"].trim()
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    import mass_chest_r2 as c2
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-90, 2, "옆"), (-25, 32, "위 앞 3/4")]
    rows = [("r2 a (전)", c2.build_all("a"))] + [(NAMES[v], build_all(v)) for v in "ab"]
    rend = []
    for nm, M in rows:
        p = M.parts["Torso"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Torso", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=4.5, ss=2, ao_amt=0.5, bg=(132, 132, 132))
               for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((150, 30, 400, 340)), "컨셉 정면"), (mn.crop((300, 40, 720, 560)), "컨셉 메인")]
    fel = os.path.join(out, "..", "felsen_upper.png")
    if os.path.exists(fel):
        fi = Image.open(fel).convert("RGB"); refs.append((fi.crop((0, 0, 1080, fi.height)), "FELSEN 상체(참고)"))
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(4)]
    W = max(250 + sum(cols) + 16 * 5, 250 + sum(c.width for c, _ in refs) + 16 * 4)
    allrows = [("참고", [c for c, _ in refs])] + rend
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 16) + 30), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 가슴 r3 — FELSEN 흉부 문법(앞으로 크게 나온 흉판 · 45° 처마 + 그늘 · 좁은 마디 배)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(allrows):
        y0 = 60 + r * (H + 16); x = 250
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); x += cw + 16
    x = 250
    for i, t in enumerate([s[2] for s in specs]):
        d.text((x + 6, 60 + len(allrows) * (H + 16) + 2), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_가슴r3_펠젠문법.png"); sh.save(p); print(p, sh.size)
