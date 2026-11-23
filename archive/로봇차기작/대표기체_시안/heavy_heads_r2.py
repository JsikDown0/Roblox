"""
heavy_heads.py — r2 중장갑 기체(flagship_heavy.py)의 몸은 그대로 두고 머리만 바꾼 시안 3종 (2026-10-25)

  A 볏 기사   : 앞으로 내민 턱 + 아래로 꺾인 V 눈썹 + T자 바이저 + 뒤로 넘어가는 굵은 볏 하나
  B 뿔 바이저 : 넓고 낮은 투구 + V자로 꺾인 눈빛 + 관자놀이에서 뒤로 뻗는 두꺼운 뿔 두 개 + 내민 턱
  C 모노아이  : 각진 돔 + 챙 + 가로 레일 속 외눈(한쪽으로 치우침) + 숨구멍 그릴 + 뒤로 누운 칼날 안테나

규약은 flag_vox 와 같다(칸 = 0.05 Blender, +X = 기체 왼쪽, -Y = 정면, +Z = 위).
목 피벗·부모(Torso)·깃 구멍(|x| ≤ 12)은 원본 그대로라 몸 쪽은 손대지 않는다.
python3 heavy_heads.py → 비교 시트
"""
import numpy as np

import flag_vox as fv
import flagship_heavy as fh
from flag_vox import box, cbox, poly, cyl, ell, slab

LO, HI, PIVOT = (-36, -32, 230), (37, 30, 296), (0, -4, 238)
SCALE, LIFT = 1.15, 3       # 머리를 1.15배 키우고 3칸 올림(깃 위로 얼굴이 더 드러나게)


def _g(p):
    """머리 마스크를 키워서 평가할 격자: 목 밑(0,-4,240) 기준 SCALE 배 + LIFT 칸 위."""
    X, Y, Z = p.g()
    return (X / SCALE, (Y + 4) / SCALE - 4, (Z - 240 - LIFT) / SCALE + 240)


def _sym(G):
    X, Y, Z = G
    return (np.abs(X), Y, Z)


def head_A(M):
    """볏 기사"""
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso")
    G = _g(p); X, Y, Z = G; ax = np.abs(X); Ga = _sym(G)
    p.add(cyl(G, "z", (0, -2), 6, (228, 243)), 3)
    hd = cbox(G, (-10, 10), (-15, 9), (241, 257), {"x-y": (4, 6), "+z-y": (6, 7), "+zx": 3, "x+y": 3})
    p.add(hd, 1)
    p.paint(hd & (Y >= 4), 2)
    # 앞으로 내민 턱(얼굴판)
    p.add(cbox(G, (-6, 6), (-19, -8), (240, 248), {"x-y": (3, 3), "-z-y": (3, 4)}), 1)
    # 볼 가드(아래가 앞으로 좁아짐)
    p.add(cbox(Ga, (8, 12), (-16, 3), (241, 252), {"-z-y": (5, 6), "+x-y": (3, 4), "+x+y": 2}), 1)
    p.paint(box(Ga, (12, 12), (-9, -1), (244, 249)), 3)
    # 아래로 꺾인 V 눈썹(앞으로 튀어나온 차양)
    p.add(poly(G, "y", [(0, 249.5), (11, 252.5), (11, 255.5), (0, 253)], rng=(-18, -9), sym=True), 1)
    # T 바이저: 가로 눈빛(파고 넣음) + 얼굴판 가운데 세로 홈
    p.cut(box(G, (-8, 8), (-22, -13.6), (247.6, 249.4)))
    p.add(box(G, (-7, 7), (-14.4, -13.0), (247.6, 249.4)), 6)
    p.add(box(G, (-8.5, 8.5), (-13.0, -11.8), (247.6, 249.4)), 4)
    p.paint(box(G, (-0.5, 0.5), (-21, -15), (241, 247)), 4)
    # 볏: 이마에서 시작해 뒤로 넘어가며 높아지는 굵은 칼날 하나(앞 모서리 주황)
    crest = poly(G, "x", [(-16, 254), (-14, 261), (-6, 266), (6, 270), (16, 268), (15, 263), (4, 260), (-8, 256)],
                 rng=(-1.6, 1.6))
    p.add(crest, 1)
    p.paint(crest & (Y <= -11), 5)
    p.add(box(G, (-2, 2), (-10, 10), (255, 258)), 3)       # 볏 받침
    # 귀 센서(작은 원통)
    p.add(cyl(Ga, "x", (-3, 249), 3, (11, 13)), 3)


def head_B(M):
    """뿔 바이저"""
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso")
    G = _g(p); X, Y, Z = G; ax = np.abs(X); Ga = _sym(G)
    p.add(cyl(G, "z", (0, -2), 6, (228, 243)), 3)
    hd = cbox(G, (-11, 11), (-14, 8), (241, 255), {"x-y": (5, 7), "+z-y": (5, 8), "+zx": 4, "x+y": 3})
    p.add(hd, 1)
    p.paint(hd & (Y >= 3), 2)
    # 어두운 바이저 띠 + V 로 꺾인 눈빛(가운데가 낮음)
    band_ = hd & (Y <= -9) & (Z >= 245) & (Z <= 251)
    p.paint(band_, 4)
    vline = (np.abs(Z - (246.2 + 0.42 * ax)) <= 0.6) & (ax <= 8)
    p.paint_s(band_ & vline, 6)
    # 눈썹 차양(가운데가 낮은 V)
    p.add(poly(G, "y", [(0, 251), (12, 254), (12, 256.5), (0, 254)], rng=(-17, -8), sym=True), 1)
    # 내민 턱 + 숨구멍
    jaw = cbox(G, (-5, 5), (-18, -9), (237, 245), {"-z-y": (3, 4), "x-y": 2})
    p.add(jaw, 1)
    p.paint(box(G, (-0.5, 0.5), (-19, -16), (239, 243)), 4)
    # 관자놀이 뿔: 바깥·뒤·위로 뻗는 두꺼운 칼날(좌우 대칭)
    e1 = np.array([0.72, 0.58, 0.38]); e2 = np.array([0.0, 0.0, 1.0])
    horn = slab(G, (9, -7, 251), e1, e2, [(0, -2.5), (0, 3), (9, 3.6), (18, 2.2), (23, 0.6), (22, -0.6), (10, -2.5)],
                h=(-1.5, 1.5), sym=True)
    p.add(horn, 1)
    p.add(cbox(Ga, (9, 13), (-10, -2), (248, 256), {"+xz": 2}), 3)    # 뿔 뿌리
    p.paint(horn & (ax >= 25), 5)                                        # 뿔 끝 주황
    # 정수리 짧은 능선
    p.add(cbox(G, (-2, 2), (-11, 5), (254, 258), {"+z-y": (3, 3)}), 1)


def head_C(M):
    """모노아이"""
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso")
    G = _g(p); X, Y, Z = G; ax = np.abs(X); Ga = _sym(G)
    p.add(cyl(G, "z", (0, -2), 6, (228, 243)), 3)
    dome = ell(G, (0, -3, 247), (12, 13, 12)) & (Z >= 241) & \
        cbox(G, (-11, 11), (-15, 9), (241, 259), {"x-y": (3, 3), "+zx": (4, 4), "+z-y": (5, 5), "+z+y": (4, 4)})
    p.add(dome, 1)
    p.paint(dome & (Y >= 4), 2)
    # 챙(앞으로 내민 차양)
    p.add(cbox(G, (-11, 11), (-18, -9), (251, 254), {"x-y": (3, 4), "+z-y": (2, 3)}), 1)
    # 가로 레일(파고 짙게) + 한쪽으로 치우친 외눈
    p.cut(box(G, (-9, 9), (-22, -11), (246, 249)))
    p.add(box(G, (-9, 9), (-11, -10), (246, 249)), 4)
    p.add(cyl(G, "y", (-3, 247.5), 2.3, (-12, -11)), 6)
    # 숨구멍 그릴
    gr = cbox(G, (-6, 6), (-17, -8), (239, 246), {"x-y": 2, "-z-y": (2, 2)})
    p.add(gr, 2)
    for xx in (-4, -2, 0, 2, 4):
        p.paint(box(G, (xx, xx), (-18, -15), (240, 244)), 4)
    # 귀 통(원통)
    p.add(cyl(Ga, "x", (-2, 248), 4, (10, 13)), 2)
    p.add(cyl(Ga, "x", (-2, 248), 2, (13, 14)), 3)
    # 뒤로 누운 칼날 안테나(한 개, 가운데)
    p.add(poly(G, "x", [(-6, 257), (-3, 263), (9, 269), (12, 267), (4, 258)], rng=(-1, 1)), 1)


VARIANTS = {"A crest knight": head_A, "B horned visor": head_B, "C mono-eye": head_C}


def build(variant=None):
    M = fh.build_all()
    if variant is not None:
        del M.parts["Head"]
        VARIANTS[variant](M)
    return M


UPPER = ("Head", "Torso", "ChestPlate", "ShoulderL", "ShoulderR", "Backpack", "UpperArmL", "UpperArmR")


if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    A = fh.SCHEMES["A"]
    rows = [("r2 original", None)] + [(k, k) for k in VARIANTS]
    tiles, labels = [], []
    out = sys.argv[1] if len(sys.argv) > 1 else "heads.png"

    def head_frame(M, yaw, pitch, mx=16, top=8, bot=22):
        d, f, r, u = vp._basis(yaw, pitch)
        p = M.parts["Head"]
        P = np.argwhere(p.a > 0) + p.lo
        T = M.world("Head")
        P = P @ T[:3, :3].T + T[:3, 3]
        sx, sy = P @ r, P @ u
        cx = (sx.min() + sx.max()) / 2
        hh = (sy.max() + top) - (sy.min() - bot)
        half = max((sx.max() - sx.min()) / 2 + mx, hh * 0.62)
        return ((cx - half, cx + half), (sy.min() - bot, sy.max() + top))

    sheet_rows = []
    for name, v in rows:
        M = build(v)
        ims = []
        for y, pch in ((0, 6), (32, 10), (-34, 16)):
            near = ()
            Bu = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n not in UPPER or n in near])
            ims.append(vp.render(Bu, A, fh.EMISSIVE, yaw=y, pitch=pch, ppc=9, ss=2, ao_amt=0.5, size=head_frame(M, y, pch)))
        Bf = M.blocks(pose=fh.STANCE)
        fulls = [vp.render(Bf, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=1.6, ss=2, ao_amt=0.5) for y, pc in ((0, 4), (30, 6))]
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        fulls = [f_.resize((int(f_.width * H / f_.height), H), Image.LANCZOS) for f_ in fulls]
        sheet_rows.append(vp.sheet(ims + fulls, [name + "  front", "3/4", "3/4 (R, high)", "full front", "full 3/4"]))
        print(name, "%.1fs" % (time.time() - t0))
    W = max(r.width for r in sheet_rows)
    S = Image.new("RGB", (W, sum(r.height for r in sheet_rows)), (13, 14, 17))
    yy = 0
    for r in sheet_rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
