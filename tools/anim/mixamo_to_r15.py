"""Mixamo FBX -> Roblox R15 KeyframeSequence (Luau builder script) + preview render.

Usage: python mixamo_to_r15.py <anim.fbx> <R15.obj> <out_dir> [name] [--render]
- Retargets by world-space bone deltas with a rest-pose alignment per limb
  (Mixamo T-pose arms -> R15 arms-down rest), assumes default R15 Motor6D C0/C1
  with identity rotation (Rig Builder R15 dummy).
- Output <name>.lua: run in Studio Command Bar -> creates
  ServerStorage.RBX_ANIMSAVES.Rig.<name> (KeyframeSequence).
"""
import os, sys, math
import bpy
import numpy as np
from mathutils import Matrix, Vector, Quaternion

FBX, OBJ, OUT = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])
NAME = sys.argv[4] if len(sys.argv) > 4 and not sys.argv[4].startswith("--") else os.path.splitext(os.path.basename(FBX))[0]
RENDER = "--render" in sys.argv
os.makedirs(OUT, exist_ok=True)

# Blender (x, y, z) Z-up, character faces -Y  ->  Roblox (x, y, z) Y-up, faces -Z
P = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
PT = P.transposed()

# R15 part -> (mixamo bone, parent part, motor name, limb segment for rest alignment)
MAP = {
    "LowerTorso":    ("Hips",         None,           "Root",          None),
    "UpperTorso":    ("Spine2",       "LowerTorso",   "Waist",         None),
    "Head":          ("Head",         "UpperTorso",   "Neck",          None),
    "LeftUpperArm":  ("LeftArm",      "UpperTorso",   "LeftShoulder",  ("LeftArm", "LeftForeArm")),
    "LeftLowerArm":  ("LeftForeArm",  "LeftUpperArm", "LeftElbow",     ("LeftForeArm", "LeftHand")),
    "LeftHand":      ("LeftHand",     "LeftLowerArm", "LeftWrist",     ("LeftForeArm", "LeftHand")),
    "RightUpperArm": ("RightArm",     "UpperTorso",   "RightShoulder", ("RightArm", "RightForeArm")),
    "RightLowerArm": ("RightForeArm", "RightUpperArm","RightElbow",    ("RightForeArm", "RightHand")),
    "RightHand":     ("RightHand",    "RightLowerArm","RightWrist",    ("RightForeArm", "RightHand")),
    "LeftUpperLeg":  ("LeftUpLeg",    "LowerTorso",   "LeftHip",       ("LeftUpLeg", "LeftLeg")),
    "LeftLowerLeg":  ("LeftLeg",      "LeftUpperLeg", "LeftKnee",      ("LeftLeg", "LeftFoot")),
    "LeftFoot":      ("LeftFoot",     "LeftLowerLeg", "LeftAnkle",     ("LeftLeg", "LeftFoot")),
    "RightUpperLeg": ("RightUpLeg",   "LowerTorso",   "RightHip",      ("RightUpLeg", "RightLeg")),
    "RightLowerLeg": ("RightLeg",     "RightUpperLeg","RightKnee",     ("RightLeg", "RightFoot")),
    "RightFoot":     ("RightFoot",    "RightLowerLeg","RightAnkle",    ("RightLeg", "RightFoot")),
}
ORDER = list(MAP)

# ---------------------------------------------------------------- R15 OBJ
V, groups, cur = [], {}, None
for line in open(OBJ):
    t = line.split()
    if not t:
        continue
    if t[0] == "v":
        V.append(tuple(map(float, t[1:4])))
    elif t[0] == "g":
        cur = t[1]; groups.setdefault(cur, [])
    elif t[0] == "f":
        groups[cur].append([int(x.split("/")[0]) - 1 for x in t[1:]])
V = np.array(V)
info = {}
for g, faces in groups.items():
    ids = sorted({i for f in faces for i in f})
    lo, hi = V[ids].min(0), V[ids].max(0)
    info[g] = dict(lo=lo, hi=hi, c=(lo + hi) / 2, size=hi - lo, faces=faces)
cx = np.mean([i["c"][0] for i in info.values()])
by_y = sorted(info, key=lambda g: info[g]["c"][1])
# torso column = widest three around the centre line
center = sorted([g for g in info if abs(info[g]["c"][0] - cx) < 0.3], key=lambda g: info[g]["c"][1])
side = [g for g in info if g not in center]
names = {center[0]: "LowerTorso", center[1]: "UpperTorso", center[2]: "Head"}
for sgn, lr in ((1, "Right"), (-1, "Left")):            # facing -Z: character right = +X
    s = [g for g in side if (info[g]["c"][0] - cx) * sgn > 0]
    near = min(abs(info[g]["c"][0] - cx) for g in s)          # legs sit closer to the centre line than arms
    legs = sorted([g for g in s if abs(info[g]["c"][0] - cx) < near + 0.3], key=lambda g: info[g]["c"][1])
    arms = sorted([g for g in s if g not in legs], key=lambda g: info[g]["c"][1])
    for g, n in zip(legs, ("Foot", "LowerLeg", "UpperLeg")): names[g] = lr + n
    for g, n in zip(arms, ("Hand", "LowerArm", "UpperArm")): names[g] = lr + n
assert len(names) == 15, names
part = {names[g]: info[g] for g in info}
ground = min(p["lo"][1] for p in part.values())

def top(n): return part[n]["hi"][1]
def bot(n): return part[n]["lo"][1]
def cxz(n): return part[n]["c"][0], part[n]["c"][2]
# approximate joint pivots (only used for the preview render)
J = {"LowerTorso": Vector(part["LowerTorso"]["c"])}
J["UpperTorso"] = Vector((cx, (top("LowerTorso") + bot("UpperTorso")) / 2, part["UpperTorso"]["c"][2]))
J["Head"] = Vector((cx, top("UpperTorso"), part["Head"]["c"][2]))
for lr in ("Left", "Right"):
    x, z = cxz(lr + "UpperArm"); J[lr + "UpperArm"] = Vector((x, top(lr + "UpperArm") - 0.2, z))
    x, z = cxz(lr + "LowerArm"); J[lr + "LowerArm"] = Vector((x, (bot(lr + "UpperArm") + top(lr + "LowerArm")) / 2, z))
    x, z = cxz(lr + "Hand");     J[lr + "Hand"] = Vector((x, (bot(lr + "LowerArm") + top(lr + "Hand")) / 2, z))
    x, z = cxz(lr + "UpperLeg"); J[lr + "UpperLeg"] = Vector((x, top(lr + "UpperLeg") - 0.1, z))
    x, z = cxz(lr + "LowerLeg"); J[lr + "LowerLeg"] = Vector((x, (bot(lr + "UpperLeg") + top(lr + "LowerLeg")) / 2, z))
    x, z = cxz(lr + "Foot");     J[lr + "Foot"] = Vector((x, (bot(lr + "LowerLeg") + top(lr + "Foot")) / 2, part[lr + "LowerLeg"]["c"][2]))
R15_DIR = {"Arm": Vector((0, -1, 0)), "Leg": Vector((0, -1, 0))}
hip_h = J["LowerTorso"].y - ground

# ---------------------------------------------------------------- Mixamo
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
pref = "mixamorig:" if "mixamorig:Hips" in arm.data.bones else ""
B = lambda n: pref + n
f0, f1 = map(int, arm.animation_data.action.frame_range)
fps = bpy.context.scene.render.fps
MW = arm.matrix_world

def rest_world(bn):
    return MW @ arm.data.bones[B(bn)].matrix_local
rest_rot = {n: rest_world(MAP[n][0]).to_3x3().normalized() for n in ORDER}
hips_rest = (MW @ arm.data.bones[B("Hips")].head_local)
mix_hip_h = hips_rest.z - min((MW @ b.head_local).z for b in arm.data.bones)
scale = hip_h / mix_hip_h

def seg_dir_rest(a, b):
    d = (MW @ arm.data.bones[B(b)].head_local) - (MW @ arm.data.bones[B(a)].head_local)
    return (P @ d).normalized()
ALIGN = {}
for n in ORDER:
    seg = MAP[n][3]
    if seg is None:
        ALIGN[n] = Matrix.Identity(3)
    else:
        target = seg_dir_rest(*seg)
        src = R15_DIR["Arm" if "Arm" in n or "Hand" in n else "Leg"]
        ALIGN[n] = src.rotation_difference(target).to_matrix()
# feet: keep R15 flat foot = mixamo rest foot (no extra alignment beyond the shin)
for lr in ("Left", "Right"):
    ALIGN[lr + "Foot"] = ALIGN[lr + "LowerLeg"]

frames = []
for f in range(f0, f1 + 1):
    bpy.context.scene.frame_set(f)
    Rw = {}
    for n in ORDER:
        pb = arm.pose.bones[B(MAP[n][0])]
        anim = (MW @ pb.matrix).to_3x3().normalized()
        D = anim @ rest_rot[n].inverted()
        Rw[n] = (P @ D @ PT) @ ALIGN[n]
    hips_now = MW @ arm.pose.bones[B("Hips")].head
    dpos = (P @ (hips_now - hips_rest)) * scale
    T = {}
    for n in ORDER:
        par = MAP[n][1]
        rel = Rw[n] if par is None else Rw[par].transposed() @ Rw[n]
        T[n] = (rel.to_quaternion().normalized(), dpos if par is None else Vector((0, 0, 0)))
    frames.append(((f - f0) / fps, T, Rw, dpos))

# ---------------------------------------------------------------- Luau
def cf(q, p):
    return "CFrame.new(%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f)" % (p.x, p.y, p.z, q.x, q.y, q.z, q.w)
CHILDREN = {}
for n in ORDER:
    CHILDREN.setdefault(MAP[n][1] or "HumanoidRootPart", []).append(n)
L = [f"-- {NAME}: Mixamo -> R15 KeyframeSequence ({len(frames)} frames, {fps} fps). Generated by tools/anim/mixamo_to_r15.py",
     "-- Paste into the Studio Command Bar. Creates ServerStorage.RBX_ANIMSAVES.Rig." + NAME,
     "local ss = game:GetService('ServerStorage')",
     "local saves = ss:FindFirstChild('RBX_ANIMSAVES') or Instance.new('Folder', ss); saves.Name = 'RBX_ANIMSAVES'",
     "local rig = saves:FindFirstChild('Rig') or Instance.new('ObjectValue', saves); rig.Name = 'Rig'",
     f"local old = rig:FindFirstChild('{NAME}'); if old then old:Destroy() end",
     "local ks = Instance.new('KeyframeSequence'); ks.Name = '" + NAME + "'; ks.Loop = false; ks.Priority = Enum.AnimationPriority.Action",
     "local CHILD = {"]
for k, v in CHILDREN.items():
    L.append(f"  {k} = {{{', '.join(repr(x) for x in v)}}},")
L += ["}", "local function pose(parent, name, cfs)",
      "  local p = Instance.new('Pose'); p.Name = name; p.Weight = 1; p.CFrame = cfs[name] or CFrame.identity",
      "  p.EasingStyle = Enum.PoseEasingStyle.Linear; p.Parent = parent",
      "  for _, c in ipairs(CHILD[name] or {}) do pose(p, c, cfs) end",
      "end", "local K = {"]
for t, T, _, _ in frames:
    L.append("  {%.4f, {%s}}," % (t, ", ".join(f"{n}={cf(*T[n])}" for n in ORDER)))
L += ["}", "for _, k in ipairs(K) do",
      "  local kf = Instance.new('Keyframe'); kf.Time = k[1]; kf.Parent = ks",
      "  pose(kf, 'HumanoidRootPart', k[2])", "end",
      "ks.Parent = rig", "print('[mixamo_to_r15] ' .. ks:GetFullName() .. ' · keyframes ' .. #K)"]
open(os.path.join(OUT, NAME + ".lua"), "w").write("\n".join(L) + "\n")
print("frames", len(frames), "scale", round(scale, 3), "lua", os.path.join(OUT, NAME + ".lua"))

# ---------------------------------------------------------------- preview
if RENDER:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    objs = {}
    for n in ORDER:
        g = [k for k, v in names.items() if v == n][0]
        faces = part[n]["faces"]; ids = sorted({i for f in faces for i in f}); remap = {i: k for k, i in enumerate(ids)}
        piv = J[n]
        verts = [tuple(P.transposed() @ (Vector(V[i]) - piv)) for i in ids]
        me = bpy.data.meshes.new(n); me.from_pydata(verts, [], [[remap[i] for i in f] for f in faces])
        ob = bpy.data.objects.new(n, me); scn.collection.objects.link(ob); objs[n] = ob
        mat = bpy.data.materials.new(n); mat.use_nodes = True
        col = (0.85, 0.45, 0.3, 1) if n.startswith("Left") else (0.3, 0.55, 0.9, 1) if n.startswith("Right") else (0.8, 0.8, 0.82, 1)
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = col
        me.materials.append(mat)
    scn.render.engine = "CYCLES"; scn.cycles.device = "CPU"; scn.cycles.samples = 16; scn.cycles.use_denoising = True
    scn.render.resolution_x = 360; scn.render.resolution_y = 480; scn.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); scn.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.62, 0.68, 1)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); cam.data.type = "ORTHO"; cam.data.ortho_scale = 6.5
    scn.collection.objects.link(cam); scn.camera = cam
    ctr = P.transposed() @ Vector((cx, ground + 2.6, part["UpperTorso"]["c"][2]))
    cam.location = ctr + Vector((-7, -9, 2)); cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    picks = sorted({0, len(frames) // 4, len(frames) // 2, 3 * len(frames) // 4, len(frames) - 1})
    from PIL import Image
    tiles = []
    for i in picks:
        _, T, Rw, dpos = frames[i]
        for n in ORDER:      # FK in roblox space using estimated pivots
            par = MAP[n][1]
            if par is None:
                pos = J[n] + dpos
            else:
                ppos = objs[par]["rb_pos"]; prot = Rw[par]
                pos = Vector(ppos) + prot @ (J[n] - J[par])
            objs[n]["rb_pos"] = list(pos)
            M4 = (PT @ Rw[n] @ P).to_4x4(); M4.translation = PT @ pos
            objs[n].matrix_world = M4
        fn = os.path.join(OUT, f"_f{i}.png"); scn.render.filepath = fn
        bpy.ops.render.render(write_still=True); tiles.append(Image.open(fn))
    W = sum(t.width for t in tiles); sheet = Image.new("RGB", (W, tiles[0].height))
    x = 0
    for t in tiles: sheet.paste(t, (x, 0)); x += t.width
    sheet.save(os.path.join(OUT, NAME + "_preview.png"))
    for i in picks: os.remove(os.path.join(OUT, f"_f{i}.png"))
    print("preview", os.path.join(OUT, NAME + "_preview.png"), "frames", picks)
