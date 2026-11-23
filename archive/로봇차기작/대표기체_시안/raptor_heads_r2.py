"""
raptor_heads.py — r2 중장갑에 '쐐기 머리 + 스트라이커 V 바이저' 2종 (2026-10-25)

머리통(픽셀아트 레퍼런스): 앞으로 뾰족한 쐐기 — 위에서 화살촉, 옆에서 뒤가 높고 앞이 낮게 기운 능선,
  앞에서 관자놀이가 넓고 턱으로 좁아지는 역오각형. 수직 앞면·평평한 뚜껑 없음. 큰 사선은 약 20°·35° 두 각도.
바이저(스트라이커): 역오각형 주황 창 + V 살, 뾰족한 이마 차양 밑 그늘 속.
  R1 대칭 : 좌우 귀 블레이드(뒤·위로 젖힘)
  R2 비대칭: 왼쪽(+X)만 긴 귀 블레이드 + 오른쪽 원통 센서 + 이마 한쪽 점 센서(보조 발광 1)
"""
import numpy as np

import flagship_heavy as fh
from flag_vox import box, cbox, poly, cyl, slab
from heavy_heads import PIVOT

LO, HI = (-44, -40, 224), (45, 40, 304)
SCALE, LIFT = 1.3, 0.0


def _g(p):
    X, Y, Z = p.g()
    return (X / SCALE, (Y + 4) / SCALE - 4, (Z - 240 - LIFT) / SCALE + 240)


def _sym(G):
    X, Y, Z = G
    return (np.abs(X), Y, Z)


def _shell(p, G):
    """앞뒤로 긴 쐐기(길이 36 ≈ 폭의 1.9배): 위에서 화살촉, 옆에서 뒤(259)→부리 끝(251) 한 번에 내려가는 능선(약 14°),
    앞에서 위가 좁은 사다리꼴 + V 턱. 부리(이마)가 얼굴보다 7칸 앞으로 나와 바이저를 덮는다."""
    X, Y, Z = G
    plan = poly(G, "z", [(-1.6, -24), (1.6, -24), (8.6, -10), (9.8, 2), (8.0, 12), (-8.0, 12), (-9.8, 2), (-8.6, -10)])
    side = poly(G, "x", [(-14.2, 240), (12, 240), (12, 255), (8, 259.2), (-24, 251.2), (-24, 249.4), (-17.2, 246.6),
                         (-16.0, 243.0), (-14.8, 240)])
    front = poly(G, "y", [(-0.6, 239.6), (3.2, 239.6), (9.8, 247.0), (9.8, 253.0), (6.4, 259.4), (-0.6, 259.4)], sym=True)
    sh = plan & side & front
    p.add(sh, 1)
    p.paint(sh & (Y >= 6), 2)
    return sh


def _beak(p, G, tip_y=-21.5, tip_z=250.2, side_z=253.6, hw=9.0):
    """이마판(부리): 위에서 화살촉, 옆에서 30° 로 내려가 끝남, 앞에서 아래 가장자리가 V(가운데가 낮음) — 바이저 위를 덮음."""
    X, Y, Z = G
    ax = np.abs(X)
    plan = poly(G, "z", [(-1.4, tip_y), (1.4, tip_y), (hw, -9), (hw, -2), (-hw, -2), (-hw, -9)])
    top = Z <= 258.9 - np.clip((-6 - Y), 0, None) * np.tan(np.radians(30)) + 0.2
    bottom = Z >= (tip_z + (side_z - tip_z) * np.clip(ax / hw, 0, 1)) + np.clip((Y + 2) * -0.0, 0, None)
    thick = Z >= 258.9 - np.clip((-6 - Y), 0, None) * np.tan(np.radians(30)) - 4.2
    p.add(plan & top & bottom & thick & (Y <= -2), 1)


def _visor(p, G, chev=(248.2,), slope=0.5):
    X, Y, Z = G
    ax = np.abs(X)
    outline = [(-0.6, 251.2), (6.0, 251.8), (5.4, 248.8), (0.6, 245.8), (-0.6, 245.8)]
    win = poly(G, "y", outline, sym=True)
    back = -12.6
    p.cut(win & (Y <= back) & (Y >= -26))
    p.add(win & (Y > back - 0.1) & (Y <= back + 1.3), 6)
    bars = np.zeros(np.broadcast_shapes(X.shape, Y.shape, Z.shape), bool)
    for z0 in chev:
        bars |= np.abs(Z - (z0 + slope * ax)) <= 0.45
    p.add(win & bars & (Y > back - 1.3) & (Y <= back - 0.1), 3)
    # 차양 밑면 짙게(그늘 선)


def _ears(p, G):
    Ga = _sym(G)
    p.add(cbox(Ga, (8.6, 10.8), (-6, 5), (243.0, 251.0), {"+xz": 1, "+xy": 1}), 2)          # 귀 블록
    for zz in (245.0, 247.5):
        p.add(box(Ga, (10.6, 11.4), (-4.5, 3.5), (zz - 0.45, zz + 0.45)), 4)


def _blade(p, G, sx, L=14.0, w=4.2, up=0.30):
    o = np.array([sx * 9.0, 2.0, 250.5])
    e1 = np.array([sx * 0.30, 1.0, up]); e2 = np.array([0.0, 0.0, 1.0])
    p.add(slab(G, o, e1, e2, [(0, -w / 2), (0, w / 2), (L * 0.55, w * 0.35), (L, 0.2), (L * 0.75, -w * 0.4)], h=(-1.0, 1.0)), 1)


def _back(p, G):
    Ga = _sym(G)
    for zz in (245.0, 248.0, 251.0):
        p.add(box(Ga, (2, 6.5), (11.0, 12.6), (zz - 0.6, zz + 0.6)), 4)


def head_R1(M):
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso"); G = _g(p)
    p.add(cyl(G, "z", (0, -2), 6.5, (224, 241)), 3)
    _shell(p, G)
    _ears(p, G)
    _visor(p, G)
    for sx in (1, -1):
        _blade(p, G, sx)
    _back(p, G)


def head_R2(M):
    p = M.part("Head", LO, HI, pivot=PIVOT, parent="Torso"); G = _g(p)
    X, Y, Z = G
    p.add(cyl(G, "z", (0, -2), 6.5, (224, 241)), 3)
    _shell(p, G)
    _ears(p, G)
    _visor(p, G)
    _blade(p, G, 1, L=19.0, w=5.0, up=0.55)
    p.add(cyl(G, "x", (-0.5, 247.5), 3.6, (-13.6, -10.0)), 2)                               # 오른쪽 원통 센서
    p.add(cyl(G, "x", (-0.5, 247.5), 2.2, (-14.4, -13.6)), 3)
    p.add(cbox(G, (2.6, 4.6), (-15.2, -13.0), (255.2, 256.8), {"xz": 0.6}), 6)               # 이마 한쪽 점 센서
    _back(p, G)


VARIANTS = {"R1 raptor + striker visor (sym)": head_R1, "R2 raptor + striker visor (asym)": head_R2}
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
    out = sys.argv[1] if len(sys.argv) > 1 else "raptor.png"
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
        ims = []
        for y, pc in ((0, 5), (34, 9), (-36, 14), (90, 4), (160, 14)):
            near = ("ShoulderL", "UpperArmL") if y == 90 else ()
            Bu = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n not in UPPER or n in near])
            ims.append(vp.render(Bu, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=8, ss=2, ao_amt=0.5, size=head_frame(M, y, pc)))
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        rows.append(vp.sheet(ims, [name + "  front", "3/4", "3/4 (other side, high)", "side", "back 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), M.parts["Head"].count(), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
