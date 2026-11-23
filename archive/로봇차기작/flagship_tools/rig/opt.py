import numpy as np
import heavy_rig as hr
import voxcheck as vc
from heavy_rig import E, T, rx, rz, inv
import pads2, skirts
PADP = (1.0, 1.0, (1.3, 3.2), 15)
SK = (0.5, 0.0, 0.5, 0.15)
BODY = ['Torso', 'Pelvis', 'Head', 'Backpack', 'ShoulderPadL', 'ShoulderPadR', 'SkirtFL', 'SkirtFR', 'SkirtSL', 'SkirtSR', 'UpperLegL', 'UpperLegR']
BASE = {('UpperArmL', 'ShoulderPadL'): 1065, ('UpperArmR', 'ShoulderPadR'): 1050, ('UpperArmL', 'Torso'): 10 ** 9, ('UpperArmR', 'Torso'): 10 ** 9}
def finish(P):
    for sd in 'LR':
        P['Pad' + sd] = pads2.pad_tf(P['Shoulder' + sd], sd, *PADP)[0]
    skirts.skirts(P, *SK)
    return P
_rest_keys = {}
def keys_for(W, names):
    O = hr.posed_points(W)
    return {n: vc.keyset(O[n]) for n in names}
def collide(P, movers, extra_pairs=(), base=None):
    P = finish(dict(P))
    W = hr.fk(P)
    names = set(movers) | set(BODY) | {b for _, b in extra_pairs} | {a for a, _ in extra_pairs}
    K = keys_for(W, names)
    tot, det = 0, {}
    pairs = [(a, b) for a in movers for b in BODY] + list(extra_pairs)
    for a, b in pairs:
        if a == b: continue
        n = len(np.intersect1d(K[a], K[b], assume_unique=True))
        n = max(0, n - (base or BASE).get((a, b), 0))
        if n: det[(a, b)] = n; tot += n
    return tot, det, W
def descend(make, x0, movers, w_dev=2.0, steps=(8, 4, 2, 1), extra=(), base=None, fixed_cost=None, log=False):
    x = list(x0); best, det, _ = collide(make(x), movers, extra, base)
    cost = best * 1.0 + (fixed_cost(x) if fixed_cost else 0)
    for st in steps:
        improved = True
        while improved:
            improved = False
            for i in range(len(x)):
                for d in (st, -st):
                    y = list(x); y[i] += d
                    c, dt, _ = collide(make(y), movers, extra, base)
                    dev = w_dev * sum(abs(a - b) for a, b in zip(y, x0))
                    tc = c + dev + (fixed_cost(y) if fixed_cost else 0)
                    if tc < cost - 1e-9:
                        x, cost, best, det, improved = y, tc, c, dt, True
        if log: print('  step', st, 'x', [round(v, 1) for v in x], 'col', best, flush=True)
    return x, best, det
