import numpy as np, vpose as V, keys2 as K, timeline2 as TL, keys as K1, sys
Ms = TL.models()
M = Ms["lit"]
pairs = [p for p in V.check_pairs(M) if "SaberHolsterL" not in p]
pairs += [("LowerArmR", "RifleStowed"), ("UpperArmR", "RifleStowed"), ("LowerArmL", "RifleStowed"), ("Saber", "RifleStowed")]
base = V.overlaps(M, K1.skirts(K1.pads({})), pairs)
fps = float(sys.argv[1]) if len(sys.argv) > 1 else 20
worst = {}
feet = []
for t in np.arange(0, K.END + 1e-6, 1 / fps):
    P, lit, *_ = TL.state(t)
    Mx = Ms["lit"] if lit > 0 else Ms["hilt"]
    ov = V.overlaps(Mx, P, pairs)
    for k, v in ov.items():
        d = v - base.get(k, 0)
        if d > 20 and d > worst.get(k, (0, 0))[0]:
            worst[k] = (d, round(t, 2))
    _, c = V.blocks(Mx, P)
    z = []
    for n in ("FootL", "FootR"):
        p = Mx.parts[n]; pts = (np.argwhere(p.a > 0) + p.lo).astype(float); T = c[n]
        z.append(float((pts @ T[:3, :3].T + T[:3, 3])[:, 2].min()))
    feet.append((round(t, 2), round(z[0], 1), round(z[1], 1)))
for k, (d, t) in sorted(worst.items(), key=lambda x: -x[1][0]):
    print("%-26s max %5d at %.2fs" % ("/".join(k), d, t))
fz = np.array([[f[1], f[2]] for f in feet])
print("foot min z over path: L %.1f..%.1f  R %.1f..%.1f (칸)" % (fz[:, 0].min(), fz[:, 0].max(), fz[:, 1].min(), fz[:, 1].max()))
print("final feet:", feet[-1])
