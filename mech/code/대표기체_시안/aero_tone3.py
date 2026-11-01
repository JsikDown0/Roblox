"""
aero_tone3.py — 정면에서 가슴 역삼각형이 '사각형'으로 뭉쳐 보이는 문제 시안 (2026-10-26 22:24~)

원인 [실측: 정면 맨 앞 칸, aero_export 자세]: 가슴 역삼각형(ChestL/R 아랫가슴 V — W1 에서 FRAME) 바깥은 비어 있고, 약 35칸 뒤의
  등 바인더·백팩 앞면(같은 검회색)이 틈으로 보임 → 정면 검회색 = 몸통 968칸 + 등 부품 1,158칸이 한 덩어리.
  그림자·AO 가 있는 렌더(aero_stow_r1)에선 뒤가 어두워져 삼각형이 떴음. 로블록스 기본 조명엔 AO 가 없음 [추측].
유저(22:24): "등 부분 부품(백팩)을 흰색으로 한 것과 3번 시안 보여줄래?"
  B = 등 부품(Backpack · BinderL/R)의 앞을 보는 면(바로 앞 칸이 빈 칸)만 검회색 → 흰색. 뒤·옆에서 보이는 면은 그대로.
      (등 전체를 흰색으로 하는 건 아님 — 해석을 답에 밝힘)
  C = 가슴 역삼각형(ChestL/R 아랫가슴 V, 검회색 칸) → 밝은 회색. 아래 변 금속 한 줄은 그대로(판 끝이 보이게).
      W2 시안(아랫가슴 주황)과 같은 자리 — 색만 다름.
"""
import numpy as np

import aero_export as E

WHITE, LGRAY, FRAME = 2, 10, 3
BACK = ("Backpack", "BinderL", "BinderR")


def front_faces(p):
    """파트 안에서 바로 앞(-Y) 칸이 비어 있는 칸."""
    a = p.a
    nb = np.zeros_like(a)
    nb[:, 1:, :] = a[:, :-1, :]               # y-1 칸
    return (a > 0) & (nb == 0)


def back_white(M):
    n = 0
    for name in BACK:
        p = M.parts[name]
        m = front_faces(p) & (p.a == FRAME)
        p.a[m] = WHITE; n += int(m.sum())
    return n


def chest_light(M):
    n = 0
    for name in ("ChestL", "ChestR"):
        p = M.parts[name]
        G = p.g(); X, Y, Z = G
        sx = 1 if name == "ChestL" else -1
        xl = sx * X                                                     # 미러 파트도 같은 식(바깥 = +)
        zc = np.where(xl <= 20, 216 + 0.5 * xl, 226 + (xl - 20))         # aero_upper_w.chest 의 발광 띠 중심선
        lo = (xl >= 0) & (xl <= 23) & (Z >= 202 + xl) & (Z <= zc - 2.5) & (Y >= -23) & (Y <= -20)
        m = np.broadcast_to(lo, p.a.shape) & (p.a == FRAME)
        p.a[m] = LGRAY; n += int(m.sum())
    return n


VARIANTS = (("A  now", None), ("B  back parts white (front faces)", back_white), ("C  chest triangle light gray", chest_light))


def build(kind="A"):
    M = E.build(tone=False)                              # 22:29 B 채택 뒤 E.build() 는 B 를 기본으로 칠함 → 시안 비교는 칠하기 전 것에서
    f = dict(A=None, B=back_white, C=chest_light)[kind]
    if f:
        f(M)
    return M


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    import aero_r1 as A
    import aero_colors as Cc
    from PIL import Image, ImageDraw
    t0 = time.time()
    out = sys.argv[1]
    pal = Cc.SCHEMES[E.SCHEME]

    def flat(M, pose, X0=-70, X1=70, Z0=150, Z1=290, S=3):
        H, W = Z1 - Z0, X1 - X0
        dep = np.full((H, W), np.inf); col = np.zeros((H, W), int)
        for n, p in M.parts.items():
            ijk = np.argwhere(p.a > 0); c = p.a[p.a > 0]; T = M.world(n, pose); P = (ijk + p.lo) @ T[:3, :3].T + T[:3, 3]
            xi = np.round(P[:, 0]).astype(int) - X0; zi = np.round(P[:, 2]).astype(int) - Z0; y = P[:, 1]
            ok = (xi >= 0) & (xi < W) & (zi >= 0) & (zi < H); o = np.argsort(-y[ok])
            xi, zi, y, c = xi[ok][o], zi[ok][o], y[ok][o], c[ok][o]
            m = y < dep[zi, xi]; dep[zi[m], xi[m]] = y[m]; col[zi[m], xi[m]] = c[m]
        img = np.full((H, W, 3), (13, 14, 17), np.uint8)
        for n, rgb in pal.items():
            img[col == n] = rgb
        return Image.fromarray(np.kron(img[::-1], np.ones((S, S, 1), np.uint8)))

    rows = []
    for k, (lab, f) in zip("ABC", VARIANTS):
        M = build(k)
        if f:
            print(k, "cells changed", f(E.build(tone=False)), flush=True)
        B = M.blocks(pose=A.STANCE)
        ims = [flat(M, E.REST_POSE)]
        ims += [vp.render(B, pal, A.EMISSIVE, yaw=y, pitch=p, ppc=pc, ss=2, size=sz, ao_amt=0.5)
                for y, p, pc, sz in ((0, 4, 3.0, ((-70, 70), (150, 290))), (20, 6, 1.5, ((-120, 120), (-10, 320))), (150, 10, 1.5, ((-120, 120), (-10, 320))))]
        rows.append(vp.sheet(ims, ["%s  flat (no light)" % lab, "front (lit)", "3/4", "back 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
