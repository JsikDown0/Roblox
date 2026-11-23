"""무릎 D안: 평면 ±BAND 띠 안에서만 최소 절단 → 기존 주름(무릎 위 턱 아랫단)·색 경계·검정 프레임을 따라 자름"""
import numpy as np, maxflow, sys
M = np.load('/home/claude/sniper3/fix/mesh.npz'); Vw, Fw, a, b, sd, L, area = M['Vw'], M['Fw'], M['a'], M['b'], M['sd'], M['L'], M['area']
code = np.load('/home/claude/sniper3/work/codeA5.npy').astype(np.int64); p = code // 3; z = code % 3
UL, LL = 9, 11; n = len(p); leg = (p == UL) | (p == LL)
pl = np.load('/home/claude/sniper3/knee/plane.npy'); PCO, PNO = pl[:3], pl[3:]
C = Vw[Fw].mean(1); d = (C - PCO) @ PNO
BAND = float(sys.argv[1]); LAM = float(sys.argv[2]); SHIFT = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
d = d - SHIFT
w = L * np.exp(-(np.abs(sd) / 25.0) ** 2)
w = np.where(z[a] != z[b], w * 0.25, w); w = np.where((z[a] == 1) & (z[b] == 1), w * 0.5, w)
idx = np.nonzero(leg)[0]; loc = np.full(n, -1); loc[idx] = np.arange(len(idx))
g = maxflow.Graph[float](); g.add_nodes(len(idx)); big = 1e3
hu = d[idx] < -BAND; hl = d[idx] > BAND
g.add_grid_tedges(np.arange(len(idx)), np.where(hu, big, 0.0) + LAM * area[idx] * np.maximum(0, -d[idx]), np.where(hl, big, 0.0) + LAM * area[idx] * np.maximum(0, d[idx]))
mm = leg[a] & leg[b]; g.add_edges(loc[a[mm]], loc[b[mm]], w[mm], w[mm]); g.maxflow()
newp = p.copy(); newp[idx] = np.where(g.get_grid_segments(np.arange(len(idx))), LL, UL)
cutm = leg[a] & leg[b] & (newp[a] != newp[b])
tear = (np.abs(sd) < 15) & (z[a] == 0) & (z[b] == 0)
print(f'BAND {BAND} LAM {LAM} SHIFT {SHIFT}: cut cm', round(float(L[cutm].sum() * 100), 1), 'white smooth cm', round(float(L[cutm & tear].sum() * 100), 1), 'white-white cm', round(float(L[cutm & (z[a] == 0) & (z[b] == 0)].sum() * 100), 1))
np.save(sys.argv[4] if len(sys.argv) > 4 else 'newp_D.npy', newp.astype(np.uint8))
