"""compare.py — 컨셉과 나란히 비교 렌더
  python3 compare.py hero  OUT     컨셉 큰 그림 | 같은 각도 렌더
  python3 compare.py ortho OUT     컨셉 3면도(위) / 정면·측면·후면 렌더(아래)
  python3 compare.py views OUT     4면(정면·3/4·옆·뒤 3/4)
  python3 compare.py upper OUT     컨셉 상체 | 렌더 상체
"""
import sys
import time

from PIL import Image

import mesh_render as mr
import nova_mesh as nm

REF = "nova_ref.png"
HY, HP = 38, -10         # 컨셉 큰 그림 카메라: 기체 왼쪽 앞, 낮게
HK = dict(fov=40, dist_mul=0.78, target=(0, 0, 140), amb=0.5, exposure=1.12, ao=1.0)
BG = (13, 15, 21)


def keylight(yaw, pitch, side=-0.75, up=0.7, front=0.45):
    import numpy as np
    d, f, r, u = mr.basis(yaw, pitch)
    L = side * r + up * u + front * d
    return tuple(L / np.linalg.norm(L))


def fit(im, h):
    return im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS)


def stack(top, bottom):
    W = max(top.width, bottom.width)
    S = Image.new("RGB", (W, top.height + bottom.height), BG)
    S.paste(top, (0, 0)); S.paste(bottom, (0, top.height))
    return S


if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]
    t0 = time.time()
    M = nm.build_all()
    ref = Image.open(REF).convert("RGB")
    if mode == "hero":
        V, N, C, B = M.tris(pose=nm.POSE_HERO)
        im = mr.render(V, N, C, B, nm.PAL, nm.EMISSIVE, yaw=HY, pitch=HP, ppc=3.0, ss=2, light=keylight(HY, HP), **HK)
        r = fit(ref.crop((20, 0, 470, 590)), 900)
        mr.sheet([r, fit(im, 900)], ["concept", "block mesh"]).save(out)
    elif mode == "trio":
        V, N, C, B = M.tris(pose=nm.POSE_HERO)
        im = mr.render(V, N, C, B, nm.PAL, nm.EMISSIVE, yaw=HY, pitch=HP, ppc=3.0, ss=2, light=keylight(HY, HP), **HK)
        r = fit(ref.crop((20, 0, 470, 590)), 900)
        other = Image.open("other_room.png").convert("RGB")
        ow, oh = other.size
        o = fit(other.crop((ow // 2, 0, ow, oh)), 900)
        mr.sheet([r, o, fit(im, 900)], ["concept (GPT)", "voxel (other room)", "block mesh (this)"]).save(out)
    elif mode == "ortho":
        V, N, C, B = M.tris(pose=nm.POSE_ORTHO)
        ims = [fit(mr.render(V, N, C, B, nm.PAL, nm.EMISSIVE, yaw=y, pitch=0, ppc=2.2, ss=2, light=keylight(y, 0), amb=0.5, exposure=1.12, ao=1.0), 520) for y in (0, 90, 180)]
        top = mr.sheet([fit(ref.crop((25, 600, 425, 788)), 520)], ["concept FRONT / SIDE / BACK"])
        stack(top, mr.sheet(ims, ["mesh front", "mesh side", "mesh back"])).save(out)
    elif mode == "views":
        V, N, C, B = M.tris(pose=nm.POSE_ORTHO)
        ims = [mr.render(V, N, C, B, nm.PAL, nm.EMISSIVE, yaw=y, pitch=p, ppc=2.6, ss=2, light=keylight(y, p), amb=0.5, exposure=1.12, ao=1.0) for y, p in ((0, 4), (30, 8), (90, 3), (150, 12))]
        mr.sheet(ims, ["front", "3/4", "side", "back 3/4"]).save(out)
    elif mode == "upper":
        V, N, C, B = M.tris(pose=nm.POSE_HERO)
        im = mr.render(V, N, C, B, nm.PAL, nm.EMISSIVE, yaw=HY, pitch=HP, ppc=4.2, ss=2, light=keylight(HY, HP), **HK)
        w, h = im.size
        im = im.crop((int(w * 0.18), 0, int(w * 0.92), int(h * 0.5)))
        r = fit(ref.crop((150, 40, 420, 280)), 700)
        mr.sheet([r, fit(im, 700)], ["concept", "block mesh"]).save(out)
    print(mode, "%.1fs" % (time.time() - t0), M.count())
