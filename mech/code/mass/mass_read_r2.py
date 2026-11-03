"""양산형 윤곽 읽기 r2 — 어깨(삼면도 정면·옆·뒤 + 메인). 다각형 = 원본 픽셀(삼면도 1536×1024 / 메인 1024×1536).
z = (925 − y) × 0.295 (삼면도). 쓰기: python3 mass_read_r2.py <삼면도.png> <메인.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, MAIN, OUT = sys.argv[1:4]
im = Image.open(SRC).convert("RGB"); mn = Image.open(MAIN).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, P, B, R, C = (20, 140, 60), (130, 70, 200), (30, 40, 200), (210, 30, 30), (0, 150, 170)
Z = lambda y: round((925 - y) * 0.295)
E = lambda cx, cy, rx, ry: ("e", cx, cy, rx, ry)
# S1 오른 어깨 장갑 · S2 왼 어깨 방패판 · S3 어깨 관절 원통 · S4 판 받침대(판과 몸 사이 짙은) · S5 원통 4(뺌) · U 위팔(팔 단계)
FRONT = [
    ("S1", G, [(105, 102), (175, 105), (181, 160), (162, 196), (86, 191), (82, 130)], (40, 100)),
    ("S3", C, E(172, 170, 11, 38), (140, 215)),
    ("S3", C, E(372, 170, 11, 38), (350, 215)),
    ("S2", P, [(394, 62), (420, 45), (462, 50), (490, 80), (516, 207), (456, 238), (410, 196)], (430, 245)),
    ("S4?", P, [(380, 70), (398, 62), (410, 196), (388, 205)], (345, 60)),
    ("S5", R, [(482, 75), (545, 75), (545, 205), (482, 205)], (520, 60)),
    ("U", (120, 120, 120), [(90, 196), (160, 196), (160, 265), (90, 265)], (60, 270)),
    ("U", (120, 120, 120), [(405, 225), (478, 225), (478, 290), (405, 290)], (420, 295)),
]
SIDE = [   # 기체 왼쪽면(앞 = 그림 왼쪽)
    ("S2", P, [(700, 56), (746, 47), (800, 60), (806, 190), (786, 240), (722, 246), (694, 182)], (700, 255)),
    ("S5", R, [(800, 60), (880, 60), (880, 215), (800, 215)], (850, 225)),
]
REAR = [   # 그림 왼쪽 = 기체 왼쪽
    ("S2", P, [(1060, 60), (1112, 45), (1140, 70), (1142, 200), (1100, 240), (1048, 215), (1042, 110)], (1060, 250)),
    ("S5", R, [(1020, 70), (1065, 70), (1065, 190), (1020, 190)], (1000, 50)),
    ("S1", G, [(1355, 112), (1405, 100), (1440, 125), (1447, 175), (1425, 195), (1365, 190)], (1400, 205)),
]
MAINP = [
    ("S1", G, [(232, 180), (330, 168), (376, 210), (370, 300), (300, 312), (226, 290)], (226, 320)),
    ("S2", P, [(684, 75), (760, 60), (840, 90), (895, 330), (850, 370), (720, 360), (672, 160)], (700, 380)),
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
        for y in range(50, y1, 50):
            if y <= y0: continue
            Y = (y - y0) * k
            dt.line([(0, Y), (10, Y)], fill=(80, 80, 80), width=2)
            dt.text((c.width - 46, Y - 10), "z%d" % Z(y), fill=(80, 80, 80), font=fs)
    return c


a = panel(im, (20, 20, 570, 320), 1.6, FRONT)
b = panel(im, (600, 20, 920, 320), 1.6, SIDE)
c = panel(im, (980, 20, 1500, 320), 1.6, REAR)
m = panel(mn, (180, 40, 980, 440), 1.2, MAINP, zlab=False)
LEG = [("양산형 윤곽 읽기 r2 — 어깨", None, ft),
       ("위: 삼면도 정면(기체 오른쪽 = 그림 왼쪽) · 옆(기체 왼쪽면) · 뒤 / 아래: 메인 3/4", (90, 90, 90), fs),
       ("초록 = 만든다 · 청록 = 관절 · 보라 = 질문 · 빨강 = 뺌(결정) · 회색 = 다음 단계(팔)", (60, 60, 60), fs), ("", None, fs),
       ("S1 오른 어깨 장갑: 관절 위를 덮는 각진 상자, 앞에서 모서리 깎은 육각", G, fs),
       ("    윗면 거의 평평 · 바깥 아래 모서리 크게 깎음 · 경고 데칼 자리", G, fs),
       ("S2 왼 어깨 방패판: 짙은 쇠 회색 세로 육각 판(위 z259 → 아래 z203, 앞뒤 약 49칸)", P, fs),
       ("    \"03\" = 데칼 · 판 두께 약 3~4칸 + 모서리 깎음", P, fs),
       ("S3 어깨 관절 원통(짙은, 가슴과 팔 사이) — 양쪽", C, fs),
       ("S4 판 받침대: 판과 몸 사이 짙은 구조(브래킷)", P, fs),
       ("S5 원통 4 = 뺌(결정 11-02)", R, fs), ("", None, fs),
       ("질문 ① S2 방향: 그림마다 다름", P, fs),
       ("   옆모습 = 판을 정면으로 봄(옆을 향함) / 정면·메인 = 앞에서도 넓게 보임", P, fs),
       ("   제안: 바깥을 향하되 앞쪽으로 약 30° 돌림(앞에서도 판이 보이게) [판단]", P, fs),
       ("질문 ② S2 아래에 오른쪽 같은 어깨 장갑이 따로 있나?", P, fs),
       ("   그림엔 판 뒤 짙은 받침대(S4)만 보임 → 제안: 판 + 받침대만", P, fs),
       ("질문 ③ S2 가 어깨와 함께 움직이나(팔 들면 같이) / 몸통에 고정?", P, fs),
       ("   제안: 어깨(ShoulderL) 파트에 붙임 = 팔 들면 같이 [판단]", P, fs),
       ("질문 ④ S1·S2 크기는 ×1.0(그림 그대로)? 몸 폭은 ×0.88 이라", P, fs),
       ("   어깨까지 줄이면 판 존재감이 약해짐 → 제안: 어깨는 ×1.0", P, fs)]
top = [a, b, c]
W = max(sum(i.width for i in top) + 40, m.width + 620)
H = max(i.height for i in top) + max(m.height, 24 * len(LEG) + 40) + 40
out = Image.new("RGB", (W, H), (255, 255, 255)); d = ImageDraw.Draw(out)
x = 10
for p in top:
    out.paste(p, (x, 10)); x += p.width + 10
y0 = max(i.height for i in top) + 30
out.paste(m, (10, y0))
y = y0 + 4; x = m.width + 30
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 32 if fo is ft else 24
out.save(OUT); print(OUT, out.size)
