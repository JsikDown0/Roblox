"""양산형 어깨 r3 (2026-11-03) — 어깨 = r2 F 확정 [결정 11-03 "F 로 가자"] + 유저 "방패는 데칼 붙이기 가장 좋은 곳인데 지금 형태로는 이상해지지 않나?"

[판단] 그렇다 — 로블록스 Decal 은 파트 상자의 한 면에서 평면 투영. F 판은 ① 세로로 꺾임(글자가 꺾임선을 넘어 접힘)
② 45° · 1:4 로 기울어 늘어남 ③ 그 기울기를 칸 계단으로 만들어 표면이 울퉁불퉁.
→ 스타일 가이드 1-4 "큰 비스듬한 판은 세워 만들고 관절로 기울인다": 꺾인 판의 앞 면·뒤 면을 각각 평평한 별도 파트로
   축에 맞춰 반듯하게 만들고, 파트 자체를 돌림(rotz ∓45 · roty −14 = 위 안쪽 1:4) → 계단 없음 + 파트 면 = 판 면 → 데칼 그대로.
   PlateF(앞 면, 바깥 = 앞·바깥 "03" 자리, 정면·옆에서 보임) · PlateB(뒤 면, 뒤·바깥 = 게임 3인칭 카메라가 늘 보는 면 → 부대 표식 자리).
   두 파트 모두 부모 ShoulderL(팔 들면 같이) · 피벗 = 꺾임선(X 62, Y −1, z 230).
   GLB 로 낼 때 이 두 판은 회전을 메시에 굽지 말고(로컬 그대로) Studio 에서 CFrame 으로 돌려야 데칼 면이 판과 맞음 → 다음 PC 세션 메모.
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
import mass_shoulder_r2 as s2  # noqa: E402

PAL = h2.PAL
XA, YA, ZP, XE, ROLL = 62, -1, 230, 38, 14.0                     # 꺾임선 · 피벗 높이 · 양 끝 X · 위 안쪽 기울기(°, tan ≈ 1/4)


def build_left(M):
    M.parts.pop("ShoulderL", None)
    L = M.part("ShoulderL", (20, -30, 196), (60, 30, 252), pivot=s1.SH, parent="Torso")
    G = L.g(); X, Y, Z = G
    span = XA - XE
    xs = XA - np.abs(Y - YA) - (Z - ZP) * np.tan(np.radians(ROLL))
    L.add(cbox(G, (27, 52), (-14, 13), (232, 247), {"+zy": 4, "-zx": 3}) & (X <= xs - 5), 1)   # 판 안쪽 위 올리브 캡
    s1.joint(L, 1)
    L.trim()
    # 펼친 육각(꺾임선 = t 0, 앞 −, 뒤 +): 옆 그림 육각의 길이 × 1.45 × √2(45° 로 접혀 투영되면 r2 F 와 같은 크기)
    hexp = [((x - 750) * s1.K * 1.45 * np.sqrt(2), s1.FZ(y)) for x, y in s1.S2_SIDE]
    for name, sgn, yaw in (("PlateF", -1, -45.0), ("PlateB", 1, 45.0)):
        P = M.part(name, (XA - 6, YA - 52, 196), (XA + 3, YA + 52, 264), pivot=(XA, YA, ZP), parent="ShoulderL")
        G = P.g(); X, Y, Z = G
        half = (sgn * (Y - YA) >= -0.5)                                                   # 이 판이 맡는 쪽(꺾임선에서 앞 또는 뒤)
        poly_ = [(YA + t, z) for t, z in hexp]
        P.add(poly(G, "x", poly_) & half & (X >= XA - 4) & (X <= XA), 2)
        cy = np.mean([p[0] for p in poly_]); cz = np.mean([p[1] for p in poly_]); inner = []
        for u, v in poly_:
            dd = np.hypot(u - cy, v - cz); inner.append((u - (u - cy) * 3.0 / dd, v - (v - cz) * 3.0 / dd))
        P.add(poly(G, "x", inner) & (sgn * (Y - YA) >= 2) & (X == XA + 1), 2)            # 바깥 면 1칸 돋운 안쪽 판(= 데칼 면)
        P.rot = rotz(yaw) @ roty(-ROLL)
        P.trim()
    return M


def build_all(ws=0.88):
    M = c4.build_all("a", ws)
    s1.build_shoulders(M, 45)
    build_left(M)
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
    specs = [(0, 2, "정면"), (35, 8, "앞 3/4 (왼쪽 판)"), (45, 14, "앞 판에 수직(데칼 시점)"), (90, 2, "옆(왼쪽)"), (150, 10, "뒤 3/4 (게임 카메라 쪽)")]
    rows = [("r2 F (계단 판)", s2.build_all("F")), ("r3 F (평평한 판 파트 2장)", build_all())]
    rend = []
    for nm, M in rows:
        for pn in [n for n in M.parts if n.startswith("Shoulder") or n.startswith("Plate")]:
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(nm, pn, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=3.4, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((20, 20, 570, 330)), "컨셉 정면"), (mn.crop((150, 40, 990, 600)), "컨셉 메인"),
            (con.crop((600, 20, 920, 330)), "컨셉 옆"), (con.crop((980, 20, 1500, 330)), "컨셉 뒤")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(len(specs))]
    W = max(260 + sum(cols) + 16 * 6, 260 + sum(c.width for c, _ in refs) + 16 * 5)
    allrows = [("참고", [c for c, _ in refs], [t for _, t in refs])] + [(nm, ims, [s[2] for s in specs]) for nm, ims in rend]
    sh = Image.new("RGB", (W, 60 + len(allrows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 어깨 r3 — F 판을 평평한 파트 2장으로(계단 없음 · 파트 면 = 판 면 → 데칼 그대로)", fill=(235, 235, 235), font=ft)
    for r, (nm, ims, labs) in enumerate(allrows):
        y0 = 60 + r * (H + 50); x = 260
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (im, t) in enumerate(zip(ims, labs)):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cw + 16
    p = os.path.join(out, "시안_어깨r3_데칼판.png"); sh.save(p); print(p, sh.size)
