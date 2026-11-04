"""새 표준 양산기 ST-10(이름 미정) 윤곽 읽기 r1 — 부품 지도. 삼면도 1536×1024.
[실측] 정면 머리 꼭대기 y80 · 발바닥 y≈943 · 몸 가운데 x≈265(렌즈 x256~273) → z = (943 − y) × 0.301.
쓰기: python3 m2_read_r1.py <삼면도.png> <메인.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, MAIN, OUT = sys.argv[1:4]
im = Image.open(SRC).convert("RGB"); mn = Image.open(MAIN).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 17); fs = ImageFont.truetype(F, 15); ft = ImageFont.truetype(F, 26)
G, P, R, B, C = (20, 140, 60), (130, 70, 200), (210, 30, 30), (30, 40, 200), (0, 150, 170)
Z = lambda y: round((943 - y) * 0.301)
E = lambda cx, cy, rx, ry: ("e", cx, cy, rx, ry)
FRONT = [   # 그림 왼쪽 = 기체 오른쪽
    ("A 머리", G, [(208, 82), (322, 82), (326, 160), (205, 160)], (330, 85)),
    ("A1 렌즈", C, E(265, 123, 10, 10), (282, 100)),
    ("B 흉판", G, [(150, 140), (352, 140), (350, 260), (320, 300), (205, 300), (152, 260)], (205, 305)),
    ("B1", B, [(275, 215), (305, 215), (290, 280), (262, 280)], (310, 240)),
    ("S1 오른 어깨", G, [(60, 160), (150, 155), (150, 255), (62, 255)], (5, 140)),
    ("S2 왼 어깨 돔", G, E(430, 190, 75, 100), (440, 300)),
    ("H 팔", G, [(45, 255), (140, 255), (135, 470), (55, 470)], (5, 360)),
    ("H", G, [(400, 255), (480, 255), (478, 470), (405, 470)], (480, 360)),
    ("W 허리·샅", G, [(150, 290), (350, 290), (330, 400), (225, 410), (170, 400)], (175, 410)),
    ("T 허벅지", G, [(150, 330), (262, 330), (255, 470), (155, 475)], (95, 440)),
    ("T", G, [(300, 330), (395, 330), (395, 470), (300, 475)], (400, 440)),
    ("K 무릎", G, [(110, 470), (220, 470), (225, 560), (110, 560)], (60, 500)),
    ("L 종아리", G, [(85, 530), (235, 530), (240, 760), (95, 760)], (35, 640)),
    ("F 발", G, [(30, 790), (215, 790), (215, 940), (30, 940)], (40, 945)),
    ("X 방패 = 뺌", R, [(415, 190), (520, 190), (520, 490), (420, 490)], (420, 500)),
    ("W2 라이플 → 돌격 소총", P, [(25, 270), (100, 270), (100, 720), (25, 720)], (5, 730)),
]
SIDE = [
    ("X 호스 = 뺌", R, [(645, 300), (700, 300), (700, 420), (645, 420)], (580, 290)),
    ("N 허리 상자 = 나이프 홀스터", P, [(700, 300), (760, 300), (760, 400), (700, 400)], (700, 410)),
]
MAINP = [
    ("X 호스 = 뺌", R, [(565, 450), (625, 450), (625, 600), (565, 600)], (470, 430)),
    ("N 홀스터(나이프 손잡이 위로)", P, [(615, 460), (700, 460), (700, 600), (615, 600)], (630, 610)),
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
            d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (35,), width=3)
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in parts:
        q = T(tp); w = dt.textlength(lab, font=f)
        q = (min(max(q[0], 2), c.width - w - 6), min(max(q[1], 2), c.height - 24))
        dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 21], fill=(255, 255, 255), outline=col, width=2)
        dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    if zlab:
        for y in range(100, y1, 100):
            if y <= y0: continue
            Y = (y - y0) * k
            dt.text((c.width - 44, Y - 9), "z%d" % Z(y), fill=(80, 80, 80), font=fs)
    return c


a = panel(im, (0, 70, 530, 950), 0.95, FRONT)
b = panel(im, (560, 70, 890, 950), 0.95, SIDE)
m = panel(mn, (430, 380, 760, 700), 1.3, MAINP, zlab=False)
LEG = [("새 표준 양산기 ST-10 윤곽 읽기 r1", None, ft),
       ("z = (943 − y) × 0.301 · 1순위 = 삼면도 정면(배치) + 메인(생김새)", (90, 90, 90), fs),
       ("[결정 11-04] 호스 뺌 · 주무장 돌격 소총 · 나이프 = 왼 허리 상자(홀스터) · 방패 뺌", (90, 90, 90), fs), ("", None, fs),
       ("A 작은 머리 + 둥근 렌즈 A1(청록 발광) · 양옆 귀 포드", G, fs),
       ("B 흉판(모래 큰 판 + 위 회색 띠) · B1 붉은 사선 = 데칼", G, fs),
       ("S1 오른 어깨 둥근 블록 · S2 왼 어깨 큰 돔(붉은 줄 = 데칼)", G, fs),
       ("H 팔 둥근 장갑 · W 허리 짙은 마디 + 모래 벨트 + 샅판", G, fs),
       ("T 불룩한 허벅지 · K 회색 무릎판 + 둥근 관절 · L 불룩한 종아리", G, fs),
       ("F 짙은 큰 발 + 모래 발끝 덮개", G, fs), ("", None, fs),
       ("질문 ① 둥근 면: 공 모양 그대로면 삼각형이 크게 늘어남(CETUS 4.5배)", P, fs),
       ("   → 팔각·45° 모서리로 깎은 다면체로 옮김(둥근 인상 유지)?", P, fs),
       ("질문 ② 색: 모래 (176,165,140)? · 짙은 회색 · 붉은 줄 데칼 · 렌즈 청록 발광", P, fs),
       ("   (BISON 은 주황 바이저 — 기체마다 강조색 하나)", P, fs),
       ("질문 ③ 체급: BISON(HT-10)보다 가볍게 — 폭 ×0.92 · 두께 그대로?", P, fs),
       ("질문 ④ 돌격 소총: 새로 디자인(BISON 라이플보다 짧은 불펍/카빈)?", P, fs),
       ("질문 ⑤ 나이프 홀스터: 허리 상자 위로 손잡이가 나옴(스트라이크 참고)", P, fs),
       ("   상자는 허벅지와 같이 움직이지 않게 골반에 고정?", P, fs)]
top = [a, b, m]
lw = 620
W = sum(i.width for i in top) + 40 + lw
H = max(max(i.height for i in top), 25 * len(LEG) + 40) + 20
out = Image.new("RGB", (W, H), (255, 255, 255)); d = ImageDraw.Draw(out)
x = 10
for p in top:
    out.paste(p, (x, 10)); x += p.width + 10
y = 14; x += 10
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 25
out.save(OUT); print(OUT, out.size)
