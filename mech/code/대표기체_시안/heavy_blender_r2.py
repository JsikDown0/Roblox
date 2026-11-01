"""
heavy_blender.py — Blender 안에서 실행: heavy_r2_mesh.json → 새 장면 'Heavy_r2' 에 중장갑 확정본 조립 (2026-10-26)

  쓰는 법 (Blender 스크립트 편집기 또는 MCP):
    F = r"C:\\Users\\<you>\\Downloads\\Mech_Basic_Roblox\\Heavy_r2"
    exec(open(F + r"\\heavy_blender.py", encoding="utf-8").read())
    build(F)                 # 색 A
    set_scheme(F, "B")       # 팔레트만 바꿔 보기 (A/B/C)

  만드는 것
    - 장면 'Heavy_r2' (기존 장면은 안 건드림) + 컬렉션 'Heavy_r2_Final'
    - 파트마다 오브젝트 'HV_<파트>': 원점 = 관절(피벗), 부모 연결(Pelvis 가 뿌리), 기울인 파트는 오브젝트 회전으로
    - 재질 하나 'HeavyPaletteMat': 팔레트 PNG(64x64, 색 n = 8x8 칸) + 발광 마스크(색 6) — 면마다 UV 가 자기 색 칸 가운데
  다시 실행하면 같은 컬렉션을 비우고 새로 만든다.
"""
import json
import os

import bpy
from mathutils import Matrix

PREFIX = "HV_"
COLL = "Heavy_r2_Final"
SCENE = "Heavy_r2"
MAT = "HeavyPaletteMat"


def palette_uv(n):
    bx, by = n % 8, 7 - n // 8
    return ((bx + 0.5) / 8.0, (by + 0.5) / 8.0)


def _img(path, noncolor=False):
    name = os.path.basename(path)
    im = bpy.data.images.get(name)
    if im is None:
        im = bpy.data.images.load(path)
    else:
        im.filepath = path
        im.reload()
    if noncolor:
        im.colorspace_settings.name = "Non-Color"
    return im


def material(folder, scheme="A"):
    m = bpy.data.materials.get(MAT) or bpy.data.materials.new(MAT)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (600, 0)
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled"); bs.location = (250, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-300, 150); tex.interpolation = "Closest"
    tex.name = "Palette"
    tex.image = _img(os.path.join(folder, "HeavyPalette_%s.png" % scheme))
    msk = nt.nodes.new("ShaderNodeTexImage"); msk.location = (-300, -200); msk.interpolation = "Closest"
    msk.image = _img(os.path.join(folder, "HeavyPalette_EmitMask.png"), noncolor=True)
    mul = nt.nodes.new("ShaderNodeMath"); mul.location = (0, -200); mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 4.0
    nt.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
    em = bs.inputs.get("Emission Color") or bs.inputs.get("Emission")
    nt.links.new(tex.outputs["Color"], em)
    nt.links.new(msk.outputs["Color"], mul.inputs[0])
    nt.links.new(mul.outputs[0], bs.inputs["Emission Strength"])
    bs.inputs["Roughness"].default_value = 0.55
    bs.inputs["Metallic"].default_value = 0.1
    nt.links.new(bs.outputs[0], out.inputs[0])
    return m


def set_scheme(folder, scheme):
    m = bpy.data.materials[MAT]
    m.node_tree.nodes["Palette"].image = _img(os.path.join(folder, "HeavyPalette_%s.png" % scheme))


def build(folder, scheme="A", switch=True):
    d = json.load(open(os.path.join(folder, "heavy_r2_mesh.json"), encoding="utf-8"))
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    col = bpy.data.collections.get(COLL)
    if col is None:
        col = bpy.data.collections.new(COLL)
        sc.collection.children.link(col)
    else:
        for o in list(col.objects):
            me = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)
    mat = material(folder, scheme)
    objs, tris = {}, 0
    for name in d["order"]:
        p = d["parts"][name]
        me = bpy.data.meshes.new(PREFIX + name)
        me.from_pydata([tuple(v) for v in p["verts"]], [], p["quads"])
        uv = []
        for c in p["cols"]:
            u = palette_uv(c)
            uv += [u[0], u[1]] * 4
        lay = me.uv_layers.new(name="UVMap")
        lay.data.foreach_set("uv", uv)
        me.materials.append(mat)
        me.update()
        o = bpy.data.objects.new(PREFIX + name, me)
        col.objects.link(o)
        o.matrix_world = Matrix(p["matrix"])
        objs[name] = o
        tris += 2 * len(p["quads"])
    vl = sc.view_layers[0]
    vl.update()                                   # ⚠ 부모 지정 전에(낡은 matrix_world 로 뒤섞인 사고 — mech_voxel 주석)
    for name, o in objs.items():
        par = d["parts"][name]["parent"]
        if par and par in objs:
            mw = o.matrix_world.copy()
            o.parent = objs[par]
            o.matrix_parent_inverse = objs[par].matrix_world.inverted()
            o.matrix_world = mw
    vl.update()
    if switch:
        bpy.context.window.scene = sc
        for area in bpy.context.window.screen.areas:
            if area.type == "VIEW_3D":
                sh = area.spaces.active.shading
                try:
                    sh.type = "MATERIAL"          # Material Preview(발광 보임) — 렌더 엔진이 Workbench 면 없음
                except TypeError:
                    sh.type = "SOLID"; sh.color_type = "TEXTURE"
    zs = [(o.matrix_world @ v.co).z for o in objs.values() for v in o.data.vertices]
    return {"parts": len(objs), "tris": tris, "z_min": round(min(zs), 3), "z_max": round(max(zs), 3)}


def export_glb(folder, path=None, scheme="A"):
    """로블록스용 GLB (프로토 mech_voxel.export_glb 와 같은 방식).
      - 오브젝트 이름 = 파트 이름(Pelvis, Torso …), 메시 데이터 이름 = "X_<파트>" (로블록스 임포터가 만드는 X_*Motor6D 이름의 출처)
      - 메시는 월드 좌표로 구워 원점 0 — 로블록스 임포터가 오브젝트 원점(관절)을 버리기 때문. 관절은 _parts.json 으로 따로.
      - 재질 하나(HeavyPaletteMat, 팔레트 PNG 가 GLB 안에 들어감). 발광 마스크는 따로 올려야 함(HeavyPalette_EmitMask.png).
      - 같은 이름(Pelvis 등)이 이미 이 .blend 에 있으면(프로토 Mech_Export) 새 것이 'Pelvis.001' 이 되어 이름이 틀어진다
        → 내보내는 동안만 기존 것을 비켜 두고 끝나면 되돌린다(mech_voxel 과 같은 처리)."""
    import json as _json
    sc = bpy.data.scenes[SCENE]
    col = bpy.data.collections[COLL]
    if path is None:
        path = os.path.join(folder, "Heavy_r2_%s_20261026.glb" % scheme)
    set_scheme(folder, scheme)
    src = sorted([o for o in col.objects if o.type == "MESH" and o.name.startswith(PREFIX)], key=lambda o: o.name)
    names = [o.name[len(PREFIX):] for o in src]
    held = []
    for nm in names:
        for coll, n in ((bpy.data.objects, nm), (bpy.data.meshes, "X_" + nm)):
            ex = coll.get(n)
            if ex is not None:
                held.append((ex, n))
                ex.name = n + "__hv_hold"
    tmp = bpy.data.collections.new("_hv_export_tmp")
    sc.collection.children.link(tmp)
    vl = sc.view_layers[0]
    info = {"_units": "Blender 1 = 칸 20개(칸 0.05). 프로토는 가져온 뒤 Size = MeshSize x 2 로 키웠다(8절 메시 교체 절차).",
            "_axes": "Blender (x, y, z) -> glTF/로블록스 가져오기 (x, z, -y). 기체 정면 = Blender -Y = 가져온 뒤 +Z (로블록스 LookVector -Z 와 반대 → 템플릿에서 180도 돌림).",
            "_rest_pose": "팔만 벌림(미리보기 STANCE의 팔), 다리 곧게. 기울인 파트(스커트·견갑)는 회전이 메시에 구워져 있다.",
            "_emissive": "팔레트 칸 6 만 발광 — HeavyPalette_EmitMask.png (프로토 마스크는 6·7·9 라 쓰면 안 됨: 7 = 이 기체의 금속색)",
            "_scheme": scheme, "parts": {}}
    try:
        # 내보내기용 재질: 발광 없이 팔레트 색만. glTF 는 "마스크로 일부만 발광"을 못 담아서 팔레트 전체가
        # emissiveTexture 로 들어갔다(02:56 실측) → 발광을 읽는 곳에선 기체 전체가 빛남. 발광은 로블록스에서 마스크로 따로.
        xm = bpy.data.materials.get(MAT + "_Export") or bpy.data.materials.new(MAT + "_Export")
        xm.use_nodes = True
        nt = xm.node_tree; nt.nodes.clear()
        xo = nt.nodes.new("ShaderNodeOutputMaterial"); xb = nt.nodes.new("ShaderNodeBsdfPrincipled")
        xt = nt.nodes.new("ShaderNodeTexImage"); xt.interpolation = "Closest"
        xt.image = bpy.data.materials[MAT].node_tree.nodes["Palette"].image
        nt.links.new(xt.outputs["Color"], xb.inputs["Base Color"])
        xb.inputs["Roughness"].default_value = 0.55
        xb.inputs["Metallic"].default_value = 0.1
        nt.links.new(xb.outputs[0], xo.inputs[0])
        exp = []
        for o, nm in zip(src, names):
            me = o.data.copy()
            me.name = "X_" + nm
            me.transform(o.matrix_world)
            me.materials.clear()
            me.materials.append(xm)
            me.update()
            e = bpy.data.objects.new(nm, me)
            tmp.objects.link(e)
            exp.append(e)
            mw = o.matrix_world
            P = [mw @ v.co for v in o.data.vertices]
            piv = mw.translation
            info["parts"][nm] = {
                "parent": (o.parent.name[len(PREFIX):] if o.parent else None),
                "pivot_blender": [round(c, 5) for c in piv],
                "pivot_import": [round(piv.x, 5), round(piv.z, 5), round(-piv.y, 5)],
                "rest_rot_blender": [[round(mw[i][j], 6) for j in range(3)] for i in range(3)],
                "bbmin_blender": [round(min(p[i] for p in P), 4) for i in range(3)],
                "bbmax_blender": [round(max(p[i] for p in P), 4) for i in range(3)],
                "tris": 2 * len(o.data.polygons),
            }
        vl.update()
        for ob in vl.objects:
            ob.select_set(False)
        for ob in exp:
            ob.select_set(True)
        with bpy.context.temp_override(scene=sc, view_layer=vl):
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                      export_materials="EXPORT", export_cameras=False, export_lights=False,
                                      export_animations=False)
        with open(os.path.splitext(path)[0] + "_parts.json", "w", encoding="utf-8") as f:
            _json.dump(info, f, ensure_ascii=False, indent=1)
    finally:
        for o in list(tmp.objects):
            me = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.meshes.remove(me)
        bpy.data.collections.remove(tmp)
        for ex, n in held:
            ex.name = n
    return {"path": path, "parts": len(names), "tris": sum(p["tris"] for p in info["parts"].values()),
            "held_names": len(held)}
