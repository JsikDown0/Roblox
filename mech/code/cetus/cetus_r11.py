"""HT-02 CETUS — r11 = 확정본(머리 3 장식 없음 · 가슴 r3b · 어깨 · 팔 2안 · 하체 r10a) + 등 r1 (2026-11-02)

등 답 [결정 11-02, 윤곽읽기_r6_등.png]: ① 가운데 큰 탱크(R1)·철창 돔(X1) 뺌 — 머리 정체성을 해침 ② 철창 등불 하나만
③ 오른쪽 뒤 작은 통 + 발광 창(한쪽만) ④ 가로·세로 배관 굵고 단순하게 ⑤ 등 해치 자리 = 태엽 손잡이 / 밸브 핸들 비교.
배치 [판단]: 등 가운데 짙은 받침판 → 양옆 세로 배관 기둥(R4) + 위 가로 배관(R3) = "ㅠ" 틀.
  통(C) = 오른쪽 기둥 위(기체 오른쪽) · 등불(L) = 왼쪽 기둥 위(반대쪽, 좌우 무게) · 가운데 = 태엽 / 밸브.
3인칭 카메라가 등 뒤에 있으므로 태엽 날개·밸브 바퀴는 등에 나란한 면(x-z)으로 세워 뒤에서 크게 읽히게.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
from flag_vox import cbox, cyl, ell, box  # noqa: E402
import cetus_r6 as r6  # noqa: E402
import cetus_r10 as r10  # noqa: E402
import cetus_heads as hd  # noqa: E402

PAL, EMISSIVE, METAL = r10.PAL, r10.EMISSIVE, r10.METAL
PX, PZ0, PZ1, PY = 24, 172, 230, 30          # 세로 배관 |x| · 아래 · 위 z · 배관 중심 y
SIG_Z = 199                                  # 태엽 / 밸브 중심 높이


def build_back(M, sig="valve", twin=True):
    B = M.part("Back", (-44, 14, 160), (45, 60, 266), pivot=(0, 24, 200), parent="Torso")
    G = B.g(); X, Y, Z = G
    # 받침판(짙은 쇠, 선체 등에 붙음)
    plate = cbox(G, (-19, 19), (19, 27), (176, 226), {"xz": 5, "+y+z": 2, "+y-z": 2, "+yx": 2})
    B.add(plate, 1)
    B.paint(plate & ~cbox(G, (-17, 17), (19, 28), (178, 224), {"xz": 4}), 5)    # 청록 판 + 황동 테
    # R4 세로 배관 기둥 2 + 황동 띠 · R3 위 가로 배관(양 끝은 둥근 팔꿈치)
    for s in (1, -1):
        B.add(cyl(G, "z", (s * PX, PY - 3), 5, rng=(PZ0, PZ1)), 3)
        for z0 in (180, 204):
            B.add(cyl(G, "z", (s * PX, PY - 3), 6.2, rng=(z0, z0 + 2)), 5)
        B.add(r6.ball(G, (s * PX, PY - 3, PZ1), 5.5), 3)
        B.add(cyl(G, "z", (s * PX, PY - 3), 6.5, rng=(PZ0 - 2, PZ0 + 1)), 3)   # 아래 받침 고리
    B.add(cyl(G, "x", (PY - 3, PZ1), 5, rng=(-PX, PX)), 3)
    B.add(cyl(G, "x", (PY - 3, PZ1), 6.2, rng=(-3, 3)), 5)                     # 가운데 황동 이음
    # 양쪽 기둥 위 철창 등불 [결정 11-02 "머리 양옆 발광 파츠 하나로 통일 — 왼쪽 등불로"] (오른쪽 작은 통 → 등불)
    for s_ in ((1, -1) if twin else (1,)):
        lx, ly, lz = s_ * PX, PY - 3, PZ1 + 12
        B.add(cyl(G, "z", (lx, ly), 6.5, rng=(PZ1 + 3, PZ1 + 5)), 5)
        B.add(ell(G, (lx, ly, lz), (4.5, 4.5, 6)), 6)
        for k in range(4):
            a = np.pi / 4 + k * np.pi / 2
            bx, by = lx + 5.5 * np.cos(a), ly + 5.5 * np.sin(a)
            B.add(cyl(G, "z", (bx, by), 1.1, rng=(PZ1 + 5, lz + 7)), 5)
        B.add(cyl(G, "z", (lx, ly), 6.5, rng=(lz + 7, lz + 8)) | cyl(G, "z", (lx, ly), 3, rng=(lz + 9, lz + 10)), 5)
    if not twin:   # (r11 첫 판) 오른쪽 작은 통 + 발광 창
        cx_, cy_ = -PX, PY - 3
        B.add(cyl(G, "z", (cx_, cy_), 9, rng=(PZ1 + 3, PZ1 + 22)), 1)
        for z0 in (PZ1 + 3, PZ1 + 20):
            B.add(cyl(G, "z", (cx_, cy_), 10, rng=(z0, z0 + 2)), 5)
        B.add(cyl(G, "z", (cx_, cy_), 6, rng=(PZ1 + 23, PZ1 + 24)), 3)
        win = box(G, x=(cx_ - 4, cx_ + 4), y=(cy_ + 6, cy_ + 10), z=(PZ1 + 8, PZ1 + 16))
        B.cut(win & (Y >= cy_ + 9)); B.paint(win & (Y >= cy_ + 8), 6)
    # 가운데 시그니처: 황동 받침 고리 + 축(뒤로) + 태엽 날개 / 밸브 바퀴(등에 나란히 섬)
    B.add(cyl(G, "y", (0, SIG_Z), 10, rng=(25, 29)) & ~cyl(G, "y", (0, SIG_Z), 6, rng=(28, 29)), 5)
    B.add(cyl(G, "y", (0, SIG_Z), 6, rng=(25, 28)), 3)
    if sig == "key":
        B.add(cyl(G, "y", (0, SIG_Z), 2.5, rng=(28, 40)), 7)                   # 축
        B.add(cyl(G, "y", (0, SIG_Z), 4, rng=(34, 36)), 5)                      # 축 깃
        bow = ((ell(G, (-12, 42, SIG_Z), (11, 2.6, 9)) | ell(G, (12, 42, SIG_Z), (11, 2.6, 9)))
               | box(G, x=(-6, 6), y=(40, 44), z=(SIG_Z - 4, SIG_Z + 4)))
        hole = cyl(G, "y", (-13, SIG_Z), 4, rng=(38, 46)) | cyl(G, "y", (13, SIG_Z), 4, rng=(38, 46))
        B.add(bow & ~hole, 5)                                                     # 나비 모양 날개(구멍 2)
        B.add(cyl(G, "y", (0, SIG_Z), 3.5, rng=(44, 45)), 7)
    else:
        B.add(cyl(G, "y", (0, SIG_Z), 3, rng=(28, 37)), 7)                      # 밸브 대
        rim = cyl(G, "y", (0, SIG_Z), 15, rng=(36, 40)) & ~cyl(G, "y", (0, SIG_Z), 11.5)
        B.add(rim, 5)                                                             # 바퀴 테(황동)
        for k in range(5):                                                        # 바퀴살 5(짙은 쇠)
            a = np.pi / 2 + k * 2 * np.pi / 5
            u = (X * np.cos(a) + (Z - SIG_Z) * np.sin(a))
            v = (-X * np.sin(a) + (Z - SIG_Z) * np.cos(a))
            B.add((u >= 0) & (u <= 12) & (np.abs(v) <= 1.3) & (Y >= 37) & (Y <= 39), 3)
        B.add(cyl(G, "y", (0, SIG_Z), 4.5, rng=(36, 41)), 7)                    # 가운데 허브
        for k in range(5):                                                        # 테 손잡이 혹 5(바퀴살 끝)
            a = np.pi / 2 + k * 2 * np.pi / 5 + np.pi / 5
            B.add(ell(G, (14.5 * np.cos(a), 38, SIG_Z + 14.5 * np.sin(a)), (2.2, 3.0, 2.2)), 5)
    B.trim()
    return B


def build_all(sig="valve", twin=True):
    M = r10.build_all("a")
    hd.head_3(M, deco=False)
    build_back(M, sig, twin)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    rows = []
    for sig, twin, name in (("valve", False, "전: 등불 + 통"), ("valve", True, "후: 등불 2 통일")):
        M = build_all(sig, twin)
        print("==", name); check_model.check(M)
        Bk = M.blocks()
        up = M.blocks(skip=[n for n in M.parts if n not in ("Torso", "Head", "ShoulderL", "ShoulderR", "Back", "UpperArmL", "UpperArmR", "Pelvis")])
        LB = (0.55, 0.75, 0.85)                                                   # 뒤 그림용 조명(뒤 위에서)
        ims = [(vp.render(up, PAL, EMISSIVE, yaw=155, pitch=10, ppc=3.4, ss=2, ao_amt=0.5, metal=METAL, light=LB), "상체 뒤 3/4"),
               (vp.render(up, PAL, EMISSIVE, yaw=180, pitch=8, ppc=3.4, ss=2, ao_amt=0.5, metal=METAL, light=LB), "상체 뒤"),
               (vp.render(up, PAL, EMISSIVE, yaw=95, pitch=4, ppc=3.4, ss=2, ao_amt=0.5, metal=METAL, light=(0.8, 0.3, 0.85)), "상체 옆"),
               (vp.render(Bk, PAL, EMISSIVE, yaw=-30, pitch=6, ppc=1.7, ss=2, ao_amt=0.5, metal=METAL), "전신 앞 3/4")]
        rows.append((name, ims))
    H = max(im.height for _, ims in rows for im, _ in ims)
    W = max(sum(im.width + 16 for im, _ in ims) for _, ims in rows)
    sh = Image.new("RGB", (W, 2 * (H + 44)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for ri, (name, ims) in enumerate(rows):
        x = 0; y0 = ri * (H + 44)
        for im, t in ims:
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 8, y0 + H + 8), name + " · " + t, fill=(220, 220, 220), font=f)
            x += im.width + 16
    sh.save(os.path.join(out, "cetus_r11_compare.png")); print(sh.size)
