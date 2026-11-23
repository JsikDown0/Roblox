"""aello_template_data.py — AELLO(LF-01) 템플릿 조립용 수치(템플릿 좌표) — 10-26 22:52~
템플릿 좌표 = Blender 칸 × 0.1, 축 (−x, z, y) (가져오기가 x·z 를 뒤집어 정면이 −Z — 실측: SkirtFL 이 Pelvis 보다 −X·−Z).
파트 자리는 쉬는 자세(팔만 STANCE)로 구운 그대로. 팔 관절의 회전(R_up·R_low)은 템플릿 축으로 옮긴 STANCE."""
import json, sys
import numpy as np
sys.path.insert(0, "/home/claude/flag")
import aero_export as E, aero_rifle as R, aero_launcher as GL

M = E.build()
P = E.REST_POSE
Mm = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)   # Blender → 템플릿 축

def T(p):            # Blender 칸 점 → 템플릿 좌표
    return (Mm @ np.asarray(p, float) * 0.1).round(5).tolist()

def W(name, p):      # 파트 로컬(쉬기 전 칸) 점 → 자세 월드 칸
    w = M.world(name, P)
    return w[:3, :3] @ np.asarray(p, float) + w[:3, 3]

def Rt(name):        # 파트의 자세 회전 → 템플릿 축
    return (Mm @ M.world(name, P)[:3, :3] @ Mm.T)

parts = json.load(open("/tmp/claude-0/-home-claude/c92e462d-993f-5ffc-afd9-9f2faa6b6c90/scratchpad/aero_out_b/Aero_r2b_C1_20261026_parts.json"))["parts"]
out = {"center_imp": {}, "pivot": {}}
for n, d in parts.items():
    c = (np.array(d["bbmin_blender"]) + np.array(d["bbmax_blender"])) / 2      # Blender 단위
    out["center_imp"][n] = (Mm @ c).round(5).tolist()                          # 가져오기 축(배율 1)
    out["pivot"][n] = (Mm @ np.array(d["pivot_blender"]) * 2).round(5).tolist()  # 템플릿 좌표(×2)
for side, s in (("L", 1), ("R", -1)):
    out["R_up" + side] = Rt("UpperArm" + side).round(6).tolist()
    out["R_low" + side] = Rt("LowerArm" + side).round(6).tolist()
fx, fy, fz = R.FIST_R
out["fistR"] = T(W("LowerArmR", (fx, fy, fz)))
out["fistL"] = T(W("LowerArmL", (-fx, fy, fz)))
# 라이플 관절 축(쉬는 자세 로컬: 위 = 앞(-Y), 뒤 = 위(+Z)) → 자세 → 템플릿
Rr = M.world("LowerArmR", P)[:3, :3]
out["gripY"] = (Mm @ Rr @ np.array([0, -1, 0.])).round(6).tolist()   # 라이플 위
out["gripZ"] = (Mm @ Rr @ np.array([0, 0, 1.])).round(6).tolist()    # 라이플 뒤(총구 반대)
sa, sb, sc = R.SCALE
def rifle_pt(a, b, c=0):   # 설계 좌표 → 쉬는 자세 로컬 칸 (attach 의 역)
    return (fx + c * sc, fy - (b + 12) * sb, fz - (a + 2) * sa)
out["foregrip"] = T(W("LowerArmR", rifle_pt(46, -9)))
out["muzzle"] = T(W("LowerArmR", rifle_pt(85.5, 3.5)))
out["muzzle2"] = T(W("LowerArmR", rifle_pt(79.5, -2.5)))
# 백팩 노즐(바인더, 뒤를 봄): 바깥 끝 y 48
out["nozzles"] = {"NozzleUL": T((22, 48.5, 247)), "NozzleDL": T((22, 48.5, 238)), "NozzleUR": T((-22, 48.5, 247)), "NozzleDR": T((-22, 48.5, 238))}
out["boostLight"] = T((0, 50, 242))
# 다리 보조 부스터 노즐(아래를 봄): BoostL 로컬 (36, 6, 46.5)
out["legNozzles"] = {"BoostNozzleL": T(W("BoostL", (36, 6, 46.5))), "BoostNozzleR": T(W("BoostR", (-36, 6, 46.5)))}
# 런처 총구(왼손목, 덮개 열림 방향 = 팔꿈치 쪽 10칸): 발사관 끝 z = MOUTH
tx0 = GL.TUBES
out["tubes"] = [T(W("LowerArmL", (tx, ty, GL.MOUTH))) for tx, ty in GL.TUBES]
out["coverSlide"] = (Mm @ M.world("LowerArmL", P)[:3, :3] @ np.array([0, 0, GL.SLIDE]) * 0.1).round(5).tolist()
# 키·발바닥
out["rootHeight"] = round(172 * 0.1 + 0.05, 4)
json.dump(out, open(sys.argv[1], "w"), indent=0)
for k in ("fistR", "fistL", "gripY", "gripZ", "foregrip", "muzzle", "legNozzles", "tubes", "coverSlide", "rootHeight"):
    print(k, out[k])
print("pivot Pelvis", out["pivot"]["Pelvis"], "Torso", out["pivot"]["Torso"], "UpperArmL", out["pivot"]["UpperArmL"], "LowerArmL", out["pivot"]["LowerArmL"])
print("R_upL", np.round(np.array(out["R_upL"]), 3).tolist(), "R_lowL", np.round(np.array(out["R_lowL"]), 3).tolist())
