"""heavy_export_bg.py — 화면 없는 Blender 로 실행: 빈 파일에서 중장갑 조립 → GLB + _parts.json → heavy_r2.blend 저장 (2026-10-26)
  D:\\blender.exe -b --factory-startup --python heavy_export_bg.py
  결과·오류는 같은 폴더 export_log.json 에 쓴다(창 Blender 는 안 건드림 — 02:51 크래시 뒤 바꾼 방식)."""
import bpy, os, json, traceback
F = os.path.dirname(os.path.abspath(__file__))
log = {"ok": False}
try:
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.context.scene.name = "Heavy_r2"
    src = open(os.path.join(F, "heavy_blender.py"), encoding="utf-8").read()
    assert "def export_glb" in src and len(src.encode("utf-8")) > 9000, "stale heavy_blender.py"
    ns = {}
    exec(compile(src, "heavy_blender.py", "exec"), ns)
    log["build"] = ns["build"](F, switch=False)
    log["export"] = ns["export_glb"](F)
    log["glb_size"] = os.path.getsize(log["export"]["path"])
    blend = os.path.join(F, "heavy_r2.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    log["blend"] = blend
    log["blend_size"] = os.path.getsize(blend)
    log["objects"] = sorted(o.name for o in bpy.data.objects)
    log["ok"] = True
except Exception:
    log["error"] = traceback.format_exc()
with open(os.path.join(F, "export_log.json"), "w", encoding="utf-8") as f:
    json.dump(log, f, ensure_ascii=False, indent=1)
