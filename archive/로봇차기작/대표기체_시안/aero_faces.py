"""
aero_faces.py — Aero 얼굴 3차: 각진 면으로 깎은 머리 (2026-10-26 12:25~)

유저(H1~H3 를 보고): "뿔도 너무 크고 넓적한 단순한 형태, 가운데 투구도 헬멧 같음, 눈도 ㅡ 자 단일" → 얼굴만 집중.
고친 방향:
  ① 둥근 돔 투구 → 판 여러 장을 각지게 맞댄 머리. 판마다 세워(축 정렬) 만들고 파트 회전으로 기울인다
     → 면이 계단 없이 평평하게 남고, 판끼리 만나는 선이 날카로운 능선이 된다(가슴 셰브론과 같은 방법).
  ② 깃 = 작고 좁은 칼날(H1 길이의 약 60%·폭 절반), 뒤 변에 한 단 꺾인 턱 + 앞 변 흰 날 + 가운데 접힌 능선, 뒤에 짧은 보조 깃.
  ③ 눈 = 두 눈. V 로 꺾인 눈썹 판 밑 그늘에 놓아 노려보게.
안 3개:
  F1 사선 두 눈(안쪽이 낮음) + 깃 위·뒤 60°
  F2 사선 두 눈 + 깃을 볼 판에서 뒤로 눕혀 뻗음(30°, 2단 깃)
  F3 짧은 가로 두 눈 + 깊은 V 눈썹 + 깃 위·뒤 60° 를 더 작게
"""
import numpy as np

import flag_vox as fv
from flag_vox import box, cbox, poly, cyl, rotx, roty, rotz
import aero_r1 as A

PIVOT = (0, -4, 240)
HEAD_PARTS = []


def _slab(M, name, x, y, z, rot, pivot, c, ch=None, extra=None, parent="Head"):
    lo = (min(x) - 3, min(y) - 3, min(z) - 3)
    hi = (max(x) + 4, max(y) + 4, max(z) + 4)
    p = M.part(name, lo, hi, pivot=pivot, parent=parent)
    G = p.g()
    m = cbox(G, x, y, z, ch) if ch else box(G, x, y, z)
    if extra is not None:
        m = m & extra(G)
    p.add(m, c)
    p.rot = rot
    HEAD_PARTS.append(name)
    return p


def _pair(M, base, *a, **k):
    _slab(M, base + "L", *a, **k)
    M.mirror(base + "L", base + "R", "Head")
    HEAD_PARTS.append(base + "R")


def head_core(M, eyes="slant"):
    for n in list(M.parts):
        if n == "Head" or n.startswith("Fin") or n.startswith("H_"):
            M.parts.pop(n)
    HEAD_PARTS.clear()
    p = M.part("Head", (-14, -24, 232), (15, 14, 270), pivot=PIVOT, parent="Torso")
    HEAD_PARTS.append("Head")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.add(cyl(G, "z", (0, -2), 5, (234, 246)), 3)                                      # 목
    p.add(cbox(G, (-9, 9), (-15, 9), (241, 263), {"xy": 3, "+zx": 3}), 3)             # 속 뼈대(짙게)
    p.add(box(G, (-8, 8), (-16, -15), (247, 254)), 4)                                 # 눈 홈 바닥(검정)
    if eyes == "slant":      # 사선 두 눈: 안쪽 끝이 낮음, 가운데 2칸 비움
        e = (ax >= 2) & (ax <= 7) & (Z >= 249 + 0.5 * (ax - 2) - 0.5) & (Z <= 249.6 + 0.5 * (ax - 2))
        p.add(e & (Y >= -17) & (Y <= -17), 6)
    else:                    # 짧은 가로 두 눈
        p.add(((ax >= 3) & (ax <= 6)) & (Y >= -17) & (Y <= -17) & (Z >= 250) & (Z <= 250), 6)
    # 뒷머리: 가로 배기 홈(뒤 카메라용 시그니처)
    p.add(cbox(G, (-8, 8), (8, 12), (244, 256), {"+y+z": 3, "+yx": 2}), 1)
    p.cut(box(G, (-5, 5), (12, 13), (248, 249)))
    p.add(box(G, (-5, 5), (11, 11), (248, 249)), 4)
    return p


def head_plates(M, brow_deep=False):
    # 정수리: 지붕처럼 두 판이 가운데 능선에서 만남(옆으로 28° 내려감) + 앞이 12° 숙임
    _pair(M, "H_Crown", (0, 12), (-15, 9), (262, 264), rotx(12) @ roty(28), (0, -3, 263), 1, ch={"+x-y": 3})
    # (가운데 능선은 뺌 — 깃 둘 + 능선 = 위로 솟는 가시 셋 = 왕관, 가이드 1-4 · v1)
    # 눈썹: V 로 꺾여 가운데가 낮음(노려봄) — 앞으로 튀어나와 눈에 그늘
    a = 30 if brow_deep else 22
    _pair(M, "H_Brow", (0, 12), (-21, -14), (253, 257), roty(-a) @ rotx(8), (0, -16, 253), 1, ch={"-z-y": 2, "+x-y": 3})
    # 볼 판: 옆면, 앞이 안쪽으로 모임(위에서 쐐기), 앞 아래 45°
    # 볼 판: 옆면, 앞이 안쪽으로 모임(위에서 쐐기), 앞 아래 45° — v1 은 너무 커서 귀마개처럼 보임 → 길이 25→17, 높이 15→11
    _pair(M, "H_Cheek", (10, 12), (-17, 0), (244, 255), rotz(-16), (11, -6, 249), 2, ch={"-z-y": 6, "+z-y": 2, "y+z": 2})
    # 주둥이 마스크: 두 판이 가운데에서 만나 위에서 V, 앞에서 아래가 1:2 로 모이는 턱
    _pair(M, "H_Mask", (0, 9), (-22, -18), (240, 249), rotz(26), (0, -20, 245), 2,
          extra=lambda G: G[2] >= 242 + 0.5 * G[0])
    _slab(M, "H_MaskRidge", (-1, 1), (-23, -21), (241, 248), np.eye(3), (0, -20, 245), 2, ch={"-y+z": 1})


FIN = [(-6, 0), (6, 0), (6, 10), (3, 13), (3, 20), (-1, 28), (-6, 18)]        # 칼날(뿌리 넓고 끝으로 좁아짐) + 뒤 변 한 단 턱
FIN_SUB = [(0, 0), (7, 0), (7, 10), (4, 16), (0, 12)]


def _fin(M, name, root, prof, rot, c, thick=(0, 2), edge=True, scale=1.0):
    x0 = root[0] + thick[0]; x1 = root[0] + thick[1]
    pts = [(root[1] + y * scale, root[2] + z * scale) for y, z in prof]
    ys = [q[0] for q in pts]; zs = [q[1] for q in pts]
    p = M.part(name, (x0 - 2, int(min(ys)) - 2, int(min(zs)) - 2), (x1 + 3, int(max(ys)) + 3, int(max(zs)) + 3),
               pivot=root, parent="Head")
    G = p.g(); X, Y, Z = G
    blade = poly(G, "x", pts, rng=(x0, x1))
    p.add(blade, c)
    if edge:
        # (앞 변 흰 날은 뺌 — 두 색 줄이 젓가락처럼 보임 · v1)
        # 가운데 접힌 능선: 바깥면에 한 줄 돋음
        p.emboss(poly(G, "x", [(root[1] - 1 * scale, root[2] + 2), (root[1] + 1 * scale, root[2] + 2),
                               (root[1] + 1 * scale, root[2] + 20 * scale), (root[1] - 1 * scale, root[2] + 20 * scale)],
                      rng=(x1 + 1, x1 + 1) if root[0] > 0 else (x0 - 1, x0 - 1)), c)
    p.rot = rot
    HEAD_PARTS.append(name)
    return p


def fins(M, kind):
    if kind in ("F1", "F3"):
        sc = 1.0 if kind == "F1" else 0.8
        for s, sfx in ((1, "L"), (-1, "R")):
            root = (9 * s, 0, 262)
            th = (0, 2) if s > 0 else (-2, 0)
            _fin(M, "FinL" if s > 0 else "FinR", root, FIN, roty(14 * s) @ rotx(-30) @ rotz(-20 * s), 1, th, scale=sc)
            _fin(M, "FinSubL" if s > 0 else "FinSubR", (8 * s, 4, 262), FIN_SUB, roty(14 * s) @ rotx(-40) @ rotz(-20 * s), 2,
                 (0, 1) if s > 0 else (-1, 0), edge=False, scale=sc)
    elif kind == "F2":       # 볼 판 위쪽 뒤에서 뒤로 눕혀 뻗는 2단 깃
        for s in (1, -1):
            root = (12 * s, 2, 254)
            th = (0, 2) if s > 0 else (-2, 0)
            _fin(M, "FinL" if s > 0 else "FinR", root, FIN, roty(10 * s) @ rotx(-60) @ rotz(-8 * s), 1, th, scale=1.1)
            _fin(M, "FinSubL" if s > 0 else "FinSubR", (11 * s, 4, 250), FIN_SUB, roty(10 * s) @ rotx(-70) @ rotz(-8 * s), 2,
                 (0, 1) if s > 0 else (-1, 0), edge=False, scale=1.1)


VARIANTS = {"F1": dict(eyes="slant", brow_deep=False), "F2": dict(eyes="slant", brow_deep=False),
            "F3": dict(eyes="flat", brow_deep=True)}


def build(kind="F1"):
    M = A.build_all()
    v = VARIANTS[kind]
    head_core(M, v["eyes"])
    head_plates(M, v["brow_deep"])
    fins(M, kind)
    return M


def build_all():
    return build("F1")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["F1", "F2", "F3"]
    rows = []
    for k in kinds:
        M = build(k)
        keep = set(HEAD_PARTS) | {"Torso"}
        B = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        ims = [vp.render(B, A.SCHEMES["A"], A.EMISSIVE, yaw=y, pitch=p, ppc=9, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in ((0, 4, ((-26, 26), (234, 292))), (30, 6, ((-28, 28), (234, 294))),
                                (90, 2, ((-30, 30), (234, 294))), (150, 12, ((-28, 28), (236, 298))))]
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
