"""
aero_rifle.py — Aero 주무장: 2점사 빔 라이플 (2026-10-26 20:38~)

유저: "S2 로 가자. 이번엔 라이플 제작이야. 2점사식(1발당 데미지는 1점사보다 낮게)으로 가자." + 레퍼런스(주황 기체가 든 총구 두 개짜리 라이플).
디자인: 위아래 두 총열(상하 2연장) — 2점사 = 총열마다 한 발씩(위 → 아래). 총구 두 개가 빛남. 특정 원작 총의 모양은 옮기지 않음.
구성(라이플 좌표 a = 앞, b = 위, c = 옆): 개머리(뼈대형, 가운데 뚫림) · 몸통(흰, 아래 밝은 회색) · 조준기(짙게 + 렌즈 발광) ·
       에너지 카트리지(앞으로 기운 탄창, 밝은 회색 + 끝 강조색) · 손잡이(짙게, 뒤로 기움) · 앞 손잡이(왼손) ·
       총열 덮개(흰, 앞 위 45° 쐐기 + 끝 강조색) · 상하 총열(짙게, 위가 길고 아래가 짧음, 끝 금속 고리 + 깊은 곳 발광).
길이 약 123칸(v2 — 키 287칸의 0.43, 중장갑 라이플/키 0.39 수준).
"""
import numpy as np

from flag_vox import box, rotx, roty, rotz
import aero_r1 as A
import aero_legs_d as D
import aero_spikes as SP

WHITE, LGRAY, FRAME, BLACK, ACC, GLOW, METAL = 2, 10, 3, 4, 1, 6, 7


def rifle_masks(a, b, c):
    """라이플 칸 마스크(색 → bool). a 앞(+), b 위(+), c 옆.
    v2: 길이 150 → 123(중장갑 라이플/키 비 0.39 기준 Aero 287칸 → 약 112~125) · 몸통 옆 짙은 판 · 덮개 옆 통풍 홈 3줄 · 총열이 덮개 밖으로 더 나옴."""
    ac = np.abs(c)
    m = {}
    body = (a >= -10) & (a <= 34) & (b >= -5) & (b <= 8) & (ac <= 4.5) & (b <= 8 - np.clip(a - 29, 0, None)) & (b >= -5 + np.clip(-7 - a, 0, None))
    side = body & (ac >= 4) & (a >= 0) & (a <= 26) & (b >= 0) & (b <= 5)                  # 몸통 옆 짙은 판(한 칸 들어감)
    shroud = (a > 34) & (a <= 62) & (b >= -6) & (b <= 7) & (ac <= 3.5) & (b <= 7 - np.clip(a - 54, 0, None)) & (b >= -6 + np.clip(a - 58, 0, None))
    vents = shroud & (ac >= 3) & (b >= 0) & (b <= 3) & ((a == 40) | (a == 44) | (a == 48))  # 덮개 옆 통풍 홈
    up = (a > 54) & (a <= 85) & (b >= 2) & (b <= 5) & (ac <= 1.6)
    lo = (a > 54) & (a <= 79) & (b >= -4) & (b <= -1) & (ac <= 1.6)
    brake = ((a >= 80) & (a <= 85) & (b >= 1) & (b <= 6) & (ac <= 2.4)) | ((a >= 74) & (a <= 79) & (b >= -5) & (b <= 0) & (ac <= 2.4))   # 총구 덩어리
    hole_u = (a >= 84) & (np.abs(b - 3.5) <= 0.6) & (ac <= 0.6)
    hole_l = (a >= 78) & (a <= 79) & (np.abs(b + 2.5) <= 0.6) & (ac <= 0.6)
    sight = (a >= 6) & (a <= 24) & (b > 8) & (b <= 12) & (ac <= 2) & (b <= 12 - np.clip(a - 21, 0, None))
    lens = (a >= 22) & (a <= 23) & (b >= 9) & (b <= 10) & (ac <= 1)
    sh = np.clip(-5 - b, 0, None) * 0.35
    mag = (b < -5) & (b >= -17) & (a >= 12 + sh) & (a <= 22 + sh) & (ac <= 3)
    gs = np.clip(-5 - b, 0, None) * 0.35
    grip = (b < -5) & (b >= -20) & (a >= -5 - gs) & (a <= 1 - gs) & (ac <= 2.5)
    guard = (b < -5) & (b >= -9) & (a >= 2) & (a <= 8) & (ac <= 1)
    fore = (a >= 40) & (a <= 52) & (b < -6) & (b >= -12) & (ac <= 2.5) & (b >= -12 + np.clip(a - 49, 0, None))
    stock = (a >= -34) & (a < -10) & (b >= -4) & (b <= 6) & (ac <= 3.5) & ~((a >= -29) & (a <= -17) & (b >= -1) & (b <= 3))
    butt = (a >= -38) & (a < -34) & (b >= -8) & (b <= 7) & (ac <= 3.5)
    m[WHITE] = (body & (b > -2) & ~side) | (shroud & ~vents) | stock
    m[LGRAY] = (body & (b <= -2)) | mag | butt
    m[FRAME] = up | lo | sight | grip | guard | fore | side | vents
    m[METAL] = brake & ~hole_u & ~hole_l
    m[ACC] = (shroud & (a >= 56) & (b >= 3)) | (mag & (b <= -15))
    m[GLOW] = lens
    m["cut"] = (side & (ac >= 4.5)) | (vents & (ac >= 3.5)) | (hole_u & (a >= 85)) | (hole_l & (a >= 79))
    m["glow_in"] = (hole_u & (a == 84)) | (hole_l & (a == 78))
    return m


def _paint(p, m):
    order = (WHITE, LGRAY, FRAME, METAL, ACC)
    for c in order:
        p.add(m[c], c)
    p.add(m[GLOW] & ~m["cut"], GLOW)
    p.cut(m["cut"])
    p.add(m["glow_in"], GLOW)


def rifle_only():
    import flag_vox as fv
    M = fv.Model()
    p = M.part("Rifle", (-8, -90, -24), (9, 42, 16), pivot=(0, 0, 0))
    X, Y, Z = p.g()
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    m = {k: np.broadcast_to(v, shp) for k, v in rifle_masks(-Y, Z, X).items()}       # 앞 = -Y, 위 = +Z
    _paint(p, m)
    return M


FIST_R = (-40, 0, 125)           # 오른 주먹 가운데(쉬는 자세, 칸)


def attach(M, sa=1.0, sb=1.0, sc=1.0):
    """오른손에 쥠: 쉬는 자세 기준 총열 = 아래(-Z), 라이플 위 = 앞(-Y). 손잡이 가운데(a -2, b -12)가 주먹 가운데.
    sa·sb·sc = 길이·높이·폭 배율(손잡이 가운데 기준, 설계 좌표를 반올림해 다시 읽음 — 한 칸 홈·구멍이 사라지지 않게)."""
    fx, fy, fz = FIST_R
    p = M.part("RifleR", (fx - int(9 * sc) - 2, fy - int(30 * sb), fz - int(92 * sa)), (fx + int(9 * sc) + 3, fy + int(14 * sb) + 2, fz + int(44 * sa)),
               pivot=FIST_R, parent="LowerArmR")
    X, Y, Z = p.g()
    a = np.round((fz - Z) / sa) - 2
    b = np.round((fy - Y) / sb) - 12
    c = np.round((X - fx) / sc)
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    m = {k: np.broadcast_to(v, shp) for k, v in rifle_masks(a, b, c).items()}
    _paint(p, m)
    return p


SCALE = (1.15, 1.35, 1.35)     # (길이, 높이, 폭) — 20:57 크기 비교 뒤 추천안: 몸통 두께가 아래팔 장갑의 절반이라 가늘어 보였음 → 두께 1.35 · 길이 1.15(키의 0.49)


def build(kind="S2", scale=None):
    M = SP.build(kind)
    attach(M, *(scale or SCALE))
    return M


build_all = build

AIM = dict(A.STANCE)
AIM.update({"UpperArmR": rotx(-86) @ roty(-4), "LowerArmR": np.eye(3), "ShoulderR": roty(-6)})

if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    import aero_colors as Cc
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    sch = Cc.SCHEMES["C1 흰·주황"]
    rows = []
    Mr = rifle_only(); Br = Mr.blocks()
    ims = [vp.render(Br, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=4, ss=2, size=sz, ao_amt=0.5)
           for y, p, sz in ((90, 2, ((-92, 44), (-26, 18))), (40, 16, ((-72, 72), (-34, 28))), (0, 4, ((-20, 20), (-24, 16))), (90, 89, ((-92, 44), (-12, 12))))]
    rows.append(vp.sheet(ims, ["rifle side", "3/4", "muzzle", "top"]))
    print("rifle", round(time.time() - t0, 1), flush=True)
    M = build("S2")
    for pose, lab in ((AIM, "aim"), (A.STANCE, "rest")):
        B = M.blocks(pose=pose)
        ims = [vp.render(B, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=pc, ss=2, size=sz, ao_amt=0.5)
               for y, p, pc, sz in ((330, 6, 1.4, ((-170, 170), (-10, 320))), (270, 4, 1.4, ((-150, 230), (-10, 320))),
                                    (305, 8, 2.4, ((-110, 190), (120, 290))))]
        rows.append(vp.sheet(ims, ["%s  3/4" % lab, "side", "close"]))
        print(lab, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
