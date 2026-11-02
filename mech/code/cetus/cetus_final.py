"""HT-02 CETUS — 최종 조립 + 최적화 (2026-11-02)

확정본 = r12(부스터 + 하체 뒤판) + 가슴 4v(코어 없음, 세로 홈 2줄 = 궁극기 줄, 색 10).
최적화 [스타일 가이드: 파트당 삼각형 1만 미만 · 섬 0]:
1. 섬 잇기: 작은 섬을 가장 가까운 본체 칸까지 같은 색 1칸 굵기 다리로 이음(지우지 않음).
2. 파트 나누기(게임에서도 쓸모 있는 자리로):
   DrillR(나선 드릴 — 궁극기 회전) · ClawL(주먹·포신·집게 — 시그니처 발사/오므림) · BoosterMain(허리 뒤 노즐 — 불꽃 붙일 자리)
   KneeL/R(무릎 방패) · Collar(목깃·코르셋·목 보호대) · ShoulderL/R 아랫부분(ShoulderBaseL/R).
3. 관절 계층: Pelvis(뿌리) → Torso → Head·Shoulder·UpperArm·Back … / Pelvis → UpperLeg → LowerLeg → Foot.
출력: cetus_final.json(flag_vox/1, PC 내보내기용) · 검사 결과 · 색 면적.
"""
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
import cetus_r12 as r12  # noqa: E402
import cetus_chest as ch  # noqa: E402
from check_model import greedy_quads  # noqa: E402

PAL, EMISSIVE, METAL = ch.PAL, ch.EMISSIVE, ch.METAL
PAL_ULT, EMISSIVE_ULT = ch.PAL_ULT, ch.EMISSIVE_ULT
COLOR_NAMES = {1: "청록 주장갑", 2: "뼈색", 3: "짙은 쇠", 4: "검정 홈", 5: "황동(금속)", 6: "발광", 7: "강철",
               8: "궁극기 유리(드릴)", 9: "밧줄", 10: "궁극기 줄(가슴)"}


def tris(p):
    return 2 * greedy_quads(p.a)


def bridge_islands(p, max_cells=400):
    """본체(가장 큰 덩어리)가 아닌 작은 섬을 가장 가까운 본체 칸까지 직선 다리(같은 색)로 잇는다."""
    lab, k = ndimage.label(p.a > 0)
    if k <= 1:
        return 0
    sizes = np.bincount(lab.ravel())[1:]
    main = int(np.argmax(sizes)) + 1
    main_pts = np.argwhere(lab == main)
    n = 0
    for i in range(1, k + 1):
        if i == main or sizes[i - 1] > max_cells:
            continue
        pts = np.argwhere(lab == i)
        c = int(np.bincount(p.a[lab == i]).argmax())
        # 가장 가까운 한 쌍(섬 쪽은 몇 점만 표본)
        sample = pts[:: max(1, len(pts) // 40)]
        d2 = ((sample[:, None, :] - main_pts[None, ::7, :]) ** 2).sum(-1)
        a_i, b_i = np.unravel_index(np.argmin(d2), d2.shape)
        a, b = sample[a_i].astype(float), main_pts[::7][b_i].astype(float)
        L = int(np.ceil(np.abs(b - a).max())) + 1
        for t in np.linspace(0, 1, L * 2):
            q = np.round(a + (b - a) * t).astype(int)
            if p.a[tuple(q)] == 0:
                p.a[tuple(q)] = c
        n += 1
    return n


def split(M, src, dst, mask_fn, pivot=None, parent=None):
    """src 파트에서 mask_fn(G) 칸을 떼어 새 파트 dst 로. 피벗 기본 = src 피벗, 부모 기본 = src."""
    p = M.parts[src]
    G = p.g()
    m = np.broadcast_to(mask_fn(G), p.a.shape) & (p.a > 0)
    q = M.part(dst, tuple(p.lo), tuple(p.hi), pivot or p.pivot, parent or src)
    q.a[m] = p.a[m]
    p.a[m] = 0
    p.trim(); q.trim()
    return q


def mirror_split(M, srcL, dstL, mask_fn, pivot=None):
    split(M, srcL, dstL, mask_fn, pivot)
    srcR, dstR = srcL[:-1] + "R", dstL[:-1] + "R"
    M.mirror(dstL, dstR, srcR)
    M.mirror(srcL, srcR, M.parts[srcR].parent)


def build_all():
    M = r12.build_all(True)
    ch.chest_4(M, "v")
    for p in M.parts.values():
        p.trim()
    # 관절 계층 정리
    M.parts["Torso"].parent = "Pelvis"
    # 1) 섬 잇기
    for n in ("ShoulderL", "LowerArmL"):
        bridge_islands(M.parts[n])
    M.mirror("ShoulderL", "ShoulderR", "Torso") if False else None     # 어깨는 좌우 비대칭이라 거울 안 함
    # 2) 나누기
    dx = r12.SHIN_X
    split(M, "LowerArmR", "DrillR", lambda G: G[2] <= 125, pivot=(fv_cx(), 0, 125))
    split(M, "LowerArmL", "ClawL", lambda G: G[2] <= 151, pivot=(56, 0, 145))
    split(M, "Pelvis", "BoosterMain", lambda G: G[1] >= 23, pivot=(0, 30, 150))
    knee = lambda G: (G[2] >= 87) & (G[1] <= -5)
    split(M, "LowerLegL", "KneeL", knee, pivot=(dx, -20, 100))
    split(M, "LowerLegR", "KneeR", lambda G: (G[2] >= 87) & (G[1] <= -5), pivot=(-dx, -20, 100))
    split(M, "Torso", "Collar", lambda G: G[2] >= 216, pivot=(0, 0, 220))
    for s in ("L", "R"):
        split(M, "Shoulder" + s, "ShoulderBase" + s, lambda G: G[2] <= 206)
    return M


def fv_cx():
    import cetus_r6 as r6
    return r6.DRILL_X


def report(M):
    bad = []
    rows = []
    tot = 0
    for n, p in M.parts.items():
        t = tris(p); tot += t
        _, k = ndimage.label(p.a > 0)
        flag = ("  ⚠삼각형" if t >= 10000 else "") + ("  ⚠섬 %d" % (k - 1) if k > 1 else "")
        if flag:
            bad.append(n)
        rows.append("%-13s cells %7d  tris %6d  부모 %-10s%s" % (n, p.count(), t, p.parent, flag))
    print("\n".join(rows))
    print("파트 %d · 총 삼각형 %d · %s" % (len(M.parts), tot, "OK" if not bad else "고칠 것 %s" % bad))
    return tot, bad


def color_area(M, yaw):
    """정사영 화면에서 색별 면적 비율(%)."""
    import vox_preview as vp
    pal = {c: (c, 0, 0) for c in range(1, 11)}
    im = np.asarray(vp.render(M.blocks(), pal, (), yaw=yaw, pitch=0, ppc=1.0, ss=1, ao_amt=0, shadow=False, outline=False, bloom=0)).astype(int)
    return im


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    M = build_all()
    report(M)
    M.save(os.path.join(out, "cetus_final.json"))
    print("저장:", os.path.join(out, "cetus_final.json"))
