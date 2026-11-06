"""jet_sheet_r2.py — FalcoJet r2 시트: 컨셉 c1 ↔ r2 같은 방향 + r1(버린 안) + 인간형. python3 jet_sheet_r2.py CONCEPT.png OUT.png"""
import sys, time
from PIL import Image, ImageDraw
import jet_r1, jet_r2, jet_r3
from jet_sheet import R, font, BG
import aero_export as E, aero_wing_v as WV, aero_r1 as A

def fit(im, h):
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)

if __name__ == "__main__":
    t = time.time(); CON, OUT = sys.argv[1:3]
    con = Image.open(CON).convert("RGB")
    B2 = jet_r3.build_all().blocks(); B1 = jet_r2.build_all().blocks()
    H = E.build(); WV.build_wing(H, "W2"); HB = H.blocks(pose=A.STANCE)
    ppc = 1.7
    rows = [
        [("컨셉 c1 (1순위)", con.crop((60, 30, 1490, 650))), ("r3 앞 3/4", R(B2, 35, 28, ppc)), ("r2 (지난 판)", R(B1, 35, 28, ppc))],
        [("컨셉 정면", con.crop((10, 690, 560, 900))), ("r3 정면", R(B2, 0, 6, ppc)), ("컨셉 위", con.crop((1090, 520, 1530, 1010))), ("r3 위", R(B2, 0, 89, ppc))],
        [("r3 옆", R(B2, 90, 2, ppc)), ("r3 뒤 3/4 (게임 카메라)", R(B2, 160, 24, ppc)), ("인간형 FALCO (같은 축척)", R(HB, 30, 8, 1.0))],
    ]
    print("render", round(time.time() - t, 1))
    hs = [300, 300, 300]; pad = 16; f = font(20)
    rows = [[(l, fit(i, h)) for l, i in r] for r, h in zip(rows, hs)]
    W = max(sum(i.width for _, i in r) + pad * (len(r) + 1) for r in rows)
    S = Image.new("RGB", (W, sum(hs) + 36 * 3 + 70), (28, 29, 32)); d = ImageDraw.Draw(S)
    d.text((pad, 12), "FalcoJet r3 — r2 + 흡기구 겹 · 주황 발톱 · 윗면 흰 판", fill=(235, 235, 235), font=font(26))
    y = 56
    for r, h in zip(rows, hs):
        x = pad
        for l, im in r:
            S.paste(im, (x, y)); d.text((x, y + h + 4), l, fill=(220, 220, 220), font=f); x += im.width + pad
        y += h + 36
    S.save(OUT); print("done", round(time.time() - t, 1))
