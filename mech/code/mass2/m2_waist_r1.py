"""새 표준 양산기 ST-10 허리·골반 r1 (2026-11-04). 팔 확정(m2_arm_r2.build_all(final=True)) 아래에.
[읽기: 삼면도 정면 · 뒤 · 옆 + 메인 확대 · z = (943 − y) × 0.301 · 폭 ×0.92]
  D 배(짙은 회색): z174~189 · ±17 — 가슴보다 안쪽으로 들어감
  B 벨트(짙은 회색 띠): z168~174 · ±25(양 끝은 옆 골반 블록)
  F 앞치마판(모래): z140~174 · 위 ±9.5 → 아래 ±6 · 위 가운데 짙은 홈
  P 벨트 주머니판(모래) 앞 양옆 2: X ±11~21 · z163~175 / 뒤 판 2(모래)
  C 샅(짙은 회색): z134~152 · ±7
  S 옆 골반 블록(짙은 회색) · 오른쪽만(왼쪽은 홀스터)
  N 왼 허리 상자 = 나이프 홀스터 [결정 11-04: 골반 고정 · 손잡이 위로] — 그림 자리(X 23~38)는 아래팔(X 31~57)과 겹침
     → X 21~30 으로 몸 쪽에 붙이고 앞뒤로 깊게(Y −12~10) · 위로 손잡이(검정) + 가드(강철) · 끈 2(짙은 프레임)
     손잡이 X27~30 · 끝 z201 — 가슴 속 프레임(X24) · 가슴판(z200 폭 ±25)에 닿지 않는 범위.
  a = 홀스터 수직 / b = 홀스터 앞으로 20° 기울임(손잡이가 앞·위 — 뽑기 쉬운 자세, 스트라이크 참고).
파트: Pelvis(뿌리, Torso 의 부모, 피벗 (0,0,160)) · KnifeHolster(부모 Pelvis) · KnifeStowed(부모 KnifeHolster).
색: 1 모래 · 2 짙은 회색 · 3 짙은 프레임 · 4 검정 · 7 강철."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, cbox, poly, rotx  # noqa: E402
import m2_arm_r2 as ar  # noqa: E402

PAL, EMISSIVE = ar.PAL, ar.EMISSIVE
HOL = (25.5, 0, 160)          # 홀스터 회전 중심(벨트 쪽 고정점)
SIDE_R2 = True                # [결정 11-04 "빨강(오른 옆 블록)은 되돌리고"] 확정본은 False(r1 블록)
R2 = False                    # r2 [유저 11-04]: 배 3겹 · 앞 옆 치마판 퍼짐 · 오른 옆 블록 길게 · 홀스터 3칸 뒤로(치마판 뒤)


def pelvis(M):
    P = M.part("Pelvis", (-34, -20, 130), (35, 18, 192), pivot=(0, 0, 160))
    G = P.g(); X, Y, Z = G; ax = np.abs(X)
    if R2:
        # 배 [유저 11-04 파랑 "통짜처럼 나와서 아쉬워"] → 3겹: 짙은 심(안쪽) · 위 넓은 띠(가슴 밑) · 앞 판(아래 모서리 45°)
        P.add(cbox(G, (-14, 14), (-9, 10), (174, 189), {"xy": 3}), 3)                                 # 심(짙은 프레임)
        P.add(cbox(G, (-18, 18), (-12, 11), (184, 189), {"xy": 4, "-yz": 1}), 2)                      # 위 띠
        P.add(poly(G, "y", [(-12, 183), (12, 183), (12, 179), (8, 175), (-8, 175), (-12, 179)]) & (Y >= -12) & (Y <= -8), 2)   # 앞 판
        P.add(cbox(G, (-12, 12), (-8, 8), (176, 183), {"xy": 2}) & ~(P.a > 0), 2)
    else:
        P.add(cbox(G, (-17, 17), (-11, 11), (174, 189), {"xy": 4}), 2)                                # 배
    P.add(cbox(G, (-25, 25), (-14, 13), (167, 175), {"xy": 6}), 2)                                    # 벨트
    P.add(cyl(G, "x", (0, 152), 6, rng=(-11, 11)), 3)                                                 # 고관절 축(1차 ±20 은 다리 없이 통나무처럼 드러남 → 다리 단계에서 늘림)
    P.add(cbox(G, (-7, 7), (-12, 8), (134, 153), {"xz": 3, "-yz": 3, "+yz": 2}), 2)                   # 샅
    # 앞치마판: 정면 윤곽(위 ±9.5 → z152 까지 곧게 → 아래 ±6, 아래 모서리 45°)
    fr = [(-9.5, 175), (9.5, 175), (9.5, 152), (6, 141), (-6, 141), (-9.5, 152)]
    P.add(poly(G, "y", fr) & (Y >= -18) & (Y <= -11) & (Y >= -18 + np.clip(Z - 173, 0, None)) & (Y >= -18 + np.clip(ax - 5.5, 0, None)) & (Y >= -18 + np.clip(144 - Z, 0, None)), 1)   # 1차: 평평한 종이판 → 앞 옆 모서리 45° · 아래 앞 모서리 45°
    P.cut((ax <= 3) & (Z >= 170) & (Z <= 175) & (Y <= -17)); P.add((ax <= 3) & (Z >= 170) & (Z <= 175) & (Y == -16), 3)   # 위 가운데 짙은 홈
    for sg in (1, -1):
        if R2:
            # 앞 옆 치마판 [유저 11-04 초록 "툭 튀어나온 형태가 아니라 옆으로 퍼진 형태"]: 벨트를 따라 옆으로 감기고(45°) 아래로 갈수록 바깥으로 퍼지는 얇은 판(3칸)
            fr2 = [(10, 176), (24, 176), (29, 166), (29, 161), (12, 161), (10, 166)]                 # 위 X10~24 → 아래 X12~29(바깥 1:2 로 퍼짐)
            sk = poly(G, "y", [(sg * x_, z_) for x_, z_ in fr2])
            yf = -17 + np.clip(ax - 17, 0, None)                                                     # 바깥은 45° 로 뒤로 감김
            P.add(sk & (Y >= yf) & (Y <= yf + 3) & (Y <= 6), 1)
        else:
            P.add(cbox(G, sorted((sg * 11, sg * 21)), (-17, -10), (163, 175), {"-yz": 2, "xy": 2}), 1)   # 앞 주머니판
        P.add(cbox(G, sorted((sg * 4, sg * 22)), (10, 15), (162, 175), {"+yz": 2, "xy": 2}), 1)       # 뒤 판
    if R2 and SIDE_R2:
        # 오른 옆 골반 블록 [유저 11-04 빨강 "더 길어야"]: z161~178 → z146~176, 아래 바깥 1:2 로 퍼짐
        # 1차: 벨트 위(z180)까지 솟은 두꺼운 판자 → 몸에서 떨어져 보임 → 벨트 높이(z176)에서 시작하는 두께 6칸 판, z156 아래 1:2 로 바깥으로 퍼짐
        xo = -30 - np.clip(156 - Z, 0, None) / 2.0                                                    # 바깥 면(2차: z166 부터 퍼지면 날개처럼 → z156 아래만)
        side = (X >= xo) & (X <= xo + 6) & (np.abs(Y) <= 11) & (Z >= 146) & (Z <= 176)
        side &= (np.abs(Y) <= 11 - np.clip(Z - 173, 0, None)) & (np.abs(Y) <= 8 + np.clip(X - xo, 0, None) * 1.0)   # 위 앞뒤 45° · 바깥 앞뒤 모서리 45°
        P.add(side, 2)
        P.add(cbox(G, (-27, -23), (-8, 8), (166, 176), {}) & ~(P.a > 0), 3)                             # 벨트와 잇는 짙은 받침
    else:
        P.add(cbox(G, (-31, -22), (-10, 10), (161, 178), {"xy": 3, "-xz": 2}), 2)                      # 오른 옆 골반 블록
    P.trim()
    return P


def holster(M, var="a"):
    """1차: 손잡이 3×4칸 · 높이 10 → 가는 막대처럼 안 보임 → 4×6칸 · 높이 13 + 넓은 가드 · 끝 뭉치.
    자리 제약: 아래팔 안쪽 X31(z142~176) · 가슴 속 프레임 X24(z188 위) · 가슴판 폭 z200 에서 ±25 → 손잡이 X27~30 · 끝 z201(2차: X26 은 등 상자(z196 위 |X|≤26)와 14칸 겹침)."""
    Hs = M.part("KnifeHolster", (18, -18, 152), (34, 16, 190), pivot=HOL, parent="Pelvis")
    G = Hs.g(); X, Y, Z = G
    Hs.add(cbox(G, (21, 29), (-13, 11), (158, 184), {"xy": 3, "-yz": 3, "-xz": 2, "+xz": 1}), 2)    # 칼집 상자
    for zc in (166, 177):                                                                             # 끈 2(2칸, 1칸 돋움)
        Hs.emboss((Z >= zc) & (Z <= zc + 1) & (X >= 29), 3)
        Hs.emboss((Z >= zc) & (Z <= zc + 1) & (Y <= -13) & (X >= 23), 3)
    Hs.cut((X >= 26) & (X <= 29) & (Y >= -7) & (Y <= 5) & (Z >= 182))                                  # 칼 꽂는 구멍
    Hs.add((X >= 26) & (X <= 28) & (Y >= -7) & (Y <= 5) & (Z == 181), 4)
    if var == "b":
        Hs.rot = rotx(20)
    Hs.trim()
    K = M.part("KnifeStowed", (20, -12, 175), (34, 10, 204), pivot=HOL, parent="KnifeHolster")
    G = K.g(); X, Y, Z = G
    K.add(cbox(G, (27, 29), (-4, 2), (182, 184), {}), 7)                                              # 칼 목(구멍 속)
    K.add(cbox(G, (25, 31), (-8, 6), (185, 186), {"yz": 1, "xy": 1}), 7)                              # 가드(강철)
    K.add(cbox(G, (27, 30), (-3, 2), (187, 199), {"xy": 1}), 4)                                       # 손잡이(검정)
    for zc in (190, 194):
        K.paint((Z == zc) & (K.a == 4), 3)                                                            # 손잡이 감은 띠
    K.add(cbox(G, (27, 30), (-4, 3), (200, 201), {"xy": 1}), 7)                                       # 끝 뭉치(강철)
    K.trim()
    return Hs


def build_all(var="a", r2=False, final=False):
    """final=True → 허리 확정 [결정 11-04 "빨강(오른 옆 블록)은 되돌리고 허리를 확정"] = r2(배 3겹 · 앞 옆 치마판 퍼짐 · 칼집 3칸 뒤) + r1 오른 옆 블록 + 홀스터 b(20°)."""
    global R2, SIDE_R2
    if final:
        var, r2 = "b", True
    R2 = r2; SIDE_R2 = not final
    M = ar.build_all(final=True)
    pelvis(M)
    M.parts["Torso"].parent = "Pelvis"
    holster(M, var)
    if r2:
        for n in ("KnifeHolster", "KnifeStowed"):                                                     # 치마판(앞 Y−17~−14)이 칼집 앞을 덮게 3칸 뒤로
            M.parts[n].lo[1] += 3
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import m2_head_trace as ht
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 22); ft = ImageFont.truetype(FN, 26)
    V = ((0, 3), (-35, 8), (-90, 3), (90, 3), (150, 8))
    rows = []
    for v, lab in (("a", "a  홀스터 수직"), ("b", "b  홀스터 앞으로 20° (손잡이 앞·위)")):
        M = build_all(v); cm.check(M)
        ims = [vp.render(M.blocks(), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=5, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}) for y, pt in V]
        sk = [n for n in M.parts if n.endswith("ArmL") or n == "HandL"]
        ims.append(vp.render(M.blocks(skip=sk), PAL, EMISSIVE, yaw=60, pitch=8, ppc=8, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0}))
        rows.append((lab + " · 맨 오른쪽 = 왼팔 빼고 홀스터 확대", ims))
    con = Image.open(ht.SRC).convert("RGB"); mn = Image.open(os.path.join(os.path.dirname(ht.SRC), "concept_v1_메인.png")).convert("RGB")
    H = max(i.height for _, r in rows for i in r)
    refs = [con.crop((60, 200, 480, 560)), con.crop((580, 200, 880, 560)), con.crop((990, 200, 1420, 560)), mn.crop((250, 450, 800, 900))]
    refs = [x.resize((int(x.width * H / x.height), H)) for x in refs]
    rows.insert(0, ("원본 아트(정면 · 옆 · 뒤 · 메인) — 호스 · 방패는 뺌", refs))
    W = max(sum(i.width + 16 for i in r) for _, r in rows) + 32
    sht = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sht)
    d.text((16, 14), "새 양산기 허리·골반 r1 — 배 · 벨트 · 앞치마판 · 주머니판 · 샅 · 왼 허리 나이프 홀스터(손잡이 위)", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((16, y), t, fill=(240, 200, 120), font=f); x = 16; y += 32
        for im in r:
            sht.paste(im, (x, y + (H - im.height) // 2)); x += im.width + 16
        y += H + 12
    p = os.path.join(out, "시안_허리r1.png"); sht.save(p); print(p, sht.size)
