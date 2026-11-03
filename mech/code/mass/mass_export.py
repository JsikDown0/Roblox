"""양산형 머리 시안 → 로블록스 확인용 GLB (2026-11-03). 유저 "a, c, d 시안 실제 로블 스튜디오에서 보고 싶어. 머리만 glb".

aero_export.py 의 greedy_mesh · palette_uv · write_glb 를 그대로 옮김(그 모듈은 Aero 빌드를 import 해서 따로 못 씀).
노드 = 파트(Head 하나), 정점 = 월드(Blender, 칸 × 0.05) → glTF (x, z, −y), 팔레트 UV(8×8 칸, NEAREST), 재질 1개.
쓰기: python3 mass_export.py <출력폴더> [a,c,d]  (소문자 = r4 하관 안, 대문자 A~E = r5 3면 안)   (원래 해상도 — 게임용 절반 해상도는 확정 뒤)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_head_r4 as h4  # noqa: E402
import mass_head_r5 as h5  # noqa: E402

VOXF = 0.05


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


def palette_uv(n):
    bx, by = n % 8, 7 - n // 8
    return ((bx + 0.5) / 8.0, 1.0 - (by + 0.5) / 8.0)       # glTF v = 1 − Blender v (rackfix_glb 와 같음)



def palette_png(rgb_by_n, path, mask=False):
    img = np.zeros((64, 64, 3), np.uint8)
    img[:] = 0 if mask else 128
    for n, rgb in rgb_by_n.items():
        if mask and n not in r1.EMISSIVE:
            continue
        bx, by = n % 8, 7 - n // 8
        r0 = 64 - (by + 1) * 8
        img[r0:r0 + 8, bx * 8:(bx + 1) * 8] = (255, 255, 255) if mask else rgb
    Image.fromarray(img).save(path)


def parts_of(M, names=("Torso", "Head")):
    """여러 파트: 노드마다 피벗 기준 정점 + 월드 행렬(부모 없이 평평하게)."""
    out = {}
    for n in names:
        p = M.parts[n]
        V, Q, C = greedy_mesh(p.a, p.lo)
        pv = np.array(p.pivot, float)
        W = M.world(n)
        mat = np.eye(4); mat[:3, :3] = W[:3, :3]; mat[:3, 3] = (W[:3, :3] @ pv + W[:3, 3]) * VOXF
        out[n] = dict(parent=None, matrix=mat, verts=(V - pv) * VOXF, quads=Q, cols=C)
    return out


def head_parts(M):
    """머리 하나만: 정점 = 월드 칸 × VOXF (피벗 = 머리 관절)."""
    p = M.parts["Head"]
    V, Q, C = greedy_mesh(p.a, p.lo)
    pv = np.array(p.pivot, float)
    W = M.world("Head")
    mat = np.eye(4); mat[:3, :3] = W[:3, :3]; mat[:3, 3] = (W[:3, :3] @ pv + W[:3, 3]) * VOXF
    return {"Head": dict(parent=None, matrix=mat, verts=(V - pv) * VOXF, quads=Q, cols=C)}


def write_glb(parts, png_path, out):
    import pygltflib as G
    png = open(png_path, "rb").read()
    blob = bytearray()
    g = G.GLTF2(asset=G.Asset(generator="mass_export.py (11-03)", version="2.0"))

    def add(arr, target=None):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\0"
        off = len(blob); b = arr.tobytes(); blob += b
        g.bufferViews.append(G.BufferView(buffer=0, byteOffset=off, byteLength=len(b), target=target))
        return len(g.bufferViews) - 1

    g.scenes = [G.Scene(nodes=[])]; g.scene = 0
    g.samplers = [G.Sampler(magFilter=9728, minFilter=9984, wrapS=10497, wrapT=10497)]     # NEAREST
    g.images = [G.Image(mimeType="image/png", name="MassPalette", bufferView=add(np.frombuffer(png, np.uint8)))]
    g.textures = [G.Texture(sampler=0, source=0)]
    g.materials = [G.Material(name="MassPaletteMat_Export", doubleSided=True,
                              pbrMetallicRoughness=G.PbrMetallicRoughness(baseColorTexture=G.TextureInfo(index=0), metallicFactor=0.1, roughnessFactor=0.55))]
    info = {"_units": "Blender 1 = 칸 20개(칸 0.05) — FELSEN·Aero 와 같은 규약(템플릿 좌표 = Blender × 2).",
            "_axes": "Blender (x, y, z) -> glTF (x, z, -y). 기체 정면 = Blender -Y = 가져온 뒤 +Z.",
            "_emissive": "팔레트 칸 6(바이저)만 발광 — MassPalette_EmitMask.png.", "parts": {}}
    report = {}
    for name, p in parts.items():
        Mw = p["matrix"]
        V = p["verts"] @ Mw[:3, :3].T + Mw[:3, 3]
        Vg = np.stack([V[:, 0], V[:, 2], -V[:, 1]], 1)
        pos, nor, uv, idx = [], [], [], []
        for q, c in zip(p["quads"], p["cols"]):
            P4 = Vg[q]
            n = np.cross(P4[1] - P4[0], P4[2] - P4[0]); n = n / np.linalg.norm(n)
            b = len(pos)
            pos.extend(P4); nor.extend([n] * 4); uv.extend([palette_uv(c)] * 4)
            idx.extend([b, b + 1, b + 2, b, b + 2, b + 3])
        pos = np.array(pos, np.float32); nor = np.array(nor, np.float32); uv = np.array(uv, np.float32); idx = np.array(idx, np.uint32)
        a_pos = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(pos, 34962), componentType=5126, count=len(pos), type="VEC3", min=pos.min(0).tolist(), max=pos.max(0).tolist()))
        a_nor = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(nor, 34962), componentType=5126, count=len(nor), type="VEC3"))
        a_uv = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(uv, 34962), componentType=5126, count=len(uv), type="VEC2"))
        a_idx = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(idx, 34963), componentType=5125, count=len(idx), type="SCALAR"))
        g.meshes.append(G.Mesh(name="X_" + name, primitives=[G.Primitive(attributes=G.Attributes(POSITION=a_pos, NORMAL=a_nor, TEXCOORD_0=a_uv), indices=a_idx, material=0, mode=4)]))
        g.nodes.append(G.Node(name=name, mesh=len(g.meshes) - 1))
        g.scenes[0].nodes.append(len(g.nodes) - 1)
        piv = Mw[:3, 3]
        c0 = pos.mean(0); fc = pos.reshape(-1, 4, 3).mean(1); fn = nor[::4]
        info["parts"][name] = {
            "parent": p["parent"],
            "pivot_blender": [round(float(c), 5) for c in piv],
            "pivot_import": [round(float(piv[0]), 5), round(float(piv[2]), 5), round(float(-piv[1]), 5)],
            "rest_rot_blender": np.round(Mw[:3, :3], 6).tolist(),
            "bbmin_blender": np.round(V.min(0), 4).tolist(), "bbmax_blender": np.round(V.max(0), 4).tolist(),
            "tris": int(len(idx) // 3)}
        report[name] = dict(tris=int(len(idx) // 3), outward=round(float(np.mean(np.sum((fc - c0) * fn, 1) > 0)), 3))
    while len(blob) % 4:
        blob += b"\0"
    g.buffers = [G.Buffer(byteLength=len(blob))]
    g.set_binary_blob(bytes(blob))
    g.save_binary(out)
    with open(os.path.splitext(out)[0] + "_parts.json", "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    return report



if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    sel = sys.argv[2].split(",") if len(sys.argv) > 2 else ["a", "c", "d"]
    os.makedirs(out, exist_ok=True)
    pal = os.path.join(out, "MassPalette.png")
    PALX = dict(h2.PAL); PALX[8] = (196, 198, 200)                       # 8 = 크롬(피스톤 로드, 하체 r4) — 흰 선(가슴 r5)은 철회
    palette_png(PALX, pal)
    palette_png(PALX, os.path.join(out, "MassPalette_EmitMask.png"), mask=True)
    for j in sel:
        if j.startswith("chest"):                                       # 가슴 rN + 머리 A: chest3a, chest4b …
            import importlib
            cm = importlib.import_module("mass_chest_r%s" % j[5])
            M = cm.build_all(j[6:] if j[5] == "5" else j[-1])
            rep = write_glb(parts_of(M), pal, os.path.join(out, "Mass_Upper_r%s%s_20261103.glb" % (j[5], j[6:])))
        else:
            M = h5.build_all(j) if j in "ABCDE" else h4.build_all(j)
            rep = write_glb(head_parts(M), pal, os.path.join(out, "Mass_Head_%s_20261103.glb" % j))
        print(j, rep)
