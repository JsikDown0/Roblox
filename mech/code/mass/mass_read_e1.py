"""BISON 공병형(ST-10E) 윤곽 읽기 e1 — 장비 컨테이너 + 크레인(컨셉 = 레퍼런스/양산형/공병형/concept_e1_컨테이너.png 1536×1024).
쓰기: python3 mass_read_e1.py <컨셉.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
SRC, OUT = sys.argv[1:3]
im = Image.open(SRC).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, P, R, B = (20, 140, 60), (130, 70, 200), (210, 30, 30), (30, 40, 200)
PARTS = [
    ("C1 상자(바깥 면 = 기체 뒤)", G, [(22, 182), (232, 182), (232, 505), (22, 505)], (30, 520)),
    ("C2 둘레 짙은 테·모서리 보강", G, [(10, 180), (22, 180), (22, 505), (10, 505)], (10, 150)),
    ("C3 잠금쇠 2(아래)", G, [(55, 395), (95, 395), (95, 470), (55, 470)], (60, 475)),
    ("C4 옆 손잡이", G, [(228, 260), (245, 260), (245, 380), (228, 380)], (250, 300)),
    ("X 고리 2 = 뺌", R, [(40, 155), (70, 155), (70, 185), (40, 185)], (40, 120)),
    ("X", R, [(185, 155), (215, 155), (215, 185), (185, 185)], (190, 120)),
    ("D 데칼 ENG-04", B, [(80, 270), (180, 270), (180, 310), (80, 310)], (90, 320)),
    ("C5 뒤 면 두 짝 문(이음매·경첩)", G, [(440, 182), (650, 182), (650, 505), (440, 505)], (450, 520)),
    ("K1 받침(경첩 받침대)", G, [(875, 330), (1000, 330), (1000, 435), (875, 435)], (880, 445)),
    ("K2 붐(각진, 2마디)", G, [(905, 190), (1170, 100), (1190, 160), (960, 260), (930, 340)], (950, 70)),
    ("K3 유압 실린더 2(크롬)", P, [(930, 230), (980, 230), (1010, 360), (960, 360)], (1010, 300)),
    ("K4 두 갈래 집게", G, [(1060, 210), (1175, 210), (1175, 340), (1060, 340)], (1085, 350)),
    ("M 장착: 등 전체 · 노즐 아래 · 크레인 오른 어깨 위 앞으로", G, [(1100, 470), (1345, 470), (1345, 770), (1100, 770)], (870, 790)),
]
c = im.copy(); ov = Image.new("RGBA", c.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
for lab, col, g, tp in PARTS:
    d.polygon(g, outline=col + (255,), fill=col + (35,), width=3)
c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
for lab, col, g, tp in PARTS:
    w = dt.textlength(lab, font=f)
    dt.rectangle([tp[0] - 3, tp[1] - 2, tp[0] + w + 3, tp[1] + 23], fill=(255, 255, 255), outline=col, width=2)
    dt.text(tp, lab, fill=col, font=f)
LEG = [("BISON 공병형(ST-10E) 윤곽 읽기 e1 — 장비 컨테이너 + 크레인", None, ft),
       ("[결정 11-04] 고양이 귀 같은 위 고리 2 = 뺌 · 백팩 색이 본체 올리브와 너무 겹침 → 손봄", (90, 90, 90), fs), ("", None, fs),
       ("그림 비율: 상자 높이 : 폭 : 두께 ≈ 1 : 0.65 : 0.38 · 모서리 짙은 테 + 각진 보강", G, fs),
       ("질문 ① 크기: 높이 64 · 폭 48(등 상자 폭) · 두께 22칸 (z 188~252)?", P, fs),
       ("   그림 비율(폭 0.65)대로면 폭 42 — 등보다 좁아 노즐 옆이 보임", P, fs),
       ("질문 ② 상자 색(본체 올리브와 구분, 강조색은 노랑 하나 유지) — 시안 3안으로", P, fs),
       ("   a 짙은 쇠 회색(2) 몸 + 올리브 문  b 모래·카키 새 색(150,136,100)  c 짙은 올리브(70,74,58)", P, fs),
       ("질문 ③ 크레인: 받침 = 상자 위 오른쪽, 붐 2마디(위로 → 앞으로 꺾임) +", P, fs),
       ("   크롬 실린더 2 · 집게 = 오른 어깨 앞 위(z≈250) — 머리 옆을 지나감", P, fs),
       ("질문 ④ 잔 디테일: 잠금쇠·손잡이·문 이음매·경첩은 2칸 이상 굵기로 넣고 볼트는 뺌?", P, fs),
       ("질문 ⑤ 노즐: 상자 바닥(z188)이 노즐 위 끝(z218)보다 위? → 상자 z 220~280 은 머리보다 높음", P, fs),
       ("   제안: 상자 z 200~258 + 바닥에 노즐 반원 홈 2(노즐 윗부분을 감쌈)", P, fs)]
W = c.width + 760; H = max(c.height, 26 * len(LEG) + 40)
out = Image.new("RGB", (W, H), (255, 255, 255)); out.paste(c, (0, 0)); d2 = ImageDraw.Draw(out)
y = 14; x = c.width + 16
for t, col, fo in LEG:
    d2.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 26
out.save(OUT); print(OUT, out.size)
