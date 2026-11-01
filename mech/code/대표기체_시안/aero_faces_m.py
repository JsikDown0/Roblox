"""
aero_faces_m.py — Aero 얼굴 5차: F2 에서 다시(유저 10-26 12:50 "가운데 시안에서 다시. 눈을 좀 키우고 마스크 형태를 레퍼런스에서 공통점을 찾아서")

레퍼런스(유저 제공 주황 기체 3장 · 흰/주황 기체 설정화 앞뒤 · 마인크래프트 타임랩스 머리) 마스크 공통점 [관찰]:
  T1 눈 아래 얼굴은 투구보다 좁고, 아래로 갈수록 좁아져 턱 끝이 좁다(역사다리꼴·V)
  T2 가운데에 세로 요소 하나(판·홈·능선)가 있고, 양옆과 색이나 깊이가 다르다
  T3 마스크 양옆을 볼·턱 판이 한 단 뒤로 물러나 감싼다 → 마스크와 볼 사이 그늘 틈
  T4 턱 끝에 작은 블록이 따로 있다(강조색인 경우가 많다)
  T5 마스크 윗변이 눈 소켓의 아랫변 — 눈이 눈썹과 마스크 사이에 끼인다
마스크 3안(공통점을 다르게 조합): M1 흰 판 + 가운데 짙은 세로 홈 / M2 짙은 가운데 판 + 흰 턱 날개 / M3 2단 주둥이 + 능선
공통: F2(볼 판에서 뒤로 눕힌 깃 · V 눈썹 · 지붕형 정수리) + 큰 눈(안쪽 2칸 → 바깥 5칸, 윗변이 눈썹 따라 올라감).
마스크는 머리 파트 안에 축 정렬로(앞면 평평, V 는 윤곽으로만 — 1:2 쐐기면 = 줄무늬 · 판 b·v2 교훈).
"""
import numpy as np

from flag_vox import box, cbox
import aero_r1 as A
import aero_faces as F

HP = F.HEAD_PARTS


def big_eyes(p):
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    p.cut(box(G, (-9, 9), (-18, -17), (246, 256)))                     # F 의 가는 눈(-17) 걷어 냄
    p.add(box(G, (-9, 9), (-16, -15), (247, 256)), 4)                  # 소켓 바닥(검정)
    eye = (ax >= 2) & (ax <= 8) & (Z >= 250) & (Z <= 250.5 + 0.34 * (ax - 2))
    p.add(eye & (Y >= -17) & (Y <= -17), 6)                            # 안쪽 1칸 → 바깥 3칸 사다리꼴(F 의 1칸 선보다 크게, v1 의 5칸은 만화 눈)


def mask(p, kind):
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    # T3: 마스크 뒤·옆 짙은 턱 뼈대(볼 판과 마스크 사이 그늘 틈이 됨)
    p.add(cbox(G, (-9, 9), (-17, -12), (239, 249), {"x-y": 2}) & (ax <= 9 - 0.5 * np.maximum(0, 245 - Z)), 3)
    if kind == "M1":     # 흰 판(아래로 45° 로 모임) + 가운데 짙은 세로 홈 + 주황 턱 블록
        plate = (ax <= 7 - np.maximum(0, 246 - Z)) & (Y >= -20) & (Y <= -17) & (Z >= 240) & (Z <= 249)
        p.add(plate, 2)
        p.cut(plate & (ax <= 0) & (Y <= -20) & (Z >= 244) & (Z <= 248))                  # 1칸 폭 이음 홈(넓으면 입이 됨 · v1)
        p.add((ax <= 0) & (Y >= -19) & (Y <= -19) & (Z >= 244) & (Z <= 248), 4)
        p.add(cbox(G, (-2, 2), (-21, -17), (238, 241), {"-z-y": 1}), 2)                     # 턱 블록(주황이면 혀처럼 읽힘 · v1)
    elif kind == "M2":   # 짙은 가운데 판(위 넓고 아래 좁게, 한 칸 앞) + 그 뒤 양옆 흰 턱 날개가 아래로 모여 감쌈
        jaw = (ax >= 3) & (ax <= 9) & (Y >= -19) & (Y <= -16) & (Z >= 240) & (Z <= 248) & (Z >= 240 + 0.5 * (ax - 3))
        p.add(jaw, 2)
        p.add((ax <= 3) & (Y >= -19) & (Y <= -16) & (Z >= 238) & (Z <= 240), 2)          # 흰 턱(가운데 판 밑)
        center = (ax <= 4 - 0.5 * np.maximum(0, 246 - Z)) & (Y >= -21) & (Y <= -18) & (Z >= 241) & (Z <= 249)
        p.add(center, 7)                                                                   # 중간 회색(검정에 가까우면 벌린 입 · v1)
        p.add((ax <= 0) & (Y >= -21) & (Y <= -21) & (Z >= 243) & (Z <= 248), 3)            # 가운데 판의 세로 이음선
    elif kind == "M3":   # 2단 주둥이: 넓은 윗단 + 한 단 앞으로 나온 좁은 아랫단 + 능선 + 주황 턱
        up = (ax <= 8 - 0.5 * np.maximum(0, 248 - Z)) & (Y >= -19) & (Y <= -16) & (Z >= 245) & (Z <= 249)
        p.add(up, 2)
        lo = (ax <= 5 - 0.5 * np.maximum(0, 244 - Z)) & (Y >= -22) & (Y <= -17) & (Z >= 240) & (Z <= 245)
        p.add(lo, 2)
        p.add((ax <= 1) & (Y >= -23) & (Y <= -23) & (Z >= 241) & (Z <= 245), 2)           # 아랫단 가운데 능선
        p.add((ax <= 6) & (Y >= -19) & (Y <= -19) & (Z >= 244) & (Z <= 244), 4)           # 두 단 사이 그늘 줄
        p.add(cbox(G, (-2, 2), (-22, -18), (238, 240), {"-z-y": 1}), 2)


def build(kind="M1"):
    M = A.build_all()
    p = F.head_core(M, "slant")
    big_eyes(p)
    F.head_plates(M, brow_deep=False)
    for n in ("H_MaskL", "H_MaskR", "H_MaskRidge"):                     # F 의 V 주둥이 판은 빼고 새 마스크로
        M.parts.pop(n, None)
        if n in HP:
            HP.remove(n)
    mask(p, kind)
    F.fins(M, "F2")
    return M


def build_all():
    return build("M1")


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    kinds = sys.argv[2:] or ["F2", "M1", "M2", "M3"]
    VIEWS = ((0, 4, ((-30, 30), (232, 292))), (30, 6, ((-32, 32), (232, 294))),
             (90, 2, ((-36, 36), (232, 294))), (150, 12, ((-32, 32), (234, 296))))
    rows = []
    for k in kinds:
        M = F.build("F2") if k == "F2" else build(k)
        keep = set(HP) | {"Torso"}
        B = M.blocks(pose=A.STANCE, skip=[n for n in M.parts if n not in keep])
        ims = [vp.render(B, A.SCHEMES["A"], A.EMISSIVE, yaw=y, pitch=p, ppc=9, ss=2, size=sz, ao_amt=0.5) for y, p, sz in VIEWS]
        rows.append(vp.sheet(ims, ["%s  front" % k, "3/4", "side", "back 3/4"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
