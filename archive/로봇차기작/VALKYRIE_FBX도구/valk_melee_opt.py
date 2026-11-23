"""
valk_melee_opt.py — 키 자세 다듬기: 설계 의도(valk_melee3.D) 둘레에서 손잡이 위치 · 날 방향 · 날 돌림 · 허리 비틀기 · 팔꿈치 방향(pole)을 찾아
  겹침(fast2) + 손목 꺾임 + 손 못 닿음 + 의도에서 벗어난 만큼 = 비용 최소.  python3 valk_melee_opt.py W1 [S1 ...] → opt_<키>.json
"""
import sys, json
import numpy as np
import valk_melee1 as V, valk_melee2 as K, valk_melee3 as M3


def rot(axis, deg):
    a = np.radians(deg); axis = K.nrm(axis); c, s = np.cos(a), np.sin(a)
    x, y, z = axis
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def pole(yaw, pitch, side):
    y, p = np.radians(yaw), np.radians(pitch)
    return np.array([side * np.cos(p) * np.cos(y), np.sin(p), np.cos(p) * np.sin(y)])


def decode(base, x):
    ry, w, nk, p, d, e, pl, pr = base
    p = np.array(p, float) + x[0:3]
    d = K.nrm(d); e = np.array(e, float); e = K.nrm(e - d * (e @ d))
    side = K.nrm(np.cross(d, e))
    R = rot(e, x[3]) @ rot(side, x[4])          # 날 방향을 날(edge) 축 · 옆 축으로 기울임
    d2 = R @ d; e2 = R @ e
    e2 = rot(d2, x[5]) @ e2                       # 날 축 둘레 돌림
    w2 = (w[0], w[1] + x[6], w[2]); nk2 = (nk[0], nk[1] - x[6], nk[2])
    return ry, w2, nk2, p, d2, e2, pole(x[7], x[8], -1), pole(x[9], x[10], 1)


SC = np.array([1.2, 1.2, 1.2, 12, 12, 25, 10, 60, 50, 60, 50])
DEV = np.array([25, 25, 25, 5, 5, 0.2, 0.3, 0, 0, 0, 0])   # 11-03 21:2x 날 방향 벌점 0.3 → 5(의도 F1 왼 아래가 오른쪽으로 돌아가던 것)   # 벗어남 벌점 무게(위치 1 스터드 = 25 · 각 1° = 0.3)


def evaluate(base, x):
    ry, w, nk, p, d, e, pl, pr = decode(base, x)
    k = K.key(K.body(ry, w, nk), p, d, e, poleL=pl, poleR=pr)
    if not np.isfinite(k["eR"]) or not all(np.all(np.isfinite(v)) for v in k["P"].values()): return 1e9, k
    rw, _ = K.right_wrist(k["P"])
    c = K.fast2(k["P"])
    cost = c + 4 * max(0, k["wrist"] - 75) + 1.5 * max(0, rw - 100) + 3000 * k["eR"] + float(DEV @ (np.abs(x) ** 2 * np.array([1, 1, 1, .1, .1, .1, .1, 0, 0, 0, 0])))
    k.update(clash=c, wristR=rw, x=x.tolist())
    return cost, k


def optimize(name, n_rand=160, n_loc=200, seed=0):
    rng = np.random.default_rng(seed)
    base = M3.D[name]
    x0 = np.zeros(11); x0[7:11] = [0, -30, 0, -30]        # 팔꿈치 바깥 아래
    best = (evaluate(base, x0)[0], x0)
    for _ in range(n_rand):
        x = best[1] + rng.normal(0, 0.6, 11) * SC
        c, _ = evaluate(base, x)
        if c < best[0]: best = (c, x)
    s = 0.35
    for i in range(n_loc):
        x = best[1] + rng.normal(0, s, 11) * SC
        c, _ = evaluate(base, x)
        if c < best[0]: best = (c, x)
        if i % 50 == 49: s *= 0.6
    c, k = evaluate(base, best[1])
    ry, w, nk, p, d, e, pl, pr = decode(base, best[1])
    return dict(name=name, cost=c, clash=k["clash"], wrist=k["wrist"], wristR=k["wristR"], eR=k["eR"],
                ry=ry, w=list(w), n=list(nk), p=list(p), d=list(d), e=list(e), pl=list(pl), pr=list(pr))


if __name__ == "__main__":
    for nm in sys.argv[1:]:
        r = optimize(nm)
        json.dump(r, open(f"/tmp/claude-0/-home-claude/45a5ff43-da6d-586c-af9c-a80fba67e5ee/scratchpad/opt_{nm}.json", "w"), indent=1)
        print(nm, {k: (round(v, 2) if isinstance(v, float) else v) for k, v in r.items() if k in ("cost", "clash", "wrist", "wristR", "eR")}, flush=True)


def mid_intent(a, b, t=0.5):
    A, B = M3.D[a], M3.D[b]
    lerp = lambda x, y: tuple(np.array(x, float) * (1 - t) + np.array(y, float) * t)
    return (A[0] * (1 - t) + B[0] * t, lerp(A[1], B[1]), lerp(A[2], B[2]), lerp(A[3], B[3]),
            tuple(K.nrm(lerp(A[4], B[4]))), lerp(A[5], B[5]), A[6], A[7])


def path_cost(kA, k, kB, n=3):
    c = 0
    for kk, (X, Y) in ((0, (kA, k)), (1, (k, kB))):
        for a in np.linspace(0, 1, n + 2)[1:-1]:
            P = K.blend(X["P"], Y["P"], a)
            pole = X["poleR"] + (Y["poleR"] - X["poleR"]) * a
            P, eR, _ = K.solve_right(P, pole)
            c += K.fast2(P) + 3000 * eR
    return c


def optimize_path(name, prev, nxt, base=None, n_rand=80, n_loc=100, seed=1, free_roll=False):
    """키 name 을 앞 키 prev → name → 뒤 키 nxt 길까지 겹침을 보며 다듬음(앞뒤 키는 고정)."""
    rng = np.random.default_rng(seed)
    base = base or M3.D[name]
    kA, kB = M3.KEYS[prev], M3.KEYS[nxt]
    def ev(x):
        c, k = evaluate(base, x)
        if c >= 1e9: return c, k
        return c + path_cost(kA, k, kB), k
    x0 = np.zeros(11); x0[7:11] = [0, -30, 0, -30]
    best = (ev(x0)[0], x0)
    if free_roll:                                  # 날 축 둘레 돌림을 0~330° 에서 먼저 고름(빔이라 날 방향은 거의 안 보임) → 그 돌림을 의도로 삼음
        b0 = base; bb = (best[0], base)
        for r in range(30, 360, 30):
            d = K.nrm(b0[4]); e = rot(d, r) @ np.array(b0[5], float)
            bc = b0[:5] + (tuple(e),) + b0[6:]
            base = bc; c, _ = ev(x0)
            if c < bb[0]: bb = (c, bc)
        base = bb[1]; best = (bb[0], x0)
    for _ in range(n_rand):
        x = best[1] + rng.normal(0, 0.6, 11) * SC
        c, _ = ev(x)
        if c < best[0]: best = (c, x)
    s = 0.35
    for i in range(n_loc):
        x = best[1] + rng.normal(0, s, 11) * SC
        c, _ = ev(x)
        if c < best[0]: best = (c, x)
        if i % 30 == 29: s *= 0.6
    c, k = ev(best[1])
    ry, w, nk, p, d, e, pl, pr = decode(base, best[1])
    return dict(name=name, cost=c, clash=k["clash"], wrist=k["wrist"], wristR=k["wristR"], eR=k["eR"],
                ry=ry, w=list(w), n=list(nk), p=list(p), d=list(d), e=list(e), pl=list(pl), pr=list(pr))


def run_path(jobs, free_roll=False):
    M3.use_opt(["W1", "S1", "F1", "V2", "S2", "F2", "P3", "T3", "RV1", "RV3"]); M3.build()
    for name, prev, nxt, mid in jobs:
        base = mid_intent(*mid) if mid else None
        if base: M3.D[name] = base
        r = optimize_path(name, prev, nxt, base, free_roll=free_roll)
        json.dump(r, open(f"/tmp/claude-0/-home-claude/45a5ff43-da6d-586c-af9c-a80fba67e5ee/scratchpad/opt_{name}.json", "w"), indent=1)
        print(name, {k: (round(v, 2) if isinstance(v, float) else v) for k, v in r.items() if k in ("cost", "clash", "wrist", "wristR", "eR")}, flush=True)


# ---------- 11-04 가드 중 칼 자세(GD): 접힌 방패(가드 t = 1)와도 안 겹치게 ----------
def evaluate_g(base, x, tg=1.0):
    c, k = evaluate(base, x)
    if c >= 1e9: return c, k
    g = K.clash_guard(k["P"], tg)
    k["gclash"] = g
    return c + 2.0 * g, k


def optimize_g(base, n_rand=120, n_loc=140, seed=3):
    rng = np.random.default_rng(seed)
    x0 = np.zeros(11); x0[7:11] = [0, -30, 0, -30]
    best = (evaluate_g(base, x0)[0], x0)
    for _ in range(n_rand):
        x = best[1] + rng.normal(0, 0.6, 11) * SC
        c, _ = evaluate_g(base, x)
        if c < best[0]: best = (c, x)
    s = 0.35
    for i in range(n_loc):
        x = best[1] + rng.normal(0, s, 11) * SC
        c, _ = evaluate_g(base, x)
        if c < best[0]: best = (c, x)
        if i % 40 == 39: s *= 0.6
    c, k = evaluate_g(base, best[1])
    ry, w, nk, p, d, e, pl, pr = decode(base, best[1])
    return dict(cost=c, clash=k["clash"], gclash=k["gclash"], wrist=k["wrist"], wristR=k["wristR"], eR=k["eR"],
                ry=ry, w=list(w), n=list(nk), p=list(p), d=list(d), e=list(e), pl=list(pl), pr=list(pr))
