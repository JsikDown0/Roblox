"""양산형(R-03, 이름 미정) 최종 조립 (2026-11-03) — [결정 11-03 "B1 로 가자. 이제 이 기체 디자인은 확정"].

확정 구성: 머리 r5 A(3면 45°) · 가슴 r4 a(갈매기 꺾임선) · 어깨 r3(꺾인 판 PlateF/PlateB) · 팔 f(2축 경첩) ·
  하체 r2b A(골반 옆 블록 · 무릎 너클) + 무릎 아래 r3 E → r4(금속 피스톤 PistonCyl/PistonRod 구동 · 호스 띄움 · 발끝 가름) ·
  골반 구멍 덮음 · 상체 호스 B1(등 → 어깨, 낮은 아치). 몸통 폭 ×0.88 · 팔·어깨·다리 ×1.0. 색 1 회올리브 (102,103,82) ~ 8 크롬.
쓰기: python3 mass_final.py <그림 폴더> [<모델 폴더>]   → 4면 시트 · 검사 · (모델 폴더 주면) R03_full.json
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


def build_all():
    M = hs.build_all("B1")
    M.extra.update({"name": "R-03 양산형(이름 미정)", "palette": {str(k): list(v) for k, v in PAL.items()},
                    "emissive": sorted(EMISSIVE), "metal": sorted(METAL), "rest_pose": "UpperArmL/R roty ∓9",
                    "keep_local": list(KEEP_LOCAL),
                    "piston": {"T": l4.T_.tolist(), "B": l4.B_.tolist(), "cyl_len": l4.LC, "rod_len": l4.LR}})
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    mdir = sys.argv[2] if len(sys.argv) > 2 else None
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    M = build_all()
    cm.check(M)
    # 색 면적(정면·옆·뒤 맨 앞 칸)
    blocks = M.blocks(pose=l4.aim(M, REST_POSE)[0])
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 22); ft = ImageFont.truetype(FN, 30)
    views = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-90, 2, "옆"), (150, 10, "뒤 3/4"), (180, 2, "뒤")]
    ims = [vp.render(blocks, PAL, EMISSIVE, yaw=y, pitch=p, ppc=2.4, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                     light=(-0.75, -0.55, 0.6), metal=METAL) for y, p, _ in views]
    H = max(i.height for i in ims); W = sum(i.width for i in ims) + 16 * 6
    sh = Image.new("RGB", (W, H + 110), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 R-03 — 디자인 확정 (11-03)", fill=(235, 235, 235), font=ft)
    x = 16
    for im, (_, _, t) in zip(ims, views):
        sh.paste(im, (x, 60)); d.text((x + 6, 60 + H + 10), t, fill=(220, 220, 220), font=f); x += im.width + 16
    p = os.path.join(out, "확정_R03_전신.png"); sh.save(p); print(p, sh.size)
    if mdir:
        os.makedirs(mdir, exist_ok=True)
        M.save(os.path.join(mdir, "R03_full.json")); print("saved", os.path.join(mdir, "R03_full.json"))
