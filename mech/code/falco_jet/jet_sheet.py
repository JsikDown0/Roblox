"""jet_sheet.py — FalcoJet 시트: 인간형 FALCO(같은 축척) + 비행기 4방향 + 위. python3 jet_sheet.py OUT.png"""
import sys, os, time
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import importlib
J = importlib.import_module(sys.argv[3] if len(sys.argv) > 3 else "jet_r1")
import vox_preview as vp
import aero_colors as Cc, aero_export as E, aero_wing_v as WV, aero_r1 as A

PAL = Cc.SCHEMES[E.SCHEME]; BG = (213, 215, 216)
def font(sz):
    for f in ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/nanum/NanumGothic.ttf"):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()
def R(B, yaw, pitch, ppc, size=None):
    return vp.render(B, PAL, A.EMISSIVE, yaw=yaw, pitch=pitch, ppc=ppc, ss=2, ao_amt=0.5, bg=BG, light=(-0.75, -0.55, 0.6), metal={7: 1.0}, size=size)
if __name__ == "__main__":
    t = time.time(); ppc = float(sys.argv[2]) if len(sys.argv) > 2 else 1.5
    M = J.build_all(); B = M.blocks()
    H = E.build(); WV.build_wing(H, "W2"); HB = H.blocks(pose=A.STANCE)
    views = [("인간형 FALCO (같은 축척)", HB, 30, 8), ("앞 3/4", B, 35, 20), ("옆", B, 90, 2), ("뒤 3/4 (게임 카메라)", B, 160, 22), ("위", B, 0, 89), ("앞", B, 0, 4)]
    ims = []
    for lab, b, y, p in views:
        ims.append((lab, R(b, y, p, ppc))); print(lab, round(time.time() - t, 1), flush=True)
    f = font(22); pad = 16
    W = sum(i.width for _, i in ims[:3]) + pad * 4; W2 = sum(i.width for _, i in ims[3:]) + pad * 4
    H1 = max(i.height for _, i in ims[:3]); H2 = max(i.height for _, i in ims[3:])
    S = Image.new("RGB", (max(W, W2), H1 + H2 + 150), (28, 29, 32)); d = ImageDraw.Draw(S)
    d.text((pad, 10), "FalcoJet r1 — FALCO 비행 형태(교체형) · 길이 26.3 · 날개 폭 21.7 · 높이 7.7 스터드 · 삼각형 8,998", fill=(235, 235, 235), font=font(26))
    x = pad
    for lab, im in ims[:3]:
        S.paste(im, (x, 56)); d.text((x, 56 + H1 + 4), lab, fill=(220, 220, 220), font=f); x += im.width + pad
    x = pad; y0 = 56 + H1 + 40
    for lab, im in ims[3:]:
        S.paste(im, (x, y0)); d.text((x, y0 + H2 + 4), lab, fill=(220, 220, 220), font=f); x += im.width + pad
    S.save(sys.argv[1]); print("done", round(time.time() - t, 1))
