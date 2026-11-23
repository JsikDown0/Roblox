"""fbxanim.py — Mixamo 스켈레톤 FBX → 프레임별 본 월드 변환(4x4, FBX 좌표 cm · Y 위)."""
import numpy as np, fbxbin
KT = 46186158000

def euler_xyz(deg):   # FBX 기본 회전 순서 eEulerXYZ: R = Rz · Ry · Rx (x 먼저)
    x, y, z = np.radians(deg)
    cx, sx, cy, sy, cz, sz = np.cos(x), np.sin(x), np.cos(y), np.sin(y), np.cos(z), np.sin(z)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]]); Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]); Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx

def load(path):
    ver, top = fbxbin.parse(path)
    T = {t.name: t for t in top}
    O = T["Objects"]
    models, curvenodes, curves = {}, {}, {}
    for c in O.children:
        if c.name == "Model":
            uid, nm = c.props[0], c.props[1].split("\x00")[0]
            P = {}
            p70 = c.first("Properties70")
            if p70:
                for p in p70.children: P[p.props[0]] = p.props[4:]
            models[uid] = dict(name=nm, P=P, parent=None, anim={})
        elif c.name == "AnimationCurveNode":
            curvenodes[c.props[0]] = dict(name=c.props[1].split("\x00")[0], ch={})
        elif c.name == "AnimationCurve":
            kt = c.first("KeyTime").props[0]; kv = c.first("KeyValueFloat").props[0]
            curves[c.props[0]] = (np.asarray(kt, float) / KT, np.asarray(kv, float))
    for c in T["Connections"].children:
        kind, a, b = c.props[0], c.props[1], c.props[2]
        if kind == "OO" and a in models and b in models: models[a]["parent"] = b
        elif kind == "OP" and a in curvenodes and b in models: models[b]["anim"][c.props[3]] = curvenodes[a]
        elif kind == "OP" and a in curves and b in curvenodes: curvenodes[b]["ch"][c.props[3]] = curves[a]
    return models

def local_at(m, t):
    P = m["P"]
    def prop(k, dflt): return np.array(P[k][:3], float) if k in P else np.array(dflt, float)
    tr = prop("Lcl Translation", (0, 0, 0)); rot = prop("Lcl Rotation", (0, 0, 0)); pre = prop("PreRotation", (0, 0, 0))
    post = prop("PostRotation", (0, 0, 0))
    for k, v in (("Lcl Translation", tr), ("Lcl Rotation", rot)):
        cn = m["anim"].get(k)
        if cn:
            for i, ax in enumerate(("d|X", "d|Y", "d|Z")):
                if ax in cn["ch"]:
                    kt, kv = cn["ch"][ax]; v[i] = np.interp(t, kt, kv)
    M = np.eye(4)
    M[:3, :3] = euler_xyz(pre) @ euler_xyz(rot) @ np.linalg.inv(euler_xyz(post))
    M[:3, 3] = tr
    return M

def world_at(models, t):
    W = {}
    def w(uid):
        if uid in W: return W[uid]
        m = models[uid]
        L = local_at(m, t)
        W[uid] = (w(m["parent"]) @ L) if m["parent"] in models else L
        return W[uid]
    for u in models: w(u)
    return {models[u]["name"]: M for u, M in W.items()}

def span(models):
    ts = [kt for m in models.values() for cn in m["anim"].values() for kt, kv in cn["ch"].values()]
    return min(t.min() for t in ts), max(t.max() for t in ts), max(len(t) for t in ts)
