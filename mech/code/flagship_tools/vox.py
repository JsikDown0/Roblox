"""
vox.py — 블록 모델(bm.Model)을 복셀 격자로 굽는다.

  G = voxelize(M, vs=1.5)      # vs = 복셀 한 칸 크기(모델 단위)
  G.col  (nx,ny,nz) uint8   0 = 빈칸, 그 외 팔레트 번호
  G.bid  (nx,ny,nz) int32   블록 번호(이음선용)
  G.org  격자 (0,0,0) 모서리의 월드 좌표,  G.vs

블록 순서대로 적용한다: add = 채움(덮어씀), cut = 비움, paint = 이미 있는 칸만 색 바꿈.
칸 중심이 블록 안(+tol 만큼 부풀림)이면 포함. 얇은 판(눈·띠)이 사라지지 않게 기본 tol = 0.25·vs.
"""
import numpy as np
from scipy.spatial import ConvexHull


class Grid:
    def __init__(self, col, bid, org, vs):
        self.col, self.bid, self.org, self.vs = col, bid, np.asarray(org, float), float(vs)

    def count(self):
        return int((self.col > 0).sum())

    def surface(self):
        c = self.col > 0
        p = np.pad(c, 1)
        inner = p[2:, 1:-1, 1:-1] & p[:-2, 1:-1, 1:-1] & p[1:-1, 2:, 1:-1] & p[1:-1, :-2, 1:-1] & p[1:-1, 1:-1, 2:] & p[1:-1, 1:-1, :-2]
        return int((c & ~inner).sum())


def _world_blocks(M, pose=None, skip=()):
    out = []
    for name, p in M.parts.items():
        if name in skip:
            continue
        T = M.world(name, pose)
        R, t = T[:3, :3], T[:3, 3]
        for b in p.blocks:
            out.append((b.pts @ R.T + t, b.col, getattr(b, "mode", "add"), getattr(b, "tol", None)))
    return out


def voxelize(M, vs=1.5, pose=None, skip=(), tol=0.25, pad=3):
    W = _world_blocks(M, pose, skip)
    adds = np.concatenate([w[0] for w in W if w[2] == "add"])
    lo = np.floor(adds.min(0) / vs) * vs - pad * vs
    hi = np.ceil(adds.max(0) / vs) * vs + pad * vs
    n = np.round((hi - lo) / vs).astype(int)
    col = np.zeros(n, np.uint8)
    bid = np.zeros(n, np.int32)
    for k, (P, c, mode, t_) in enumerate(W, start=1):
        try:
            H = ConvexHull(P)
        except Exception:
            continue
        eq = H.equations
        tt = (tol if t_ is None else t_) * vs
        a = np.clip(np.floor((P.min(0) - tt - lo) / vs - 0.5).astype(int), 0, n - 1)
        b = np.clip(np.ceil((P.max(0) + tt - lo) / vs - 0.5).astype(int) + 1, 0, n)
        if (b <= a).any():
            continue
        ii, jj, kk = [np.arange(a[d], b[d]) for d in range(3)]
        cx = lo[0] + (ii + 0.5) * vs; cy = lo[1] + (jj + 0.5) * vs; cz = lo[2] + (kk + 0.5) * vs
        X, Y, Z = np.meshgrid(cx, cy, cz, indexing="ij")
        C = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
        inside = np.all(C @ eq[:, :3].T + eq[:, 3] <= tt, axis=1).reshape(X.shape)
        sl = (slice(a[0], b[0]), slice(a[1], b[1]), slice(a[2], b[2]))
        sc, sb = col[sl], bid[sl]
        if mode == "add":
            sc[inside] = c; sb[inside] = k
        elif mode == "cut":
            sc[inside] = 0; sb[inside] = 0
        else:  # paint
            m = inside & (sc > 0)
            sc[m] = c; sb[m] = k
    return Grid(col, bid, lo, vs)


def chip(G, cols=(1,), p=0.2, passes=1, seed=0, protect_z=None):
    """모서리 칸(노출면 2개 이상)을 확률 p 로 깎아 '깨진 모서리' 질감. 흰 판(cols)만."""
    rng = np.random.default_rng(seed)
    for _ in range(passes):
        c = G.col > 0
        pd = np.pad(c, 1)
        expo = ((~pd[2:, 1:-1, 1:-1]).astype(np.int8) + (~pd[:-2, 1:-1, 1:-1]) + (~pd[1:-1, 2:, 1:-1]) +
                (~pd[1:-1, :-2, 1:-1]) + (~pd[1:-1, 1:-1, 2:]) + (~pd[1:-1, 1:-1, :-2]))
        m = np.isin(G.col, cols) & (expo >= 2) & (rng.random(G.col.shape) < p)
        # 바닥이 비지 않게: 아래가 비어 있는 칸만 깎지 않도록(떠 있는 조각 방지) — 노출 3면 이하만
        m &= expo <= 3
        G.col[m] = 0; G.bid[m] = 0
    return G
