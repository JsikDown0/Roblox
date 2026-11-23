"""
aero_faces_t.py — Aero 얼굴 7차: P2 + 실제 투구의 가운데 띠 (2026-10-26 13:05~)

유저: "P2 기준으로 투구를 깎아볼까? 실제 투구의 가운데 부분을 잘라서 붙인 거처럼. 줄 장식처럼 보이는 건 안 따라 해도 돼"
+ 고대 청동 투구 사진(빨간 선으로 가운데 띠를 표시: 정수리 갈래 장식 → 이마로 내려오는 능선 띠 → 눈썹 만나는 곳에서 넓어짐 → 두 눈 사이로 내려오는 코가리개, 끝이 뾰족).
옮긴 것(주황 한 색, 판 테두리 줄·점 장식 없음):
  ① 정수리 갈래 장식: 짙은 받침 + 위로 선 두 갈래(끝 모따기) — 정수리 능선 위, 이마 쪽
  ② 정수리 능선 띠: 지붕형 정수리 판 두 장이 만나는 선 위에 돋은 띠(정수리 판과 같은 12° 숙임)
  ③ 이마 판: 능선 띠가 이마로 내려와 눈썹(V) 만나는 곳에서 방패꼴로 넓어짐
  ④ 코가리개: 눈썹 가운데에서 두 눈 사이로 내려오는 판 — 좁게 시작해 아래로 조금 넓어지다 뾰족하게 끝남, 페이스플레이트보다 한 칸 앞
안: T1 짧은 코가리개(마스크 윗변까지) / T2 긴 코가리개(마스크 중간까지 덮음)
"""
import numpy as np

from flag_vox import box, cbox, rotx
import aero_r1 as A
import aero_faces as F
import aero_faces_p as P

HP = F.HEAD_PARTS


def helm_strip(M, long_nasal):
    # ② 능선 띠(정수리 판과 같은 피벗·숙임)
    F._slab(M, "H_HelmRidge", (-2, 2), (-16, 9), (264, 266), rotx(12), (0, -3, 263), 1, ch={"+zx": 1, "+z-y": 2})
    # ① 갈래 장식: 받침 + 두 갈래
    def fork(G):
        X, Y, Z = G; ax = np.abs(X)
        base = (ax <= 3) & (Y >= -7) & (Y <= -1) & (Z >= 266) & (Z <= 268)
        prong = (ax >= 2) & (ax <= 3) & (Y >= -5) & (Y <= -3) & (Z >= 266) & (Z <= 276) & (Z <= 276 - np.maximum(0, -Y - 4))
        return base | prong
    F._slab(M, "H_HelmFork", (-3, 3), (-7, -1), (266, 276), rotx(12), (0, -3, 263), 1, extra=fork)
    fk = M.parts["H_HelmFork"]; G = fk.g(); X, Y, Z = G
    fk.paint(Z <= 268, 3)                                                   # 받침은 짙게
    # ③ 이마 판: 위 좁고(능선 띠 폭) 아래가 방패꼴로 넓어짐, 위를 뒤로 14° 눕힘
    def brow_shield(G):
        X, Y, Z = G; ax = np.abs(X)
        return ax <= 2 + np.maximum(0, 259 - Z) * 0.5
    F._slab(M, "H_HelmBrow", (-5, 5), (-21, -17), (254, 263), rotx(-14), (0, -19, 256), 1, extra=brow_shield)
    # ④ 코가리개: 머리 파트 안 축 정렬(앞면 평평), 페이스플레이트(-22)보다 한 칸 앞(-23)
    p = M.parts["Head"]
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    tip = 243 if long_nasal else 247
    w = np.where(Z >= 251, 1.5, 1.5 + (251 - Z) * 0.375)                   # 눈 사이에서 좁게 → 아래로 조금 넓어짐
    w = np.minimum(w, (Z - tip) * 1.0 + 0.5)                                 # 끝은 45° 로 뾰족
    nasal = (ax <= w) & (Y >= -23) & (Y <= -20) & (Z >= tip) & (Z <= 255)
    p.add(nasal, 1)
    p.add(box(G, (-1, 1), (-20, -16), (251, 254)), 3)                      # 코가리개 뒤 받침(두 눈 사이 — 소켓 바닥과 이어 떠 있지 않게)


def build(kind="T1"):
    M = P.build("P2")
    helm_strip(M, long_nasal=(kind == "T2"))
    return M


def build_all():
    return build("T1")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["P2", "T1", "T2"]
    VIEWS = ((0, 4, ((-30, 30), (232, 292))), (30, 6, ((-32, 32), (232, 294))),
             (90, 2, ((-36, 36), (232, 294))), (150, 12, ((-32, 32), (234, 296))))
    rows = []
    for k in kinds:
        M = P.build("P2") if k == "P2" else build(k)
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
