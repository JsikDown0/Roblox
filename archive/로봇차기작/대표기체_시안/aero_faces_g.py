"""
aero_faces_g.py — Aero 얼굴 4차: F1 을 바탕으로 입체감 다듬기 (2026-10-26 12:36~)

유저가 준 수정 지시서(복셀_로봇_머리_디자인_수정_지시서.docx)는 레퍼런스 머리(타사 게임 기체)에 맞추는 게 목표라
그 머리 모양으로 옮기는 부분은 하지 않고, 우리 F1 을 더 기계적·입체적으로 만드는 항목만 적용:
  ① 깃(귀)을 두껍고 구조적으로: 뿌리 4칸 두께 → 끝 2칸, 중간에서 바깥으로 한 번 꺾임, 끝은 바늘이 아니라 잘린 사선,
     안쪽 면 어두운 주황, 뿌리는 짙은 경첩 뭉치에 박힘(측면·후면에서 층으로 이어짐)
  ② 눈 소켓을 깊게: 뼈대 속으로 3칸 판 검은 홈 안에 눈, 눈썹 처마가 위를 가림, 눈 1칸 굵기
  ③ 주황 3단 명도: 밝은(빛 받는 윗·앞 모서리) / 기본 / 어두운(눈썹 밑·깃 안쪽·판 가장자리 아래)
  ④ 흰색 2단: 앞면 흰색 + 옆면 밝은 회색(면 방향 구분)
  ⑤ 뒷머리: 주황 판이 짙은 구조물 위에 한 단씩 겹치게(정면에서 회색이 덜 보이게)
안 2개는 깃 꺾임만 다름: G1 12° · G2 28°.
새 색 번호(이 기체 팔레트에 추가): 8 어두운 주장갑 · 9 밝은 주장갑 · 10 밝은 회색(보조장갑 옆면)
"""
import numpy as np

import flag_vox as fv
from flag_vox import box, cbox, poly, cyl, rotx, roty, rotz
import aero_r1 as A
import aero_faces as F

SCHEMES = {k: dict(v) for k, v in A.SCHEMES.items()}
SCHEMES["A"].update({8: (164, 78, 26), 9: (246, 156, 74), 10: (186, 188, 190)})
SCHEMES["B"].update({8: (184, 186, 188), 9: (246, 246, 242), 10: (170, 86, 28)})
SCHEMES["C"].update({8: (160, 158, 150), 9: (226, 224, 216), 10: (60, 64, 70)})
HP = F.HEAD_PARTS


def core(M):
    p = F.head_core(M, "slant")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    # ② 눈 소켓: 뼈대 앞면(-15)에서 3칸 파고 들어감 → 바닥 검정, 눈은 바닥 바로 앞(-13)
    p.cut(box(G, (-8, 8), (-17, -12), (247, 254)))                 # F1 의 앞쪽 눈(-17)까지 같이 걷어 냄(안 지우면 떠 있는 섬)
    p.add(box(G, (-8, 8), (-12, -12), (247, 254)), 4)
    e = (ax >= 2) & (ax <= 7) & (Z >= 249 + 0.5 * (ax - 2) - 0.5) & (Z <= 249.6 + 0.5 * (ax - 2))
    p.add(e & (Y >= -13) & (Y <= -13), 6)
    # 소켓 위·옆 테(짙은 회색) — 눈이 평면 장식이 아니라 구멍 속에 있게
    p.add(box(G, (-9, 9), (-16, -13), (254, 255)), 3)
    for s in (1, -1):
        p.add(box(G, (s * 9, s * 9), (-16, -13), (247, 254)) if s > 0 else box(G, (-9, -9), (-16, -13), (247, 254)), 3)
    # ⑤ 뒷머리 층: 짙은 구조물(아래) 위에 주황 판(위)이 한 단 뒤로 겹침 + 가로 배기 홈
    p.cut(box(G, (-9, 9), (8, 13), (243, 257)))
    p.add(cbox(G, (-8, 8), (8, 11), (243, 252), {"+yx": 2}), 3)
    p.add(cbox(G, (-9, 9), (9, 13), (250, 258), {"+y+z": 3, "+yx": 2, "-z+y": 2}), 1)
    p.paint(box(G, (-9, 9), (9, 13), (250, 251)), 8)                 # 판 아래 가장자리 = 어두운 주황
    p.cut(box(G, (-5, 5), (10, 11), (246, 247)))
    p.add(box(G, (-5, 5), (9, 9), (246, 247)), 4)
    return p


def plates(M):
    F.head_plates(M, brow_deep=False)
    for s in ("L", "R"):
        # ③ 눈썹: 밑면 어두운 / 윗앞 모서리 밝은
        b = M.parts["H_Brow" + s]; G = b.g(); X, Y, Z = G
        b.paint(Z <= 253, 8)
        b.paint((Z >= 257) & (Y <= -19), 9)
        # 정수리: 앞 모서리 밝게, 바깥 끝 어둡게
        c = M.parts["H_Crown" + s]; G = c.g(); X, Y, Z = G
        c.paint(Y <= -13, 9)
        c.paint(np.abs(X) >= 11, 8)
        # ④ 볼: 바깥 옆면 밝은 회색, 앞을 한 칸 더 내밀어 눈 바깥 끝을 감쌈
        k = M.parts["H_Cheek" + s]; G = k.g(); X, Y, Z = G
        k.add(cbox(G, (10, 12) if s == "L" else (-12, -10), (-19, -17), (247, 254), {"-z-y": 2}), 2)
        k.paint(np.abs(X) >= 12, 10)
        mk = M.parts["H_Mask" + s]; G = mk.g(); X, Y, Z = G
        mk.paint(Y >= -19, 10)


# ① 깃: 두 마디(아래 = 뿌리, 위 = 꺾인 끝). 세워 만들고 회전.
LOW = [(-7, 0), (7, 0), (6, 15), (-5, 15)]                    # 뿌리 마디(위로 살짝 좁아짐)
UP = [(-5, 0), (5, 0), (4, 6), (2, 12), (-1, 15), (-5, 11)]   # 끝 마디: 뒤 변 한 단 턱, 끝은 잘린 사선(-1,15)~(-5,11)


def _seg(M, name, parent, root, prof, thick, rot, inner_sign):
    x0, x1 = thick
    pts = [(root[1] + y, root[2] + z) for y, z in prof]
    ys = [q[0] for q in pts]; zs = [q[1] for q in pts]
    p = M.part(name, (root[0] + min(x0, x1) - 3, int(min(ys)) - 2, int(min(zs)) - 2),
               (root[0] + max(x0, x1) + 4, int(max(ys)) + 3, int(max(zs)) + 3), pivot=root, parent=parent)
    G = p.g(); X, Y, Z = G
    lo, hi = root[0] + min(x0, x1), root[0] + max(x0, x1)
    blade = poly(G, "x", pts, rng=(lo, hi))
    p.add(blade, 1)
    # 안쪽 면(머리 쪽) 어두운 주황 — 두께와 방향이 보이게
    p.paint(blade & ((X <= lo) if inner_sign > 0 else (X >= hi)), 8)
    # 바깥 면 가운데 접힌 능선(밝은 주황) 한 줄
    outer = hi + 1 if inner_sign > 0 else lo - 1
    p.emboss(poly(G, "x", [(root[1] - 1, root[2] + 1), (root[1] + 1, root[2] + 1),
                           (root[1] + 1, max(zs) - 3), (root[1] - 1, max(zs) - 3)], rng=(outer, outer)), 9)
    p.rot = rot
    HP.append(name)
    return p


def fins(M, bend):
    for s in (1, -1):
        sfx = "L" if s > 0 else "R"
        root = (9 * s, 0, 262)
        # 뿌리 경첩 뭉치(짙게) + 주황 덮개 — 정수리 판·깃 뿌리·뒷머리가 층으로 이어지게
        _slab_root(M, "H_FinMount" + sfx, s)
        base = roty(14 * s) @ rotx(-30) @ rotz(-20 * s)
        th = (0, 4) if s > 0 else (-4, 0)
        _seg(M, "Fin" + sfx, "Head", root, LOW, th, base, s)
        # 끝 마디: 뿌리 마디 끝에서 바깥으로 bend° 더 꺾임(부모 = 뿌리 마디, 피벗 = 마디 끝)
        tip_root = (root[0], root[1], root[2] + 15)
        th2 = (0, 3) if s > 0 else (-3, 0)
        _seg(M, "FinTip" + sfx, "Fin" + sfx, tip_root, UP, th2, roty(bend * s), s)
        # 보조 깃(뒤, 흰색) — F1 과 같음
        F._fin(M, "FinSub" + sfx, (8 * s, 4, 262), F.FIN_SUB, base @ rotx(-10), 2,
               (0, 1) if s > 0 else (-1, 0), edge=False)


def _slab_root(M, name, s):
    x = (7, 12) if s > 0 else (-12, -7)
    p = M.part(name, (x[0] - 3, -10, 252), (x[1] + 4, 12, 268), pivot=(9 * s, 0, 262), parent="Head")
    G = p.g(); X, Y, Z = G
    p.add(cbox(G, x, (-6, 7), (256, 264), {"xy": 2, "+zy": 2}), 3)
    xc = (x[0] + 1, x[1] + 1) if s > 0 else (x[0] - 1, x[1] - 1)
    p.add(cbox(G, xc, (-7, 2), (260, 265), {"x-y": 2, "+z-y": 2}), 1)                     # 주황 덮개(한 칸 바깥)
    p.paint(Z <= 260, 8)
    HP.append(name)


def build(kind="G1"):
    M = A.build_all()
    core(M)
    plates(M)
    fins(M, {"G1": 12, "G2": 28}[kind])
    return M


def build_all():
    return build("G1")


def label(im, pts, font):
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    for (x, y), (tx, ty), text in pts:
        d.line([(x, y), (tx, ty)], fill=(120, 220, 255), width=2)
        d.ellipse([x - 4, y - 4, x + 4, y + 4], outline=(120, 220, 255), width=2)
        d.text((tx + 4, ty - 12), text, fill=(120, 220, 255), font=font)
    return im


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image, ImageFont
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["F1", "G1", "G2"]
    font = ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 22, index=1)
    VIEWS = ((0, 4, ((-30, 30), (234, 294))), (30, 6, ((-32, 32), (234, 296))),
             (90, 2, ((-34, 34), (234, 296))), (180, 10, ((-32, 32), (234, 296))))
    PPC = 9
    rows = []
    for k in kinds:
        if k.startswith("F"):
            M = F.build(k); sch = SCHEMES["A"]
        else:
            M = build(k); sch = SCHEMES["A"]
        keep = set(HP) | {"Torso"}
        B = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        ims = [vp.render(B, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=PPC, ss=2, size=sz, ao_amt=0.5) for y, p, sz in VIEWS]
        if k == "G1":
            # 정면 주석: 화면 x = X, 화면 y = sin4·Y + cos4·Z (yaw 0, pitch 4)
            (x0, x1), (y0, y1) = VIEWS[0][2]
            s4, c4 = np.sin(np.radians(4)), np.cos(np.radians(4))
            P = lambda X, Y, Z: ((X - x0) * PPC, (y1 - (s4 * Y + c4 * Z)) * PPC)
            ims[0] = label(ims[0], [
                (P(5, -13, 250), (P(14, -13, 239)[0], P(14, -13, 239)[1]), "눈 소켓"),
                (P(5, -20, 255), (P(14, -20, 261)[0], P(14, -20, 261)[1]), "눈썹 처마"),
                (P(11, -18, 250), (P(16, -18, 246)[0], P(16, -18, 246)[1]), "볼 가드"),
                (P(-11, 0, 263), (P(-29, 0, 266)[0], P(-29, 0, 266)[1]), "깃 뿌리"),
                (P(-15, 0, 279), (P(-29, 0, 286)[0], P(-29, 0, 286)[1]), "꺾임"),
            ], font)
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
