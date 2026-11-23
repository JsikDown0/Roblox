"""
valk_melee2.py — VALKYRIE 두 손 블레이드 키 자세 풀이(2026-11-03, valk_melee1 FK 위).
  키 = 몸통(Root 내림 · Waist · Neck 각) + 손잡이 틀(몸통 로컬: 왼손 쥔 점 위치 p · 날 방향 d · 날(edge) 방향 e).
  왼팔 = 손잡이 쥔 점(SaberGrip C1 = 손잡이 로컬 (0, −1.4, 0))에 IK(solve_arm) + 손목(SaberGrip) = 남는 회전.
  오른손 = 지느러미(사격 때 쥐는 곳) — 손잡이 로컬 FIN = (0, 0.88, −1.01) [Studio 실측: Rifle 로컬 주먹 (0.96, −2.78, 0) → VBladeHilt 용접 → SaberHilt 로컬].
  손잡이 로컬 축: +y = 날 방향 · +z = 금 등줄(사격 때 위) · −z = 지느러미 = 날(edge) 쪽.
"""
import numpy as np
import valk_melee1 as V
inv = np.linalg.inv
FIN = np.array([0.0, 0.88, -1.01])
C1S = V.J["SaberGrip"][3]          # 손잡이 로컬 쥔 점
C0S = V.J["SaberGrip"][2]          # 아래팔 로컬


def nrm(v): v = np.asarray(v, float); return v / np.linalg.norm(v)


def hilt_local(p, d, e):
    """몸통 로컬 손잡이 틀(4x4). d = 날 방향 · e = 날(edge) 방향(d 에 수직으로 맞춤)."""
    y = nrm(d); e = np.asarray(e, float); e = nrm(e - y * (e @ y)); z = -e
    x = np.cross(y, z)
    H = np.eye(4); H[:3, :3] = np.stack([x, y, z], 1)
    H[:3, 3] = np.asarray(p, float) - H[:3, :3] @ C1S[:3, 3]     # p = 왼손 쥔 점
    return H


def body(root_y=0.0, waist=(0, 0, 0), neck=(0, 0, 0)):
    return {"Root": V.T(0, root_y, 0), "Waist": V.E(*waist), "Neck": V.E(*neck)}


def ang(R):
    return float(np.degrees(np.arccos(np.clip((np.trace(R[:3, :3]) - 1) / 2, -1, 1))))


def solve_left(P, Hw, pole_local):
    """왼손을 손잡이 틀 Hw(월드)에. 돌려주는 값: P(왼팔 · SaberGrip 넣음), 손 오차, 손목 각."""
    W = V.fk(P); Tt = W["Torso"]
    _, _, c0s, c1s = V.J["ShoulderL"]; _, _, c0e, c1e = V.J["ElbowL"]
    S = Tt @ c0s
    a = (inv(c1s) @ c0e)[:3, 3]; b = (inv(c1e) @ C0S)[:3, 3]
    target = (Hw @ C1S)[:3, 3]
    Rs, th = V.solve_arm(S, a, b, target, Tt[:3, :3] @ nrm(pole_local))
    Q = dict(P); Q["ShoulderL"] = Rs; Q["ElbowL"] = V.rx(np.degrees(th))
    W2 = V.fk(Q)
    G = inv(W2["LowerArmL"] @ C0S) @ Hw @ C1S
    G[:3, 3] = 0
    Q["SaberGrip"] = G
    W3 = V.fk(Q)
    err = float(np.linalg.norm(W3["SaberHilt"][:3, 3] - Hw[:3, 3]))
    return Q, err, ang(G)


def solve_right(P, pole_local, w=1.0):
    """오른손을 지느러미에(MechPoses axeRightHand 와 같은 식 + 손잡이 로컬 옆 오프셋)."""
    W = V.fk(P); Tt = W["Torso"]
    target = (W["SaberHilt"] @ np.append(FIN, 1))[:3]
    _, _, c0s, c1s = V.J["ShoulderR"]; _, _, c0e, c1e = V.J["ElbowR"]
    gC0 = V.CF((0.28029, -2.70493, 0.0945))
    S = Tt @ c0s
    a = (inv(c1s) @ c0e)[:3, 3]; b = (inv(c1e) @ gC0)[:3, 3]
    Rs, th = V.solve_arm(S, a, b, target, Tt[:3, :3] @ nrm(pole_local))
    Q = dict(P); Q["ShoulderR"] = Rs; Q["ElbowR"] = V.rx(np.degrees(th))
    fist = (V.fk(Q)["LowerArmR"] @ gC0)[:3, 3]
    return Q, float(np.linalg.norm(fist - target)), float(np.linalg.norm(target - S[:3, 3]))


def key(bd, p, d, e, poleL=(-1, -0.6, 0.3), poleR=(1, -0.6, 0.3)):
    """키 자세 풀이: bd = body(...) · p/d/e = 몸통 로컬 손잡이. 돌려주는 값 dict(P, 오차들)."""
    P = dict(bd)
    Tt = V.fk(P)["Torso"]
    Hw = Tt @ hilt_local(p, d, e)
    P, eL, wr = solve_left(P, Hw, poleL)
    P, eR, reach = solve_right(P, poleR)
    return dict(P=P, eL=eL, eR=eR, wrist=wr, poleR=np.array(poleR, float), poleL=np.array(poleL, float))


# ---------- 키 사이 보간(Roblox CFrame:Lerp = 회전 slerp + 위치 선형) ----------
def quat(R):
    m = R[:3, :3]; t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1) * 2; return np.array([0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s])
    i = np.argmax(np.diag(m))
    if i == 0:
        s = np.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2; return np.array([(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s])
    if i == 1:
        s = np.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2; return np.array([(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s])
    s = np.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2; return np.array([(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s])


def qmat(q):
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def lerpcf(A, B, k):
    qa, qb = quat(A), quat(B)
    if qa @ qb < 0: qb = -qb
    d = np.clip(qa @ qb, -1, 1)
    if d > 0.9995: q = qa + (qb - qa) * k
    else:
        th = np.arccos(d); q = (np.sin((1 - k) * th) * qa + np.sin(k * th) * qb) / np.sin(th)
    M = np.eye(4); M[:3, :3] = qmat(q); M[:3, 3] = A[:3, 3] + (B[:3, 3] - A[:3, 3]) * k
    return M


LEFT = ("Root", "Waist", "Neck", "ShoulderL", "ElbowL", "SaberGrip")


def blend(PA, PB, k):
    out = {}
    for n in LEFT:
        out[n] = lerpcf(PA.get(n, np.eye(4)), PB.get(n, np.eye(4)), k)
    return out


def ease(kind, a):
    if kind == "smooth": return a * a * (3 - 2 * a)
    if kind == "in": return a * a
    if kind == "out": return np.sin(a * np.pi / 2)
    return a


def frame(KEYS, seq, e):
    """comboPose 와 같은 식 → 그 시각 자세(왼팔·몸통 보간 + 오른손 IK, pole 은 키 사이 선형)."""
    t0 = 0
    for i, sg in enumerate(seq):
        t1 = sg[0]
        if e <= t1 or i == len(seq) - 1:
            a = np.clip((e - t0) / max(1e-3, t1 - t0), 0, 1)
            k = ease(sg[3], a)
            A, B = KEYS[sg[1]], KEYS[sg[2]]
            P = blend(A["P"], B["P"], k)
            pole = A["poleR"] + (B["poleR"] - A["poleR"]) * k
            P, eR, _ = solve_right(P, pole)
            return P, eR
        t0 = t1


# ---------- 겹침 ----------
def overlap(P):
    """칼(손잡이 · 지느러미 · 날) ↔ 몸(팔 제외) · 칼 ↔ 팔 · 팔 ↔ 몸. 손이 쥔 칸 둘레는 겹침으로 안 셈(손잡이 ↔ 왼 아래팔, 지느러미 ↔ 오른 아래팔)."""
    blade = V.cells(P, "blade") | V.cells(P, "beam")
    bodyc = V.cells(P, "body")
    aL = V.cells(P, "armL"); aR = V.cells(P, "armR")
    return dict(blade_body=len(blade & bodyc), arms_body=len((aL | aR) & bodyc), blade_armL=len(blade & aL), blade_armR=len(blade & aR), arm_arm=len(aL & aR))


def part_cells(P):
    """파트별 월드 칸(복셀 몸 + 칼). 겹침 내역용."""
    M, B = V.model(); W = V.fk(P); out = {}
    for n, p in M.parts.items():
        f = V.FOLLOW.get(n)
        if f is None: continue
        D = W[f] @ inv(V.REST[f]); Wb = np.eye(4) if n in V.STRAIGHT else M.world(n)
        Tm = V.MB @ D @ V.MS @ Wb
        ijk = np.argwhere(p.a > 0) + p.lo
        out[n] = set(map(tuple, np.round(ijk @ Tm[:3, :3].T + Tm[:3, 3]).astype(int)))
    for n, p in B.parts.items():
        ijk = np.argwhere(p.a > 0) + p.lo
        Tm = V.MB @ W["SaberHilt"] @ V.BLADE_IN_HILT @ V.MS @ B.world(n)
        out["B_" + n] = set(map(tuple, np.round(ijk @ Tm[:3, :3].T + Tm[:3, 3]).astype(int)))
    return out


ARMS = ("UpperArmL", "LowerArmL", "UpperArmR", "LowerArmR")
GRIPPED = {("LowerArmL", "B_Hilt"), ("LowerArmR", "B_HiltFin"), ("LowerArmR", "B_HiltGuard")}   # 쥔 손 ↔ 쥔 곳은 안 셈


def clashes(P, min_n=1):
    C = part_cells(P); names = list(C); res = {}
    movers = [n for n in names if n in ARMS or n.startswith("B_")]
    for a in movers:
        for b in names:
            if a >= b and b in movers: continue
            if a == b: continue
            if (a, b) in GRIPPED or (b, a) in GRIPPED: continue
            if a in ARMS and b in ARMS and a[-1] == b[-1]: continue          # 같은 팔 위·아래
            if a.startswith("B_") and b.startswith("B_"): continue
            if {a, b} <= {"UpperArmL", "ShoulderL", "PadGoldL", "PadFinL"} or {a, b} <= {"UpperArmR", "ShoulderR", "PadGoldR", "PadFinR"}: pass
            n = len(C[a] & C[b])
            if n >= min_n: res[(a, b)] = n
    return dict(sorted(res.items(), key=lambda x: -x[1]))


BASE = {("UpperArmL", "ShoulderL"), ("UpperArmR", "ShoulderR")}   # 위팔이 어깨 장갑 안에 들어간 칸 — 쉬는 자세부터 300 안팎(모델 그대로) → 안 셈


def clash_score(P):
    c = clashes(P)
    return sum(v for k, v in c.items() if k not in BASE and tuple(reversed(k)) not in BASE), c


def right_wrist(P):
    """오른손 주먹 ↔ 지느러미 각(사격 때 쥔 모양과의 차이). = Grip Transform 회전 각(라이플을 그 자리에 두려면 손목을 얼마나 꺾나)."""
    W = V.fk(P)
    C0g, C1g = V.J["Grip"][2], V.J["Grip"][3]
    Rw = W["SaberHilt"] @ V.VH_IN_HILT
    Tg = inv(W["LowerArmR"] @ C0g) @ Rw @ C1g
    return ang(Tg), Tg


def sphere(n=40):
    i = np.arange(n) + 0.5; phi = np.arccos(1 - 2 * i / n); th = np.pi * (1 + 5 ** 0.5) * i
    return np.stack([np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)], 1)


def key_auto(bd, p, d, e, n=40, wclash=0.05, verbose=False):
    """pole 을 구 위 n 방향에서 골라 (손목 각 + 겹침) 최소."""
    P0 = dict(bd); Tt = V.fk(P0)["Torso"]; Hw = Tt @ hilt_local(p, d, e)
    bestL = None
    for pl in sphere(n):
        P, eL, wr = solve_left(P0, Hw, pl)
        if eL > 0.02: continue
        if bestL is None or wr < bestL[0]: bestL = (wr, pl, P)
    if bestL is None: return None
    wrL, pl, PL = bestL
    best = None
    for pr in sphere(n):
        P, eR, _ = solve_right(PL, pr)
        if eR > 0.05: continue
        rw, _ = right_wrist(P)
        if best is None or rw < best[0] - 1e-6: best = (rw, pr, P, eR)
    if best is None:
        P, eR, _ = solve_right(PL, (1, -0.6, 0.3)); best = (right_wrist(P)[0], np.array([1, -0.6, 0.3]), P, eR)
    rw, pr, P, eR = best
    sc, c = clash_score(P)
    return dict(P=P, eL=0.0, eR=eR, wrist=wrL, wristR=rw, poleL=pl, poleR=pr, clash=sc, clashes=c)


def key_best(bd, p, d, e, n=30, topL=5, topR=3, wR=0.3, wC=0.08):
    """손목 각이 작은 pole 몇 개씩 → 겹침까지 넣은 점수 최소. 점수 = 왼손목 + wR·오른손목 + wC·겹침칸."""
    P0 = dict(bd); Tt = V.fk(P0)["Torso"]; Hw = Tt @ hilt_local(p, d, e)
    Ls = []
    for pl in sphere(n):
        P, eL, wr = solve_left(P0, Hw, pl)
        if eL < 0.02: Ls.append((wr, pl, P))
    Ls.sort(key=lambda x: x[0])
    best = None
    for wrL, pl, PL in Ls[:topL]:
        Rs = []
        for pr in sphere(n):
            P, eR, _ = solve_right(PL, pr)
            if eR < 0.05: Rs.append((right_wrist(P)[0], pr, P))
        Rs.sort(key=lambda x: x[0])
        for rw, pr, P in Rs[:topR]:
            sc, c = clash_score(P)
            s = wrL + wR * rw + wC * sc
            if best is None or s < best["score"]:
                best = dict(P=P, score=s, wrist=wrL, wristR=rw, clash=sc, clashes=c, poleL=pl, poleR=pr, p=p, d=d, e=e, bd=bd)
    return best


# ---------- 빠른 겹침(정수 키 + np.isin) — 최적화용. clash_score 와 같은 규칙 ----------
_IJK = {}
def _ijk():
    if not _IJK:
        M, B = V.model()
        for n, p in M.parts.items():
            if V.FOLLOW.get(n): _IJK[n] = (np.argwhere(p.a > 0) + p.lo).astype(float)
        for n, p in B.parts.items(): _IJK["B_" + n] = (np.argwhere(p.a > 0) + p.lo).astype(float)
    return _IJK


def _keys(a):
    a = np.round(a).astype(np.int64) + 2000
    return np.unique(a[:, 0] * 16000000 + a[:, 1] * 4000 + a[:, 2])


def part_keys(P, names=None):
    M, B = V.model(); W = V.fk(P); I = _ijk(); out = {}
    for n, ijk in I.items():
        if names is not None and n not in names: continue
        if n.startswith("B_"):
            Tm = V.MB @ W["SaberHilt"] @ V.BLADE_IN_HILT @ V.MS @ B.world(n[2:])
        else:
            f = V.FOLLOW[n]; D = W[f] @ inv(V.REST[f]); Wb = np.eye(4) if n in V.STRAIGHT else M.world(n)
            Tm = V.MB @ D @ V.MS @ Wb
        out[n] = _keys(ijk @ Tm[:3, :3].T + Tm[:3, 3])
    return out


PADS = {"L": ("ShoulderL",), "R": ("ShoulderR",)}


def fast_clash(P):
    C = part_keys(P)
    arms = {n: C.pop(n) for n in ARMS}
    blade = np.unique(np.concatenate([C.pop(n) for n in list(C) if n.startswith("B_") and n not in ("B_Hilt", "B_HiltFin", "B_HiltGuard")] +
                                     [np.array([], np.int64)]))
    grip = {n: C.pop(n) for n in ("B_Hilt", "B_HiltFin", "B_HiltGuard")}
    body = np.unique(np.concatenate(list(C.values())))
    nopad = {s: np.unique(np.concatenate([v for k, v in C.items() if k not in PADS[s]])) for s in "LR"}
    tot = 0
    for n, a in arms.items():
        s = n[-1]
        tot += np.isin(a, nopad[s] if n.startswith("Upper") else body).sum()
    tot += np.isin(arms["LowerArmL"], arms["LowerArmR"]).sum() + np.isin(arms["LowerArmL"], arms["UpperArmR"]).sum() + np.isin(arms["UpperArmL"], arms["LowerArmR"]).sum()
    allgrip = np.concatenate(list(grip.values()))
    tot += np.isin(blade, body).sum() + np.isin(allgrip, body).sum()
    tot += np.isin(blade, np.concatenate(list(arms.values()))).sum()
    tot += np.isin(grip["B_Hilt"], arms["LowerArmR"]).sum() + np.isin(grip["B_HiltFin"], arms["LowerArmL"]).sum()
    tot += np.isin(np.concatenate([grip["B_HiltFin"], grip["B_HiltGuard"]]), arms["UpperArmL"]).sum() + np.isin(allgrip, arms["UpperArmR"]).sum()
    return int(tot)


_GRP = {}
def _groups():
    """몸(팔 제외) 파트를 따라가는 Studio 파트별로 묶어, 쉬는 자세 칸 키(정렬)를 미리 만듦."""
    if not _GRP:
        M, B = V.model(); I = _ijk()
        tmp = {}
        for n, ijk in I.items():
            if n.startswith("B_") or n in ARMS: continue
            f = V.FOLLOW[n]
            Wb = M.world(n)
            w = ijk @ Wb[:3, :3].T + Wb[:3, 3]
            key = (f, "pad" if n in ("ShoulderL", "ShoulderR") else "x")
            tmp.setdefault(key, []).append(w)
        for k, ws in tmp.items(): _GRP[k] = np.sort(_keys(np.concatenate(ws)))
    return _GRP


def _hits(world_cells, W, grp_keys_filter=None):
    """월드 칸(복셀 좌표) 중 몸 묶음과 겹치는 수."""
    G = _groups(); n = 0
    for (f, kind), keys in G.items():
        if grp_keys_filter and not grp_keys_filter(f, kind): continue
        D = W[f] @ inv(V.REST[f]); Tm = V.MB @ inv(D) @ V.MS        # 월드 복셀 → 쉬는 자세 복셀
        loc = world_cells @ Tm[:3, :3].T + Tm[:3, 3]
        k = _keys(loc)
        i = np.searchsorted(keys, k); i[i >= len(keys)] = 0
        n += int((keys[i] == k).sum())
    return n


def _world(P, W, names):
    M, B = V.model(); I = _ijk(); out = {}
    for n in names:
        ijk = I[n]
        if n.startswith("B_"): Tm = V.MB @ W["SaberHilt"] @ V.BLADE_IN_HILT @ V.MS @ B.world(n[2:])
        else:
            f = V.FOLLOW[n]; D = W[f] @ inv(V.REST[f]); Tm = V.MB @ D @ V.MS
        out[n] = ijk @ Tm[:3, :3].T + Tm[:3, 3]
    return out


def fast2(P):
    W = V.fk(P)
    X = _world(P, W, list(ARMS) + ["B_Hilt", "B_HiltFin", "B_HiltGuard", "B_HiltBarrel", "B_BladeFX"])
    tot = 0
    for n in ARMS:
        s = n[-1]
        flt = (lambda f, kind, s=s: not (kind == "pad" and f == "ShoulderPad" + s)) if n.startswith("Upper") else None
        tot += _hits(X[n], W, flt)
    for n in ("B_Hilt", "B_HiltFin", "B_HiltGuard", "B_HiltBarrel", "B_BladeFX"): tot += _hits(X[n], W)
    K_ = {n: np.sort(_keys(v)) for n, v in X.items()}
    def isin(a, b): return int(np.isin(a, b, assume_unique=True).sum())
    tot += isin(K_["LowerArmL"], K_["LowerArmR"]) + isin(K_["LowerArmL"], K_["UpperArmR"]) + isin(K_["UpperArmL"], K_["LowerArmR"])
    bl = np.concatenate([K_["B_HiltBarrel"], K_["B_BladeFX"]])
    for a in ARMS: tot += isin(np.unique(bl), K_[a])
    tot += isin(K_["B_Hilt"], K_["LowerArmR"]) + isin(K_["B_HiltFin"], K_["LowerArmL"])
    for g in ("B_Hilt", "B_HiltFin", "B_HiltGuard"):
        tot += isin(K_[g], K_["UpperArmR"]) + isin(K_[g], K_["UpperArmL"])
    return tot


# ---------- 11-04 가드(방패 ③ 접이식 지지대) 자세와 같이 겹침 ----------
GUARD_PARTS = ("Rail1L", "Rail2L", "Rail3L", "KnuckleL", "ShieldL", "Rail1R", "Rail2R", "Rail3R", "KnuckleR", "ShieldR")


def guard_world(t):
    import valk_guard2 as G2
    return G2.frame(t)


def clash_guard(P, t, weapon="saber", detail=False):
    """가드 t(0~1)에서 팔 · 칼(또는 총) ↔ 방패 · 레일 · 마디 겹침(칸)."""
    M, B = V.model(); W = V.fk(P); X = guard_world(t)
    def wcells(n):
        p = M.parts[n]; ijk = np.argwhere(p.a > 0) + p.lo
        f = V.FOLLOW[n]; D = W[f] @ inv(V.REST[f])
        Wb = X[n] if n in X else (np.eye(4) if n in V.STRAIGHT else M.world(n))
        Tm = V.MB @ D @ V.MS @ Wb
        return _keys(ijk @ Tm[:3, :3].T + Tm[:3, 3])
    G = {n: wcells(n) for n in GUARD_PARTS}
    movers = {n: wcells(n) for n in ARMS}
    Wf = W["SaberHilt"] if weapon == "saber" else W["Rifle"] @ inv(V.VH_IN_HILT)
    for n, p in B.parts.items():
        if weapon != "saber" and n == "BladeFX": continue
        ijk = np.argwhere(p.a > 0) + p.lo
        Tm = V.MB @ Wf @ V.BLADE_IN_HILT @ V.MS @ B.world(n)
        movers["B_" + n] = _keys(ijk @ Tm[:3, :3].T + Tm[:3, 3])
    res = {}
    for a, ka in movers.items():
        for b, kb in G.items():
            c = int(np.isin(ka, kb).sum())
            if c: res[(a, b)] = c
    return (sum(res.values()), res) if detail else sum(res.values())
