"""양산형 기본형 무장 r2 (2026-11-03) — r1 답 [결정 11-03]: ① 빔사벨 = S2 왼 허리 뒤 ② 방패를 앞으로 20° 돌린 판 ③ 라이플 좋음, 개머리 디자인 몇 개 더.
  방패: 바깥 면을 앞쪽으로 20°(rotz −20, 피벗 = 받침 (54, −1, 158)) — 정면에서 면이 보이게.
  개머리 K0 지금 · K1 각진 쐐기 + 볼받침 + 고무 받침 · K2 접이식 골격 · K3 신축식(버퍼 관) · K4 두툼한 상자 + 옆 홈.
쓰기: python3 mass_weapon_r2.py <출력>"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_weapon_r1 as w1  # noqa: E402

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    AS = w1.MF.REST_POSE
    R = lambda M, y, p, ppc=1.9: vp.render(M.blocks(pose=l4.aim(M, AS)[0]), w1.PAL, w1.EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2,
                                          ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=w1.METAL)
    rows = []
    for yaw_, nm in ((0, "방패 0°(r1)"), (20, "방패 앞으로 20°")):
        M = w1.build_all("S2", False, shield_yaw=yaw_)
        ov = w1.overlaps(M, AS, [("Shield", ("UpperLegL", "LowerLegL", "PlateF", "PlateB", "ShoulderL", "HandL", "SaberHilt"))])
        print(nm, ov)
        ims = [R(M, y, p) for y, p in ((0, 2), (35, 8), (90, 2), (150, 10))]
        im = R(M, 25, 6, 3.6); w, h = im.size
        ims.append(im.crop((int(w * 0.35), int(h * 0.2), w, int(h * 0.75))))
        rows.append((nm, ims))
    stock_ims = []
    for k in w1.STOCKS:
        Mr = fv.Model(); w1.place_rifle(Mr, "Rifle", None, (0, 0, 0), (0, -1, 0), (0, 0, 1), k)
        p = Mr.parts["Rifle"]; _, n = ndimage.label(p.a > 0)
        print(k, "tris", 2 * greedy_quads(p.a), "섬", n - 1)
        a = vp.render(Mr.blocks(), w1.PAL, w1.EMISSIVE, yaw=-90, pitch=2, ppc=3.6, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=w1.METAL)
        b = vp.render(Mr.blocks(), w1.PAL, w1.EMISSIVE, yaw=-140, pitch=18, ppc=3.6, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=w1.METAL)
        stock_ims.append((w1.STOCKS[k], [a, b]))
    H1 = max(i.height for _, ims in rows for i in ims)
    W1 = max(sum(i.width for i in ims) for _, ims in rows) + 16 * 6
    H2 = max(i.height for _, ims in stock_ims for i in ims)
    W2 = max(sum(i.width for i in ims) for _, ims in stock_ims) + 48
    cols = 2
    W = max(W1, cols * W2) + 32
    nr = (len(stock_ims) + cols - 1) // cols
    sh = Image.new("RGB", (W, 60 + 2 * (H1 + 40) + nr * (H2 + 46)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 기본형 무장 r2 — 빔사벨 왼 허리 뒤(S2) · 방패 앞으로 20° · 개머리 5안", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(rows):
        y0 = 60 + r * (H1 + 40); x = 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
    for i, (nm, ims) in enumerate(stock_ims):
        x0 = 16 + (i % cols) * W2; y0 = 60 + 2 * (H1 + 40) + (i // cols) * (H2 + 46)
        d.text((x0, y0 - 2), nm, fill=(255, 190, 90), font=f)
        x = x0
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
    p = os.path.join(out, "시안_무장r2_방패개머리.png"); sh.save(p); print(p, sh.size)
