"""
aero_heads.py — Aero 머리 2차: 블록 머리 쌓는 방식(유저 타임랩스 5:14~)으로 다시 (2026-10-26)

영상에서 가져온 것 = 쌓는 방식만(그 기체 머리 모양은 옮기지 않음):
  ① 투구 껍질이 얼굴을 U 자로 감싸고, 얼굴은 껍질보다 한참 안쪽에 따로 앉는다 → 둘레에 그늘 틈
  ② 머리통은 층마다 한 칸씩 들어가는 계단 돔(둥근 투구 실루엣) — 상자 머리 금지
  ③ 투구 앞 끝(눈썹)이 얼굴 위로 처마처럼 나와 눈이 그늘 속에
  ④ 얼굴 양옆을 볼 가드 판이 따로 막음 · 정수리 가운데 낮은 능선
  ⑤ 머리 크기를 r1 보다 키움(높이 26 → 30, 폭 22 → 28)
얼굴: 부리처럼 앞·아래로 모이는 마스크(위에서 45°, 앞에서 V 턱) + 처마 밑 좁은 V 바이저 1줄.
안 3개는 깃만 다름: H1 높은 깃(위·뒤 52°) · H2 누운 깃(22°) · H3 한쪽 깃(왼쪽만 길게 + 오른쪽 센서 토막).
"""
import numpy as np

import flag_vox as fv
from flag_vox import box, cbox, poly, cyl, ell, rotx, roty, rotz
import aero_r1 as A

PIVOT = (0, -4, 240)


def head_base(M):
    M.parts.pop("Head", None)
    p = M.part("Head", (-18, -32, 232), (19, 22, 276), pivot=PIVOT, parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cyl(G, "z", (0, -2), 5, (234, 248)), 3)                                  # 목
    p.add(cbox(G, (-9, 9), (-12, 9), (241, 263), {"xy": 3}), 3)                    # 속(짙게 — 틈으로 보임)
    # ② 계단 돔 투구 + ① 앞을 크게 연 껍질
    dome = ell(G, (0, -3, 250), (13.5, 19, 17)) & (Z >= 245)
    back = cbox(G, (-12, 12), (-2, 13), (241, 252), {"xy": 4, "-z+y": 3})
    shell = (dome | back) & ~ell(G, (0, -3, 250), (10, 15.5, 13.5))
    face_open = (Y <= -5) & (Z <= 255) & (ax <= 10.5)
    helm = shell & ~face_open
    p.add(helm, 1)
    p.paint(helm & (Y >= 6) & (Z <= 252), 3)                                       # 뒷머리 아래 프레임
    # 뒷머리 시그니처: 가로 배기 홈 하나(뒤 카메라용)
    p.cut(box(G, (-6, 6), (11, 14), (246, 247)))
    p.add(box(G, (-6, 6), (10, 10), (246, 247)), 4)
    # ⑤ 얼굴(흰 마스크): 투구 앞 끝보다 안쪽. 아래는 부리처럼 앞으로 모임
    # 앞면은 평평(45° 쐐기면은 세로 줄무늬 = 수염처럼 읽힘 — v2), 가장자리만 45° 모따기
    low = cbox(G, (-8, 8), (-18, 4), (238, 249), {"x-y": 3, "+z-y": 2}) & (ax <= 8 - np.maximum(0, 244 - Z))   # 앞에서 V 턱
    up = cbox(G, (-8, 8), (-14, 4), (249, 255), {"x-y": 2})
    p.add(low | up, 2)
    p.add(cbox(G, (-1, 1), (-20, -18), (239, 249), {"-y+z": 2}) & (Z >= 239 + np.abs(X)), 2)   # 가운데 부리 능선(한 줄)
    # ③ 처마 밑 V 바이저 1줄(가운데 낮고 바깥이 높은 1:2) — 발광은 여기만
    p.cut(box(G, (-7, 7), (-16, -12), (250, 254)) & (low | up))
    p.add(box(G, (-7, 7), (-12, -12), (250, 254)), 4)
    p.add(box(G, (-6, 6), (-13, -13), (251, 251)), 6)        # 가로 바이저 1줄(V 로 올리면 웃는 눈 — v2)
    # ④ 볼 가드: 얼굴 양옆을 막는 판(앞 아래 45°), 투구 옆면보다 한 칸 바깥
    for s in (1, -1):
        xr = (12, 15) if s > 0 else (-15, -12)
        p.add(cbox(G, xr, (-20, 6), (244, 256), {"-z-y": 7, "+z-y": 2, "y+z": 2}), 2)
    # 정수리 가운데 낮은 능선(색 그대로 — 형태만)
    p.emboss(box(G, (-1, 1), (-21, 8), (258, 272)) & (Z >= 258), 1)
    return p


def _fin(M, name, side, prof, rng, rot, color, pivot):
    """세워 만든 얇은 깃을 회전으로 눕힌다(긴 변이 계단 없이 남게)."""
    x0, x1 = rng
    if side < 0:
        x0, x1 = -x1, -x0
    p = M.part(name, (x0 - 1, -20, 248), (x1 + 2, 40, 310), pivot=(side * pivot[0], pivot[1], pivot[2]), parent="Head")
    G = p.g()
    p.add(poly(G, "x", prof, rng=(x0, x1)), color)
    p.rot = rot
    return p


FIN_MAIN = [(-8, 257), (10, 257), (10, 280), (2, 296), (-8, 276)]        # 넓은 칼날, 끝 1:2
FIN_SUB = [(0, 257), (12, 257), (12, 274), (6, 286), (0, 274)]           # 뒤 보조 깃(짧게)
FIN_STUB = [(-4, 257), (6, 257), (6, 266), (-4, 262)]


def fins(M, kind):
    for n in ("FinL", "FinR", "FinSubL", "FinSubR"):
        M.parts.pop(n, None)
    if kind == "H1":     # 높은 깃: 위·뒤로 52°, 위가 바깥으로 12°
        for s, sfx in ((1, "L"), (-1, "R")):
            _fin(M, "Fin" + sfx, s, FIN_MAIN, (12, 14), roty(12 * s) @ rotx(-38) @ rotz(-25 * s), 1, (13, 1, 258))
            _fin(M, "FinSub" + sfx, s, FIN_SUB, (11, 11), roty(12 * s) @ rotx(-44) @ rotz(-25 * s), 2, (11, 1, 258))
    elif kind == "H2":   # 누운 깃: 22°, 매처럼 머리 뒤로
        for s, sfx in ((1, "L"), (-1, "R")):
            _fin(M, "Fin" + sfx, s, FIN_MAIN, (12, 14), roty(6 * s) @ rotx(-68) @ rotz(-10 * s), 1, (13, 1, 258))
            _fin(M, "FinSub" + sfx, s, FIN_SUB, (11, 11), roty(6 * s) @ rotx(-72) @ rotz(-10 * s), 2, (11, 1, 258))
    elif kind == "H3":   # 한쪽 깃: 왼쪽만 길게, 오른쪽은 센서 토막(비대칭)
        long_ = [(-8, 257), (10, 257), (10, 288), (2, 304), (-8, 284)]
        _fin(M, "FinL", 1, long_, (12, 14), roty(12) @ rotx(-42) @ rotz(-25), 1, (13, 1, 258))
        _fin(M, "FinSubL", 1, FIN_SUB, (11, 11), roty(12) @ rotx(-48) @ rotz(-25), 2, (11, 1, 258))
        _fin(M, "FinR", -1, FIN_STUB, (12, 14), rotx(-30), 3, (12, 1, 258))


def build(kind="H1"):
    M = A.build_all()
    head_base(M)
    fins(M, kind)
    return M


def build_all():
    return build("H1")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["r1", "H1", "H2", "H3"]
    up = {"Head", "Torso", "ChestPlate", "ShoulderL", "ShoulderR", "Backpack", "WingL", "WingR",
          "UpperArmL", "UpperArmR", "FinL", "FinR", "FinSubL", "FinSubR", "Pelvis"}
    rows = []
    for k in kinds:
        M = A.build_all() if k == "r1" else build(k)
        Bc = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in up])
        Bf = M.blocks(pose=A.STANCE)
        ims = [vp.render(Bc, A.SCHEMES["A"], A.EMISSIVE, yaw=y, pitch=p, ppc=6, ss=2, size=((-36, 36), (220, 304)), ao_amt=0.5)
               for y, p in ((0, 4), (30, 8), (90, 4), (150, 14))]
        ims += [vp.render(Bf, A.SCHEMES["A"], A.EMISSIVE, yaw=y, pitch=p, ppc=1.8, ss=2, size=((-110, 110), (-10, 320)), ao_amt=0.5)
                for y, p in ((30, 6), (150, 12))]
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back 3/4", "full 3/4", "full back"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
