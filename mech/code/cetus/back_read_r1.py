"""CETUS 등 윤곽 읽기 r1 — 2순위 삼면도 뒤 + 1순위 메인 그림 위쪽. 다각형 = 원본 픽셀 좌표."""
from PIL import Image, ImageDraw, ImageFont
import sys
REAR, MAIN, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
F = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
f = ImageFont.truetype(F, 20); fs = ImageFont.truetype(F, 17); ft = ImageFont.truetype(F, 26)
GREEN, ORANGE, PURPLE, RED, BLUE = (20, 140, 60), (220, 120, 0), (130, 70, 200), (210, 30, 30), (30, 40, 200)
Zr = lambda y: round((945 - y) * 0.334)          # 삼면도 뒤: 발바닥 y945 · 어깨 위 y200 → z249

P_REAR = [
    ("R1", GREEN, [(725, 110), (840, 110), (845, 200), (830, 300), (735, 300), (722, 200)], (845, 120)),
    ("X1", RED, [(735, 40), (820, 40), (828, 100), (728, 100)], (830, 45)),
    ("R2", ORANGE, ("ell", 808, 342, 58, 58), (868, 330)),
    ("R3", GREEN, [(688, 245), (885, 245), (885, 272), (688, 272)], (612, 245)),
    ("R4", GREEN, [(688, 200), (725, 200), (725, 400), (688, 400)], (640, 330)),
    ("R4", GREEN, [(858, 200), (892, 200), (892, 400), (858, 400)], (900, 210)),
    ("L?", PURPLE, ("ell", 695, 170, 30, 32), (630, 130)),
    ("L?", PURPLE, ("ell", 896, 172, 30, 32), (930, 130)),
    ("X2", RED, [(698, 98), (748, 98), (748, 138), (698, 138)], (650, 90)),
]
P_MAIN = [
    ("C?", PURPLE, [(565, 60), (690, 60), (692, 140), (568, 140)], (500, 60)),
    ("X2", RED, [(690, 15), (770, 15), (772, 150), (692, 150)], (700, 160)),
    ("X1", RED, [(745, 20), (960, 20), (960, 100), (745, 100)], (900, 2)),
    ("X3", RED, ("ell", 828, 115, 33, 33), (770, 165)),
    ("R1", GREEN, [(845, 85), (960, 85), (960, 200), (845, 200)], (965, 140)),
    ("L?", PURPLE, ("ell", 945, 150, 35, 42), (950, 200)),
]


def panel(path, box, k, parts, zfun=None):
    im = Image.open(path).convert("RGB")
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
            d.polygon([T(p) for p in g], outline=col + (255,), fill=col + (45,), width=3)
    c = Image.alpha_composite(c.convert("RGBA"), ov).convert("RGB"); dt = ImageDraw.Draw(c)
    for lab, col, g, tp in parts:
        q = T(tp); w = dt.textlength(lab, font=f)
        q = (min(max(q[0], 2), c.width - w - 6), min(max(q[1], 2), c.height - 28))
        dt.rectangle([q[0] - 3, q[1] - 2, q[0] + w + 3, q[1] + 25], fill=(255, 255, 255), outline=col, width=2)
        dt.text((q[0], q[1] - 1), lab, fill=col, font=f)
    if zfun:
        for y in range((y0 // 50 + 1) * 50, y1, 50):
            Y = (y - y0) * k
            dt.line([(c.width - 14, Y), (c.width, Y)], fill=(90, 90, 90), width=2)
            dt.text((c.width - 70, Y - 11), "z%d" % zfun(y), fill=(90, 90, 90), font=fs)
    return c


a = panel(REAR, (600, 30, 1000, 420), 1.7, P_REAR, Zr)
b = panel(MAIN, (480, 0, 1000, 260), 1.3, P_MAIN)
LEG = [
    ("등 윤곽 읽기 r1", None, ft),
    ("등은 메인 그림에 거의 안 보임 → 2순위 삼면도 뒤(위)", (90, 90, 90), fs),
    ("+ 메인 그림 어깨 위로 보이는 부분(아래)", (90, 90, 90), fs),
    ("삼면도 z = (945 − y) × 0.334 (어깨 위 y200 = z249)", (90, 90, 90), fs),
    ("", None, fs),
    ("R1 가운데 큰 탱크(쌓인 원통 + 황동 띠)", GREEN, fs),
    ("   원본 꼭대기 z≈279(머리보다 높음)", GREEN, fs),
    ("R2 등 아래 둥근 해치(z≈180~220)", ORANGE, fs),
    ("   → 결정 5-3: 여기를 태엽 손잡이 / 밸브 핸들로", ORANGE, fs),
    ("R3 가로 배관(탱크 아래를 가로지름, z≈225)", GREEN, fs),
    ("R4 양옆 세로 배관 기둥(황동 띠)", GREEN, fs),
    ("X1 탱크 위 철창 돔 · X2 위로 솟은 U 배관", RED, fs),
    ("X3 압력계 — 결정 5-2·5-3 대로 뺌", RED, fs),
    ("", None, fs),
    ("질문(보라 = 정할 것)", None, f),
    ("1. R1 탱크 높이: 원본은 머리 위로 솟음.", PURPLE, fs),
    ("   제안: 어깨 위 높이(z≈250)까지 — 앞에서", PURPLE, fs),
    ("   머리 뒤로 살짝만 보이게", PURPLE, fs),
    ("2. L 어깨 뒤 철창 등불 2개: 결정 5-3 은 뺌.", PURPLE, fs),
    ("   그 뒤 \"발광 더 늘림\" → 넣을까? 제안: 넣음", PURPLE, fs),
    ("3. C 오른쪽 뒤 작은 통 + 발광 창(메인 그림)", PURPLE, fs),
    ("   제안: 한쪽만 넣음(비대칭)", PURPLE, fs),
    ("4. R3·R4 배관: 제안: 넣음(굵게, 단순하게)", PURPLE, fs),
    ("5. 태엽 / 밸브 = 두 안 다 만들어 비교(결정대로)", PURPLE, fs),
]
LW = 520
W = max(a.width, b.width) + LW + 30
H = max(a.height + b.height + 70, 40 + 29 * len(LEG))
sh = Image.new("RGB", (W, H), (250, 250, 250)); d = ImageDraw.Draw(sh)
d.text((8, 4), "삼면도 뒤(2순위)", fill=(20, 20, 20), font=f); sh.paste(a, (0, 32))
d.text((8, a.height + 38), "메인 그림 어깨 위(1순위)", fill=(20, 20, 20), font=f); sh.paste(b, (0, a.height + 66))
y = 10; x = max(a.width, b.width) + 24
for t, col, fo in LEG:
    d.text((x, y), t, fill=col or (20, 20, 20), font=fo); y += 34 if fo is ft else 28
sh.save(OUT); print(sh.size)
