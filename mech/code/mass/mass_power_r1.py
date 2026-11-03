"""양산형 상체 동력부 r1 (2026-11-03) — 유저 "상체에도 동력부를 추가하자(지금 하체에만 있음) · 골반의 구멍 난 부분을 덮자".

하체 r4 위에:
  · 골반 샅판 둥근 구멍 → 덮음(구멍 자리를 판과 같은 높이로 채움)
  · 팔 피스톤 = 하체 피스톤과 같은 구조(실린더 = 강철 7 + 노랑 띠 / 로드 = 크롬 8, 둘 다 별도 파트, 매 프레임 서로를 바라봄) —
    팔꿈치를 건너질러 위팔 ↔ 아래팔을 이음 → 팔을 굽히면 로드가 들어갔다 나옴.
  A  팔 뒤(삼두근 자리): T = 위팔 뒤 (43, 12, 214) · B = 아래팔 뒤 (43, 13, 170) — 게임 3인칭 카메라(뒤)에서 늘 보임
  B  팔 바깥 옆: T = 위팔 바깥 (56, 0, 214) · B = 아래팔 바깥 (58, 0, 170) — 정면·옆에서 보임
파트: ArmCylL(부모 UpperArmL) · ArmRodL(부모 LowerArmL) → 거울. 구동 = mech/studio/mass_piston.lua(ArmCylJoint/ArmRodJoint · ArmTop/ArmBot).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, rotx  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_leg_r2 as l2  # noqa: E402
import mass_leg_r4 as l4  # noqa: E402

PAL, METAL = l4.PAL, l4.METAL
_xf, _inv, _rot = l4._xf, l4._inv, l4._rot_between
NAMES = {"A": "A 팔 뒤 피스톤", "B": "B 팔 바깥 옆 피스톤"}
# 길이 [실측: 팔꿈치 0~120° 훑기] A 46.0~53.8 → 실린더 28 + 로드 30(최소 겹침 4) · B 24.8~46.1(110° 까지 28.1) → 26 + 26(팔꿈치 110° 까지)
ARM = {"A": dict(T=(43, 12.5, 214), B=(43, 13.5, 168), lug=(0, 1, 0), Lc=28, Lr=30),
       "B": dict(T=(56.5, 0, 214), B=(58.5, 0, 168), lug=(1, 0, 0), Lc=26, Lr=26)}
RCA, RRA = 3.4, 1.9
# (실린더 파트, 로드 파트, 실린더 부모, 로드 부모, T, B) — 하체 + 팔 공통 조준
ACT = []


def cover_pelvis_hole(M):
    P = M.parts["Pelvis"]; G = P.g(); X, Y, Z = G
    P.add(cyl(G, "y", (0, 163), 3.8) & (Y >= -16) & (Y <= -12), 1)


def actuator(M, cname, rname, ca, ra, T, B, Lc, Lr, rc, rr, lug):
    T = np.array(T, float); B = np.array(B, float)
    WA, WB = M.world(ca), M.world(ra)
    Bl = _xf(_inv(WA) @ WB, B); Tl = _xf(_inv(WB) @ WA, T)
    pad = int(max(Lc, Lr) + 6)
    C = M.part(cname, tuple(np.floor(T - pad).astype(int)), tuple(np.ceil(T + pad).astype(int)), pivot=tuple(T), parent=ca)
    G = C.g(); d = (Bl - T) / np.linalg.norm(Bl - T)
    C.add(r1.seg(G, T + d * 2, T + d * Lc, rc), 7)
    C.add(r1.seg(G, T + d * 5, T + d * 6.5, rc + 0.5), 5)
    C.add(r1.seg(G, T + d * (Lc - 1.5), T + d * Lc, rc + 0.5), 3)
    C.add(r1.seg(G, T, T + d * 2.5, rc - 0.6), 3)
    C.trim()
    R = M.part(rname, tuple(np.floor(B - pad).astype(int)), tuple(np.ceil(B + pad).astype(int)), pivot=tuple(B), parent=ra)
    G = R.g(); e = (Tl - B) / np.linalg.norm(Tl - B)
    R.add(r1.seg(G, B + e * 2, B + e * Lr, rr), 8)
    R.add(r1.seg(G, B, B + e * 2.5, rr + 0.6), 3)
    R.trim()
    # 고정 귀(짙은): 부모 파트 겉면에서 고정점까지
    lug = np.array(lug, float)
    for part, P_ in ((ca, T), (ra, B)):
        Q = M.parts[part]
        lo = np.minimum(Q.lo, np.floor(P_ - 4).astype(int)); hi = np.maximum(Q.hi, np.ceil(P_ + 5).astype(int))
        a = np.zeros(tuple(hi - lo), np.uint8); o = Q.lo - lo
        a[o[0]:o[0] + Q.a.shape[0], o[1]:o[1] + Q.a.shape[1], o[2]:o[2] + Q.a.shape[2]] = Q.a
        Q.a, Q.lo, Q.hi = a, lo, hi
        G = Q.g()
        Q.add(r1.seg(G, P_ - lug * 4, P_, 2.4) & ~(Q.a > 0), 3)
        Q.trim()


def build_all(v="A", ws=0.88):
    M = l4.build_all(ws)
    cover_pelvis_hole(M)
    a = ARM[v]
    actuator(M, "ArmCylL", "ArmRodL", "UpperArmL", "LowerArmL", a["T"], a["B"], a["Lc"], a["Lr"], RCA, RRA, a["lug"])
    for n in ("UpperArmL", "LowerArmL"):                                                    # 귀가 붙은 팔을 다시 거울
        M.parts.pop(n[:-1] + "R")
    M.mirror("UpperArmL", "UpperArmR", "Torso"); M.mirror("LowerArmL", "LowerArmR", "UpperArmR")
    M.parts["HandR"].parent = "LowerArmR"
    M.mirror("ArmCylL", "ArmCylR", "UpperArmR"); M.mirror("ArmRodL", "ArmRodR", "LowerArmR")
    M.extra["arm_act"] = (a["T"], a["B"], a["Lc"], a["Lr"])
    return M


def aim_all(M, pose):
    pose, info = l4.aim(M, pose)
    T, B, LCA, LRA = M.extra["arm_act"]
    for s in "LR":
        sx = 1 if s == "L" else -1
        Tm = np.array((sx * T[0], T[1], T[2])); Bm = np.array((sx * B[0], B[1], B[2]))
        WU, WL = M.world("UpperArm" + s, pose), M.world("LowerArm" + s, pose)
        Tw, Bw = _xf(WU, Tm), _xf(WL, Bm)
        rest_B = _xf(_inv(M.world("UpperArm" + s)) @ M.world("LowerArm" + s), Bm)
        rest_T = _xf(_inv(M.world("LowerArm" + s)) @ M.world("UpperArm" + s), Tm)
        pose["ArmCyl" + s] = _rot(rest_B - Tm, _xf(_inv(WU), Bw) - Tm)
        pose["ArmRod" + s] = _rot(rest_T - Bm, _xf(_inv(WL), Tw) - Bm)
        Lh = float(np.linalg.norm(Tw - Bw)); info["arm" + s] = (round(Lh, 1), round(LCA + LRA - Lh, 1), round(Lh - LRA, 1), round(Lh - LCA, 1))
    return pose, info


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    from flag_vox import roty
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    AS = l2.ARM_SPLAY
    bend = lambda a: dict(AS, LowerArmL=rotx(-a), LowerArmR=rotx(-a))
    rows = []
    for v in "AB":
        M = build_all(v)
        for pn in ("Pelvis", "UpperArmL", "LowerArmL", "ArmCylL", "ArmRodL"):
            p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
            print(v, pn, p.parent, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
        ims = []
        for nm, ps, y, pt, ppc in (("정면", AS, 0, 2, 1.9), ("앞 3/4", AS, -35, 8, 1.9), ("뒤 3/4", AS, 150, 10, 1.9),
                                   ("팔꿈치 0° 옆", AS, -90, 2, 3.6), ("팔꿈치 60°", bend(60), -90, 2, 3.6), ("팔꿈치 110°", bend(110), -90, 2, 3.6)):
            pz, info = aim_all(M, ps)
            if "팔꿈치" in nm:
                print(v, nm, "팔 피스톤 길이·겹침·로드여유·실린더여유", info["armL"])
            im = vp.render(M.blocks(pose=pz), PAL, r1.EMISSIVE, yaw=y, pitch=pt, ppc=ppc, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                           light=(-0.75, -0.55, 0.6), metal=METAL)
            if "팔꿈치" in nm:
                im = im.crop((0, int(im.height * 0.1), im.width, int(im.height * 0.55)))
            ims.append((nm + ("  L=%.0f" % info["armL"][0] if "팔꿈치" in nm else ""), im))
        rows.append((NAMES[v], ims))
    H = max(i.height for _, ims in rows for _, i in ims)
    cols = [max(ims[i][1].width for _, ims in rows) for i in range(6)]
    W = 230 + sum(cols) + 16 * 7
    sh = Image.new("RGB", (W, 60 + len(rows) * (H + 50)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 상체 동력부 r1 — 팔꿈치 피스톤(하체와 같은 구조, 구동) · 골반 구멍 덮음", fill=(235, 235, 235), font=ft)
    for r, (nm, ims) in enumerate(rows):
        y0 = 60 + r * (H + 50); x = 230
        d.text((16, y0 + H // 2 - 12), nm, fill=(255, 190, 90), font=f)
        for i, (t, im) in enumerate(ims):
            sh.paste(im, (x + (cols[i] - im.width) // 2, y0 + (H - im.height) // 2)); d.text((x + 6, y0 + H + 8), t, fill=(220, 220, 220), font=f); x += cols[i] + 16
    p = os.path.join(out, "시안_상체동력부r1.png"); sh.save(p); print(p, sh.size)
