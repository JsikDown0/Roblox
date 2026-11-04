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


def build_torso_r2(M):
    """r2 [유저 11-04]: ① 옆에서 보면 회색 멍에가 위에서 앞·아래로 미끄러지다 모래 판을 만나 각도가 다시 바뀜 — 양옆 면도 각각 꺾임
    ② 가슴 포트 2(총구) → 어깨 쪽으로 올림 ③ 등도 굴곡(위·아래 비스듬, 가운데 불룩) ④ 등 세로 일자 홈 뺌."""
    T = M.part("Torso", (-36, -32, 182), (37, 28, 250), pivot=(0, 0, 200))
    G = T.g(); X, Y, Z = G; ax = np.abs(X)
    T.add(cbox(G, (-24, 24), (-12, 16), (188, 236), {"xy": 4}), 3)                               # 속(짙은 프레임)
    # 앞면 옆 단면(Y 앞 경계, Z 마다): 멍에 z243 Y−10 → z222 Y−19(1:2.3, 앞·아래로 미끄러짐) | 모래 판 z221 Y−22(턱 2칸) → z207 Y−22 → z194 Y−16(1:2 뒤로)
    # 1차: 9/21 · 0.45 · 10/15 같은 애매한 기울기 + 위로 좁아지는 멍에 → 둥근 덩어리(삼각김밥)처럼 보임 → 모든 면 1:2 · 45° 정수비, 어깨는 각지게
    yf_g = -12 - (243 - Z) / 2.0                                                                    # 멍에 앞면 1:2(z243 Y−12 → z222 Y−22.5)
    yf_s = np.where(Z >= 207, -24.0, -24 + (207 - Z) / 2.0)                                       # 모래 판: 2칸 턱 → 수직 → 1:2 뒤로
    # 뒷면: z243 Y 10 → z228 Y 20(1:1.5) · z228~212 Y 20 · z212 → z194 Y 13(1:2.6)
    yb = np.where(Z >= 231, 12 + (243 - Z) / 2.0, np.where(Z >= 212, 18.0, 18 - (212 - Z) / 2.0))  # 등: 위 1:2 · 가운데 수직 · 아래 1:2
    # 옆 폭: 멍에는 위로 갈수록 안쪽(z222 ±28 → z243 ±23) · 모래 판은 아래로 좁아짐(z204 ±28 → z194 ±21)
    w_g = 28 - np.clip(Z - 238, 0, None)                                                           # 어깨 위 바깥 모서리 45° 만
    w_s = 28 - np.clip(204 - Z, 0, None) * 0.7
    top = 241 + np.clip(ax - 16, 0, 2)
    yoke = (ax <= w_g) & (Z >= 222) & (Z <= top) & (Y >= yf_g) & (Y <= yb)
    yoke &= (Y >= yf_g + np.clip(ax - 20, 0, None) * 1.0)                                         # 옆 앞 모서리 45°(옆 면 따로 꺾임) — 2차: 뒤 모서리 깎기는 빼서 덜 둥글게
    yoke &= (Y <= yb - np.clip(ax - 24, 0, None) * 1.0)
    T.add(yoke, 2)
    back = (ax <= 26) & (Z >= 196) & (Z < 222) & (Y >= 0) & (Y <= yb) & (Y <= yb - np.clip(ax - 22, 0, None))
    T.add(back, 2)                                                                                 # 등 아래(짙은 회색)
    T.cut((ax <= 13) & (Y <= 8) & (Z >= 233)); T.cut((ax <= 14) & (Y <= 17) & (Z >= 237))
    T.add(cbox(G, (-13, 13), (-12, 8), (230, 232), {"xy": 3}) & ~(T.a > 0), 3)
    plate = (ax <= w_s) & (Z >= 194) & (Z <= 221) & (Y >= yf_s) & (Y <= 6)
    plate &= (Y >= yf_s + np.clip(ax - 16, 0, None))                                               # 옆 면 45°
    T.add(plate, 1)
    T.emboss((ax <= 15 - np.clip(214 - Z, 0, None) / 2.0) & (Z >= 199) & (Z <= 219) & (Y < -23) & (Z >= 207), 1)
    T.groove((Z == 221) & (ax <= 28) & (Y <= -16), 4)
    T.add(cbox(G, (-14, 14), (-16, 0), (188, 193), {"-yz": 2, "xy": 2}), 1)
    # 포트 2 → 어깨 쪽 멍에 윗면 앞(총구가 앞을 향함)
    for sg in (1, -1):
        xc = sg * 21
        T.add(cbox(G, (xc - 4, xc + 4), (-14, -6), (240, 245), {"xy": 1, "-yz": 1}) & ~(T.a > 0), 2)   # 받침
        T.add(cyl(G, "y", (xc, 243), 2.8, rng=(-18, -12)), 7)                                     # 총구
        T.cut(cyl(G, "y", (xc, 243), 1.5, rng=(-19, -14)))
    T.trim()
    return T


def build_all(r2=True):
    M = fv.Model()
    (build_torso_r2 if r2 else build_torso)(M)
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
    M1 = build_all(False)
    ims1 = [vp.render(M1.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=5, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0})
            for y, pt in ((0, 3), (-35, 10), (-90, 3), (150, 8))]
    ims = [vp.render(M.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=5, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0})
           for y, pt in ((0, 3), (-35, 10), (-90, 3), (150, 8))]
    con = Image.open(ht.SRC).convert("RGB"); mn = Image.open(os.path.join(os.path.dirname(ht.SRC), "concept_v1_메인.png")).convert("RGB")
    H = max(i.height for i in ims)
    refs = [con.crop((130, 70, 380, 330)), mn.crop((300, 60, 780, 640)), con.crop((580, 70, 900, 330)), con.crop((990, 70, 1500, 330))]
    refs = [c.resize((int(c.width * H / c.height), H)) for c in refs]
    W = max(sum(i.width for i in ims), sum(i.width for i in refs)) + 100
    sh = Image.new("RGB", (W, 3 * H + 160), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "새 양산기 가슴 r2 — 옆 단면 꺾임(회색 미끄러짐 → 모래 판 → 아래 뒤로) · 양옆 면 · 포트 → 어깨 쪽 · 등 굴곡", fill=(235, 235, 235), font=ft)
    for r_, row in enumerate((refs, ims1, ims)):
        x = 16
        for im in row:
            sh.paste(im, (x, 60 + r_ * (H + 30))); x += im.width + 16
    p = os.path.join(out, "시안_가슴r2.png"); sh.save(p); print(p, sh.size)
