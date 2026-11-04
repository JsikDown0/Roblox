"""BISON 지휘관형 ST-10C r1 (2026-11-04) — 윤곽 읽기 c1 답 [결정 11-04 "모두 동의"].
기본형 확정본(mass_final.build_armed) 위에 차이만:
  ① 안테나 하나 = 왼 어깨 캡 안쪽 위(받침 + 짙은 막대 r1.3 + 강철 끝) — 높이 z274(머리 꼭대기 260 보다 위)
  ② 보조 무장 통 3개씩 = 양 어깨판 뒤 면(PlateB / PlateBR) 바깥 위쪽, 입구 앞·바깥(판 회전을 따라) — 짙은 통 + 강철 입구 테 + 노랑 탄두(발광 아님) + 받침 판
  ③ 오른 어깨 = 왼 어깨(캡·관절 + PlateF/PlateB)의 거울 → 양쪽 대칭(PlateFR · PlateBR)
  ④ 목깃 양옆 센서 렌즈 = 짙은 상자 + 짙은 유리(4) + 강철 테, 발광 없음
  ⑤ 흉판 덧장갑 3칸(위 가슴, 아래로 좁아지는 판) — 가운데 = 엠블럼 데칼 자리
  ⑥ 허벅지 파트 폭·두께 +15%(다리 축 X 22 중심) · 무릎판 +15%
역할 = 강화된 스펙 + 아군 보조(수치는 동작·밸런스 단계).
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
import mass_leg_r2 as l2  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402
import mass_shoulder_r3 as s3  # noqa: E402
import mass_weapon_r1 as w1  # noqa: E402
import mass_final as MF  # noqa: E402

PAL, METAL, EMISSIVE = MF.PAL, MF.METAL, MF.EMISSIVE
CX = l2.CX


def grow(P, lo, hi):
    lo = np.minimum(P.lo, lo); hi = np.maximum(P.hi, hi)
    a = np.zeros(tuple(hi - lo), np.uint8); o = P.lo - lo
    a[o[0]:o[0] + P.a.shape[0], o[1]:o[1] + P.a.shape[1], o[2]:o[2] + P.a.shape[2]] = P.a
    P.a, P.lo, P.hi = a, np.array(lo), np.array(hi)


def scale_region(P, s, c, sel=None, axes=(1, 1, 1)):
    """P 의 칸(sel 이 주어지면 그 칸만)을 중심 c 로 axes 축 방향 s 배 — 가장 가까운 칸으로 다시 뽑아 덧붙임(원래 칸은 남김)."""
    c = np.asarray(c, float); k = np.where(np.asarray(axes) > 0, s, 1.0)
    src = P.a.copy()
    if sel is not None:
        src[~np.broadcast_to(sel, src.shape)] = 0
    ijk = np.argwhere(src > 0)
    if not len(ijk):
        return
    w = ijk + P.lo
    lo = np.floor(c + (w.min(0) - c) * k).astype(int) - 1; hi = np.ceil(c + (w.max(0) - c) * k).astype(int) + 2
    grow(P, lo, hi)
    X, Y, Z = P.g()
    shp = P.a.shape
    q = [np.broadcast_to(A, shp) for A in (X, Y, Z)]
    p = [np.round(c[i] + (q[i] - c[i]) / k[i]).astype(int) for i in range(3)]
    o = w.min(0); dims = w.max(0) - o + 1
    ok = np.ones(shp, bool)
    for i in range(3):
        ok &= (p[i] >= o[i]) & (p[i] < o[i] + dims[i])
    lut = np.zeros(tuple(dims), np.uint8)
    lut[tuple((w - o).T)] = src[tuple(ijk.T)]
    vals = np.zeros(shp, np.uint8)
    vals[ok] = lut[p[0][ok] - o[0], p[1][ok] - o[1], p[2][ok] - o[2]]
    m = vals > 0
    P.a[m] = vals[m]
    P.trim()


def mirror_shoulders(M):
    for n in ("ShoulderR",):
        M.parts.pop(n)
    M.mirror("ShoulderL", "ShoulderR", "Torso")
    for a, b in (("PlateF", "PlateFR"), ("PlateB", "PlateBR")):
        M.parts[b] = M.parts[a].mirrored(b, "ShoulderR")


def pods(M, plate):
    """PlateB(로컬 = 축에 맞춘 판, 바깥 면 X 63) 바깥 위쪽에 통 3개 — 축 = 로컬 −Y(판 회전 뒤 앞·바깥)."""
    P = M.parts[plate]
    grow(P, (P.lo[0], P.lo[1] - 2, P.lo[2]), (P.hi[0] + 10, P.hi[1], P.hi[2] + 2))
    G = P.g(); X, Y, Z = G
    XA = s3.XA; YA = s3.YA
    P.add(box(G, x=(XA + 2, XA + 3), y=(YA + 5, YA + 19), z=(227, 253)), 3)                    # 받침 판
    for zc in (248, 240, 232):
        cx_ = XA + 7.5
        P.add(cyl(G, "y", (cx_, zc), 3.6, rng=(YA + 4, YA + 18)), 3)                           # 통
        P.add(cyl(G, "y", (cx_, zc), 4.0, rng=(YA + 4, YA + 5)), 2)                            # 입구 테(앞 = 로컬 −Y) — [결정 11-04] 강철(금속)은 빛 받는 쪽이 하얗게 보여 짙은 쇠로
        P.cut(cyl(G, "y", (cx_, zc), 2.4, rng=(YA + 3, YA + 4)))
        P.add(cyl(G, "y", (cx_, zc), 2.4, rng=(YA + 5, YA + 5)), 5)                            # 노랑 탄두(오목)
        P.add(cyl(G, "y", (cx_, zc), 3.9, rng=(YA + 14, YA + 15)), 5)                          # 뒤 노랑 띠
    P.trim()


def build_all():
    M = MF.build_armed()
    mirror_shoulders(M)
    pods(M, "PlateB"); M.parts["PlateBR"] = M.parts["PlateB"].mirrored("PlateBR", "ShoulderR")
    # ① 안테나(왼 어깨 캡 안쪽 위)
    S = M.parts["ShoulderL"]; grow(S, (S.lo[0], S.lo[1], S.lo[2]), (S.hi[0], S.hi[1], 280))
    G = S.g()
    S.add(cbox(G, (28, 33), (1, 7), (246, 250), {"xy": 1}), 3)
    S.add(cyl(G, "z", (30.5, 4), 1.3, rng=(250, 274)), 3)
    S.add(cyl(G, "z", (30.5, 4), 1.8, rng=(258, 259)), 7)
    S.add(cyl(G, "z", (30.5, 4), 1.6, rng=(274, 276)), 7)
    S.trim()
    # ④ 목깃 센서 렌즈 · ⑤ 흉판 덧장갑
    T = M.parts["Torso"]; G = T.g(); X, Y, Z = G; ax = np.abs(X)
    for sg in (1, -1):
        xr = sorted((sg * 17, sg * 23))
        T.add(cbox(G, xr, (-27, -20), (237, 244), {"xy": 1}) & ~(T.a > 0), 3)
        T.add(cyl(G, "y", (sg * 20, 240.5), 2.4, rng=(-28, -28)), 7)
        T.add(cyl(G, "y", (sg * 20, 240.5), 1.6, rng=(-28, -28)), 4)
    yf = -26 * w1.SY
    plate = (ax <= 25 - np.clip(220 - Z, 0, None)) & (Z >= 212) & (Z <= 235) & (Y <= yf + 1)
    T.emboss(plate, 1, h=3)
    T.groove((ax <= 20 - np.clip(220 - Z, 0, None)) & (Z == 228) & (Y <= yf - 1), 4)          # 덧장갑 위·아래 판 나눔
    # ⑥ 허벅지 +15%(폭·두께) · 무릎판 +15%
    U = M.parts["UpperLegL"]; scale_region(U, 1.15, (CX, 0, 140), axes=(1, 1, 0))
    L = M.parts["LowerLegL"]; G = L.g(); X, Y, Z = G
    knee = (np.abs(X - CX) <= 13) & (Y <= -10) & (Z >= 89) & (Z <= 125) & (L.a == 2)
    scale_region(L, 1.15, (CX, -12, 107), sel=knee)
    for n, par in (("UpperLegR", "Pelvis"), ("LowerLegR", "UpperLegR")):
        M.parts.pop(n)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis"); M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.parts["FootR"].parent = "LowerLegR"; M.parts["PistonCylR"].parent = "LowerLegR"
    M.extra.update({"name": "BISON", "designation": "HT-10C", "variant": "commander"})
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    AS = MF.REST_POSE
    from flag_vox import rotx, roty
    M0 = MF.build_armed(); M = build_all()
    cm.check(M)
    swing = dict(AS, UpperArmL=rotx(-50) @ roty(-9), UpperArmR=rotx(-50) @ roty(9))
    print("겹침 쉬는", w1.overlaps(M, AS, [("PlateB", ("UpperArmL", "LowerArmL", "Head", "Torso")), ("PlateBR", ("UpperArmR", "LowerArmR", "Head", "Torso")),
                                          ("ShoulderL", ("Head",)), ("UpperLegL", ("UpperLegR", "Pelvis", "HandL", "Shield")), ("UpperLegR", ("RifleStowed", "RifleMount", "HandR"))]))
    print("겹침 팔 앞 50°", w1.overlaps(M, swing, [("PlateB", ("UpperArmL", "LowerArmL")), ("PlateBR", ("UpperArmR", "LowerArmR"))]))
    R = lambda Mm, y, p, ppc=1.9: vp.render(Mm.blocks(pose=l4.aim(Mm, AS)[0], skip=("RifleStowed",)), PAL, EMISSIVE, yaw=y, pitch=p, ppc=ppc, ss=2,
                                           ao_amt=0.5, bg=(132, 132, 132), light=(-0.75, -0.55, 0.6), metal=METAL)
    con = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "양산형", "지휘관형", "concept_c1_삼면도.png")).convert("RGB")
    views = ((0, 2), (-35, 8), (-90, 2), (150, 10))
    rows = [("기본형 ST-10", [R(M0, y, p) for y, p in views]), ("지휘관형 ST-10C", [R(M, y, p) for y, p in views])]
    up = []
    for y, p, fr in ((-30, 10, (0.0, 0.0, 1.0, 0.45)), (60, 12, (0.0, 0.0, 1.0, 0.45)), (160, 14, (0.0, 0.0, 1.0, 0.45))):
        im = R(M, y, p, 3.0); w, h = im.size; up.append(im.crop((int(w * fr[0]), int(h * fr[1]), int(w * fr[2]), int(h * fr[3]))))
    rows.append(("지휘관형 상체 확대", up))
    H = max(i.height for _, ims in rows for i in ims)
    cH = H; cc = con.resize((int(con.width * cH / con.height), cH))
    W = max(max(sum(i.width for i in ims) for _, ims in rows) + 16 * 5, cc.width + 32) + 20
    sh = Image.new("RGB", (W, 60 + (len(rows) + 1) * (H + 46)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "BISON 지휘관형 ST-10C r1 — 안테나(왼 어깨) · 양 어깨 판 + 보조 무장 통 · 목깃 렌즈 · 흉판 덧장갑 · 허벅지·무릎 +15%", fill=(235, 235, 235), font=ft)
    allrows = [("컨셉 c1", [cc])] + rows
    for r_, (nm, ims) in enumerate(allrows):
        y0 = 60 + r_ * (H + 46); x = 16
        d.text((16, y0 - 2), nm, fill=(255, 190, 90), font=f)
        for im in ims:
            sh.paste(im, (x, y0 + 26)); x += im.width + 16
    p = os.path.join(out, "시안_지휘관형r1.png"); sh.save(p); print(p, sh.size)
