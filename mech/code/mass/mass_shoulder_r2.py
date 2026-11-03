"""양산형 어깨 r2 (2026-11-03) — 유저 "어깨에 차는 어깨 갑옷 같은 느낌을 원했는데, 지금은 어깨판을 위한 받침대가 따로 있는 것 같아서 별로".

받침대·버팀대 없앰 → 판이 어깨를 직접 덮는 갑옷(폴드런). 판 = r1 B 크기(45° · 길이 46 · 두께 5, 그림 세 장에 맞춘 값).
오른쪽 S1 · 관절 원통은 r1 그대로.
  A 캡형      어깨 위를 덮는 올리브 캡(관절 위, 바깥 위 45°) + 판이 캡 바깥 끝에 붙음
  B 접힌 판   판 윗부분이 안쪽 위로 45° 꺾여 어깨 위를 감쌈(판 한 장 = 갑옷)
  C 덧댄 판   오른쪽과 같은 S1 장갑(거울) + 그 앞·바깥에 판을 덧댐(현장 보강 느낌)
  → A~C 렌더 [관찰]: 셋 다 판이 몸 바깥에 따로 선 판으로 보임(B 날개는 거의 안 보이고 섬 2).
  [판단] 그림에서 판이 정면·옆·뒤 세 장 모두 넓게 보이는 이유 = 평평한 판이 아니라 세로로 한 번 꺾여 어깨를 앞·옆·뒤로 감쌈
         (위에서 보면 "<", 앞 면은 앞·바깥, 뒤 면은 뒤·바깥). 이게 "어깨에 찬 갑옷" 느낌.
  D 꺾인 판   세로 꺾임선(바깥 X 62)에서 앞·뒤로 45° 접힌 판이 어깨를 감쌈(양 끝 X 38) + 안쪽 위 올리브 캡(관절 위를 덮음)
  E 앞으로 감싼 판  D 의 꺾임선을 뒤로(Y +8) 옮겨 앞 면이 길게 앞을 덮음(메인 그림처럼 앞에서 넓게)
  → D·E 렌더 [관찰]: 정면에서 여전히 벽처럼 선 판. [실측] 판이 위는 안쪽·아래는 바깥으로 기욺 — 정면 안쪽 위 끝 x420 → 아래 x456,
     뒤에서도 위가 안쪽(약 1:5). 판 윗부분이 어깨 위로 기대야 "어깨에 찬 갑옷"(스타일 가이드 八 처럼 아래가 바깥).
  F  D + 위 안쪽 기울기 1:4      G  E + 위 안쪽 기울기 1:4
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, poly, slab  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_chest_r4 as c4  # noqa: E402
import mass_shoulder_r1 as s1  # noqa: E402

PAL = h2.PAL
NAMES = {"A": "A 캡형", "B": "B 접힌 판", "C": "C 장갑 + 덧댄 판", "D": "D 세로로 꺾여 감싼 판", "E": "E 앞으로 감싼 판"}
FOLD = {"D": dict(xa=62, ya=-1, xe=38), "E": dict(xa=62, ya=7, xe=38),
        "F": dict(xa=62, ya=-1, xe=38, roll=0.25), "G": dict(xa=62, ya=7, xe=38, roll=0.25)}
NAMES.update({"F": "F 꺾인 판 + 위 안쪽 기울기", "G": "G 앞으로 감싼 판 + 위 안쪽 기울기"})
ANG, LS, TH = 45, 1.4, (-2, 2)


def plate(L, G, o, e1, pts, h=TH, col=2):
    L.add(slab(G, o, e1, (0, 0, 1), pts, h=h), col)
    cx = np.mean([p[0] for p in pts]); cz = np.mean([p[1] for p in pts]); inner = []
    for u, v in pts:
        d = np.hypot(u - cx, v - cz); inner.append((u - (u - cx) * 3.0 / d, v - (v - cz) * 3.0 / d))
    L.add(slab(G, o, e1, (0, 0, 1), inner, h=(h[1] + 1, h[1] + 1)), col)


def build_left(M, var):
    M.parts.pop("ShoulderL", None)
    L = M.part("ShoulderL", (20, -48, 192), (84, 48, 272), pivot=s1.SH, parent="Torso")
    G = L.g(); X, Y, Z = G
    th = np.radians(ANG)
    n = np.array((np.cos(th), -np.sin(th), 0.0)); e1 = np.array((np.sin(th), np.cos(th), 0.0))
    zc, yc = 229.5, -1.0
    pts = [((x - 750) * s1.K * LS, s1.FZ(y) - zc) for x, y in s1.S2_SIDE]
    half = max(abs(p[0]) for p in pts)
    if var in FOLD:
        fd = FOLD[var]
        span = fd["xa"] - fd["xe"]                                                       # 45° 접힘 → 꺾임선에서 앞뒤로 span 칸
        xs = fd["xa"] - np.abs(Y - fd["ya"]) - (Z - 230) * fd.get("roll", 0)              # 판 바깥 면 X(Y 마다, F·G: 위로 갈수록 안쪽)
        zc2 = 229.5
        hexp = [((x - 750) * s1.K * 1.45 + fd["ya"], s1.FZ(y)) for x, y in s1.S2_SIDE]   # 옆 육각을 (Y, z) 에 펼침
        side = poly(G, "x", hexp) & (np.abs(Y - fd["ya"]) <= span)
        L.add(side & (X <= xs) & (X >= xs - 4), 2)
        cy = np.mean([p[0] for p in hexp]); cz = np.mean([p[1] for p in hexp]); inner = []
        for u, v in hexp:
            dd = np.hypot(u - cy, v - cz); inner.append((u - (u - cy) * 3.0 / dd, v - (v - cz) * 3.0 / dd))
        L.add(poly(G, "x", inner) & (np.abs(Y - fd["ya"]) <= span - 2) & (X == np.floor(xs) + 1), 2)   # 바깥 면 1칸 돋운 안쪽 판
        cap = cbox(G, (27, 52), (-14, 13), (232, 247 if fd.get("roll") else 246), {"+zy": 4, "-zx": 3}) & (X <= xs - 4)
        L.add(cap, 1)                                                                    # 판 안쪽 위 올리브 캡(관절 위)
        s1.joint(L, 1)
        L.trim()
        return
    if var == "C":
        R = M.parts["ShoulderR"]                                                           # S1 거울을 왼쪽에(올리브 장갑)
        sub = R.a[::-1].copy(); lo = np.array((-(R.hi[0] - 1), R.lo[1], R.lo[2]))
        o_ = lo - L.lo
        L.a[o_[0]:o_[0] + sub.shape[0], o_[1]:o_[1] + sub.shape[1], o_[2]:o_[2] + sub.shape[2]][sub > 0] = sub[sub > 0]
        o = np.array((44.0 + half * np.sin(th), yc - 6, zc))                             # 장갑 앞·바깥 모서리에 덧댐
    else:
        o = np.array((36.0 + half * np.sin(th) + 3, yc, zc))
    if var == "A":
        # 캡: 관절 위를 덮는 올리브 덩어리 — 몸 쪽(X 28)에서 판 안쪽까지, 바깥 위 45°, 앞뒤 45°
        cap = cbox(G, (27, 50), (-14, 13), (232, 247), {"+x+z": 6, "+zy": 4, "-zx": 3})
        L.add(cap, 1)
        L.emboss((Z >= 244) & (X >= 30) & (X <= 44) & (np.abs(Y + 0.5) <= 9), 1)            # 윗면 덧판
    plate(L, G, o, e1, pts)
    if var == "B":
        # 판 윗부분을 안쪽 위로 45° 꺾은 날개: 판 위 끝(꼭짓점 z≈259 아래 4칸)에서 몸 쪽으로 15칸, 판 길이의 80%
        top = o + np.array((0, 0, 25.0)) - n * 2
        e2 = (-n + np.array((0, 0, 1.0))) / np.sqrt(2)
        w = half * 0.78
        fl = [(-w, 0), (w, 0), (w - 4, 15), (-w + 4, 15)]
        L.add(slab(G, top, e1, e2, fl, h=(-2, 2)), 2)
        L.add(slab(G, top, e1, e2, [(-w + 3, 1), (w - 3, 1), (w - 6, 13), (-w + 6, 13)], h=(3, 3)), 2)
        # 날개 안쪽 끝 아래를 관절 위까지 짙은 받침으로 채움(떠 보이지 않게, 바깥에선 안 보임)
        L.add(box(G, x=(28, 40), y=(-10, 9), z=(231, 240)), 3)
    s1.joint(L, 1)
    L.trim()


def build_all(var="A", ws=0.88):
    M = c4.build_all("a", ws)
    s1.build_shoulders(M, 45)
    build_left(M, var)
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    Rr = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(Rr, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(Rr, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 2, "정면"), (35, 8, "앞 3/4 (왼쪽 판)"), (60, 25, "위 옆 앞"), (90, 2, "옆(왼쪽)"), (180, 2, "뒤")]
    sel = sys.argv[2] if len(sys.argv) > 2 else "ABC"
    rows = [("r1 B (전, 받침대)", s1.build_all(45))] + [(NAMES[v], build_all(v)) for v in sel]
    rend = []
    for nm, M in rows:
        p = M.parts["ShoulderL"]; _, k = ndimage.label(p.a > 0)
        print(nm, "ShoulderL", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=3.4, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((20, 20, 570, 330)), "컨셉 정면"), (mn.crop((150, 40, 990, 600)), "컨셉 메인"),
            (con.crop((600, 20, 920, 330)), "컨셉 옆"), (con.crop((980, 20, 1500, 330)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(230 + sum(cols) + 16 * 6, 230 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 어깨 r2 — 받침대 없이 어깨를 직접 덮는 갑옷(판 45° · 길이 46)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 230
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_어깨r2_갑옷_%s.png" % sel); sh.save(p); print(p, sh.size)
