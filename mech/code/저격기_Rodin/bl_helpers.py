# bl_seamsimp.py — Blender: 색 경계선(심) 단순화. 고해상 메시에서 경계 사슬을 더글러스-포이커로 줄이고
# 빠지는 점은 이웃 유지점으로 용접(weld_verts) → 양쪽 면이 같이 바뀌므로 갈라짐 없음. 2026-10-28
import bpy, bmesh, base64, os, math
from collections import defaultdict
from mathutils.geometry import intersect_point_line

def _dp(pts, eps, maxlen):
    keep = [False] * len(pts); keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1: continue
        a, b = pts[i], pts[j]; best, bi = -1.0, -1
        for k in range(i + 1, j):
            p, t = intersect_point_line(pts[k], a, b)
            t = min(1.0, max(0.0, t)); d = (pts[k] - a.lerp(b, t)).length
            if d > best: best, bi = d, k
        if best > eps or (b - a).length > maxlen:
            if bi < 0: bi = (i + j) // 2
            keep[bi] = True; stack += [(i, bi), (bi, j)]
    return keep

def simplify_seams(me, eps=0.0006, maxlen=0.010):
    bm = bmesh.new(); bm.from_mesh(me); zl = bm.faces.layers.int["zone"]
    seam = [e for e in bm.edges if len(e.link_faces) >= 2 and len({f[zl] for f in e.link_faces}) > 1]
    adj = defaultdict(list)
    for e in seam:
        a, b = e.verts; adj[a].append(b); adj[b].append(a)
    fixed = {v for v in adj if len(adj[v]) != 2 or v.is_boundary or not v.is_manifold}
    seen = set(); chains = []
    def walk(v0, nb):
        chain = [v0]; prev, cur = v0, nb
        while True:
            seen.add(frozenset((prev, cur))); chain.append(cur)
            if cur in fixed or cur is v0: break
            nx = [w for w in adj[cur] if w is not prev]
            if not nx: break
            prev, cur = cur, nx[0]
        return chain
    for v0 in list(fixed):
        for nb in adj[v0]:
            if frozenset((v0, nb)) not in seen: chains.append(walk(v0, nb))
    for v in list(adj):                                   # 고정점 없는 닫힌 고리
        for nb in adj[v]:
            if frozenset((v, nb)) not in seen:
                fixed.add(v); chains.append(walk(v, nb))
    tmap = {}
    for ch in chains:
        if len(ch) < 3: continue
        closed = ch[0] is ch[-1]
        pts = [v.co.copy() for v in ch]
        if closed and len(ch) > 4:                        # 닫힌 고리는 가장 먼 점에서 반으로
            far = max(range(len(ch)), key=lambda k: (pts[k] - pts[0]).length)
            keep = _dp(pts[:far + 1], eps, maxlen)[:-1] + _dp(pts[far:], eps, maxlen)
        else:
            keep = _dp(pts, eps, maxlen)
        idx = [k for k, f in enumerate(keep) if f]
        for a_, b_ in zip(idx[:-1], idx[1:]):
            mid = (a_ + b_) / 2
            for k in range(a_ + 1, b_):
                v = ch[k]
                if v in fixed or v in tmap: continue
                tmap[v] = ch[a_] if k <= mid else ch[b_]
    nseam0 = len(adj)
    bmesh.ops.weld_verts(bm, targetmap=tmap)
    seam2 = [e for e in bm.edges if len(e.link_faces) >= 2 and len({f[zl] for f in e.link_faces}) > 1]
    nseam1 = len({v for e in seam2 for v in e.verts})
    bm.to_mesh(me); bm.free()
    return {"seam_v0": nseam0, "seam_v1": nseam1, "welded": len(tmap)}


def s2_shot(name, target, az, el, oscale, w, h, cols, color_type="TEXTURE"):
    sc = bpy.data.scenes.get("_SnDiag") or bpy.data.scenes.new("_SnDiag")
    for c in list(sc.collection.children): sc.collection.children.unlink(c)
    for o in list(sc.collection.objects): sc.collection.objects.unlink(o)
    for c in cols: sc.collection.children.link(c)
    cd = bpy.data.cameras.get("_SnDiagCam") or bpy.data.cameras.new("_SnDiagCam")
    cd.type = "ORTHO"; cd.ortho_scale = oscale; cd.clip_end = 100
    cam = bpy.data.objects.get("_SnDiagCam") or bpy.data.objects.new("_SnDiagCam", cd)
    sc.collection.objects.link(cam)
    a, e, d = math.radians(az), math.radians(el), 10.0
    cam.location = (target[0] + d * math.sin(a) * math.cos(e), target[1] - d * math.cos(a) * math.cos(e), target[2] + d * math.sin(e))
    cam.rotation_euler = (math.radians(90 - el), 0, a)
    sc.camera = cam
    wd = bpy.data.worlds.get("_SnDiagWorld") or bpy.data.worlds.new("_SnDiagWorld"); wd.color = (0.012, 0.012, 0.016); sc.world = wd
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = color_type
    sc.display.shading.show_cavity = False
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x = w; sc.render.resolution_y = h; sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "JPEG"; sc.render.image_settings.quality = 85
    sc.render.filepath = os.path.join(r"C:\tmp", name + ".jpg")
    bpy.ops.render.render(write_still=True, scene=sc.name)
    return base64.b64encode(open(sc.render.filepath, "rb").read()).decode()

# ── 범용 감면 빌드: 고해상(src 접두) → 심 단순화 → 심 잠금 감면 → 팔레트 UV → 게임 파트(dst 접두) ──
import numpy as np, math
UVZ = {0: (0.125, 0.875), 1: (0.375, 0.875), 2: (0.625, 0.875)}
def build_dec(budget, src="S3F_", dst="S3R_", coll="Sniper3_Roblox", piv=None, dx=-26.0, eps=0.0015, maxlen=0.015, scale=1.0, only=None):
    import bmesh
    vis = bpy.data.collections.get(coll) or bpy.data.collections.new(coll)
    if vis.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(vis)
    mat = bpy.data.materials["S2R_Palette"]
    tmps = {}; st = {}
    for k, b in budget.items():
        if only and k not in only: continue
        me = bpy.data.objects[src + k].data.copy(); me.name = "_Dec_" + k
        st[k] = simplify_seams(me, eps=eps, maxlen=maxlen) if eps > 0 else {}
        me.validate(verbose=False)
        bm = bmesh.new(); bm.from_mesh(me); zl = bm.faces.layers.int["zone"]
        seamv = set()
        for e in bm.edges:
            if len(e.link_faces) >= 2 and len({f[zl] for f in e.link_faces}) > 1: seamv.update(v.index for v in e.verts)
        bm.free()
        ob = bpy.data.objects.new("_DecTmp_" + k, me); vis.objects.link(ob)
        vg = ob.vertex_groups.new(name="free"); vg.add(sorted(set(range(len(me.vertices))) - seamv), 1.0, "REPLACE")
        m = ob.modifiers.new("dec", "DECIMATE"); m.decimate_type = "COLLAPSE"; m.use_collapse_triangulate = True
        m.vertex_group = "free"; m.vertex_group_factor = 1.0; m.ratio = min(1.0, b * scale / len(me.polygons))
        tmps[k] = (ob, me)
    dg = bpy.context.evaluated_depsgraph_get()
    for k, (ob, me) in tmps.items():
        new = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        bpy.data.objects.remove(ob); bpy.data.meshes.remove(me)
        nf = len(new.polygons)
        zone = np.zeros(nf, np.int32); new.attributes["zone"].data.foreach_get("value", zone)
        lt = np.empty(nf, np.int64); new.polygons.foreach_get("loop_total", lt)
        uvl = new.uv_layers.new(name="Palette")
        uv = np.array([UVZ[z] for z in range(3)])[np.repeat(zone, lt)]
        uvl.data.foreach_set("uv", uv.astype(np.float32).ravel())
        new.materials.clear(); new.materials.append(mat)
        new.polygons.foreach_set("use_smooth", np.ones(nf, bool))
        new.set_sharp_from_angle(angle=math.radians(40))
        new.validate(verbose=False)
        tgt = bpy.data.objects.get(dst + k)
        if tgt is None:
            tgt = bpy.data.objects.new(dst + k, new); vis.objects.link(tgt)
            p = piv[k]; tgt.location = (p[0] + dx, p[1], p[2])
        else:
            old = tgt.data; tgt.data = new
            if old.users == 0 and not old.use_fake_user: bpy.data.meshes.remove(old)
        new.name = dst + k
        st[k]["tris"] = nf
    return {"parts": st, "total": sum(v["tris"] for v in st.values())}

bpy.app.driver_namespace["s2_seamsimp"] = simplify_seams
bpy.app.driver_namespace["s2_shot"] = s2_shot
bpy.app.driver_namespace["build_dec"] = build_dec
result = {"ok": True}
