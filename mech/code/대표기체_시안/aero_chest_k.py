"""
aero_chest_k.py — Aero 상체 1차: 카트 앞부분 같은 콕핏 가슴 (2026-10-26 13:18~)

유저: "잘됐다고 평가한 중장갑 기체의 콕핏 부분을 잘 보면 카트 바디 앞쪽과 꽤 형상이 유사해. 이런 느낌을 구현해줘. 다만 너무 툭 튀어나오진 않게"
+ 카트 앞모습 3장. 얼굴은 P1 로 마무리(유저 13:12).
카트 앞부분 형태 언어 [관찰] → 가슴에 옮긴 것:
  ① 가운데 노즈: 위에서 보면 V(가운데 능선이 가장 앞), 앞에서 보면 아래 끝이 뾰족, 윗면은 뒤로 눕는 후드
     → 중장갑 H1 의 "흉판 사이로 나온 콕핏 블록"과 같은 자리. 판 두 장을 돌려 맞대 면은 평평하게
  ② 노즈 위 캐노피: 짙은 판이 한 칸 들어간 자리(콕핏 덮개) — 가운데 하나
  ③ 양옆 사이드 포드: 노즈 뒤에서 바깥·뒤로 물러나는 각진 판, 앞 윗모서리 45° 후드, 위·아래 단 겹침
  ④ 포드 밑 흡기: 처마 그늘 속 짙은 함 + 깊은 곳 발광 한 줄
튀어나옴 제한: 노즈 앞끝이 포드 앞면보다 K1·K2 4칸 / K3 2칸(중장갑 H1 은 6칸).
안(v3): K1 중장갑 H1 짜임 그대로(육각 노즈) / K2 카트 노즈(아래 끝 뾰족, 흰 끝) / K3 K2 + 2단 포드(아랫단 흰 판 한 칸 뒤)
"""
import numpy as np

from flag_vox import box, cbox, poly, rotx, rotz
import aero_r1 as A
import aero_faces as F
import aero_faces_p as P

CHEST = []


def _part(M, name, lo, hi, pivot, rot, build):
    p = M.part(name, lo, hi, pivot=pivot, parent="Torso")
    build(p)
    p.rot = rot
    CHEST.append(name)
    return p


def chest(M, kind):
    """v3: 유저가 잘됐다고 한 중장갑 흉부 H1(안 1)의 짜임을 Aero 몸통 크기로 옮기고 카트 노즈 쪽으로 다듬음.
    v1·v2(판을 따로 만들어 돌려 붙임)는 납작한 상자 + 톱니 모서리로 보여 버림."""
    M.parts.pop("ChestPlate", None)
    CHEST.clear()
    t = M.parts["Torso"]
    G = t.g(); X, Y, Z = G; ax = np.abs(X)
    t.cut((ax <= 28) & (Y <= -12) & (Z >= 199) & (Z <= 241))                   # r1 가슴 앞쪽(흰 윗가슴·옆 판) 비움

    p = M.part("ChestNew", (-30, -32, 196), (31, 14, 244), pivot=(0, -20, 220), parent="Torso")
    CHEST.append("ChestNew")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    B = lambda m: np.broadcast_to(m, shp)
    # 흉판(사이드 포드): 앞면은 바깥으로 물러나는 얕은 V, 윗면은 깃에서 앞으로 약 30° 내려가는 후드, 아래 앞은 처마로 깎임
    # v4: 앞면 평평 + 바깥만 45°, 후드도 45° — v3 의 1:4 앞면·30° 후드는 큰 주황 면에 줄무늬(가이드 1-4)
    yf = -22.0 + np.clip(ax - 18.0, 0, None) * 1.0
    ztop = np.minimum(238.0, 238.0 - 1.0 * (-10.0 - Y)) - np.clip(ax - 21.0, 0, None) * 1.0
    zbot = 208.0 + np.clip(ax - 22.0, 0, None) * 1.0
    pec = (ax >= 1.5) & (ax <= 27) & (Y <= 12) & (Z <= ztop) & (Z >= zbot) & \
          (Y >= yf + np.clip(211.5 - Z, 0, None) * 1.0)
    p.add(B(pec), 1)
    if kind == "K3":     # 2단 포드: 아랫단(처마 위 6칸)은 한 칸 뒤로 물러난 흰 판 — 위 주황이 덮음
        low = pec & (Z <= 216)
        p.cut(B(low & (Y <= yf + np.clip(211.5 - Z, 0, None) * 1.0 + 0.5)))
        p.paint(B(low), 2)
        p.paint_s(B(pec & (np.abs(Z - 216.5) <= 0.5)), 3)
    # 처마 밑 흡기: 짙은 함 + 가로 살 + 깊은 곳 주황 빛(중장갑과 같은 방식, 한 줄)
    vent = (ax >= 9) & (ax <= 22) & (Z >= 201.5) & (Z <= 208) & (Y >= yf + 3.5) & (Y <= -14)
    p.add(B(vent), 4)
    sl = (ax >= 11) & (ax <= 20) & (Z >= 203.5) & (Z <= 205.5)
    p.cut(B(sl & (Y >= yf + 3.4) & (Y < yf + 6.5)))
    p.add(B(sl & (Y >= yf + 6.5) & (Y <= yf + 7.5)), 6)
    p.add(B(box(G, (-28, 28), (-20, 10), (206.0, 207.0)) & ~pec), 3)           # 흉판 밑 짙은 받침
    # 가운데 노즈(콕핏 블록): 흉판보다 4칸 앞(중장갑 6칸 — "너무 툭 튀어나오지 않게")
    if kind == "K1":     # 중장갑식 육각 앞면
        front = poly(G, "y", [(-0.6, 206), (5, 206), (8, 209), (8, 228), (5, 232), (-0.6, 232)], sym=True)
    else:                # 카트 노즈: 아래 끝이 뾰족(45°), 위는 후드를 따라 깃 밑으로 올라감
        front = poly(G, "y", [(-0.6, 203), (8, 211), (8, 228), (5, 232), (-0.6, 232)], sym=True)
    prow = B(front) & (Y >= -26 + ax * 0.5 + np.clip(210 - Z, 0, None) * 1.0) & (Y <= -10) & (Z <= ztop + 2.5)   # 흉판보다 4칸 앞, 위에서 1:2 V
    p.cut(B((ax < 1.5) & (Y < -10) & (Z > 208)))                                # 흉판·노즈 사이 틈
    p.add(B((ax < 1.5) & (Y >= -22) & (Y < -10) & (Z > 208) & (Z <= ztop)), 4)
    # 노즈 양옆 홈(2칸) — 노즈가 흉판에서 따로 떨어진 덩어리로 읽히게(v4 는 같은 주황끼리 붙어 노즈가 안 보임)
    groove = (ax > 8) & (ax <= 10) & (Z > 208) & (Z <= ztop)
    p.cut(B(groove & (Y <= -17)))
    p.add(B(groove & (Y >= -17) & (Y <= -16)), 4)
    p.add(prow, 1)
    p.paint_s(B(prow & (np.abs(Z - 214.5) <= 0.5)), 3)                          # 노즈 가로 이음선(형태 단차 대신 한 줄)
    if kind != "K1":
        p.paint(B(prow & (Z <= 208 + ax)), 2)                                    # 뾰족한 아래 끝 흰색(카트 앞 끝 색 바뀜)


def build(kind="K1"):
    M = P.build("P1")
    chest(M, kind)
    return M


def build_all():
    return build("K2")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["r1", "K1", "K2", "K3"]
    sch = A.SCHEMES["A"] | {10: (186, 188, 190), 8: (164, 78, 26)}
    UP = {"Torso", "Pelvis", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "Backpack", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR"}
    rows = []
    for k in kinds:
        M = P.build("P1") if k == "r1" else build(k)
        keep = UP | set(F.HEAD_PARTS) | set(CHEST if k != "r1" else ["ChestPlate"])
        Bc = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        Bf = M.blocks(pose=A.STANCE)
        ims = [vp.render(Bc, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=5, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in ((0, 4, ((-64, 64), (180, 290))), (30, 8, ((-66, 66), (180, 292))), (90, 2, ((-60, 60), (180, 292))))]
        ims.append(vp.render(Bf, sch, A.EMISSIVE, yaw=30, pitch=6, ppc=1.7, ss=2, size=((-110, 110), (-10, 320)), ao_amt=0.5))
        rows.append(vp.sheet(ims, ["%s  front" % ("r1 (P1 face)" if k == "r1" else k), "3/4", "side", "full 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
