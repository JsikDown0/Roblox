"""
jet_export.py — FalcoJet r1 → GLB + parts.json + Studio 조립 Lua (2026-11-06)

  python3 jet_export.py OUTDIR
  → OUTDIR/FalcoJet_r1_20261106.glb          노드 = 파트 8개, 메시 = X_<파트>, 정점 = 월드(Blender, 칸 0.05) → glTF (x, z, −y), 팔레트 UV(인간형과 같은 배치)
    OUTDIR/FalcoJet_r1_20261106_parts.json   파트 · 부착점 · 크기 · 무게 중심(템플릿 좌표)
    OUTDIR/falco_jet_build.lua               Studio 명령 바 조립 스크립트(데이터 표 포함)

선례 = aero_export.py(10-26 AELLO) 규약 그대로: 가져오기 뒤 (x, y, z) → (−x, z, y) 로 들어오고 회전 없음, 템플릿 = (가져온 위치 − O) × 2.
기울인 파트(꼬리날개)는 회전을 메시에 구움 → 모든 MeshPart 는 회전 0.
"""
import json
import os
import sys

import numpy as np

import jet_r1 as J
import aero_export as E                     # greedy_mesh · palette_png · write_glb · palette_uv
import aero_colors as Cc

VOXF = 0.05


def mesh_data(M):
    out = {}
    for name, p in M.parts.items():
        V, Q, C = E.greedy_mesh(p.a, p.lo)
        pv = np.array(p.pivot, float)
        W = M.world(name)
        mat = np.eye(4); mat[:3, :3] = W[:3, :3]; mat[:3, 3] = (W[:3, :3] @ pv + W[:3, 3]) * VOXF
        out[name] = dict(parent=p.parent, pivot_cells=pv.tolist(), merged=[], matrix=mat, verts=(V - pv) * VOXF, quads=Q, cols=C)
    return out


def world_bbox(part):
    Mw = part["matrix"]
    V = part["verts"] @ Mw[:3, :3].T + Mw[:3, 3]            # Blender 단위
    return V.min(0), V.max(0)


def v3(t):
    return [round(float(c), 4) for c in t]


def build_data(M, parts):
    A, G = J.attachments()
    D = {"center_imp": {}, "center": {}, "size": {}, "pivot": {}, "att": {}, "glow": {}}
    for n, p in parts.items():
        lo, hi = world_bbox(p)
        c = (lo + hi) / 2
        D["center_imp"][n] = v3((-c[0], c[2], c[1]))          # 가져온 자리(Blender 단위, 가져오기 축)
        D["center"][n] = v3(J.Mm @ c * 2)                      # 템플릿(스터드) = Blender × 2
        e = hi - lo
        D["size"][n] = v3(np.abs(J.Mm @ e) * 2)
        D["pivot"][n] = v3(J.T(M.parts[n].pivot) if n != "JetBody" else (0, 0, 0))
    for k, (part, pos, d) in A.items():
        D["att"][k] = {"part": part, "pos": v3(J.T(pos)), "dir": d}
    for k, (part, pos) in G.items():
        D["glow"][k] = {"part": part, "pos": v3(J.T(pos))}
    size, center = J.hitbox(M)
    D["hitbox"] = {"size": list(size), "center": center}
    st = J.stats(M)
    D["bbox_min"], D["bbox_max"], D["com"] = st["bbox_min"], st["bbox_max"], st["com"]
    D["source"] = J.TAG + ".glb"
    return D, st


def lua_table(o, ind=0):
    if isinstance(o, dict):
        items = []
        for k, v in o.items():
            items.append('["%s"] = %s' % (k, lua_table(v, ind + 1)))
        return "{" + ", ".join(items) + "}"
    if isinstance(o, (list, tuple)):
        return "{" + ", ".join(lua_table(v, ind + 1) for v in o) + "}"
    if o is None:
        return "nil"
    if isinstance(o, bool):
        return "true" if o else "false"
    if isinstance(o, str):
        return '"%s"' % o
    return repr(o)


def export(outdir):
    os.makedirs(outdir, exist_ok=True)
    pal = os.path.join(outdir, "AeroPalette_C1.png")
    E.palette_png(Cc.SCHEMES[E.SCHEME], pal)
    M = J.build_all()
    parts = mesh_data(M)
    glb = os.path.join(outdir, J.TAG + ".glb")
    rep = E.write_glb(parts, pal, glb)
    D, st = build_data(M, parts)
    info = {"_units": "템플릿(로블록스) 스터드. 원점 = HumanoidRootPart 중심 자리. 앞 = −Z · 위 = +Y · +X = 기체 오른쪽(인간형 AELLO 템플릿과 같은 축).",
            "_import": "GLB = Blender 단위(칸 0.05). 로블록스 가져오기 뒤 (x, y, z) → (−x, z, y), 회전 없음 → 템플릿 = (가져온 위치 − O) × 2.",
            "_palette": "인간형과 같은 팔레트 배치(색 n = 8x8 칸 (n%8, 7−n//8)) → SurfaceAppearance 102711399981461 + 발광 마스크 125885624850733 그대로.",
            "tris": {n: r["tris"] for n, r in rep.items()}, **D, "stats": st}
    with open(os.path.join(outdir, J.TAG + "_parts.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    tpl = open(os.path.join(J.HERE, "falco_jet_build_template.lua"), encoding="utf-8").read()
    with open(os.path.join(outdir, "falco_jet_build.lua"), "w", encoding="utf-8") as f:
        f.write("local D = " + lua_table(D) + "\n" + tpl)
    for n, r in rep.items():
        print("%-12s tris %5d  outward %.3f  size %s" % (n, r["tris"], r["outward"], D["size"][n]))
    print("total tris", sum(r["tris"] for r in rep.values()))
    return D, st


if __name__ == "__main__":
    export(sys.argv[1] if len(sys.argv) > 1 else "jet_out")
