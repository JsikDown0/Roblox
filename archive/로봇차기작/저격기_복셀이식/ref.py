"""ref.py — Rodin Sniper3(base_3 + codeA5) → 우리 칸 좌표 참고 메시.
다리·팔뚝을 곧게 펴고(쉬는 자세), 허벅지·정강이를 축 방향 1.4배(유저 결정 ③), 발바닥 z=0, 머리 꼭대기 268칸.
축은 같음: +X = 기체 왼쪽 · −Y = 정면 · +Z = 위.  python3 ref.py → ref/ref_mesh.npz"""
import os as _os
_HERE = _os.path.dirname(_os.path.abspath(__file__))
import numpy as np
NAMES = ["Pelvis", "Torso", "Head", "ShoulderPadL", "ShoulderPadR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
         "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR"]
IX = {n: i for i, n in enumerate(NAMES)}
K = 1.4
TOP = 268.0
HIP, KNEE, ANK = np.array([0.174, -0.06, 0.93]), np.array([0.215, 0.043, 0.57]), np.array([0.307, 0.062, 0.13])
ELB = np.array([0.247, -0.001, 1.373]); HAND = np.array([0.294, -0.087, 0.971])
SHO = np.array([0.25, -0.01, 1.5])


def rot_to_down(d):
    """d 를 (0,0,-1) 로 돌리는 최소 회전."""
    a = d / np.linalg.norm(d); b = np.array([0, 0, -1.0])
    v = np.cross(a, b); c = a @ b; s = np.linalg.norm(v)
    if s < 1e-9: return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * ((1 - c) / s ** 2)


def build():
    M = np.load(_os.path.join(_HERE, 'ref', 'mesh.npz')); V, F = M['Vw'].astype(float), M['Fw']
    code = np.load(_os.path.join(_HERE, 'ref', 'codeA5.npy')).astype(int); P = code // 3; Z = code % 3
    # 면 → 꼭짓점 소속(파트별로 따로 변환하려고 꼭짓점을 면마다 복제)
    T = V[F]                                  # (n,3,3)
    out = T.copy()
    Rt = rot_to_down(KNEE - HIP); Rs = rot_to_down(ANK - KNEE); Ra = rot_to_down(HAND - ELB)
    Lt, Ls = np.linalg.norm(KNEE - HIP), np.linalg.norm(ANK - KNEE)
    knee_n = HIP + np.array([0, 0, -K * Lt]); ank_n = knee_n + np.array([0, 0, -K * Ls])
    def st(R, c, v, k):                       # c 기준 회전 후 z 로 k 배
        w = (v - c) @ R.T; w[..., 2] *= k; return w
    for side, sx in (("L", 1), ("R", -1)):
        m = np.array([sx, 1, 1.0])
        for part, fn in ((f"UpperLeg{side}", lambda v: HIP * m + st(Rt, HIP, v * m, K) * m),
                         (f"LowerLeg{side}", lambda v: knee_n * m + st(Rs, KNEE, v * m, K) * m),
                         (f"Foot{side}", lambda v: ank_n * m + (v * m - ANK) * m),
                         (f"LowerArm{side}", lambda v: ELB * m + st(Ra, ELB, v * m, 1.0) * m)):
            sel = P == IX[part]
            out[sel] = fn(T[sel])
            # 오른쪽은 L 관절을 거울로 쓰므로 R 파트 좌표를 x 반전해 L 식에 넣고 다시 반전
    zmin = out[np.isin(P, [IX["FootL"], IX["FootR"]])][..., 2].min()
    out[..., 2] -= zmin
    s = TOP / out[..., 2].max()
    out *= s
    J = {}
    for nm, v in (("HIP", HIP), ("KNEE", knee_n), ("ANKLE", ank_n), ("SHOULDER", SHO), ("ELBOW", ELB), ("HAND", ELB + np.array([0, 0, -np.linalg.norm(HAND - ELB)]))):
        J[nm] = ((v - [0, 0, zmin]) * s).round(1)
    for nm, v in (("NECK", np.array([0, -0.03, 1.66])), ("WAIST", np.array([0, -0.06, 1.34])), ("PADPIV", np.array([0.2, -0.01, 1.6]))):
        J[nm] = ((v - [0, 0, zmin]) * s).round(1)
    return out, P, Z, J, s


if __name__ == "__main__":
    tri, P, Z, J, s = build()
    np.savez_compressed(_os.path.join(_HERE, 'ref', 'ref_mesh.npz'), tri=tri.astype(np.float32), P=P.astype(np.uint8), Z=Z.astype(np.uint8))
    import json; json.dump({k: v.tolist() for k, v in J.items()} | {"scale_cells_per_unit": s}, open(_os.path.join(_HERE, 'ref', 'joints.json'), 'w'), indent=1)
    print('scale', round(s, 2), 'cells/unit'); [print(k, v) for k, v in J.items()]
    for i, n in enumerate(NAMES):
        t = tri[P == i].reshape(-1, 3)
        print(f'{n:13s} lo {t.min(0).round(0)} hi {t.max(0).round(0)}')
