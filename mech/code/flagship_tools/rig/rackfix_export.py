"""rackfix_export.py — 왼쪽 랙 칼자루를 백팩 메시에서 떼어 따로 파트로 (10-26 유저 "왼쪽 랙 칼자루가 백팩 메시에 합쳐져 있는 문제")
  python3 rackfix_export.py OUTDIR
  → OUTDIR/heavy_r2_mesh.json : 파트 2개만 — Backpack(왼쪽 칼자루 칸을 뺀 것, 나머지는 heavy_mesh_export 와 똑같이 합침) + SaberRackL(칼자루)
    heavy_blender.build / export_glb 가 그대로 읽는 형식. SaberRackL 축 = RackL 축(기울어진 랙과 같이 기움), 부모 Backpack.
  칼자루 칸 = RackL 의 색 4(자루)·7(꼭지) 중 랙 꼭대기(z 272) 위 — 랙 몸통은 백팩에 남는다.
"""
import json, os, sys
import numpy as np
import heavy_mesh_export as hx
import final_m2b as fm
import flagship_heavy as fh

def export(out):
    M = fm.build_all()
    rk = M.parts['RackL']
    Z = np.arange(rk.a.shape[2]) + rk.lo[2]
    mask = np.zeros(rk.a.shape, bool)
    mask[:, :, Z > 272] = True
    mask &= (rk.a == 4) | (rk.a == 7)
    hilt = np.where(mask, rk.a, 0).astype(rk.a.dtype)
    n_hilt = int(mask.sum())
    rk.a = np.where(mask, 0, rk.a).astype(rk.a.dtype)       # 랙 몸통만 남김
    data = {"voxf": hx.VOXF, "rest_pose": "arms = STANCE, legs straight", "parts": {}, "order": ["Backpack", "SaberRackL"],
            "merge": hx.MERGE, "note": "rackfix 10-26: Backpack(왼쪽 칼자루 뺌) + SaberRackL"}
    # Backpack: heavy_mesh_export.export 와 같은 합치기(RackL·RackR 는 기울어져 메시째)
    name = 'Backpack'
    p = M.parts[name]
    V, Q, C = hx.greedy_mesh(p.a, p.lo)
    pv = np.array(p.pivot)
    loc = (V - pv) * hx.VOXF
    W = M.world(name, hx.REST_POSE)
    for src in ('RackL', 'RackR'):
        q = M.parts[src]
        V2, Q2, C2 = hx.greedy_mesh(q.a, q.lo)
        Ws = M.world(src, hx.REST_POSE)
        P = V2 @ Ws[:3, :3].T + Ws[:3, 3]
        Wi = np.linalg.inv(W)
        P = P @ Wi[:3, :3].T + Wi[:3, 3]
        base = len(loc)
        loc = np.vstack([loc, (P - pv) * hx.VOXF])
        Q = Q + [[i + base for i in qq] for qq in Q2]
        C = C + C2
    mat = np.eye(4); mat[:3, :3] = W[:3, :3]; mat[:3, 3] = (W[:3, :3] @ pv + W[:3, 3]) * hx.VOXF
    data["parts"][name] = {"parent": p.parent, "pivot_cells": pv.tolist(), "merged": ["RackL(칼자루 뺌)", "RackR"],
                           "matrix": np.round(mat, 6).tolist(), "verts": np.round(loc, 4).tolist(), "quads": Q, "cols": C}
    # SaberRackL: RackL 의 축·피벗 그대로
    Vh, Qh, Ch = hx.greedy_mesh(hilt, rk.lo)
    pvr = np.array(rk.pivot)
    Wr = M.world('RackL', hx.REST_POSE)
    matr = np.eye(4); matr[:3, :3] = Wr[:3, :3]; matr[:3, 3] = (Wr[:3, :3] @ pvr + Wr[:3, 3]) * hx.VOXF
    data["parts"]["SaberRackL"] = {"parent": "Backpack", "pivot_cells": pvr.tolist(), "merged": [],
                                   "matrix": np.round(matr, 6).tolist(), "verts": np.round((Vh - pvr) * hx.VOXF, 4).tolist(), "quads": Qh, "cols": Ch}
    os.makedirs(out, exist_ok=True)
    json.dump(data, open(os.path.join(out, "heavy_r2_mesh.json"), "w"), separators=(",", ":"))
    for k, v in fh.SCHEMES.items():
        hx.palette_png(v, os.path.join(out, "HeavyPalette_%s.png" % k))
    hx.palette_png(fh.SCHEMES["A"], os.path.join(out, "HeavyPalette_EmitMask.png"), mask=True)
    # 확인: 칼자루·백팩 월드 상자(템플릿 좌표 = Blender × 2, (x,y,z) → (−x, z, y))
    def wbox(part, matrix):
        pts = np.array(part["verts"]) @ np.array(matrix)[:3, :3].T + np.array(matrix)[:3, 3]
        r = np.stack([-pts[:, 0], pts[:, 2], pts[:, 1]], 1) * 2
        return r.min(0).round(3), r.max(0).round(3)
    for n in data["order"]:
        lo, hi = wbox(data["parts"][n], data["parts"][n]["matrix"])
        print(n, 'quads', len(data["parts"][n]["quads"]), 'tris', 2 * len(data["parts"][n]["quads"]), 'template box', lo, hi, 'center', ((lo + hi) / 2).round(3), 'size', (hi - lo).round(3))
    print('hilt cells', n_hilt)
    return data

if __name__ == '__main__':
    export(sys.argv[1] if len(sys.argv) > 1 else 'rackfix_out')
