"""GLB 를 직접 읽어 검사 (Blender 를 거치지 않음) — 로블록스 좌표 = glTF 좌표 가정
  ① 반구: uv 가 위치에서 계산한 경도 · 위도와 맞나 (PlanetGummyArt M.hemi 규칙)
  ② 삼각형마다 기하 법선(반시계) 과 꼭짓점 법선 방향이 같은가 (앞면이 바깥을 보나)
  ③ 고리 · 원판 uv 규칙
"""
import json, struct, sys, math
FRONT = 110
path = sys.argv[1]
data = open(path, "rb").read()
jlen = struct.unpack_from("<I", data, 12)[0]
gj = json.loads(data[20:20 + jlen])
bin0 = 20 + jlen + 8
CT = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}
def acc(i):
    a = gj["accessors"][i]; bv = gj["bufferViews"][a["bufferView"]]
    fmt, sz = CT[a["componentType"]]; n = NC[a["type"]]
    off = bin0 + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", sz * n)
    return [struct.unpack_from("<" + fmt * n, data, off + k * stride) for k in range(a["count"])]
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
nodes = {n["name"]: n for n in gj["nodes"]}
ok_all = True
for m in gj["meshes"]:
    name = m["name"]
    node = nodes.get(name, {})
    tr = [k for k in ("translation", "rotation", "scale", "matrix") if k in node]
    P, N, UV, idx = [], [], [], []
    for prim in m["primitives"]:
        base = len(P)
        P += acc(prim["attributes"]["POSITION"]); N += acc(prim["attributes"]["NORMAL"]); UV += acc(prim["attributes"]["TEXCOORD_0"])
        idx += [i[0] + base for i in acc(prim["indices"])]
    tris = [idx[k:k+3] for k in range(0, len(idx), 3)]
    bad_wind, bad_uv, maxerr = 0, 0, 0.0
    for a, b, c in tris:
        g = cross(sub(P[b], P[a]), sub(P[c], P[a]))
        vn = tuple(N[a][q] + N[b][q] + N[c][q] for q in range(3))
        if dot(g, vn) <= 0: bad_wind += 1
    for p, n, uv in zip(P, N, UV):
        u, v = uv
        if name.startswith("PlanetHemi"):
            r = math.sqrt(dot(p, p)) * 2
            lat = math.degrees(math.asin(max(-1, min(1, p[1] * 2))))
            ev = (90 - lat) / 180
            err = abs(v - ev)
            if abs(abs(lat) - 90) > 0.5:   # 극점이 아니면 경도도
                d = math.degrees(math.atan2(-p[0], -p[2]))     # p = (-cos la sin d, sin la, -cos la cos d)
                lon = FRONT + d
                eu = (lon - (FRONT - 180)) / 360
                err = max(err, min(abs(u - eu), abs(u - eu - 1), abs(u - eu + 1)))
            maxerr = max(maxerr, err, abs(r - 1))
        elif name == "PlanetDisc":
            maxerr = max(maxerr, abs(u - (0.5 + p[2])), abs(v - (0.5 - p[1])))
        elif name.startswith("PlanetRing"):
            maxerr = max(maxerr, abs(v - (math.atan2(p[2], p[0]) + math.pi / 2) / math.pi))
    xs, ys, zs = zip(*P)
    print(f"{name:20s} 삼각형 {len(tris):5d} · 앞면 어긋남 {bad_wind} · uv 최대 오차 {maxerr:.4f} · 노드 변환 {tr or '없음'}"
          f" · bbox x {min(xs):.3f}~{max(xs):.3f} y {min(ys):.3f}~{max(ys):.3f} z {min(zs):.3f}~{max(zs):.3f}")
    if bad_wind or maxerr > 0.003 or tr: ok_all = False
print("전부 통과" if ok_all else "⚠️ 어긋남 있음")
