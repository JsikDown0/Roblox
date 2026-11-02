"""HT-02 CETUS — 헬멧·가슴 r3 (2026-11-02) — r2b 채택 + 관자놀이 뾰족 못 + 가슴 뼈색 판을 붓선 같은 곡선 띠로(유저 11-02). 아래는 r2 설명 — r1 + A3 를 "약간 솟은 목 보호대"로(유저 11-02 "머리띠나 후드가 되니까 이상"). VARIANT="b" = r2b(코르셋 받침·뼈색 판 키움·멍에 한 단·호스 굵게)

기준 그림: mech/docs/레퍼런스/CETUS/concept_v1_GPT_후보.png (1순위)
읽기 확인: mech/docs/레퍼런스/CETUS/윤곽읽기_r2_헬멧가슴.png + 결정기록 5-4
축척: 그림 헬멧 꼭대기 y148 → z 260, 바닥 y1228 → z 0  (1px ≈ 0.24칸). 좌우는 그림 중심 x≈630.
칸 0.05 · +X = 기체 왼쪽 · −Y = 정면 · +Z = 위.

색: 1 짙은 청록 · 2 뼈색 · 3 짙은 무쇠 · 4 검정(홈) · 5 황동 · 6 호박 발광 · 7 강철
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402

PAL = {1: (58, 80, 76), 2: (204, 196, 174), 3: (44, 46, 48), 4: (16, 17, 19),
       5: (170, 128, 60), 6: (255, 186, 84), 7: (118, 120, 120)}
EMISSIVE = {6}

NECK_Z = 221          # 헬멧 피벗(목)
CHEST_TOP = 218
VARIANT = "b"   # r3 = r2b 기반


def dilate(m, n=1):
    for _ in range(n):
        P = np.pad(m, 1)
        m = (P[1:-1, 1:-1, 1:-1] | P[2:, 1:-1, 1:-1] | P[:-2, 1:-1, 1:-1] | P[1:-1, 2:, 1:-1]
             | P[1:-1, :-2, 1:-1] | P[1:-1, 1:-1, 2:] | P[1:-1, 1:-1, :-2])
    return m


def capsule(G, a, b, r):
    """선분 a-b 둘레 반지름 r 관."""
    X, Y, Z = G
    a = np.asarray(a, float); b = np.asarray(b, float); d = b - a
    L2 = float(d @ d)
    t = ((X - a[0]) * d[0] + (Y - a[1]) * d[1] + (Z - a[2]) * d[2]) / L2
    t = np.clip(t, 0, 1)
    px, py, pz = a[0] + t * d[0], a[1] + t * d[1], a[2] + t * d[2]
    return (X - px) ** 2 + (Y - py) ** 2 + (Z - pz) ** 2 <= r * r + 0.25


def hose(G, pts, r, mirror=True):
    m = None
    for a, b in zip(pts[:-1], pts[1:]):
        s = capsule(G, a, b, r)
        if mirror:
            s = s | capsule(G, (-a[0], a[1], a[2]), (-b[0], b[1], b[2]), r)
        m = s if m is None else (m | s)
    return m


def build_head(M):
    """A1 돔 · A2 창(창살 2×2, 발광①) · A5 정수리 고리."""
    H = M.part("Head", (-32, -26, 214), (33, 24, 270), pivot=(0, -1, NECK_Z), parent="Torso")
    G = H.g()
    c = (0, -1, 240)
    H.add(fv.ell(G, c, (19, 19, 19)) & fv.box(G, z=(221, 270)), 1)
    # A2 창: 황동 테 + 안으로 들어간 발광 유리 + 굵은 창살(가로·세로 2칸)
    wz = 238
    ring = fv.cyl(G, "y", (0, wz), 11, rng=(-22, -15)) & ~fv.cyl(G, "y", (0, wz), 8)
    H.cut(fv.cyl(G, "y", (0, wz), 8, rng=(-26, -17)))
    H.add(ring, 5)
    H.add(fv.cyl(G, "y", (0, wz), 8, rng=(-17, -16)), 6)
    bars = (fv.box(G, x=(-1, 0)) | fv.box(G, z=(wz - 1, wz))) & fv.cyl(G, "y", (0, wz), 8, rng=(-19, -18))
    H.add(bars, 5)
    # A5 정수리 고리 손잡이(2칸 굵기, 가운데 구멍)
    H.add(fv.box(G, x=(-1, 0), y=(-2, 1), z=(258, 261)), 5)
    loop = fv.box(G, x=(-4, 3), y=(-1, 0), z=(261, 267)) & ~fv.box(G, x=(-2, 1), z=(263, 265))
    H.add(loop, 5)
    # 관자놀이 뾰족 못(좌우): 황동 축 |x| 16~23 + 강철 원뿔 끝 |x| 23~30, 창 높이·살짝 앞
    X, Y, Z = G
    ax = np.abs(X)
    d2 = (Y - (-5)) ** 2 + (Z - wz) ** 2
    H.add((ax >= 16) & (ax <= 23) & (d2 <= 2.6 ** 2 + 0.25), 5)
    H.add((ax >= 22) & (ax <= 23) & (d2 <= 3.6 ** 2 + 0.25), 5)          # 축 끝 고리
    rr = 2.6 * (30 - ax) / 7.0
    H.add((ax > 23) & (ax <= 30) & (d2 <= rr ** 2 + 0.25), 7)
    H.trim()
    return H


def build_torso(M):
    """B1 압력선체 · A4 목깃 · A3 후드 · B2 연 판 · B3 처마 + B4 가로 틈 코어 · B5 호스 · C 멍에."""
    T = M.part("Torso", (-40, -36, 150), (41, 32, 266), pivot=(0, 0, 172))
    G = T.g()
    # B1 술통 선체: 위에서 보면 팔각, 아래 모서리 둥글게
    hull = fv.cbox(G, (-32, 32), (-26, 24), (172, CHEST_TOP), ch={"xy": 11, "-zx": 6, "-zy": 6})
    hull &= fv.ell(G, (0, -1, 196), (38, 31, 44))          # 술통처럼 위아래로 살짝 오므림
    T.add(hull, 1)
    # 앞면 세로 홈 두 줄(판 나눔) — 처마·틈 자리는 비움
    T.groove(fv.box(G, x=(11, 11), y=(-27, -18), z=(176, 216)) | fv.box(G, x=(-11, -11), y=(-27, -18), z=(176, 216)), 4)
    # A4 황동 목깃(헬멧 아래 둥근 띠)
    T.add(fv.cyl(G, "z", (0, -1), 22, rng=(216, 223)) & ~fv.cyl(G, "z", (0, -1), 17), 5)
    T.add(fv.cyl(G, "z", (0, -1), 17, rng=(216, 219)), 3)       # 목깃 안 바닥(목)
    if VARIANT == "b":   # 코르셋 받침: 목깃 둘레로 둥글게 솟은 어깨받이(청록 + 황동 테)
        cors = fv.cyl(G, "z", (0, -1), 31, rng=(218, 220)) & ~fv.cyl(G, "z", (0, -1), 22) & fv.box(G, y=(-30, 12))
        cors |= fv.cyl(G, "z", (0, -1), 27, rng=(221, 222)) & ~fv.cyl(G, "z", (0, -1), 22) & fv.box(G, y=(-30, 12))
        T.add(cors, 1)
        T.paint(cors & ~fv.cyl(G, "z", (0, -1), 29), 5)
    # A3 후드(목 보호대): 헬멧 뒤를 반구 껍데기로 감쌈, 앞쪽 끝은 비스듬히
    # A3 목 보호대: 헬멧 아랫부분 둘레(뒤·옆)에서 약간 솟은 깃. 뒤가 가장 높고(약 z 238) 앞으로 갈수록 낮아짐(옆 앞 z 227)
    guard = fv.cyl(G, "z", (0, 0), 25, rng=(219, 245)) & ~fv.cyl(G, "z", (0, 0), 21)
    guard &= fv.box(G, y=(-12, 30)) & fv.half(G, (0, -0.28, 1), (0, -12, 226))
    T.add(guard, 7)
    top = guard & ~fv.half(G, (0, -0.28, 1), (0, -12, 224))      # 윗가장자리 2칸 황동 테
    T.paint(top, 5)
    # B2 가슴 옆 뼈색 연 모양 판(좌우 대칭) — 선체 겉 1~2칸
    chest = T.a > 0
    # B2 붓선 띠(좌우 대칭): 목깃 옆에서 시작 → 바깥으로 휨 → 멍에 쪽으로 다시 모임. 가운데 두껍고 양 끝 가늘게
    X, Y, Z = G
    ax = np.abs(X)
    path = [(15, 216), (22, 209), (26, 198), (24, 187), (18, 179), (12, 175)]
    seg = [(np.array(a, float), np.array(b, float)) for a, b in zip(path[:-1], path[1:])]
    Ls = [np.linalg.norm(b - a) for a, b in seg]; Ltot = sum(Ls)
    best = np.full(np.broadcast_shapes(X.shape, Y.shape, Z.shape), 1e9); tpar = np.zeros_like(best)
    acc = 0.0
    for (a, b), L in zip(seg, Ls):
        d = b - a
        t = np.clip(((ax - a[0]) * d[0] + (Z - a[1]) * d[1]) / (L * L), 0, 1)
        dist = np.sqrt((ax - (a[0] + t * d[0])) ** 2 + (Z - (a[1] + t * d[1])) ** 2)
        dist = np.broadcast_to(dist, best.shape); tt = np.broadcast_to((acc + t * L) / Ltot, best.shape)
        upd = dist < best
        best = np.where(upd, dist, best); tpar = np.where(upd, tt, tpar)
        acc += L
    width = 1.0 + 2.6 * np.sin(np.pi * tpar)                 # 반폭: 끝 1칸 → 가운데 3.6칸
    stroke = (best <= width) & np.broadcast_to(Y < -6, best.shape)
    near = dilate(chest, 2) & ~chest & fv.box(G, z=(172, 218))
    T.add(stroke & near, 2)
    # B3 처마(황동 띠, 앞으로 4칸) + B4 그 밑 그늘 속 가로 틈 코어
    T.add(fv.cbox(G, (-13, 13), (-31, -24), (199, 203), ch={"+z-y": 2}), 5)
    T.cut(fv.box(G, x=(-10, 10), y=(-27, -24), z=(193, 196)))
    T.add(fv.box(G, x=(-10, 10), y=(-23, -23), z=(193, 196)), 4)
    T.add(fv.box(G, x=(-8, 8), y=(-24, -23), z=(194, 195)), 6)
    # C 황동 멍에(가슴 아래 앞)
    if VARIANT == "b":   # 한 단, 작게
        T.add(fv.cbox(G, (-12, 12), (-29, -18), (164, 175), ch={"xz": 3, "-y+z": 3}), 5)
    else:
        T.add(fv.cbox(G, (-16, 16), (-30, -16), (160, 176), ch={"xz": 3, "-y+z": 3}), 5)
        T.groove(fv.box(G, x=(-16, 16), y=(-31, -29), z=(168, 168)), 4)
    # B5 굵은 호스 2줄: 목깃 옆 → 가슴 앞 모서리 바깥 → 멍에 옆
    path = [(22, -8, 221), (32, -19, 210), (33, -26, 192), (26, -31, 177), (17, -29, 169)]
    tube = hose(G, path, 4 if VARIANT == "b" else 3) & ~(T.a > 0)
    T.add(tube, 3)
    for z in (205, 188):   # 황동 고리
        T.paint(tube & fv.box(G, z=(z, z + 1)), 5)
    T.trim()
    return T


def build_all():
    M = fv.Model()
    build_torso(M)
    build_head(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    import vox_preview as vp
    M = build_all()
    for n, p in M.parts.items():
        print(n, "cells", p.count(), "lo", p.lo.tolist(), "hi", p.hi.tolist())
    B = M.blocks()
    views = ((-30, 6, "front 3/4 A"), (0, 4, "front"), (30, 6, "front 3/4 B"), (90, 2, "side"), (150, 10, "back 3/4"))
    ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=5.0, ss=2, ao_amt=0.5) for y, p, _ in views]
    vp.sheet(ims, [v[2] for v in views]).save(os.path.join(out, "cetus_r3_views.png"))
    print("saved")
