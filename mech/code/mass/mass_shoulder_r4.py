"""양산형 어깨 r4 (2026-11-03) — 유저 "꺾이는 부분을 만들 필요가 있어? 방패 한쪽을 좀 짧게 만들면 꺾이는 부분이 안 생기지 않아?"

[판단] 맞음 — 꺾임은 정면·옆·뒤 세 그림을 모두 맞추려다 생긴 것. 1순위 메인 그림의 판은 평평한 한 장. 데칼도 면 하나가 가장 좋음.
→ 판 한 장(평평한 별도 파트 Plate, 부모 ShoulderL), 뒤쪽을 짧게(꺾임선 너머 뒤 면 없앰). r3 처럼 축에 맞춰 반듯하게 만들고
  파트를 돌림 = 계단 없음 · 파트 면 = 판 면(데칼). 위 안쪽 기울기 14°(1:4) · 판 안쪽 위 올리브 캡은 그대로(갑옷 느낌).
  H  45° 앞·바깥 · 길이 42(앞 끝 X 38 · Y −25)       I  30° · 길이 46(앞 끝 X 40 · Y −22, 옆을 더 덮음)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, poly, rotz, roty  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_chest_r4 as c4  # noqa: E402
import mass_shoulder_r1 as s1  # noqa: E402
import mass_shoulder_r3 as s3  # noqa: E402

PAL = h2.PAL
ROLL, ZP = 14.0, 230
VAR = {"H": dict(yaw=-45.0, L=42.0, front=(38.0, -25.0)), "I": dict(yaw=-30.0, L=46.0, front=(40.0, -22.0))}
NAMES = {"H": "H 판 한 장 45° · 길이 42", "I": "I 판 한 장 30° · 길이 46"}


def build_left(M, var="H"):
    v = VAR[var]
    Rm = roty(-ROLL) @ rotz(v["yaw"])
    d = Rm @ np.array((0, -1.0, 0)); d[2] = 0; d /= np.linalg.norm(d)                    # 판 앞 방향(수평)
    c = np.array((v["front"][0] - d[0] * v["L"] / 2, v["front"][1] - d[1] * v["L"] / 2, ZP))   # 판 가운데(피벗)
    n = Rm @ np.array((1.0, 0, 0))                                                      # 판 바깥 방향
    M.parts.pop("ShoulderL", None)
    L = M.part("ShoulderL", (20, -30, 196), (62, 30, 252), pivot=s1.SH, parent="Torso")
    G = L.g(); X, Y, Z = G
    inside = ((X - c[0]) * n[0] + (Y - c[1]) * n[1] + (Z - c[2]) * n[2]) <= -6            # 판 안쪽 면보다 몸 쪽
    L.add(cbox(G, (27, 54), (-15, 14), (232, 247), {"+zy": 4, "-zx": 3}) & inside, 1)   # 판 안쪽 위 올리브 캡
    s1.joint(L, 1)
    L.trim()
    ci = np.round(c).astype(int)
    hexp = [((x - 750) * s1.K * v["L"] / 33.0, s1.FZ(y)) for x, y in s1.S2_SIDE]       # 옆 그림 육각을 길이 L 로
    P = M.part("Plate", (ci[0] - 6, ci[1] - 32, 196), (ci[0] + 3, ci[1] + 32, 264), pivot=tuple(c), parent="ShoulderL")
    G = P.g(); X, Y, Z = G
    poly_ = [(c[1] + u, z) for u, z in hexp]
    P.add(poly(G, "x", poly_) & (X >= ci[0] - 4) & (X <= ci[0]), 2)
    cy = np.mean([p[0] for p in poly_]); cz = np.mean([p[1] for p in poly_]); inner = []
    for u, z in poly_:
        dd = np.hypot(u - cy, z - cz); inner.append((u - (u - cy) * 3.0 / dd, z - (z - cz) * 3.0 / dd))
    P.add(poly(G, "x", inner) & (X == ci[0] + 1), 2)                                     # 바깥 면 1칸 돋운 안쪽 판 = 데칼 면
    P.pivot = (float(ci[0]), float(c[1]), float(ZP))
    P.rot = Rm
    P.trim()
    return M


def build_all(var="H", ws=0.88):
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
    specs = [(0, 2, "정면"), (35, 10, "앞 3/4 (왼쪽 판)"), (90, 2, "옆(왼쪽)"), (90, 70, "위에서"), (150, 10, "뒤 3/4 (게임 카메라 쪽)")]
    rows = [("r3 (꺾인 판 2장)", s3.build_all())] + [(NAMES[k], build_all(k)) for k in "HI"]
    rend = []
    for nm, M in rows:
        for pn in [n for n in M.parts if n in ("ShoulderL", "Plate", "PlateF", "PlateB")]:
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=3.4, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((20, 20, 570, 330)), "컨셉 정면"), (mn.crop((150, 40, 990, 600)), "컨셉 메인(1순위)"),
            (con.crop((600, 20, 920, 330)), "컨셉 옆"), (con.crop((980, 20, 1500, 330)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(260 + sum(cols) + 16 * 6, 260 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 어깨 r4 — 꺾임 없이 판 한 장(뒤쪽을 짧게) · 위 안쪽 14° · 데칼 면 하나", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 260
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_어깨r4_판한장.png"); sh.save(p); print(p, sh.size)
