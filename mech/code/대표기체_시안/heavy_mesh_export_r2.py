"""
heavy_mesh_export.py — 확정 중장갑(final_m2b.build_all)을 Blender 로 넘길 메시 데이터로 바꾼다 (2026-10-26)

  python3 heavy_mesh_export.py OUTDIR
  → OUTDIR/heavy_r2_mesh.json        파트별 그리디 메시(피벗 기준 로컬, Blender 단위) + 부모 + 쉬는 자세 행렬
    OUTDIR/HeavyPalette_A.png / _B.png / _C.png   64x64 팔레트(색 n = 8x8 칸 (n%8, 7-n//8), 행은 아래부터) — 프로토와 같은 배치
    OUTDIR/HeavyPalette_EmitMask.png  발광 칸(6)만 흰색

규약
  - 칸 = 0.05 Blender. flag_vox 칸 i 의 중심 = 정수 i → 칸 모서리 = i ± 0.5.
  - 오브젝트 원점 = 파트 피벗(관절). 메시 정점 = (모서리 - 피벗) × 0.05, 파트 자기 축(회전 전)이라 기울인 파트도 메시는 반듯.
  - 쉬는 자세 = 팔만 미리보기 STANCE(팔 벌림·아래팔 굽힘), 다리는 곧게.
    팔을 곧게 내리면 아래팔이 八 스커트와 약 17,500칸 겹친다 [실측].
  - matrix = 파트의 월드 4x4(Blender 단위). 기울기(스커트·랙·견갑)는 여기에 들어 있다.
  - 면마다 색 번호 → Blender 쪽에서 팔레트 UV(그 색 칸의 가운데)로.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

import flagship_heavy as fh
import final_m2b as fm

VOXF = 0.05
REST_POSE = {k: v for k, v in fh.STANCE.items() if "Arm" in k or "Shoulder" in k}
# (10-26 02:41 유저 "파트 수를 외형 영향 없는 선에서 줄일 수 있어?") 서로 안 움직이는 파트를 합친다.
#   같은 축(상대 회전 없음)이면 칸을 합쳐(나중 파트가 덮음 — vox_preview 와 같은 규칙) 가려진 안쪽 면까지 없앤다.
#   기울어진 파트(랙)는 메시째로 합친다(회전된 판이 그대로 → 계단 없음).
#   안 합치는 것: Head(고개)·Shoulder(팔을 일부 따라감)·Skirt(걸을 때 허벅지 추종)·Backpack(게임 코드가 무기·추진기 붙이는 기준 파트 — MechServer setGun 의 bp)
MERGE = {"ChestNew": "Torso", "RackL": "Backpack", "RackR": "Backpack"}


def greedy_mesh(a, lo):
    """파트 칸 배열 → (정점 [모서리 좌표, 실수], 쿼드 [정점 번호 4개, 바깥에서 보면 반시계], 색)."""
    P = np.pad(a, 1)
    off = np.array(lo) - 1                       # P 인덱스 → 칸 번호
    verts, vmap, quads, cols = [], {}, [], []

    def vid(p):
        k = tuple(p)
        if k not in vmap:
            vmap[k] = len(verts); verts.append(k)
        return vmap[k]

    for ax in range(3):
        u, w = (ax + 1) % 3, (ax + 2) % 3
        for d in (1, -1):
            nb = np.roll(P, -d, axis=ax)
            face = np.where((P > 0) & (nb == 0), P, 0)
            for s in range(P.shape[ax]):
                m = np.take(face, s, axis=ax)
                rest = [x for x in range(3) if x != ax]
                if rest != [u, w]:
                    m = m.T
                if not m.any():
                    continue
                m = m.copy()
                plane = s + (1 if d > 0 else 0)          # 칸 s 의 위/아래 모서리(칸 [c, c+1] 기준)
                done = np.zeros(m.shape, bool)
                nu, nw = m.shape
                for iu, iw in np.argwhere(m > 0):
                    if done[iu, iw]:
                        continue
                    c = m[iu, iw]
                    ww = 1
                    while iw + ww < nw and m[iu, iw + ww] == c and not done[iu, iw + ww]:
                        ww += 1
                    hu = 1
                    while iu + hu < nu and np.all(m[iu + hu, iw:iw + ww] == c) and not done[iu + hu, iw:iw + ww].any():
                        hu += 1
                    done[iu:iu + hu, iw:iw + ww] = True
                    corners = []
                    for cu, cw in ((iu, iw), (iu + hu, iw), (iu + hu, iw + ww), (iu, iw + ww)):
                        p = [0, 0, 0]
                        p[ax] = plane + off[ax]
                        p[u] = cu + off[u]
                        p[w] = cw + off[w]
                        corners.append(p)
                    if d < 0:
                        corners.reverse()
                    quads.append([vid(p) for p in corners])
                    cols.append(int(c))
    # 칸 [c, c+1] 모서리 → flag_vox 좌표(칸 중심 정수): -0.5
    V = np.array(verts, float) - 0.5
    return V, quads, cols


def palette_png(rgb_by_n, path, mask=False):
    img = np.zeros((64, 64, 3), np.uint8)
    img[:] = 0 if mask else 128
    for n, rgb in rgb_by_n.items():
        if mask and n not in fh.EMISSIVE:
            continue
        bx, by = n % 8, 7 - n // 8                 # by = 아래부터 행
        r0 = 64 - (by + 1) * 8                     # PNG 는 위부터 행
        img[r0:r0 + 8, bx * 8:(bx + 1) * 8] = (255, 255, 255) if mask else rgb
    Image.fromarray(img).save(path)


def export(out):
    M = fm.build_all()
    data = {"voxf": VOXF, "rest_pose": "arms = STANCE, legs straight", "parts": {}, "order": None, "merge": MERGE,
            "schemes": {k: {str(n): list(c) for n, c in v.items()} for k, v in fh.SCHEMES.items()},
            "emissive": sorted(fh.EMISSIVE)}
    tot = 0
    # 1) 같은 축 파트는 칸을 합친다
    union = {}
    for src, dst in MERGE.items():
        rel = np.linalg.inv(M.world(dst)) @ M.world(src)
        if np.allclose(rel, np.eye(4)):
            a, b = M.parts[dst], M.parts[src]
            lo = np.minimum(a.lo, b.lo); hi = np.maximum(a.hi, b.hi)
            g = np.zeros(tuple(hi - lo), np.uint8)
            for q in (a, b):                                # 나중 파트(src)가 덮음
                o = q.lo - lo
                sub = g[o[0]:o[0] + q.a.shape[0], o[1]:o[1] + q.a.shape[1], o[2]:o[2] + q.a.shape[2]]
                sub[q.a > 0] = q.a[q.a > 0]
            a.a, a.lo, a.hi = g, lo, hi
            union[src] = dst
    order = [n for n in M.parts if n not in MERGE]
    data["order"] = order
    for name in order:
        p = M.parts[name]
        V, Q, C = greedy_mesh(p.a, p.lo)
        pv = np.array(p.pivot)
        loc = (V - pv) * VOXF
        W = M.world(name, REST_POSE)                       # 칸 단위 4x4
        # 2) 기울어진 파트는 메시째로 이 파트의 축에 옮겨 붙인다
        for src, dst in MERGE.items():
            if dst != name or src in union:
                continue
            q = M.parts[src]
            V2, Q2, C2 = greedy_mesh(q.a, q.lo)
            Ws = M.world(src, REST_POSE)
            P = V2 @ Ws[:3, :3].T + Ws[:3, 3]                # 월드 칸
            Wi = np.linalg.inv(W)
            P = P @ Wi[:3, :3].T + Wi[:3, 3]                 # 이 파트 격자(회전 전)
            base = len(loc)
            loc = np.vstack([loc, (P - pv) * VOXF])
            Q = Q + [[i + base for i in qq] for qq in Q2]
            C = C + C2
        R = W[:3, :3]
        t = (W[:3, :3] @ pv + W[:3, 3]) * VOXF              # 피벗의 월드 위치(Blender 단위)
        mat = np.eye(4); mat[:3, :3] = R; mat[:3, 3] = t
        data["parts"][name] = {
            "parent": p.parent, "pivot_cells": pv.tolist(), "merged": [k for k, v in MERGE.items() if v == name],
            "matrix": np.round(mat, 6).tolist(),
            "verts": np.round(loc, 4).tolist(), "quads": Q, "cols": C,
        }
        tot += 2 * len(Q)
        print("%-10s quads %5d verts %5d" % (name, len(Q), len(V)), flush=True)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "heavy_r2_mesh.json"), "w") as f:
        json.dump(data, f, separators=(",", ":"))
    for k, v in fh.SCHEMES.items():
        palette_png(v, os.path.join(out, "HeavyPalette_%s.png" % k))
    palette_png(fh.SCHEMES["A"], os.path.join(out, "HeavyPalette_EmitMask.png"), mask=True)
    print("total tris", tot)
    return data


if __name__ == "__main__":
    export(sys.argv[1] if len(sys.argv) > 1 else ".")
