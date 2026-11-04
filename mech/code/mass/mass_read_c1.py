"""BISON 지휘관형(ST-10C) 윤곽 읽기 c1 — 기본형과 다른 부분만. 컨셉 = 레퍼런스/양산형/지휘관형/concept_c1_삼면도.png(1536×1024).
[실측] 정면 머리 꼭대기 y≈64(안테나 제외) · 발바닥 y≈921 → z = (921 − y) × 0.303.
쓰기: python3 mass_read_c1.py <컨셉.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, OUT = sys.argv[1:3]
im = Image.open(SRC).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, P, B, R, C = (20, 140, 60), (130, 70, 200), (30, 40, 200), (210, 30, 30), (0, 150, 170)
Z = lambda y: round((921 - y) * 0.303)
E = lambda cx, cy, rx, ry: ("e", cx, cy, rx, ry)
FRONT = [   # 그림 왼쪽 = 기체 오른쪽
    ("A1", G, [(359, 22), (367, 22), (367, 100), (359, 100)], (372, 30)),
    ("A2", R, [(223, 22), (231, 22), (231, 100), (223, 100)], (180, 30)),
    ("M", P, [(60, 80), (100, 80), (104, 175), (62, 178)], (10, 120)),
    ("M", P, [(488, 92), (526, 92), (528, 185), (490, 185)], (530, 140)),
    ("RS", G, [(92, 62), (150, 55), (200, 75), (205, 200), (175, 220), (100, 215), (88, 150)], (120, 230)),
    ("L", C, E(240, 127, 12, 12), (205, 145)),
    ("L", C, E(368, 127, 12, 12), (380, 145)),
    ("CH", G, [(185, 120), (300, 108), (470, 125), (475, 210), (430, 260), (190, 262), (180, 210)], (420, 270)),
    ("EM", B, [(270, 145), (335, 145), (335, 205), (270, 205)], (230, 210)),
    ("TH", G, [(120, 395), (240, 395), (245, 515), (125, 520)], (60, 450)),
    ("TH", G, [(330, 395), (450, 395), (455, 520), (335, 515)], (460, 450)),
    ("KN", G, [(110, 515), (205, 510), (215, 600), (195, 640), (120, 640), (105, 590)], (60, 600)),
]
SIDE = [    # 앞 = 그림 왼쪽
    ("A1", G, [(818, 30), (828, 30), (828, 110), (818, 110)], (835, 40)),
    ("M", P, [(770, 125), (830, 125), (835, 245), (772, 245)], (845, 180)),
    ("TH", G, [(750, 300), (870, 300), (875, 470), (745, 470)], (880, 380)),
]
REAR = [
    ("M", P, [(990, 85), (1035, 85), (1037, 185), (992, 185)], (985, 60)),
    ("M", P, [(1462, 85), (1505, 85), (1508, 190), (1465, 190)], (1440, 60)),
]


def panel(box, k, parts):
    x0, y0, x1, y1 = box
    c = im.crop(box).resize((int((x1 - x0) * k), int((y1 - y0) * k)), Image.LANCZOS)
    c = Image.blend(c, Image.new("RGB", c.size, (255, 255, 255)), 0.25)
    ov = Image.new("RGBA", c.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    T = lambda p: ((p[0] - x0) * k, (p[1] - y0) * k)
    for lab, col, g, tp in parts:
        if isinstance(g, tuple):
            _, cx, cy, rx, ry = g
            d.ellipse([T((cx - rx, cy - ry)), T((cx + rx, cy + ry))], outline=col + (255,), width=3, fill=col + (40,))
        else:
            d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (40,), width=3)
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in parts:
        q = T(tp); w = dt.textlength(lab, font=f)
        q = (min(max(q[0], 2), c.width - w - 6), min(max(q[1], 2), c.height - 26))
        dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 23], fill=(255, 255, 255), outline=col, width=2)
        dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    for y in range(100, y1, 100):
        if y <= y0: continue
        Y = (y - y0) * k
        dt.line([(0, Y), (10, Y)], fill=(80, 80, 80), width=2)
        dt.text((c.width - 46, Y - 10), "z%d" % Z(y), fill=(80, 80, 80), font=fs)
    return c


a = panel((0, 15, 580, 660), 1.0, FRONT)
b = panel((590, 15, 910, 660), 1.0, SIDE)
c = panel((975, 15, 1530, 660), 1.0, REAR)
LEG = [("BISON 지휘관형(ST-10C) 윤곽 읽기 c1 — 기본형과 다른 부분만", None, ft),
       ("z = (921 − y) × 0.303 · 답 [결정 11-04]: 안테나 b · 둥근 통 = 보조 무장(미사일·연막) ·", (90, 90, 90), fs),
       ("  오른 어깨 판 · 목깃 렌즈 · 흉판 덧장갑 · 큰 허벅지·무릎 판 가져옴 · 역할 = 강화 스펙 + 아군 보조", (90, 90, 90), fs), ("", None, fs),
       ("A1 안테나 하나 = 왼 어깨 위(그림 오른쪽 것) · A2 오른쪽 = 뺌", G, fs),
       ("M 어깨 보조 무장 통 3개씩(그림: 양 어깨 바깥, 옆에선 어깨 뒤쪽)", P, fs),
       ("RS 오른 어깨에도 큰 판(왼쪽 판의 거울 → 양쪽 대칭)", G, fs),
       ("L 목깃 양옆 둥근 센서 렌즈 2", C, fs),
       ("CH 흉판 덧장갑(가슴 위를 한 겹 더 덮는 큰 판) · EM 가운데 엠블럼 = 데칼", G, fs),
       ("TH 허벅지 판 · KN 무릎 판 — 더 크고 두툼", G, fs), ("", None, fs),
       ("질문 ① 보조 무장 통: 양 어깨(그림대로) / 한쪽만?", P, fs),
       ("   제안: 양쪽 — 판도 양쪽 대칭이라 균형 · 왼쪽 = 미사일, 오른쪽 = 연막처럼 나눌 수도", P, fs),
       ("질문 ② 통 자리: 어깨판 뒤 면(PlateB) 바깥 위쪽, 통 입구는 앞·위", P, fs),
       ("   앞 면(PlateF \"03\" 데칼)은 가리지 않게 — 그림 옆모습도 뒤쪽", P, fs),
       ("질문 ③ 흉판 덧장갑 두께: 2칸 / 4칸(그림은 한 겹 두툼)?  제안 3칸", P, fs),
       ("질문 ④ 허벅지·무릎 판 크기: 폭·두께 +10% / +20%?  제안 +15%", P, fs),
       ("질문 ⑤ 목깃 렌즈 발광? 발광은 바이저만(결정 8절) → 제안: 발광 없음(짙은 유리)", P, fs)]
top = [a, b, c]
lw = 720
W = sum(i.width for i in top) + 40 + lw
H = max(max(i.height for i in top), 26 * len(LEG) + 40) + 20
out = Image.new("RGB", (W, H), (255, 255, 255)); d = ImageDraw.Draw(out)
x = 10
for p in top:
    out.paste(p, (x, 10)); x += p.width + 10
y = 14; x += 10
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 26
out.save(OUT); print(OUT, out.size)
