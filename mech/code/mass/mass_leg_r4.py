"""양산형 하체 r4 (2026-11-03) — 하체 = r3 E 확정 [결정 11-03 "E 로 가자"] + 개선 3:
  1) 피스톤 회색 부분 → 금속 파트 + **실제로 구동**  2) 호스를 옆으로 살짝 벌려 입체적으로  3) 발끝 갈라짐 "표현"(홈) 없애고 실제로 살짝 가름.

1) 피스톤 = 별도 파트 2개(발목 액추에이터):
   PistonCylL  부모 LowerLegL · 피벗 = 위 고정점 T (CX, −15.5, 90)(무릎판 밑) · 실린더 r4.5 · 길이 22 · 색 7 강철(금속) + 노랑 띠 + 짙은 고정 귀
   PistonRodL  부모 FootL     · 피벗 = 아래 고정점 B (CX, −16, 46)(발 혀 위 짙은 귀) · 로드 r2.4 · 길이 30 · 새 색 8 크롬(금속)
   매 프레임 실린더는 B 를, 로드는 T 를 바라보게 돌림 → 발이 까딱이면(걷기·착지) 로드가 실린더 속으로 들어갔다 나옴.
   쉬는 자세 길이 |T−B| ≈ 44 · 겹침 = 22 + 30 − 길이(> 0 이어야 로드가 실린더 속) — 아래 표에 자세별 실측.
   커프 가운데에 로드가 지나가는 틈(±4, 속 짙은)을 냄. Studio 구동 = mech/studio/mass_piston.lua.
2) 호스 가운데 두 점을 바깥 +3 · 뒤 +1.5 로 띄우고 양끝에 짙은 죔쇠.
3) 발끝: 가운데 홈 대신 3칸 폭 · 앞 13칸 실제 틈(스타일 가이드 1-4 "발은 한 덩어리" → 유저 결정으로 이 기체는 살짝 가른 발끝).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cyl, box, cbox, rotx, roty  # noqa: E402
import mass_r1 as r1  # noqa: E402
import mass_leg_r2 as l2  # noqa: E402
import mass_leg_r3 as l3  # noqa: E402

PAL = dict(l3.PAL); PAL[8] = (196, 198, 200)                   # 8 = 크롬 로드
METAL = {7: 1.0, 8: 1.0}
CX = l3.CX
T_ = np.array((CX, -15.5, 90.0)); B_ = np.array((CX, -16.0, 46.0))
LC, LR, RC, RR = 22, 30, 4.5, 2.4


def _xf(T, p):
    return T[:3, :3] @ p + T[:3, 3]


def _inv(T):
    I = np.eye(4); I[:3, :3] = T[:3, :3].T; I[:3, 3] = -T[:3, :3].T @ T[:3, 3]; return I


def _rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    V = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + V + V @ V * (1 / (1 + c))


def build_pistons(M):
    WL, WF = M.world("LowerLegL"), M.world("FootL")
    Bl = _xf(_inv(WL) @ WF, B_)                                    # B 를 정강이 좌표로
    Tf = _xf(_inv(WF) @ WL, T_)                                    # T 를 발 좌표로
    C = M.part("PistonCylL", (CX - 8, -26, 60), (CX + 9, -6, 96), pivot=tuple(T_), parent="LowerLegL")
    G = C.g()
    d = (Bl - T_) / np.linalg.norm(Bl - T_)
    C.add(r1.seg(G, T_ + d * 2, T_ + d * LC, RC), 7)               # 실린더(강철)
    C.add(r1.seg(G, T_ + d * 6, T_ + d * 8, RC + 0.5), 5)          # 노랑 띠
    C.add(r1.seg(G, T_ + d * (LC - 2), T_ + d * LC, RC + 0.6), 3)  # 아래 테(짙은)
    C.add(r1.seg(G, T_, T_ + d * 3, 2.6), 3)                       # 위 고정 귀
    C.add(cyl(G, "x", (T_[1], T_[2]), 2.2, rng=(CX - 3, CX + 3)), 3)
    C.trim()
    R = M.part("PistonRodL", (CX - 6, -26, 38), (CX + 7, -6, 84), pivot=tuple(B_), parent="FootL")
    G = R.g()
    e = (Tf - B_) / np.linalg.norm(Tf - B_)
    R.add(r1.seg(G, B_ + e * 2, B_ + e * LR, RR), 8)               # 로드(크롬)
    R.add(r1.seg(G, B_, B_ + e * 3, 2.4), 3)                       # 아래 고정 귀
    R.add(cyl(G, "x", (B_[1], B_[2]), 2.0, rng=(CX - 3, CX + 3)), 3)
    R.trim()
    # 발 혀 위 짙은 귀 받침 + 커프 가운데 틈
    F = M.parts["FootL"]; G = F.g(); X, Y, Z = G
    F.add(cbox(G, (CX - 4, CX + 4), (-20, -12), (38, 44), {"xy": 1}) & ~(F.a > 0), 3)
    L = M.parts["LowerLegL"]; G = L.g(); X, Y, Z = G
    slot = (np.abs(X - CX) <= 4) & (Y <= -9) & (Z >= 43) & (Z <= 60)
    L.cut(slot)
    L.add((np.abs(X - CX) <= 4) & (Y == -8) & (Z >= 43) & (Z <= 60), 3)
    for n in ("PistonCylL", "PistonRodL"):
        M.mirror(n, n[:-1] + "R")


def build_all(ws=0.88):
    M = l2.build_all("A", ws)
    l3.build_lower(M, "E", piston=False, hose_out=3, toe="split")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")                # build_lower 가 만든 R 을 다시 거울(커프 틈·귀 반영 전후 맞춤)
    build_pistons(M)
    M.parts.pop("LowerLegR"); M.parts.pop("FootR")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR"); M.mirror("FootL", "FootR", "LowerLegR")
    for n in ("PistonCylR", "PistonRodR"):                         # 부모 이름 다시 확인
        M.parts[n].parent = {"PistonCylR": "LowerLegR", "PistonRodR": "FootR"}[n]
    return M


def aim(M, pose):
    """실린더·로드가 서로의 고정점을 바라보게 하는 pose 를 더함 + 자세별 길이/겹침."""
    pose = dict(pose or {}); info = {}
    for s in "LR":
        sx = 1 if s == "L" else -1
        Tm = np.array((sx * T_[0], T_[1], T_[2])); Bm = np.array((sx * B_[0], B_[1], B_[2]))
        WL, WF = M.world("LowerLeg" + s, pose), M.world("Foot" + s, pose)
        Tw, Bw = _xf(WL, Tm), _xf(WF, Bm)
        for part, piv, tgt_w, par_w in (("PistonCyl" + s, Tm, Bw, WL), ("PistonRod" + s, Bm, Tw, WF)):
            rest_tgt = Bm if part.startswith("PistonCyl") else Tm
            rest_par = _xf(_inv(M.world("LowerLeg" + s)) @ M.world("Foot" + s), Bm) if part.startswith("PistonCyl") else \
                _xf(_inv(M.world("Foot" + s)) @ M.world("LowerLeg" + s), Tm)
            cur = _xf(_inv(par_w), tgt_w)
            pose[part] = _rot_between(rest_par - piv, cur - piv)
        Lh = float(np.linalg.norm(Tw - Bw)); info[s] = (round(Lh, 1), round(LC + LR - Lh, 1), round(Lh - LR, 1))
    return pose, info


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
                          '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 20); ft = ImageFont.truetype(FN, 26)
    M = build_all()
    for pn in ("LowerLegL", "FootL", "PistonCylL", "PistonRodL", "LowerLegR", "PistonRodR"):
        p = M.parts[pn]; _, k = ndimage.label(p.a > 0)
        print(pn, p.parent, p.count(), "tris", 2 * greedy_quads(p.a), "섬", k - 1)
    AS = l2.ARM_SPLAY
    # flag_vox rotx(+a) = 발끝이 아래로(렌더로 확인)
    poses = [("쉬는 자세", dict(AS)),
             ("발끝 아래로 20°", dict(AS, FootL=rotx(20), FootR=rotx(20))),
             ("발끝 위로 20°", dict(AS, FootL=rotx(-20), FootR=rotx(-20))),
             ("걷기(무릎 30° · 발 −15°)", dict(AS, UpperLegL=rotx(-25), LowerLegL=rotx(30), FootL=rotx(-15),
                                         UpperLegR=rotx(20), LowerLegR=rotx(10), FootR=rotx(15)))]
    tiles = []
    for nm, ps in poses:
        pz, info = aim(M, ps)
        print(nm, "길이·겹침·로드 끝 여유(L/R)", info)
        im = vp.render(M.blocks(pose=pz), PAL, r1.EMISSIVE, yaw=-90, pitch=2, ppc=4.2, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                       light=(-0.75, -0.55, 0.6), metal=METAL)
        im2 = vp.render(M.blocks(pose=pz), PAL, r1.EMISSIVE, yaw=-30, pitch=6, ppc=4.2, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                        light=(-0.75, -0.55, 0.6), metal=METAL)
        tiles.append((nm + "  L=%.0f 겹침 %.0f" % (info["L"][0], info["L"][1]), [i.crop((0, int(i.height * 0.6), i.width, i.height)) for i in (im2, im)]))
    full = [vp.render(M.blocks(pose=aim(M, AS)[0]), PAL, r1.EMISSIVE, yaw=y, pitch=p, ppc=1.9, ss=2, ao_amt=0.5, bg=(132, 132, 132),
                      light=(-0.75, -0.55, 0.6), metal=METAL) for y, p in ((0, 2), (-35, 8), (-90, 2), (150, 10))]
    H1 = max(i.height for i in full)
    tw = max(sum(i.width for i in ims) + 16 for _, ims in tiles); th = max(max(i.height for i in ims) for _, ims in tiles)
    W = max(sum(i.width for i in full) + 16 * 5, tw * 2 + 48)
    sh = Image.new("RGB", (W, 60 + H1 + 40 + 2 * (th + 40)), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((16, 14), "양산형 하체 r4 — E + 금속 피스톤 파트(구동) · 호스 띄움 · 발끝 실제로 가름", fill=(235, 235, 235), font=ft)
    x = 16
    for im in full:
        sh.paste(im, (x, 60)); x += im.width + 16
    for i, (nm, ims) in enumerate(tiles):
        x0 = 16 + (i % 2) * (tw + 16); y0 = 60 + H1 + 40 + (i // 2) * (th + 40)
        d.text((x0, y0 - 30), nm, fill=(255, 190, 90), font=f)
        x = x0
        for im in ims:
            sh.paste(im, (x, y0)); x += im.width + 16
    p = os.path.join(out, "시안_하체r4_피스톤구동.png"); sh.save(p); print(p, sh.size)
