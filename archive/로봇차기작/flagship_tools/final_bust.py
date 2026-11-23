"""final.py — 최종 시트: 4뷰 비교 / 3/4 히어로 / 머리 근접"""
import time
from PIL import Image
import bust, vox, vrt, cmp
OUT = "/mnt/user-data/outputs/bust/"
t0 = time.time()
M = bust.build_all()
G = vox.voxelize(M, vs=1.25); vrt.bake(G, bust.PAL, bust.EMIS, aoK=64, spK=32)
H = 560
top = vrt.sheet([cmp.ref(k, H) for k in cmp.CAMS], ["concept " + k for k in cmp.CAMS])
ims = [vrt.render(G, bust.PAL, bust.EMIS, height=H, ss=3, fov=cmp.FOV, **cmp.CAMS[k]) for k in cmp.CAMS]
bot = vrt.sheet(ims, ["voxel " + k for k in cmp.CAMS])
W = max(top.width, bot.width)
S = Image.new("RGB", (W, top.height + bot.height), (9, 10, 14)); S.paste(top, (0, 0)); S.paste(bot, (0, top.height))
S.save(OUT + "bust_4view_compare.png")
hero = vrt.render(G, bust.PAL, bust.EMIS, yaw=34, pitch=12, height=1100, ss=3, fov=cmp.FOV)
hero.save(OUT + "bust_hero.png")
front = vrt.render(G, bust.PAL, bust.EMIS, yaw=0, pitch=11, height=900, ss=3, fov=cmp.FOV)
vrt.sheet([cmp.ref("front", 900), front], ["concept front", "voxel front"]).save(OUT + "bust_front_compare.png")
print("done %.1fs" % (time.time() - t0), G.col.shape, G.count(), G.surface())
skip = ("ShoulderL", "ShoulderR", "ArmL", "ArmR", "WingL", "WingR")
Gh = vox.voxelize(M, vs=1.25, skip=skip)
Gh.col[:, :, :int((80 - Gh.org[2]) / 1.25)] = 0
vrt.bake(Gh, bust.PAL, bust.EMIS, aoK=64, spK=32)
a = vrt.render(Gh, bust.PAL, bust.EMIS, yaw=0, pitch=6, height=640, ss=3, fov=cmp.FOV)
b = vrt.render(Gh, bust.PAL, bust.EMIS, yaw=34, pitch=10, height=640, ss=3, fov=cmp.FOV)
vrt.sheet([cmp.ref("face", 640), a, b], ["concept face", "voxel head front", "voxel head 3/4"]).save(OUT + "bust_head_compare.png")
print("head done %.1fs" % (time.time() - t0))
