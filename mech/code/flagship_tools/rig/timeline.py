import numpy as np
import heavy_rig as hr, opt
from heavy_rig import E, T
from pads import slerp_rot
def lerpcf(A, B, a):
    R = slerp_rot(np.linalg.inv(A) @ B, a)
    out = A @ R; out[:3, 3] = A[:3, 3] + (B[:3, 3] - A[:3, 3]) * a
    return out
def blend(A, B, a):
    o = {}
    for n in set(A) | set(B): o[n] = lerpcf(A.get(n, np.eye(4)), B.get(n, np.eye(4)), a)
    return o
C = lambda *r: (lambda m: m)(np.block([[np.array(r).reshape(3, 3), np.zeros((3, 1))], [np.zeros((1, 3)), np.ones((1, 1))]]))
Q = dict(
    G=dict(Root=T(0, -0.2, 0), Waist=E(4, 15), Neck=E(0, -10), ShoulderL=C(0.78577, 0.40702, -0.46573, 0.20073, -0.88003, -0.43041, -0.58504, 0.24472, -0.77320), ElbowL=E(105.2), SaberGrip=C(0.99990, 0.00244, 0.01378, 0.00007, 0.98378, -0.17936, -0.01399, 0.17935, 0.98369)),
    W=dict(Root=T(0, -0.3, 0), Waist=E(6, 30), Neck=E(-4, -18), ShoulderL=E(165, 0, -25), ElbowL=E(45), SaberGrip=E(40)),
    S=dict(Root=T(0, -1, 0), Waist=E(-16, -20), Neck=E(8, 12), ShoulderL=E(60, 0, 18), ElbowL=E(6), SaberGrip=E(-25)),
    F=dict(Root=T(0, -1.2, 0), Waist=E(-14, -28), Neck=E(6, 16), ShoulderL=E(48, 10, 26), ElbowL=E(12), SaberGrip=E(-32)),
    S2A=dict(Root=T(0, -0.6, 0), Waist=E(-4, -30), Neck=E(0, 18), ShoulderL=E(18.9, -10.8, -6.6), ElbowL=E(91.0), SaberGrip=E(-97.7)),
    S2B=dict(Root=T(0, -0.8, 0), Waist=E(-6, 28), Neck=E(0, -16), ShoulderL=E(-29.6, -35.2, -111.2), ElbowL=E(86.2), SaberGrip=E(-162.4)),
    S2C=dict(Root=T(0, -0.8, 0), Waist=E(-4, 36), Neck=E(0, -20), ShoulderL=E(-25.8, -8.4, -98.1), ElbowL=E(109.0), SaberGrip=E(168.0)),
    S3A=dict(Root=T(0, -0.8, 0), Waist=E(-4, 22), Neck=E(0, -14), ShoulderL=E(-46, -16, -42), ElbowL=E(129), SaberGrip=E(-65)),
    S3B=dict(Root=T(0, -1.4, 0), Waist=E(-8, -26), Neck=E(0, 18), ShoulderL=E(89.2, -2.0, -13.4), ElbowL=E(5.0), SaberGrip=E(-85.0)),
    S3C=dict(Root=T(0, -1.2, 0), Waist=E(-6, -20), Neck=E(0, 14), ShoulderL=E(84, -2, -10), ElbowL=E(16), SaberGrip=E(-82)),
    PW=dict(Root=T(0, -0.3, 0), Waist=E(2, 28), Neck=E(0, -16), ShoulderL=E(25, 0, -6), ElbowL=E(95)),
    PS=dict(Root=T(0, -0.8, 0), Waist=E(-10, -26), Neck=E(6, 14), ShoulderL=E(86, 0, 10), ElbowL=E(4)),
)
base = hr.base_pose()
R = dict(Root=base['Root'], Waist=base['Waist'], Neck=base['Neck'], ShoulderL=E(5.2, -5.3, -11.3), ElbowL=E(83.5), SaberGrip=E(-38.1))
IDLE_L = dict(ShoulderL=base['ShoulderL'], ElbowL=base['ElbowL'], SaberGrip=np.eye(4), Root=base['Root'], Waist=base['Waist'], Neck=base['Neck'])
FREE_R = dict(ShoulderR=E(4, 0, 15), ElbowR=E(16), Grip=np.eye(4))
STOW = dict(ShoulderR=C(0.77251, -0.35405, 0.52713, -0.45199, 0.27648, 0.84809, -0.44601, -0.89342, 0.05355), ElbowR=E(89.8), Grip=C(0.44601, -0.45199, 0.77251, 0.89359, 0.27378, -0.35573, -0.05072, 0.84897, 0.52601))
MID = dict(ShoulderR=E(-12, 0, 22), ElbowR=E(30), Grip=np.eye(4))
LOWR = dict(ShoulderR=base['ShoulderR'], ElbowR=base['ElbowR'], Grip=np.eye(4))
SEQ = {
    'draw(R키)': [IDLE_L, Q['G'], Q['W'], Q['S'], Q['F']],
    'equip(2)': [IDLE_L, Q['G'], Q['W'], R],
    'slash1': [R, Q['W'], Q['S'], Q['F'], R],
    'slash2': [Q['F'], Q['S2A'], Q['S2B'], Q['S2C'], R],
    'slash3': [Q['S2C'], Q['S3A'], Q['S3B'], Q['S3C'], R],
    'unequip(1)': [R, Q['G'], IDLE_L],
    'punch': [IDLE_L, Q['PW'], Q['PS'], IDLE_L],
    'rifle→back': [LOWR, MID, STOW, FREE_R],
}
MOVL = ['UpperArmL', 'LowerArmL', 'SaberHilt', 'SaberBlade']
MOVR = ['UpperArmR', 'LowerArmR', 'Rifle']
if __name__ == '__main__':
    for name, keys in SEQ.items():
        worst = (0, None, None)
        for i in range(len(keys) - 1):
            for a in np.linspace(0, 1, 6)[1:]:
                P = hr.base_pose(); P.update(blend(keys[i], keys[i + 1], a))
                mov = MOVR if name.startswith('rifle') else (['UpperArmL', 'LowerArmL'] if name == 'punch' else MOVL)
                if name.startswith(('draw', 'equip', 'unequip')) and i == 0 and a < 0.99: mov = ['UpperArmL', 'LowerArmL']   # 칼은 잡은 뒤에만 보임
                if name.startswith('rifle'):
                    c, det, _ = opt.collide(P, mov, extra_pairs=[('Rifle', 'UpperArmL'), ('Rifle', 'LowerArmL')])
                else:
                    c, det, _ = opt.collide(P, mov)
                if 'SaberHilt' in mov: c -= det.get(('SaberHilt', 'Backpack'), 0) + det.get(('SaberBlade', 'Backpack'), 0) if (i == 0 or (name.startswith('unequip') and i == 0)) else 0
                if c > worst[0]: worst = (c, '%d→%d @%.1f' % (i, i + 1, a), {'%s/%s' % k: v for k, v in det.items()})
        print('%-11s worst %4d %s %s' % (name, worst[0], worst[1] or '', worst[2] or ''), flush=True)
