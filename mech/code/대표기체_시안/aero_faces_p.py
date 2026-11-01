"""
aero_faces_p.py — Aero 얼굴 6차: F2 + M1 크기 눈 + 로봇 마스크류 특징 (2026-10-26 12:59~)

유저: "가운데 시안(F2)에서 눈 크기를 M1 정도로 하고 로봇 마스크류 특징을 살려서 다시" + 마스크 사진 2장(같은 원작 계열).
로봇 마스크류에 흔한 특징만 쓰고, 사진 속 원작 얼굴 그대로는 옮기지 않는다:
  K1 한 장짜리 페이스플레이트가 눈 아래 얼굴을 덮고, 윗변이 눈 소켓 아랫변이 된다
  K2 판이 가운데 세로선에서 좌우 두 면으로 접힘(위에서 얕은 V) — 두 판을 회전해 맞대 면은 평평하게
  K3 판 양옆을 볼 판이 한 단 뒤에서 겹쳐 감싸고, 그 사이 짙은 그늘 틈
  K4 판 표면 흡기 그릴(안마다 다름)
  K5 턱 끝 블록이 판 아래로 한 칸 나옴(짙은 회색 — 주황이면 혀처럼 읽혔다 · 5차)
  K6 판 윗변을 따라 짙은 띠 한 줄(눈 밑 그늘)
안: P1 가로 슬롯 그릴 2줄 / P2 세로 슬릿 그릴 / P3 그릴 없이 2단 겹친 판
"""
import numpy as np

from flag_vox import box, cbox, rotz
import aero_r1 as A
import aero_faces as F
import aero_faces_m as Mm

HP = F.HEAD_PARTS
FOLD = 18          # 판 접힘 각(위에서 본 V)


def faceplate(M, kind):
    p = M.parts["Head"]
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    # K3 판 뒤·옆 짙은 턱 뼈대 (판과 볼 사이 그늘)
    p.add(cbox(G, (-10, 10), (-18, -12), (238, 249), {"x-y": 2}) & (ax <= 10 - 0.5 * np.maximum(0, 244 - Z)), 3)
    # K5 턱 블록
    p.add(cbox(G, (-2, 2), (-23, -18), (237, 240), {"-z-y": 1, "x-y": 1}), 7)

    def half(Gl):
        Xl, Yl, Zl = Gl
        return (Zl >= 240 + 0.5 * Xl) & (Zl <= 249)          # 아래가 1:2 로 모이는 V

    # K1·K2 판 반쪽(왼쪽) — 세워 만들고 rotz 로 접음. 앞면 y -22, 두께 4
    F._slab(M, "H_PlateL", (0, 10), (-22, -19), (240, 249), rotz(FOLD), (0, -21, 244), 2, extra=half)
    pl = M.parts["H_PlateL"]; G2 = pl.g(); X2, Y2, Z2 = G2
    pl.paint((Z2 >= 248) & (Y2 <= -21), 3)                    # K6 윗변 짙은 띠
    pl.paint(X2 >= 9, 10)                                     # 바깥 옆면 밝은 회색(면 방향)
    if kind == "P1":     # K4 가로 슬롯 2줄(가운데 가까이, 짧게)
        for z in (243, 245):                                  # 짧게(3칸) · 바깥쪽 — 길게 가운데까지 오면 이를 드러낸 입(v1)
            pl.cut(box(G2, (4, 6), (-22, -22), (z, z)))
            pl.add(box(G2, (4, 6), (-21, -21), (z, z)), 4)
    elif kind == "P2":   # K4 세로 슬릿 3줄(판 아래쪽)
        for x in (4, 6):                                      # 두 줄·짧게 — 세 줄로 판 전체를 덮으면 이빨(v1)
            pl.cut(box(G2, (x, x), (-22, -22), (243, 246)) & half(G2))
            pl.add(box(G2, (x, x), (-21, -21), (243, 246)) & half(G2), 4)
    elif kind == "P3":   # 그릴 없이 아랫판이 한 단 앞으로 겹침
        F._slab(M, "H_PlateLowL", (0, 7), (-23, -22), (240, 245), rotz(FOLD), (0, -21, 244), 2,
                extra=lambda Gl: Gl[2] >= 240 + 0.5 * Gl[0])
        M.mirror("H_PlateLowL", "H_PlateLowR", "Head"); HP.append("H_PlateLowR")
    M.mirror("H_PlateL", "H_PlateR", "Head"); HP.append("H_PlateR")


def build(kind="P1"):
    M = A.build_all()
    p = F.head_core(M, "slant")
    Mm.big_eyes(p)                                            # M1 과 같은 눈(안쪽 1 → 바깥 3칸)
    F.head_plates(M, brow_deep=False)
    for n in ("H_MaskL", "H_MaskR", "H_MaskRidge"):
        M.parts.pop(n, None)
        if n in HP:
            HP.remove(n)
    faceplate(M, kind)
    F.fins(M, "F2")
    return M


def build_all():
    return build("P1")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["P1", "P2", "P3"]
    VIEWS = ((0, 4, ((-30, 30), (232, 292))), (30, 6, ((-32, 32), (232, 294))),
             (90, 2, ((-36, 36), (232, 294))), (150, 12, ((-32, 32), (234, 296))))
    rows = []
    for k in kinds:
        M = Mm.build("M1") if k == "M1" else build(k)
        keep = set(HP) | {"Torso"}
        B = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        ims = [vp.render(B, A.SCHEMES["A"] | {10: (186, 188, 190)}, A.EMISSIVE, yaw=y, pitch=p, ppc=9, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in VIEWS]
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
