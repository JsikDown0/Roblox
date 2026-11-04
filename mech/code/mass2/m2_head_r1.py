"""새 표준 양산기 ST-10 머리 r1 (2026-11-04) — 윤곽 읽기 r1 답 [결정 11-04]: 둥근 면 → 팔각·45° 다면체 · 색(모래 · 짙은 회색 · 붉은 줄 데칼 · 청록 렌즈) ·
폭 ×0.92 · 카빈 새로 · 나이프 홀스터 골반 고정.
[관찰: 메인 머리 확대] 깎은 팔각 상자(앞에서 가운데 면 + 양옆 45° 면, 윗면 평평 + 위 덮개 판) · 정면 가운데 큰 사각 홈(짙은) 속 둥근 청록 렌즈 ·
  홈 아래 짙은 턱 · 양옆 비스듬한 볼판 · 귀 = 옆으로 나온 짧은 원통(팔각) · 목은 회색 깃 속.
[실측] 정면 폭 x208~322 → 34칸(귀 포함 약 40) · 높이 y82~160 → 23칸(z 236~260).
  M1 그림대로(사각 홈 폭 17 · 렌즈 r5)   M2 홈 작게 + 이마 처마(진중)   M3 홈 크게 + 렌즈 r6.5(존재감)
색: 1 모래 (176,165,140) · 2 짙은 회색 (88,92,98) · 3 프레임 · 4 검정 · 6 청록 발광 · 7 강철."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox  # noqa: E402

PAL = {1: (176, 165, 140), 2: (88, 92, 98), 3: (52, 54, 56), 4: (20, 21, 23), 5: (170, 60, 50), 6: (90, 236, 240), 7: (150, 152, 150)}
EMISSIVE = {6}
NAMES = {"M1": "M1 그림대로", "M2": "M2 홈 작게 + 이마 처마", "M3": "M3 홈 크게 + 큰 렌즈"}
V = {"M1": dict(sw=8.5, sh=7, lr=5.0, brow=0), "M2": dict(sw=7, sh=6, lr=4.5, brow=2), "M3": dict(sw=10, sh=8.5, lr=6.5, brow=0)}


def octo(G, hx, hy, z0, z1, c=5, ct=3):
    """팔각 머리통: 위에서 본 팔각(모서리 c) + 위 모서리 45° ct."""
    X, Y, Z = G; ax, ay = np.abs(X), np.abs(Y + 1)
    m = (ax <= hx) & (ay <= hy) & (Z >= z0) & (Z <= z1) & (ax + ay <= hx + hy - c)
    m &= (Z <= z1 - np.clip(ax - (hx - ct), 0, None)) & (Z <= z1 - np.clip(ay - (hy - ct), 0, None))
    return m


def build_head(M, v="M1", parent=None, tall=0):
    """tall > 0 (r2): 머리를 tall 칸 길게(아래로) + 위로 갈수록 좁아짐(1:6) — 정사각 상자 느낌 줄임."""
    p = V[v]
    H = M.part("Head", (-24, -22, 216), (25, 20, 266), pivot=(0, 0, 236), parent=parent)
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    z0 = 236 - tall
    H.add(cyl(G, "z", (0, 0), 8, rng=(z0 - 8, z0 + 1)), 3)                                       # 목
    body = octo(G, 14 if not tall else 12, 15, z0, 259 + (2 if tall else 0))
    if tall:
        body &= (ax <= 12 - np.clip(Z - 252, 0, None) / 3.0)                                       # 위쪽 좁아짐
    H.add(body, 1)
    tw = 9 if not tall else 7
    zt = 259 + (2 if tall else 0)
    H.add(cbox(G, (-tw, tw), (-9, 9), (zt, zt + 2), {"xy": 2}), 1)                                 # 위 덮개 판
    H.groove((ax <= tw) & (np.abs(Y + 1) <= 9) & (Z == zt + 1) & ((ax == tw) | (np.abs(Y + 1) == 9)), 4)
    zc = 248.5 - (tall * 0.3 if tall else 0)
    sock = (ax <= p["sw"]) & (np.abs(Z - zc) <= p["sh"]) & (Y <= -10)                            # 정면 사각 홈
    H.cut(sock)
    H.add((ax <= p["sw"]) & (np.abs(Z - zc) <= p["sh"]) & (Y == -9), 4)
    H.add((ax <= p["sw"] + 1) & (np.abs(Z - zc) <= p["sh"] + 1) & ((ax >= p["sw"]) | (np.abs(Z - zc) >= p["sh"])) & (Y >= -16) & (Y <= -14) & (H.a == 0), 2)   # 홈 테(짙은 회색)
    ring = 2.5 if tall else 1.5                                                                   # r2: 어두운 링 두껍게(눈동자처럼)
    H.add(cyl(G, "y", (0, zc), p["lr"] + ring, rng=(-11, -10)), 3 if tall else 2)               # 렌즈 테
    H.add(cyl(G, "y", (0, zc), p["lr"] - (0.5 if tall else 0), rng=(-12, -11)), 6)              # 렌즈(발광)
    if p["brow"]:
        H.add((ax <= p["sw"] + 3) & (Z >= zc + p["sh"] + 1) & (Z <= zc + p["sh"] + 2) & (Y >= -18) & (Y <= -14), 1)   # 이마 처마
    H.add(cbox(G, (-6, 6), (-15, -8), (z0 - 4, z0 + 3), {"xy": 2, "-y-z": 2}), 3)                 # 짙은 턱
    if tall:                                                                                       # 홈 테 단차: 홈 둘레 1칸 돋움(짙은 회색) + 볼판 2칸
        H.emboss((ax <= p["sw"] + 2) & (np.abs(Z - zc) <= p["sh"] + 2) & ((ax > p["sw"]) | (np.abs(Z - zc) > p["sh"])) & (Y < -12), 2)
    for s in (1, -1):                                                                              # 볼판(비스듬)
        H.emboss((ax >= 10) & (ax <= 13) & (Z >= z0 + 1) & (Z <= 247) & (Y <= -6), 1, h=2 if tall else 1)
        e0 = 12 if tall else 14                                                                    # r2: 머리통이 좁아져 귀를 몸에 붙임(섬 방지)
        lo_, hi_ = sorted((s * e0, s * (e0 + 5)))                                                  # 귀(팔각 원통)
        ear = (np.abs(Y - 1) <= 5) & (np.abs(Z - 247) <= 5) & (np.abs(Y - 1) + np.abs(Z - 247) <= 7) & (X >= lo_) & (X <= hi_)
        H.add(ear, 1)
        H.add(ear & (ax >= e0 + 4) & (np.abs(Y - 1) + np.abs(Z - 247) <= 3.5), 2)
        H.add((ax >= e0) & (ax <= e0 + 1) & (np.abs(Y - 1) <= 6) & (np.abs(Z - 247) <= 6) & (np.abs(Y - 1) + np.abs(Z - 247) <= 8.5) & (H.a == 0), 2)
    H.trim()
    return H


def collar(M):
    """비교용 회색 깃 + 흉판 윗부분(몸통 시안 전 임시)."""
    T = M.part("CollarStub", (-40, -24, 205), (41, 22, 240))
    G = T.g(); X, Y, Z = G
    T.add(cbox(G, (-38, 38), (-20, 18), (206, 232), {"xy": 6, "+z-y": 5, "+zx": 4}), 2)
    T.cut((np.abs(X) <= 12) & (Z >= 228))
    T.add(cbox(G, (-36, 36), (-21, -12), (206, 214), {"xz": 3}), 1)
    T.trim()


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    R = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형2")
    mn = Image.open(os.path.join(R, "concept_v1_메인.png")).convert("RGB")
    con = Image.open(os.path.join(R, "concept_v1_삼면도.png")).convert("RGB")
    TALL = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    rows = []
    for v in ("M1", "M2", "M3"):
        M = fv.Model(); collar(M); build_head(M, v, tall=TALL)
        p = M.parts["Head"]; _, k = ndimage.label(p.a > 0)
        print(v, "Head tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = [vp.render(M.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=8, ss=2, ao_amt=0.5, bg=(200, 200, 200), light=(-0.75, -0.55, 0.6))
               for y, pt in ((0, 3), (-30, 10), (-90, 3), (150, 12))]
        rows.append((NAMES[v], ims))
    H = max(i.height for _, ims in rows for i in ims)
    refs = [(mn.crop((380, 80, 640, 330)), "메인"), (con.crop((180, 70, 350, 220)), "삼면도 정면"), (con.crop((580, 70, 720, 220)), "옆")]
    refs = [(c.resize((int(c.width * H / c.height), H)), t) for c, t in refs]
    W = max(sum(i.width for i in ims) for _, ims in rows) + 16 * 6
    W = max(W, sum(c.width for c, _ in refs) + 16 * 4)
    sh = Image.new("RGB", (W, 60 + 4 * (H + 46)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "새 표준 양산기 ST-10 머리 r%s — 팔각 머리통 · 사각 홈 속 둥근 렌즈 · 귀 포드" % ("2 (9칸 길게 · 폭 좁게 · 위로 좁아짐 · 렌즈 링 두껍게 · 홈 테·볼판 단차)" if TALL else "1"), fill=(235, 235, 235), font=ft)
    for r_, (nm, ims) in enumerate([("컨셉", [c for c, _ in refs])] + rows):
        y0 = 60 + r_ * (H + 46); x = 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
    p = os.path.join(out, "시안_머리r1.png" if not TALL else "시안_머리r2_길쭉.png"); sh.save(p); print(p, sh.size)
