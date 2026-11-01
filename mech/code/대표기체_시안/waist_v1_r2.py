"""
waist_v1.py — 흉부 안 1(chest_heavy_v1, H1) 의 허리 빈 곳 메우기 비교 (2026-10-26)

  W0 안 1 그대로
  W1 콕핏만 늘림 : 콕핏 블록을 스커트 바로 위(z ~175)까지 내림, 아래로 갈수록 좁아지고 끝은 V, 가운데 이음선 1줄 추가
  W2 추천(층층 배 장갑) : 1단 콕핏 아랫단(약 10칸, 아래 V) → 2단 배 판(±14, 한 단 뒤) → 3단 배 판(±12, 더 뒤, 스커트 위에 겹침)
                          양옆은 짙은 뼈대 노출 유지, 판 사이 틈 뒤 깊숙이 주황 열
두 안 모두 옛 Torso 배 장갑(|x|≤24, y<-20, z166~205)을 비워 새 판이 보이게 한다.
"""
import numpy as np

import flagship_heavy as fh
import chest_heavy_v1 as c1
from flag_vox import box, cbox, poly


def _clear_old_belly(M):
    T = M.parts["Torso"]
    tx, ty, tz = T.g()
    T.cut((np.abs(tx) <= 24) & (ty < -20) & (tz >= 166) & (tz <= 205))


def waist_W1(M):
    p = M.parts["ChestNew"]
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    shape = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    front = poly(G, "y", [(-0.6, 174.5), (5, 174.5), (10, 182), (12.5, 192), (12.5, 210), (-0.6, 210)], sym=True)
    lo = np.broadcast_to(front, shape) & (Y <= -14) & \
        (Y >= -50.5 + ax * 0.22 + np.clip(184.0 - Z, 0, None) * 1.0) & (Z <= 208)
    p.add(lo, 1)
    p.paint_s(np.broadcast_to(lo & (np.abs(Z - 199.5) <= 0.5), shape), 3)        # 위·아래 해치 이음선


def waist_W2(M):
    p = M.parts["ChestNew"]
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    shape = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    # 1단: 콕핏 아랫단(아래 V, 아래로 갈수록 뒤로)
    front = poly(G, "y", [(-0.6, 193.5), (4.5, 193.5), (10.5, 199.5), (12.5, 204), (12.5, 210), (-0.6, 210)], sym=True)
    t1 = np.broadcast_to(front, shape) & (Y <= -14) & \
        (Y >= -50.5 + ax * 0.22 + np.clip(200.0 - Z, 0, None) * 1.0) & (Z <= 208)
    p.add(t1, 1)
    p.paint_s(np.broadcast_to(t1 & (np.abs(Z - 203.5) <= 0.5) & (Y <= -46), shape), 3)
    # 판 사이 틈 뒤 주황 열(먼저 넣고 판이 앞을 덮음)
    p.add(box(G, (-8, 8), (-30.6, -29.4), (181.0, 183.2)), 6)
    p.add(box(G, (-14, 14), (-27.4, -22), (172, 194)), 4)
    # 2단 배 판: 1단보다 한 단 뒤, 폭 ±14
    t2 = cbox(G, (-17, 17), (-44.5, -30.6), (183.4, 193.0), {"x-y": (5, 5), "-z-y": (2, 2), "+z-y": (1, 1)})
    p.add(t2, 1)
    p.paint_s(np.broadcast_to(t2 & (ax <= 0.6), shape), 3)
    # 3단 배 판: 더 뒤, 폭 ±12, 스커트 위에 겹침
    t3 = cbox(G, (-15, 15), (-40.5, -30.6), (171.5, 181.0), {"x-y": (4, 4), "-z-y": (2, 3), "+z-y": (1, 1)})
    p.add(t3, 1)
    # (10-26) 3단 판 뒤 짙은 연결 칸: 판(y≤-31)과 배 블록(y≥-27) 사이 3칸 틈을 이어 떠 있는 조각(섬)을 없앰. 앞에선 판에 가려 안 보임.
    p.add(box(G, (-10, 10), (-30.6, -27.4), (173, 180)), 4)


def waist_W3(M):
    """W2 + 2·3단 배 판을 옆구리까지 감쌈. 각 단: 앞판(±17/±15) 뒤로 한 단 물러난 옆 판이 바깥으로 갈수록 뒤로 꺾여
    옆면(|x| 28.5/26.5)까지 → 위에서 보면 U 자 띠. 바깥 앞 모서리 45° 모따기. 단 사이 틈은 옆까지 짙게 열어 둠."""
    waist_W2(M)
    p = M.parts["ChestNew"]
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    shape = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    yf2 = -41.0 + np.clip(ax - 13.0, 0, None) * 0.55
    w2 = (ax >= 13) & (ax <= 28.5) & (Z >= 183.4) & (Z <= 193.0) & (Y <= 8) & \
        (Y >= yf2 + np.clip(ax - 25.5, 0, None)) & (Z <= 193.0 - np.clip(ax - 27.5, 0, None))
    p.add(np.broadcast_to(w2, shape), 1)
    p.paint_s(np.broadcast_to(w2 & (np.abs(ax - 20.5) <= 0.5) & (Y <= -20), shape), 3)       # 옆 판 이음선
    yf3 = -37.0 + np.clip(ax - 11.0, 0, None) * 0.55
    w3 = (ax >= 11) & (ax <= 26.5) & (Z >= 171.5) & (Z <= 181.0) & (Y <= 6) & \
        (Y >= yf3 + np.clip(ax - 23.5, 0, None)) & (Z <= 181.0 - np.clip(ax - 25.5, 0, None))
    p.add(np.broadcast_to(w3, shape), 1)
    p.paint_s(np.broadcast_to(w3 & (np.abs(ax - 18.5) <= 0.5) & (Y <= -20), shape), 3)


MODES = {"W0 plan-1 as is": None, "W1 cockpit extended only": waist_W1, "W2 layered ab plates (recommended)": waist_W2,
         "W3 W2 + wrap to flanks": waist_W3}
UPPER = c1.UPPER + ("SkirtSL", "SkirtSR")


def build(mode):
    M = c1.build("H1")
    if MODES[mode] is not None:
        _clear_old_belly(M)
        MODES[mode](M)
    return M


if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    out = sys.argv[1] if len(sys.argv) > 1 else "waist.png"
    A = fh.SCHEMES["A"]

    def frame(M, yaw, pitch, names=("Head", "ChestNew", "SkirtFL", "SkirtFR", "Pelvis"), mx=14, top=6, bot=6):
        d, f, r, u = vp._basis(yaw, pitch)
        P = []
        for n in names:
            q = M.parts[n]
            Q = np.argwhere(q.a > 0) + q.lo
            T = M.world(n, fh.STANCE)
            P.append(Q @ T[:3, :3].T + T[:3, 3])
        P = np.concatenate(P)
        sx, sy = P @ r, P @ u
        cx = (sx.min() + sx.max()) / 2
        hh = (sy.max() + top) - (sy.min() - bot)
        half = max((sx.max() - sx.min()) / 2 + mx, hh * 0.5)
        return ((cx - half, cx + half), (sy.min() - bot, sy.max() + top))

    rows = []
    for name in (sys.argv[2:] or list(MODES)):
        M = build(name)
        ims = []
        for y, pc in ((0, 5), (32, 9), (-34, 12), (90, 3), (150, 12)):
            near = ("ShoulderL", "UpperArmL", "LowerArmL") if y == 90 else ()
            skip = [n for n in M.parts if n not in UPPER or n in near]
            Bu = M.blocks(pose=fh.STANCE, skip=skip)
            ims.append(vp.render(Bu, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=3.6, ss=2, ao_amt=0.5, size=frame(M, y, pc)))
        Bf = M.blocks(pose=fh.STANCE)
        fulls = [vp.render(Bf, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=1.6, ss=2, ao_amt=0.5) for y, pc in ((0, 4), (30, 6))]
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        fulls = [f_.resize((int(f_.width * H / f_.height), H), Image.LANCZOS) for f_ in fulls]
        rows.append(vp.sheet(ims + fulls, [name + "  front", "3/4", "3/4 (other side)", "side", "back 3/4", "full front", "full 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
