"""땅굴 사출 경로를 MechClient 와 같은 식(pathFrame · LAUNCH_BLEND 10 · 발 + 위 방향 × RootUp)으로 따라가며 중장갑 복셀이 구조물에 닿는지"""
import json, numpy as np
import heavy_rig as hr, opt, voxcheck as vc
from heavy_rig import E, T
D = json.load(open('tunnel.json'))
pts = [np.array(p, float) for p in D['pts']]
segs = []; total = 0
for a, b in zip(pts[:-1], pts[1:]):
    t = (b - a) / np.linalg.norm(b - a)
    side = np.cross(t, [0, 1, 0]); side = side / np.linalg.norm(side) if np.linalg.norm(side) > 1e-3 else np.array([1.0, 0, 0])
    n = np.cross(side, t); n /= np.linalg.norm(n)
    segs.append(dict(a=a, t=t, n=n, len=np.linalg.norm(b - a), s0=total)); total += np.linalg.norm(b - a)
def sm(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def frame(s):
    s = min(max(s, 0), total)
    i = len(segs) - 1
    for k, g in enumerate(segs):
        if s < g['s0'] + g['len']: i = k; break
    g = segs[i]; foot = g['a'] + g['t'] * (s - g['s0']); t, n = g['t'].copy(), g['n'].copy()
    if i + 1 < len(segs):
        dd = g['s0'] + g['len'] - s
        if dd < 10: w = 0.5 * sm(1 - dd / 10); t = t + (segs[i + 1]['t'] - t) * w; t /= np.linalg.norm(t); n = n + (segs[i + 1]['n'] - n) * w; n /= np.linalg.norm(n)
    if i > 0:
        dd = s - g['s0']
        if dd < 10: w = 0.5 * sm(1 - dd / 10); t = t + (segs[i - 1]['t'] - t) * w; t /= np.linalg.norm(t); n = n + (segs[i - 1]['n'] - n) * w; n /= np.linalg.norm(n)
    return foot, t, n
def lookat(pos, fwd, up):
    z = -fwd / np.linalg.norm(fwd); x = np.cross(up, z); x /= np.linalg.norm(x); y = np.cross(z, x)
    m = np.eye(4); m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = x, y, z, pos; return m
boxes = []
for b in D['boxes']:
    boxes.append((b['n'], hr.cf(b['c']), np.array(b['s']) / 2))
def hits(P):
    hit = {}
    lo, hi = P.min(0) - 1, P.max(0) + 1
    for name, C, h in boxes:
        r = np.abs(C[:3, :3]) @ h
        if np.any(C[:3, 3] + r < lo) or np.any(C[:3, 3] - r > hi): continue
        q = (P - C[:3, 3]) @ C[:3, :3]
        inside = np.all(np.abs(q) < h - 0.05, axis=1)
        if inside.any(): hit[name] = int(inside.sum())
    return hit
# 사출 중 자세: 웅크림 1.6 × legK, 숙임 16° (riding 가속 뒤 w = 1)
LK = 1.38
for label, drop, lean in (('crouched(실제)', 1.6 * LK, 16), ('upright(최악)', 0.0, 0)):
    P = hr.base_pose()
    if drop > 0:
        import skirts; a, b = skirts.crouch(drop)
        P['Root'] = T(0, -drop, 0)
        for s_ in 'LR':
            P['Hip' + s_] = P['Hip' + s_] @ E(a); P['Knee' + s_] = P['Knee' + s_] @ E(-(a + b)); P['Ankle' + s_] = P['Ankle' + s_] @ E(b)
        P['Waist'] = E(-3 - lean)
    P = opt.finish(P)
    W0 = hr.fk(P, root=np.eye(4))           # 루트 = 원점
    O = hr.posed_points(W0)
    names = [n for n in O if n not in ('RifleStowed', 'SaberHilt', 'SaberBlade')]
    body = np.vstack([O[n] for n in names])
    q = np.unique(np.round(body / 0.4).astype(int), axis=0); body = q * 0.4   # 0.4 격자로 줄임
    rootUp = D['rootUp'] + (15.05 - 11.6)
    worst = {}
    top = -1e9
    for s in np.arange(0, total + 0.01, 1.0):
        foot, t, n = frame(s)
        R = lookat(foot + n * rootUp, t, n)
        Pw = body @ R[:3, :3].T + R[:3, 3]
        h = hits(Pw)
        for k, v in h.items():
            if v > worst.get(k, (0, 0))[0]: worst[k] = (v, round(float(s), 0))
    print(label, 'rootUp %.2f' % rootUp, 'path len %.1f' % total, {k: v for k, v in worst.items()} or 'clean')
