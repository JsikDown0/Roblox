"""front_compare.py — 정면 직교 '맨 앞 칸 색' 비교: 복셀 모델(내보낸 자세) vs 내보낸 GLB(z-버퍼). 칸 1개 = 1픽셀.
그림자·조명 없이 팔레트 색 그대로 → 렌더러 차이가 아니라 '실제로 앞에 보이는 색'이 같은지 본다."""
import sys, numpy as np
sys.path.insert(0, "/home/claude/flag"); sys.path.insert(0, "/home/claude/flag/tools")
import aero_export as E, aero_colors as Cc, glb_preview as GP
from PIL import Image

def vox_front(M, pose, pal):
    X0, X1, Z0, Z1 = -90, 90, -5, 300
    depth = np.full((Z1 - Z0, X1 - X0), np.inf); col = np.zeros((Z1 - Z0, X1 - X0), int); who = np.full((Z1 - Z0, X1 - X0), "", object)
    for n, p in M.parts.items():
        ijk = np.argwhere(p.a > 0); c = p.a[p.a > 0]
        T = M.world(n, pose); W = (ijk + p.lo) @ T[:3, :3].T + T[:3, 3]
        xi = np.round(W[:, 0]).astype(int) - X0; zi = np.round(W[:, 2]).astype(int) - Z0; y = W[:, 1]
        ok = (xi >= 0) & (xi < X1 - X0) & (zi >= 0) & (zi < Z1 - Z0)
        for a, b, d, cc in zip(xi[ok], zi[ok], y[ok], c[ok]):
            if d < depth[b, a]:
                depth[b, a] = d; col[b, a] = cc; who[b, a] = n
    return col[::-1], who[::-1]

def glb_front(path):
    T, C, names = GP.load(path)
    T = T / 0.05                                        # Blender → 칸, glTF (x, z, -y): 정면 = +Z
    X0, X1, Z0, Z1 = -90, 90, -5, 300
    H, Wd = Z1 - Z0, X1 - X0
    zb = np.full((H, Wd), -np.inf); cb = np.zeros((H, Wd, 3)); wb = np.full((H, Wd), "", object)
    for t, c, nm in zip(T, C, names):
        P = np.stack([t[:, 0] - X0 - 0.5, t[:, 1] - Z0 - 0.5, t[:, 2]], 1)   # 픽셀 중심 = 칸 중심
        x0, x1 = int(np.floor(P[:, 0].min())), int(np.ceil(P[:, 0].max())); y0, y1 = int(np.floor(P[:, 1].min())), int(np.ceil(P[:, 1].max()))
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, Wd - 1), min(y1, H - 1)
        if x1 < x0 or y1 < y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = P
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12: continue
        l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        l3 = 1 - l1 - l2
        inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
        z = l1 * az + l2 * bz + l3 * cz
        sel = inside & (z > zb[gy, gx])
        zb[gy[sel], gx[sel]] = z[sel]; cb[gy[sel], gx[sel]] = c; wb[gy[sel], gx[sel]] = nm
    return cb[::-1], wb[::-1], zb[::-1]

if __name__ == "__main__":
    out = sys.argv[1]; glb = sys.argv[2]
    pal = Cc.SCHEMES[E.SCHEME]
    M = E.build()
    col, who = vox_front(M, E.REST_POSE, pal)
    vimg = np.zeros(col.shape + (3,));
    for n, rgb in pal.items(): vimg[col == n] = np.array(rgb) / 255
    gimg, gwho, zb = glb_front(glb)
    diff = np.any(np.abs(vimg - gimg) > 0.02, axis=2)
    print("pixels voxel", int((col > 0).sum()), "glb", int(np.isfinite(zb).sum()), "differ", int(diff.sum()))
    # 다른 칸이 어느 파트(복셀 기준)에서 나는지
    from collections import Counter
    print("differ by voxel part", Counter(who[diff]).most_common(12))
    print("differ by glb part", Counter(gwho[diff]).most_common(12))
    S = 3
    def up(a): return np.kron(a, np.ones((S, S, 1)))
    red = vimg.copy(); red[diff] = [1, 0, 1]
    canvas = np.concatenate([up(vimg), np.ones((col.shape[0] * S, 6, 3)) * 0.2, up(gimg), np.ones((col.shape[0] * S, 6, 3)) * 0.2, up(red)], 1)
    Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8)).save(out)
