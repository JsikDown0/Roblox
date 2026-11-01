"""check_model.py — 빌더 검사: 파트별 삼각형 수(그리디 메싱) + 떠 있는 복셀 섬.
    python3 check_model.py flagship_build      # 모듈 이름(.py 빼고). build_all() 을 부른다.
기준: 파트당 삼각형 10,000 미만(로블록스 MeshPart 한도 여유), 파트마다 연결 덩어리 1개."""
import importlib
import sys

import numpy as np
from scipy import ndimage


def greedy_quads(a):
    P = np.pad(a, 1)
    n = 0
    for ax in range(3):
        for d in (1, -1):
            nb = np.roll(P, -d, axis=ax)
            face = np.moveaxis(np.where((P > 0) & (nb == 0), P, 0), ax, 0)
            for s in range(face.shape[0]):
                m = face[s]
                if not m.any():
                    continue
                done = np.zeros(m.shape, bool)
                for iu, iw in np.argwhere(m > 0):
                    if done[iu, iw]:
                        continue
                    c = m[iu, iw]
                    ww = 1
                    while iw + ww < m.shape[1] and m[iu, iw + ww] == c and not done[iu, iw + ww]:
                        ww += 1
                    hu = 1
                    while iu + hu < m.shape[0] and np.all(m[iu + hu, iw:iw + ww] == c) and not done[iu + hu, iw:iw + ww].any():
                        hu += 1
                    done[iu:iu + hu, iw:iw + ww] = True
                    n += 1
    return n


def check(M):
    tot, bad = 0, []
    for name, p in M.parts.items():
        q = greedy_quads(p.a)
        tot += 2 * q
        lab, k = ndimage.label(p.a > 0)
        flag = ""
        if 2 * q >= 10000:
            flag += "  ⚠삼각형"; bad.append(name)
        if k > 1:
            sizes = np.bincount(lab.ravel())[1:]
            small = [(int(s), (np.argwhere(lab == i + 1).mean(0) + p.lo).round().astype(int).tolist())
                     for i, s in enumerate(sizes) if s < sizes.max()]
            flag += "  ⚠섬 %d개 %s" % (k - 1, small[:4]); bad.append(name)
        print("%-12s cells %7d  tris %6d%s" % (name, p.count(), 2 * q, flag))
    lo, hi = M.bounds()
    print("total tris %d · 경계 칸 lo %s hi %s · 높이 %d칸(회전 전 경계 — 날개 등 기울인 파트는 실제보다 큼)" % (tot, lo.tolist(), hi.tolist(), hi[2] - lo[2]))
    print("OK" if not bad else "고칠 것: %s" % sorted(set(bad)))


if __name__ == "__main__":
    mod = importlib.import_module(sys.argv[1] if len(sys.argv) > 1 else "flagship_build")
    check(mod.build_all())
