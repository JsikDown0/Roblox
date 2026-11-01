"""
aero_export.py — Aero 리메이크(몸 + 무장 확정본)를 로블록스용 GLB 로 (2026-10-26 21:47~)

  python3 aero_export.py OUTDIR
  → OUTDIR/Aero_r2_C1_20261026.glb          노드 = 파트, 메시 = X_<파트>, 정점 = 월드(Blender) → glTF (x, z, −y), 팔레트 UV, 재질 1개
    OUTDIR/Aero_r2_C1_20261026_parts.json   관절(피벗)·부모·쉬는 자세 회전·상자 — heavy_blender.export_glb 와 같은 형식
    OUTDIR/AeroPalette_C1.png               64x64 팔레트(색 n = 8x8 칸 (n%8, 7-n//8)) — 프로토·중장갑과 같은 배치
    OUTDIR/AeroPalette_EmitMask.png         발광 칸(6)만 흰색 = HeavyPalette_EmitMask 와 같은 그림(이미 올린 중장갑 마스크를 그대로 써도 됨)

선례 그대로(heavy_mesh_export + rackfix_glb): 칸 0.05 Blender · 오브젝트 원점 = 관절 · 쉬는 자세 = 팔만 STANCE(다리 곧게) ·
  같은 축 자식은 칸을 합쳐(가려진 면 제거) · 기울인 자식은 메시째로 부모 축에 붙임 · Blender 없이 pygltflib 로 GLB.
유저 결정: 색 C1(T0 원본, 10-26 18:27) · 무장 = 라이플(2점사, 크기 1.15/1.35) · 왼손목 그레네이드 런처(탄두 빨강) · 못 S2 ·
  칼자루 등 위 왼쪽 + 라이플 허리 뒤 가로 = 안 A(21:47 "A로 가자").

파트 정리(움직이는 것만 따로 — 나머지는 합침):
  합침  SkirtB→Pelvis · ChestL/R→Torso · H_*·FinL/R·FinSubL/R→Head · BinderL/R→Backpack · BoostL/R→LowerLegL/R · GLauncherL→LowerArmL
  이름  ShoulderL/R → ShoulderPadL/R (MechClient 가 관절을 FindFirstChild(이름, true) 로 찾음 — 중장갑 때 같은 함정) · RifleR → Rifle
  따로  WingL/R(상승·부스트 때 펼침/젖힘) · GLCoverL(쏠 때 밀림) · SpikeL1/L2/R1/R2(궁극기 때 날아감) · SaberHolsterL(칼 뽑으면 숨김) ·
        Rifle(손) · RifleStowed(빔사벨 상태) · Grenade(탄 본보기 — 왼쪽 발사관 앞)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

import aero_r1 as A
import aero_colors as Cc
import aero_rifle as R
import aero_launcher as GL
import aero_stow as K

VOXF = 0.05                                              # heavy_mesh_export.VOXF 와 같음


# heavy_mesh_export.greedy_mesh 그대로 복사(그 모듈은 중장갑 빌드를 통째로 import 해서 Aero 묶음만으로는 안 돌아감)
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


class hx:
    greedy_mesh = staticmethod(greedy_mesh)

TAG = "Aero_r2b_C1_20261026"                             # r2b = r2 + 등 부품 앞면 흰색(22:29 유저 "B로 가자"). r2(21:52)는 이것 없이 내보낸 옛것
SCHEME = "C1 흰·주황"
REST_POSE = {k: v for k, v in A.STANCE.items() if "Arm" in k or "Shoulder" in k}
HEAD_SUBS = ["H_CrownL", "H_CrownR", "H_BrowL", "H_BrowR", "H_CheekL", "H_CheekR", "H_PlateL", "H_PlateR",
             "H_HelmRidge", "H_HelmBrow", "FinL", "FinR", "FinSubL", "FinSubR"]
MERGE = {"SkirtB": "Pelvis", "ChestL": "Torso", "ChestR": "Torso", **{n: "Head" for n in HEAD_SUBS},
         "BinderL": "Backpack", "BinderR": "Backpack", "BoostL": "LowerLegL", "BoostR": "LowerLegR", "GLauncherL": "LowerArmL"}
RENAME = {"ShoulderL": "ShoulderPadL", "ShoulderR": "ShoulderPadR", "RifleR": "Rifle"}


BACK_FRONT_WHITE = ("Backpack", "BinderL", "BinderR")


def back_front_white(M):
    """등 부품(백팩·바인더)의 앞을 보는 면(바로 앞 -Y 칸이 빈 칸)만 검회색 → 흰색 (aero_tone3 시안 B, 22:29 유저 "B로 가자").
    이유 [실측]: 가슴 역삼각형 바깥 틈으로 약 35칸 뒤 등 부품 앞면이 보이는데 같은 검회색이라, 조명·AO 없이 보면
    몸통과 뭉쳐 사각형으로 읽힘(정면 검회색 = 몸통 968칸 + 등 부품 1,158칸). 뒤·옆에서 보이는 면은 그대로."""
    n = 0
    for name in BACK_FRONT_WHITE:
        p = M.parts[name]
        nb = np.zeros_like(p.a); nb[:, 1:, :] = p.a[:, :-1, :]
        m = (p.a == 3) & (nb == 0)
        p.a[m] = 2; n += int(m.sum())
    return n


def build(tone=True):
    M = K.build("K1", stowed=True)                       # 몸 + 못 + 런처(닫힘) + 칼자루(등) + 허리 뒤 라이플
    R.attach(M, *R.SCALE)                                # 손 라이플도(쥐는 자리 확인용 + 총 본보기)
    tx, ty = GL.TUBES[0]
    GL.grenade(M, "Grenade", (int(tx), int(ty), GL.MOUTH - 8), parent="LowerArmL")
    if tone:
        back_front_white(M)
    return M


def _final_parent(name, M):
    par = M.parts[name].parent
    while par in MERGE:                                  # 합쳐진 부모(BinderL 등)는 합친 곳으로
        par = MERGE[par]
    return RENAME.get(par, par)


def mesh_data(M):
    """파트별 (로컬 정점[Blender, 피벗 기준], 쿼드, 색, 4x4 월드[Blender]) — heavy_mesh_export.export 와 같은 합치기."""
    union = set()
    for src, dst in MERGE.items():                       # 1) 같은 축이면 칸을 합침(나중 = src 가 덮음)
        rel = np.linalg.inv(M.world(dst)) @ M.world(src)
        if np.allclose(rel, np.eye(4)):
            a, b = M.parts[dst], M.parts[src]
            lo = np.minimum(a.lo, b.lo); hi = np.maximum(a.lo + np.array(a.a.shape), b.lo + np.array(b.a.shape))
            g = np.zeros(tuple(hi - lo), np.uint8)
            for q in (a, b):
                o = q.lo - lo
                sub = g[o[0]:o[0] + q.a.shape[0], o[1]:o[1] + q.a.shape[1], o[2]:o[2] + q.a.shape[2]]
                sub[q.a > 0] = q.a[q.a > 0]
            a.a, a.lo, a.hi = g, lo, hi
            union.add(src)
    out = {}
    for name in [n for n in M.parts if n not in MERGE]:
        p = M.parts[name]
        V, Q, C = hx.greedy_mesh(p.a, p.lo)
        pv = np.array(p.pivot, float)
        loc = (V - pv) * VOXF
        W = M.world(name, REST_POSE)
        for src, dst in MERGE.items():                   # 2) 기울어진 자식은 메시째로 이 파트 축에
            if dst != name or src in union:
                continue
            q = M.parts[src]
            V2, Q2, C2 = hx.greedy_mesh(q.a, q.lo)
            Ws = M.world(src, REST_POSE)
            P = V2 @ Ws[:3, :3].T + Ws[:3, 3]
            Wi = np.linalg.inv(W)
            P = P @ Wi[:3, :3].T + Wi[:3, 3]
            base = len(loc)
            loc = np.vstack([loc, (P - pv) * VOXF])
            Q = Q + [[i + base for i in qq] for qq in Q2]
            C = C + C2
        mat = np.eye(4); mat[:3, :3] = W[:3, :3]; mat[:3, 3] = (W[:3, :3] @ pv + W[:3, 3]) * VOXF
        out[RENAME.get(name, name)] = dict(parent=_final_parent(name, M) if p.parent else None, pivot_cells=pv.tolist(),
                                          merged=[k for k, v in MERGE.items() if v == name], matrix=mat, verts=loc, quads=Q, cols=C)
    return out


def palette_uv(n):
    bx, by = n % 8, 7 - n // 8
    return ((bx + 0.5) / 8.0, 1.0 - (by + 0.5) / 8.0)       # glTF v = 1 − Blender v (rackfix_glb 와 같음)


def palette_png(rgb_by_n, path, mask=False):
    img = np.zeros((64, 64, 3), np.uint8)
    img[:] = 0 if mask else 128
    for n, rgb in rgb_by_n.items():
        if mask and n not in A.EMISSIVE:
            continue
        bx, by = n % 8, 7 - n // 8
        r0 = 64 - (by + 1) * 8
        img[r0:r0 + 8, bx * 8:(bx + 1) * 8] = (255, 255, 255) if mask else rgb
    Image.fromarray(img).save(path)


def write_glb(parts, png_path, out):
    import pygltflib as G
    png = open(png_path, "rb").read()
    blob = bytearray()
    g = G.GLTF2(asset=G.Asset(generator="aero_export.py (10-26)", version="2.0"))

    def add(arr, target=None):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\0"
        off = len(blob); b = arr.tobytes(); blob += b
        g.bufferViews.append(G.BufferView(buffer=0, byteOffset=off, byteLength=len(b), target=target))
        return len(g.bufferViews) - 1

    g.scenes = [G.Scene(nodes=[])]; g.scene = 0
    g.samplers = [G.Sampler(magFilter=9728, minFilter=9984, wrapS=10497, wrapT=10497)]     # NEAREST
    g.images = [G.Image(mimeType="image/png", name="AeroPalette_C1", bufferView=add(np.frombuffer(png, np.uint8)))]
    g.textures = [G.Texture(sampler=0, source=0)]
    g.materials = [G.Material(name="AeroPaletteMat_Export", doubleSided=True,
                              pbrMetallicRoughness=G.PbrMetallicRoughness(baseColorTexture=G.TextureInfo(index=0), metallicFactor=0.1, roughnessFactor=0.55))]
    info = {"_units": "Blender 1 = 칸 20개(칸 0.05). 중장갑과 같은 규약 — 템플릿 좌표 = Blender × 2.",
            "_axes": "Blender (x, y, z) -> glTF/로블록스 가져오기 (x, z, -y). 기체 정면 = Blender -Y = 가져온 뒤 +Z (로블록스 LookVector -Z 와 반대 → 템플릿에서 180도 돌림).",
            "_rest_pose": "팔만 벌림(미리보기 STANCE 의 팔: UpperArm roty ∓9 · Shoulder ∓3 · LowerArm rotx -14/-10), 다리 곧게. 기울인 파트(스커트·날개·칼자루)는 회전이 메시에 구워져 있다.",
            "_emissive": "팔레트 칸 6 만 발광 — AeroPalette_EmitMask.png(= HeavyPalette_EmitMask 와 같은 그림). 7 = 금속색이라 프로토 마스크(6·7·9) 쓰면 안 됨.",
            "_scheme": SCHEME, "_merge": MERGE, "_rename": RENAME, "parts": {}}
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
            "parent": p["parent"], "merged": p["merged"],
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


def export(outdir):
    os.makedirs(outdir, exist_ok=True)
    pal = os.path.join(outdir, "AeroPalette_C1.png")
    palette_png(Cc.SCHEMES[SCHEME], pal)
    palette_png(Cc.SCHEMES[SCHEME], os.path.join(outdir, "AeroPalette_EmitMask.png"), mask=True)
    M = build()
    parts = mesh_data(M)
    rep = write_glb(parts, pal, os.path.join(outdir, TAG + ".glb"))
    tot = sum(r["tris"] for r in rep.values())
    for n, r in rep.items():
        print("%-14s parent=%-12s tris %5d  outward %.3f" % (n, parts[n]["parent"], r["tris"], r["outward"]))
    print("nodes", len(rep), "total tris", tot)
    return parts, rep


if __name__ == "__main__":
    export(sys.argv[1] if len(sys.argv) > 1 else "aero_out")
