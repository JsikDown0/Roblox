import numpy as np
import heavy_rig as hr
from heavy_rig import E, T, rx, rz, inv
from pads import POSES, PAIRS
BASE = {('UpperArmL', 'ShoulderPadL'): 1065, ('UpperArmR', 'ShoulderPadR'): 1050, ('ShoulderPadL', 'Torso'): 200, ('ShoulderPadR', 'Torso'): 200}
def pad_tf(SH, side, fX, fZ, hinge, z0, out=11):
    s = 1 if side == 'L' else -1          # 왼팔 바깥 = −X
    d = SH[:3, :3] @ np.array([0, -1.0, 0])
    th = np.degrees(np.arctan2(-d[2], -d[1]))            # 앞으로 든 각(+ = 앞)
    ph = np.degrees(np.arcsin(np.clip(-s * d[0], -1, 1)))  # 바깥으로 벌린 각(+ = 바깥)
    lat = max(0.0, ph - z0) * fZ
    h = np.array([s * hinge[0], hinge[1], 0.0])            # 관절점 기준 경첩(안쪽 위 모서리): 왼쪽은 +X 가 안쪽
    Lz = T(*h) @ rz(-s * lat) @ T(*-h)                      # 왼쪽은 바깥으로 들면 Z− (팔과 같은 방향)
    return rx(th * fX) @ Lz, th, ph
def score(fX, fZ, hinge, z0, verbose=False):
    tot = 0; rows = []
    for n in POSES:
        P = hr.base_pose(); P.update(POSES[n])
        for sd in 'LR':
            P['Pad' + sd], th, ph = pad_tf(P['Shoulder' + sd], sd, fX, fZ, hinge, z0)
        o = hr.overlaps(hr.fk(P), PAIRS)
        ex = {k: max(0, v - BASE.get(k, 0)) for k, v in o.items()}
        s = sum(ex.values()); tot += s
        if verbose: rows.append('%s:%d[%s]' % (n, s, ' '.join('%s/%s:%d' % (a[:5] + a[-1], b[:5] + b[-1], v) for (a, b), v in ex.items() if v > 30)))
    if verbose: print(' '.join(rows))
    return tot
if __name__ == '__main__':
    best = None
    for fX in (0.8, 1.0):
        for fZ in (0.5, 0.8, 1.0):
            for hinge in ((1.3, 3.2), (0.6, 3.2), (1.3, 1.5)):
                for z0 in (15, 30):
                    s = score(fX, fZ, hinge, z0)
                    print('fX %.1f fZ %.1f hinge %s z0 %d → %d' % (fX, fZ, hinge, z0, s), flush=True)
                    if best is None or s < best[0]: best = (s, fX, fZ, hinge, z0)
    print('BEST', best)
    score(*best[1:], verbose=True)
