"""
flag_vox.py — 대표 기체(플래그십)용 고해상도 복셀 엔진 (2026-10-25)

mech_voxel.py 와 같은 축 규약, 칸 크기만 절반:
  - 칸 = VOXF = 0.05 Blender 단위 (프로토 0.1 의 절반).
  - +X = 기체 왼쪽, -Y = 정면, +Z = 위, 바닥 z=0.
  - 칸 i 의 중심 = 정수 i (칸은 [i-0.5, i+0.5]). 좌우 대칭은 i -> -i (칸 0 중심이 대칭면).
  - 파트마다 자기 경계 상자(lo..hi-1)를 가진다 → 전역 격자가 필요 없다.

모양은 "마스크 식"으로 만든다: G = p.g() 가 (X, Y, Z) 열린 격자(브로드캐스트)를 주고,
box/poly/half/cyl 이 bool 마스크를 돌려준다. & | ~ 로 조합해 add/cut/paint.
  poly(G, "y", [(x,z),...])  = 정면 실루엣을 Y 로 뽑기 (sym=True 면 |X| 로 평가 → 좌우 대칭 자동)
  poly(G, "x", [(y,z),...])  = 옆 실루엣을 X 로 뽑기
  poly(G, "z", [(x,y),...])  = 위에서 본 실루엣을 Z 로 뽑기
세 실루엣의 교집합 = 3면도 모델링.
"""
import json

import numpy as np
from matplotlib.path import Path

VOXF = 0.05


# ------------------------------------------------------------------ 마스크 원시형
def box(G, x=None, y=None, z=None):
    X, Y, Z = G
    m = np.ones(np.broadcast_shapes(X.shape, Y.shape, Z.shape), bool)
    for A, r in ((X, x), (Y, y), (Z, z)):
        if r is not None:
            a, b = min(r), max(r)
            m = m & (A >= a) & (A <= b)
    return m


def _pip(u, w, pts):
    """2D 격자 (u 열, w 행) 의 칸 중심이 다각형 안인가. u: (nu,) w: (nw,) -> (nu, nw)"""
    U, W = np.meshgrid(u, w, indexing="ij")
    path = Path(np.asarray(pts, float))
    inside = path.contains_points(np.stack([U.ravel(), W.ravel()], 1), radius=1e-9)
    return inside.reshape(U.shape)


def poly(G, axis, pts, rng=None, sym=False):
    """축 axis 로 뽑은(extrude) 다각형 기둥. pts 는 그 축을 뺀 두 좌표 (오름차순 축 순서: x→(y,z), y→(x,z), z→(x,y)).
    sym=True: X 를 |X| 로 평가(정면·위 실루엣에서 오른쪽 반만 주면 좌우 대칭)."""
    X, Y, Z = G
    xs, ys, zs = X.ravel(), Y.ravel(), Z.ravel()
    if sym:
        xs = np.abs(xs)
    if axis == "x":
        m2 = _pip(ys, zs, pts)[None, :, :]
        A, ra = X, rng
    elif axis == "y":
        m2 = _pip(xs, zs, pts)
        m2 = m2[:, None, :] if not sym else m2[:, None, :]
        A, ra = Y, rng
    else:
        m2 = _pip(xs, ys, pts)[:, :, None]
        A, ra = Z, rng
    m = np.broadcast_to(m2, np.broadcast_shapes(X.shape, Y.shape, Z.shape)).copy()
    if ra is not None:
        a, b = min(ra), max(ra)
        m &= (A >= a) & (A <= b)
    return m


def half(G, n, p0, sym=False):
    """반공간 n·(P - p0) <= 0. sym=True 면 X 를 |X| 로."""
    X, Y, Z = G
    if sym:
        X = np.abs(X)
    return (n[0] * (X - p0[0]) + n[1] * (Y - p0[1]) + n[2] * (Z - p0[2])) <= 0


def cyl(G, axis, c, r, rng=None, sym=False):
    """축 axis 원기둥. c = 나머지 두 좌표의 중심(오름차순 축 순서)."""
    X, Y, Z = G
    if sym:
        X = np.abs(X)
    if axis == "x":
        d2 = (Y - c[0]) ** 2 + (Z - c[1]) ** 2; A = X
    elif axis == "y":
        d2 = (X - c[0]) ** 2 + (Z - c[1]) ** 2; A = Y
    else:
        d2 = (X - c[0]) ** 2 + (Y - c[1]) ** 2; A = Z
    m = d2 <= r * r + 0.25
    if rng is not None:
        a, b = min(rng), max(rng)
        m = m & (A >= a) & (A <= b)
    return m


def ell(G, c, r, sym=False):
    X, Y, Z = G
    if sym:
        X = np.abs(X)
    return ((X - c[0]) / r[0]) ** 2 + ((Y - c[1]) / r[1]) ** 2 + ((Z - c[2]) / r[2]) ** 2 <= 1.0


def _edges(key):
    """"+x-y" -> [(("x",1),("y",-1))], "xy" -> 네 모서리, "+xy" -> (+x,±y) 두 모서리"""
    toks, i = [], 0
    while i < len(key):
        sg = None
        if key[i] in "+-":
            sg = 1 if key[i] == "+" else -1
            i += 1
        toks.append((key[i], sg)); i += 1
    (a, sa), (b, sb) = toks
    out = []
    for s1 in ([sa] if sa else [1, -1]):
        for s2 in ([sb] if sb else [1, -1]):
            out.append(((a, s1), (b, s2)))
    return out


def cbox(G, x, y, z, ch=None):
    """모서리 깎은 상자. ch = {"xy": 6, "+z-y": 8, "+x-z": (4, 10)} — 값이 (la, lb) 면 두 축으로 다른 길이(비스듬히).
    키는 두 축(부호 생략 = 양쪽). 칸 중심 기준, 범위 양끝 포함."""
    m = box(G, x, y, z)
    X, Y, Z = G
    A = {"x": (X, x), "y": (Y, y), "z": (Z, z)}
    for key, s in (ch or {}).items():
        la, lb = (s, s) if np.isscalar(s) else s
        for (a, sa), (b, sb) in _edges(key):
            Aa, ra = A[a]; Bb, rb = A[b]
            ae = max(ra) if sa > 0 else min(ra)
            be = max(rb) if sb > 0 else min(rb)
            dA = (ae - Aa) * sa
            dB = (be - Bb) * sb
            m = m & (dA * lb + dB * la >= la * lb - 1e-6)
    return m


def shift(G, dx=0, dy=0, dz=0):
    X, Y, Z = G
    return (X - dx, Y - dy, Z - dz)


def slab(G, o, e1, e2, pts, h=(-1, 1), sym=False):
    """비스듬한 판: 원점 o, 평면 축 e1·e2(정규화함), 그 평면의 다각형 pts(s,t), 두께 방향 e3 = e1×e2 로 h 범위."""
    X, Y, Z = G
    if sym:
        X = np.abs(X)
    e1 = np.asarray(e1, float); e1 /= np.linalg.norm(e1)
    e2 = np.asarray(e2, float); e2 = e2 - e1 * np.dot(e1, e2); e2 /= np.linalg.norm(e2)
    e3 = np.cross(e1, e2)
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    dx, dy, dz = X - o[0], Y - o[1], Z - o[2]
    s = np.broadcast_to(e1[0] * dx + e1[1] * dy + e1[2] * dz, shp)
    t = np.broadcast_to(e2[0] * dx + e2[1] * dy + e2[2] * dz, shp)
    n = np.broadcast_to(e3[0] * dx + e3[1] * dy + e3[2] * dz, shp)
    m = (n >= h[0] - 0.5) & (n <= h[1] + 0.5)
    pts = np.asarray(pts, float)
    lo, hi = pts.min(0), pts.max(0)
    m &= (s >= lo[0] - 1) & (s <= hi[0] + 1) & (t >= lo[1] - 1) & (t <= hi[1] + 1)
    idx = np.nonzero(m.ravel())[0]
    out = np.zeros(shp, bool)
    if len(idx):
        inside = Path(pts).contains_points(np.stack([s.ravel()[idx], t.ravel()[idx]], 1))
        out.ravel()[idx[inside]] = True
    return out


def local(G, o, e1, e2):
    """(s, t, n) 지역 좌표 배열 — 비스듬한 판에 선·칠을 넣을 때."""
    X, Y, Z = G
    e1 = np.asarray(e1, float); e1 /= np.linalg.norm(e1)
    e2 = np.asarray(e2, float); e2 = e2 - e1 * np.dot(e1, e2); e2 /= np.linalg.norm(e2)
    e3 = np.cross(e1, e2)
    dx, dy, dz = X - o[0], Y - o[1], Z - o[2]
    f = lambda e: e[0] * dx + e[1] * dy + e[2] * dz
    return f(e1), f(e2), f(e3)


def band(G, n, p0, w=0.5, sym=False):
    """평면 n·(P-p0)=0 근처 두께 2w 띠 (패널 선용). n 은 정규화 안 해도 됨(칸 단위로 맞춤)."""
    X, Y, Z = G
    if sym:
        X = np.abs(X)
    nn = np.sqrt(sum(c * c for c in n))
    d = (n[0] * (X - p0[0]) + n[1] * (Y - p0[1]) + n[2] * (Z - p0[2])) / nn
    return np.abs(d) <= w


# ------------------------------------------------------------------ 파트
class Part:
    def __init__(self, name, lo, hi, pivot=(0, 0, 0), parent=None):
        self.name = name
        self.lo = np.array(lo, int)
        self.hi = np.array(hi, int)
        self.a = np.zeros(tuple(self.hi - self.lo), np.uint8)
        self.pivot = tuple(float(c) for c in pivot)   # 칸 단위
        self.parent = parent
        self.rot = np.eye(3)                           # 피벗 둘레 기본 회전(쉬는 자세의 기울기)

    def g(self):
        return (np.arange(self.lo[0], self.hi[0])[:, None, None],
                np.arange(self.lo[1], self.hi[1])[None, :, None],
                np.arange(self.lo[2], self.hi[2])[None, None, :])

    def add(self, m, c):
        self.a[np.broadcast_to(m, self.a.shape)] = c

    def cut(self, m):
        self.a[np.broadcast_to(m, self.a.shape)] = 0

    def paint(self, m, c):
        m = np.broadcast_to(m, self.a.shape) & (self.a > 0)
        self.a[m] = c

    def surface(self):
        o = self.a > 0
        P = np.pad(o, 1)
        inner = P[2:, 1:-1, 1:-1] & P[:-2, 1:-1, 1:-1] & P[1:-1, 2:, 1:-1] & P[1:-1, :-2, 1:-1] & P[1:-1, 1:-1, 2:] & P[1:-1, 1:-1, :-2]
        return o & ~inner

    def paint_s(self, m, c, depth=1):
        """겉면(깊이 depth 칸)만 칠한다."""
        s = self.surface()
        if depth > 1:
            o = self.a > 0
            for _ in range(depth - 1):
                P = np.pad(s, 1)
                grow = P[2:, 1:-1, 1:-1] | P[:-2, 1:-1, 1:-1] | P[1:-1, 2:, 1:-1] | P[1:-1, :-2, 1:-1] | P[1:-1, 1:-1, 2:] | P[1:-1, 1:-1, :-2]
                s = (s | grow) & o
        m = np.broadcast_to(m, self.a.shape) & s
        self.a[m] = c

    def groove(self, m, c=4):
        """겉면 띠를 한 칸 파고, 판 자리 바로 밑(새로 드러난 칸)을 c 로 칠한다(패널 선)."""
        m = np.broadcast_to(m, self.a.shape)
        cutm = m & self.surface()
        self.a[cutm] = 0
        self.a[_dilate(cutm) & (self.a > 0) & m] = c

    def emboss(self, m, c, h=1):
        """겉면 바깥 빈칸 중 m 에 든 칸을 h 겹 덧붙인다(돋을 판)."""
        for _ in range(h):
            o = self.a > 0
            add = _dilate(o) & ~o & np.broadcast_to(m, self.a.shape)
            self.a[add] = c

    def count(self):
        return int((self.a > 0).sum())

    def trim(self):
        """빈 가장자리를 잘라 경계 상자를 줄인다."""
        ijk = np.argwhere(self.a > 0)
        if len(ijk) == 0:
            return
        a0, a1 = ijk.min(0), ijk.max(0) + 1
        self.a = self.a[a0[0]:a1[0], a0[1]:a1[1], a0[2]:a1[2]].copy()
        self.lo = self.lo + a0
        self.hi = self.lo + (a1 - a0)

    def mirrored(self, name, parent=None):
        q = Part(name, (-(self.hi[0] - 1), self.lo[1], self.lo[2]), (-self.lo[0] + 1, self.hi[1], self.hi[2]),
                 (-self.pivot[0], self.pivot[1], self.pivot[2]), parent)
        q.a = self.a[::-1].copy()
        F = np.diag([-1.0, 1, 1])
        q.rot = F @ self.rot @ F
        return q


class Model:
    def __init__(self):
        self.parts = {}
        self.extra = {}

    def part(self, name, lo, hi, pivot=(0, 0, 0), parent=None):
        p = Part(name, lo, hi, pivot, parent)
        self.parts[name] = p
        return p

    def mirror(self, src, dst, parent=None):
        p = self.parts[src]
        q = p.mirrored(dst, parent if parent is not None else _mirror_name(p.parent))
        self.parts[dst] = q
        return q

    def world(self, name, pose=None):
        """4x4 (칸 단위): 파트 격자 좌표 -> 월드. 부모 사슬 + 각 파트 rot(쉬는 기울기) + pose[name](추가 회전)."""
        p = self.parts[name]
        R = p.rot if pose is None or name not in pose else pose[name] @ p.rot
        T = np.eye(4); T[:3, :3] = R
        pv = np.array(p.pivot)
        T[:3, 3] = pv - R @ pv
        if p.parent and p.parent in self.parts:
            return self.world(p.parent, pose) @ T
        return T

    def blocks(self, skip=(), pose=None):
        out = []
        for n, p in self.parts.items():
            if n in skip:
                continue
            T = self.world(n, pose)
            out.append((p.lo, p.a, None if np.allclose(T, np.eye(4)) else T))
        return out

    def stats(self):
        return {n: p.count() for n, p in self.parts.items()}

    def bounds(self):
        lo = np.min([p.lo for p in self.parts.values()], 0)
        hi = np.max([p.hi for p in self.parts.values()], 0)
        return lo, hi

    def save(self, path):
        d = {"format": "flag_vox/1", "vox": VOXF, "extra": self.extra, "parts": {}}
        for n, p in self.parts.items():
            p.trim()
            ijk = np.argwhere(p.a > 0)
            runs = []
            if len(ijk):
                order = np.lexsort((ijk[:, 0], ijk[:, 2], ijk[:, 1]))
                ijk = ijk[order]
                cur = None
                for i, j, k in ijk:
                    c = int(p.a[i, j, k]); x = int(i + p.lo[0]); y = int(j + p.lo[1]); z = int(k + p.lo[2])
                    if cur and cur[0] == y and cur[1] == z and cur[2] + cur[3] == x and cur[4] == c:
                        cur[3] += 1
                    else:
                        if cur:
                            runs.append(cur)
                        cur = [y, z, x, 1, c]
                if cur:
                    runs.append(cur)
            d["parts"][n] = {"lo": p.lo.tolist(), "hi": p.hi.tolist(), "pivot": list(p.pivot), "parent": p.parent,
                             "rot": np.round(p.rot, 6).tolist(), "runs": runs}
        with open(path, "w", encoding="utf-8") as f:
            json.dump(d, f, separators=(",", ":"))

    @classmethod
    def load(cls, path):
        d = json.load(open(path, encoding="utf-8"))
        m = cls()
        m.extra = d.get("extra", {})
        for n, q in d["parts"].items():
            p = m.part(n, q["lo"], q["hi"], q["pivot"], q["parent"])
            p.rot = np.array(q.get("rot", np.eye(3).tolist()), float)
            for y, z, x0, k, c in q["runs"]:
                p.a[x0 - p.lo[0]:x0 - p.lo[0] + k, y - p.lo[1], z - p.lo[2]] = c
        return m


def _dilate(m):
    P = np.pad(m, 1)
    return (P[2:, 1:-1, 1:-1] | P[:-2, 1:-1, 1:-1] | P[1:-1, 2:, 1:-1] | P[1:-1, :-2, 1:-1]
            | P[1:-1, 1:-1, 2:] | P[1:-1, 1:-1, :-2] | m)


def _mirror_name(n):
    if n is None:
        return None
    if n.endswith("L"):
        return n[:-1] + "R"
    if n.endswith("R"):
        return n[:-1] + "L"
    return n


def rotx(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def roty(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
