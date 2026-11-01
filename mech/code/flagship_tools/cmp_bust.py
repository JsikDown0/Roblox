"""cmp.py — 시안 1행 4뷰와 같은 구도로 렌더해 나란히 비교
  python3 cmp.py views OUT [vs]      시안 4뷰(위) / 렌더 4뷰(아래)
  python3 cmp.py one VIEW OUT [vs]   한 뷰만 크게(front/q34/side/back) + 시안
  python3 cmp.py head OUT [vs]       머리 근접(정면·3/4) + 시안 얼굴 디테일
"""
import sys, time
from PIL import Image
import bust, vox, vrt

REF = Image.open("ref.png").convert("RGB")
CROPS = {"front": (10, 30, 420, 410), "q34": (430, 30, 800, 410), "side": (800, 40, 1030, 410), "back": (1030, 40, 1360, 410),
         "face": (1370, 50, 1530, 200), "chest": (1370, 225, 1530, 395)}
CAMS = {"front": dict(yaw=0, pitch=11), "q34": dict(yaw=38, pitch=14), "side": dict(yaw=90, pitch=6), "back": dict(yaw=180, pitch=10)}
FOV = 36


def fit(im, h):
    return im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS)


def ref(k, h):
    return fit(REF.crop(CROPS[k]), h)


if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]
    t0 = time.time()
    M = bust.build_all()
    vs = float(sys.argv[-1]) if len(sys.argv) > 3 and sys.argv[-1].replace('.', '').isdigit() else 1.25
    G = vox.voxelize(M, vs=vs); vrt.bake(G, bust.PAL, bust.EMIS)
    if mode == "views":
        H = 520
        top = vrt.sheet([ref(k, H) for k in CAMS], ["concept " + k for k in CAMS])
        ims = [vrt.render(G, bust.PAL, bust.EMIS, height=H, ss=2, fov=FOV, **CAMS[k]) for k in CAMS]
        bot = vrt.sheet(ims, ["render " + k for k in CAMS])
        W = max(top.width, bot.width)
        S = Image.new("RGB", (W, top.height + bot.height), (9, 10, 14))
        S.paste(top, (0, 0)); S.paste(bot, (0, top.height)); S.save(out)
    elif mode == "one":
        k = sys.argv[3]
        H = 820
        im = vrt.render(G, bust.PAL, bust.EMIS, height=H, ss=2, fov=FOV, **CAMS[k])
        vrt.sheet([ref(k, H), im], ["concept " + k, "render"]).save(out)
    elif mode == "head":
        import numpy as np
        skip = ("ShoulderL", "ShoulderR", "ArmL", "ArmR", "WingL", "WingR")
        Gh = vox.voxelize(M, vs=vs, skip=skip)
        # 머리 근처만 남김
        z0 = int((80 - Gh.org[2]) / vs)
        Gh.col[:, :, :max(z0, 0)] = 0
        H = 640
        a = vrt.render(Gh, bust.PAL, bust.EMIS, yaw=0, pitch=6, height=H, ss=2, fov=FOV)
        b = vrt.render(Gh, bust.PAL, bust.EMIS, yaw=34, pitch=10, height=H, ss=2, fov=FOV)
        vrt.sheet([ref("face", H), a, b], ["concept face", "head front", "head 3/4"]).save(out)
    print(mode, "%.1fs" % (time.time() - t0), G.col.shape, G.count())
