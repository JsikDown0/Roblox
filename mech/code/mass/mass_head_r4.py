"""양산형 머리 r4 하관 비교 (2026-11-02) — 유저 "바이저 아래(입 지운 쪽)는 단차가 없어야 맞지 않나? 하관 수정 버전 여러 개".

공통: r3(판 단차 · 입 지움)에서 턱 윗입술 단차를 뺌 → 바이저 아래는 단차 없는 한 판.
  a 매끈       r3 − 윗입술 단차(가장 작은 변경)
  b 앞턱       턱 아래쪽이 앞으로 2칸 나온 쐐기(옆에서 턱선이 또렷)
  c 감싼 턱    턱판이 바이저 양끝을 아래에서 감싸 올라감(U) — 바이저가 턱판 안에 박힌 모양
  d 좁은 턱    아래로 갈수록 좁아지는 V 턱(정면 윤곽이 날렵)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import poly, cyl, box, cbox  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_head_r3 as h3  # noqa: E402

PAL = h2.PAL
JAWS = {"a2": "a2 턱판 확장", "a": "a 매끈", "b": "b 앞턱(쐐기)", "c": "c 감싼 턱(U)", "d": "d 좁은 턱(V)"}


def build_head(M, jaw="a", parent="Torso", pivot_z=r1.NECK_Z):
    M.parts.pop("Head", None)
    H = M.part("Head", (-18, -20, 226), (19, 19, 263), pivot=(0, -3, pivot_z), parent=parent)
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    fr = [(h2.FX(x), h2.FZ(y)) for x, y in h2.FRONT_R]
    fr = fr + [(-a, b) for a, b in fr[::-1]]
    sd = [(h2.SY(x), h2.FZ(y)) for x, y in h2.SIDE]
    hull = poly(G, "y", fr) & poly(G, "x", sd)
    H.add(hull, 1)
    H.cut((ax > 6) & (Y < -15 + (ax - 6) * 0.7))
    # ---- 하관(바이저 아래, z < 243)
    if jaw == "b":      # 턱 아래가 앞으로: z236~241 에서 앞면을 Y −15 까지, 아래 모서리 45°
        H.add((ax <= 8 - np.clip(241 - Z, 0, None) * 0.5) & (Z >= 235) & (Z <= 242) & (Y >= -17) & (Y <= -8)
              & (Y >= -17 + np.clip(238 - Z, 0, None)), 1)
    if jaw == "a2":     # 유저 표시(11-03): 바이저 바로 밑 얇은 띠를 턱 끝까지 → 앞면이 평평한 한 장의 턱판
        H.add((ax <= 10.5 - (243 - Z) * 0.15) & (Z >= 235) & (Z <= 242.5) & (Y >= -13) & (Y <= -6), 1)
    if jaw == "d":      # V 턱: 아래로 갈수록 좁게
        H.cut((Z < 242) & (Y < 0) & (ax > 2.5 + (Z - 234) * 0.85))
    neck = cyl(G, "z", (0, 3), 7, rng=(226, 236)) & ~(H.a > 0)
    H.add(neck, 3)
    side = (ax >= 9) & (Z >= 238) & (Z <= 252) & (Y >= -6)
    H.cut(side & H.surface() & ~neck)
    # 바이저 홈 + 발광(r3 와 같음)
    top = 247.5 - np.clip(ax - 8, 0, None) * 0.8
    zc = 245.0 + 1.3 * (X / 8.0) ** 2
    back = -10.5 + np.clip(ax - 6, 0, None) * 0.7
    H.cut((ax <= 10.5) & (Z >= 243) & (Z <= top) & (Y <= back))
    wall = (ax <= 10.5) & (Z >= 243) & (Z <= top) & (np.abs(Y - (back + 0.5)) <= 0.5)
    H.add(wall, 3)
    H.paint(wall & (ax <= 8) & (np.abs(Z - zc) <= 1.5), 6)
    if jaw == "c":      # 턱판이 바이저 양끝을 감쌈: 홈 양끝(|X| 7.5~10.5)을 아래부터 z246 까지 다시 채움
        cup = (ax >= 5.5) & (ax <= 10.5) & (Z >= 243) & (Z <= 243 + (ax - 5.5) * 0.8) \
            & (Y >= -14 + np.clip(ax - 6, 0, None) * 0.7) & (Y <= back + 1)
        H.add(cup, 1)
        H.paint(wall & cup, 1)
    # 위쪽 판 단차(r3 와 같음) — 바이저 아래는 단차 없음
    H.emboss((ax <= 10) & (Z >= 248) & (Z <= 249) & (Y <= -12), 1)
    H.emboss((ax <= 5 + (258 - Z) * 0.16) & (Z >= 250) & (Z <= 258) & (Y <= 6), 1)
    H.emboss((ax <= 6) & (Y >= -4) & (Y <= 8) & (Z >= 257), 1)
    for s in (1, -1):
        H.add(box(G, x=(min(2 * s, 4 * s), max(2 * s, 4 * s)), y=(-3, 4), z=(258, 260)), 3)
    H.add(box(G, x=(-4, 4), y=(-3, 4), z=(261, 262)), 3)
    for s in (1, -1):
        lo_, hi_ = sorted((10 * s, 16 * s))
        H.add(cyl(G, "x", (1.5, 248.5), 5.6, rng=(lo_, hi_)), 3)
        H.groove(cyl(G, "x", (1.5, 248.5), 3.6) & ~cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 4)
        H.paint(cyl(G, "x", (1.5, 248.5), 2.2) & (ax >= 16), 2)
    H.emboss((ax <= 6) & (Z >= 250) & (Z <= 257) & (Y >= 10), 1)
    H.paint((Y >= 8) & (Z >= 241) & (Z <= 243), 3)
    H.trim()
    return H


def build_all(jaw="a", ws=0.88):
    M = r1.build_all(ws)
    h2.lower_neck_well(M, ws)
    h3.collar_lip(M, ws)
    build_head(M, jaw)
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
    specs = [(0, 0, "정면"), (-35, 4, "앞 3/4"), (-90, 0, "옆")]
    sel = sys.argv[2].split(",") if len(sys.argv) > 2 else list("abcd")
    rows = ([("r3 (지금)", h3.build_all(0.88))] if len(sys.argv) <= 2 else []) + [(JAWS[j], build_all(j)) for j in sel]
    rend = []
    for nm, M in rows:
        p = M.parts["Head"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Head", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = []
        for y, pt, _ in specs:
            im = vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=7, ss=2, ao_amt=0.5, bg=(132, 132, 132))
            ims.append(im.crop((int(im.width * 0.12), 0, int(im.width * 0.88), int(im.height * 0.42))))
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((205, 35, 345, 150)), "컨셉 정면"), (mn.crop((380, 40, 620, 260)), "컨셉 메인"),
            (con.crop((625, 30, 765, 145)), "컨셉 옆")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max([refs[i][0].width] + [ims[i].width for _, ims in rend]) for i in range(3)]
    W = 190 + sum(cols) + 16 * 4
    allrows = [("컨셉", [c for c, _ in refs])] + rend
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 16) + 30), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 머리 r4 — 하관 비교 (바이저 아래 단차 없음)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(allrows):
        y0 = 60 + r * (H + 16); x = 190
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            sh.paste(im, (x + (cols[i] - im.width) // 2, y0)); x += cols[i] + 16
    x = 190
    for i, t in enumerate(["정면", "앞 3/4", "옆"]):
        d.text((x + 6, 60 + len(allrows) * (H + 16) + 2), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_머리r4_하관비교.png" if len(sys.argv) <= 2 else "시안_머리r4_%s.png" % "_".join(sel))
    sh.save(p); print(p, sh.size)
