"""
chest_heavy.py — r2 흉부 중장갑 양식 [안 2: 최종판, H1 선택] (2026-10-26)
안 2 특징: 흉판 윗면 평평 + 45° 모따기만, 콕핏 블록엔 이음선만, 센서 슬릿은 왼쪽 흉판에만, 배 마디 틈 뒤 주황 열. build() 가 옛 Torso 배 장갑을 cut 함.
안 1(첫 판)은 chest_heavy_v1.py.

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

    # 흉판: 큰 면 + 45° 모따기만(계단 줄무늬 최소). 윗면 평평(z233), 앞 윗모서리 45° 로 앞면(z223)까지.
    yf = -44.0 + np.clip(ax - 14.0, 0, None) * 0.30
    ztop = np.where(Y >= -34, 233.0, 233.0 - (-34.0 - Y)) - np.clip(ax - 33.0, 0, None)
    zbot = 205.0 + np.clip(ax - 35.0, 0, None)
    pec = (ax >= 2.0) & (ax <= 41) & (Y <= 16) & (Z <= ztop) & (Z >= zbot) & \
          (Y >= yf + np.clip(209.0 - Z, 0, None)) & (Y >= yf + np.clip(ax - 33.0, 0, None))
    p.add(pec, 1)
    # 2단 판: 윗면 안쪽 판 테두리 홈(앞 안쪽 모서리 깎은 육각) + 앞면 처마 이음선
    outer = (ax >= 7) & (ax <= 32) & (Y >= -33) & (Y <= -14)
    inner = (ax >= 8.6) & (ax <= 30.4) & (Y >= -31.4) & (Y <= -15.6)
    cut_c = (ax - 7) + (Y + 33) >= 5
    p.paint_s(B(outer & ~inner & cut_c & (Z >= 230)), 3)
    p.paint_s(B(pec & (np.abs(Z - 211.5) <= 0.5) & (Y <= yf + 3)), 3)
    # 흉판 밑 짙은 받침(처마 그늘)
    p.add(B((ax <= 40) & (Y >= -30) & (Y <= 14) & (Z >= 199) & (Z <= 205)) & B(~pec), 3)
    # 배: 짙은 마디 판(앞) + 그 뒤 깊숙이 주황 열(마디 틈으로만 보임)
    p.add(box(G, (-14, 14), (-22, 8), (171, 199)), 4)
    p.add(box(G, (-9, 9), (-22.4, -21.2), (172, 198)), 6)
    for k, z0 in enumerate(range(173, 197, 5)):
        p.add(cbox(G, (-18, 18), (-26.5 + (k % 2) * 1.0, -22.6), (z0, z0 + 3.4), {"x-y": (3, 3)}), 3 if k % 2 == 0 else 2)
        p.add(cbox(G, (-18, 18), (-22.6, 10), (z0, z0 + 3.4), {"x+y": (3, 3)}) & B((ax >= 9.6)), 3)
    # 가운데
    if variant == "H1":
        # 함수(콕핏 블록): 흉판보다 6칸 앞, 육각 앞면(45° 모따기), 가로 이음선 한 줄 — 점·슬릿 없음(얼굴 방지)
        p.cut(B((ax < 2.0) & (Y < -12) & (Z > 205)))
        p.add(B((ax < 2.0) & (Y >= -36) & (Y < -12) & (Z > 205) & (Z <= ztop)), 4)
        prow = (ax <= 12.5) & (Z >= 204) & (Z <= 235) & (Y <= -12) & \
            (Y >= -50.5 + np.clip(208.5 - Z, 0, None) + np.clip(Z - 229.0, 0, None) + np.clip(ax - 8.5, 0, None)) & \
            (Z <= 235 - np.clip(ax - 8.5, 0, None)) & (Z >= 204 + np.clip(ax - 8.5, 0, None))
        p.add(B(prow), 1)
        p.paint_s(B(prow & (np.abs(Z - 219.5) <= 0.5) & (Y <= -44)), 3)
    else:
        # 흉판 두 장이 가운데에서 맞물림: 가운데 짙은 홈
        p.add(B((ax < 2.0) & (Y >= -42) & (Y <= -12) & (Z >= 206) & (Z <= ztop - 1)), 4)
    # 왼쪽(+X) 흉판에만 가로 센서 슬릿(두 칸, 비대칭) — 앞면 처마 위
    yfx = -44.0 + np.clip(np.abs(X) - 14.0, 0, None) * 0.30
    sl = (X >= 15) & (X <= 29) & (Z >= 215.0) & (Z <= 217.6) & (np.abs(X - 22) >= 0.8)
    p.cut(B(sl & (Y < yfx + 2.2)))
    p.add(B(sl & (Y >= yfx + 2.2) & (Y <= yfx + 3.2)), 6)
    p.add(B((X >= 14) & (X <= 30) & (Z >= 214.0) & (Z <= 218.6) & (Y >= yfx + 3.2) & (Y <= yfx + 4.4)), 4)
    return p


def build(variant):
    M = fh.build_all()
    del M.parts["ChestPlate"]
    del M.parts["Head"]
    # 옛 배 장갑·몸통 속 앞부분을 비워 새 배 마디 틈(주황 열)이 보이게
    T = M.parts["Torso"]
    tx, ty, tz = T.g()
    T.cut((np.abs(tx) <= 24) & (ty < -20) & (tz >= 166) & (tz <= 205))
    uh.head_U2m(M)
    build_chest(M, variant)
    return M


VARIANTS = {"H1 center prow (cockpit) + asym slit": "H1", "H2 merged pecs + asym slit": "H2"}
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
