"""새 표준 양산기 ST-10 가슴 r1 (2026-11-04). 머리 확정(m2_head_trace.build_final) 위에.
[읽기: 삼면도 정면 x130~380 · y120~360 확대 + 메인 + 뒤] z = (943 − y) × 0.301 · 가슴 가운데 x≈250(그림이 살짝 돌아감 → 반폭으로)
  Y 짙은 회색 멍에: y150~205 → z222~239, 폭 x148~352 → ±30(폭 ×0.92 → ±28) · 양 어깨 쪽이 조금 높고 가운데 목 홈 · 앞 윗모서리 45°
  P 둥근 포트 2: x185·340, y200 → X ±23 · z224 — 멍에와 가슴판 사이(짙은 구멍 + 강철 테)
  C 모래 가슴판: y205~300 → z194~222 · 위 ±28 → 아래 ±20(아래 옆 모서리 큰 45°) · 옆으로 돌아 감쌈(메인)
    가운데 판(±18 → 아래 ±12) 1칸 돋움 + 양옆 판은 바깥으로 45° 비스듬 · 붉은 사선 = 데칼(복셀엔 없음)
  L 아래 턱판(모래): x210~305 → ±14 · y300~320 → z188~194, 가슴판보다 2칸 뒤
  뒤 = 짙은 회색 상자(뒤 그림) + 가운데 세로 홈 · 몸통 속 = 짙은 프레임.
색: 1 모래 · 2 짙은 회색 · 3 짙은 프레임 · 4 검정 · 7 강철."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox  # noqa: E402
import m2_head_r1 as h1  # noqa: E402
import m2_head_trace as ht  # noqa: E402

PAL, EMISSIVE = h1.PAL, h1.EMISSIVE
NECK = (0, 0, 236)


def build_torso(M):
    T = M.part("Torso", (-36, -30, 182), (37, 26, 248), pivot=(0, 0, 200))
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    T.add(cbox(G, (-25, 25), (-14, 18), (188, 236), {"xy": 4, "+zx": 3}), 3)                     # 몸통 속(짙은 프레임)
    # 뒤 상자(짙은 회색) + 세로 홈
    T.add(cbox(G, (-26, 26), (4, 20), (196, 238), {"+yx": 4, "+y+z": 3, "+yz": 2}), 2)
    T.groove((X == 0) & (Y >= 19) & (Z >= 200) & (Z <= 234), 4)
    # 멍에(짙은 회색): 앞 윗모서리 45° · 어깨 쪽 높게 · 목 홈
    top = 241 + np.clip(ax - 16, 0, 2)                                                          # 1차(238)는 머리가 위에 얹혀 커 보임 → 컨셉처럼 머리 아랫부분이 멍에에 묻히게(어깨 쪽 z243)
    yoke = (ax <= 28) & (Y >= -19) & (Y <= 12) & (Z >= 220) & (Z <= top)
    yoke &= (Y >= -19 + np.clip(Z - 237, 0, None)) & (ax <= 28 - np.clip(Z - 239, 0, None))
    yoke &= (ax + (-Y) <= 28 + 19 - 4)
    T.add(yoke, 2)
    T.cut((ax <= 13) & (Y <= 8) & (Z >= 233))                                                    # 목 홈(머리 폭 ±13 이 들어감)
    T.cut((ax <= 14) & (Y <= 17) & (Z >= 237))                                                   # 머리 뒤통수 자리(1차 머리∩몸통 1,689칸)
    T.add(cbox(G, (-13, 13), (-12, 8), (230, 232), {"xy": 3}) & ~(T.a > 0), 3)
    T.groove((ax >= 15) & (ax <= 26) & (Y == -14) & (Z >= 239), 4)                               # 멍에 윗면 판 이음매
    # 포트 2(멍에 앞 아래, 가슴판 바로 위)
    for s in (1, -1):
        T.add(cyl(G, "y", (s * 23, 224), 3.6, rng=(-21, -18)), 7)
        T.cut(cyl(G, "y", (s * 23, 224), 2.2, rng=(-22, -18)))
        T.add(cyl(G, "y", (s * 23, 224), 2.2, rng=(-17, -17)), 4)
    # 가슴판(모래): 아래로 좁아짐 · 아래 옆 45° · 가운데 판 + 옆 판 비스듬 · 옆으로 감쌈
    w = 28 - np.clip(204 - Z, 0, None) * 0.7                                                     # 위 ±28 → 아래(z194) ±21(1차는 일찍 좁아져 양동이 같음)
    plate = (ax <= w) & (Z >= 194) & (Z <= 221) & (Y <= 6)
    yf = -22 + np.clip(ax - 16, 0, None)                                                          # 가운데 앞면 Y −22, ±16 밖은 45° 로 물러남
    plate &= (Y >= yf) & (Y >= -22 + np.clip(Z - 219, 0, None))                                   # 위 앞모서리 2칸
    T.add(plate, 1)
    T.emboss((ax <= 15 - np.clip(214 - Z, 0, None) * 0.35) & (Z >= 197) & (Z <= 219) & (Y < -21), 1)   # 가운데 판 1칸
    T.groove((Z == 221) & (ax <= 28) & (Y <= -14), 4)                                             # 멍에와 판 사이 그늘 줄
    # 아래 턱판
    T.add(cbox(G, (-14, 14), (-20, 0), (188, 193), {"-yz": 2, "xy": 2}), 1)
    T.trim()
    return T


def build_all():
    M = fv.Model()
    build_torso(M)
    H = ht.build_final(M, parent="Torso")
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    M = build_all(); cm.check(M)
    ims = [vp.render(M.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=5, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0})
           for y, pt in ((0, 3), (-35, 10), (-90, 3), (180, 5))]
    con = Image.open(ht.SRC).convert("RGB"); mn = Image.open(os.path.join(os.path.dirname(ht.SRC), "concept_v1_메인.png")).convert("RGB")
    H = max(i.height for i in ims)
    refs = [con.crop((130, 70, 380, 330)), mn.crop((300, 60, 780, 640)), con.crop((580, 70, 900, 330)), con.crop((990, 70, 1500, 330))]
    refs = [c.resize((int(c.width * H / c.height), H)) for c in refs]
    W = max(sum(i.width for i in ims), sum(i.width for i in refs)) + 100
    sh = Image.new("RGB", (W, 2 * H + 130), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "새 양산기 가슴 r1 — 짙은 회색 멍에 + 포트 2 + 모래 가슴판(가운데 판 · 옆 45°) + 아래 턱판 · 머리 확정본", fill=(235, 235, 235), font=ft)
    for r_, row in enumerate((refs, ims)):
        x = 16
        for im in row:
            sh.paste(im, (x, 60 + r_ * (H + 30))); x += im.width + 16
    p = os.path.join(out, "시안_가슴r1.png"); sh.save(p); print(p, sh.size)
