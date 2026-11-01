"""rackfix_glb.py — heavy_r2_mesh.json(파트 2개) → GLB, Blender 없이 (10-26). heavy_blender.export_glb 와 같은 규약:
  노드 이름 = 파트, 메시 이름 = X_<파트>, 정점 = 월드(Blender) → glTF Y-up (x, z, −y), UV = 팔레트 칸 가운데(glTF v = 1 − Blender v),
  재질 1개(팔레트 PNG — 원래 GLB 의 그림을 그대로 씀, NEAREST), 양면, 금속 0.1 · 거칠기 0.55, 발광 없음."""
import json, sys
import numpy as np
import pygltflib as G

def palette_uv(n):
    bx, by = n % 8, 7 - n // 8
    return ((bx + 0.5) / 8.0, 1.0 - (by + 0.5) / 8.0)

def build(mesh_json, ref_glb, out):
    d = json.load(open(mesh_json))
    ref = G.GLTF2().load(ref_glb)
    img_bv = ref.bufferViews[ref.images[0].bufferView]
    png = ref.binary_blob()[img_bv.byteOffset or 0:(img_bv.byteOffset or 0) + img_bv.byteLength]
    blob = bytearray()
    def add(arr, target=None):
        nonlocal blob
        while len(blob) % 4: blob += b'\0'
        off = len(blob); b = arr.tobytes(); blob += b
        bv = G.BufferView(buffer=0, byteOffset=off, byteLength=len(b), target=target)
        g.bufferViews.append(bv); return len(g.bufferViews) - 1
    g = G.GLTF2(asset=G.Asset(generator='rackfix_glb.py (10-26)', version='2.0'))
    g.scenes = [G.Scene(nodes=[])]; g.scene = 0
    g.samplers = [G.Sampler(magFilter=9728, minFilter=9984, wrapS=10497, wrapT=10497)]
    g.images = [G.Image(mimeType='image/png', name='HeavyPalette_A', bufferView=add(np.frombuffer(png, np.uint8)))]
    g.textures = [G.Texture(sampler=0, source=0)]
    g.materials = [G.Material(name='HeavyPaletteMat_Export', doubleSided=True,
                              pbrMetallicRoughness=G.PbrMetallicRoughness(baseColorTexture=G.TextureInfo(index=0), metallicFactor=0.1, roughnessFactor=0.55))]
    report = {}
    for name in d['order']:
        p = d['parts'][name]
        Mw = np.array(p['matrix'])
        V = np.array(p['verts']) @ Mw[:3, :3].T + Mw[:3, 3]           # 월드(Blender)
        Vg = np.stack([V[:, 0], V[:, 2], -V[:, 1]], 1)                # glTF Y-up
        pos, nor, uv, idx = [], [], [], []
        for q, c in zip(p['quads'], p['cols']):
            P4 = Vg[q]
            n = np.cross(P4[1] - P4[0], P4[2] - P4[0]); n = n / np.linalg.norm(n)
            b = len(pos)
            pos.extend(P4); nor.extend([n] * 4); uv.extend([palette_uv(c)] * 4)
            idx.extend([b, b + 1, b + 2, b, b + 2, b + 3])
        pos = np.array(pos, np.float32); nor = np.array(nor, np.float32); uv = np.array(uv, np.float32); idx = np.array(idx, np.uint32)
        a_pos = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(pos, 34962), componentType=5126, count=len(pos), type='VEC3', min=pos.min(0).tolist(), max=pos.max(0).tolist()))
        a_nor = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(nor, 34962), componentType=5126, count=len(nor), type='VEC3'))
        a_uv = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(uv, 34962), componentType=5126, count=len(uv), type='VEC2'))
        a_idx = len(g.accessors); g.accessors.append(G.Accessor(bufferView=add(idx, 34963), componentType=5125, count=len(idx), type='SCALAR'))
        g.meshes.append(G.Mesh(name='X_' + name, primitives=[G.Primitive(attributes=G.Attributes(POSITION=a_pos, NORMAL=a_nor, TEXCOORD_0=a_uv), indices=a_idx, material=0, mode=4)]))
        g.nodes.append(G.Node(name=name, mesh=len(g.meshes) - 1))
        g.scenes[0].nodes.append(len(g.nodes) - 1)
        c0 = pos.mean(0)
        fc = pos.reshape(-1, 4, 3).mean(1); fn = nor[::4]
        outward = float(np.mean(np.sum((fc - c0) * fn, 1) > 0))
        report[name] = dict(tris=len(idx) // 3, min=pos.min(0).round(4).tolist(), max=pos.max(0).round(4).tolist(), outward_frac=round(outward, 3))
    while len(blob) % 4: blob += b'\0'
    g.buffers = [G.Buffer(byteLength=len(blob))]
    g.set_binary_blob(bytes(blob))
    g.save_binary(out)
    return report

if __name__ == '__main__':
    r = build(sys.argv[1], sys.argv[2], sys.argv[3])
    print(json.dumps(r, ensure_ascii=False, indent=1))
