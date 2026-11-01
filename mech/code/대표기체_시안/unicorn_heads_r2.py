"""
unicorn_heads.py — 쐐기 머리 + 스트라이커 바이저(raptor_heads R 계열) 에 이마 가운데 칼날 뿔 하나 (2026-10-26)
  U1 앞으로 선 뿔 : 이마(부리 윗면)에서 위·살짝 앞으로(약 75°) — 유니콘식
  U2 뒤로 누운 뿔 : 같은 뿌리에서 위·뒤로(약 65°) — 머리 능선을 이어받는 볏처럼
귀 블레이드는 뺌(돌출부 1개 원칙). 뿔은 옆에서 넓고 앞에서 얇은 판, 끝은 뾰족.
"""
import numpy as np

import flagship_heavy as fh
from flag_vox import cbox, cyl, slab
from heavy_heads import PIVOT
import raptor_heads as rh


def _horn(p, G, d, L=26.0, w=7.0, t=1.4):
    o = np.array([0.0, -15.5, 254.0])
    e1 = np.array(d, float); e2 = np.array([0.0, 1.0, 0.0])
    p.add(slab(G, o, e1, e2, [(0, -w / 2), (0, w / 2), (L * 0.45, w * 0.28), (L, 0.15), (L * 0.7, -w * 0.3)], h=(-t, t)), 1)
    p.add(cbox(G, (-2.6, 2.6), (-19.0, -11.0), (251.5, 256.0), {"+zx": 1.0, "+z-y": (1.5, 1.5)}), 1)      # 뿌리 받침


def _base(M):
    p = M.part("Head", rh.LO, rh.HI, pivot=PIVOT, parent="Torso"); G = rh._g(p)
    p.add(cyl(G, "z", (0, -2), 6.5, (224, 241)), 3)
    rh._shell(p, G)
    rh._ears(p, G)
    rh._visor(p, G)
    rh._back(p, G)
    return p, G


def head_U1(M):
    p, G = _base(M)
    _horn(p, G, (0.0, -0.26, 1.0))


def head_U2(M):
    p, G = _base(M)
    _horn(p, G, (0.0, 0.48, 1.0), L=27.0)


def head_U2m(M):
    p, G = _base(M)
    _horn(p, G, (0.0, 0.52, 1.0), L=20.0, w=6.6)


def head_U2s(M):
    p, G = _base(M)
    _horn(p, G, (0.0, 0.56, 1.0), L=15.5, w=6.2)


rh.VARIANTS.clear()
rh.VARIANTS.update({"U2 horn L27 (before)": head_U2, "U2 horn L20 (-25%)": head_U2m, "U2 horn L15.5 (-40%)": head_U2s})

if __name__ == "__main__":
    VARIANTS = rh.VARIANTS; UPPER = rh.UPPER; build = rh.build
    import numpy as np
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
