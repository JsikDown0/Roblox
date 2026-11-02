"""HT-02 CETUS — 가슴 코어 둘레 다듬기 비교 (2026-11-02, 유저 "앞면부 가슴코어 주변 장식을 좀 다듬고 싶어")

지금(r3b): 평평한 황동 처마 막대 + 그 밑 가는 가로 발광 틈 · 아래에 황동 멍에(가슴) + 황동 상자(허리) 두 덩이가 겹쳐 쌓임.
[관찰] 처마가 그냥 막대라 "코어"보다 "명찰"처럼 보이고, 아래 황동 두 덩이가 계단처럼 둔함.
세 안 공통: 가슴 멍에를 빼고 허리 황동 상자 하나만 남김(두 덩이 → 한 덩이). 가로 틈(얼굴 함정 피하기 결정)은 유지.
1 압력 해치 테 — 둥근 모서리 황동 테(볼트 6) 안을 2칸 오목한 짙은 판으로, 그 안에 발광 틈 + 세로 창살 3
2 보일러 화구 — 비스듬한 무거운 황동 갓 + 3칸 오목한 화구 안에 황동 가로 날개 4, 날개 사이로 발광 4줄
3 아치 처마 + 죔쇠 — 양끝이 아래로 휜 넓은 처마 + 넓은 발광 틈 + 양끝 황동 죔쇠 + 밑에 짧은 환기 홈 3줄
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cbox, box  # noqa: E402
import cetus_r3 as r3  # noqa: E402
import cetus_r12 as r12  # noqa: E402

PAL, EMISSIVE, METAL = r12.PAL, r12.EMISSIVE, r12.METAL


def _hull(G):
    h = cbox(G, (-32, 32), (-26, 24), (172, r3.CHEST_TOP), ch={"xy": 11, "-zx": 6, "-zy": 6})
    return h & fv.ell(G, (0, -1, 196), (38, 31, 44))


def _clear(T, G):
    """처마·틈·멍에를 지우고 선체 면을 되살림(세로 홈 2줄 포함)."""
    X, Y, Z = G
    T.cut(box(G, x=(-16, 16), y=(-35, -18), z=(160, 208)))
    T.add(_hull(G) & box(G, x=(-16, 16), y=(-35, -18), z=(160, 208)), 1)
    T.groove(box(G, x=(11, 11), y=(-27, -18), z=(176, 216)) | box(G, x=(-11, -11), y=(-27, -18), z=(176, 216)), 4)


def bolt_y(T, G, x, z, y):
    T.add(fv.ell(G, (x, y, z), (1.3, 1.0, 1.3)), 5)


def chest_1(M):
    T = M.parts["Torso"]; G = T.g(); X, Y, Z = G
    _clear(T, G)
    frame = cbox(G, (-15, 15), (-29, -24), (183, 207), {"xz": 6})
    inner = cbox(G, (-11, 11), (-30, -24), (187, 203), {"xz": 4})
    T.add(frame & ~inner, 5)
    T.cut(inner & (Y <= -25))
    T.add(inner & (Y == -24), 3)                                   # 2칸 오목한 짙은 판
    T.add(box(G, x=(-8, 8), y=(-24, -24), z=(194, 197)), 6)       # 발광 틈
    for bx in (-4, 0, 4):
        T.add(box(G, x=(bx, bx), y=(-26, -25), z=(192, 199)), 3)   # 세로 창살 3
    for bx, bz in ((-13, 195), (13, 195), (-9, 205), (9, 205), (-9, 185), (9, 185)):
        bolt_y(T, G, bx, bz, -29.5)


def chest_2(M):
    T = M.parts["Torso"]; G = T.g(); X, Y, Z = G
    _clear(T, G)
    T.add(cbox(G, (-14, 14), (-29, -24), (182, 201), {"xz": 3}), 3)                     # 화구 틀(짙은 쇠)
    hood = cbox(G, (-16, 16), (-34, -24), (200, 208), {"xz": 3, "-y-z": (6, 5), "-y+z": 2})
    T.add(hood, 5)                                                                        # 비스듬한 황동 갓
    mouth = box(G, x=(-11, 11), y=(-30, -26), z=(184, 199))
    T.cut(mouth)
    T.add(box(G, x=(-11, 11), y=(-25, -25), z=(184, 199)), 6)                            # 안쪽 벽 발광
    for zc in (198, 194, 190, 186):
        T.add(box(G, x=(-11, 11), y=(-28, -26), z=(zc - 1, zc)), 5)                      # 가로 날개 4(2칸)


def chest_3(M):
    T = M.parts["Torso"]; G = T.g(); X, Y, Z = G
    _clear(T, G)
    ax = np.abs(X)
    zt = 206 - 0.035 * X ** 2                                                             # 양끝이 아래로 휜 아치
    eave = (ax <= 17) & (Z <= zt) & (Z >= zt - 4) & (Y >= -32) & (Y <= -24)
    eave &= (Y >= -32 + 0.25 * ax)                                                        # 끝으로 갈수록 덜 튀어나옴
    T.add(eave, 5)
    slit = box(G, x=(-12, 12), y=(-27, -25), z=(193, 196))
    T.cut(slit); T.add(box(G, x=(-12, 12), y=(-24, -24), z=(193, 196)), 6)
    for s in (1, -1):
        T.add(cbox(G, (s * 13, s * 16), (-29, -24), (189, 200), {"-yz": 1}), 5)          # 양끝 죔쇠
    for zc in (186, 183, 180):
        T.groove(box(G, x=(-7, 7), y=(-27, -25), z=(zc, zc)), 4)                          # 환기 홈 3


VARIANTS = [("0", "지금", None), ("1", "압력 해치 테", chest_1), ("2", "보일러 화구", chest_2), ("3", "아치 처마 + 죔쇠", chest_3)]


def build_all(which="0"):
    M = r12.build_all(True)
    fn = dict((v[0], v[2]) for v in VARIANTS)[which]
    if fn:
        fn(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    keep = ("Torso", "Head", "Pelvis", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR")
    cols = []
    for key, label, fn in VARIANTS:
        M = build_all(key)
        T = M.parts["Torso"]; _, k = ndimage.label(T.a > 0)
        print(key, "Torso tris", 2 * greedy_quads(T.a), "섬", k - 1)
        B = M.blocks(skip=[n for n in M.parts if n not in keep])
        a = vp.render(B, PAL, EMISSIVE, yaw=0, pitch=4, ppc=4.2, ss=2, ao_amt=0.5, metal=METAL)
        b = vp.render(B, PAL, EMISSIVE, yaw=-30, pitch=8, ppc=4.2, ss=2, ao_amt=0.5, metal=METAL)
        cols.append((key + " " + label, a, b))
    ha = max(t[1].height for t in cols); hb = max(t[2].height for t in cols)
    wcol = max(max(t[1].width, t[2].width) for t in cols)
    sh = Image.new("RGB", ((wcol + 16) * 2, 2 * (ha + hb + 70)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for i, (lab, a, b) in enumerate(cols):
        x = (i % 2) * (wcol + 16); y = (i // 2) * (ha + hb + 70)
        d.text((x + 8, y + 6), lab, fill=(230, 230, 230), font=f)
        sh.paste(a, (x, y + 40)); sh.paste(b, (x, y + 50 + ha))
    sh.save(os.path.join(out, "cetus_chest_compare.png")); print(sh.size)
