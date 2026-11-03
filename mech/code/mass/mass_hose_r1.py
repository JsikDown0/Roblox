"""양산형 상체 호스 r1 (2026-11-03) — 유저 정정: "동력부가 아니고 호스야"(상체에도 하체 같은 호스).
→ 팔 피스톤(mass_power_r1)은 버린 안으로 보관, 골반 구멍 덮음은 유지. 호스 문법 = 하체 r4 종아리 호스와 같음
  (검정 r1.8~2 · 가운데가 판에서 2~3칸 떠서 입체적 · 양끝 짙은 죔쇠).
  A  아래팔 바깥 호스: 팔꿈치 밑 → 손목 위(아래팔 한 파트 안이라 팔이 움직여도 늘어나지 않음) — 정강이 호스와 짝
  B  등 → 어깨 호스: 등 상자 위 바깥 → 어깨 관절 뒤, 아치로 솟음(몸통 한 파트) — 게임 카메라(뒤)에서 늘 보임
  C  A + B
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
from flag_vox import cbox  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_leg_r2 as l2  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_power_r1 as pw  # noqa: E402

PAL, METAL = l4.PAL, l4.METAL
NAMES = {"A": "A 아래팔 바깥 호스", "B": "B 등 → 어깨 호스", "C": "C A + B"}


def grow(P, lo, hi):
    lo = np.minimum(P.lo, lo); hi = np.maximum(P.hi, hi)
    a = np.zeros(tuple(hi - lo), np.uint8); o = P.lo - lo
    a[o[0]:o[0] + P.a.shape[0], o[1]:o[1] + P.a.shape[1], o[2]:o[2] + P.a.shape[2]] = P.a
    P.a, P.lo, P.hi = a, np.array(lo), np.array(hi)


def hose(P, pts, r=1.8, clamp=True):
    G = P.g()
    for a_, b_ in zip(pts[:-1], pts[1:]):
        P.add(r1.seg(G, a_, b_, r) & ~(P.a > 0), 4)
    if clamp:
        for c_ in (pts[0], pts[-1]):
            P.add(cbox(G, (c_[0] - 2, c_[0] + 2), (c_[1] - 2, c_[1] + 2), (c_[2] - 2, c_[2] + 2), {"xy": 1}), 3)


def build_all(v="C", ws=0.88):
    M = l4.build_all(ws)
    pw.cover_pelvis_hole(M)
    if v in "AC":
        L = M.parts["LowerArmL"]; grow(L, (28, -18, 150), (64, 14, 192))
        hose(L, [(54, 4, 183), (58, 6, 176), (58, 5.5, 166), (51, 2, 159)])
        M.parts.pop("LowerArmR"); M.mirror("LowerArmL", "LowerArmR", "UpperArmR")
        M.parts["HandR"].parent = "LowerArmR"
    if v in "BC":
        T = M.parts["Torso"]; grow(T, (-40, -30, 165), (41, 42, 256))
        for s in (1, -1):
            hose(T, [(s * 19, 27, 241), (s * 24, 26, 249), (s * 29, 19, 249), (s * 31, 9, 236)], r=2.0)
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
    AS = l2.ARM_SPLAY
    rows = []
    for v in "ABC":
        M = build_all(v)
        for pn in ("Torso", "LowerArmL", "Pelvis"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(v, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        pz, _ = l4.aim(M, AS)
        ims = [vp.render(M.blocks(pose=pz), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=1.9, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6), metal=METAL) for y, pt in ((0, 2), (-35, 8), (150, 12), (-120, 10))]
        up = [vp.render(M.blocks(pose=pz), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=3.6, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                        light=(-0.75, -0.55, 0.6), metal=METAL) for y, pt in ((-60, 8), (160, 18))]
        up = [i.crop((0, int(i.height * 0.08), i.width, int(i.height * 0.5))) for i in up]
        rows.append((NAMES[v], list(zip(["정면", "앞 3/4", "뒤 3/4", "뒤 옆", "상체 확대 옆 앞", "상체 확대 뒤"], ims + up))))
    H = max(i.height for _, ims in rows for _, i in ims)
    cols = [max(ims[i][1].width for _, ims in rows) for i in range(6)]
    W = 230 + sum(cols) + 16 * 7
    sh = Image.new("RGB", (W, 60 + len(rows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 상체 호스 r1 — 하체 종아리 호스와 같은 문법(검정 · 가운데 떠 있음 · 양끝 죔쇠) · 골반 구멍 덮음", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(rows):
        y0 = 60 + r * (H + 50); x = 230
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (t, im) in enumerate(ims):
            sh.paste(im, (x + (cols[i] - im.width) // 2, y0 + (H - im.height) // 2)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_상체호스r1.png"); sh.save(p); print(p, sh.size)
