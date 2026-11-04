"""HT-10 BISON(양산형, 옛 ST-10, 컨셉 표기 R-03) 최종 조립 (2026-11-03) — 이름·형식번호 [결정 11-03 "바이슨 + ST-10 좋아"] — [결정 11-03 "B1 로 가자. 이제 이 기체 디자인은 확정"].

확정 구성: 머리 r5 A(3면 45°) · 가슴 r4 a(갈매기 꺾임선) · 어깨 r3(꺾인 판 PlateF/PlateB) · 팔 f(2축 경첩) ·
  하체 r2b A(골반 옆 블록 · 무릎 너클) + 무릎 아래 r3 E → r4(금속 피스톤 PistonCyl/PistonRod 구동 · 호스 띄움 · 발끝 가름) ·
  골반 구멍 덮음 · 상체 호스 B1(등 → 어깨, 낮은 아치). 몸통 폭 ×0.88 · 팔·어깨·다리 ×1.0. 색 1 회올리브 (102,103,82) ~ 8 크롬.
쓰기: python3 mass_final.py <그림 폴더> [<모델 폴더>]   → 4면 시트 · 검사 · (모델 폴더 주면) BISON_full.json
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import mass_r1 as r1  # noqa: E402
import mass_leg_r2 as l2  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_hose_r1 as hs  # noqa: E402

PAL, METAL, EMISSIVE = l4.PAL, l4.METAL, r1.EMISSIVE
REST_POSE = l2.ARM_SPLAY                                         # 쉬는 자세 = 팔 9° 벌림(주먹이 허벅지에 닿지 않게)
# 회전을 메시에 굽지 말고 Studio 에서 CFrame 으로 돌릴 파트(데칼 면 · 구동)
KEEP_LOCAL = ("PlateF", "PlateB", "PistonCylL", "PistonCylR", "PistonRodL", "PistonRodR")


def build_body():
    """무장 전 확정 몸(11-03 디자인 확정 시점)."""
    M = hs.build_all("B1")
    M.extra.update({"name": "BISON", "designation": "HT-10", "palette": {str(k): list(v) for k, v in PAL.items()},
                    "emissive": sorted(EMISSIVE), "metal": sorted(METAL), "rest_pose": "UpperArmL/R roty ∓9",
                    "keep_local": list(KEEP_LOCAL),
                    "piston": {"T": l4.T_.tolist(), "B": l4.B_.tolist(), "cyl_len": l4.LC, "rod_len": l4.LR}})
    return M


build_all = build_body


def build_armed():
    """[결정 11-03] 두께 B + 기본형 무장: 라이플(K2 곧은 아래 막대, 손) + RifleStowed(오른 허벅지) + 방패(돌리지 않음) + 빔사벨 손잡이(왼 허리 뒤)."""
    import mass_weapon_r1 as w1
    M = w1.build_all("S2", both=True, shield_yaw=0.0, stock="K2")
    import mass_weapon_r3 as w3
    w3.add_mount(M, "H1")                                                                     # [결정 11-03 "수납은 H1"] 간이 거치대
    M.extra["piston"]["T"] = l4.T_.tolist()
    M.extra["weapons"] = {"Rifle": "HandR", "RifleStowed": "UpperLegR", "RifleMount": "UpperLegR", "Shield": "LowerArmL", "SaberHilt": "Pelvis",
                          "note": "Rifle / RifleStowed 는 상태에 따라 하나만 보임(FELSEN 규약) · 방패 치기 = R · 빔사벨 = 근접 1/2"}
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    mdir = sys.argv[2] if len(sys.argv) > 2 else None
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    M = build_armed()
    cm.check(M)
    # 색 면적(정면·옆·뒤 맨 앞 칸)
    blocks = M.blocks(pose=l4.aim(M, REST_POSE)[0], skip=("RifleStowed",))
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 22); ft = ImageFont.truetype(FN, 30)
    views = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-90, 2, "옆"), (150, 10, "뒤 3/4"), (180, 2, "뒤")]
    ims = [vp.render(blocks, PAL, EMISSIVE, yaw=y, pitch=p, ppc=2.4, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                     light=(-0.75, -0.55, 0.6), metal=METAL) for y, p, _ in views]
    H = max(i.height for i in ims); W = sum(i.width for i in ims) + 16 * 6
    sh = Image.new("RGB", (W, H + 110), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "HT-10 BISON — 디자인 확정 + 기본형 무장 (11-03)", fill=(235, 235, 235), font=ft)
    x = 16
    for im, (_, _, t) in zip(ims, views):
        sh.paste(im, (x, 60)); d.text((x + 6, 60 + H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    p = os.path.join(out, "확정_BISON_전신_무장.png"); sh.save(p); print(p, sh.size)
    Ms = M; bl2 = Ms.blocks(pose=l4.aim(Ms, REST_POSE)[0], skip=("Rifle",))
    st = [vp.render(bl2, PAL, EMISSIVE, yaw=y, pitch=p, ppc=2.4, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=METAL)
          for y, p in ((-35, 8), (-90, 2))]
    import flag_vox as fv
    import mass_weapon_r1 as w1
    Mr = fv.Model(); w1.place_rifle(Mr, "Rifle", None, (0, 0, 0), (0, -1, 0), (0, 0, 1), "K2")
    rf = [vp.render(Mr.blocks(), PAL, EMISSIVE, yaw=y, pitch=p, ppc=3.6, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=METAL)
          for y, p in ((-90, 2), (-140, 18))]
    H2 = max(i.height for i in st + rf); W2 = sum(i.width for i in st + rf) + 16 * 5
    s2 = Image.new("RGB", (W2, H2 + 100), (24, 25, 28)); d2 = ImageDraw.Draw(s2)
    d2.text((16, 14), "수납 상태(라이플 오른 허벅지 간이 거치대 H1 · 빔사벨 왼 허리 뒤) + 라이플 K2", fill=(235, 235, 235), font=ft)
    x = 16
    for im in st + rf:
        s2.paste(im, (x, 60)); x += im.width + 16
    p2 = os.path.join(out, "확정_BISON_수납_라이플.png"); s2.save(p2); print(p2, s2.size)
    if mdir:
        os.makedirs(mdir, exist_ok=True)
        M.save(os.path.join(mdir, "BISON_full.json")); print("saved", os.path.join(mdir, "BISON_full.json"))
