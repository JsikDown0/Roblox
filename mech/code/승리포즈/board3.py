import sys
from PIL import Image, ImageDraw, ImageFont
import keys2 as K, scene2 as S
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
f1 = ImageFont.truetype(FONT, 22); f2 = ImageFont.truetype(FONT, 16); f3 = ImageFont.truetype(FONT, 14)
SZ = ((-230, 230), (-15, 400)); ppc = 0.8
REF = {"K0": 3, "K1": 16, "K2": 22, "K3": 62, "K4": 70, "K5": 80, "K6": 92, "K7": 140}
TT = dict(K.TIMES); TT["K1"] = 0.45      # 불똥 보이는 순간
cols = []
for k in K.ORDER:
    t = TT[k]
    a, _ = S.frame(t, 55, 4, SZ, ppc=ppc)
    b, _ = S.frame(t, 160, 12, SZ, ppc=ppc, fx=False)
    W = a.width
    r = Image.open("/home/claude/victory/ref/f/%03d.jpg" % (REF[k] + 1)).convert("RGB").crop((0, 52, 960, 488))
    r = r.resize((W, int(W * 436 / 960)))
    H = 60 + r.height + 22 + a.height + b.height
    C = Image.new("RGB", (W, H), (13, 14, 17)); d = ImageDraw.Draw(C)
    d.text((10, 8), "%s  %.2fs" % (k, t), font=f1, fill=(235, 238, 242)); d.text((10, 36), K.LABEL[k], font=f2, fill=(170, 176, 186))
    C.paste(r, (0, 60)); d.text((8, 60 + r.height + 2), "레퍼런스 %.2fs" % (REF[k] / 30), font=f3, fill=(120, 126, 136))
    y = 60 + r.height + 22; C.paste(a, (0, y)); C.paste(b, (0, y + a.height)); cols.append(C); print(k, flush=True)
W = sum(c.width for c in cols) + 8 * (len(cols) - 1)
B = Image.new("RGB", (W, cols[0].height), (30, 32, 36)); x = 0
for c in cols: B.paste(c, (x, 0)); x += c.width + 8
B.save(sys.argv[1]); print(B.size)
