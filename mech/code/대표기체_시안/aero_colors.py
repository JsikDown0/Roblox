"""
aero_colors.py — Aero 색 배합 시안 (2026-10-26 13:58~)

유저: "W1(상체 3차 맨 윗줄 — 유저는 'U1'이라 부름) 멋진데. 아까 만든 얼굴 투구와 합쳐서 색 배합 시안 몇 개"
기체 = 상체 W1(aero_upper_w) + 얼굴 P1 + 투구 가운데 띠 T1(aero_faces_t.helm_strip, 짧은 코가리개)
     + 골반·다리를 상체와 같은 색 규칙으로 다시 칠함(주장갑 흰/밝은 회색, 강조색은 끝에만).
색 번호 역할(시안마다 이 역할에 색만 바꿈):
  2 주장갑 · 10 보조장갑 · 3 프레임 · 4 검정 홈 · 1 강조 · 6 발광 · 7 금속
"""
import numpy as np

import aero_r1 as A
import aero_faces as F
import aero_faces_t as T
import aero_upper_w as W

MAIN, SUB, FRAME, ACC = 2, 10, 3, 1


def legs_recolor(M):
    """다리·골반: r1 은 주황이 큰 판(아래 정강이·발·앞 스커트) → 상체 W 규칙(큰 판 = 주장갑, 강조색은 끝에만)."""
    for side in "LR":
        s = M.parts["LowerLeg" + side]; G = s.g(); X, Y, Z = G
        s.paint((s.a == MAIN) & (Z >= 62) & (Z <= 96) & (Y <= -6), SUB)          # 윗 정강이 판 → 보조(아래 보호대와 층 구분)
        s.paint((s.a == ACC) & (Z <= 74), MAIN)                                  # 아래 정강이 보호대 → 주장갑 (무릎 쐐기만 강조)
        f = M.parts["Foot" + side]; G = f.g(); X, Y, Z = G
        f.paint((f.a == ACC) & (Y >= 14), FRAME)                                 # 뒤꿈치 박차 → 프레임
        f.paint((f.a == ACC) & (Z >= 14), SUB)                                   # 발등 → 보조
        f.paint((f.a == ACC) & (Y > -44), MAIN)                                  # 발끝 → 주장갑, 맨 끝만 강조
        u = M.parts["UpperLeg" + side]
        u.paint(u.a == ACC, SUB)                                                 # 허벅지 바깥 깃판 → 보조
        k = M.parts["SkirtF" + side]; G = k.g(); X, Y, Z = G
        k.paint((k.a == ACC) & (Z >= 154), MAIN)                                 # 앞 스커트 → 주장갑, 아래 끝만 강조
    b = M.parts["SkirtB"]
    b.paint(b.a == ACC, SUB)


def build():
    M = W.build("W1")
    T.helm_strip(M, long_nasal=False)
    legs_recolor(M)
    return M


build_all = build

_base = {4: (20, 21, 24), 5: (200, 40, 48), 8: (164, 78, 26)}     # 5 = 빨강(그레네이드 탄두, 10-26 21:22 유저 "탄두 빨강으로")
SCHEMES = {
    "C1 흰·주황": _base | {2: (226, 226, 222), 10: (186, 188, 190), 3: (64, 68, 76), 1: (222, 118, 40), 6: (255, 214, 90), 7: (138, 144, 150)},
    "C2 회색·주황": _base | {2: (176, 178, 176), 10: (136, 140, 144), 3: (50, 53, 58), 1: (216, 112, 34), 6: (255, 192, 82), 7: (110, 114, 118)},
    "C3 흰·적·금": _base | {2: (230, 229, 226), 10: (190, 190, 192), 3: (56, 58, 64), 1: (176, 36, 48), 6: (255, 206, 96), 7: (196, 160, 84)},
    "C4 흰·청": _base | {2: (222, 226, 232), 10: (160, 170, 182), 3: (36, 42, 56), 1: (52, 104, 196), 6: (110, 210, 255), 7: (120, 132, 148)},
    "C5 건메탈·주황": _base | {2: (96, 100, 108), 10: (72, 76, 82), 3: (38, 40, 44), 1: (232, 126, 40), 6: (255, 200, 80), 7: (130, 134, 138)},
}

if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    names = [n for n in SCHEMES if not sys.argv[2:] or n.split()[0] in sys.argv[2:]]
    M = build()
    Bf = M.blocks(pose=A.STANCE)
    keep = {"Torso", "Pelvis", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
            "Backpack", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR"} | set(F.HEAD_PARTS) | set(W.UPPER)
    Bc = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
    rows = []
    for nm in names:
        sch = SCHEMES[nm]
        ims = [vp.render(Bf, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=1.9, ss=2, size=((-100, 100), (-10, 300)), ao_amt=0.5)
               for y, p in ((0, 4), (30, 6), (150, 12))]
        ims.append(vp.render(Bc, sch, A.EMISSIVE, yaw=24, pitch=6, ppc=3.6, ss=2, size=((-72, 72), (176, 292)), ao_amt=0.5))
        rows.append(vp.sheet(ims, ["%s  front" % nm.split()[0], "3/4", "back 3/4", "bust"]))
        print(nm, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
