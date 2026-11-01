import sys, os, numpy as np
from multiprocessing import Pool
from PIL import Image, ImageDraw, ImageFont
FPS = 24
SZ = ((-240, 240), (-15, 400)); PPC = 1.25
OUT = sys.argv[1]; YAW = float(sys.argv[2]) if len(sys.argv) > 2 else 0; PIT = float(sys.argv[3]) if len(sys.argv) > 3 else 4
TAIL = 0.6
def label(t):
    import keys2 as K
    k = max((kk for kk in K.ORDER if K.TIMES[kk] <= t + 1e-6), key=lambda kk: K.TIMES[kk])
    return k, K.LABEL[k]
def job(i):
    import scene2 as S
    t = i / FPS
    im, _ = S.frame(t, YAW, PIT, SZ, ppc=PPC)
    d = ImageDraw.Draw(im); f = ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", 18)
    k, lab = label(t)
    d.text((12, 10), "%.2fs  %s %s" % (t, k, lab), font=f, fill=(200, 205, 214))
    p = os.path.join(OUT, "%04d.png" % i); im.save(p); return p
if __name__ == "__main__":
    import keys2 as K, timeline2 as TL
    os.makedirs(OUT, exist_ok=True)
    TL.models()
    for n in K.ORDER: K.get(n, TL.models())       # 풀이 캐시 미리
    N = int((K.END + TAIL) * FPS) + 1
    with Pool(int(sys.argv[4]) if len(sys.argv) > 4 else 4) as pool:
        for j, p in enumerate(pool.imap(job, range(N))):
            if j % 20 == 0: print(j, N, flush=True)
    print("frames", N)
