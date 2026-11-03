"""양산형 무장 r3 (2026-11-03) — 유저 "총집이나 간이 거치대 추가 — 지금은 수납 라이플이 공중에 떠 있는 것처럼 보임".
수납 라이플(오른 허벅지 바깥, 총구 아래 · 윗면 앞): 몸통 X −44.5 ~ −55.5 · Y 11 ~ 25 · z 112 ~ 148. 허벅지 바깥 면 X −37, 뒤 면 Y ≈ 17.
늘어뜨린 손(X −34 ~ −51 · Y −9 ~ 8 · z 134 ~ 151)을 피하려고 모든 받침은 Y 8 보다 뒤.
  H1 간이 거치대: 허벅지 바깥 받침판 + 팔 2개 + 리시버를 감싼 고리 2(짙은) + 고정 핀(강철)
  H2 리시버 총집: 허벅지에 붙은 짙은 판 + 리시버를 뒤·옆에서 감싼 U 자 통(앞 = 총 윗면은 열림, 탄창·손잡이는 뒤로 나옴) + 위 끈
부모 = UpperLegR(허벅지와 같이 움직임). 파트 이름 RifleMount.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
from flag_vox import cbox, box  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_weapon_r1 as w1  # noqa: E402
import mass_final as MF  # noqa: E402

NAMES = {"H0": "H0 지금(받침 없음)", "H1": "H1 간이 거치대(팔 2 + 고리 2)", "H2": "H2 리시버 총집(U 자 통)"}


def add_mount(M, kind):
    if kind == "H0":
        return
    P = M.part("RifleMount", (-62, 4, 104), (-34, 32, 156), pivot=(-37, 12, 135), parent="UpperLegR")
    G = P.g(); X, Y, Z = G
    if kind == "H1":
        P.add(cbox(G, (-40, -37), (8, 16), (122, 147), {"yz": 2}), 3)                          # 허벅지 받침판
        P.groove((X == -40) & (Y >= 10) & (Y <= 14) & ((Z == 128) | (Z == 141)), 4)
        for z0 in (127, 141):
            P.add(box(G, x=(-45, -40), y=(13, 17), z=(z0 - 1, z0 + 1)), 3)                     # 팔
            ring = box(G, x=(-57, -43), y=(9, 27), z=(z0 - 1, z0 + 1)) & ~box(G, x=(-56, -44), y=(10, 26), z=(z0 - 2, z0 + 2))
            P.add(ring, 3)                                                                      # 리시버 고리
            P.add(box(G, x=(-58, -57), y=(16, 18), z=(z0 - 1, z0 + 1)), 7)                       # 바깥 고정 핀
    else:
        P.add(cbox(G, (-40, -37), (8, 18), (114, 150), {"yz": 2}), 3)                          # 허벅지 받침판
        shell = box(G, x=(-58, -42), y=(10, 28), z=(114, 146))
        hollow = box(G, x=(-56, -44), y=(8, 26), z=(113, 147))
        U = shell & ~hollow                                                                     # 앞(Y<10) 열림 = 총 윗면이 보임
        U &= ~(box(G, x=(-53, -47), y=(26, 28), z=(118, 140)))                                  # 뒤 창(탄창·손잡이 나옴)
        P.add(U, 2)
        P.add(box(G, x=(-42, -40), y=(12, 16), z=(118, 142)), 3)                               # 판 ↔ 통 이음
        P.add(box(G, x=(-59, -41), y=(9, 29), z=(147, 149)) & ~box(G, x=(-56, -44), y=(10, 26), z=(146, 150)), 3)   # 위 끈
        P.paint(box(G, x=(-59, -58), y=(15, 19), z=(147, 149)), 7)                             # 끈 버클
    P.trim()


def build_all(kind="H1"):
    M = MF.build_armed()
    add_mount(M, kind)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    from flag_vox import rotx
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    AS = MF.REST_POSE
    walk = dict(AS, UpperLegL=rotx(-25), LowerLegL=rotx(30), UpperLegR=rotx(20), LowerLegR=rotx(10))
    rows = []
    for k in ("H0", "H1", "H2"):
        M = build_all(k)
        if "RifleMount" in M.parts:
            p = M.parts["RifleMount"]; _, n = ndimage.label(p.a > 0)
            print(k, "RifleMount tris", 2 * greedy_quads(p.a), "섬", n - 1)
            print(k, "겹침", w1.overlaps(M, AS, [("RifleMount", ("HandR", "LowerArmR", "LowerLegR", "Pelvis"))]),
                  "걷기", w1.overlaps(M, walk, [("RifleMount", ("HandR", "LowerArmR", "LowerLegR", "Pelvis"))]))
        ims = []
        for y, pt, fr in ((-35, 8, (0.0, 0.3, 0.6, 0.75)), (-90, 4, (0.15, 0.3, 0.85, 0.75))):
            im = vp.render(M.blocks(pose=l4.aim(M, AS)[0], skip=("Rifle",)), MF.PAL, MF.EMISSIVE, yaw=y, pitch=pt, ppc=3.4, ss=2,
                           ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=MF.METAL)
            w, h = im.size; ims.append(im.crop((int(w * fr[0]), int(h * fr[1]), int(w * fr[2]), int(h * fr[3]))))
        rows.append((NAMES[k], ims))
    H = max(i.height for _, ims in rows for i in ims)
    cols = [max(ims[i].width for _, ims in rows) for i in range(2)]
    W = 300 + sum(cols) + 16 * 4
    sh = Image.new("RGB", (W, 60 + len(rows) * (H + 20)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 무장 r3 — 수납 라이플 거치(앞 3/4 · 옆) · 손 총은 숨김", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(rows):
        y0 = 60 + r * (H + 20); x = 300
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            sh.paste(im, (x + (cols[i] - im.width) // 2, y0)); x += cols[i] + 16
    p = os.path.join(out, "시안_무장r3_거치대.png"); sh.save(p); print(p, sh.size)
