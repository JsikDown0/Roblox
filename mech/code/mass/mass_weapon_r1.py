"""양산형 기본형 무장 r1 (2026-11-03) — 답 [결정 11-03]: 체격 B(앞뒤 두께만 ×1.15) · 라이플 체격에 맞춰(키의 약 0.42, 굵게) ·
소형 방패(어깨판보다 상하좌우 약간 크게, 세로 육각) · 라이플 수납 = 오른 허벅지 바깥 세로 · 방패 치기(R) + 빔사벨.

1) 두께 B: Torso · Pelvis · UpperLeg · LowerLeg 를 Y(앞뒤)로 ×1.15(중심 Y 0) — 칸 배열을 가장 가까운 칸으로 다시 뽑음.
   정강이 피스톤 위 고정점 T 도 같이 옮기고 피스톤 파트를 다시 만듦(발·로드 고정점 B 는 그대로).
2) 라이플(파트 Rifle, 부모 HandR): 길이 110(개머리 −38 ~ 소염기 72, 손잡이 기준) · 폭 ±5.5(+올리브 옆판 ±6) ·
   개머리(짙은) · 몸통(짙은 쇠) + 올리브 옆판 · 위 레일(홈) · 조준경 · 탄창(앞으로 기욺) · 손잡이(뒤로 기욺) ·
   총열 덮개(옆 통풍 홈) + 앞 손잡이 · 강철 총열 · 소염기(홈). 쥔 자세 = 총구가 아래·앞(컨셉 메인).
   RifleStowed(부모 UpperLegR): 같은 총, 총구 아래 · 윗면 앞 · X −48(허벅지 바깥).
3) 방패(파트 Shield, 부모 LowerArmL): 어깨판 육각(옆 그림 S2)과 같은 모양, 폭 40 · 높이 66(어깨판 약 34 × 59 보다 상하좌우 3~4칸씩),
   두께 4 + 바깥 2단 판(데칼 면) · 짙은 받침으로 아래팔 바깥(X 55)에 붙음 · 색 2 짙은 쇠 회색.
4) 빔사벨 손잡이(파트 SaberHilt): 짙은 손잡이(홈) + 강철 이미터·꼭지. 자리 2안:
   S1 방패 뒤(방패 안쪽 · 주먹 뒤, 밖에서 안 보이고 뒤에서 보임, 부모 Shield)
   S2 왼 허리 뒤(골반 옆 블록 뒤, 손잡이가 위·뒤로 30°, 부모 Pelvis)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, poly, rotx  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_leg_r2 as l2  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_shoulder_r1 as s1  # noqa: E402
import mass_final as MF  # noqa: E402

PAL, METAL, EMISSIVE = MF.PAL, MF.METAL, MF.EMISSIVE
SY = 1.15
THICK = ("Torso", "Pelvis", "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR")


def scale_y(P, s):
    ys = np.arange(P.lo[1], P.hi[1])
    lo = int(np.floor(P.lo[1] * s)) - 1; hi = int(np.ceil((P.hi[1] - 1) * s)) + 2
    ny = np.arange(lo, hi)
    src = np.clip(np.round(ny / s).astype(int) - P.lo[1], -1, len(ys))
    ok = (src >= 0) & (src < len(ys))
    a = np.zeros((P.a.shape[0], len(ny), P.a.shape[2]), np.uint8)
    a[:, ok, :] = P.a[:, src[ok], :]
    P.a = a; P.lo = np.array((P.lo[0], lo, P.lo[2])); P.hi = np.array((P.hi[0], hi, P.hi[2]))
    P.pivot = (P.pivot[0], P.pivot[1] * s, P.pivot[2])
    P.trim()


def thicken(M, s=SY):
    for n in ("Torso", "Pelvis", "UpperLegL", "LowerLegL"):
        scale_y(M.parts[n], s)
    for n in ("PistonCylL", "PistonRodL", "PistonCylR", "PistonRodR", "UpperLegR", "LowerLegR", "FootR"):
        M.parts.pop(n, None)
    l4.T_ = np.array((l4.CX, round(-15.5 * s, 1), 90.0))
    l4.build_pistons(M)
    M.parts.pop("LowerLegR", None); M.parts.pop("FootR", None)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis"); M.mirror("LowerLegL", "LowerLegR", "UpperLegR"); M.mirror("FootL", "FootR", "LowerLegR")
    M.parts["PistonCylR"].parent = "LowerLegR"; M.parts["PistonRodR"].parent = "FootR"
    # 머리·어깨는 그대로 — 목 우물이 앞뒤로 넓어진 만큼 머리는 그 자리


def _frame(P, O, a_, b_):
    a_ = np.asarray(a_, float); a_ /= np.linalg.norm(a_)
    b_ = np.asarray(b_, float); b_ = b_ - a_ * (a_ @ b_); b_ /= np.linalg.norm(b_)
    c_ = np.cross(a_, b_)
    X, Y, Z = P.g(); dx, dy, dz = X - O[0], Y - O[1], Z - O[2]
    f = lambda e: e[0] * dx + e[1] * dy + e[2] * dz
    return f(a_), f(b_), f(c_)


def rifle_masks(a, b, c):
    """a = 앞(손잡이 0), b = 위(손잡이 쥔 점 0), c = 옆."""
    ac = np.abs(c); m = {}
    rec = (a >= -14) & (a <= 22) & (b >= 6) & (b <= 20) & (ac <= 5.5) & (b <= 20 - np.clip(a - 19, 0, None))
    stock = (a >= -38) & (a < -14) & (b <= 19) & (b >= 7 + np.clip(-26 - a, 0, None) * 0.5) & (ac <= 4)
    stock &= ~((a >= -30) & (a <= -22) & (b >= 11) & (b <= 14) & (ac <= 4.5))               # 개머리 가운데 작은 구멍(1차는 커서 갈고리처럼 보임)
    plate = (a >= -10) & (a <= 16) & (b >= 9) & (b <= 17) & (ac <= 6.5)
    rail = (a >= -12) & (a <= 48) & (b > 20) & (b <= 22) & (ac <= 2.5) & ~((b == 22) & (np.mod(np.round(a), 4) == 0))
    scope = (a >= -6) & (a <= 12) & (b > 22) & (b <= 28) & (ac <= 3.2)
    lens = scope & (a >= 11)
    sh = np.clip(6 - b, 0, None) * 0.3
    mag = (b < 6) & (b >= -12) & (a >= 6 + sh) & (a <= 16 + sh) & (ac <= 3.5)
    gs = np.clip(6 - b, 0, None) * 0.35
    grip = (b < 6) & (b >= -8) & (a >= -6 - gs) & (a <= 0 - gs) & (ac <= 3)
    guard = (a > 22) & (a <= 54) & (b >= 7) & (b <= 19) & (ac <= 4.5) & (b >= 7 + np.clip(a - 50, 0, None))
    vents = guard & (ac >= 4) & (b >= 11) & (b <= 15) & np.isin(np.round(a), (28, 34, 40, 46))
    fgrip = (a >= 30) & (a <= 36) & (b >= -3) & (b < 7) & (ac <= 2.5)
    rr = (b - 13) ** 2 + c ** 2
    barrel = (a > 54) & (a <= 64) & (rr <= 2.2 ** 2 + 0.25)
    brake = (a > 64) & (a <= 72) & (rr <= 3.2 ** 2 + 0.25) & ~(np.isin(np.round(a), (66, 69)) & (ac >= 2))
    bore = (a >= 71) & (rr <= 1.0)
    for col, mm in ((3, stock), (2, rec), (1, plate), (3, rail), (3, scope), (4, lens), (3, mag), (3, grip),
                    (2, guard), (4, vents), (3, fgrip), (7, barrel), (3, brake)):
        m[col] = m.get(col, np.zeros(np.broadcast_shapes(a.shape, b.shape, c.shape), bool)) | np.broadcast_to(mm, np.broadcast_shapes(a.shape, b.shape, c.shape))
    return m, bore


def place_rifle(M, name, parent, O, a_, b_):
    O = np.asarray(O, float)
    P = M.part(name, tuple((O - 80).astype(int)), tuple((O + 80).astype(int)), pivot=tuple(O), parent=parent)
    a, b, c = _frame(P, O, a_, b_)
    m, bore = rifle_masks(a, b, c)
    for col in (3, 2, 1, 4, 7):                                                              # 뒤에 칠한 색이 이김(올리브 판 > 몸통)
        if col in m:
            P.add(m[col], col)
    for col in (1,):
        P.paint(m[col] & ~m[2] | (m[1]), col)
    P.cut(bore)
    P.trim()
    return P


def build_shield(M):
    ZC = 158                                                                                  # 1차 z172 는 어깨판(z≈200 아래 끝)과 겹쳐 한 장처럼 이어 보임 → 아래로
    P = M.part("Shield", (40, -30, 118), (66, 28, 200), pivot=(56, -1, ZC), parent="LowerArmL")
    G = P.g(); X, Y, Z = G
    xs = np.array([x for x, _ in s1.S2_SIDE], float); ys = np.array([y for _, y in s1.S2_SIDE], float)
    W, H = 40.0, 66.0
    hexp = [(-1 + (x - xs.mean()) / (xs.max() - xs.min()) * W, ZC + (ys.mean() - y) / (ys.max() - ys.min()) * H) for x, y in s1.S2_SIDE]
    P.add(poly(G, "x", hexp) & (X >= 57) & (X <= 60), 2)
    cy = np.mean([p[0] for p in hexp]); cz = np.mean([p[1] for p in hexp]); inner = []
    for u, v in hexp:
        d = np.hypot(u - cy, v - cz); inner.append((u - (u - cy) * 3.5 / d, v - (v - cz) * 3.5 / d))
    P.add(poly(G, "x", inner) & (X == 61), 2)                                                # 바깥 2단 판(데칼 면)
    P.add(cbox(G, (52, 56), (-7, 5), (160, 184), {"xy": 1}), 3)                              # 받침(아래팔 바깥에 붙음)
    P.add(cyl(G, "y", (54, 178), 2.4, rng=(-9, 7)), 7)                                       # 받침 핀
    P.trim()


def hilt(M, name, parent, O, axis):
    O = np.asarray(O, float)
    P = M.part(name, tuple((O - 16).astype(int)), tuple((O + 16).astype(int)), pivot=tuple(O), parent=parent)
    a, b, c = _frame(P, O, axis, (0, 1, 0) if abs(axis[1]) < 0.9 else (1, 0, 0))
    r2 = b ** 2 + c ** 2
    P.add((a >= -9) & (a <= 6) & (r2 <= 2.4 ** 2 + 0.25), 3)                                 # 손잡이
    P.add((a >= -6) & (a <= 4) & (r2 <= 2.9 ** 2 + 0.25) & np.isin(np.round(a), (-5, -2, 1, 4)), 4)   # 홈 테
    P.add((a > 6) & (a <= 10) & (r2 <= 3.0 ** 2 + 0.25), 7)                                  # 이미터
    P.add((a >= 9) & (a <= 10) & (r2 <= 1.2), 4)
    P.add((a >= -12) & (a < -9) & (r2 <= 2.0 ** 2 + 0.25), 7)                                # 꼭지
    P.trim()


def build_all(saber="S1", stowed=False, thick=True):
    M = MF.build_all()
    if thick:
        thicken(M)
    build_shield(M)
    if stowed:
        place_rifle(M, "RifleStowed", "UpperLegR", (-50, 31, 134), (0, 0, -1), (0, -1, 0))   # 1차 Y 13 은 늘어뜨린 손·아래팔과 겹침 → 허벅지 바깥 뒤쪽
    else:
        fc = np.array((-42.5, -0.5, 142.5))
        a_ = np.array((0, -0.5, -0.866)); b_ = np.array((0, -0.866, 0.5))
        place_rifle(M, "Rifle", "HandR", fc - a_ * -3 - b_ * 0, a_, b_)
    if saber == "S1":
        hilt(M, "SaberHilt", "Shield", (53.5, 13, 138), (0, 0, 1))
    else:
        ax = np.array((0, 0.5, 0.866))
        hilt(M, "SaberHilt", "Pelvis", (30, 18, 162), ax)
    return M


def overlaps(M, pose, pairs):
    def cells(n):
        p = M.parts[n]; T = M.world(n, pose); ijk = np.argwhere(p.a > 0) + p.lo
        return set(map(tuple, np.round(ijk @ T[:3, :3].T + T[:3, 3]).astype(int)))
    out = {}
    for a, bs in pairs:
        if a not in M.parts:
            continue
        ca = cells(a)
        out[a] = {b: len(ca & cells(b)) for b in bs if b in M.parts}
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    AS = MF.REST_POSE
    walk = dict(AS, UpperLegL=rotx(-25), LowerLegL=rotx(30), UpperLegR=rotx(20), LowerLegR=rotx(10))
    R = lambda M, ps, y, p, ppc=1.9: vp.render(M.blocks(pose=l4.aim(M, ps)[0]), PAL, EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2,
                                              ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=METAL)
    M0 = MF.build_all()
    Ma = build_all("S1", False)
    Mb = build_all("S2", True)
    for nm, M in (("무장(S1)", Ma), ("수납(S2)", Mb)):
        for pn in ("Torso", "UpperLegL", "LowerLegL", "Rifle", "RifleStowed", "Shield", "SaberHilt", "PistonCylL"):
            if pn in M.parts:
                p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
                print(nm, pn, p.parent, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
    import importlib.util
    spec = importlib.util.spec_from_file_location("sz", os.path.join(out, "..", "size.py"))
    pairs = [("Rifle", ("UpperLegR", "LowerLegR", "Torso", "Pelvis")), ("RifleStowed", ("HandR", "LowerArmR", "LowerLegR", "FootR")),
             ("Shield", ("UpperLegL", "LowerLegL", "PlateF", "PlateB", "ShoulderL", "Torso", "Pelvis")), ("SaberHilt", ("UpperLegL", "HandL", "LowerArmL", "Shield", "Pelvis"))]
    for nm, M in (("무장(S1)", Ma), ("수납(S2)", Mb)):
        print(nm, "쉬는 자세 겹침", overlaps(M, AS, pairs))
        print(nm, "걷기 겹침", overlaps(M, walk, pairs))
    pts = lambda M: np.concatenate([np.argwhere(p.a > 0) + p.lo for n, p in M.parts.items() if n in ("Torso", "Pelvis", "UpperLegL", "LowerLegL")])
    for nm, M in (("확정본", M0), ("두께 B", Ma)):
        P_ = pts(M); print(nm, "몸통·다리 앞뒤", int(P_[:, 1].max() - P_[:, 1].min()))
    rows = [("확정본(전)", [R(M0, AS, y, p) for y, p in ((0, 2), (-35, 8), (-90, 2), (150, 10))]),
            ("두께 B + 무장 · 사벨 S1(방패 뒤)", [R(Ma, AS, y, p) for y, p in ((0, 2), (-35, 8), (-90, 2), (150, 10))]),
            ("두께 B + 라이플 수납 · 사벨 S2(왼 허리 뒤)", [R(Mb, AS, y, p) for y, p in ((0, 2), (-35, 8), (-90, 2), (150, 10))])]
    # 무장 확대
    Mr = fv.Model(); place_rifle(Mr, "Rifle", None, (0, 0, 0), (0, -1, 0), (0, 0, 1))
    rif = [vp.render(Mr.blocks(), PAL, EMISSIVE, yaw=y, pitch=p, ppc=4, ss=2, ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=METAL)
           for y, p in ((-90, 2), (-35, 15), (0, 2))]
    def crop_part(M, yaw, pitch, names, ppc=3.4, pad=40):
        im = R(M, AS, yaw, pitch, ppc)
        full = R(M, AS, yaw, pitch, ppc)
        return im
    det = []
    for M_, yaw, pt, fr in ((Ma, -40, 6, (0.0, 0.25, 0.55, 0.75)), (Ma, 135, 8, (0.0, 0.25, 0.55, 0.72)), (Mb, -70, 6, (0.1, 0.3, 0.75, 0.8))):
        im = R(M_, AS, yaw, pt, 3.4); w, h = im.size
        det.append(im.crop((int(w * fr[0]), int(h * fr[1]), int(w * fr[2]), int(h * fr[3]))))
    rows.append(("무장 확대(라이플 옆·3/4·앞 / 방패·사벨 S1 · 수납)", rif + det))
    H = max(i.height for _, ims in rows for i in ims)
    W = max(sum(i.width for i in ims) + 16 * (len(ims) + 1) for _, ims in rows) + 20
    sh = Image.new("RGB", (W, 60 + len(rows) * (H + 46)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 기본형 무장 r1 — 두께 B(앞뒤 ×1.15) · 라이플 110칸 · 소형 방패(어깨판보다 조금 크게) · 빔사벨 손잡이", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(rows):
        y0 = 60 + r * (H + 46); x = 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
        for im in ims:
            sh.paste(im, (x, y0 + 26 + (H - 26 - im.height) // 2 if im.height < H - 26 else y0 + 26)); x += im.width + 16
    p = os.path.join(out, "시안_무장r1.png"); sh.save(p); print(p, sh.size)
