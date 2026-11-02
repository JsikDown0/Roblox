"""APIS 윤곽 읽기 r2 — 머리·가슴(삼면도 앞·옆 확대). 다각형 = 원본 픽셀. 칸 = (x − 276) × 0.319 · z = (950 − y) × 0.319."""
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, OUT = sys.argv[1], sys.argv[2]
im = Image.open(SRC).convert("RGB")
F = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, O, P, B, R, C = (20, 140, 60), (220, 120, 0), (130, 70, 200), (30, 40, 200), (210, 30, 30), (0, 150, 170)
Rc = lambda x0, y0, x1, y1: [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
FRONT = [
    ("A", G, [(240, 152), (252, 142), (300, 142), (313, 152), (316, 205), (306, 222), (248, 222), (237, 205)], (318, 150)),
    ("A2?", P, ("e", 246, 145, 6, 7), (205, 132)),
    ("A2?", P, ("e", 307, 145, 6, 7), (318, 125)),
    ("A3", B, Rc(268, 181, 287, 190), (290, 172)),
    ("A1", C, [(250, 201), (262, 209), (276, 212), (290, 209), (302, 201), (302, 208), (290, 217), (276, 219), (262, 217), (250, 208)], (200, 196)),
    ("A4", B, [(252, 216), (300, 216), (296, 238), (256, 238)], (300, 226)),
    ("A5", O, Rc(236, 195, 251, 236), (205, 222)),
    ("A5", O, Rc(301, 195, 316, 236), (318, 200)),
    ("N", B, Rc(240, 236, 312, 251), (318, 238)),
    ("B1", O, [(198, 241), (256, 241), (268, 253), (284, 253), (296, 241), (354, 241), (358, 257), (194, 257)], (202, 228)),
    ("B", G, [(194, 258), (358, 258), (362, 300), (342, 318), (276, 327), (210, 318), (190, 300)], (200, 300)),
    ("B2", P, ("e", 328, 275, 11, 11), (338, 262)),
    ("C", C, Rc(257, 381, 294, 400), (300, 386)),
    ("C1", B, Rc(246, 366, 306, 406), (200, 345)),
    ("C2", O, Rc(200, 370, 245, 406), (204, 410)),
    ("C2", O, Rc(307, 370, 352, 406), (320, 410)),
]
SIDE = [
    ("A", G, [(612, 172), (640, 152), (690, 138), (720, 142), (722, 180), (700, 200), (662, 206), (652, 236), (622, 236), (610, 206)], (690, 120)),
    ("A1", C, ("e", 640, 192, 12, 10), (596, 168)),
    ("B", G, [(612, 250), (650, 236), (662, 256), (657, 330), (612, 330), (600, 300)], (590, 300)),
    ("D", O, [(650, 210), (746, 206), (756, 282), (702, 292), (656, 262)], (720, 215)),
]


def panel(box, k, parts):
    x0, y0, x1, y1 = box
    c = im.crop(box).resize((int((x1 - x0) * k), int((y1 - y0) * k)), Image.LANCZOS)
    c = Image.blend(c, Image.new("RGB", c.size, (255, 255, 255)), 0.3)
    ov = Image.new("RGBA", c.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    T = lambda p: ((p[0] - x0) * k, (p[1] - y0) * k)
    for lab, col, g, tp in parts:
        if isinstance(g, tuple):
            _, cx, cy, rx, ry = g
            d.ellipse([T((cx - rx, cy - ry)), T((cx + rx, cy + ry))], outline=col + (255,), width=3, fill=col + (40,))
        else:
            d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (35,), width=3)
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in parts:
        q = T(tp); w = dt.textlength(lab, font=f)
        q = (min(max(q[0], 2), c.width - w - 6), min(max(q[1], 2), c.height - 26))
        dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 23], fill=(255, 255, 255), outline=col, width=2)
        dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    return c


a = panel((185, 115, 375, 420), 2.6, FRONT)
b = panel((585, 115, 765, 345), 2.6, SIDE)
LEG = [("APIS 머리·가슴 윤곽 읽기 r2", None, ft), ("삼면도 앞(왼쪽)·옆(가운데) 2.6배", (90, 90, 90), fs), ("", None, fs),
       ("A 노랑 헬멧: 폭 ≈ 25칸 · 높이 ≈ 32칸(작은 머리)", G, fs), ("   옆: 앞이 낮고 뒤가 높은 길쭉한 모양, 앞으로 숙임", G, fs),
       ("A1 청록 바이저(발광): 양끝이 처진 넓은 호", C, fs), ("A3 이마 짙은 가로 홈 · A4 짙은 턱", B, fs),
       ("A5 노랑 볼판(좌우) · N 짙은 목 고리", O, fs), ("", None, fs),
       ("B1 노랑 목깃 띠: 가운데가 V 로 파임", O, fs), ("B 흰 가슴판: 폭 ≈ 53칸, 아래 끝이 가운데로 뾰족", G, fs),
       ("B2 노랑 ▲ = 데칼 자리(결정)", P, fs), ("C 배 청록 코어(발광) · C1 짙은 틀 · C2 노랑 옆 블록", C, fs),
       ("D (옆) 어깨 덮개가 머리 옆을 크게 가림", O, fs), ("", None, fs), ("질문", None, f),
       ("1. A2? 헬멧 위 양 모서리 짙은 혹 2개(곰 귀처럼 보임)", P, fs),
       ("   귀여움 포인트로 넣을까? 제안: 넣음(작게)", P, fs),
       ("2. 머리 높이: 그림처럼 어깨 사이에 낮게 + 앞으로", P, fs),
       ("   (옆에서 머리가 가슴보다 앞) — 그대로?", P, fs),
       ("3. 바이저 호의 처짐(ㅅ) 정도 — 그림 그대로?", P, fs)]
W = a.width + b.width + 540
H = max(a.height, 40 + 29 * len(LEG))
sh = Image.new("RGB", (W, H), (250, 250, 250)); d = ImageDraw.Draw(sh)
sh.paste(a, (0, 0)); sh.paste(b, (a.width + 10, 0))
y = 10; x = a.width + b.width + 24
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 28
sh.save(OUT); print(sh.size)
