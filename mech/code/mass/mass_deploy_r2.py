"""설치물 r2 (2026-11-04) — 유저 "방벽 배치를 레퍼런스처럼 약간 오목하게 · 포탑 머리 다시(옛날 영사기처럼 생김)".
방벽: 바깥 기둥 앞으로 22 + 판 가운데가 뒤로(오목). 포탑 머리 3안 T1 쐐기 / T2 낮고 넓은 상자 + 긴 총열 덮개 / T3 양옆 장갑 포드.
[판단] 영사기 원인 = 정육면체 상자 + 납작한 정면 판 + 가운데 둥근 원형 받침(렌즈처럼 읽힘) → 둥근 원 없이 각진 총열·덮개로."""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import mass_deploy_r1 as d1  # noqa: E402
if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    R = lambda B, y, p, ppc: vp.render(B, d1.PAL, (), yaw=y, pitch=p, ppc=ppc, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=d1.METAL)
    W = d1.build_wall()
    rows = [("방벽 오목하게 (정면 3/4 · 위)", [R(W.blocks(), -25, 10, 1.3), R(W.blocks(), 0, 85, 1.3)])]
    for k in ("T0", "T1", "T2", "T3"):
        M = d1.build_turret(k); p = M.parts["TurretHead"]; _, n = ndimage.label(p.a > 0)
        print(k, "head tris", 2 * greedy_quads(p.a), "섬", n - 1)
        rows.append((d1.HEADS[k] if k in d1.HEADS else k, [R(M.blocks(), y, pt, 3.0) for y, pt in ((0, 6), (-35, 14), (-90, 4))]))
    H = [max(i.height for i in ims) for _, ims in rows]
    Wd = max(sum(i.width for i in ims) + 16 * (len(ims) + 1) for _, ims in rows)
    sh = Image.new("RGB", (Wd, 60 + sum(h + 46 for h in H)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "설치물 r2 — 방벽 오목 · 포탑 머리 3안", fill=(235, 235, 235), font=ft)
    y0 = 60
    for (nm, ims), h in zip(rows, H):
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f); x = 16
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
        y0 += h + 46
    p = os.path.join(out, "시안_설치물r2.png"); sh.save(p); print(p, sh.size)
