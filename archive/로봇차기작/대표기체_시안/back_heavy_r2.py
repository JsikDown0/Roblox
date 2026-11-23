"""
back_heavy.py — 중장갑 r2 최종본(M2b) 손보기 (2026-10-26 01:50~)

유저 요청:
  ① 떠 있는 조각(섬) 정리 → waist_v1.waist_W2 에 3단 배 판 뒤 짙은 연결 칸을 넣음(앞에선 안 보임).
  ② 스커트가 다리를 파고듦: 옆 스커트가 정면에서 \\ / (아래가 안쪽)로 기울어 허벅지 속으로 들어감 → / \\ (八) 또는 수직.
     [실측] flag_vox 의 roty(+a) 는 왼쪽(+X) 파트의 '아래'를 안쪽으로 보낸다 → 옛 roty(14) 가 거꾸로였다.
     앞 스커트도 같은 꼴: rotx(+12) 가 아래를 뒤(허벅지 쪽)로 보냄 → rotx(-) 로 아래가 앞으로 벌어지게.
  ③ 백팩 새로: 레퍼런스(남색 중장갑 프라모델 — 뒤로 향한 원형 노즐 4개(2×2) + 위로 솟은 빔사벨 랙 2개 + 가운데 위 블록)
     를 우리 양식으로. 랙 = 빔사벨 꽂는 자리(꼭대기에 칼자루가 나와 있음 — 손이 어깨 위로 뽑는 위치).
     라이플은 랙·노즐을 막지 않게 허리 뒤(골반 뒤 스커트)에 가로로 거는 것을 전제로 백팩 아래를 비워 둠(z 186 위로만).
     BP1 = 레퍼런스처럼 곧게 선 V 랙(꼭대기 ≈ 뿔 높이)
     BP2 = 랙을 머리 뿔과 같은 방향으로 뒤로 눕힘(우리 기체만의 형태, 앞에서 '귀'로 덜 읽힘)
"""
import numpy as np

import flagship_heavy as fh
import flag_vox as fv
from flag_vox import box, cbox, cyl, poly
import legs_mix as lm

F = np.diag([-1.0, 1, 1])
# 스커트: (옆 roty, 옆 바깥 이동, 앞 rotx). 이동은 다리와 겹침 0 이 되는 최소값 [실측: overlap 검사]
SKIRT_MODES = {"cur": None, "8": (-14, 2, -12), "V": (0, 8, -4)}
# 수직(V)은 옆 스커트 안쪽 짙은 받침 층(|x|<38)을 빼고 8 바깥으로 — 12 를 옮기면 팔(STANCE)과 2,600칸 겹침 [실측]


def _setrot(M, n, R):
    M.parts[n].rot = R
    M.parts[n[:-1] + "R"].rot = F @ R @ F


def _shift(M, n, dx):
    for nm, sg in ((n, 1), (n[:-1] + "R", -1)):
        p = M.parts[nm]
        p.lo = p.lo + np.array([sg * dx, 0, 0])
        p.hi = p.hi + np.array([sg * dx, 0, 0])
        p.pivot = (p.pivot[0] + sg * dx, p.pivot[1], p.pivot[2])


def fix_skirts(M, mode):
    if SKIRT_MODES.get(mode) is None:
        return
    side_a, dx, front_a = SKIRT_MODES[mode]
    if mode == "V":
        for n in ("SkirtSL", "SkirtSR"):
            p = M.parts[n]
            p.cut(np.broadcast_to(np.abs(p.g()[0]) < 38, p.a.shape))
    _setrot(M, "SkirtSL", fv.roty(side_a))
    _shift(M, "SkirtSL", dx)
    _setrot(M, "SkirtFL", fv.rotx(front_a))
    # 옆 스커트를 바깥으로 옮기면 골반과 사이가 떠 보임 → 골반 옆에 짙은 경첩 받침(허벅지 위 z160~171, 허벅지와 안 닿음)
    p = M.parts["Pelvis"]
    out = 37 + dx
    _grow(p, (-out - 1, p.lo[1], p.lo[2]), (out + 2, p.hi[1], p.hi[2]))
    G = p.g()
    for sg in (1, -1):
        p.add(cbox(G, (sg * 28, sg * out), (-9, 9), (160, 171), {"xy": (3, 3), "-zx": (2, 2)}), 3)


def _grow(p, lo, hi):
    lo = np.minimum(p.lo, lo); hi = np.maximum(p.hi, hi)
    a = np.zeros(tuple(hi - lo), np.uint8)
    o = p.lo - lo
    a[o[0]:o[0] + p.a.shape[0], o[1]:o[1] + p.a.shape[1], o[2]:o[2] + p.a.shape[2]] = p.a
    p.a, p.lo, p.hi = a, np.array(lo), np.array(hi)


# ------------------------------------------------------------------ 백팩
RACK = {  # 꼭대기 z(칼자루 아래), 바깥 기울기(도), 뒤로 눕힘(도)
    "BP1": dict(top=272, out=9, back=6),
    "BP2": dict(top=262, out=7, back=28),
}


def build_backpack(M, variant="BP1"):
    del M.parts["Backpack"]
    b = M.part("Backpack", (-40, 22, 182), (41, 64, 260), pivot=(0, 28, 212), parent="Torso")
    G = b.g(); X, Y, Z = G; ax = np.abs(X)
    # 몸통: 짙은 큰 덩어리, 뒤 모서리 깎음, 아래 뒤는 45° 로 들어감
    b.add(cbox(G, (-24, 24), (26, 46), (190, 244), {"+yx": (6, 6), "+y-z": (10, 10), "+y+z": (6, 6), "+zx": (4, 4)}), 2)
    # 위 멍에판(랙 받침): 몸 장갑과 같은 아이보리 한 장 — 위·아래 바깥 모서리 45°. 뒤에서 밝은 위 / 짙은 노즐 아래로 나뉨
    # 정면 실루엣은 사다리꼴(위 ±34 → 아래 ±24, 45°)이라 몸통 옆선으로 흘러내림 — 막대처럼 안 보이게
    yoke = poly(G, "y", [(-0.6, 224), (24, 224), (34, 234), (34, 242), (30, 246), (-0.6, 246)], rng=(28, 48), sym=True)
    b.add(yoke & cbox(G, (-34, 34), (28, 48), (224, 246), {"+yx": (4, 4), "+y+z": (3, 3), "+y-z": (3, 3)}), 1)
    # 가운데 위 블록(머리 뒤, 멍에판 위로 솟음): 짙은 프레임 + 뒤 얕은 홈
    b.add(cbox(G, (-11, 11), (28, 46), (238, 256), {"+z+y": (5, 5), "+zx": (3, 3)}), 3)
    b.cut(box(G, (-6, 6), (45.4, 47), (248, 252)))
    # 노즐 받침판 + 원형 노즐 4개(2×2, 뒤로) — 종 모양 금속, 안은 짙게, 가장 깊은 곳만 주황
    b.add(cbox(G, (-21, 21), (45, 50), (193, 228), {"xz": (5, 5), "+yx": (2, 2)}), 3)
    for nx in (-9.5, 9.5):
        for nz in (202, 219):
            b.add(cyl(G, "y", (nx, nz), 6.6, (50, 57)), 7)
            b.add(cyl(G, "y", (nx, nz), 7.4, (56, 58)), 7)
            b.cut(cyl(G, "y", (nx, nz), 4.6, (52.6, 58)))
            b.add(cyl(G, "y", (nx, nz), 4.6, (52, 52)), 4)
            b.add(cyl(G, "y", (nx, nz), 2.0, (52, 52)), 6)
    # (10-26 02:16 유저) 노즐 묶음을 감싸는 몸통 회색(왼·오른 옆면 + 아래, 3방향)을 흰색으로 — 멍에판 아래 몸통 겉면 전부
    srf = b.surface()
    b.a[srf & (b.a == 2) & np.broadcast_to(Z < 228, b.a.shape)] = 1
    # 아래: 몸통 밑 짙은 띠(허리 뒤 라이플 자리 위로 비워 둠)
    b.add(cbox(G, (-18, 18), (28, 40), (186, 192), {"+yx": (3, 3)}), 3)

    # 빔사벨 랙(왼쪽을 만들고 미러). 곧게 만들고 관절(rot)로 기울임 → 계단 없음
    r = RACK[variant]
    T = r["top"]
    cx, cy0, cy1 = 26, 33, 45
    k = M.part("RackL", (16, 28, 220), (37, 52, T + 14), pivot=(cx, 39, 232), parent="Backpack")
    G = k.g(); X, Y, Z = G
    front = poly(G, "y", [(cx - 7, 222), (cx + 7, 222), (cx + 5.5, T), (cx - 5, T)], rng=(cy0, cy1))
    side = poly(G, "x", [(cy0, 222), (cy1, 222), (cy1, T), (cy0 + 5, T), (cy0, T - 7)])
    rack = front & side
    k.add(rack, 3)
    # 뒤 면 세로 홈(짙게)
    k.cut(box(G, (cx - 2, cx + 2), (cy1 - 0.6, cy1 + 1), (238, T - 12)))
    k.add(box(G, (cx - 2, cx + 2), (cy1 - 1.4, cy1 - 0.6), (238, T - 12)), 4)
    # 꼭대기 칼자루(빔 쪽이 랙 속, 손잡이가 위로): 짙은 손잡이 + 회색 끝마개
    hx, hy = cx + 0.3, 41
    k.add(cyl(G, "z", (hx, hy), 2.8, (T + 1, T + 8)), 4)
    k.add(cyl(G, "z", (hx, hy), 3.2, (T + 9, T + 12)), 7)
    k.rot = fv.roty(r["out"]) @ fv.rotx(-r["back"])
    M.mirror("RackL", "RackR", "Backpack")


def build(skirt="8", back="BP1"):
    M = lm.build("M2b")
    fix_skirts(M, skirt)
    if back != "cur":
        build_backpack(M, back)
    return M


def build_all():
    return build()


if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    what = sys.argv[1]
    out = sys.argv[2]
    A = fh.SCHEMES["A"]
    rows = []
    if what == "skirt":
        items = [("current  \\ /", "cur", "cur"), ("/ \\  (side 14 out, front 12 fwd)", "8", "cur"),
                 ("vertical (inner layer off, moved out 8)", "V", "cur")]
        views = ((0, 4, ""), (30, 6, "3/4"), (90, 2, "side"))
    else:
        items = [("current backpack", "8", "cur"), ("BP1 upright racks", "8", "BP1"), ("BP2 swept-back racks", "8", "BP2")]
        views = ((180, 8, ""), (150, 12, "back 3/4"), (90, 2, "side"), (0, 4, "front"), (30, 6, "3/4"))
    for label, sk, bk in items:
        M = build(sk, bk)
        B = M.blocks(pose=fh.STANCE)
        ims = [vp.render(B, A, fh.EMISSIVE, yaw=y, pitch=p, ppc=2.3, ss=2, ao_amt=0.5) for y, p, _ in views]
        if what == "skirt":
            legs = [n for n in M.parts if n.startswith(("Skirt", "UpperLeg", "LowerLeg", "Foot", "Pelvis"))]
            Bl = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n not in legs])
            ims.append(vp.render(Bl, A, fh.EMISSIVE, yaw=0, pitch=4, ppc=4.0, ss=2, ao_amt=0.5))
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        labs = [label + ("  " + views[0][2] if views[0][2] else "")] + [v[2] for v in views[1:]]
        if what == "skirt":
            labs.append("hips + legs only")
        rows.append(vp.sheet(ims, labs))
        print(label, "%.1fs" % (time.time() - t0), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
