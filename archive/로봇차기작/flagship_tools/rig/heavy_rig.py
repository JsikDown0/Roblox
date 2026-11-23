"""heavy_rig.py — Studio HeavyTemplate 관절(heavy_rig.json)을 그대로 옮긴 파이썬 FK·IK + 복셀 겹침 (10-26)
  CFrame = 4x4 (Roblox 성분 순서 x,y,z,R00..R22). E(x,y,z) = Ry·Rx·Rz (MechClient 와 같음).
"""
import json, sys
import numpy as np
sys.path.insert(0, '/home/claude/flag/rig'); sys.path.insert(0, '/home/claude/flag')
import voxcheck as vc

RIG = json.load(open('/home/claude/flag/rig/heavy_rig.json'))
def cf(c):
    m = np.eye(4); m[:3, :3] = np.array(c[3:]).reshape(3, 3); m[:3, 3] = c[:3]; return m
def T(x=0, y=0, z=0): m = np.eye(4); m[:3, 3] = [x, y, z]; return m
def rx(a):
    a = np.radians(a); c, s = np.cos(a), np.sin(a); m = np.eye(4); m[1:3, 1:3] = [[c, -s], [s, c]]; return m
def ry(a):
    a = np.radians(a); c, s = np.cos(a), np.sin(a); m = np.eye(4); m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, s, -s, c; return m
def rz(a):
    a = np.radians(a); c, s = np.cos(a), np.sin(a); m = np.eye(4); m[0:2, 0:2] = [[c, -s], [s, c]]; return m
def E(x=0, y=0, z=0): return ry(y) @ rx(x) @ rz(z)
inv = np.linalg.inv
JOINTS = {j['name']: dict(p0=j['p0'], p1=j['p1'], c0=cf(j['c0']), c1=cf(j['c1'])) for j in RIG['joints']}
PARTS0 = {k: cf(v) for k, v in RIG['parts'].items()}
ORIG = {k: cf(v) for k, v in RIG['orig'].items()}
GRIPC1 = cf(RIG['gripC1'])
ROOT = T(0, 15, 0)

def fk(P, root=ROOT):
    W = {'HumanoidRootPart': root}
    ch = True
    while ch:
        ch = False
        for n, j in JOINTS.items():
            if j['p0'] in W and j['p1'] not in W:
                W[j['p1']] = W[j['p0']] @ j['c0'] @ P.get(n, np.eye(4)) @ inv(j['c1']); ch = True
    W['RifleStowed'] = W['Torso'] @ inv(PARTS0['Torso']) @ PARTS0['RifleStowed']
    return W

def solve_arm(S, a, b, target, poleW):
    t = (inv(S) @ np.append(target, 1))[:3]
    d = np.linalg.norm(t)
    K = (d * d - a @ a - b @ b) / 2 - a[0] * b[0]
    P1 = a[1] * b[1] + a[2] * b[2]
    Q1 = a[2] * b[1] - a[1] * b[2]
    R = np.hypot(P1, Q1)
    th = np.arctan2(Q1, P1) + np.arccos(np.clip(K / R, -1, 1))
    v = a + np.array([b[0], b[1] * np.cos(th) - b[2] * np.sin(th), b[1] * np.sin(th) + b[2] * np.cos(th)])
    X1 = v / np.linalg.norm(v)
    hinge = np.array([1.0, 0, 0]) - X1 * X1[0]
    Y1 = np.cross(X1, hinge); Y1 /= np.linalg.norm(Y1)
    X2 = t / np.linalg.norm(t)
    p = S[:3, :3].T @ poleW
    Y2 = p - X2 * (p @ X2); Y2 /= np.linalg.norm(Y2)
    F1 = np.eye(4); F1[:3, :3] = np.stack([X1, Y1, np.cross(X1, Y1)], 1)
    F2 = np.eye(4); F2[:3, :3] = np.stack([X2, Y2, np.cross(X2, Y2)], 1)
    return F2 @ inv(F1), np.degrees(th)

def torso_frame(P, root=ROOT):
    jr, jw = JOINTS['Root'], JOINTS['Waist']
    return root @ jr['c0'] @ P.get('Root', np.eye(4)) @ inv(jr['c1']) @ jw['c0'] @ P.get('Waist', np.eye(4)) @ inv(jw['c1'])

def arm_ik(P, side, target, pole_local):
    """P 의 몸통 자세에서 손(라이플 Grip / SaberGrip 점)을 target 으로. pole 은 몸통 로컬."""
    Tt = torso_frame(P)
    sh, el = JOINTS['Shoulder' + side], JOINTS['Elbow' + side]
    hp = JOINTS['Grip' if side == 'R' else 'SaberGrip']['c0']
    S = Tt @ sh['c0']
    a = (inv(sh['c1']) @ el['c0'])[:3, 3]
    b = (inv(el['c1']) @ T(*hp[:3, 3]))[:3, 3]
    Rs, th = solve_arm(S, a, b, np.array(target, float), Tt[:3, :3] @ np.array(pole_local, float))
    return Rs, rx(th), th

def angle(M):
    return np.degrees(np.arccos(np.clip((np.trace(M[:3, :3]) - 1) / 2, -1, 1)))

def posed_points(W):
    pts = vc.rest_points()
    out = {}
    for n, P in pts.items():
        G = W[n] @ inv(ORIG[n])
        out[n] = P @ G[:3, :3].T + G[:3, 3]
    for n in ('Rifle', 'RifleStowed'):
        Tn = W[n]; out[n] = vc.RIFLE @ Tn[:3, :3].T + Tn[:3, 3]
    Tn = W['SaberHilt']; out['SaberHilt'] = vc.HILT @ Tn[:3, :3].T + Tn[:3, 3]; out['SaberBlade'] = vc.BLADE @ Tn[:3, :3].T + Tn[:3, 3]
    return out

def overlaps(W, pairs, keys=None):
    O = posed_points(W)
    K = keys if keys is not None else {}
    for a, b in pairs:
        for n in (a, b):
            if n not in K: K[n] = vc.keyset(O[n])
    return {(a, b): len(np.intersect1d(K[a], K[b], assume_unique=True)) for a, b in pairs}

def base_pose(out=11):
    P = dict(Root=np.eye(4), Waist=E(-3), Neck=np.eye(4), ShoulderR=E(12, 0, out), ElbowR=E(62), ShoulderL=E(4, 0, -4 - out), ElbowL=E(16))
    legs(P, 4, 4, -8, -8)
    return P
def legs(P, hl, hr, kl, kr):
    P['HipL'], P['HipR'], P['KneeL'], P['KneeR'] = E(hl), E(hr), E(kl), E(kr)
    P['AnkleL'], P['AnkleR'] = E(-0.6 * (hl + kl)), E(-0.6 * (hr + kr))
