"""glb_preview.py — GLB 를 다시 읽어 그림(앞면만 그림 = 면 방향이 뒤집히면 구멍으로 보임). 검사용.
  python3 glb_preview.py IN.glb OUT.png"""
import sys, io
import numpy as np
import pygltflib as G
from PIL import Image
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

def load(path):
    g = G.GLTF2().load(path); blob = g.binary_blob()
    def acc(i, dt, n):
        a = g.accessors[i]; bv = g.bufferViews[a.bufferView]; o = (bv.byteOffset or 0) + (a.byteOffset or 0)
        return np.frombuffer(blob[o:o + a.count * n * np.dtype(dt).itemsize], dt).reshape(a.count, n)
    img = g.images[0]; bv = g.bufferViews[img.bufferView]
    pal = np.asarray(Image.open(io.BytesIO(blob[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength])).convert("RGB"))
    tris, cols, names = [], [], []
    for node in g.nodes:
        pr = g.meshes[node.mesh].primitives[0]
        P = acc(pr.attributes.POSITION, np.float32, 3); UV = acc(pr.attributes.TEXCOORD_0, np.float32, 2)
        I = acc(pr.indices, np.uint32, 1).reshape(-1, 3)
        T = P[I]; uv = UV[I[:, 0]]
        px = np.clip((uv[:, 0] * 64).astype(int), 0, 63); py = np.clip((uv[:, 1] * 64).astype(int), 0, 63)   # glTF v 위부터
        tris.append(T); cols.append(pal[py, px] / 255.0); names += [node.name] * len(T)
    return np.concatenate(tris), np.concatenate(cols), names

def view(ax, T, C, yaw, pitch=8):
    y, p = np.radians(yaw), np.radians(pitch)
    R1 = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    R2 = np.array([[1, 0, 0], [0, np.cos(p), -np.sin(p)], [0, np.sin(p), np.cos(p)]])
    Rm = R2 @ R1
    V = T @ Rm.T                                     # 카메라는 +Z 에서 -Z 를 봄(기체 정면 = glTF +Z)
    n = np.cross(V[:, 1] - V[:, 0], V[:, 2] - V[:, 0])
    front = n[:, 2] > 1e-9
    nl = n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)
    L = np.array([-0.35, 0.6, 0.72]); L /= np.linalg.norm(L)
    sh = 0.45 + 0.55 * np.clip(nl @ L, 0, 1)
    V, Cc, sh = V[front], C[front], sh[front]
    order = np.argsort(V[:, :, 2].mean(1))
    pc = PolyCollection(V[order][:, :, :2], facecolors=np.clip(Cc[order] * sh[order, None], 0, 1), edgecolors="none", antialiased=False)
    ax.add_collection(pc); ax.set_aspect("equal"); ax.autoscale_view(); ax.axis("off"); ax.set_title("yaw %d" % yaw, color="w", fontsize=8)

if __name__ == "__main__":
    T, C, names = load(sys.argv[1])
    print("tris", len(T), "bounds", T.reshape(-1, 3).min(0).round(3), T.reshape(-1, 3).max(0).round(3))
    fig, axs = plt.subplots(1, 4, figsize=(16, 6), facecolor=(0.05, 0.055, 0.067))
    for ax, yw in zip(axs, (0, 35, 180, 270)):
        ax.set_facecolor((0.05, 0.055, 0.067)); view(ax, T, C, yw)
    plt.tight_layout(); plt.savefig(sys.argv[2], dpi=110, facecolor=fig.get_facecolor())
