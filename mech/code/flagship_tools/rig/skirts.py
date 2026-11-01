import numpy as np
import heavy_rig as hr
from heavy_rig import E, T, rx, rz
CR = [(0.00, 0, 0.0), (0.09, 4, 2.8), (0.23, 8, 5.7), (0.40, 12, 8.5), (0.61, 16, 11.3), (0.86, 20, 14.0), (1.15, 24, 16.7), (1.46, 28, 19.4), (1.81, 32, 21.9), (2.18, 36, 24.4),
      (2.58, 40, 26.8), (2.99, 44, 29.1), (3.42, 48, 31.2), (3.86, 52, 33.3), (4.31, 56, 35.1), (4.76, 60, 36.8), (5.20, 64, 38.2), (5.64, 68, 39.4), (6.06, 72, 40.4), (6.47, 76, 41.1), (6.86, 80, 41.5)]
def crouch(drop):
    for i in range(1, len(CR)):
        if drop <= CR[i][0]:
            u = (drop - CR[i - 1][0]) / (CR[i][0] - CR[i - 1][0]); return CR[i - 1][1] + (CR[i][1] - CR[i - 1][1]) * u, CR[i - 1][2] + (CR[i][2] - CR[i - 1][2]) * u
    return CR[-1][1], CR[-1][2]
def legpose(hl, hr_, kl, kr, al=0, ar=0, drop=0, lean=0):
    P = hr.base_pose()
    P['HipL'], P['HipR'], P['KneeL'], P['KneeR'], P['AnkleL'], P['AnkleR'] = E(hl), E(hr_), E(kl), E(kr), E(al), E(ar)
    if drop > 0:
        a, b = crouch(drop)
        P['Root'] = T(0, -drop, 0)
        for s in 'LR':
            P['Hip' + s] = P['Hip' + s] @ E(a); P['Knee' + s] = P['Knee' + s] @ E(-(a + b)); P['Ankle' + s] = P['Ankle' + s] @ E(b)
        P['Waist'] = E(-3 - lean)
    return P
def walk(s, c, a=1.0):
    sw = 26 * s * a
    kl = -(8 + 36 * a * max(0, c)); kr = -(8 + 36 * a * max(0, -c))
    hl = 4 + sw; hr_ = 4 - sw
    return legpose(hl, hr_, kl, kr, -0.6 * (hl + kl), -0.6 * (hr_ + kr))
POSES = {}
for i, ph in enumerate(np.linspace(0, 2 * np.pi, 8, endpoint=False)):
    POSES['walk%d' % i] = walk(np.sin(ph), np.cos(ph))
POSES['boost'] = legpose(40, -18, -50, -30, 14, 32)
POSES['boostBack'] = legpose(26, -8, -30, -42, -6, 28)
POSES['airTuck'] = legpose(26, 10, -48, -28, 14, 10)
POSES['airFall'] = legpose(14, 4, -20, -14, 6, 6)
POSES['airRise'] = legpose(6, -8, -12, -8, -6, -4)
P0 = (4, 4, -8, -8, 2.4, 2.4)
POSES['jumpCrouch'] = legpose(*P0, drop=2.8 * 1.38, lean=16)
POSES['landHard'] = legpose(*P0, drop=3.0 * 1.38, lean=14)
POSES['launchCrouch'] = legpose(*P0, drop=1.6 * 1.38, lean=16)
PAIRS = [(l, s) for l in ('UpperLegL', 'UpperLegR', 'LowerLegL', 'LowerLegR') for s in ('SkirtFL', 'SkirtFR', 'SkirtSL', 'SkirtSR')]
def hipx(M):   # E(x) 만 쓰는 엉덩이 → X 각
    return np.degrees(np.arctan2(M[2, 1], M[1, 1]))
def skirts(P, fF, fB, fS, oS):
    for s, sg in (('L', -1), ('R', 1)):
        hx = hipx(P['Hip' + s])
        P['SkirtJointF' + s] = rx(fF * max(0, hx) + fB * min(0, hx))
        P['SkirtJointS' + s] = rx(fS * hx) @ rz(sg * oS * max(0, hx))
    return P
def score(fF, fB, fS, oS, verbose=False):
    tot = 0; rows = []
    for n, P0_ in POSES.items():
        P = skirts(dict(P0_), fF, fB, fS, oS)
        o = hr.overlaps(hr.fk(P), PAIRS)
        s = sum(o.values()); tot += s
        if verbose and s: rows.append('%s:%d[%s]' % (n, s, ' '.join('%s/%s:%d' % (a[-4:], b[-2:], v) for (a, b), v in o.items() if v)))
    if verbose: print(' '.join(rows) or 'clean')
    return tot
if __name__ == '__main__':
    print('no follow', score(0, 0, 0, 0, True))
    best = None
    for fF in (0.5, 0.7, 0.9):
        for fB in (0.0, 0.3):
            for fS in (0.0, 0.3, 0.5):
                for oS in (0.0, 0.15, 0.3):
                    s = score(fF, fB, fS, oS)
                    if best is None or s < best[0] or (s == best[0] and fF + fS + oS < sum(best[1:])): best = (s, fF, fB, fS, oS)
    print('BEST', best); score(*best[1:], verbose=True)
