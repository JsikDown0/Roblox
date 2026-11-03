"""양산형 윤곽 읽기 r3 — 팔(삼면도 정면 오른팔 · 뒤 오른팔 + 메인 양팔). z = (925 − y) × 0.295.
쓰기: python3 mass_read_r3.py <삼면도.png> <메인.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, MAIN, OUT = sys.argv[1:4]
im = Image.open(SRC).convert("RGB"); mn = Image.open(MAIN).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, P, R, C = (20, 140, 60), (130, 70, 200), (210, 30, 30), (0, 150, 170)
Z = lambda y: round((925 - y) * 0.295)
E = lambda cx, cy, rx, ry: ("e", cx, cy, rx, ry)
FRONT = [   # 기체 오른팔(그림 왼쪽)
    ("A1", G, [(92, 200), (160, 200), (163, 258), (95, 260)], (30, 210)),
    ("A2", C, [(82, 262), (160, 262), (160, 296), (82, 296)], (30, 268)),
    ("A3", G, [(98, 296), (168, 296), (172, 355), (150, 372), (108, 372), (100, 340)], (30, 320)),
    ("A4", C, [(105, 372), (158, 372), (158, 408), (105, 408)], (30, 380)),
    ("A5", G, [(95, 408), (165, 408), (162, 480), (100, 480)], (30, 440)),
    ("W", R, [(10, 290), (75, 290), (90, 520), (20, 520)], (10, 530)),
]
REAR = [    # 기체 오른팔(그림 오른쪽)
    ("A1", G, [(1372, 212), (1440, 212), (1442, 255), (1374, 255)], (1460, 220)),
    ("A2", C, [(1378, 265), (1450, 265), (1450, 300), (1378, 300)], (1460, 270)),
    ("A3", G, [(1388, 300), (1462, 300), (1468, 400), (1412, 405), (1390, 360)], (1470, 340)),
    ("A5", G, [(1400, 420), (1450, 420), (1452, 490), (1402, 490)], (1460, 450)),
]
MAINR = [   # 메인 오른팔(그림 왼쪽, 기체 오른쪽)
    ("A1", G, [(235, 330), (330, 330), (335, 410), (240, 412)], (180, 340)),
    ("A2", C, [(225, 415), (310, 415), (320, 480), (230, 480)], (170, 430)),
    ("A2b", P, E(320, 480, 18, 22), (340, 470)),
    ("A3", G, [(240, 470), (330, 465), (330, 580), (300, 610), (250, 610), (240, 560)], (340, 560)),
    ("A5", G, [(200, 610), (265, 610), (262, 700), (205, 700)], (180, 720)),
]
MAINL = [   # 메인 왼팔(그림 오른쪽, 기체 왼쪽)
    ("A3", G, [(750, 480), (835, 480), (838, 640), (760, 650)], (690, 560)),
    ("A5", G, [(745, 680), (835, 680), (838, 800), (750, 800)], (690, 760)),
    ("I1", R, [(830, 370), (965, 400), (960, 820), (880, 850), (835, 800)], (900, 860)),
]


def panel(img, box, k, parts, zlab=True):
    x0, y0, x1, y1 = box
    c = img.crop(box).resize((int((x1 - x0) * k), int((y1 - y0) * k)), Image.LANCZOS)
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
    if zlab:
        for y in range(200, y1, 50):
            if y <= y0: continue
            Y = (y - y0) * k
            dt.line([(0, Y), (10, Y)], fill=(80, 80, 80), width=2)
            dt.text((c.width - 46, Y - 10), "z%d" % Z(y), fill=(80, 80, 80), font=fs)
    return c


k = 1.8
a = panel(im, (0, 180, 240, 540), k, FRONT)
b = panel(im, (1340, 180, 1510, 540), k, REAR)
m1 = panel(mn, (150, 300, 420, 900), 1.08, MAINR, zlab=False)
m2 = panel(mn, (640, 330, 1000, 900), 1.08, MAINL, zlab=False)
LEG = [("양산형 윤곽 읽기 r3 — 팔", None, ft),
       ("왼쪽부터: 삼면도 정면 오른팔 · 뒤 오른팔 · 메인 오른팔 · 메인 왼팔", (90, 90, 90), fs),
       ("초록 = 만든다 · 청록 = 관절(짙은) · 보라 = 질문 · 빨강 = 뺌(무장)", (60, 60, 60), fs), ("", None, fs),
       ("A1 위팔: 짧은 올리브 상자(z214~196), 앞에 볼트 덧판", G, fs),
       ("    어깨 장갑 밑에 반쯤 숨음 · 가운데 X ≈ ±44", G, fs),
       ("A2 팔꿈치: 짙은 가로 원통 2겹(경첩) — z196~186", C, fs),
       ("A3 아래팔: 올리브 상자, 위가 넓고 아래로 좁아짐(z186~163)", G, fs),
       ("    앞 비스듬한 덧판 · 바깥 아래 모서리 깎음 · 위팔보다 굵음", G, fs),
       ("A4 손목: 짙은 마디 띠(z163~152)", C, fs),
       ("A5 주먹: 짙은 쇠 큰 주먹(z152~131) — 골반 높이까지", G, fs), ("", None, fs),
       ("W 라이플 · I1 왼팔뚝 방패 = 뺌(무장 제외, 결정 11-02)", R, fs),
       ("    → 왼팔 = 오른팔 거울(맨팔)", R, fs), ("", None, fs),
       ("질문 ① A2b 팔꿈치 바깥 둥근 원반(메인 그림) — 넣음?", P, fs),
       ("   그림에선 팔꿈치 안쪽(몸 쪽) 끝 → 제안: 넣음(관절 원통 끝 덮개, 양 끝)", P, fs),
       ("질문 ② 주먹: 쥔 주먹 / 편 손? 무장 없이 쉬는 자세라", P, fs),
       ("   제안: 반쯤 쥔 주먹(무장 쥘 자리, 나중에 무기 넣기 쉬움)", P, fs),
       ("질문 ③ 팔 크기: 어깨처럼 ×1.0(줄이지 않음)?", P, fs),
       ("   제안: ×1.0 — 몸통만 0.88, 팔·어깨는 그림 그대로", P, fs),
       ("질문 ④ 팔 길이: 주먹 아래 끝 z131(고관절 z155 보다 아래)", P, fs),
       ("   그림 그대로 둘지(긴 팔 = 육중함)", P, fs)]
top = [a, b, m1, m2]
lw = 600
W = sum(i.width for i in top) + 50 + lw
H = max(max(i.height for i in top), 26 * len(LEG) + 40) + 20
out = Image.new("RGB", (W, H), (255, 255, 255)); d = ImageDraw.Draw(out)
x = 10
for p in top:
    out.paste(p, (x, 10)); x += p.width + 10
y = 14; x += 10
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 26
out.save(OUT); print(OUT, out.size)
