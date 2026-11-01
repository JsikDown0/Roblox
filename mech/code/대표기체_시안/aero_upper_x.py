"""
aero_upper_x.py — Aero 상체 3차: 카트 + 메카 레퍼런스 공통점 (2026-10-26 13:42~)

유저: "Aero 상체 리메이크중이야. 레퍼런스들의 공통점을 분석하고 이를 바탕으로 유사한 느낌의 상체를 만들어줘."
레퍼런스 = 카트 앞모습 3장(주황·청·적) + 메카 4장(적백 · 청백 흉상 · 주황회 · 짙은 청 흉상).

공통점 [관찰] → 이 파일에서 쓰는 법
 C1 위가 넓고 아래 가운데 한 점으로 모이는 방패꼴 가슴(카트 노즈 / 메카 흉판 아래 V)
    → 주황 셸: 아래 변 = 가운데 45° 후 바깥 1:2(갈매기 날개 V), 위 변은 바깥으로 올라감
 C2 강조선은 판 윤곽을 '안쪽으로 몇 칸 들어와서' 평행하게 따라감(카트 흰 줄 / 메카 V 발광)
    → 셸 아래 변에서 3칸 위에 같은 V 로 판 홈 + 홈 바닥에 발광(겉면 띠 아님 — 가이드 1-3)
 C3 가운데 세로 요소가 앞으로 나옴(카트 노즈콘 + 흰 끝 / 메카 가운데 세로 슬릿)
    → 가운데 노즈(셸보다 3칸 앞, 아래 끝 45° 뾰족, 끝은 흰색, 양옆 짙은 홈). 발광 V 의 가운데를 가림 = 웃는 입 방지
 C4 겹침: 주색 판 밑에 흰 판이 한 단 물러나 V 를 한 번 더 그림(카트 흰 쐐기)
    → 셸 아래 변 밑 흰 아랫단(2칸 뒤, 3칸 노출)
 C5 색: 주색 큰 판 + 흰 + 짙은 틈, 뜨거운 강조는 가운데 작게 / 허리는 짙고 가늚
 C6 옆으로 물러나는 포드·뒤로 젖힌 지느러미(카트 사이드포드 45° 후드 / 메카 어깨 날개)
    → 어깨 = 후드 45° 주황 포드 + 한 단 물러난 흰 아랫단 + 뒤·위로 젖힌 얇은 지느러미
 C7 머리 둘레를 낮은 깃이 V 로 감쌈(메카 흉상 2장)
    → 목 둘레 흰 V 깃(턱보다 낮게)

안: X1 기본 / X2 = X1 + 노즈 세로 슬릿 발광 + 어깨 흡기 발광(짙은 청 흉상식, 발광 많음)
    X3 = X1 색 뒤집기(흰 셸 + 주황 노즈·아랫단 — 메카 레퍼런스식 흰 몸 + 가운데 강조색)
얼굴 = P1. 팔뚝·등(바인더)·다리·골반·날개 = 상체 2차(aero_upper_v) 그대로.
"""
import numpy as np

from flag_vox import box, cbox, poly, cyl, ell, rotx, roty, rotz
import aero_r1 as A
import aero_faces as F
import aero_faces_p as P
import aero_upper_v as U

UPPER = []
FOLD = 14                   # 셸 반쪽 접힘(위에서 본 V)


def _B(G):
    X, Y, Z = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    return lambda m: np.broadcast_to(m, shp)


def _zb(X):
    """셸 아래 변: 가운데 202 에서 45° → X 12 부터 1:2 (갈매기 날개 V)"""
    return np.where(X <= 12, 202 + X, 214 + 0.5 * (X - 12))


def _zt(X):
    """셸 위 변: 목 홈(가운데 224 → X 8 에서 234) 뒤 바깥으로 1:2 상승"""
    return np.where(X <= 8, 224 + 1.25 * X, 234 + 0.5 * (X - 8))


# ------------------------------------------------------------------ 몸통 속 + 짙은 허리 + 깃
def torso(M, kind):
    old = M.parts["Torso"]
    t = M.part("Torso", (-34, -22, 174), (35, 26, 250), pivot=old.pivot, parent=old.parent)
    G = t.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    # 허리: 짙고 가늚(반폭 10), 배 판 2단(짙은 회색, 위가 아래를 덮음)
    t.add(cbox(G, (-10, 10), (-10, 11), (176, 206), {"xy": 3}), 3)
    t.add(cbox(G, (-8, 8), (-14, -9), (180, 189), {"xy": 2, "-z-y": (3, 3)}), 4)
    t.add(cbox(G, (-9, 9), (-16, -9), (188, 198), {"xy": 2, "-z-y": (3, 3)}), 3)
    # V 몸통 속(프레임): 반폭 10 → z 204 부터 45° 로 벌어져 z 222 에서 28
    w = 10 + np.clip(Z - 204, 0, 18)
    core = (ax <= w) & cbox(G, (-28, 28), (-18, 16), (200, 240), {"x-y": 4, "x+y": 4, "+zx": 4})
    t.add(B(core), 3)
    t.add(cbox(G, (-33, 33), (-11, 13), (226, 238), {"+zx": 6, "xy": 3}), 3)                # 어깨 다리
    t.add(cbox(G, (-20, 20), (16, 22), (202, 238), {"xy": 3}), 3)                           # 등판(백팩 붙는 면)
    # C7 목 둘레 V 깃: 목 양옆에서 바깥으로 45° 내려가는 흰 판(턱 240 보다 낮게, 앞이 셸 위 변에 걸침)
    for s in (1, -1):
        xr = tuple(sorted((s * 7, s * 20)))
        col = cbox(G, xr, (-17, 8), (232, 244), {("+z+x" if s > 0 else "+z-x"): (9, 9), "x-y": 3, "+z-y": 3})
        t.add(col, 2)
        t.paint(col & (Y >= 4), 3)                                                          # 뒤쪽은 짙게
    t.add(cyl(G, "z", (0, -2), 6, (232, 242)), 3)                                           # 목


# ------------------------------------------------------------------ C1·C2·C4 셸 반쪽(접어서 V)
def shell(M, kind):
    p = M.part("ChestL", (-1, -30, 190), (32, -12, 248), pivot=(0, -22, 214), parent="Torso")
    G = p.g(); X, Y, Z = G; B = _B(G)
    xin = X >= 0
    zb, zt = _zb(X), _zt(X)
    outer = X <= 25 - np.clip(Z - 237, 0, None)                                              # 바깥 위 모서리 45°
    sh = xin & outer & (Z >= zb) & (Z <= zt) & (Y >= -24) & (Y <= -20)
    c_shell, c_under = (2, 1) if kind == "X3" else (1, 2)
    p.add(B(sh), c_shell)
    # 셸 앞 아래 모서리 한 칸 모따기(처마 느낌)
    p.cut(B(xin & (Y == -24) & (Z <= zb) & (Z >= zb - 1)))
    # C2 V 홈: 아래 변에서 3칸 위, 같은 V 로 평행 · 깊이 2 · 홈 바닥 가운데 두 줄 발광
    gz = Z - zb
    groove = xin & (X >= 3) & (X <= 22) & (gz >= 3) & (gz <= 6) & sh
    p.cut(B(groove & (Y <= -23)))                                                           # 깊이 2(3 이면 비스듬히 볼 때 바깥 발광이 가려져 검은 눈썹처럼 보임)
    p.add(B(groove & (Y == -22)), 4)
    p.paint(B(groove & (Y == -22) & (gz <= 5.5)), 6)                                        # 홈 바닥 전체 발광, 맨 윗줄만 짙은 턱
    # C4 흰 아랫단: 셸 아래 변 밑으로 4칸, 2칸 뒤(셸 밑 그늘이 생김)
    under = xin & (X <= 24) & (Z >= zb - 4) & (Z < zb) & (Y >= -22) & (Y <= -18)
    p.add(B(under), c_under)
    p.add(B(xin & (X <= 23) & (Z >= zb - 7) & (Z < zb - 4) & (Y >= -20) & (Y <= -17)), 3)   # 그 밑 짙은 받침
    p.rot = rotz(FOLD)
    M.mirror("ChestL", "ChestR", "Torso")
    UPPER.extend(["ChestL", "ChestR"])


# ------------------------------------------------------------------ C3 가운데 노즈(카트 노즈콘)
def keel(M, kind):
    k = M.part("ChestKeel", (-7, -31, 192), (8, -18, 236), pivot=(0, -24, 214), parent="Torso")
    G = k.g(); X, Y, Z = G; ax = np.abs(X); B = _B(G)
    # 노즈: 반폭 4, 셸보다 3칸 앞(y -27), 아래 끝 45° 뾰족(z 196), 윗면 뒤로 눕는 후드
    nose = (ax <= 4) & (Z >= 196 + ax * 1.0) & (Z <= 232) & (Y >= -27) & (Y <= -22)
    nose &= ~((Y <= -26) & (Z >= 228))                                                       # 위 앞 모서리 후드
    nose &= ~((Y <= -27) & (Z >= 224))
    c_nose, c_tip = (1, 2) if kind == "X3" else (1, 2)
    k.add(B(nose), c_nose)
    k.paint(B(nose & (Z <= 206)), c_tip)                                                    # 노즈 끝 흰색(카트 노즈 끝)
    k.groove(B(nose & (np.abs(Z - 216) <= 0.5) & (Y <= -26)), 4)                            # 가로 이음선 한 줄
    # 양옆 짙은 홈: 노즈와 셸 사이 1칸 틈 뒤 받침
    k.add(B((ax >= 4) & (ax <= 6) & (Z >= 200) & (Z <= 230) & (Y >= -22) & (Y <= -19)), 4)
    if kind == "X2":                                                                        # 짙은 청 흉상식 가운데 세로 슬릿 발광
        sl = (ax <= 0.5) & (Z >= 209) & (Z <= 225) & (Y <= -26)
        k.cut(B(sl))
        k.add(B((ax <= 0.5) & (Z >= 209) & (Z <= 225) & (Y == -25)), 6)
    UPPER.append("ChestKeel")


# ------------------------------------------------------------------ C6 어깨 = 사이드 포드
def shoulder(M, kind):
    sh = M.part("ShoulderL", (26, -24, 196), (62, 40, 262), pivot=A.SHOULDER, parent="Torso")
    G = sh.g(); X, Y, Z = G; B = _B(G)
    sh.add(cbox(G, (33, 42), (-11, 11), (208, 234), {"xy": 3}), 3)                          # 안쪽 받침
    # 주황 포드: 위 바깥 45° 후드(크게) · 앞 위 45° · 앞 아래 살짝 뒤로
    pod = cbox(G, (37, 53), (-14, 14), (213, 240), {"+z+x": (9, 9), "+z-y": (8, 8), "-z-y": (4, 4), "x+y": 3, "-z+x": (6, 6), "+x-y": 4})
    sh.add(B(pod), 1)
    # 흰 아랫단: 2칸 안쪽·2칸 뒤로 물러나 포드 밑에 그늘(카트 사이드포드 아래 흰 판)
    low = cbox(G, (39, 50), (-11, 11), (203, 214), {"-z+x": (4, 4), "x-y": 3})
    sh.add(B(low), 2)
    # 앞면 흡기: 짙은 함(처마 그늘 속), X2 는 깊은 곳에 발광 한 줄
    if kind == "X2":                                                                        # 발광 없는 검은 함은 손잡이 구멍처럼 보여 X2 에만
        intake = (X >= 41) & (X <= 51) & (Z >= 215) & (Z <= 220) & (Y <= -13)
        sh.cut(B(intake & (Y <= -14)))
        sh.add(B(intake & (Y == -13)), 4)
        sh.paint(B(intake & (Y == -13) & (Z >= 216) & (Z <= 218) & (X >= 43) & (X <= 49)), 6)
    # 뒤·위로 젖힌 얇은 지느러미(포드 뒤 위에서 45° 로 솟음, 두께 3)
    fin = poly(G, "x", [(6, 232), (16, 232), (32, 240), (37, 245), (29, 245), (14, 239), (6, 239)], rng=(43, 47))
    sh.add(B(fin), 1)
    sh.paint(B(fin & (Y <= 14)), 3)                                                          # 뿌리는 짙게(포드에서 따로 떨어져 보이게)
    sh.rot = roty(-8)
    M.mirror("ShoulderL", "ShoulderR", "Torso")


def upper(M, kind="X1"):
    UPPER.clear()
    M.parts.pop("ChestPlate", None)
    torso(M, kind)
    shell(M, kind)
    keel(M, kind)
    shoulder(M, kind)
    U.forearm(M)
    U.UPPER.clear()
    U.back(M)
    UPPER.extend(U.UPPER)


def build(kind="X1"):
    M = P.build("P1")
    upper(M, kind)
    return M


def build_all():
    return build("X1")


# ------------------------------------------------------------------ 정면 색 면적(직교, 맨 앞 칸)
def front_area(M, pose=None, yaw=0):
    """정면(-Y 쪽)에서 본 맨 앞 칸 색 비율. 회전 파트는 칸 중심을 월드로 옮겨 계산(근사)."""
    best = {}
    for name, p in M.parts.items():
        T = M.world(name, pose)
        ijk = np.argwhere(p.a > 0)
        if len(ijk) == 0:
            continue
        c = p.a[ijk[:, 0], ijk[:, 1], ijk[:, 2]]
        P_ = (ijk + p.lo).astype(float)
        W = P_ @ T[:3, :3].T + T[:3, 3]
        key = np.round(W[:, 0]).astype(int) * 100000 + np.round(W[:, 2]).astype(int)
        y = W[:, 1]
        order = np.lexsort((y, key))
        k_s = key[order]
        first = np.ones(len(k_s), bool); first[1:] = k_s[1:] != k_s[:-1]
        for kk, yy, cc in zip(k_s[first], y[order][first], c[order][first]):
            if kk not in best or yy < best[kk][0]:
                best[kk] = (yy, cc)
    cols = np.array([v[1] for v in best.values()])
    n = len(cols)
    return {int(k): round(100 * (cols == k).sum() / n, 2) for k in np.unique(cols)}


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["U1", "X1", "X2", "X3"]
    sch = A.SCHEMES["A"] | {10: (186, 188, 190), 8: (164, 78, 26)}
    UP = {"Torso", "Pelvis", "ShoulderL", "ShoulderR", "UpperArmL", "UpperArmR", "LowerArmL", "LowerArmR",
          "Backpack", "SkirtFL", "SkirtFR", "SkirtSL", "SkirtSR"}
    rows = []
    for k in kinds:
        if k.startswith("U"):
            M = U.build(k); extra = set(U.UPPER)
        else:
            M = build(k); extra = set(UPPER)
        keep = UP | set(F.HEAD_PARTS) | extra | {"ChestPlate", "ChestNew"}
        Bc = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        Bf = M.blocks(pose=A.STANCE)
        ims = [vp.render(Bc, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=4, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in ((0, 4, ((-70, 70), (150, 292))), (30, 8, ((-72, 72), (150, 294))),
                                (90, 2, ((-66, 66), (150, 294))), (150, 12, ((-72, 72), (150, 296))))]
        ims.append(vp.render(Bf, sch, A.EMISSIVE, yaw=30, pitch=6, ppc=1.5, ss=2, size=((-110, 110), (-10, 320)), ao_amt=0.5))
        fa = front_area(M, A.STANCE)
        rows.append(vp.sheet(ims, ["%s  front  (glow %.1f%%  orange %.0f%%  white %.0f%%  dark %.0f%%)" % (
            k, fa.get(6, 0), fa.get(1, 0), fa.get(2, 0), fa.get(3, 0) + fa.get(4, 0)), "3/4", "side", "back 3/4", "full 3/4"]))
        print(k, fa, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
