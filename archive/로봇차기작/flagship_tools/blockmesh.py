"""
blockmesh.py — 모따기 블록 메시 모델러 (2026-10-25, NOVA 재현용)

복셀 격자 대신 "블록 하나 = 볼록 다면체(모따기 상자·사다리꼴·임의 볼록 껍질)"로 쌓는다.
블록마다 자유 회전이 되므로 비스듬한 판에 계단이 생기지 않는다(컨셉의 각진 덩어리 표현).
좌표 단위·축은 flag_vox 와 같다: 칸(0.05 Blender), +X = 기체 왼쪽, -Y = 정면, +Z = 위.
파트(관절)·피벗·부모·쉬는 기울기(rot)·자세(pose)도 flag_vox.Model 과 같은 규약.

  P = M.part("Torso", pivot=(0,0,198), parent="Pelvis")
  P.box((-30,30), (-22,18), (208,246), col=1, b=2)                 # 모따기 2칸 상자
  P.box((6,30), (-26,-20), (216,244), col=1, b=1.5, R=rotz(12))     # 블록 자기 중심 둘레 회전
  P.box(..., top=(0.8, 0.9, dx, dy))                                # 윗면 축소·이동(사다리꼴)
  P.hull(points, col, b)                                            # 임의 볼록 껍질(+모따기)
"""
import numpy as np
from scipy.spatial import ConvexHull


def rotx(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def roty(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def _bevel_box(h, b):
    hx, hy, hz = h
    b = max(0.0, min(b, hx * 0.9, hy * 0.9, hz * 0.9))
    if b <= 1e-6:
        return np.array([(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], float)
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts += [(sx * hx, sy * (hy - b), sz * (hz - b)), (sx * (hx - b), sy * hy, sz * (hz - b)),
                        (sx * (hx - b), sy * (hy - b), sz * hz)]
    return np.array(pts, float)


class Block:
    __slots__ = ("pts", "col", "_hull")

    def __init__(self, pts, col):
        self.pts = np.asarray(pts, float)
        self.col = int(col)
        self._hull = None

    def hull(self):
        if self._hull is None:
            H = ConvexHull(self.pts)
            n = H.equations[:, :3]
            self._hull = (H.simplices.copy(), n / np.linalg.norm(n, axis=1, keepdims=True))
        return self._hull


class Part:
    def __init__(self, name, pivot=(0, 0, 0), parent=None):
        self.name = name
        self.pivot = tuple(float(c) for c in pivot)
        self.parent = parent
        self.rot = np.eye(3)
        self.blocks = []

    # ---- 블록 만들기
    def box(self, x, y, z, col=1, b=1.5, R=None, about=None, top=None, front=None):
        """x,y,z = (최소, 최대) 연속 좌표. b = 모따기. R = 회전(블록 중심 또는 about 둘레).
        top=(sx, sy, dx, dy): 윗면(+z)을 x·y 로 sx·sy 배 줄이고 dx·dy 만큼 옮김(사다리꼴).
        front=(sx, sz, dx, dz): 앞면(-y)을 같은 식으로."""
        lo = np.array([min(x), min(y), min(z)], float); hi = np.array([max(x), max(y), max(z)], float)
        c = (lo + hi) / 2; h = (hi - lo) / 2
        P = _bevel_box(h, b)
        if top is not None:
            sx, sy, dx, dy = (list(top) + [0, 0])[:4]
            m = P[:, 2] > 0
            P[m, 0] = P[m, 0] * sx + dx; P[m, 1] = P[m, 1] * sy + dy
        if front is not None:
            sx, sz, dx, dz = (list(front) + [0, 0])[:4]
            m = P[:, 1] < 0
            P[m, 0] = P[m, 0] * sx + dx; P[m, 2] = P[m, 2] * sz + dz
        P = P + c
        if R is not None:
            o = c if about is None else np.asarray(about, float)
            P = (P - o) @ np.asarray(R).T + o
        self.blocks.append(Block(P, col))
        return self.blocks[-1]

    def chunk(self, x, y, z, col=1, b=1.6, n=(1, 1, 2), gap=0.9, out=(0, -1, 0), jit=1.6, tilt=3.0, seed=0,
              alt=None, alt_p=0.0, R=None, about=None, top=None, var=0.18, notch=0.0, step=0.0, ncol=4):
        """상자 하나를 n=(nx,ny,nz) 조각으로 나눠 틈(gap)을 두고, 조각마다 out 방향으로 0~jit 만큼 튀어나오게,
        tilt 도 살짝 비틀어 쌓는다(컨셉의 '덩어리 블록' 질감). alt 색을 alt_p 확률로 섞음.
        notch: 조각 바깥면에 짙은 홈판(ncol)을 붙일 확률, step: 바깥면에 작은 덧블록(계단)을 얹을 확률.
        R/about 는 묶음 전체 회전. 같은 seed 면 같은 결과."""
        rng = np.random.default_rng(seed)
        lo = np.array([min(x), min(y), min(z)], float); hi = np.array([max(x), max(y), max(z)], float)
        cuts = []
        for a in range(3):
            k = n[a]
            w = np.ones(k) + rng.uniform(-var, var, k)
            edges = lo[a] + np.concatenate([[0], np.cumsum(w) / w.sum()]) * (hi[a] - lo[a])
            cuts.append(edges)
        outv = np.asarray(out, float)
        oa = int(np.argmax(np.abs(outv))); osg = 1 if outv[oa] > 0 else -1
        group_c = (lo + hi) / 2 if about is None else np.asarray(about, float)
        made = []
        for i in range(n[0]):
            for j in range(n[1]):
                for k in range(n[2]):
                    a0 = np.array([cuts[0][i], cuts[1][j], cuts[2][k]])
                    a1 = np.array([cuts[0][i + 1], cuts[1][j + 1], cuts[2][k + 1]])
                    g = np.array([gap / 2 if (i > 0) else 0, gap / 2 if (j > 0) else 0, gap / 2 if (k > 0) else 0])
                    g1 = np.array([gap / 2 if (i < n[0] - 1) else 0, gap / 2 if (j < n[1] - 1) else 0, gap / 2 if (k < n[2] - 1) else 0])
                    a0 = a0 + g; a1 = a1 - g1
                    sh = outv * rng.uniform(0, jit)
                    a0 = a0 + sh; a1 = a1 + sh
                    c = col if (alt is None or rng.uniform() > alt_p) else alt
                    Rt = rotx(rng.uniform(-tilt, tilt)) @ roty(rng.uniform(-tilt, tilt)) @ rotz(rng.uniform(-tilt, tilt) * 0.5)
                    pc = (a0 + a1) / 2
                    sz = a1 - a0
                    piece = [self.box((a0[0], a1[0]), (a0[1], a1[1]), (a0[2], a1[2]), col=c, b=min(b, 0.3 * min(sz)), top=top)]
                    # 바깥면 좌표축(u, v)
                    ax2 = [t for t in range(3) if t != oa]
                    face = a1[oa] if osg > 0 else a0[oa]
                    if rng.uniform() < step and min(sz[ax2]) > 5:
                        f0 = np.zeros(3); f1 = np.zeros(3)
                        for t in ax2:
                            L_ = sz[t] * rng.uniform(0.35, 0.65); s0 = a0[t] + rng.uniform(0, sz[t] - L_)
                            f0[t], f1[t] = s0, s0 + L_
                        f0[oa], f1[oa] = (face, face + osg * rng.uniform(1.2, 2.4)) if osg > 0 else (face - rng.uniform(1.2, 2.4), face)
                        piece.append(self.box((f0[0], f1[0]), (f0[1], f1[1]), (f0[2], f1[2]), col=c, b=0.8))
                    if rng.uniform() < notch and min(sz[ax2]) > 4:
                        f0 = np.zeros(3); f1 = np.zeros(3)
                        for t in ax2:
                            L_ = sz[t] * rng.uniform(0.15, 0.35); s0 = a0[t] + rng.uniform(0.15, 0.85) * (sz[t] - L_)
                            f0[t], f1[t] = s0, s0 + L_
                        f0[oa], f1[oa] = (face - 0.4, face + 0.35) if osg > 0 else (face - 0.35, face + 0.4)
                        piece.append(self.box((f0[0], f1[0]), (f0[1], f1[1]), (f0[2], f1[2]), col=ncol, b=0.2))
                    for blk in piece:
                        blk.pts = (blk.pts - pc) @ Rt.T + pc
                        if R is not None:
                            blk.pts = (blk.pts - group_c) @ np.asarray(R).T + group_c
                    made += piece
        return made

    def hull(self, pts, col=1, b=0.0, R=None, about=None):
        P = np.asarray(pts, float)
        if b > 0:
            c = P.mean(0)
            rad = np.linalg.norm(P - c, axis=1).mean()
            s = max(0.3, 1 - b / max(rad, 1e-6))
            P = c + (P - c) * s
            off = np.array([(b, 0, 0), (-b, 0, 0), (0, b, 0), (0, -b, 0), (0, 0, b), (0, 0, -b)], float) * 0.85
            P = (P[:, None, :] + off[None]).reshape(-1, 3)
        if R is not None:
            o = P.mean(0) if about is None else np.asarray(about, float)
            P = (P - o) @ np.asarray(R).T + o
        self.blocks.append(Block(P, col))
        return self.blocks[-1]

    def prism(self, poly, axis, rng, col=1, b=0.0, R=None, about=None):
        """2D 볼록 다각형(축을 뺀 두 좌표, 오름차순 축 순서)을 axis 로 rng 만큼 뽑기."""
        pts = []
        for a in rng:
            for u, w in poly:
                if axis == "x":
                    pts.append((a, u, w))
                elif axis == "y":
                    pts.append((u, a, w))
                else:
                    pts.append((u, w, a))
        return self.hull(pts, col, b, R, about)

    def cyl(self, axis, c, r, rng, col=3, n=10, R=None, about=None):
        t = np.linspace(0, 2 * np.pi, n, endpoint=False) + np.pi / n
        poly = [(c[0] + r * np.cos(a), c[1] + r * np.sin(a)) for a in t]
        return self.prism(poly, axis, rng, col, 0.0, R, about)


class Model:
    def __init__(self):
        self.parts = {}

    def part(self, name, pivot=(0, 0, 0), parent=None):
        p = Part(name, pivot, parent)
        self.parts[name] = p
        return p

    def mirror(self, src, dst, parent=None):
        s = self.parts[src]
        q = Part(dst, (-s.pivot[0], s.pivot[1], s.pivot[2]), parent if parent is not None else _mirror_name(s.parent))
        F = np.diag([-1.0, 1, 1])
        q.rot = F @ s.rot @ F
        for b in s.blocks:
            q.blocks.append(Block(b.pts * np.array([-1, 1, 1]), b.col))
        self.parts[dst] = q
        return q

    def world(self, name, pose=None):
        p = self.parts[name]
        R = p.rot if pose is None or name not in pose else pose[name] @ p.rot
        T = np.eye(4); T[:3, :3] = R
        pv = np.array(p.pivot)
        T[:3, 3] = pv - R @ pv
        if p.parent and p.parent in self.parts:
            return self.world(p.parent, pose) @ T
        return T

    def tris(self, pose=None, skip=()):
        """-> (V (N,3,3) 월드 삼각형, Nn (N,3) 바깥 법선, col (N,), bid (N,) 블록 번호)"""
        Vs, Ns, Cs, Bs = [], [], [], []
        bid = 0
        for name, p in self.parts.items():
            if name in skip:
                continue
            T = self.world(name, pose)
            R, t = T[:3, :3], T[:3, 3]
            for b in p.blocks:
                bid += 1
                simp, n = b.hull()
                P = b.pts @ R.T + t
                Vs.append(P[simp]); Ns.append(n @ R.T)
                Cs.append(np.full(len(simp), b.col)); Bs.append(np.full(len(simp), bid))
        return np.concatenate(Vs), np.concatenate(Ns), np.concatenate(Cs), np.concatenate(Bs)

    def count(self):
        nb = sum(len(p.blocks) for p in self.parts.values())
        nt = sum(len(b.hull()[0]) for p in self.parts.values() for b in p.blocks)
        return nb, nt


def _mirror_name(n):
    if n is None:
        return None
    if n.endswith("L"):
        return n[:-1] + "R"
    if n.endswith("R"):
        return n[:-1] + "L"
    return n
