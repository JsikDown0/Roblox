"""HT-02 CETUS — r8 = 헬멧·가슴 r3b + 어깨 r1 + 드릴 팔 2안 확정 + 왼팔 r7 (2026-11-02)

유저 11-02: "2번이 가장 낫다. 이걸로 가자. 노랑 부분은 전부 금속 처리, 왼팔 그물은 실제 그물처럼 갈색"
- 오른팔 = cetus_drillarms.arm_2 (받침판 + 피스톤 기둥 2 + 축 → 낮은 모터 북 + 감긴 관 → 나선 계단 드릴)
- 색 5(황동) = 금속 재질. 게임에선 SurfaceAppearance 금속도 마스크(팔레트 5번 칸 = 흰색)로. 미리보기는 vox_preview metal 인자.
  색 시안 3: A 황동 그대로 · B 짙게 바랜 황동 · C 은색 강철 — 고르는 건 유저.
- 그물 밧줄·매듭·밧줄 테 = 새 색 9(갈색 밧줄). 갈색 2안: 삼베 갈색 / 짙은 젖은 밧줄.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import cetus_r4 as r4  # noqa: E402
import cetus_r6 as r6  # noqa: E402
import cetus_r7 as r7  # noqa: E402
import cetus_drillarms as da  # noqa: E402

ROPE = {"삼베 갈색": (142, 108, 70), "젖은 밧줄": (84, 60, 40)}
BRASS = {"A 황동 그대로": (170, 128, 60), "B 짙게 바랜 황동": (132, 104, 62), "C 은색 강철": (150, 152, 150)}
METAL = {5: 1.0}

PAL = dict(r6.PAL); PAL[9] = ROPE["삼베 갈색"]
EMISSIVE = r6.EMISSIVE
PAL_ULT = dict(r6.PAL_ULT); PAL_ULT[9] = PAL[9]
EMISSIVE_ULT = r6.EMISSIVE_ULT


def build_claw(M):
    C = r7.build_claw(M)
    C.a[C.a == 2] = 9            # 왼팔 아래팔의 뼈색은 그물 밧줄뿐 → 갈색 밧줄
    return C


def build_all():
    M = r4.build_all()
    r6.build_upper(M, +1)
    da.arm_2(M)
    build_claw(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
    import check_model
    M = build_all()
    check_model.check(M)
    B = M.blocks()
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    tiles = []
    for name, c in BRASS.items():
        pal = dict(PAL); pal[5] = c
        tiles.append((vp.render(B, pal, EMISSIVE, yaw=-35, pitch=6, ppc=2.6, ss=2, ao_amt=0.5, metal=METAL), name + " · 금속"))
    pal = dict(PAL)
    tiles.append((vp.render(B, pal, EMISSIVE, yaw=35, pitch=6, ppc=2.6, ss=2, ao_amt=0.5, metal=METAL), "A · 왼쪽 앞 3/4"))
    tiles.append((vp.render(B, pal, EMISSIVE, yaw=150, pitch=10, ppc=2.6, ss=2, ao_amt=0.5, metal=METAL), "A · 뒤 3/4"))
    left = M.blocks(skip=[n for n in M.parts if n not in ("ShoulderL", "UpperArmL", "LowerArmL")])
    for rn, rc in ROPE.items():
        pal = dict(PAL); pal[9] = rc
        tiles.append((vp.render(left, pal, EMISSIVE, yaw=40, pitch=8, ppc=4.0, ss=2, ao_amt=0.5, metal=METAL), "그물 " + rn))
    ref = vp.render(B, PAL, EMISSIVE, yaw=-35, pitch=6, ppc=2.6, ss=2, ao_amt=0.5)
    tiles.insert(0, (ref, "비교: 금속 처리 전"))
    H = max(t[0].height for t in tiles)
    row1, row2 = tiles[:4], tiles[4:]
    W = max(sum(t[0].width for t in r) + 16 * len(r) for r in (row1, row2))
    sh = Image.new("RGB", (W, 2 * (H + 44)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for ri, row in enumerate((row1, row2)):
        x = 0; y0 = ri * (H + 44)
        for im, t in row:
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 8, y0 + H + 8), t, fill=(225, 225, 225), font=f); x += im.width + 16
    sh.save(os.path.join(out, "cetus_r8_compare.png")); print(sh.size)
