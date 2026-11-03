"""양산형 가슴 r2 (2026-11-03) — 머리 A(3면 45°) 확정 뒤. 몸통 나머지(등·허리·겨드랑이)는 r1 그대로, 가슴 앞만 다시.

[관찰: 메인 그림 확대] 흉판도 각진 면 — 넓은 가운데 앞면 + 좁은 양옆 비스듬한 면 · 가로 꺾임선(정면 y200 → z214) 아래 띠는
아래·뒤로 기울어 처마 · 아래 양 모서리는 큰 대각선 면(경고 줄 자리 → 데칼) · 고리 2 는 앞면이 아니라 **윗면**에 서 있음
(r1 은 앞면에 붙여 눈처럼 읽혔음).
공통(머리 A 와 같은 문법, 평면만): 가운데 앞면 Y −20 · 옆 면 45°(바깥 5칸) · 위 앞 모서리 45° 2칸 · 아래 띠 1:2 로 뒤로(z214 → 197 에서 8.5칸)
  · 아래 모서리 1:2 로 좁아짐 · 고리 = 윗면(z243) 위에 세움(받침 짙은 · 고리 짙은 쇠 회색).
  a  꺾임선 단차 없음(머리 A 처럼 면만)
  b  위 판이 아래 띠를 1칸 덮는 처마 단차
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_head_r3 as h3  # noqa: E402
import mass_head_r5 as h5  # noqa: E402

PAL = h2.PAL
NAMES = {"a": "a 3면 · 꺾임 단차 없음", "b": "b 3면 + 처마 단차"}


def rebuild_chest(M, var="a", ws=0.88):
    T = M.parts["Torso"]
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    w = round(29 * ws)
    T.cut((ax <= w + 1) & (Y <= -8) & (Z >= 196) & (Z <= 252))                              # r1 가슴 앞(고리 포함) 걷어냄
    zc = 214                                                                                  # 가로 꺾임선
    s = (ax <= w) & (Y >= -20) & (Y <= -7) & (Z >= 197) & (Z <= 243)
    s &= Y >= -20 + np.clip(ax - (w - 5), 0, None)                                            # 옆 면 45°
    s &= Y >= -20 + np.clip(Z - 241, 0, None)                                                 # 위 앞 모서리 45°
    lower = Z < zc
    s &= ~lower | (Y >= -20 + (var == "b") + (zc - Z) / 2.0)                                  # 아래 띠 1:2 로 뒤로(b: 1칸 더 들어가 처마)
    s &= ~lower | (ax <= w - (zc - Z) / 2.0)                                                  # 아래 모서리 1:2 로 좁아짐
    T.add(s, 1)
    # 고리 2: 윗면 앞쪽에 세움
    for sg in (1, -1):
        xc = sg * round(19 * ws)
        T.add(box(G, x=(xc - 3, xc + 3), y=(-18, -13), z=(243, 245)), 3)
        ring = cyl(G, "y", (xc, 249), 4.0, rng=(-17, -15)) & ~cyl(G, "y", (xc, 249), 2.0) & (Z >= 245)
        T.add(ring, 2)


def build_all(var="a", ws=0.88):
    M = r1.build_all(ws)
    T = M.parts["Torso"]
    # 고리가 경계 상자 위로 나가므로 위로 넓힘
    a = np.zeros((T.a.shape[0], T.a.shape[1], T.a.shape[2] + 12), np.uint8); a[:, :, :T.a.shape[2]] = T.a
    T.a = a; T.hi = T.lo + np.array(a.shape)
    rebuild_chest(M, var, ws)
    h2.lower_neck_well(M, ws)
    h3.collar_lip(M, ws)
    h5.build_head(M, "A")
    M.parts["Torso"].trim()
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
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-90, 2, "옆"), (-25, 32, "위 앞 3/4")]
    M0 = r1.build_all(0.88); h2.lower_neck_well(M0, 0.88); h3.collar_lip(M0, 0.88); h5.build_head(M0, "A")
    rows = [("r1 가슴 (전)", M0)] + [(NAMES[v], build_all(v)) for v in "ab"]
    rend = []
    for nm, M in rows:
        for pn in ("Torso", "Head"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=4.5, ss=2, ao_amt=0.5, bg=(132, 132, 132))
               for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((150, 30, 400, 340)), "컨셉 정면"), (mn.crop((300, 40, 720, 560)), "컨셉 메인"),
            (con.crop((600, 30, 830, 340)), "컨셉 옆(방패에 가림)")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max([refs[i][0].width if i < 3 else 0] + [ims[i].width for _, ims in rend]) for i in range(4)]
    W = 250 + sum(cols) + 16 * 5
    allrows = [("컨셉", [c for c, _ in refs])] + rend
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 16) + 30), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 가슴 r2 — 머리 A 와 같은 3면 45° · 고리는 윗면", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(allrows):
        y0 = 60 + r * (H + 16); x = 250
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            sh.paste(im, (x + (cols[i] - im.width) // 2, y0)); x += cols[i] + 16
    x = 250
    for i, t in enumerate([s[2] for s in specs]):
        d.text((x + 6, 60 + len(allrows) * (H + 16) + 2), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_가슴r2_3면.png"); sh.save(p); print(p, sh.size)
