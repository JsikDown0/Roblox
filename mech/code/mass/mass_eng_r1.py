"""BISON 공병형 ST-10E r1 (2026-11-04) — 윤곽 읽기 e1 답 [결정 11-04]: ⑤ 대신 "상자 옆이나 아래에 노즐을 연결", 나머지 동의
(크기 높이 64 · 폭 48 · 두께 22 · 색 3안 · 크레인 상자 위 오른쪽 → 오른 어깨 앞 위 · 잔 디테일 2칸 이상, 볼트 없음 · 위 고리 없음).
기본형 확정본(build_armed) 위에:
  Container(부모 Torso): X ±24 · Y 40~61(등 뒤 면 Y 39 바로 뒤) · z 194~257. 둘레 짙은 테(모서리 보강) · 뒤 면 두 짝 문(가운데 이음매 + 경첩 2쌍) ·
    아래 잠금쇠 2 · 옆 손잡이 · 데칼 자리(문 위쪽 평평) · 등 원래 노즐은 상자 속에 가려짐 → 노즐을 상자에 다시 연결:
    N1 아래: 상자 바닥에 노즐 2(아래·뒤 45°)   N2 옆: 상자 양옆 아래쪽에 노즐 1씩(뒤 향함)
  Crane(부모 Container): 받침(상자 위 오른쪽) → 붐 1(위로) → 꺾임 → 붐 2(앞으로, 오른 어깨 위) + 크롬 실린더 2 + 두 갈래 집게(앞).
색 9 = 상자·크레인 몸색: a 짙은 쇠 회색 몸(2) + 올리브 문(1) / b 모래·카키 (150,136,100) / c 짙은 올리브 (70,74,58).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_final as MF  # noqa: E402

COLORS = {"a": None, "b": (150, 136, 100), "c": (70, 74, 58)}
NAMES = {"a": "색 a 짙은 쇠 몸 + 올리브 문", "b": "색 b 모래·카키", "c": "색 c 짙은 올리브"}
X0, X1, Y0, Y1, Z0, Z1 = -24, 24, 40, 61, 194, 257


def pal(col):
    P = dict(MF.PAL)
    P[9] = COLORS[col] if COLORS[col] else MF.PAL[2]
    return P


def bell(G, base, d, r0=5.5, r1_=8.5, L=9):
    """base 에서 방향 d 로 벌어지는 노즐(속 검정)."""
    X, Y, Z = G
    d = np.asarray(d, float); d /= np.linalg.norm(d); base = np.asarray(base, float)
    t = (X - base[0]) * d[0] + (Y - base[1]) * d[1] + (Z - base[2]) * d[2]
    px = X - base[0] - t * d[0]; py = Y - base[1] - t * d[1]; pz = Z - base[2] - t * d[2]
    rr = np.sqrt(px ** 2 + py ** 2 + pz ** 2)
    rad = r0 + (r1_ - r0) * np.clip(t / L, 0, 1)
    shell = (t >= 0) & (t <= L) & (rr <= rad + 0.5)
    inner = (t >= 2) & (t <= L + 1) & (rr <= rad - 1.5)
    return shell, inner


def build_container(M, col="b", noz="N1"):
    body, door = (2, 1) if col == "a" else (9, 9)
    C = M.part("Container", (X0 - 14, Y0 - 2, Z0 - 22), (X1 + 14, Y1 + 12, Z1 + 3), pivot=(0, Y0, 220), parent="Torso")
    G = C.g(); X, Y, Z = G
    C.add(cbox(G, (X0, X1), (Y0, Y1), (Z0, Z1), {"xy": 3, "xz": 3, "yz": 3}), body)
    C.paint_s((np.abs(X) >= X1 - 2) | (Z <= Z0 + 2) | (Z >= Z1 - 2), 3)                        # 둘레 짙은 테
    door_m = (np.abs(X) <= X1 - 4) & (Z >= Z0 + 5) & (Z <= Z1 - 5) & (Y == Y1)
    C.add(door_m & ~(C.a > 0) | (door_m), door)
    C.emboss((np.abs(X) <= X1 - 5) & (Z >= Z0 + 6) & (Z <= Z1 - 6) & (Y > Y1), door)          # 문 1칸 돋움
    C.groove((X == 0) & (Z >= Z0 + 6) & (Z <= Z1 - 6) & (Y >= Y1), 4)                          # 가운데 이음매
    for zc in (Z0 + 14, Z1 - 14):                                                               # 경첩 2쌍
        for s in (1, -1):
            C.add(box(G, x=sorted((s * (X1 - 6), s * (X1 - 1))), y=(Y1 + 1, Y1 + 3), z=(zc - 3, zc + 3)), 3)
            C.add(box(G, x=sorted((s * (X1 - 1), s * (X1 - 1))), y=(Y1 + 1, Y1 + 3), z=(zc - 3, zc + 3)), 7)
    for s in (1, -1):                                                                           # 아래 잠금쇠 2
        xs = sorted((s * 8, s * 13))
        C.add(box(G, x=xs, y=(Y1 + 2, Y1 + 4), z=(Z0 + 6, Z0 + 15)), 3)
        C.add(box(G, x=(min(xs) + 1, max(xs) - 1), y=(Y1 + 4, Y1 + 5), z=(Z0 + 7, Z0 + 11)), 7)
        hz = (Z0 + 22, Z1 - 22)                                                                 # 옆 손잡이
        C.add(box(G, x=sorted((s * (X1 + 1), s * (X1 + 3))), y=(50, 52), z=hz) &
              ~box(G, x=sorted((s * (X1 + 1), s * (X1 + 1))), y=(50, 52), z=(hz[0] + 2, hz[1] - 2)), 3)
    # 노즐 연결
    if noz == "N1":
        for s in (1, -1):
            C.add(cbox(G, sorted((s * 7, s * 19)), (44, 56), (Z0 - 4, Z0), {"xy": 2}), 3)          # 바닥 받침
            sh, inn = bell(G, (s * 13, 52, Z0 - 3), (0, 0.7, -0.7))
            C.add(sh, 2); C.cut(inn); C.add(bell(G, (s * 13, 52, Z0 - 3), (0, 0.7, -0.7), r0=3.5, r1_=6.5, L=2)[0] & ~(C.a > 0), 4)
    else:
        for s in (1, -1):
            C.add(cbox(G, sorted((s * (X1), s * (X1 + 5))), (44, 56), (Z0 + 2, Z0 + 18), {"xy": 1}), 3)   # 옆 받침
            sh, inn = bell(G, (s * (X1 + 3), 54, Z0 + 10), (0, 1, 0))
            C.add(sh, 2); C.cut(inn); C.add(bell(G, (s * (X1 + 3), 54, Z0 + 10), (0, 1, 0), r0=3.5, r1_=6.5, L=2)[0] & ~(C.a > 0), 4)
    C.trim()
    # 크레인
    K = M.part("Crane", (-48, -36, 248), (-4, 60, 286), pivot=(-15, 50, Z1), parent="Container")
    G = K.g(); X, Y, Z = G
    A = np.array((-15, 50, Z1 + 1)); B = np.array((-19, 46, 276)); Cc = np.array((-32, -14, 268))
    K.add(cbox(G, (-21, -9), (44, 56), (Z1, Z1 + 5), {"xy": 2}), 3)                              # 받침
    K.add(cyl(G, "x", (50, Z1 + 6), 3.5, rng=(-21, -9)), 3)
    K.add(r1.seg(G, A + (0, 0, 4), B, 3.6), body)                                                # 붐 1
    K.add(cyl(G, "x", (B[1], B[2]), 4.2, rng=(-23, -15)), 3)                                     # 꺾임 관절
    K.add(r1.seg(G, B, Cc, 3.2), body)                                                           # 붐 2(앞으로)
    K.add(r1.seg(G, B + (0, -6, -1), Cc + (2, 10, -1), 1.0) & ~(K.a > 0), 4)                    # 붐 옆 홈 줄
    for dx in (-2.5, 2.5):                                                                        # 크롬 실린더 2
        K.add(r1.seg(G, (-15 + dx, 47, Z1 + 6), (-18 + dx, 36, 270), 1.3), 8)
    K.add(cyl(G, "x", (Cc[1], Cc[2]), 3.4, rng=(-36, -28)), 3)                                  # 집게 손목
    for dz in (-1, 1):                                                                            # 두 갈래 집게(앞·아래)
        K.add(r1.seg(G, Cc + (0, -2, 0), Cc + (0, -10, dz * 5), 1.6), 3)
        K.add(r1.seg(G, Cc + (0, -10, dz * 5), Cc + (0, -15, dz * 2), 1.6), 3)
    K.trim()
    return M


def build_all(col="b", noz="N1"):
    M = MF.build_armed()
    build_container(M, col, noz)
    M.extra.update({"name": "BISON", "designation": "ST-10E", "variant": "engineer"})
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import mass_weapon_r1 as w1
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    AS = MF.REST_POSE
    rows = []
    for col, noz in (("a", "N1"), ("b", "N1"), ("c", "N1"), ("b", "N2")):
        M = build_all(col, noz)
        if (col, noz) == ("b", "N1"):
            cm.check(M)
            print(w1.overlaps(M, AS, [("Crane", ("Head", "ShoulderR", "UpperArmR", "PlateF", "Torso")), ("Container", ("ShoulderL", "ShoulderR", "PlateB", "UpperArmL", "UpperArmR", "Head"))]))
        P = pal(col)
        ims = [vp.render(M.blocks(pose=l4.aim(M, AS)[0], skip=("RifleStowed",)), P, MF.EMISSIVE, yaw=y, pitch=p, ppc=1.9, ss=2, ao_amt=0.5,
                         bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=MF.METAL) for y, p in ((0, 2), (-35, 8), (-90, 2), (150, 12), (200, 10))]
        rows.append(("%s · 노즐 %s" % (NAMES[col], "N1 아래" if noz == "N1" else "N2 옆"), ims))
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형", "공병형", "concept_e1_컨테이너.png")).convert("RGB")
    H = max(i.height for _, ims in rows for i in ims)
    cc = con.resize((int(con.width * H / con.height), H))
    W = max(max(sum(i.width for i in ims) for _, ims in rows) + 16 * 6, cc.width + 32) + 20
    sh = Image.new("RGB", (W, 60 + (len(rows) + 1) * (H + 46)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "BISON 공병형 ST-10E r1 — 장비 컨테이너 + 크레인(오른 어깨 위 앞으로) · 색 3안 · 노즐 연결 2안", fill=(235, 235, 235), font=ft)
    for r_, (nm, ims) in enumerate([("컨셉 e1", [cc])] + rows):
        y0 = 60 + r_ * (H + 46); x = 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
    p = os.path.join(out, "시안_공병형r1.png"); sh.save(p); print(p, sh.size)
