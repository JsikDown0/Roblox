"""새 표준 양산기 ST-10 카빈 r1 (2026-11-04) — [결정 11-04] 주무장 = 돌격 소총 → "카빈으로 새로 디자인".
BISON 라이플(mass_weapon_r1: 길이 110 · 위 조준경 · 접이식 골격 개머리 K2 · 앞 손잡이)과 겹치지 않게 — 짧고(약 80~86) 덩어리가 큼.
색은 몸과 맞춤: 몸통 짙은 회색(2) · 옆판 모래(1) · 짙은 프레임(3) · 검정(4) · 강철(7) · 조준 점 청록 발광(6, 머리 렌즈와 같은 색).
좌표: a = 앞(총구 쪽, 손잡이 쥔 점 0) · b = 위 · c = 옆. 쥔 자세 = BISON 과 같이 총구가 아래·앞(손에서 60° 아래).
  C1 각진 카빈   : 상자 몸통 + 모래 옆판 · 8각 총열 덮개(통풍 홈) · 짧은 신축 개머리(관 + 쐐기) · 열린 상자 조준기(청록 점) · 곧은 탄창
  C2 불펍       : 긴 상자 몸통 하나에 개머리가 붙음 · 탄창이 손잡이 뒤 · 위 운반 손잡이(구멍) · 짧은 덮개 → 같은 길이에 총열이 김
  C3 굵은 덮개   : C1 몸통 + 둥근(16각) 굵은 총열 덮개(구멍 줄) + 넓은 소염기 · 개머리 없음(끝판만) · 짧은 굽은 탄창 — 가장 짧고 묵직함
파트: Carbine(부모 HandR). 수납(등·허리)은 고른 뒤."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
sys.path.insert(0, os.path.join(HERE, "..", "mass"))
import flag_vox as fv  # noqa: E402
import m2_leg_r1 as lg  # noqa: E402

PAL, EMISSIVE = lg.PAL, lg.EMISSIVE
NAMES = {"C1": "C1 각진 카빈(신축 개머리 · 8각 덮개 · 상자 조준기)", "C2": "C2 불펍(탄창이 손잡이 뒤 · 운반 손잡이)",
         "C3": "C3 굵은 둥근 덮개(개머리 없음 · 가장 짧고 묵직)"}


def _frame(P, O, a_, b_):
    a_ = np.asarray(a_, float); a_ /= np.linalg.norm(a_)
    b_ = np.asarray(b_, float); b_ = b_ - a_ * (a_ @ b_); b_ /= np.linalg.norm(b_)
    c_ = np.cross(a_, b_)
    X, Y, Z = P.g(); dx, dy, dz = X - O[0], Y - O[1], Z - O[2]
    f = lambda e: e[0] * dx + e[1] * dy + e[2] * dz
    return [np.broadcast_to(v, P.a.shape) for v in (f(a_), f(b_), f(c_))]


def oct_(a, b, c, a0, a1, bc, h, w, ch):
    """a 축 8각 기둥: 가운데 b=bc, 반높이 h, 반폭 w, 모서리 ch."""
    db = np.abs(b - bc); dc = np.abs(c)
    return (a >= a0) & (a <= a1) & (db <= h) & (dc <= w) & (db + dc <= h + w - ch)


BUTT = None                   # r2 [유저 11-04 "불펍으로 가되 개머리판이 그냥 사각형 처리가 끝"]: 개머리 3안
BUTTS = {"B1": "B1 쐐기(AUG·타보르식) — 아래가 1:2 로 올라가는 쐐기 · 기운 받침판 · 볼받침 돋움",
         "B2": "B2 엄지 구멍(QBZ·P90식) — 개머리 아래로 내려온 뒤 손잡이 고리 · 엄지 구멍",
         "B3": "B3 2단 받침(SA80·FAMAS식) — 몸통보다 좁은 목 + 넓은 받침 덩어리 · 사이 짙은 틈 · 옆 오목 판"}


def butt_masks(m, a, b, c, ac, body, kind):
    """불펍 개머리(a < −18, 탄창 뒤). 몸통 앞부분(a ≥ −18)은 그대로."""
    front = body & (a >= -18)
    m[2] |= front
    m[1] |= (a >= -16) & (a <= 12) & (b >= 7) & (b <= 15) & (ac <= 6) & (ac > 5)                      # 모래 옆판(앞)
    if kind == "B1":
        bot = 4 + np.clip(-20 - a, 0, None) / 2.0                                                      # 아래 1:2 로 올라감(a −36 에서 b 12)
        top = 18 - np.clip(-34 - a, 0, None) * 1.0
        rear = -36 + np.clip(b - 14, 0, None) / 2.0                                                    # 받침판 1:2 로 기욺(위가 앞)
        bu = (a < -18) & (a >= rear) & (b >= bot) & (b <= top) & (ac <= 5) & ((np.abs(b - 11) + ac) <= 7 + 5 - 2)
        m[2] |= bu
        m[1] |= (a >= -29) & (a < -18) & (b >= 10) & (b <= 15) & (ac <= 6) & (ac > 5)                   # 모래 옆판(뒤) — 1차: 쐐기 따라 자르니 계단 줄 → 사각, 쐐기 끝은 짙은 색만
        m[3] |= (a >= -31) & (a <= -21) & (b > 18) & (b <= 19) & (ac <= 3.5)                           # 볼받침 돋움
        m[4] |= (a >= rear - 1) & (a < rear) & (b >= bot + 1) & (b <= top - 1) & (ac <= 4)               # 고무 받침(기운)
    elif kind == "B2":
        bu = oct_(a, b, c, -36, -18, 11, 7, 5, 2)
        grip = (a >= -36) & (a <= -24) & (b >= -8) & (b < 5) & (ac <= 4) & ((np.abs(a + 30) + np.clip(-4 - b, 0, None)) <= 9)
        hole = (a >= -31) & (a <= -25) & (b >= -4) & (b <= 2)
        m[2] |= (bu | grip) & ~hole
        m[3] |= (bu | grip) & ~hole & (ac <= 4) & (b < 4)                                               # 아래 고리(짙은 프레임)
        m[1] |= (a >= -33) & (a < -18) & (b >= 7) & (b <= 15) & (ac <= 6) & (ac > 5)
        m[4] |= (a >= -37) & (a < -36) & (b >= -6) & (b <= 17) & (ac <= 4)
    elif kind == "B3":
        neck = oct_(a, b, c, -26, -18, 11, 5, 4, 2)                                                    # 좁은 목
        pad = oct_(a, b, c, -36, -28, 10, 8, 5.5, 3) & (a >= -36 + np.clip(b - 15, 0, None) / 2.0)       # 넓은 받침 덩어리(위 뒤 1:2)
        m[2] |= neck | pad
        m[3] |= oct_(a, b, c, -28, -26, 11, 4, 3.5, 1)                                                 # 사이 짙은 틈(심)
        m[1] |= pad & (ac > 4.5) & (a >= -34) & (a <= -30) & (b >= 6) & (b <= 14)                       # 옆 오목 판 자리 → 모래
        m[4] |= (a >= -37) & (a < -36 + np.clip(b - 15, 0, None) / 2.0) & (b >= 3) & (b <= 17) & (ac <= 4.5)


def carbine_masks(a, b, c, var):
    ac = np.abs(c); m = {k: np.zeros(a.shape, bool) for k in (1, 2, 3, 4, 6, 7)}
    rr = (b - 12) ** 2 + c ** 2
    grip = (b < 6) & (b >= -9) & (a >= -6 - np.clip(6 - b, 0, None) * 0.35) & (a <= -np.clip(6 - b, 0, None) * 0.35) & (ac <= 3)
    m[3] |= grip
    if var in ("C1", "C3"):
        rec = oct_(a, b, c, -12, 20, 12, 6, 5, 2) & (b <= 18 - np.clip(a - 17, 0, None))
        m[2] |= rec
        m[1] |= (a >= -9) & (a <= 15) & (b >= 8) & (b <= 15) & (ac <= 6) & (ac > 5)                    # 모래 옆판(몸 색)
        # 열린 상자 조준기 + 청록 점
        sight = (a >= 0) & (a <= 8) & (b > 18) & (b <= 25) & (ac <= 3.5)
        win = (a >= 0) & (a <= 6) & (b >= 20) & (b <= 23) & (ac <= 2)                                  # 1차: 창이 앞뒤로 뚫려 청록 점이 공중에 뜸(섬) → 앞쪽 뒷벽에 점
        m[3] |= sight & ~win
        m[6] |= (a >= 7) & (a <= 7) & (b >= 21) & (b <= 22) & (ac <= 0.6)
        m[3] |= (a >= -10) & (a <= 18) & (b > 18) & (b <= 19) & (ac <= 2.5)                             # 위 레일
    if var == "C1":
        mag = (b < 6) & (b >= -12) & (a >= 7) & (a <= 14) & (ac <= 3.5)
        m[3] |= mag
        m[2] |= oct_(a, b, c, 20, 40, 12, 5, 4.5, 2)                                                    # 8각 덮개
        m[4] |= oct_(a, b, c, 20, 40, 12, 5, 4.5, 2) & (ac >= 4) & (b >= 10) & (b <= 14) & np.isin(np.round(a), (24, 28, 32, 36))
        m[7] |= (a > 40) & (a <= 47) & (rr <= 2.2 ** 2 + 0.25)
        m[3] |= (a > 47) & (a <= 53) & (np.abs(b - 12) <= 3) & (ac <= 3) & (np.abs(b - 12) + ac <= 5)  # 각진 소염기
        m[3] |= (a >= -26) & (a < -12) & ((b - 13) ** 2 + c ** 2 <= 2.6 ** 2)                          # 버퍼 관
        st = (a >= -33) & (a <= -24) & (b >= 5) & (b <= 18) & (ac <= 4) & (a >= -33 + np.clip(9 - b, 0, None)) & (a <= -24 - np.clip(b - 15, 0, None))
        st &= ~((a >= -31) & (a <= -27) & (b >= 9) & (b <= 14))                                        # 1차: 통짜 상자 → 위 앞 45° + 가운데 구멍(골격)
        m[2] |= st                                                                                     # 쐐기 개머리(아래 앞 45°)
        m[4] |= (a >= -34) & (a <= -33) & (b >= 6) & (b <= 18) & (ac <= 4)                              # 고무 받침
        bore_a = 52
    elif var == "C3":
        sh = np.clip(6 - b, 0, None) * 0.4
        m[3] |= (b < 6) & (b >= -6) & (a >= 6 + sh) & (a <= 15 + sh) & (ac <= 4)                         # 짧고 굵은 굽은 탄창(1차: 손잡이와 같은 길이·굵기 → 벌린 두 다리처럼)
        shroud = (a > 20) & (a <= 40) & (rr <= 6.2 ** 2)
        m[2] |= shroud
        holes = shroud & (rr >= 5.0 ** 2) & np.isin(np.round(a), (24, 28, 32, 36)) & (np.abs(np.arctan2(b - 12, c)) % (np.pi / 3) < 0.35)
        m[4] |= holes
        m[3] |= (a > 40) & (a <= 42) & (rr <= 6.2 ** 2)                                                   # 덮개 끝 테
        m[7] |= (a > 42) & (a <= 45) & (rr <= 2.4 ** 2 + 0.25)
        m[3] |= (a > 45) & (a <= 51) & (rr <= 4.4 ** 2) & ~(np.isin(np.round(a), (47, 49)) & (rr >= 2.5 ** 2))   # 넓은 소염기
        m[2] |= (a >= -15) & (a < -12) & (b >= 6) & (b <= 18) & (ac <= 4.5)                               # 끝판
        m[4] |= (a >= -16) & (a < -15) & (b >= 7) & (b <= 17) & (ac <= 3.5)
        bore_a = 50
    elif var == "C2":
        body = oct_(a, b, c, -36, 16, 11, 7, 5, 2)                                                     # 긴 몸통(개머리 포함)
        if BUTT is None:
            m[2] |= body
            m[1] |= (a >= -32) & (a <= 12) & (b >= 7) & (b <= 15) & (ac <= 6) & (ac > 5)                 # 모래 옆판
            m[4] |= (a >= -37) & (a < -36) & (b >= 5) & (b <= 17) & (ac <= 4)                             # 고무 받침
        else:
            butt_masks(m, a, b, c, ac, body, BUTT)
        m[3] |= (b < 4) & (b >= -10) & (a >= -18) & (a <= -11) & (ac <= 3.5)                              # 탄창(손잡이 뒤)
        m[3] |= (b < 4) & (b >= 2) & (a >= -11) & (a <= -6) & (ac <= 3)                                   # 방아쇠 울 이음
        # 운반 손잡이(구멍) + 청록 점
        h = (a >= -12) & (a <= 12) & (b > 18) & (b <= 24) & (ac <= 2.5)
        hole = (a >= -8) & (a <= 8) & (b >= 19) & (b <= 21)
        m[3] |= h & ~hole
        m[6] |= (a >= 11) & (a <= 12) & (b >= 22) & (b <= 23) & (ac <= 0.6)
        m[2] |= oct_(a, b, c, 16, 30, 11, 5, 4.5, 2)
        m[4] |= oct_(a, b, c, 16, 30, 11, 5, 4.5, 2) & (ac >= 4) & (b >= 9) & (b <= 13) & np.isin(np.round(a), (20, 25))
        rr = (b - 11) ** 2 + c ** 2
        m[7] |= (a > 30) & (a <= 42) & (rr <= 2.2 ** 2 + 0.25)
        m[3] |= (a > 42) & (a <= 48) & (rr <= 3.3 ** 2 + 0.25) & ~(np.isin(np.round(a), (44, 46)) & (np.abs(c) >= 2))
        bore_a = 47
    bc = 11 if var == "C2" else 12
    bore = (a >= bore_a) & ((b - bc) ** 2 + c ** 2 <= 1.1)
    return m, bore


import m2_frame as fr  # noqa: E402
GRIP_O, A_, B_ = fr.hp("HandR")                                                                        # 장착점 HandR: 오른 주먹 속 · 총구 아래·앞 60°


def place(M, var, name="Carbine", parent="HandR", O=GRIP_O, a_=A_, b_=B_):
    O = np.asarray(O, float)
    P = M.part(name, tuple((O - 70).astype(int)), tuple((O + 70).astype(int)), pivot=tuple(O), parent=parent)
    a, b, c = _frame(P, O, a_, b_)
    m, bore = carbine_masks(a, b, c, var)
    for col in (2, 3, 1, 4, 7, 6):
        P.add(m[col], col)
    P.cut(bore)
    from scipy import ndimage
    lab, n = ndimage.label(P.a > 0)
    if n > 1:                                                                                       # 1~7칸 조각(대각선으로만 닿는 칸) 정리
        big = np.bincount(lab.ravel())[1:].argmax() + 1
        P.a[(lab != big) & (lab > 0)] = 0
    P.trim()
    return P


def build_all(var="C1", butt=None):
    global BUTT
    BUTT = butt
    M = lg.build_all(final=True)
    place(M, var)
    return M


def solo(var, butt=None):
    global BUTT
    BUTT = butt
    """총만(옆에서 보기용): a = +Y? → 수평 · 총구 −Y(앞) 가 아니라 화면 오른쪽(+X)으로."""
    M = fv.Model()
    place(M, var, parent=None, O=(0, 0, 0), a_=(1, 0, 0), b_=(0, 0, 1))
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    import m2_head_trace as ht
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 24); ft = ImageFont.truetype(FN, 28)
    R = lambda M, y, pt, ppc, pose=None: vp.render(M.blocks(pose=pose), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=ppc, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0})
    rows = []
    for v in sys.argv[2].split(",") if len(sys.argv) > 2 else NAMES:
        M = build_all(v); cm.check(M)
        print(v, lg.overlaps(M, lg.ARM_SPLAY), "카빈 칸", int((M.parts["Carbine"].a > 0).sum()))
        S = solo(v)
        ims = [R(S, y, pt, 7) for y, pt in ((0, 0), (-35, 15))] + [R(M, y, pt, 2.2, lg.ARM_SPLAY) for y, pt in ((0, 3), (-35, 8), (-90, 3))]
        rows.append((NAMES[v], ims))
    con = Image.open(ht.SRC).convert("RGB"); mn = Image.open(os.path.join(os.path.dirname(ht.SRC), "concept_v1_메인.png")).convert("RGB")
    H = max(i.height for _, r in rows for i in r)
    bison = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형", "확정_BISON_전신_무장.png")).convert("RGB")
    refs = [con.crop((0, 330, 120, 800)), mn.crop((30, 500, 230, 1180)), bison.crop((15, 60, 390, 730))]
    refs = [x.resize((int(x.width * H / x.height), H)) for x in refs]
    rows.insert(0, ("원본 소총(정면 · 메인) | BISON 라이플(겹치지 않게)", refs))
    W = max(sum(i.width + 14 for i in r) for _, r in rows) + 20
    sh = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((14, 14), "새 양산기 카빈 r1 — 3안(총만 옆 · 3/4 + 쥔 자세 정면 · 3/4 · 옆) · 몸 색(짙은 회색 + 모래 옆판) · 조준 점 청록", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((14, y), t, fill=(240, 200, 120), font=f); x = 14; y += 36
        for im in r:
            sh.paste(im, (x, y + (H - im.height) // 2)); x += im.width + 14
        y += H + 8
    p = os.path.join(out, "시안_카빈r1.png"); sh.save(p); print(p, sh.size)


# ---- 확정 [결정 11-04 "B3 가자"] = C2 불펍 + B3 2단 받침 · 수납 자리 시안
FINAL = ("C2", "B3")
STOWS = {"S1": "S1 등 대각선(총구 오른쪽 아래, 옆판이 뒤로 보임)",
         "S2": "S2 등 아래 가로(허리 위, 총구 오른쪽)",
         "S3": "S3 등 오른쪽 세로(총구 아래, 칼처럼 멘 모양)"}


def stow(M, kind):
    v, k = FINAL
    global BUTT
    BUTT = k
    s2 = np.sqrt(0.5)
    if kind == "S1":
        a_, b_, ctr = np.array((-s2, 0, -s2)), np.array((-s2, 0, s2)), fr.hp("BackUpper")[0] + (0, 6, -2)     # 장착점 BackUpper 에서
    elif kind == "S2":
        a_, b_, ctr = np.array((-1.0, 0, 0)), np.array((0, 0, 1.0)), fr.hp("BackUpper")[0] + (-12, 6, -4)
    else:
        a_, b_, ctr = np.array((0, 0, -1.0)), np.array((-1.0, 0, 0)), fr.hp("BackUpper")[0] + (-12, 6, -6)
    O = ctr - 5 * a_ - 7 * b_                                                                     # 총 가운데(a 5 · b 7)를 ctr 에 · Y 25 = 옆판(c 6)이 등(Y 18~19)에 닿음(1차 26 은 1칸 떠 보임)
    return place(M, v, name="CarbineStowed", parent="Torso", O=O, a_=a_, b_=b_)


def build_final(stow_kind=None):
    M = lg.build_all(final=True)
    global BUTT
    BUTT = FINAL[1]
    place(M, FINAL[0])
    if stow_kind:
        stow(M, stow_kind)
    return M
