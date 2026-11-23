"""
aero_colors2.py — Aero 색 배합 2차: 마스코트 느낌 빼기 (2026-10-26 18:19~)

유저: "근데 색상 때문인가 한화이글스 마스코트 같아.."
원인 측정 [aero_legs_d 정면 맨 앞 칸, 칸 수 기준]:
  - 전신 주황은 9.8% 뿐인데 머리 구역(z≥232)은 주황 25.6% — 주황이 머리에 몰림(볏·눈썹·깃·투구 띠·코가리개)
  - 정면 주황 칸이 가장 많은 파트: 날개(양옆으로 비어져 나온 뒤 판) > 정강이 > 어깨 > 발 > 머리 깃·눈썹
  [추측] "흰 몸 + 짙은 테 + 주황 머리(볏·눈썹 V·부리처럼 내려온 코가리개) + 주황 날개" = 주황·흰·검정 새 = 그 구단 마스코트.
         새 기체라 모양은 그대로 두고, 주황이 머리·날개에 몰리지 않게 하는 쪽으로 푼다.
톤다운(TD): 머리 주황 → 흰·밝은 회색(깃 끝만 강조색) · 코가리개 → 밝은 회색(주황 부리처럼 읽힘) · 눈썹 → 짙게(눈 발광이 더 뜸)
            · 날개 뒤 판 → 보조색, 위 끝만 강조색.
시안: T0 지금 그대로 / T1 흰·주황+TD / T2 건메탈·주황+TD / T3 흰·적·금+TD / T4 흰·청+TD
"""
import numpy as np

import aero_r1 as A
import aero_faces as F
import aero_colors as Cc
import aero_legs_d as D

MAIN, SUB, FRAME, ACC = 2, 10, 3, 1


def _tip(p, frac=0.72):
    """파트 피벗에서 가장 먼 쪽(끝) 칸 마스크."""
    ijk = np.argwhere(p.a > 0)
    d = np.linalg.norm(ijk + p.lo - np.array(p.pivot), axis=1)
    m = np.zeros(p.a.shape, bool)
    sel = ijk[d >= frac * d.max()]
    m[sel[:, 0], sel[:, 1], sel[:, 2]] = True
    return m


def tone_down(M):
    for n in ("H_CrownL", "H_CrownR", "H_HelmBrow"):
        if n in M.parts:
            q = M.parts[n]; q.paint(q.a == ACC, MAIN)
    if "H_HelmRidge" in M.parts:
        q = M.parts["H_HelmRidge"]; q.paint(q.a == ACC, SUB)
    for n in ("H_BrowL", "H_BrowR"):
        q = M.parts[n]; q.paint(q.a == ACC, FRAME)                         # 눈썹 짙게 — 눈 발광이 그늘 속에서 뜸
    h = M.parts["Head"]; G = h.g(); X, Y, Z = G
    h.paint(h.a == ACC, MAIN)
    h.paint((h.a == MAIN) & (Y <= -20) & (Z >= 243) & (Z <= 255) & (np.abs(X) <= 4), SUB)   # 코가리개(부리처럼 읽힘) → 밝은 회색
    for n in ("FinL", "FinR"):
        q = M.parts[n]; q.paint(q.a == ACC, MAIN); q.paint(_tip(q) & (q.a > 0), ACC)          # 깃은 흰, 끝만 강조색
    for n in ("WingL", "WingR"):
        q = M.parts[n]; G = q.g(); X, Y, Z = G
        q.paint(q.a == ACC, SUB)
        q.paint((q.a == SUB) & (Z >= 238) & (Y >= 36), ACC)                # 날개 위 끝만 강조색


def build(td=True):
    M = D.build()
    if td:
        tone_down(M)
    return M


build_all = build

S = Cc.SCHEMES
VARIANTS = [("T0 지금", "C1 흰·주황", False), ("T1 흰·주황+TD", "C1 흰·주황", True), ("T2 건메탈·주황+TD", "C5 건메탈·주황", True),
            ("T3 흰·적·금+TD", "C3 흰·적·금", True), ("T4 흰·청+TD", "C4 흰·청", True)]

if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    pick = sys.argv[2:]
    models = {False: build(False), True: build(True)}
    blocks = {k: m.blocks(pose=A.STANCE) for k, m in models.items()}
    rows = []
    for label, sch, td in VARIANTS:
        if pick and label.split()[0] not in pick:
            continue
        B = blocks[td]; pal = S[sch]
        ims = [vp.render(B, pal, A.EMISSIVE, yaw=y, pitch=p, ppc=1.9, ss=2, size=((-100, 100), (-10, 300)), ao_amt=0.5)
               for y, p in ((0, 4), (30, 6), (150, 12))]
        ims.append(vp.render(B, pal, A.EMISSIVE, yaw=24, pitch=6, ppc=4.2, ss=2, size=((-60, 60), (196, 286)), ao_amt=0.5))
        rows.append(vp.sheet(ims, ["%s  front" % label.split()[0], "3/4", "back 3/4", "bust"]))
        print(label, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    Sh = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        Sh.paste(r, (0, y)); y += r.height
    Sh.save(out)
    print("done", round(time.time() - t0, 1))
