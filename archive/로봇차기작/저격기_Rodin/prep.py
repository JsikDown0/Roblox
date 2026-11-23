"""base_3 메시 준비: 용접·인접·이면각·면적을 한 번 계산해 저장"""
import numpy as np, sys
sys.path.insert(0, '/home/claude/sniper2/rebuild')
from load import load, weld
from seg import adjacency, signed_dihedral
m = load('/home/claude/sniper3/in/base_3.glb')[0]
V, F = m['V'], m['F']
Vw, Fw = weld(V, F, 1e-5)
a, b, ev = adjacency(Fw)
sd = signed_dihedral(Vw, Fw, a, b)
L = np.linalg.norm(Vw[ev[:, 0]] - Vw[ev[:, 1]], axis=1)
area = 0.5 * np.linalg.norm(np.cross(Vw[Fw[:, 1]] - Vw[Fw[:, 0]], Vw[Fw[:, 2]] - Vw[Fw[:, 0]]), axis=1)
C = Vw[Fw].mean(1)
np.savez('/home/claude/sniper3/fix/mesh.npz', Vw=Vw, Fw=Fw, a=a, b=b, sd=sd, L=L, area=area, C=C)
print('faces', len(Fw), 'adj', len(a), 'mean edge mm %.2f' % (L.mean() * 1e3), 'median face mm2 %.2f' % (np.median(area) * 1e6))
for th in (12, 15, 20, 25, 30):
    print(th, 'edges over', (np.abs(sd) > th).mean().round(4))
