"""
aero_stow.py — Aero 무장 마무리: 빔사벨 칼자루 자리 + 빔사벨 꺼낼 때 라이플 수납 자리 (2026-10-26 21:22~)

유저: "이제 무장은 전부 완료됐나? 완료됐으면 로블록스에 가져갈 준비하자."
남은 것 = 빔사벨(공통 무기) 칼자루를 Aero 어디에 꽂아 두나 + 빔사벨 상태에서 라이플을 어디에 거나(aero_r1.md 19절 '남은 것').
중장갑 선례 [실측: 현재상태_20261026 5-1·rig]: 빔사벨 = 왼손(saber 자세가 ShoulderL·ElbowL), 등 위 왼쪽 랙에서 어깨 위로 뽑음 /
  라이플 = 허리 뒤 가로(개머리판 오른쪽), 몸통에 묶음(StowPart = "Torso").
게임 손 칼자루 = 0.8 × 3.8 × 0.8 스터드(rig/voxcheck HILT) → 260칸 ≈ 32스터드 기준 길이 약 31칸 · 굵기 약 6칸 [추측: 비율 환산].
안:
  K1 칼자루 = 등 위 왼쪽(백팩 윗면, 머리 뒤 · 왼 바인더 안쪽) — 중장갑과 같은 '어깨 위로 뽑기' → 칼 잡기 자세 재사용
  K2 칼자루 = 왼쪽 옆 스커트 바깥면(손잡이가 앞) — 허리에서 뽑기 → 뽑는 동작 새로 필요
  R1 라이플 = 허리 뒤 가로(중장갑과 같음) — 뒤 스커트(y 31)와 날개(y 44~49) 사이 틈 [실측]
"""
import numpy as np

from flag_vox import box, cyl, rotx, roty
import aero_r1 as A
import aero_rifle as R
import aero_launcher as GL

WHITE, LGRAY, FRAME, BLACK, ACC, GLOW, METAL = 2, 10, 3, 4, 1, 6, 7
HILT_LEN, HILT_R = 31, 2.8


def _hilt(G, axis, c, rng, pommel_low):
    """칼자루 마스크 {색: bool}. axis 방향 rng 구간, pommel_low=True 면 rng 아래쪽 끝이 끝마개(손이 잡는 쪽)."""
    lo, hi = rng
    if pommel_low:
        cap, emit = (lo, lo + 3), (hi - 4, hi)
    else:
        cap, emit = (hi - 3, hi), (lo, lo + 4)
    body = cyl(G, axis, c, HILT_R, rng)
    out = {METAL: cyl(G, axis, c, 3.2, cap) | cyl(G, axis, c, 3.0, emit)}
    out[BLACK] = body
    # 손잡이 가로 홈 4줄(짙은 회색) — 칼자루로 읽히게
    k = {"x": 0, "y": 1, "z": 2}[axis]
    t = G[k]
    ridge = np.zeros(np.broadcast_shapes(*[g.shape for g in G]), bool)
    for i in range(4):
        z0 = (cap[1] if pommel_low else emit[1]) + 4 + i * 5
        ridge |= np.broadcast_to(body & (t == z0), ridge.shape)
    out[FRAME] = ridge
    out[ACC] = cyl(G, axis, c, 3.3, (emit[0] + 1, emit[0] + 1) if pommel_low else (emit[1] - 1, emit[1] - 1))   # 빔 나오는 쪽 고리 하나만 강조색
    return out


def _paint(p, m):
    G = p.g(); shp = np.broadcast_shapes(*[g.shape for g in G])
    for c in (BLACK, FRAME, METAL, ACC):
        p.add(np.broadcast_to(m[c], shp), c)


def holster_back(M):
    """K1: 백팩 윗면 왼쪽, 머리 뒤(머리 y ≤ 12) · 왼 바인더 안쪽(x ≥ 14). 빔 쪽이 받침 속, 끝마개가 위 — 중장갑 랙과 같은 방향."""
    cx, cy, z0 = 8, 29, 243
    p = M.part("SaberHolsterL", (cx - 7, cy - 7, z0 - 2), (cx + 8, cy + 8, z0 + HILT_LEN + 3), pivot=(cx, cy, z0 + 2), parent="Backpack")
    G = p.g()
    p.add(box(G, (cx - 4, cx + 4), (cy - 4, cy + 4), (z0, z0 + 6)), FRAME)                       # 받침(백팩에 물림)
    _paint(p, _hilt(G, "z", (cx, cy), (z0 + 3, z0 + HILT_LEN + 2), pommel_low=False))
    p.rot = roty(8) @ rotx(-6)                                                                   # 끝이 바깥·뒤로 살짝(중장갑 랙 9°·6°)
    return p


def holster_hip(M):
    """K2: 왼쪽 옆 스커트 바깥면, 손잡이(끝마개)가 앞 — 왼손이 허리에서 앞으로 뽑음."""
    q = M.parts["SkirtSL"]
    ijk = np.argwhere(q.a > 0) + q.lo
    xo = int(ijk[:, 0].max())                                                                     # 스커트 바깥면 x(쉬는 틀)
    zc = int(round((ijk[:, 2].min() + ijk[:, 2].max()) / 2))
    cx, cz = xo + 5, zc
    p = M.part("SaberHolsterL", (xo, -20, cz - 6), (xo + 10, 20, cz + 7), pivot=(xo, 0, cz), parent="SkirtSL")
    G = p.g()
    p.add(box(G, (xo + 1, xo + 2), (-5, 5), (cz - 4, cz + 4)), FRAME)                            # 받침
    _paint(p, _hilt(G, "y", (cx, cz), (-17, 13), pommel_low=True))
    p.rot = rotx(18)                                                                              # 손잡이 앞쪽이 살짝 위로 [부호는 렌더로 확인]
    return p


def place_rifle(M, name, O, ax, bx, parent, scale=None):
    """라이플 설계 좌표 (a 앞, b 위, c 옆) 원점을 월드 O 에, a·b 축을 ax·bx 로 놓음(attach 와 같은 배율·반올림)."""
    sa, sb, sc = scale or R.SCALE
    O = np.array(O, float); ax = np.array(ax, float); bx = np.array(bx, float); cx = np.cross(ax, bx)
    cs = [O + a * sa * ax + b * sb * bx + c * sc * cx for a in (-39, 87) for b in (-21, 13) for c in (-5, 5)]
    lo = np.floor(np.min(cs, 0)).astype(int) - 1; hi = np.ceil(np.max(cs, 0)).astype(int) + 1
    p = M.part(name, tuple(lo), tuple(hi), pivot=tuple(O.astype(int)), parent=parent)
    X, Y, Z = p.g()
    P = (X - O[0], Y - O[1], Z - O[2])
    a = np.round((P[0] * ax[0] + P[1] * ax[1] + P[2] * ax[2]) / sa)
    b = np.round((P[0] * bx[0] + P[1] * bx[1] + P[2] * bx[2]) / sb)
    c = np.round((P[0] * cx[0] + P[1] * cx[1] + P[2] * cx[2]) / sc)
    shp = np.broadcast_shapes(np.shape(a), np.shape(b), np.shape(c))
    m = {k: np.broadcast_to(v, shp) for k, v in R.rifle_masks(a, b, c).items()}
    R._paint(p, m)
    return p


RIFLE_STOW = dict(O=(-27, 38, 166), ax=(1, 0, 0), bx=(0, 0, 1))      # R1: 허리 뒤 가로, 개머리판 오른쪽(중장갑과 같음) — y·z 는 겹침 최소로 고름(__main__ 탐색)


def build(k="K1", stowed=True, open_=False):
    """무장 전부 단 Aero. stowed=True 면 빔사벨 상태(라이플은 허리 뒤, 손 라이플 없음)."""
    M = GL.build(open_)
    (holster_back if k == "K1" else holster_hip)(M)
    if stowed:
        del M.parts["RifleR"]
        place_rifle(M, "RifleStowed", parent="Torso", **RIFLE_STOW)
    return M


def overlap(M, names, pose=None):
    """names 파트 칸이 다른 파트 칸과 겹치는 수(월드, 반올림) — 파트별."""
    pose = A.STANCE if pose is None else pose
    def W(n):
        p = M.parts[n]; ijk = np.argwhere(p.a > 0) + np.array(p.lo); T = M.world(n, pose)
        return np.round(ijk @ T[:3, :3].T + T[:3, 3]).astype(int)
    occ = {}
    for n in M.parts:
        if n in names:
            continue
        for t in map(tuple, W(n)):
            occ[t] = n
    res = {}
    for n in names:
        hit = {}
        for t in map(tuple, W(n)):
            if t in occ:
                hit[occ[t]] = hit.get(occ[t], 0) + 1
        res[n] = hit
    return res


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    import aero_colors as Cc
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    if len(sys.argv) > 2 and sys.argv[2] == "search":                                            # 라이플 y·z 탐색
        for y in (35, 37, 38, 39):
            for z in (160, 163, 166, 170):
                RIFLE_STOW["O"] = (-27, y, z)
                M = build("K1")
                print(y, z, overlap(M, ["RifleStowed"])["RifleStowed"], flush=True)
        sys.exit()
    sch = Cc.SCHEMES["C1 흰·주황"]
    rows = []
    for k, lab in (("K1", "A  saber back"), ("K2", "B  saber hip")):
        M = build(k)
        print(k, overlap(M, ["SaberHolsterL", "RifleStowed"]), flush=True)
        B = M.blocks(pose=A.STANCE)
        close = (150, 12, 3.0, ((-80, 80), (150, 290))) if k == "K1" else (60, 8, 3.0, ((-80, 80), (110, 240)))
        views = [(20, 4, 1.5, ((-120, 120), (-10, 320))), (150, 10, 1.5, ((-120, 120), (-10, 320))),
                 (240, 6, 1.5, ((-120, 120), (-10, 320))), close]
        ims = [vp.render(B, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=pc, ss=2, size=sz, ao_amt=0.5) for y, p, pc, sz in views]
        rows.append(vp.sheet(ims, ["%s  front 3/4" % lab, "back 3/4", "side", "close"]))
        print(k, round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
