"""양산형 가슴 r5 (2026-11-03) — 유저 "a 로 가되, 컨셉 아트처럼 흰 선을 추가해서 입체감을 살리자".

r4 a(갈매기 꺾임선) 확정 + 면이 꺾이는 모서리에만 밝은 선(컨셉: 판 모서리 칠이 벗겨져 금속이 드러난 자국).
[결정 11-03 유저 요청] 스타일 가이드 1-4 "판 테두리 줄 쓰지 않음"의 예외 — 이 기체 흉판 모서리.
모서리 찾기: r4 의 앞면 평면식(가운데 앞면 · 옆 45° · 위 앞 모서리 45° · 꺾임선 아래 45°)을 칸마다 계산해,
  두 평면이 함께 겉면을 정하는 칸(값 차이 ≤ 0.6) = 꺾인 모서리 + 윗면/바깥 옆/처마 아래 끝과 만나는 모서리.
  e1  1칸 · 강철(7, 150,152,150 — 드러난 금속이라는 뜻과 맞음)
  e2  1칸 · 밝은 새 색 8 (196,196,184)
  e3  2칸 · 새 색 8 (절반 해상도에서도 남게)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import mass_r1 as r1  # noqa: E402
import mass_head_r2 as h2  # noqa: E402
import mass_chest_r4 as c4  # noqa: E402

PAL = dict(h2.PAL); PAL[8] = (196, 196, 184)
NAMES = {"e1": "e1 1칸 강철(7)", "e2": "e2 1칸 밝은 색(8)", "e3": "e3 2칸 밝은 색(8)"}
YF, W, CX, ZT, ZE = -26, 29, 13, 237, 203          # r4 a 와 같은 값


def edge_mask(T):
    X, Y, Z = T.g(); ax = np.abs(X)
    shp = T.a.shape
    zc = 214 + np.clip(ax - CX, 0, None) / 2.0
    # 꺾이기 전(clip 없는) 평면값 — clip 하면 평평한 앞면에서 네 식이 모두 같아져 앞면 전체가 "모서리"로 잡힘
    vals = [np.broadcast_to(v, shp) for v in (
        np.full(shp, float(YF)),
        YF + (ax - (W - 6)),
        YF + (Z - (ZT - 3)),
        YF + (zc - Z))]
    V = np.stack(vals)
    mx = V.max(0)
    active = (V >= mx - 0.6).sum(0)
    surf = T.surface() & (T.a == 1)
    front = np.broadcast_to((Y <= -6) & (Z >= ZE) & (Z <= ZT) & (ax <= W), shp) & (np.broadcast_to(Y, shp) <= mx + 1.5)
    m = (active >= 2)
    m |= np.broadcast_to(Z == ZT, shp)                                                       # 윗면과 만나는 모서리
    m |= np.broadcast_to(ax >= W, shp)                                                       # 바깥 세로 모서리
    m |= np.broadcast_to(Z == ZE, shp)                                                       # 처마 아래 끝
    return surf & front & m


def build_all(var="e2", ws=0.88):
    M = c4.build_all("a", ws)
    T = M.parts["Torso"]
    m = edge_mask(T)
    if var == "e3":
        P = np.pad(m, 1)
        grow = P[2:, 1:-1, 1:-1] | P[:-2, 1:-1, 1:-1] | P[1:-1, 2:, 1:-1] | P[1:-1, :-2, 1:-1] | P[1:-1, 1:-1, 2:] | P[1:-1, 1:-1, :-2]
        m = (m | grow) & T.surface() & (T.a == 1) & edge_mask_zone(T)
    T.a[m] = 7 if var == "e1" else 8
    return M


def edge_mask_zone(T):
    X, Y, Z = T.g(); ax = np.abs(X)
    return np.broadcast_to((Y <= -6) & (Z >= ZE) & (Z <= ZT) & (ax <= W), T.a.shape)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    specs = [(0, 2, "정면"), (-35, 8, "앞 3/4"), (-60, 18, "옆 앞 위"), (30, 8, "앞 3/4 (반대)")]
    rows = [("r4 a (선 없음)", c4.build_all("a"))] + [(NAMES[v], build_all(v)) for v in ("e1", "e2", "e3")]
    rend = []
    for nm, M in rows:
        p = M.parts["Torso"]; _, k = ndimage.label(p.a > 0)
        print(nm, "Torso", p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1, "선 칸", int(((p.a == 7) | (p.a == 8)).sum()))
        ims = [vp.render(M.blocks(), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=4.5, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                         light=(-0.75, -0.55, 0.6)) for y, pt, _ in specs]
        rend.append((nm, ims))
    H = max(i.height for _, ims in rend for i in ims)
    refs = [(con.crop((150, 30, 400, 340)), "컨셉 정면"), (mn.crop((300, 40, 720, 560)), "컨셉 메인"),
            (mn.crop((320, 180, 620, 430)), "컨셉 흉판 확대")]
    refs = [(c.resize((int(c.width * H / c.height), H), Image.LANCZOS), t) for c, t in refs]
    cols = [max(ims[i].width for _, ims in rend) for i in range(4)]
    W_ = max(250 + sum(cols) + 16 * 5, 250 + sum(c.width for c, _ in refs) + 16 * 4)
    allrows = [("참고", [c for c, _ in refs])] + rend
    sh = Image.new("RGB", (W_, 60 + len(allrows) * (H + 16) + 30), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 가슴 r5 — r4 a + 꺾인 모서리 흰 선", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(allrows):
        y0 = 60 + r * (H + 16); x = 250
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, im in enumerate(ims):
            cw = cols[i] if r else im.width
            sh.paste(im, (x + (cw - im.width) // 2, y0)); x += cw + 16
    x = 250
    for i, t in enumerate([s[2] for s in specs]):
        d.text((x + 6, 60 + len(allrows) * (H + 16) + 2), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_가슴r5_흰선.png"); sh.save(p); print(p, sh.size)
