"""aello_glow_data.py — AELLO 발광 칸(색 6) 덩어리 → 템플릿 좌표 목록 (10-26 23:40, 유저 "aero tone3 r1 오른쪽 줄처럼 발광을 더")
덩어리 = 26-이웃 연결 성분. 중심·면 방향(빈 이웃이 가장 많은 축)·크기를 템플릿 좌표(칸 × 0.1, 축 (−x, z, y))로.
로블록스 파트 = MERGE·RENAME 뒤 이름. 무기(Rifle·RifleStowed·Grenade)는 뺌 — 무기는 들고/넣고에 따라 자리가 바뀜.
  python3 rig/aello_glow_data.py > out.lua   (Luau 표 한 줄씩)"""
import sys
import numpy as np
from scipy import ndimage
sys.path.insert(0, "/home/claude/flag")
import aero_export as E

SKIP = {"RifleR", "RifleStowed", "Grenade"}
Mm = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)


def clusters():
    M = E.build()
    P = E.REST_POSE
    out = []
    for n, p in M.parts.items():
        if n in SKIP:
            continue
        m = p.a == 6
        if not m.any():
            continue
        solid = p.a > 0
        lab, k = ndimage.label(m, structure=np.ones((3, 3, 3)))
        W = M.world(n, P)
        for i in range(1, k + 1):
            ijk = np.argwhere(lab == i)
            c = ijk.mean(0) + p.lo + 0.5
            best, bc = None, -1
            for ax in range(3):
                for s in (-1, 1):
                    q = ijk.copy(); q[:, ax] += s
                    ok = (q >= 0).all(1) & (q < np.array(solid.shape)).all(1)
                    empty = (~ok).sum() + (~solid[tuple(q[ok].T)]).sum()
                    if empty > bc:
                        best, bc = (ax, s), empty
            nl = np.zeros(3); nl[best[0]] = best[1]
            pos = Mm @ (W[:3, :3] @ c + W[:3, 3]) * 0.1
            nrm = Mm @ (W[:3, :3] @ nl)
            ext = (ijk.max(0) - ijk.min(0) + 1)
            span = float(np.sort(ext)[-2:].mean()) * 0.1          # 면 크기(긴 두 변 평균, 스터드)
            n2 = E.MERGE.get(n, n); n2 = E.RENAME.get(n2, n2)
            out.append(dict(src=n, part=n2, n=int(len(ijk)), pos=pos.round(3).tolist(), nrm=nrm.round(3).tolist(), span=round(span, 2)))
    return out


if __name__ == "__main__":
    for c in clusters():
        print('{src="%s", part="%s", n=%d, pos=Vector3.new(%.3f, %.3f, %.3f), nrm=Vector3.new(%.3f, %.3f, %.3f), span=%.2f},'
              % (c["src"], c["part"], c["n"], *c["pos"], *c["nrm"], c["span"]))


def halos(clusters_=None):
    """덩어리 → 후광 점. 띠(채움률 < 0.5)는 20칸마다 1개, 꽉 찬 판은 긴 변/짧은 변 비로 나눔 — k-평균(시드 고정)."""
    M = E.build(); P = E.REST_POSE
    out = []
    for n, p in M.parts.items():
        if n in SKIP:
            continue
        m = p.a == 6
        if not m.any():
            continue
        lab, k = ndimage.label(m, structure=np.ones((3, 3, 3)))
        W = M.world(n, P)
        for i in range(1, k + 1):
            ijk = np.argwhere(lab == i)
            ext = np.sort(ijk.max(0) - ijk.min(0) + 1)[::-1]
            fill = len(ijk) / float(np.prod(ext))
            ns = max(1, round(len(ijk) / 20)) if fill < 0.5 else max(1, round(ext[0] / max(ext[1] * 2, 6)))
            pts = ijk.astype(float)
            rng = np.random.default_rng(0)
            C = pts[rng.choice(len(pts), ns, replace=False)]
            for _ in range(30):
                d = ((pts[:, None, :] - C[None]) ** 2).sum(2); a = d.argmin(1)
                C = np.array([pts[a == j].mean(0) if (a == j).any() else C[j] for j in range(ns)])
            for j in range(ns):
                q = ijk[a == j]
                e2 = np.sort(q.max(0) - q.min(0) + 1)[::-1]
                span = float(e2[:2].mean()) * 0.1
                c = q.mean(0) + p.lo + 0.5
                pos = Mm @ (W[:3, :3] @ c + W[:3, 3]) * 0.1
                n2 = E.MERGE.get(n, n); n2 = E.RENAME.get(n2, n2)
                out.append(dict(src=n, part=n2, n=int(len(q)), pos=pos.round(3).tolist(), span=round(span, 2)))
    return out
