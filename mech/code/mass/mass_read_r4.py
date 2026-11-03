"""양산형 윤곽 읽기 r4 — 하체(삼면도 정면·옆·뒤 + 메인). z = (925 − y) × 0.295.
쓰기: python3 mass_read_r4.py <삼면도.png> <메인.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, MAIN, OUT = sys.argv[1:4]
im = Image.open(SRC).convert("RGB"); mn = Image.open(MAIN).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, P, B, C = (20, 140, 60), (130, 70, 200), (30, 40, 200), (0, 150, 170)
Z = lambda y: round((925 - y) * 0.295)
E = lambda cx, cy, rx, ry: ("e", cx, cy, rx, ry)
FRONT = [   # 기체 오른다리 = 그림 왼쪽
    ("P1", G, [(228, 330), (322, 330), (330, 395), (300, 420), (250, 420), (220, 395)], (230, 300)),
    ("P2", P, E(275, 450, 16, 18), (300, 445)),
    ("H", G, [(140, 330), (225, 330), (228, 385), (150, 385)], (100, 330)),
    ("T", G, [(135, 385), (245, 390), (240, 495), (140, 500)], (95, 420)),
    ("T1", B, [(160, 410), (230, 410), (228, 470), (162, 470)], (165, 480)),
    ("K", G, [(120, 500), (195, 495), (205, 545), (195, 610), (120, 610), (112, 560)], (70, 520)),
    ("K1", P, E(218, 555, 17, 25), (230, 520)),
    ("S", G, [(110, 610), (235, 610), (240, 700), (225, 760), (100, 760), (100, 680)], (60, 650)),
    ("S1", P, [(140, 620), (172, 620), (172, 725), (140, 725)], (180, 680)),
    ("A", G, [(110, 760), (230, 760), (225, 800), (115, 800)], (60, 770)),
    ("F", P, [(95, 810), (215, 805), (220, 925), (95, 925)], (60, 860)),
]
SIDE = [    # 기체 왼쪽면, 앞 = 그림 왼쪽
    ("T", G, [(640, 400), (790, 400), (795, 500), (650, 505)], (800, 440)),
    ("K", G, [(645, 505), (735, 510), (740, 610), (660, 615), (640, 560)], (595, 540)),
    ("K1", P, E(762, 548, 30, 30), (800, 520)),
    ("S", G, [(690, 610), (830, 600), (840, 700), (820, 760), (700, 765), (685, 690)], (850, 650)),
    ("F", P, [(615, 900), (660, 840), (760, 800), (845, 800), (875, 870), (875, 925), (615, 925)], (600, 870)),
]
REAR = [    # 그림 왼쪽 = 기체 왼쪽
    ("T", G, [(1110, 380), (1235, 380), (1230, 500), (1115, 505)], (1060, 400)),
    ("S2", P, [(1130, 625), (1165, 625), (1170, 700), (1135, 700)], (1060, 660)),
    ("H2", B, [(1100, 800), (1190, 800), (1190, 905), (1100, 905)], (1060, 850)),
]
MAINP = [
    ("K1", P, E(425, 900, 35, 40), (470, 870)),
    ("S1", P, [(715, 1040), (780, 1040), (785, 1210), (720, 1210)], (800, 1120)),
    ("F", P, [(700, 1355), (900, 1355), (910, 1500), (695, 1500)], (720, 1300)),
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
        for y in range(350, y1, 50):
            if y <= y0: continue
            Y = (y - y0) * k
            dt.line([(0, Y), (10, Y)], fill=(80, 80, 80), width=2)
            dt.text((c.width - 46, Y - 10), "z%d" % Z(y), fill=(80, 80, 80), font=fs)
    return c


k = 1.0
a = panel(im, (60, 300, 480, 935), k, FRONT)
b = panel(im, (580, 300, 900, 935), k, SIDE)
c = panel(im, (1040, 300, 1460, 935), k, REAR)
m = panel(mn, (240, 600, 960, 1520), 635 / 920, MAINP, zlab=False)
LEG = [("양산형 윤곽 읽기 r4 — 하체", None, ft),
       ("정면(기체 오른다리) · 옆(왼쪽면) · 뒤 · 메인 오른다리 쪽", (90, 90, 90), fs),
       ("초록 = 만든다 · 보라 = 질문 · 파랑 = 데칼 자리", (60, 60, 60), fs), ("", None, fs),
       ("P1 샅판(올리브, 가운데 둥근 구멍) z175~149", G, fs),
       ("H 골반 옆 장갑 · T 허벅지 장갑(큰 올리브 상자)", G, fs),
       ("    정면 |X| 8~42, z149~125 · 옆 앞뒤 약 45칸", G, fs),
       ("T1 허벅지 앞 = R-03 / 경고 삼각 데칼 자리", B, fs),
       ("K 무릎판: 짙은 쇠 회색 육각(z126~93), 경고 줄 = 데칼", G, fs),
       ("S 정강이: 올리브, 아래로 벌어짐(z93~49), 바깥 판 R-03 데칼", G, fs),
       ("A 발목 띠 + 짙은 기계부(z49~37)", G, fs),
       ("H2 뒤꿈치 블록 = 경고 줄 데칼 자리", B, fs), ("", None, fs),
       ("질문 ① K1 무릎 둥근 관절(옆·안쪽으로 보임)", P, fs),
       ("   팔꿈치처럼 다리 폭 안 2축 경첩(너클 + 직사각 블록)?", P, fs),
       ("   제안: 그렇게 — 옆에서 둥근 너클만 보임", P, fs),
       ("질문 ② S1 정강이 앞 드러난 피스톤(강철 + 노랑 띠)", P, fs),
       ("   제안: 넣음 — 판 사이 홈 속(돌출 없이)", P, fs),
       ("질문 ③ S2 종아리 뒤 세로 통풍 격자(게임 카메라 쪽)", P, fs),
       ("   제안: 넣음(등 격자와 같은 문법)", P, fs),
       ("질문 ④ F 발: 메인은 발끝 두 갈래", P, fs),
       ("   결정 11-02 '한 덩어리' → 가운데 홈만, 길이 그림대로(77칸)?", P, fs),
       ("질문 ⑤ P2 샅 아래 고리(가슴 고리와 같은 견인 고리): 넣음?", P, fs),
       ("질문 ⑥ 다리 폭: ×1.0(팔·어깨처럼) / ×0.88(몸통처럼)?", P, fs),
       ("   제안: ×1.0 — 무거운 다리 + 좁은 허리 대비(육중함)", P, fs)]
top = [a, b, c, m]
lw = 560
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
