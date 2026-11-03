"""양산형 가슴 r4 (2026-11-03) — 유저 "입체감은 대략 됐는데 컨셉 아트처럼 각진 느낌이 전혀 없음. 펠젠은 평면 흉부가 아니고 굴곡이 느껴짐".

[관찰: 메인 흉판 확대] 각진 느낌 = 여러 면이 꺾여 만남. 가로 꺾임선이 갈매기(⌄ 뒤집힌) 모양 — 가운데 수평(z≈214), 바깥으로 갈수록
대각선으로 올라감(z≈222) → 꺾임선 아래가 가운데 아래 면 + 양 모서리 면(경고 줄 자리)으로 나뉘고 셋 다 아래·뒤로 기욺 ·
위는 큰 앞면 → 앞 윗모서리 띠 → 윗면(고리) · 바깥 세로 옆 면.
[판단] r3 은 꺾임선이 수평 한 줄 + 앞면 수직 한 장이라 이 분할이 없어 평평. FELSEN 굴곡 = 흉판 두 덩어리 · 가운데 함수 · 30° 후드처럼 면이 여러 번 꺾임.
몸통 나머지(허리 마디 판·피스톤·호스·받침·고리·2단 판 홈)는 r3 a 그대로(앞 Y −26 · 폭 ±29).
  a  갈매기 꺾임선(가운데 |X|≤13 수평, 바깥 1:2 로 올라감) + 아래 45° → 모서리 면이 아래·바깥을 향한 비스듬한 면으로 생김
  b  a + 위 앞면이 위로 갈수록 1:3 뒤로 → 꺾임선이 가장 앞(옆에서 "<")
  c  b + 가운데 세로 능선(얕은 V 1:4, FELSEN 흉판 두 덩어리 느낌)
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
import mass_head_r5 as h5  # noqa: E402

PAL = h2.PAL
NAMES = {"a": "a 갈매기 꺾임선", "b": "b a + 위 앞면 1:3 (옆에서 <)", "c": "c b + 가운데 세로 능선"}


def grow(T, lo, hi):
    lo = np.minimum(T.lo, lo); hi = np.maximum(T.hi, hi)
    a = np.zeros(tuple(hi - lo), np.uint8); o = T.lo - lo
    a[o[0]:o[0] + T.a.shape[0], o[1]:o[1] + T.a.shape[1], o[2]:o[2] + T.a.shape[2]] = T.a
    T.a, T.lo, T.hi = a, np.array(lo), np.array(hi)


def rebuild(M, var="a", ws=0.88):
    yf, w = -26, 29
    T = M.parts["Torso"]
    grow(T, (-w - 8, yf - 4, 165), (w + 9, 42, 256))
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    # r1 가슴 앞 + 허리 앞(피스톤·호스) 걷어냄 — 등 상자(Y≥14)·척추(Y 6~15)·겨드랑이·어깨 축은 남김
    T.cut((ax <= w + 2) & (Y <= -8) & (Z >= 196))
    T.cut((ax <= 30) & (Y <= 5) & (Z >= 165) & (Z <= 199))
    ze = 203                                                                                  # 처마 아래 끝
    zt = 237                                                                                  # 흉판 윗면(곧은 한 줄)
    cx = 13                                                                                   # 꺾임선 가운데 수평 구간 반폭
    zc = 214 + np.clip(ax - cx, 0, None) / 2.0                                                # 갈매기 꺾임선: 바깥으로 1:2 로 올라감
    up = np.clip(Z - zc, 0, None) / 3.0 if var in "bc" else 0                                 # b·c: 위 앞면이 위로 갈수록 1:3 뒤로(꺾임선이 가장 앞)
    ridge = np.clip(ax, 0, None) / 4.0 if var == "c" else 0                                   # c: 가운데 세로 능선(얕은 V, 1:4)
    s = (ax <= w) & (Y >= yf) & (Y <= -6) & (Z >= ze) & (Z <= zt)
    base = yf + up + ridge
    s &= Y >= base + np.clip(ax - (w - 6), 0, None)                                           # 옆 면 45°(바깥 6칸)
    s &= Y >= base + np.clip(Z - (zt - 3), 0, None)                                           # 위 앞 모서리 45° 3칸
    s &= Y >= yf + ridge + np.clip(zc - Z, 0, None)                                           # 꺾임선 아래 45° 로 뒤로(가운데 아래 면 + 모서리 면)
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
    d = np.array((0, -4, 2))                                                                  # 머리 앞 4 · 위 2 [판단]
    H.lo = H.lo + d; H.hi = H.hi + d; H.pivot = tuple(np.array(H.pivot) + d)
    M.parts["Torso"].trim()
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    import mass_chest_r3 as c3
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-60, 18, "옆 앞 위"), (-90, 2, "옆")]
    rows = [("r3 a (전)", c3.build_all("a"))] + [(NAMES[v], build_all(v)) for v in "abc"]
    rend = []
    for nm, M in rows:
        p = M.parts["Torso"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Torso", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=4.5, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((150, 30, 400, 340)), "컨셉 정면"), (mn.crop((300, 40, 720, 560)), "컨셉 메인"),
            (mn.crop((320, 180, 620, 430)), "컨셉 흉판 확대")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(4)]
    W = max(330 + sum(cols) + 16 * 5, 330 + sum(c.width for c, _ in refs) + 16 * 4)
    allrows = [("참고", [c for c, _ in refs])] + rend
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 16) + 30), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 가슴 r4 — 갈매기 꺾임선 · 여러 면으로 꺾인 흉판 (빛 = 왼쪽 앞에서 낮게, 면 차이가 보이게)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(allrows):
        y0 = 60 + r * (H + 16); x = 330
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); x += cw + 16
    x = 330
    for i, t in enumerate([s[2] for s in specs]):
        d.text((x + 6, 60 + len(allrows) * (H + 16) + 2), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_가슴r4_꺾인면.png"); sh.save(p); print(p, sh.size)
