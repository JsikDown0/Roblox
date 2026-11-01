"""관절 경계 다시 자르기: 경계 주변 띠(링 R개)에서만 두 파트 사이 최소 절단.
절단 비용 = 변 길이 × (매끈한 면일수록 비쌈; 꺾인 모서리·색 경계·검정 프레임은 쌈) → 판 이음매·관절 프레임을 따라 자르게 된다."""
import numpy as np, maxflow, sys, json
NAMES = ["Pelvis", "Torso", "Head", "ShoulderPadL", "ShoulderPadR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR", "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR", "FootL", "FootR"]
ix = {n: i for i, n in enumerate(NAMES)}
M = np.load('/home/claude/sniper3/fix/mesh.npz'); a, b, sd, L, area, C = M['a'], M['b'], M['sd'], M['L'], M['area'], M['C']
code = np.load('/home/claude/sniper3/work/codeA5.npy').astype(np.int64); p = code // 3; z = code % 3
n = len(p)
RINGS = int(sys.argv[1]) if len(sys.argv) > 1 else 10
TH = 25.0
w = L * np.exp(-(np.abs(sd) / TH) ** 2)
w = np.where(z[a] != z[b], w * 0.25, w)                    # 색 경계 = 판 가장자리일 가능성 높음
w = np.where((z[a] == 1) & (z[b] == 1), w * 0.5, w)        # 검정 관절 프레임 속은 잘라도 안 보임
nbr = [[] for _ in range(0)]
def rings_from(mask_seed, allowed):
    d = np.full(n, 10 ** 6); d[mask_seed] = 0; front = mask_seed.copy()
    for r in range(1, RINGS + 1):
        nxt = np.zeros(n, bool)
        m1 = front[a] & allowed[b] & (d[b] > r); m2 = front[b] & allowed[a] & (d[a] > r)
        nxt[b[m1]] = True; nxt[a[m2]] = True
        d[nxt] = r; front = nxt
    return d
PAIRS = [("Pelvis", "Torso"), ("UpperArmL", "LowerArmL"), ("UpperArmR", "LowerArmR"), ("ShoulderPadL", "UpperArmL"), ("ShoulderPadR", "UpperArmR"),
         ("Torso", "UpperArmL"), ("Torso", "UpperArmR"), ("Torso", "ShoulderPadL"), ("Torso", "ShoulderPadR"), ("Torso", "LowerArmL"),
         ("Pelvis", "UpperLegL"), ("UpperLegL", "LowerLegL"), ("LowerLegL", "FootL"), ("Pelvis", "UpperLegR")]
newp = p.copy(); rep = {}
for P, Q in PAIRS:
    i, j = ix[P], ix[Q]
    allowed = (newp == i) | (newp == j)
    bnd = np.zeros(n, bool)
    m = allowed[a] & allowed[b] & (newp[a] != newp[b]); bnd[a[m]] = True; bnd[b[m]] = True
    if not bnd.any(): continue
    d = rings_from(bnd, allowed)
    band = allowed & (d <= RINGS)
    idx = np.where(band)[0]; loc = np.full(n, -1); loc[idx] = np.arange(len(idx))
    g = maxflow.Graph[float](); g.add_nodes(len(idx))
    big = 1e3
    # 띠 바깥 이웃과 맞닿은 면은 그 이웃 파트에 묶음
    src = np.zeros(len(idx)); snk = np.zeros(len(idx))
    for (u, v) in ((a, b), (b, a)):
        mm = band[u] & allowed[v] & ~band[v]
        np.add.at(src, loc[u[mm & (newp[v] == i)]], big); np.add.at(snk, loc[u[mm & (newp[v] == j)]], big)
    # 약한 현재 유지 경향(띠 안에서 너무 멀리 튀지 않게)
    keep = 2e-4 * area[idx] / area.mean()
    src += np.where(newp[idx] == i, keep, 0); snk += np.where(newp[idx] == j, keep, 0)
    g.add_grid_tedges(np.arange(len(idx)), src, snk)
    mm = band[a] & band[b]
    g.add_edges(loc[a[mm]], loc[b[mm]], w[mm], w[mm])
    g.maxflow()
    seg = g.get_grid_segments(np.arange(len(idx)))         # True = 싱크 쪽(Q)
    lab = np.where(seg, j, i)
    before = (newp[idx] != lab).sum()
    newp[idx] = lab
    # 효과 측정
    cutm = allowed[a] & allowed[b] & (newp[a] != newp[b])
    tear = (np.abs(sd) < 15) & (z[a] == 0) & (z[b] == 0)
    rep[f'{P}-{Q}'] = dict(moved=int(before), cut_cm=round(float(L[cutm].sum() * 100), 1), white_tear_cm=round(float(L[cutm & tear].sum() * 100), 1))
for k, v in rep.items(): print(k, v)
np.save('/home/claude/sniper3/recut/newp.npy', newp.astype(np.uint8))
