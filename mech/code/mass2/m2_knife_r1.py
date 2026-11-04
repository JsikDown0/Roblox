"""새 표준 양산기 ST-10 컴뱃 나이프 r1 (2026-11-04) — [결정 11-04] 근접 = 컴뱃 나이프 · 수납 = 왼 허리 홀스터(손잡이 위, 20°).
수납 칼(KnifeStowed)은 손잡이·가드만 보임 → 뽑은 칼(Knife, 부모 HandL)을 따로: 손잡이·가드·끝 뭉치는 수납 칼과 같은 모양(검정 손잡이 + 짙은 띠 2 · 강철 가드 · 강철 끝).
칼날 길이 26 · 손잡이 13 · 전체 약 42(아래팔 길이쯤). 홀스터 속 깊이는 약 18 — 수납 칼은 손잡이만 보여 겉으론 안 드러남.
색: 날 = 짙은 프레임 몸(3) + 강철 날 띠(7) · 손잡이 검정(4) · 가드·끝 강철(7).
좌표: a = 칼끝 쪽(가드 0) · b = 등(위) · c = 두께. 쥔 자세 = 왼 주먹(축 앞뒤)에 정수 쥠, 칼끝 앞·아래 30°.
  K1 탄토  : 곧은 날 + 끝이 비스듬히 꺾인 각진 끝(두 번째 날) · 등 홈
  K2 클립  : 등이 끝에서 깎여 내려간 보위식 끝 · 등 앞쪽 톱니
  K3 넓은 날: 폭 넓은 외날(아머 슈나이더식) · 짙은 등 판 + 넓은 강철 날 · 대칭 가까운 끝"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import m2_booster_r1 as bo  # noqa: E402
import m2_carbine_r1 as C  # noqa: E402
import m2_leg_r1 as lg  # noqa: E402

PAL, EMISSIVE = bo.PAL, bo.EMISSIVE
NAMES = {"K1": "K1 탄토(각진 끝 · 등 홈)", "K2": "K2 클립(깎인 등 끝 · 등 톱니)", "K3": "K3 넓은 날(짙은 등 판 + 넓은 강철 날)"}
BL = 26                       # 1차 22 → 쥔 자세에서 주먹에 묻혀 거의 안 보임 → 26


def knife_masks(a, b, c, kind):
    ac = np.abs(c); m = {k: np.zeros(a.shape, bool) for k in (3, 4, 7)}
    # 손잡이(수납 칼과 같은 말): 검정 4×6 → 여기선 b 폭 4 · c 두께 3, 짙은 띠 2 · 가드 · 끝 뭉치
    m[4] |= (a >= -14) & (a < -1) & (b >= -2) & (b <= 2) & (ac <= 1.5) & ((np.abs(b) + ac) <= 3)
    m[3] |= (a >= -14) & (a < -1) & np.isin(np.round(a), (-11, -6)) & (b >= -2) & (b <= 2) & (ac <= 1.6) & ((np.abs(b) + ac) <= 3.2)
    m[7] |= (a >= -1) & (a <= 0) & (b >= -6) & (b <= 5) & (ac <= 2.5)                                    # 가드
    m[7] |= (a >= -16) & (a < -14) & (b >= -3) & (b <= 3) & (ac <= 2) & ((np.abs(b) + ac) <= 4)          # 끝 뭉치
    t = a / BL
    if kind == "K1":
        top = 3.0 + 0 * a
        bot = -4.0 + 0 * a
        tipcut = b >= -4 + np.clip(a - (BL - 7), 0, None)                                              # 끝 7칸 45° 로 꺾여 등 높이 끝(1차 7/6 기울기 → 계단)
        blade = (a > 0) & (a <= BL) & (b <= top) & (b >= bot) & tipcut & (ac <= 1)
        edge = blade & ((b <= bot + 1.5) | (a >= BL - 7) & (b <= -4 + (a - (BL - 7)) + 1.5))
        m[3] |= blade
        m[7] |= edge
        m[4] |= blade & (b == 1) & (a >= 3) & (a <= BL - 8) & (ac <= 0.5)                               # 등 홈
    elif kind == "K2":
        top = 3.0 - np.clip(a - (BL - 8), 0, None) / 2.0                                                 # 끝 8칸 등이 1:2 로 깎여 내려감
        bot = -4.0 + np.clip(a - (BL - 6), 0, None) / 2.0                                                # 날 끝 6칸 1:2 로 올라감(1차 곡선 → 계단)
        blade = (a > 0) & (a <= BL) & (b <= top) & (b >= bot) & (ac <= 1)
        saw = (b >= 2) & (a >= 3) & (a <= 11) & (np.mod(np.round(a), 2) == 0)                            # 등 톱니
        m[3] |= blade & ~saw
        m[7] |= blade & (b <= bot + 1.5)
        m[7] |= blade & (top < 2.5) & (b >= top - 1)                                                    # 깎인 등도 날
    else:
        top = 4.0 - np.clip(a - (BL - 5), 0, None)                                                       # 등 끝 45°
        bot = -6.0 + np.clip(a - (BL - 10), 0, None) / 2.0                                               # 날 끝 1:2(1차 5/6 · 5/8 → 계단)
        blade = (a > 0) & (a <= BL) & (b <= top) & (b >= bot) & (ac <= 1.5) & ~((ac > 1) & (b < bot + 2.5))  # 날 쪽은 얇게(1칸)
        m[3] |= blade & (b >= 0)                                                                        # 짙은 등 판
        m[7] |= blade & (b < 0)                                                                         # 넓은 강철 날
    return m


GRIP = np.array((42.0, 0.0, 122.0))                                                                     # 왼 주먹 속
A_ = np.array((0, -0.866, -0.5)); B_ = np.array((0, -0.5, 0.866))


def place(M, kind, name="Knife", parent="HandL", O=None, a_=A_, b_=B_):
    O = GRIP + 7 * a_ if O is None else np.asarray(O, float)                                            # 손잡이 가운데(a −7)를 주먹 속에
    P = M.part(name, tuple((O - 45).astype(int)), tuple((O + 45).astype(int)), pivot=tuple(O), parent=parent)
    a, b, c = C._frame(P, O, a_, b_)
    m = knife_masks(a, b, c, kind)
    for col in (4, 3, 7):
        P.add(m[col], col)
    from scipy import ndimage
    lab, n = ndimage.label(P.a > 0)
    if n > 1:
        big = np.bincount(lab.ravel())[1:].argmax() + 1
        P.a[(lab != big) & (lab > 0)] = 0
    P.trim()
    return P


def build_all(kind="K1"):
    M = bo.build_final()
    place(M, kind)
    return M


def solo(kind):
    M = fv.Model()
    place(M, kind, parent=None, O=(0, 0, 0), a_=(1, 0, 0), b_=(0, 0, 1))
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 24); ft = ImageFont.truetype(FN, 28)
    R = lambda M, y, pt, ppc, sk=(): vp.render(M.blocks(skip=sk, pose=lg.ARM_SPLAY), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=ppc, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0})
    rows = []
    for k in NAMES:
        M = build_all(k); cm.check(M)
        S = solo(k)
        sk = ["KnifeStowed"]
        full = [R(M, y, pt, 2.4, sk) for y, pt in ((0, 3), (40, 8))]
        z = [R(M, y, pt, 6, sk + [n for n in M.parts if n.endswith("R") or n in ("Carbine", "CarbineStowed")]) for y, pt in ((60, 8), (90, 3))]
        z = [im.crop((int(im.width * 0.15), int(im.height * 0.25), int(im.width * 0.85), int(im.height * 0.62))) for im in z]
        ims = [R(S, y, pt, 11) for y, pt in ((0, 0), (-35, 15))] + full + z
        rows.append((NAMES[k] + " · 쥔 자세(수납 칼 숨김)", ims))
    H = max(i.height for _, r in rows for i in r); W = max(sum(i.width + 14 for i in r) for _, r in rows) + 20
    sh = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((14, 14), "새 양산기 컴뱃 나이프 r1 — 3안(칼만 옆 · 3/4 + 쥔 자세 정면 · 왼 3/4 + 왼팔 확대 2)", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((14, y), t, fill=(240, 200, 120), font=f); x = 14; y += 36
        for im in r:
            sh.paste(im, (x, y + (H - im.height) // 2)); x += im.width + 14
        y += H + 8
    p = os.path.join(out, "시안_나이프r1.png"); sh.save(p); print(p, sh.size)
