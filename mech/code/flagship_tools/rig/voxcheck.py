"""voxcheck.py — Studio 가 계산한 자세별 파트 CFrame(heavy_pose_dump.json)으로 중장갑 복셀을 놓고 겹침을 센다 (10-26)
  파트 메시는 원래 임포트(쉬는 자세 = 팔 STANCE) 위치에 구워져 있으므로 G = C'(자세) · C_orig⁻¹ 로 옮긴다.
"""
import json, sys
import numpy as np
sys.path.insert(0, '/home/claude/flag')
import final_m2b as fm
import heavy_mesh_export as hx

GRID = 0.25
MAP = {'Torso': ['Torso', 'ChestNew'], 'Backpack': ['Backpack', 'RackL', 'RackR'], 'ShoulderPadL': ['ShoulderL'], 'ShoulderPadR': ['ShoulderR']}

def cf(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    m = np.eye(4); m[:3, :3] = [[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]]; m[:3, 3] = [x, y, z]
    return m

_cache = {}
def rest_points():
    if _cache: return _cache
    M = fm.build_all()
    for rname in ['Pelvis', 'Torso', 'Head', 'Backpack', 'ShoulderPadL', 'ShoulderPadR', 'UpperArmL', 'UpperArmR', 'LowerArmL', 'LowerArmR',
                  'SkirtFL', 'SkirtFR', 'SkirtSL', 'SkirtSR', 'UpperLegL', 'UpperLegR', 'LowerLegL', 'LowerLegR', 'FootL', 'FootR']:
        pts = []
        for vn in MAP.get(rname, [rname]):
            p = M.parts[vn]
            idx = np.argwhere(p.a > 0) + np.array(p.lo)
            W = M.world(vn, hx.REST_POSE)
            P = idx @ W[:3, :3].T + W[:3, 3]
            pts.append(np.stack([-P[:, 0], P[:, 2], P[:, 1]], 1) * 0.1)
        _cache[rname] = np.vstack(pts)
    return _cache

def box_pts(sx, sy, sz, step=0.25):
    xs = np.arange(sx[0], sx[1] + 1e-6, step); ys = np.arange(sy[0], sy[1] + 1e-6, step); zs = np.arange(sz[0], sz[1] + 1e-6, step)
    g = np.stack(np.meshgrid(xs, ys, zs, indexing='ij'), -1).reshape(-1, 3)
    return g

RIFLE = box_pts((-0.45, 0.45), (-1.2, 1.4), (-7.3, 7.3))       # 라이플 몸통 근사(실제 메시보다 약간 얇게)
HILT = box_pts((-0.4, 0.4), (-1.9, 1.9), (-0.4, 0.4))
BLADE = box_pts((-0.22, 0.22), (2.0, 13.0), (-0.22, 0.22))

def keyset(P):
    q = np.floor(P / GRID).astype(np.int64)
    return np.unique((q[:, 0] + 4000) * 64000000 + (q[:, 1] + 4000) * 8000 + (q[:, 2] + 4000))

def posed(dump, pose):
    pts = rest_points()
    orig = dump['orig']; cur = dump['poses'][pose]
    out = {}
    for n, P in pts.items():
        G = cf(cur[n]) @ np.linalg.inv(cf(orig[n]))
        out[n] = P @ G[:3, :3].T + G[:3, 3]
    for n, L in (('Rifle', RIFLE), ('RifleStowed', RIFLE)):
        if n in cur:
            T = cf(cur[n]); out[n] = L @ T[:3, :3].T + T[:3, 3]
    if 'SaberHilt' in cur:
        T = cf(cur['SaberHilt']); out['SaberHilt'] = HILT @ T[:3, :3].T + T[:3, 3]; out['SaberBlade'] = BLADE @ T[:3, :3].T + T[:3, 3]
    return out

BODY = ['Torso', 'Pelvis', 'Head', 'Backpack', 'ShoulderPadL', 'ShoulderPadR', 'SkirtFL', 'SkirtFR', 'SkirtSL', 'SkirtSR', 'UpperLegL', 'UpperLegR']
ARMS = ['UpperArmL', 'UpperArmR', 'LowerArmL', 'LowerArmR']
SKIP = {('UpperArmL', 'Torso'), ('UpperArmR', 'Torso'), ('UpperArmL', 'ShoulderPadL'), ('UpperArmR', 'ShoulderPadR')}

def check(dump, pose, pairs=None, saber=False, stowed=False):
    O = posed(dump, pose)
    K = {n: keyset(P) for n, P in O.items()}
    res = []
    A = ARMS + ['Rifle'] + (['SaberHilt', 'SaberBlade'] if saber else []) + (['RifleStowed'] if stowed else [])
    for a in A:
        for b in BODY + ARMS + (['RifleStowed'] if stowed and a != 'RifleStowed' else []):
            if a == b or (a, b) in SKIP: continue
            if a in ARMS and b in ARMS and a < b: continue
            if a == 'Rifle' and b in ('LowerArmR',): continue
            if a in ('SaberHilt', 'SaberBlade') and b == 'LowerArmL': continue
            if a.startswith('UpperArm') and b.startswith('LowerArm') and a[-1] == b[-1]: continue
            n = len(np.intersect1d(K[a], K[b], assume_unique=True))
            if n: res.append((a, b, n))
    # 다리 vs 스커트
    for a in ['UpperLegL', 'UpperLegR', 'LowerLegL', 'LowerLegR']:
        for b in ['SkirtFL', 'SkirtFR', 'SkirtSL', 'SkirtSR']:
            n = len(np.intersect1d(K[a], K[b], assume_unique=True))
            if n: res.append((a, b, n))
    return res, O

if __name__ == '__main__':
    dump = json.load(open(sys.argv[1]))
    poses = sys.argv[2].split(',') if len(sys.argv) > 2 else sorted(dump['poses'])
    for p in poses:
        sab = p.startswith(('saber', 'slash'))
        res, O = check(dump, p, saber=sab, stowed=p in ('stow', 'saberR', 'slash2A', 'slash2B', 'slash2C', 'slash3A', 'slash3B'))
        extra = ''
        if 'Rifle' in O: extra = ' muzzleY %.1f' % O['Rifle'][:, 1].min()
        print('%-9s' % p, ' '.join('%s/%s:%d' % r for r in sorted(res, key=lambda r: -r[2])) or 'clean', extra)
