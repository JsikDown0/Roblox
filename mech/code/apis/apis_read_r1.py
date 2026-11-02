"""APIS 윤곽 읽기 r1 — 부품 지도(삼면도 앞·옆). 다각형 = 원본 픽셀(1536×1024). z = (950 − y) × 0.319 (머리 꼭대기 y136 → z260)."""
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, OUT = sys.argv[1], sys.argv[2]
im = Image.open(SRC).convert("RGB")
F = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, O, P, B, R, C = (20, 140, 60), (220, 120, 0), (130, 70, 200), (30, 40, 200), (210, 30, 30), (0, 160, 170)
Z = lambda y: round((950 - y) * 0.319)
R_ = lambda x0, y0, x1, y1: [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
FRONT = [   # [실측] 몸 가운데 x≈276(배 코어 257~292 · 바이저 254~300), 발바닥 y≈950
    ("A", G, R_(236, 136, 318, 232), (322, 140)),
    ("A1", C, R_(254, 204, 300, 223), (180, 200)),
    ("B", G, R_(205, 240, 347, 340), (210, 300)),
    ("B1?", P, ("e", 330, 268, 12, 11), (340, 245)),
    ("C", C, R_(255, 378, 294, 404), (300, 380)),
    ("D", G, R_(62, 175, 180, 300), (66, 180)),
    ("D", G, R_(372, 175, 490, 300), (440, 180)),
    ("E", G, R_(30, 330, 130, 490), (36, 335)),
    ("E", G, R_(420, 330, 515, 490), (470, 335)),
    ("E1", O, R_(32, 490, 105, 600), (36, 602)),
    ("E1", O, R_(440, 490, 512, 600), (460, 602)),
    ("F", G, R_(252, 430, 296, 510), (256, 515)),
    ("G", G, R_(112, 440, 248, 592), (118, 448)),
    ("G", G, R_(302, 440, 432, 592), (380, 448)),
    ("H", G, R_(100, 592, 232, 750), (104, 600)),
    ("H", G, R_(305, 592, 440, 750), (400, 600)),
    ("I", G, R_(90, 750, 236, 892), (94, 760)),
    ("I", G, R_(300, 750, 452, 892), (410, 760)),
    ("J", G, R_(43, 892, 236, 952), (60, 900)),
    ("J", G, R_(300, 892, 487, 952), (420, 900)),
    ("K", C, R_(58, 160, 112, 262), (8, 160)),
    ("K", B, R_(118, 110, 200, 200), (150, 92)),
    ("K2?", P, ("l", [(140, 58), (140, 150)]), (100, 50)),
    ("L", O, ("l", [(350, 160), (415, 90), (470, 95), (505, 140), (505, 230)]), (440, 60)),
    ("L1", O, R_(455, 240, 535, 292), (470, 296)),
]
SIDE = [   # 옆(앞 = 그림 왼쪽)
    ("A", G, R_(615, 140, 712, 235), (575, 140)),
    ("K", C, R_(735, 150, 810, 370), (815, 330)),
    ("L", O, ("l", [(775, 150), (812, 70), (862, 58), (905, 110), (920, 190)]), (870, 30)),
    ("L1", O, R_(880, 215, 965, 275), (900, 280)),
    ("M?", P, R_(700, 410, 765, 570), (640, 480)),
    ("M?", P, ("l", [(795, 370), (805, 490), (765, 570), (706, 575)]), (810, 480)),
    ("E", G, R_(640, 320, 740, 520), (585, 330)),
]


def panel(box, k, parts):
    x0, y0, x1, y1 = box
    c = im.crop(box).resize((int((x1 - x0) * k), int((y1 - y0) * k)), Image.LANCZOS)
    c = Image.blend(c, Image.new("RGB", c.size, (255, 255, 255)), 0.3)
    ov = Image.new("RGBA", c.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    T = lambda p: ((p[0] - x0) * k, (p[1] - y0) * k)
    for lab, col, g, tp in parts:
        if isinstance(g, tuple) and g[0] == "e":
            _, cx, cy, rx, ry = g
            d.ellipse([T((cx - rx, cy - ry)), T((cx + rx, cy + ry))], outline=col + (255,), width=3, fill=col + (40,))
        elif isinstance(g, tuple):
            d.line([T(p) for p in g[1]], fill=col + (255,), width=5)
        else:
            d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (40,), width=3)
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in parts:
        q = T(tp); w = dt.textlength(lab, font=f)
        q = (min(max(q[0], 2), c.width - w - 6), min(max(q[1], 2), c.height - 26))
        dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 23], fill=(255, 255, 255), outline=col, width=2)
        dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    for y in range((y0 // 100 + 1) * 100, y1, 100):
        Y = (y - y0) * k
        dt.text((c.width - 50, Y - 10), "z%d" % Z(y), fill=(90, 90, 90), font=fs)
    return c


a = panel((0, 0, 500, 960), 0.95, FRONT)
b = panel((560, 0, 1000, 960), 0.95, SIDE)
LEG = [("APIS 윤곽 읽기 r1 — 부품 지도", None, ft), ("1순위 = 삼면도(앞·옆·뒤) · 수리 장면 = 토치·자세 참고", (90, 90, 90), fs),
       ("z = (950 − y) × 0.319 · 머리 꼭대기 y136 → z260", (90, 90, 90), fs), ("", None, fs),
       ("A 헬멧(노랑 둥근 투구) · A1 청록 바이저(발광)", G, fs), ("B 흰 가슴판 + 노랑 위 띠", G, fs),
       ("C 배 청록 코어(발광) + 양옆 노랑 블록", C, fs), ("D 큰 어깨 덮개(흰+노랑)", G, fs),
       ("E 굵은 팔뚝 · E1 큰 손(빈손 = 토치는 손에 듦 결정)", G, fs), ("F 흰 샅판 · G 허벅지 · H 무릎(짙은 관절 + 흰 판)", G, fs),
       ("I 정강이(노랑+흰) · J 굵은 장화(노랑+검정 밑창)", G, fs), ("K 백팩: 청록 유리 탱크(발광) + 짙은 상자", C, fs),
       ("L 크레인 팔(기체 왼쪽, 한쪽만 결정) · L1 수리 상자", O, fs), ("   어깨 위로 솟아 뒤·바깥으로 휘어 상자를 매닮", O, fs),
       ("", None, fs), ("다리 비율: 샅 y510 → z140 = 키의 54%", (20, 20, 20), fs),
       ("(FELSEN 51 · SKADI 57 · CETUS 54)", (90, 90, 90), fs), ("", None, fs),
       ("질문(보라 = 불확실)", None, f),
       ("1. M? 옆모습 엉덩이 뒤 짙은 상자 + 백팩에서 내려온 호스", P, fs),
       ("   = 토치 연료통으로 보고, 토치는 오른손(크레인 반대)", P, fs),
       ("   에 들고 호스로 이 통에 연결 — 맞나?", P, fs),
       ("2. K2? 백팩 위 긴 안테나(앞에서 왼쪽 1, 옆 1)", P, fs),
       ("   넣을까? 제안: 하나만, 짧게", P, fs),
       ("3. B1? 가슴 노랑 ▲ 표시 → 무늬 대신 데칼 자리", P, fs),
       ("4. 발광(청록): 바이저 · 배 코어 · 등 탱크 3곳 모두?", P, fs),
       ("   제안: 모두(발광 늘리기 결정) — 크레인 마디 점등은 뺌", P, fs)]
W = a.width + b.width + 560
H = max(a.height, 40 + 29 * len(LEG))
sh = Image.new("RGB", (W, H), (250, 250, 250)); d = ImageDraw.Draw(sh)
sh.paste(a, (0, 0)); sh.paste(b, (a.width + 10, 0))
y = 10; x = a.width + b.width + 24
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 28
sh.save(OUT); print(sh.size)
