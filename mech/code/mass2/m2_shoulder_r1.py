"""새 표준 양산기 ST-10 어깨 r1 (2026-11-04). 가슴 확정(m2_chest_r1.build_all(final=True)) 위에.
[읽기: 삼면도 1152 축소 · 칸/px = 0.401 × 폭 0.92 = 0.37 · 머리 가운데 x≈197]
  R 오른 어깨(−X, 그림 왼쪽): 모래 상자 x45~115 → X −56~−30 · y105~185 → z242~210 · 모서리 깎음 · 붉은 가로줄(데칼)
     안쪽 위는 짙은 회색 멍에 끝 · 아래는 위팔(다음 단계)
  L 왼 어깨(+X): 모래 알 돔 x285~380 → X 32~66 · y80~190 → z252~208 · 옆에서 x505~625 → 앞뒤 44칸(둥근 원)
     안쪽에 짙은 회색 테(돔을 받치는 컵) · 붉은 세로줄(데칼) · 구멍 3(앞 아래 · 뒤 아래 · 바깥 아래)
  둘 다 아래에 짙은 회색 어깨 관절(X 축 원통).
돔은 공 대신 정수 기울기 면만 쓰는 다면체(스타일 [결정]: 구 대신 45° 다각) — 타원체에 외접하는 평면들:
  a = 축 + 45°(1,1) + 꼭짓점(1,1,1) → 큰 면 8각
  b = a + 1:2 / 2:1 면 → 16각, 더 둥글게
색: 1 모래 · 2 짙은 회색 · 3 짙은 프레임 · 4 검정 · 5 빨강(데칼 미리보기만)."""
import itertools
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, cbox  # noqa: E402
import m2_chest_r1 as ch  # noqa: E402

PAL, EMISSIVE = ch.PAL, ch.EMISSIVE
SJ = (32, 0, 227)                                                                                    # 어깨 관절 중심(|X|)


def facet_ellipsoid(G, c, r, dirs, k=1.0):
    """타원체(중심 c, 반지름 r)에 외접하는 평면들의 교집합. dirs = 정수 법선(양수 성분 · 부호는 모두 돌림). k<1 이면 비스듬한 면을 더 깎음."""
    X, Y, Z = G
    d = [np.abs(X - c[0]), np.abs(Y - c[1]), np.abs(Z - c[2])]
    m = np.ones(np.broadcast_shapes(*(a.shape for a in d)), bool)
    for n in dirs:
        h = np.sqrt(sum((n[i] * r[i]) ** 2 for i in range(3)))
        kk = 1.0 if sum(1 for v in n if v) == 1 else k
        m &= (n[0] * d[0] + n[1] * d[1] + n[2] * d[2] <= h * kk + 0.25)
    return m


def _perm(base):
    return sorted(set(itertools.permutations(base)))


DIRS_A = _perm((1, 0, 0)) + _perm((1, 1, 0)) + [(1, 1, 1)]
DIRS_B = DIRS_A + _perm((1, 2, 0)) + _perm((1, 1, 2))


def joint(M, s):
    """짙은 회색 어깨 관절(X 축) — 몸통 옆에서 바깥으로."""
    nm = "ShoulderJointL" if s > 0 else "ShoulderJointR"
    J = M.part(nm, (-40, -12, 215), (41, 12, 240), pivot=(s * SJ[0], 0, SJ[2]), parent="Torso")
    G = J.g(); X, Y, Z = G
    xr = (26, 36) if s > 0 else (-36, -26)
    J.add(cyl(G, "x", (0, SJ[2]), 8.5, rng=xr), 2)
    J.add(cyl(G, "x", (0, SJ[2]), 9.5, rng=(xr[0] + 2, xr[0] + 3) if s > 0 else (xr[1] - 3, xr[1] - 2)), 2)   # 테 1칸
    J.groove(cyl(G, "x", (0, SJ[2]), 5.5, rng=(-40, 40)) & ~cyl(G, "x", (0, SJ[2]), 4.5, rng=(-40, 40)) & (np.abs(X) >= 34), 3)
    J.trim()
    return J


def surf_hole(P, c, u, r=2.2, depth=2, rim=True):
    """중심 c 에서 방향 u 로 나간 겉면 자리에 구멍: 깊이 depth 파고 바닥 검정 · 둘레 짙은 회색 테 1칸(칠)."""
    X, Y, Z = P.g(); u = np.array(u, float); u /= np.linalg.norm(u)
    dx, dy, dz = X - c[0], Y - c[1], Z - c[2]
    t = dx * u[0] + dy * u[1] + dz * u[2]
    perp = np.sqrt(np.maximum(dx ** 2 + dy ** 2 + dz ** 2 - t ** 2, 0))
    t = np.broadcast_to(t, P.a.shape); perp = np.broadcast_to(perp, P.a.shape)
    tm = t[(P.a > 0) & (perp <= r)].max()
    if rim:
        P.paint_s((perp > r) & (perp <= r + 1.2) & (t >= tm - 3), 2)
    P.cut((perp <= r) & (t > tm - depth))
    P.a[(perp <= r) & (t <= tm - depth) & (t > tm - depth - 1.5) & (P.a > 0)] = 4


def dome_L(M, var="a"):
    """왼 어깨 돔(+X) + 안쪽 짙은 회색 컵.
    1차: 돔 중심 X46 · 컵 X29~34 가 돔 뒤에 숨어 안 보이고 돔이 몸통에서 떠 보임 · 구멍이 점 → 중심 X44 · 컵을 3칸 크게(X27~35) · 구멍 r2.2 + 테."""
    D = M.part("ShoulderArmorL", (22, -28, 202), (70, 28, 260), pivot=(SJ[0], 0, SJ[2]), parent="Torso")
    G = D.g(); X, Y, Z = G
    c, r = (44, 0, 231), (19, 21, 22)
    dirs = DIRS_A if var == "a" else DIRS_B
    body = facet_ellipsoid(G, c, r, dirs, k=0.97) & (X >= 33)
    D.add(body, 1)
    for k_, xk in enumerate(range(28, 36)):                                                         # 컵: 안쪽(X28) 작게 → 바깥(X35) 돔보다 2칸 크게, 1칸에 1칸씩 넓어짐(45°)
        g = min(2, -5 + k_)                                                                        # 2차: 평평한 원판(X27~35 같은 크기)은 따로 붙은 판처럼 보임
        D.add(facet_ellipsoid(G, c, (r[0] + g, r[1] + g, r[2] + g), dirs, k=0.97) & (X == xk) & ~(D.a > 0), 2)
    D.groove((X == 36) & body, 4)                                                                    # 돔·컵 이음
    for u in ((0.35, -1, -0.45), (0.35, 1, -0.45), (1, 0, -0.55)):                                  # 앞 아래 · 뒤 아래 · 바깥 아래
        surf_hole(D, c, u)
    D.trim()
    return D


def block_R(M, var="a"):
    """오른 어깨 상자(−X): 모서리 깎은 모래 상자.
    1차: 앞뒤 30칸·모서리 4칸 → 뚱뚱한 직육면체 → 앞뒤 24칸 · 세로 모서리 6칸(위에서 8각) · 위 바깥 큰 45°."""
    B = M.part("ShoulderArmorR", (-60, -20, 204), (-26, 20, 246), pivot=(-SJ[0], 0, SJ[2]), parent="Torso")
    G = B.g(); X, Y, Z = G
    x0, x1, z0, z1 = -56, -31, 210, 242
    B.add(cbox(G, (x0, x1), (-12, 12), (z0, z1), {"xy": 6, "-x+z": 7, "-x-z": 4, "yz": 4, "+x+z": 2}), 1)
    B.add(cbox(G, (x1 + 1, x1 + 4), (-9, 9), (z0 + 4, z1 - 3), {"yz": 2}) & ~(B.a > 0), 2)          # 안쪽 짙은 받침
    if var == "b":
        B.groove((Z == 225) & (X <= x1 - 1), 4)                                                     # 가로 이음매(줄무늬 아래)
    surf_hole(B, (-43, 0, 216), (0, -1, 0), r=1.6)                                                   # 앞 아래 볼트 구멍
    B.trim()
    return B


def build_all(var="a", stripes=False):
    M = ch.build_all(final=True)
    for s in (1, -1):
        joint(M, s)
    dome_L(M, var); block_R(M, var)
    if stripes:
        paint_stripes(M)
    return M


def paint_stripes(M):
    """데칼 미리보기(모델엔 안 넣음): 돔 세로 줄(위→앞 아래, 바깥 쪽) · 상자 가로 줄."""
    D = M.parts["ShoulderArmorL"]; G = D.g(); X, Y, Z = G
    D.paint_s((np.abs(Y - 0.5 * (X - 44) + 0.3 * (Z - 231) - 1) <= 2.6) & (X >= 38), 5)
    B = M.parts["ShoulderArmorR"]; G = B.g(); X, Y, Z = G
    B.paint_s((Z >= 228) & (Z <= 232) & (X <= -36), 5)


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import m2_head_trace as ht
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 22); ft = ImageFont.truetype(FN, 26)
    V = ((0, 3), (-35, 10), (-90, 3), (90, 3), (150, 8))
    rows = []
    for v, lab in (("a", "a  돔 8각(축 + 45° + 꼭짓점 면)"), ("b", "b  돔 16각(a + 1:2 면 — 더 둥글게)")):
        M = build_all(v, stripes=False); cm.check(M)
        M2 = build_all(v, stripes=True)
        rows.append((lab + " · 붉은 줄 = 데칼 미리보기", [vp.render(M2.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=4, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in V]))
    con = Image.open(ht.SRC).convert("RGB"); mn = Image.open(os.path.join(os.path.dirname(ht.SRC), "concept_v1_메인.png")).convert("RGB")
    H = max(i.height for _, r in rows for i in r)
    refs = [con.crop((40, 60, 540, 420)), mn.crop((150, 80, 900, 620)), con.crop((600, 60, 900, 420)), con.crop((990, 60, 1500, 420))]
    refs = [x.resize((int(x.width * H / x.height), H)) for x in refs]
    rows.insert(0, ("원본 아트(정면 · 메인 · 옆 · 뒤)", refs))
    W = max(sum(i.width + 16 for i in r) for _, r in rows) + 32
    sh = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "새 양산기 어깨 r1 — 오른 상자 · 왼 돔(구 대신 정수 기울기 다면체) · 관절", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((16, y), t, fill=(240, 200, 120), font=f); x = 16; y += 32
        for im in r:
            sh.paste(im, (x, y)); x += im.width + 16
        y += H + 12
    p = os.path.join(out, "시안_어깨r1.png"); sh.save(p); print(p, sh.size)
