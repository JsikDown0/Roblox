"""White voxel puppy generator (headless Blender / bpy).

Usage:  python white_puppy.py <out_dir> [--render]
Builds the puppy from a voxel grid, exports an FBX with one MeshPart per
animatable body part (pivots at joints) and a small palette texture.
"""
import os
import random
import sys

import bpy
from mathutils import Vector

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
RENDER = "--render" in sys.argv
VOXEL = 0.1  # meters per voxel
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- palette
PALETTE = {
    "white": (0.96, 0.96, 0.98),
    "shade": (0.88, 0.89, 0.94),
    "paw": (0.98, 0.80, 0.84),
    "pink": (0.98, 0.58, 0.70),
    "black": (0.10, 0.10, 0.14),
    "shine": (1.0, 1.0, 1.0),
    "collar": (0.25, 0.55, 1.0),
    "collar_dk": (0.15, 0.38, 0.85),
    "gold": (1.0, 0.80, 0.25),
}
VARIANTS = 3  # slight per-voxel brightness jitter
NAMES = list(PALETTE)

# ---------------------------------------------------------------- voxels
vox = {}  # (x, y, z) -> (part, color)   front is -Y, up is +Z


def box(part, x0, x1, y0, y1, z0, z1, color):
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                vox[(x, y, z)] = (part, color)


def put(part, x, y, z, color):
    vox[(x, y, z)] = (part, color)


def remove(x, y, z):
    vox.pop((x, y, z), None)


# legs
for name, (x0, y0) in {
    "LegFL": (-4, -3), "LegFR": (1, -3), "LegBL": (-4, 4), "LegBR": (1, 4),
}.items():
    box(name, x0, x0 + 2, y0, y0 + 2, 0, 3, "white")
    box(name, x0, x0 + 2, y0, y0 + 2, 0, 0, "paw")

# body
box("Body", -4, 3, -4, 7, 4, 9, "white")
box("Body", -3, 2, -5, -5, 5, 8, "white")          # chest fluff
box("Body", -3, 2, -2, 6, 4, 4, "shade")           # belly shade
for x in (-4, 3):
    for y in (-4, 7):
        remove(x, y, 9)                            # rounded corners
box("Body", -4, 3, -4, 1, 10, 10, "white")
box("Body", -5, 4, -6, 2, 10, 10, "collar")        # collar sticks out under head
box("Body", -5, 4, 2, 2, 10, 10, "collar_dk")
box("Body", -4, 3, 1, 1, 10, 10, "white")
box("Body", -1, 0, -7, -7, 9, 10, "gold")          # name tag
put("Body", -1, -7, 10, "collar_dk"); put("Body", 0, -7, 10, "collar_dk")

# tail (curled up)
for y, z in [(8, 8), (8, 9), (9, 10), (9, 11), (9, 12), (8, 13), (7, 13)]:
    box("Tail", -1, 0, y, y, z, z, "white")
put("Tail", -1, 7, 13, "shade"); put("Tail", 0, 7, 13, "shade")

# head
box("Head", -5, 4, -8, 0, 11, 20, "white")
for x in (-5, 4):                                  # bevel corners
    for z in (11, 20):
        for y in (-8, 0):
            remove(x, y, z)
    remove(x, -8, 19); remove(x, 0, 19)
box("Head", -5, 4, -8, 0, 11, 11, "shade")         # chin shade
box("Head", -2, 1, -9, -9, 12, 14, "white")        # snout
box("Head", -1, 0, -10, -10, 12, 14, "white")
box("Head", -1, 0, -10, -10, 14, 14, "black")      # nose
box("Head", -1, 0, -10, -10, 12, 12, "pink")       # tongue
for ex in (-4, 2):                                 # eyes
    box("Head", ex, ex + 1, -8, -8, 14, 16, "black")
put("Head", -4, -8, 16, "shine"); put("Head", 2, -8, 16, "shine")
box("Head", -5, -4, -8, -8, 13, 13, "pink")        # blush
box("Head", 3, 4, -8, -8, 13, 13, "pink")
box("Head", -1, 0, -6, -2, 21, 21, "white")        # hair tuft
put("Head", 0, -5, 22, "white")
# ears (pointy, samoyed style)
for side, xs in (("L", (-5, -2)), ("R", (1, 4))):
    x0, x1 = xs
    box("Head", x0, x1, -5, -3, 21, 21, "white")
    if side == "L":
        box("Head", x0, x1 - 1, -5, -3, 22, 22, "white")
        box("Head", x0, x0 + 1, -4, -3, 23, 23, "white")
        box("Head", x0 + 1, x1 - 1, -5, -5, 21, 21, "pink")
        put("Head", x0 + 1, -5, 22, "pink")
    else:
        box("Head", x0 + 1, x1, -5, -3, 22, 22, "white")
        box("Head", x1 - 1, x1, -4, -3, 23, 23, "white")
        box("Head", x0 + 1, x1 - 1, -5, -5, 21, 21, "pink")
        put("Head", x1 - 1, -5, 22, "pink")

# ears get one more row of height
for (x, y, z), (p, c) in list(vox.items()):
    if p == "Head" and z == 23:
        put("Head", x, y, 24, c)
remove(-5, -3, 24); remove(4, -3, 24)

# pivots (voxel coords, joints for code animation)
PIVOTS = {
    "Body": (-0.5, 1.5, 4.0),
    "Head": (-0.5, -3.0, 11.0),
    "Tail": (-0.5, 8.0, 8.0),
    "LegFL": (-2.5, -1.5, 4.0), "LegFR": (2.5 - 0.0, -1.5, 4.0),
    "LegBL": (-2.5, 5.5, 4.0), "LegBR": (2.5, 5.5, 4.0),
}
PIVOTS["LegFR"] = (2.5, -1.5, 4.0)
PIVOTS["LegFL"] = (-2.5, -1.5, 4.0)

# ---------------------------------------------------------------- texture
TEX_W, TEX_H = len(NAMES) * VARIANTS * 4, 4
img = bpy.data.images.new("WhitePuppy_Palette", TEX_W, TEX_H, alpha=False)
px = [0.0] * (TEX_W * TEX_H * 4)
for ci, n in enumerate(NAMES):
    for v in range(VARIANTS):
        mul = (1.0, 0.985, 0.97)[v]
        col = [min(1.0, c * mul) for c in PALETTE[n]]
        for dx in range(4):
            for y in range(TEX_H):
                i = ((y * TEX_W) + (ci * VARIANTS + v) * 4 + dx) * 4
                px[i:i + 4] = [col[0] ** 2.2, col[1] ** 2.2, col[2] ** 2.2, 1.0]
img.pixels = px
img.filepath_raw = os.path.join(OUT, "WhitePuppy_Palette.png")
img.file_format = "PNG"
img.save()


def uv_for(color, variant):
    cell = NAMES.index(color) * VARIANTS + variant
    return ((cell * 4 + 2) / TEX_W, 0.5)


# ---------------------------------------------------------------- mesh
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

mat = bpy.data.materials.new("WhitePuppy")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.85
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
tex.interpolation = "Closest"
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

FACES = [
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]
rng = random.Random(7)
objects = []
for part in PIVOTS:
    cells = {k: c for k, (p, c) in vox.items() if p == part}
    piv = Vector(PIVOTS[part])
    verts, faces, uvs, vindex = [], [], [], {}
    for (x, y, z), color in cells.items():
        variant = rng.randrange(VARIANTS) if color in ("white", "shade") else 0
        uv = uv_for(color, variant)
        for n, quad in FACES:
            if (x + n[0], y + n[1], z + n[2]) in cells:
                continue
            idx = []
            for q in quad:
                key = (x + q[0], y + q[1], z + q[2])
                if key not in vindex:
                    vindex[key] = len(verts)
                    verts.append(((Vector(key) - piv) * VOXEL))
                idx.append(vindex[key])
            faces.append(idx)
            uvs.append(uv)
    me = bpy.data.meshes.new(part)
    me.from_pydata(verts, [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly, uv in zip(me.polygons, uvs):
        for li in poly.loop_indices:
            uvl.data[li].uv = uv
    me.materials.append(mat)
    me.validate()
    ob = bpy.data.objects.new(part, me)
    ob.location = piv * VOXEL
    bpy.context.scene.collection.objects.link(ob)
    objects.append(ob)

# ---------------------------------------------------------------- export
bpy.ops.object.select_all(action="DESELECT")
for ob in objects:
    ob.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "WhitePuppy.fbx"),
    use_selection=True, object_types={"MESH"},
    apply_scale_options="FBX_SCALE_ALL", path_mode="COPY", embed_textures=False,
)
print("voxels:", len(vox), "tris:", sum(len(o.data.polygons) * 2 for o in objects))

# ---------------------------------------------------------------- preview
if RENDER:
    import math
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = 48
    scn.cycles.use_denoising = True
    scn.render.resolution_x = scn.render.resolution_y = 1024
    scn.render.film_transparent = False
    scn.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W"); scn.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.035, 0.16, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
    floor = bpy.context.object
    fm = bpy.data.materials.new("floor"); fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.06, 0.25, 1)
    floor.data.materials.append(fm)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5; sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scn.collection.objects.link(sun)
    for name, rot in (("34", -35), ("front", 0), ("side", -90)):
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        cam.data.type = "ORTHO"; cam.data.ortho_scale = 3.4
        r = math.radians(rot)
        target = Vector((0, 0.0, 1.2))
        cam.location = target + Vector((math.sin(r) * -10 * -1, -math.cos(r) * 10, 6))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.collection.objects.link(cam); scn.camera = cam
        scn.render.filepath = os.path.join(OUT, f"preview_{name}.png")
        bpy.ops.render.render(write_still=True)
