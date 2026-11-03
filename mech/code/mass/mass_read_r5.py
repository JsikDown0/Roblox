"""양산형 윤곽 읽기 r5 — 기본형 무장(라이플 + 소형 방패). 메인 그림(1024×1536, 0.177칸/px) 기준.
쓰기: python3 mass_read_r5.py <메인.png> <출력.png>"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
MAIN, OUT = sys.argv[1:3]
mn = Image.open(MAIN).convert("RGB")
F = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
f = ImageFont.truetype(F, 18); fs = ImageFont.truetype(F, 16); ft = ImageFont.truetype(F, 26)
G, P, B, C = (20, 140, 60), (130, 70, 200), (30, 40, 200), (0, 150, 170)
RIFLE = [   # 메인 그림 픽셀(총이 비스듬히 아래·앞)
    ("R1 개머리", G, [(205, 505), (240, 515), (232, 580), (200, 572)], (245, 520)),
    ("R2 몸통 + 올리브 옆판", G, [(150, 560), (230, 585), (200, 760), (120, 740)], (235, 650)),
    ("R3 위 레일·조준기", G, [(150, 545), (180, 552), (120, 740), (95, 732)], (20, 600)),
    ("R4 탄창", G, [(190, 760), (240, 770), (225, 820), (178, 808)], (245, 780)),
    ("R5 앞 손잡이·총열 덮개", G, [(100, 745), (185, 765), (150, 890), (70, 875)], (190, 840)),
    ("R6 총열 + 소염기", G, [(68, 880), (105, 888), (80, 1045), (42, 1040)], (110, 960)),
    ("D 노랑 줄·\"3Smm\" = 데칼", B, [(130, 780), (165, 790), (150, 860), (115, 850)], (10, 900)),
]
SHIELD = [
    ("S 방패(컨셉: 팔꿈치 ~ 무릎, 약 88칸)", P, [(850, 395), (970, 420), (985, 760), (945, 875), (870, 885), (838, 820)], (700, 900)),
    ("S1 팔 쪽 받침(경첩·잠금)", G, [(840, 520), (870, 520), (872, 760), (842, 760)], (700, 640)),
]


def panel(img, box, k, parts):
    x0, y0, x1, y1 = box
    c = img.crop(box).resize((int((x1 - x0) * k), int((y1 - y0) * k)), Image.LANCZOS)
    c = Image.blend(c, Image.new("RGB", c.size, (255, 255, 255)), 0.25)
    ov = Image.new("RGBA", c.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    T = lambda p: ((p[0] - x0) * k, (p[1] - y0) * k)
    for lab, col, g, tp in parts:
        d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (40,), width=3)
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in parts:
        q = T(tp); w = dt.textlength(lab, font=f)
        q = (min(max(q[0], 2), c.width - w - 6), min(max(q[1], 2), c.height - 26))
        dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 23], fill=(255, 255, 255), outline=col, width=2)
        dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    return c


a = panel(mn, (0, 480, 330, 1080), 1.1, RIFLE)
b = panel(mn, (680, 360, 1024, 940), 1.1, SHIELD)
LEG = [("양산형 윤곽 읽기 r5 — 기본형 무장", None, ft),
       ("메인 그림 기준 · 0.177칸/px(키 266칸) · 결정 8-1: 출시 무장 고정 = 라이플 + 소형 방패", (90, 90, 90), fs), ("", None, fs),
       ("라이플: R1 개머리 · R2 몸통(짙은 쇠 + 올리브 옆판) · R3 위 레일·조준기", G, fs),
       ("  R4 탄창 · R5 앞 손잡이·총열 덮개(위 레일 이어짐) · R6 총열 + 소염기", G, fs),
       ("  [실측] 길이 약 538px → 약 95칸 = 키의 0.36(FELSEN 라이플 0.39, AELLO 0.43)", G, fs),
       ("방패: 컨셉은 왼 아래팔 바깥에 큰 세로 육각 판(약 88칸, 팔꿈치 ~ 무릎)", P, fs),
       ("  짙은 쇠 회색 + 노랑 줄(데칼) · 팔 쪽 받침(S1)", P, fs), ("", None, fs),
       ("질문 ① 라이플 길이 95칸(그림 그대로)?", P, fs),
       ("질문 ② '소형' 방패 크기", P, fs),
       ("   a 약 50칸(아래팔 + 주먹을 덮는 정도) / b 약 65칸(팔꿈치 ~ 허벅지 중간)", P, fs),
       ("   제안: a — 왼 어깨에 큰 방패판이 이미 있어 왼쪽이 무거워지지 않게", P, fs),
       ("질문 ③ 방패 모양: 컨셉처럼 세로 육각(어깨판과 같은 문법)?", P, fs),
       ("질문 ④ 라이플 수납(근접 때·바리에이션 공통 규약 RifleStowed)", P, fs),
       ("   등은 노즐·호스·어깨판이라 FELSEN 식 허리 뒤 가로는 노즐과 겹침", P, fs),
       ("   제안: 오른 허벅지 바깥 세로(총구 아래) — 오른쪽은 방패가 없어 비어 있음", P, fs),
       ("질문 ⑤ 근접 무기: 지금 공통 근접(빔사벨)을 쓸지 / 방패 치기?", P, fs),
       ("   제안: 방패 치기(밀쳐내기) — 칼집 자리가 필요 없고 양산형다움", P, fs)]
lw = 640
W = a.width + b.width + 40 + lw
H = max(a.height, b.height, 26 * len(LEG) + 40) + 20
out = Image.new("RGB", (W, H), (255, 255, 255)); d = ImageDraw.Draw(out)
out.paste(a, (10, 10)); out.paste(b, (a.width + 20, 10))
y = 14; x = a.width + b.width + 40
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 26
out.save(OUT); print(OUT, out.size)
