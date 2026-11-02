from PIL import Image, ImageDraw, ImageFont
import sys
SRC, OUT = sys.argv[1], sys.argv[2]
im = Image.open(SRC).convert("RGB")
F = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
f = ImageFont.truetype(F, 20); fs = ImageFont.truetype(F, 17); ft = ImageFont.truetype(F, 26)
GREEN, ORANGE, PURPLE, RED, BLUE = (20, 140, 60), (220, 120, 0), (130, 70, 200), (210, 30, 30), (30, 40, 200)
Z = lambda y: round((1228 - y) * 0.2407)

PARTS = [  # (기호, 색, 다각형 or ("ell", cx, cy, rx, ry) or ("line", pts), 글자 위치)
    ("W1", ORANGE, [(560, 497), (645, 497), (650, 560), (620, 568), (570, 566), (560, 540)], (652, 505)),
    ("W2", GREEN, [(572, 578), (622, 578), (628, 600), (625, 665), (578, 665), (572, 640)], (540, 600)),
    ("H?", PURPLE, ("line", [(470, 575), (500, 535), (560, 505)]), (455, 515)),
    ("H?", PURPLE, ("line", [(650, 512), (720, 500), (790, 522), (850, 562)]), (850, 520)),
    ("P", GREEN, ("ell", 662, 662, 72, 58), (610, 700)),
    ("T", GREEN, [(705, 668), (735, 628), (800, 612), (830, 620), (880, 640), (905, 700), (890, 760), (830, 772), (760, 762), (715, 722)], (885, 640)),
    ("T1", BLUE, [(712, 668), (738, 632), (800, 618), (810, 660), (800, 712), (760, 722), (718, 705)], (690, 610)),
    ("T", GREEN, [(425, 690), (440, 640), (470, 625), (540, 640), (560, 700), (545, 760), (480, 772), (430, 745)], (400, 650)),
    ("K", GREEN, [(745, 795), (772, 762), (860, 755), (895, 790), (905, 840), (870, 872), (770, 872), (745, 835)], (905, 800)),
    ("K1", ORANGE, [(772, 762), (860, 757), (870, 800), (855, 850), (785, 850), (775, 800)], (700, 765)),
    ("G1?", PURPLE, ("ell", 822, 792, 24, 19), (790, 815)),
    ("K", GREEN, [(368, 800), (385, 770), (440, 768), (500, 790), (505, 840), (470, 872), (380, 868)], (345, 830)),
    ("G1?", PURPLE, ("ell", 410, 795, 20, 16), (395, 812)),
    ("G2?", PURPLE, ("ell", 556, 875, 20, 36), (585, 860)),
    ("S", GREEN, [(795, 915), (860, 890), (990, 900), (1000, 975), (990, 1002), (900, 1008), (815, 1032), (793, 990)], (1005, 930)),
    ("S", GREEN, [(380, 930), (430, 918), (500, 905), (540, 935), (535, 1000), (490, 1012), (400, 1002), (375, 970)], (340, 945)),
    ("A", ORANGE, [(820, 1040), (880, 1012), (960, 1006), (1010, 1030), (1010, 1110), (820, 1110)], (1012, 1080)),
    ("G3?", PURPLE, ("ell", 930, 1060, 28, 28), (860, 1060)),
    ("G3?", PURPLE, ("ell", 345, 1045, 25, 25), (335, 995)),
    ("D", GREEN, ("ell", 766, 1110, 32, 62), (705, 1050)),
    ("D", GREEN, ("ell", 550, 1090, 50, 60), (555, 1025)),
    ("R", ORANGE, [(800, 1100), (830, 1100), (830, 1215), (800, 1215)], (770, 1180)),
    ("F", BLUE, [(845, 1240), (852, 1175), (900, 1140), (960, 1135), (1012, 1150), (1040, 1190), (1045, 1240)], (960, 1205)),
    ("F", BLUE, [(330, 1130), (380, 1150), (410, 1200), (400, 1245), (330, 1245)], (345, 1160)),
    ("B", GREEN, [(700, 1130), (760, 1125), (765, 1225), (700, 1225)], (705, 1195)),
    ("B", GREEN, [(1050, 1120), (1100, 1150), (1135, 1190), (1130, 1225), (1050, 1225)], (1080, 1160)),
    ("B", GREEN, [(560, 1100), (610, 1095), (665, 1150), (670, 1200), (560, 1200)], (610, 1160)),
    ("X?", RED, [(1000, 965), (1030, 970), (1050, 1020), (1050, 1100), (1020, 1100), (1010, 1030)], (1052, 985)),
]
AXES = [[(745, 650), (825, 815), (915, 1095)], [(515, 655), (440, 820), (420, 1080)]]


def panel(box, k):
    x0, y0, x1, y1 = box
    c = im.crop(box).resize((int((x1 - x0) * k), int((y1 - y0) * k)), Image.LANCZOS)
    c = Image.blend(c, Image.new("RGB", c.size, (255, 255, 255)), 0.25)
    ov = Image.new("RGBA", c.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov); dt = ImageDraw.Draw(c)
    T = lambda p: ((p[0] - x0) * k, (p[1] - y0) * k)
    for lab, col, g, tp in PARTS:
        if isinstance(g, tuple) and g[0] == "ell":
            _, cx, cy, rx, ry = g
            bb = [T((cx - rx, cy - ry)), T((cx + rx, cy + ry))]
            d.ellipse(bb, outline=col + (255,), width=3, fill=col + (40,))
        elif isinstance(g, tuple) and g[0] == "line":
            d.line([T(p) for p in g[1]], fill=col + (255,), width=5)
        else:
            d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (45,), width=3)
    for ax in AXES:
        d.line([T(p) for p in ax], fill=BLUE + (255,), width=3)
        for p in ax:
            q = T(p); d.ellipse([q[0] - 5, q[1] - 5, q[0] + 5, q[1] + 5], fill=BLUE + (255,))
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in PARTS:
        q = T(tp)
        if 0 <= q[0] < c.width - 10 and 0 <= q[1] < c.height - 10:
            w = dt.textlength(lab, font=f)
            dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 25], fill=(255, 255, 255), outline=col, width=2)
            dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    # z 눈금(오른쪽 끝)
    for y in range((y0 // 50 + 1) * 50, y1, 50):
        Y = (y - y0) * k
        dt.line([(c.width - 14, Y), (c.width, Y)], fill=(90, 90, 90), width=2)
        dt.text((c.width - 70, Y - 11), "z%d" % Z(y), fill=(90, 90, 90), font=fs)
    return c


a = panel((330, 470, 1060, 905), 1.25)
b = panel((320, 860, 1145, 1250), 1.1)
LEG = [
    ("하체 윤곽 읽기 r1", None, ft),
    ("1순위 = concept_v1_GPT_후보.png · z = (1228 − y) × 0.24", (90, 90, 90), fs),
    ("파란 선 = 다리 축(엉덩이→무릎→발목) 끝점", BLUE, fs),
    ("  기체 왼다리 (745,650)→(825,815)→(915,1095)", BLUE, fs),
    ("  기체 오른다리 (515,655)→(440,820)→(420,1080)", BLUE, fs),
    ("  → 쉬는 자세는 곧게 + 살짝 벌림(삼면도 뒤)", BLUE, fs),
    ("", None, fs),
    ("W1 허리 앞 황동 상자(가슴 밑, z160~176)", ORANGE, fs),
    ("W2 샅 청록 판(세로 직사각, z135~155)", GREEN, fs),
    ("P  엉덩이 관절 = 짙은 원반 덩어리(z≈139)", GREEN, fs),
    ("T  허벅지 청록 장갑(z113~148)", GREEN, fs),
    ("T1 허벅지 앞 회색 윗판(▲ 표시)", BLUE, fs),
    ("K  무릎 청록 방패(z86~113)", GREEN, fs),
    ("K1 무릎 위 황동 상자", ORANGE, fs),
    ("S  정강이 청록 판 + 아래 황동 테(z48~81)", GREEN, fs),
    ("A  발목 아치 띠(짙은 쇠 + 황동 테, z28~45)", ORANGE, fs),
    ("D  발목 옆 큰 원반(바퀴) — 양옆(삼면도)", GREEN, fs),
    ("R  발목 옆 세로 연결대(황동)", ORANGE, fs),
    ("F  발끝 둥근 덮개(밝은 회색, 잠수 장화)", BLUE, fs),
    ("B  발 옆·뒤 짙은 블록(넓게 받침)", GREEN, fs),
    ("", None, fs),
    ("질문(보라·빨강 = 불확실)", None, f),
    ("G1? 무릎 황동 상자 창 발광", PURPLE, fs),
    ("G2? 무릎 옆 쌍둥이 램프", PURPLE, fs),
    ("G3? 발목 앞 갓 씌운 램프", PURPLE, fs),
    ("  발광은 헬멧 창 + 가슴 코어만으로 정함 →", PURPLE, fs),
    ("  제안: G1·G3 = 색 8(궁극기 때만) · G2 뺌", PURPLE, fs),
    ("H?  허리 호스 띠(가슴 밑을 가로지르는 관)", PURPLE, fs),
    ("  제안: 1줄만", PURPLE, fs),
    ("T1 ▲ 표시: 그린 무늬 대신 빼기 제안", BLUE, fs),
    ("색: T1 회색판 (109,98,93) → 강철 7?", BLUE, fs),
    ("    F 발끝 (170,153,142) → 뼈색 2 / 강철 7?", BLUE, fs),
    ("X?  발목 뒤 굽은 지느러미 + 주황 빛", RED, fs),
    ("  흐려서 정체 불명 → 안 만들고 물음", RED, fs),
]
LW = 520
H = max(a.height + b.height + 50, 40 + 28 * len(LEG))
W = max(a.width, b.width) + LW + 30
sh = Image.new("RGB", (W, H), (250, 250, 250)); d = ImageDraw.Draw(sh)
d.text((8, 4), "허리·허벅지·무릎", fill=(20, 20, 20), font=f); sh.paste(a, (0, 32))
d.text((8, a.height + 36), "정강이·발목·발", fill=(20, 20, 20), font=f); sh.paste(b, (0, a.height + 64))
y = 10; x = max(a.width, b.width) + 24
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 27
sh.save(OUT); print(sh.size)
