"""새 표준 양산기 머리 r4 — 그림 색 지도 이식(2026-11-04).
근거: 유저가 공유한 「복셀 제작 방식 비교 — 손 설계 vs 그림 색 지도 이식(11-03, VALKYRIE 방패)」 — 정면은 그림 픽셀을 색으로 나눠 칸에 그대로,
두께·뒤·관절만 직접 설계. 방패 2차에서 흰색 차이 14.6%p → 2.7%p.
여기서:
  1) 삼면도 정면 머리(x195~335, y78~160)를 5색으로 분류(배경 · 모래 · 짙은 회색 · 짙은 프레임/검정 · 청록 발광) — 경계값 아래 classify().
  2) 칸 크기(0.301칸/px)로 줄이며 블록 다수결 · 좌우 대칭(양쪽 표 합산) · 3×3 다수결 1회(발광 제외) · 5칸 미만 조각은 주변 색으로.
  3) 모양: 정면 지도 실루엣 × r3 앞뒤 길이(앞뒤 40칸, 뒤 윗모서리 1:2) — 귀(|X|>12)는 귀 두께(|Y−1|≤6)만.
  4) 앞면 단차(지도 색 → 깊이): 검정 = 3칸 파냄(사각 홈) · 발광 = 3칸 파고 바닥에 발광 · 짙은 회색·프레임 = 1칸 파냄 · 모래 = 그대로.
  5) 옆·위·뒤 = 모래(귀 테 짙은 회색), 목 = 짙은 프레임.
  6) 그림과 같은 방향(정면)으로 렌더해 색 비율 비교.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox  # noqa: E402
import m2_head_r1 as h1  # noqa: E402

SRC = os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형2", "concept_v1_삼면도.png")
K = 0.301; CXP = 265; FOOT = 943
BOX = (195, 78, 336, 149)                                      # 정면 머리(턱까지 — y150 아래는 깃 윗면·그늘)
BG, SAND, GRAY, DARK, GLOW = 0, 1, 2, 3, 6


def classify(a):
    a = a.astype(int); r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = (r + g + b) / 3.0
    c = np.full(r.shape, GRAY, np.uint8)
    c[lum < 62] = DARK
    c[(r - b > 10) & (lum > 105)] = SAND                       # 따뜻한 밝은 색 = 모래(그늘진 모래 포함)
    c[(lum > 165) & (r - b > 4)] = SAND
    c[(g > 140) & (b > 150) & (g - r > 45)] = GLOW
    bg = (np.abs(r - 213) < 12) & (np.abs(g - 215) < 12) & (np.abs(b - 216) < 12)
    c[bg] = BG
    return c


def cell_map():
    im = np.asarray(Image.open(SRC).convert("RGB"))
    x0, y0, x1, y1 = BOX
    cls = classify(im[y0:y1, x0:x1])
    xs = np.arange(int(np.floor((x0 - CXP) * K)), int(np.ceil((x1 - CXP) * K)) + 1)
    zs = np.arange(int(np.floor((FOOT - y1) * K)), int(np.ceil((FOOT - y0) * K)) + 1)
    votes = np.zeros((len(xs), len(zs), 7), int)
    py, px = np.mgrid[y0:y1, x0:x1]
    cx = np.round((px - CXP) * K).astype(int) - xs[0]; cz = np.round((FOOT - py) * K).astype(int) - zs[0]
    np.add.at(votes, (cx.ravel(), cz.ravel(), cls.ravel()), 1)
    # 좌우 대칭: 그림이 살짝 돌아가 좌우 귀 위치가 2~3px 다름 → 표를 그냥 더하면 귀가 배경과 상쇄됨(1차).
    # 한쪽이라도 배경이 아니면(배경 표 < 절반) 두 쪽 비배경 표를 합쳐 색을 정함.
    vm = votes[::-1]
    side_fg = lambda v: v[..., BG] < 0.5 * v.sum(2)
    fg = side_fg(votes) | side_fg(vm)
    nb = (votes + vm).copy(); nb[..., BG] = 0
    m = np.where(fg, nb.argmax(2), BG).astype(np.uint8)
    m[np.abs(xs) > 18] = BG                                     # 귀 바깥(|X|>18) = 깃 어깨(머리 아님)
    ear = np.abs(xs) > 12
    m[ear[:, None] & (m == DARK)] = BG                          # 귀 밑 그늘(검정 띠로 튀어나옴) 제거
    # 3×3 다수결 1회(발광 제외)
    out = m.copy()
    for i in range(1, m.shape[0] - 1):
        for j in range(1, m.shape[1] - 1):
            if m[i, j] in (GLOW, BG):
                continue
            w = m[i - 1:i + 2, j - 1:j + 2].ravel(); w = w[(w != BG)]
            v = np.bincount(w, minlength=7); v[GLOW] = 0
            if v.max() >= 5:
                out[i, j] = v.argmax()
    # 1차 [관찰]: 머리 옆·아래의 깃 구멍 그늘(검정)까지 머리로 읽힘 → 줄마다 모래·회색·발광이 있는 범위 밖의 검정 = 배경
    for j in range(out.shape[1]):
        keep = np.nonzero((out[:, j] == SAND) | (out[:, j] == GRAY) | (out[:, j] == GLOW))[0]
        if len(keep) == 0:
            out[:, j][out[:, j] == DARK] = BG
            continue
        row = out[:, j]; row[:keep.min()][row[:keep.min()] == DARK] = BG; row[keep.max() + 1:][row[keep.max() + 1:] == DARK] = BG
    from scipy import ndimage
    for col in (SAND, GRAY):                                    # 5칸 미만 조각 → 주변 다수 색
        lab, n = ndimage.label(out == col)
        for k in range(1, n + 1):
            reg = lab == k
            if reg.sum() < 5:
                ring = ndimage.binary_dilation(reg) & ~reg & (out != BG)
                if ring.any():
                    out[reg] = np.bincount(out[ring], minlength=7).argmax()
    return xs, zs, out, cls


def build(M, deep=10, parent=None):
    xs, zs, mp, _ = cell_map()
    F = -deep
    H = M.part("Head", (int(xs[0]) - 2, -26 + F, 224), (int(xs[-1]) + 3, 22, 266), pivot=(0, 0, 236), parent=parent)
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    shp = H.a.shape
    ix = np.clip(np.broadcast_to(X, shp) - xs[0], 0, len(xs) - 1); iz = np.clip(np.broadcast_to(Z, shp) - zs[0], 0, len(zs) - 1)
    inx = (np.broadcast_to(X, shp) >= xs[0]) & (np.broadcast_to(X, shp) <= xs[-1]) & (np.broadcast_to(Z, shp) >= zs[0]) & (np.broadcast_to(Z, shp) <= zs[-1])
    col = np.where(inx, mp[ix, iz], BG)
    yc0 = -1 + F / 2.0; hy = 15 + deep / 2.0
    dep = (np.abs(np.broadcast_to(Y, shp) - yc0) <= hy) & (np.broadcast_to(Z, shp) <= 259 - np.clip(np.broadcast_to(Y, shp) - 4, 0, None) / 2.0)
    dep &= (np.broadcast_to(Z, shp) <= 259 - np.clip(-(np.broadcast_to(Y, shp) - yc0) - (hy - 3), 0, None) + 1)
    ear = ax > 12
    ey = np.abs(np.broadcast_to(Y, shp) - 1); ez = np.abs(np.broadcast_to(Z, shp) - 247)
    dep &= ~np.broadcast_to(ear, shp) | ((ey <= 6) & (ey + ez <= 9))                            # 귀 = 팔각 원통 단면
    solid = (col != BG) & dep
    H.a[solid] = SAND
    # 앞면 단차 + 색: 기둥(x,z)마다 지도 색에 따라 파고 칠함
    yfront = np.where(solid.any(1), solid.argmax(1), -1)       # 기둥마다 가장 앞 칸(배열 Y 인덱스)
    depth = {DARK: 3, GLOW: 2, GRAY: 1, SAND: 0}                                                # 렌즈는 홈 바닥보다 1칸 앞(튀어나온 눈)
    for i in range(shp[0]):
        for k in range(shp[2]):
            j = yfront[i, k]
            if j < 0:
                continue
            c = col[i, j, k]; d = depth.get(int(c), 0)
            if ear[i, 0, 0]:
                d = 0
            H.a[i, j:j + d, k] = 0
            jj = min(j + d, shp[1] - 1)
            if H.a[i, jj, k]:
                H.a[i, jj, k] = {DARK: 4, GLOW: 6, GRAY: 2, SAND: 1}[int(c)]
    # 귀 바깥 면: 지도 색(바깥에서 본 테·가운데)
    for s in (1, -1):
        H.add(cyl(G, "x", (1, 247), 2.2, rng=sorted((s * 17, s * 18))) & (H.a > 0), 2)
    H.add(cbox(G, (-9, 9), (F - 6, 4), (260, 261), {"xy": 2}) & ~(H.a > 0), 1)                  # 위 덮개 판(정면 지도엔 안 보이는 윗면, r3 과 같음)
    H.groove((ax <= 9) & (np.broadcast_to(Y, shp) >= F - 6) & (np.broadcast_to(Y, shp) <= 4) & (Z == 261) & ((ax == 9) | (Y == F - 6) | (Y == 4)), 4)
    H.add(cyl(G, "z", (0, 0), 8, rng=(226, 237)) & ~(H.a > 0), 3)                              # 목
    from scipy import ndimage                                                                     # 지도 가장자리 외톨이 칸(귀 밑 모서리) 제거
    lab, n = ndimage.label(H.a > 0)
    if n > 1:
        big = np.bincount(lab.ravel())[1:].argmax() + 1
        H.a[(lab != big) & (lab > 0)] = 0
    H.trim()
    return H


EAR_GEOM = False


def build_clean(M, deep=10, parent=None):
    """r5 [결정 11-04 "다음 판 + 색 분할이 지저분한 것도 해결"]: 실루엣·크기·위치는 색 지도에서, 안쪽 색은 지도에서 맞춘 도형으로 다시 그림.
      사각 홈 = 지도 검정(가운데 |X|≤11)의 경계 상자 · 렌즈 = 발광 칸 무게중심 + 넓이로 반지름 · 턱 = 홈 아래 검정 · 귀 = 실루엣 + 테·가운데 원.
      그 위에 r3 판 단차: 홈 테(짙은 회색) 1칸 돋움 · 이마 판 1칸 · 볼판 2칸(홈 옆 아래) · 위 덮개 판."""
    xs, zs, mp, _ = cell_map()
    X2, Z2 = np.meshgrid(xs, zs, indexing="ij")
    dk = (mp == DARK) & (np.abs(X2) <= 11) & (Z2 >= 241)
    sw = int(np.abs(X2[dk]).max()); s0, s1 = int(Z2[dk].min()), int(Z2[dk].max())
    gl = mp == GLOW
    lz = float(Z2[gl].mean()); lr = float(np.sqrt(gl.sum() / np.pi)) * 1.3                       # 발광 핵만 잡혀 작음 → 그림의 렌즈 원판 크기로
    chin = (mp == DARK) & (Z2 < s0) & (np.abs(X2) <= 8)
    sil = mp != BG
    F = -deep
    H = M.part("Head", (int(xs[0]) - 2, -26 + F, 224), (int(xs[-1]) + 3, 22, 266), pivot=(0, 0, 236), parent=parent)
    G = H.g(); X, Y, Z = G; shp = H.a.shape
    Xb, Yb, Zb = [np.broadcast_to(A, shp) for A in G]; ax = np.abs(Xb)
    ix = np.clip(Xb - xs[0], 0, len(xs) - 1); iz = np.clip(Zb - zs[0], 0, len(zs) - 1)
    inmap = (Xb >= xs[0]) & (Xb <= xs[-1]) & (Zb >= zs[0]) & (Zb <= zs[-1])
    silb = inmap & sil[ix, iz]
    yc0 = -1 + F / 2.0; hy = 15 + deep / 2.0
    dep = (np.abs(Yb - yc0) <= hy) & (Zb <= 259 - np.clip(Yb - 4, 0, None) / 2.0) & (Zb <= 259 - np.clip(-(Yb - yc0) - (hy - 3), 0, None) + 1)
    ear = ax > 12
    ey = np.abs(Yb - 1); ez = np.abs(Zb - 247)
    dep &= ~ear | ((ey <= 6) & (ey + ez <= 9))
    if EAR_GEOM:
        silb = silb & ~ear                                                                         # r6: 귀는 지도 대신 도형으로(아래)
    H.a[silb & dep] = SAND
    yfront = np.where((H.a > 0).any(1), (H.a > 0).argmax(1), -1)[:, None, :] + H.lo[1]         # 기둥 앞면 Y
    face = (Yb >= yfront) & (Yb <= yfront) & ~ear
    # 사각 홈(3칸) · 렌즈 · 홈 테
    sock = (ax <= sw) & (Zb >= s0) & (Zb <= s1) & ~ear
    H.cut(sock & (Yb < yfront + 3))
    H.add(sock & (Yb == yfront + 3), 4)
    lens_r = (Xb ** 2 + (Zb - lz) ** 2)
    H.add(sock & (Yb == yfront + 2) & (lens_r <= (lr + 1.6) ** 2), 3)                              # 렌즈 테(짙은)
    H.add(sock & (Yb == yfront + 1) & (lens_r <= lr ** 2 + 0.5), 6)                                # 렌즈(홈 바닥보다 2칸 앞)
    H.add(sock & (Yb == yfront + 2) & (lens_r <= lr ** 2 + 0.5), 6)
    rim = (ax <= sw + 1) & (Zb >= s0 - 1) & (Zb <= s1 + 1) & ~((ax <= sw) & (Zb >= s0) & (Zb <= s1))
    H.emboss(rim & ~ear & (Yb < F - 8), 2)                                                         # 홈 테 1칸 돋움(앞면만 — 1차는 뒷면에도 붙음)
    # 턱(검정 → 짙은 프레임, 1칸 들어감)
    chb = inmap & chin[ix, iz]
    H.cut(chb & (Yb == yfront)); H.paint(chb & (Yb == yfront + 1), 3)
    if not EAR_GEOM:
        H.emboss((ax <= sw + 2) & (Zb >= s1 + 2) & (Zb <= 257) & (Yb < -10 + F), 1)
        H.emboss((ax >= sw + 2) & (ax <= 12) & (Zb >= s0 - 3) & (Zb <= int(lz)) & (Yb < -8 + F), 1, h=2)
        ring = (np.sqrt((Yb - 1) ** 2 + (Zb - 247) ** 2) <= 4.2) & (np.sqrt((Yb - 1) ** 2 + (Zb - 247) ** 2) >= 2.8)
        surf = H.surface()
        P_ = np.pad(H.a > 0, 1); outward = (~P_[2:, 1:-1, 1:-1] & (Xb > 0)) | (~P_[:-2, 1:-1, 1:-1] & (Xb < 0))
        H.paint(surf & outward & ear & ring & (ax >= 15), 2)
        H.paint(surf & outward & ear & (np.sqrt((Yb - 1) ** 2 + (Zb - 247) ** 2) < 2.8) & (ax >= 15), 3)
        H.add(cbox(G, (-9, 9), (F - 6, 4), (260, 261), {"xy": 2}) & ~(H.a > 0), 1)
        H.groove((ax <= 9) & (Yb >= F - 6) & (Yb <= 4) & (Zb == 261) & ((ax == 9) | (Yb == F - 6) | (Yb == 4)), 4)
    else:
        # r6 [유저 표시 11-04] ① 귀 = 가운데 회색 원 하나 + 귀를 크게 감싸는 회색 테 ② 앞에서 봐도 둥글게 ③ 머리 둘레 디테일(위 해치 · 볼판)
        rr = np.sqrt((Yb - 1) ** 2 + (Zb - 247) ** 2)
        dome = (ax >= 12) & ((ax - 11) ** 2 + rr ** 2 <= 7.2 ** 2)                                  # 반구 귀(앞에서도 둥근 윤곽)
        H.add(dome & ~(H.a > 0), SAND)
        H.add((ax >= 11) & (ax <= 13) & (rr <= 8.2) & (rr >= 5.5), 2)                               # 귀 둘레 큰 회색 테
        H.paint(dome & (rr <= 2.6), 2)                                                              # 가운데 회색 원 하나
        # 볼판: 홈 양옆 세로 판 1칸 돋움 + 홈 쪽 이음매 + 가로 이음매 + 아래 모서리 45°
        cheek = (ax >= sw + 3) & (ax <= 12) & (Zb >= 238) & (Zb <= 256) & (Zb >= 238 + np.clip(ax - (sw + 3) - 2, 0, None))
        H.emboss(cheek & (Yb < -6 + F), 1)
        H.groove((ax == sw + 2) & (Zb >= 239) & (Zb <= 255) & (Yb < -6 + F), 4)
        # (1차: 볼판 가로 이음매는 옆에서 금 간 줄처럼 보여 뺌)
        # 이마 판(홈 위) 1칸
        H.emboss((ax <= sw + 1) & (Zb >= s1 + 2) & (Zb <= 257) & (Yb < -10 + F), 1)
        # 위 해치: 앞쪽 윗면 돋운 판 + 테두리 홈 + 손잡이 홈 2
        hy0, hy1 = F - 12, F + 2
        H.add(cbox(G, (-8, 8), (hy0, hy1), (260, 261), {"xy": 2}) & ~(H.a > 0), 1)
        H.groove((ax <= 8) & (Yb >= hy0) & (Yb <= hy1) & (Zb == 261) & ((ax == 8) | (Yb == hy0) | (Yb == hy1)), 4)
        # (1차: 해치 손잡이 홈 2 는 1~2칸 점으로 보여 뺌)
        # (1차: 해치 뒤 가로 이음매는 옆 윤곽에 홈 점으로 보여 뺌)
    H.add(cyl(G, "z", (0, 0), 8, rng=(226, 241)) & ~(H.a > 0), 3)                                 # 목(머리 아랫면까지 — 1차는 떨어져 섬으로 지워짐)
    from scipy import ndimage
    lab, n = ndimage.label(H.a > 0)
    if n > 1:
        big = np.bincount(lab.ravel())[1:].argmax() + 1
        H.a[(lab != big) & (lab > 0)] = 0
    H.trim()
    M.extra["head_fit"] = dict(socket_half=sw, socket_z=(s0, s1), lens_z=round(lz, 1), lens_r=round(lr, 2))
    return H


def ratios_concept():
    xs, zs, mp, cls = cell_map()
    v = np.bincount(mp.ravel(), minlength=7)[[SAND, GRAY, DARK, GLOW]].astype(float)          # 정리한 칸 지도 기준(머리 실루엣 안)
    return v / v.sum()


def ratios_model(M):
    p = M.parts["Head"]; a = p.a.copy()
    a[:, :, : max(0, 239 - p.lo[2])] = 0                                                        # 목 제외(머리만)
    has = (a > 0).any(1); j = (a > 0).argmax(1)
    c = np.take_along_axis(a, j[:, None, :], 1)[:, 0, :][has]
    grp = {1: 0, 2: 1, 3: 2, 4: 2, 7: 1, 6: 3}
    v = np.zeros(4)
    for k, g in grp.items():
        v[g] += (c == k).sum()
    return v / v.sum()


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    xs, zs, mp, cls = cell_map()
    pal = {BG: (213, 215, 216), SAND: h1.PAL[1], GRAY: h1.PAL[2], DARK: h1.PAL[4], GLOW: h1.PAL[6]}
    lut = np.array([pal.get(i, (255, 0, 255)) for i in range(7)], np.uint8)
    mapimg = Image.fromarray(lut[mp.T[::-1]]).resize((len(xs) * 12, len(zs) * 12), Image.NEAREST)
    clsimg = Image.fromarray(lut[cls]).resize(((BOX[2] - BOX[0]) * 3, (BOX[3] - BOX[1]) * 3), Image.NEAREST)
    rows = []

    for nm, M in (("r5 (전)", "clean"), ("r6 귀 반구 + 회색 테·원 · 볼판 · 위 해치", "r6")):
        Mm = fv.Model(); h1.collar(Mm)
        if M in ("clean", "r6"):
            globals()["EAR_GEOM"] = (M == "r6")
            build_clean(Mm, deep=10)
        else:
            build(Mm, deep=10)
        p = Mm.parts["Head"]; _, k = ndimage.label(p.a > 0)
        rr = ratios_model(Mm)
        print(nm, "tris", 2 * greedy_quads(p.a), "섬", k - 1, "정면 색 비율 모래/짙은회색/검정/발광", (rr * 100).round(1))
        ims = [vp.render(Mm.blocks(), h1.PAL, h1.EMISSIVE, yaw=y, pitch=pt, ppc=8, ss=2, ao_amt=0.5, bg=(200, 200, 200), light=(-0.75, -0.55, 0.6))
               for y, pt in ((0, 3), (-30, 10), (-90, 3), (150, 12))]
        rows.append(("%s — 정면 칸 색: 모래 %.0f%% · 짙은 회색 %.0f%% · 검정 %.0f%% · 발광 %.0f%%" % ((nm,) + tuple(rr * 100)), ims))
    rc = ratios_concept()
    print("컨셉 픽셀 비율", (rc * 100).round(1))
    con = Image.open(SRC).convert("RGB").crop(BOX).resize(((BOX[2] - BOX[0]) * 3, (BOX[3] - BOX[1]) * 3))
    H = max(i.height for _, ims in rows for i in ims)
    W = max(sum(i.width for i in ims) for _, ims in rows) + 16 * 6
    top = [con, clsimg, mapimg]
    Ht = max(i.height for i in top)
    sh = Image.new("RGB", (max(W, sum(i.width for i in top) + 64), 60 + Ht + 60 + 2 * (H + 46)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "새 양산기 머리 r6 — 귀 · 머리 둘레 디테일 (컨셉 · 픽셀 분류 · 칸 지도)", fill=(235, 235, 235), font=ft)
    x = 16
    for im in top:
        sh.paste(im, (x, 60)); x += im.width + 16
    d.text((16, 60 + Ht + 10), "컨셉 칸 지도 비율(머리 안): 모래 %.0f%% · 짙은 회색 %.0f%% · 검정 %.0f%% · 발광 %.0f%%" % tuple(rc * 100), fill=(255, 190, 90), font=f)
    y0 = 60 + Ht + 60
    for nm, ims in rows:
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f); x = 16
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
        y0 += H + 46
    p = os.path.join(out, "시안_머리r6_귀디테일.png"); sh.save(p); print(p, sh.size)
