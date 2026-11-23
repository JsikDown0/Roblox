"""행성 젤리 메시 6개 — PlanetGummyArt 가 실행 중에 EditableMesh 로 만들던 것과 같은 꼭짓점 · UV (2026-10-30)

좌표는 '로블록스 좌표'로 적는다 (r = x, y, z · Y 위 · 앞 = -Z).
  Blender 꼭짓점 = (x, -z, y)  →  glTF 내보내기(+Y 위) = (x, y, z)  — 정회전이라 감김 방향이 그대로다
UV 도 로블록스 규약(v = 0 이 그림 위)으로 적고, Blender 에는 1 - v 로 넣는다 (glTF 내보내기가 다시 뒤집는다)
앞면 = 바깥 법선 쪽에서 볼 때 반시계 (glTF 규약). 삼각형마다 외적으로 맞춘다

메시 (단위 크기 — 로블록스에서 Size 를 다시 준다):
  PlanetHemiL / R        반구 (side -1 = x<0 · +1 = x>0) · 바깥면만 · 경도 40 칸 · 위도 36 칸
  PlanetHemiDoubleL / R  같은 반구 + 안쪽 면 (투명 껍질 — 뒤쪽 안면이 비쳐 보이게)
  PlanetDisc             단면 원판 (+X 를 본다 · 두께 0.01 · 48 칸 · 앞뒤 두 장)
  PlanetRingSaturn       토성 고리 반쪽 (+X 쪽 반원 · 띠 2개 · 틈은 비움 · 두께 0.01 · 위아래 두 장)
"""
import math, sys, json
import bpy

FRONT = 110
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "PlanetMeshes.glb"

def to_b(p):  # 로블록스 좌표 → Blender 좌표
    x, y, z = p
    return (x, -z, y)

def norm(v):
    l = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (v[0] / l, v[1] / l, v[2] / l)

def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

class Builder:
    """꼭짓점 하나 = (위치, 법선, uv) — 같은 위치라도 법선 · uv 가 다르면 따로 둔다"""
    def __init__(self):
        self.P, self.N, self.UV, self.F = [], [], [], []
    def v(self, p, n, uv):
        self.P.append(p); self.N.append(n); self.UV.append(uv)
        return len(self.P) - 1
    def tri(self, a, b, c, want):
        """want = 바깥(앞) 쪽 방향 — 반시계로 맞춘다. 넓이 0 이면 버린다"""
        pa, pb, pc = self.P[a], self.P[b], self.P[c]
        n = cross(sub(pb, pa), sub(pc, pa))
        if dot(n, n) < 1e-14:
            return False
        if dot(n, want) < 0:
            b, c = c, b
        self.F.append((a, b, c))
        return True

def hemi(side, double):
    B = Builder()
    NU, NV = 40, 36
    lon0 = FRONT if side < 0 else FRONT - 180
    layers = [1, -1] if double else [1]
    for s in layers:   # s = 1 바깥 · -1 안쪽 (법선 반대)
        vid = {}
        for j in range(NV + 1):
            la = math.radians(90 - j * 180 / NV)
            for i in range(NU + 1):
                lon = lon0 + i * 180 / NU
                d = math.radians(lon - FRONT)
                p = (-math.cos(la) * math.sin(d), math.sin(la), -math.cos(la) * math.cos(d))
                n = norm(p) if dot(p, p) > 0 else (0, 1, 0)
                n = (n[0] * s, n[1] * s, n[2] * s)
                vid[(j, i)] = B.v((p[0] * 0.5, p[1] * 0.5, p[2] * 0.5), n, ((lon - (FRONT - 180)) / 360, j / NV))
        for j in range(NV):
            for i in range(NU):
                a, b, c, dd = vid[(j, i)], vid[(j, i + 1)], vid[(j + 1, i)], vid[(j + 1, i + 1)]
                # 앞 방향 = 그 자리 법선 (네 꼭짓점 평균)
                w = [sum(B.N[k][q] for k in (a, b, c, dd)) for q in range(3)]
                B.tri(a, c, b, w)
                B.tri(b, c, dd, w)
    return B

def disc():
    B = Builder()
    N = 48
    for x in (0.005, -0.005):
        n = (1 if x > 0 else -1, 0, 0)
        c = B.v((x, 0, 0), n, (0.5, 0.5))
        ring = []
        for i in range(N):
            a = i / N * 2 * math.pi
            y, z = math.cos(a) * 0.5, math.sin(a) * 0.5
            ring.append(B.v((x, y, z), n, (0.5 + z, 0.5 - y)))
        for i in range(N):
            B.tri(c, ring[i], ring[(i + 1) % N], n)
    return B

RING_SATURN = [(1.09, 1.41), (1.47, 1.70)]
def ring(bands):
    B = Builder()
    NSEG = 36
    rin, rout = bands[0][0], bands[-1][1]
    for y in (0.005, -0.005):
        n = (0, 1 if y > 0 else -1, 0)
        for b0, b1 in bands:
            fi, fo = b0 / rout, b1 / rout
            ti, to = (b0 - rin) / (rout - rin), (b1 - rin) / (rout - rin)
            vi, vo = [], []
            for s in range(NSEG + 1):
                a = -math.pi / 2 + s / NSEG * math.pi
                vi.append(B.v((math.cos(a) * 0.5 * fi, y, math.sin(a) * 0.5 * fi), n, (ti + 0.005, s / NSEG)))
                vo.append(B.v((math.cos(a) * 0.5 * fo, y, math.sin(a) * 0.5 * fo), n, (to - 0.005, s / NSEG)))
            for s in range(NSEG):
                B.tri(vi[s], vo[s], vo[s + 1], n)
                B.tri(vi[s], vo[s + 1], vi[s + 1], n)
    return B

def make_object(name, B):
    me = bpy.data.meshes.new(name)
    me.from_pydata([to_b(p) for p in B.P], [], B.F)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            u, v = B.UV[vi]
            uvl.data[li].uv = (u, 1 - v)
    for poly in me.polygons:
        poly.use_smooth = True
    me.normals_split_custom_set_from_vertices([to_b(n) for n in B.N])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

bpy.ops.wm.read_factory_settings(use_empty=True)
meshes = {
    "PlanetHemiL": hemi(-1, False), "PlanetHemiR": hemi(1, False),
    "PlanetHemiDoubleL": hemi(-1, True), "PlanetHemiDoubleR": hemi(1, True),
    "PlanetDisc": disc(), "PlanetRingSaturn": ring(RING_SATURN),
}
info = {}
for name, B in meshes.items():
    make_object(name, B)
    xs, ys, zs = zip(*B.P)
    info[name] = {"tris": len(B.F), "verts": len(B.P),
                  "bbox_min": [round(min(xs), 4), round(min(ys), 4), round(min(zs), 4)],
                  "bbox_max": [round(max(xs), 4), round(max(ys), 4), round(max(zs), 4)]}
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_normals=True,
                          export_texcoords=True, export_materials="NONE", use_selection=False)
print(json.dumps(info, ensure_ascii=False, indent=1))
