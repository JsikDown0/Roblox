"""
striker_heads.py — r2 중장갑에 스트라이커 유레카(퍼시픽 림) 계열 머리 2종 (2026-10-25)

레퍼런스 머리 분석(정면 사진):
  - 덩어리: 짧고 넓은 드럼(앞에서 거의 정사각, 모서리 둥긂). 목이 거의 없이 가슴 위에 낮게 앉음.
  - 뚜껑: 위를 덮는 두꺼운 캡이 앞·옆으로 살짝 튀어나옴. 윗면에 사다리꼴 돋움 판.
  - 바이저: 얼굴 가운데 큰 '역오각형'(위는 일자, 아래는 V 로 모임) 주황 창 + 창 안에 겹친 V자 살.
  - 턱: 바이저 아래를 V 로 감싸는 두꺼운 볼·턱 판, 턱 밑(목)에서 주황 빛이 샘.
  X1 충실형 : 위 그대로.
  X2 각진형 : 뚜껑 앞이 V 로 내려와 바이저 위를 누름(노려봄), 바이저는 좁고 살 2줄, 턱이 더 앞으로.
"""
import numpy as np

import flagship_heavy as fh
from flag_vox import box, cbox, poly, cyl
from heavy_heads import PIVOT

LO, HI = (-40, -36, 226), (41, 34, 300)
SCALE, LIFT = 1.2, 0.0


def _g(p):
    X, Y, Z = p.g()
    return (X / SCALE, (Y + 4) / SCALE - 4, (Z - 240 - LIFT) / SCALE + 240)


def _sym(G):
    X, Y, Z = G
    return (np.abs(X), Y, Z)


def _visor(p, G, outline, face_y=-13.0, depth=3.0, chev=(247.0, 250.2), slope=0.62, center_bar=False):
    """역오각형 창: 파고 → 안쪽 벽 발광 → 앞에 겹친 V 살(짙은 회색)."""
    X, Y, Z = G
    ax = np.abs(X)
    win = poly(G, "y", outline, sym=True)
    p.cut(win & (Y <= face_y + depth) & (Y >= -24))
    p.add(win & (Y > face_y + depth - 0.1) & (Y <= face_y + depth + 1.2), 6)            # 창 안쪽 발광 벽
    bars = np.zeros(np.broadcast_shapes(X.shape, Y.shape, Z.shape), bool)
    for z0 in chev:
        bars |= np.abs(Z - (z0 + slope * ax)) <= 0.45
    if center_bar:
        bars |= ax <= 0.6
    p.add(win & bars & (Y > face_y + depth - 1.4) & (Y <= face_y + depth - 0.1), 3)     # V 살


def _neck_glow(p, G):
    p.add(cyl(G, "z", (0, -3), 6, (226, 241)), 3)
    p.add(box(G, (-4.5, 4.5), (-10.5, -8.5), (239.2, 240.4)), 6)                        # 턱 밑 새는 빛


def head_X1(M):
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso"); G = _g(p); Ga = _sym(G)
    X, Y, Z = G
    _neck_glow(p, G)
    hd = cbox(G, (-11, 11), (-13, 9), (240.5, 256), {"x-y": (4, 4), "x+y": (5, 5), "-z-y": (2, 3)})
    p.add(hd, 1)
    p.paint(hd & (Y >= 5), 2)
    # 뚜껑(앞·옆으로 튀어나옴) + 윗면 사다리꼴 돋움판
    p.add(cbox(G, (-12, 12), (-15, 10), (255, 259), {"x-y": (5, 5), "x+y": (6, 6), "+zx": 2.5, "+zy": 2.5, "-z-y": (1, 1)}), 1)
    p.add(poly(G, "z", [(-0.6, -13), (8, -13), (5, -3.5), (-0.6, -3.5)], rng=(259, 260.2), sym=True), 1)
    # 바이저 아래를 V 로 감싸는 볼·턱 판
    p.add(poly(G, "y", [(-0.6, 246.5), (10.6, 249.5), (10.6, 242.5), (4, 239.6), (-0.6, 239.6)], rng=(-14.6, -9), sym=True), 1)
    p.paint(box(G, (-0.5, 0.5), (-16, -12), (239.6, 243)), 3)                            # 턱 가운데 홈
    # 옆면 홈(드럼 띠)
    p.paint(box(Ga, (10.2, 11.5), (-9, 6), (248.4, 249.4)), 3)
    _visor(p, G, [(-0.6, 254.4), (8.6, 254.4), (7.2, 249.6), (0.6, 243.4), (-0.6, 243.4)])
    # 뒷머리: 가로 배기 슬릿
    for zz in (245, 248, 251):
        p.add(box(Ga, (1.5, 7.5), (8.8, 10.2), (zz - 0.7, zz + 0.7)), 4)


def head_X2(M):
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso"); G = _g(p); Ga = _sym(G)
    X, Y, Z = G
    ax = np.abs(X)
    _neck_glow(p, G)
    hd = cbox(G, (-11, 11), (-13, 9), (240.5, 256), {"x-y": (3, 3), "x+y": (5, 5), "-z-y": (2, 3)})
    p.add(hd, 1)
    p.paint(hd & (Y >= 5), 2)
    # 뚜껑: 앞 가장자리가 V 로 내려와 바이저 윗부분을 누름
    lid = cbox(G, (-12, 12), (-15.5, 10), (255, 259.5), {"x-y": (4, 4), "x+y": (6, 6), "+zx": 2.5, "+z-y": (2.5, 2.5), "+z+y": 2})
    p.add(lid, 1)
    vbrow = (Y >= -16.0) & (Y <= -11) & (ax <= 11) & (Z <= 255.5) & (Z >= 255.5 - 3.2 * np.clip(1 - ax / 11, 0, 1))
    p.add(vbrow, 1)
    p.add(poly(G, "z", [(-0.6, -14), (7, -14), (4.5, -4), (-0.6, -4)], rng=(259.5, 260.6), sym=True), 1)
    # 턱: 더 앞으로 내민 V
    p.add(poly(G, "y", [(-0.6, 246.0), (10.6, 249.0), (10.6, 242.0), (3.5, 239.0), (-0.6, 239.0)], rng=(-15.8, -9), sym=True), 1)
    p.paint(box(G, (-0.5, 0.5), (-17, -13), (239, 242.6)), 3)
    p.paint(box(Ga, (10.2, 11.5), (-9, 6), (248.4, 249.4)), 3)
    # 바이저: 좁고 낮게(V 차양 아래), 살 2줄
    _visor(p, G, [(-0.6, 253.6), (7.6, 253.6), (6.4, 249.6), (0.6, 244.4), (-0.6, 244.4)], chev=(247.6,))
    for zz in (245, 248, 251):
        p.add(box(Ga, (1.5, 7.5), (8.8, 10.2), (zz - 0.7, zz + 0.7)), 4)


VARIANTS = {"X1 striker faithful": head_X1, "X2 angular brow": head_X2}
UPPER = ("Head", "Torso", "ChestPlate", "ShoulderL", "ShoulderR", "Backpack", "UpperArmL", "UpperArmR")


def build(name):
    M = fh.build_all()
    del M.parts["Head"]
    VARIANTS[name](M)
    return M


if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    out = sys.argv[1] if len(sys.argv) > 1 else "striker.png"
    only = sys.argv[2:] or list(VARIANTS)
    A = fh.SCHEMES["A"]

    def head_frame(M, yaw, pitch, mx=10, top=5, bot=14):
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

    rows = []
    for name in only:
        M = build(name)
        Bu = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n not in UPPER])
        ims = [vp.render(Bu, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=9, ss=2, ao_amt=0.5, size=head_frame(M, y, pc))
               for y, pc in ((0, 5), (34, 9), (-36, 14), (160, 14))]
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        rows.append(vp.sheet(ims, [name + "  front", "3/4", "3/4 (other side, high)", "back 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), M.parts["Head"].count(), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
