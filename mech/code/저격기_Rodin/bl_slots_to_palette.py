# bl_slots_to_palette.py — 손 도색(재질 슬롯 S3_White/S3_Dark/S3_Green) → zone 속성 + 팔레트 UV + 단일 재질 S3R_Palette. 내보내기 직전 실행. 2026-10-28
# 주의: 사용자가 S3R 에 손 도색을 시작한 뒤에는 build_dec 로 S3R 을 다시 만들면 손 도색이 지워진다.
import bpy, numpy as np
UVZ = {0: (0.125, 0.875), 1: (0.375, 0.875), 2: (0.625, 0.875)}
def slots_to_palette(coll="Sniper3_Roblox", mat_name="S3R_Palette"):
    pm = bpy.data.materials[mat_name]; rep = {}
    for o in bpy.data.collections[coll].objects:
        me = o.data; nf = len(me.polygons)
        mi = np.zeros(nf, np.int32); me.polygons.foreach_get("material_index", mi)
        names = [m.name if m else "" for m in me.materials]
        zmap = {i: {"S3_White": 0, "S3_Dark": 1, "S3_Green": 2}.get(n, 0) for i, n in enumerate(names)}
        zone = np.array([zmap[i] for i in mi], np.int32)
        old = np.zeros(nf, np.int32); me.attributes["zone"].data.foreach_get("value", old)
        me.attributes["zone"].data.foreach_set("value", zone)
        lt = np.zeros(nf, np.int64); me.polygons.foreach_get("loop_total", lt)
        uv = np.array([UVZ[z] for z in range(3)])[np.repeat(zone, lt)]
        me.uv_layers["Palette"].data.foreach_set("uv", uv.astype(np.float32).ravel())
        me.materials.clear(); me.materials.append(pm)
        me.polygons.foreach_set("material_index", np.zeros(nf, np.int32)); me.update()
        rep[o.name] = int((zone != old).sum())
    return rep
bpy.app.driver_namespace["s3_slots_to_palette"] = slots_to_palette
