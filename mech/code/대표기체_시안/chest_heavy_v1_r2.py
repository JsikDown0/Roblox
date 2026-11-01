"""
chest_heavy_v1.py — r2 흉부 중장갑 양식 [안 1: 첫 판] (2026-10-26)
유저가 최종판(chest_heavy.py, 안 2)과 함께 이 첫 판의 H1(위쪽 줄)도 마음에 들어 해서 따로 보관.
안 1 특징: 흉판 윗면 30° 후드, 가운데 콕핏 블록 앞면에 두 칸 센서 슬릿, 흉판 처마 밑 열 배출구 2개(주황 살).
실행: python3 chest_heavy_v1.py out.png  (H1 만: python3 chest_heavy_v1.py out.png "H1 center prow + sensor slit")

(원래 설명)

레퍼런스(유저 제공 2장) 공통 양식:
  - 흉부가 배 위로 크게 튀어나온 처마(앞 아랫단이 배보다 18칸 앞) → 밑에 깊은 그늘.
  - 좌우 큰 흉판 두 덩어리, 윗면은 높은 깃에서 앞으로 약 30° 내려가는 후드.
  - 모서리를 깎은 육각 판 + 안쪽 판 테두리 홈(2단 판).
  - 배는 짙고 좁은 마디 구조(뼈대 노출).
  - 발광은 '틈 안에서' — 센서 슬릿, 흉판 처마 밑 열 배출구. 테두리·외곽선 발광 없음.
  H1 가운데 함수(콕핏 블록)가 흉판 사이로 가장 앞에 튀어나옴 + 가로 센서 슬릿
  H2 함수 없이 흉판 두 장이 맞물린 후드 + 왼쪽 흉판에만 센서 슬릿(비대칭)
머리는 U2(뒤로 누운 뿔, 길이 20).
"""
import numpy as np

import flagship_heavy as fh
from flag_vox import box, cbox, poly
import unicorn_heads as uh


def build_chest(M, variant="H1"):
    p = M.part("ChestNew", (-48, -58, 166), (49, 26, 252), pivot=(0, -30, 210), parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    shape = np.broadcast_shapes(X.shape, Y.shape, Z.shape)

    def B(m):
        return np.broadcast_to(m, shape)

    yf = -44.0 + np.clip(ax - 14.0, 0, None) * 0.30          # 흉판 앞면(바깥으로 물러나는 얕은 V)
    ztop = np.minimum(242.0, 242.0 - 0.58 * (-10.0 - Y))      # 후드: 깃(z242, y-10)에서 앞으로 약 30° 내려감
    ztop = ztop - np.clip(ax - 30.0, 0, None) * 0.9           # 바깥 윗모서리 깎음
    zbot = 205.0 + np.clip(ax - 34.0, 0, None) * 1.0          # 바깥 아랫모서리 깎음
    pec = (ax >= 2.0) & (ax <= 41) & (Y <= 16) & (Z <= ztop) & (Z >= zbot) & \
          (Y >= yf + np.clip(209.5 - Z, 0, None) * 0.9) & \
          (Y >= yf + np.clip(ax - 34.0, 0, None) * 1.1)
    p.add(pec, 1)
    # 2단 판: 후드 윗면에 안쪽 판 테두리 홈(육각)
    outer = (ax >= 7) & (ax <= 33) & (Y >= yf + 3) & (Y <= -14)
    inner = (ax >= 8.6) & (ax <= 31.4) & (Y >= yf + 4.6) & (Y <= -15.6)
    cut_c = (ax - 7) + (Y - (yf + 3)) >= 4                     # 앞 안쪽 모서리 깎은 육각
    p.paint_s(B(outer & ~inner & cut_c & (Z >= 214)), 3)
    p.paint_s(B(pec & (np.abs(Z - 209.6) <= 0.5) & (Y <= yf + 3)), 3)          # 처마 앞단 이음선
    # 처마 밑 열 배출구(짙은 함 + 가로 살 + 안쪽 주황 빛)
    vent = (ax >= 15) & (ax <= 34) & (Z >= 195.5) & (Z <= 205) & (Y >= yf + 3.5) & (Y <= -22)
    p.add(vent, 4)
    for z0 in (197.0, 200.6):
        sl = (ax >= 17) & (ax <= 32) & (Z >= z0) & (Z <= z0 + 2.0)
        p.cut(sl & (Y >= yf + 3.4) & (Y < yf + 6.5))
        p.add(sl & (Y >= yf + 6.5) & (Y <= yf + 7.5), 6)
    # 배: 짙고 좁은 마디(뒤로 물러남)
    for k, z0 in enumerate(range(174, 197, 5)):
        hw = 18 - k * 0.0
        p.add(cbox(G, (-hw, hw), (-26 + (k % 2) * 1.2, 10), (z0, z0 + 3.6), {"x-y": (3, 3)}), 3 if k % 2 == 0 else 2)
    p.add(box(G, (-14, 14), (-22, 8), (172, 197)), 4)
    p.add(box(G, (-42, 42), (-28, 14), (203.0, 205.0)) & B(~pec), 3)        # 흉판 밑 짙은 받침
    if variant == "H1":
        # 가운데 함수(콕핏 블록): 흉판보다 6칸 앞, 앞면 육각, 밑은 깎음
        front = poly(G, "y", [(-0.6, 203), (8, 203), (12.5, 208), (12.5, 230), (8, 236), (-0.6, 236)], sym=True)
        prow = B(front) & (Y >= -50.5 + ax * 0.22 + np.clip(207.5 - Z, 0, None) * 1.0) & (Y <= -12) & \
            (Z <= ztop + 2.5)
        p.cut(B((ax < 2.0) & (Y < -12) & (Z > 205)))                                # 흉판 사이 틈
        p.add(B((ax < 2.0) & (Y >= -36) & (Y < -12) & (Z > 205) & (Z <= ztop)), 4)
        p.add(prow, 1)
        p.paint_s(B(prow & (np.abs(Z - 214.5) <= 0.5)), 3)                          # 함수 가로 이음선
        # 가로 센서 슬릿(두 칸, 가운데 칸막이)
        sl = (ax >= 1.4) & (ax <= 8.6) & (Z >= 222.5) & (Z <= 225.5)
        p.cut(B(sl & (Y < -47.5 + ax * 0.22)))
        p.add(B(sl & (Y >= -47.5 + ax * 0.22) & (Y <= -46.5 + ax * 0.22)), 6)
    else:
        # 흉판 두 장이 가운데에서 맞물림: 가운데 짙은 홈만
        p.add(B((ax < 2.0) & (Y >= -40) & (Y <= -12) & (Z >= 206) & (Z <= ztop - 1)), 4)
        # 왼쪽(+X) 흉판에만 가로 센서 슬릿(두 칸)
        Xs = X
        sl = (Xs >= 12) & (Xs <= 26) & (Z >= 213.0) & (Z <= 215.6) & (np.abs(Xs - 19) >= 0.8)
        yfx = -44.0 + np.clip(np.abs(Xs) - 14.0, 0, None) * 0.30
        p.cut(B(sl & (Y < yfx + 2.2)))
        p.add(B(sl & (Y >= yfx + 2.2) & (Y <= yfx + 3.2)), 6)
        p.add(B((Xs >= 11) & (Xs <= 27) & (Z >= 212.0) & (Z <= 216.6) & (Y >= yfx + 3.2) & (Y <= yfx + 4.4)), 4)
    return p


def build(variant):
    M = fh.build_all()
    del M.parts["ChestPlate"]
    del M.parts["Head"]
    uh.head_U2m(M)
    build_chest(M, variant)
    return M


VARIANTS = {"H1 center prow + sensor slit": "H1", "H2 hood pecs + asym slit": "H2"}
UPPER = ("Head", "Torso", "ChestNew", "ShoulderL", "ShoulderR", "Backpack", "UpperArmL", "UpperArmR", "Pelvis",
         "SkirtFL", "SkirtFR")

if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    out = sys.argv[1] if len(sys.argv) > 1 else "chest_heavy.png"
    only = sys.argv[2:] or list(VARIANTS)
    A = fh.SCHEMES["A"]

    def frame(M, yaw, pitch, names=("Head", "ChestNew"), mx=14, top=6, bot=8):
        d, f, r, u = vp._basis(yaw, pitch)
        P = []
        for n in names:
            q = M.parts[n]
            Q = np.argwhere(q.a > 0) + q.lo
            T = M.world(n)
            P.append(Q @ T[:3, :3].T + T[:3, 3])
        P = np.concatenate(P)
        sx, sy = P @ r, P @ u
        cx = (sx.min() + sx.max()) / 2
        hh = (sy.max() + top) - (sy.min() - bot)
        half = max((sx.max() - sx.min()) / 2 + mx, hh * 0.62)
        return ((cx - half, cx + half), (sy.min() - bot, sy.max() + top))

    rows = []
    for name in only:
        M = build(VARIANTS[name])
        ims = []
        for y, pc in ((0, 5), (32, 9), (-34, 12), (90, 3)):
            near = ("ShoulderL", "UpperArmL") if y == 90 else ()
            Bu = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n not in UPPER or n in near])
            ims.append(vp.render(Bu, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=4.5, ss=2, ao_amt=0.5, size=frame(M, y, pc)))
        Bf = M.blocks(pose=fh.STANCE)
        fulls = [vp.render(Bf, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=1.6, ss=2, ao_amt=0.5) for y, pc in ((0, 4), (30, 6))]
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        fulls = [f_.resize((int(f_.width * H / f_.height), H), Image.LANCZOS) for f_ in fulls]
        rows.append(vp.sheet(ims + fulls, [name + "  front", "3/4", "3/4 (other side)", "side", "full front", "full 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
