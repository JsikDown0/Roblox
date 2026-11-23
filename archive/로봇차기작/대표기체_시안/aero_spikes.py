"""
aero_spikes.py — Aero 궁극기 '마비 못' 부품 디자인 (2026-10-26 20:24~)

유저: "(못을 어디서 쏘나) 디자인과 관련해서 보고 싶어. 건담 시리즈의 판넬처럼 따로 디자인으로 추가할 수 있을까?"
→ 판넬과 같은 '역할'(기체에 달려 있다가 떨어져 날아가는 별도 부품)만 쓰고 모양은 Aero 고유로. 레퍼런스 영상의 말뚝(박히고 → 전기로 이어짐)이 형태 출발점.
못 1개(v2) = 긴 마름모 금속 촉(박히는 쪽) + 강조색 고리 + 밝은 회색 팔각 몸통 + 흰 십자 날개(화살 깃) + 짧은 짙은 머리(발광 고리 = 전기가 나오는 곳) + 뾰족한 흰 꼭대기.
길이 64칸(≈ 6.4스터드 [추측: 기체 287칸 ≈ 28스터드 기준]). 궁극기 한 번에 4개.
장착 안: S1 날개 뒤 판에 한 날개당 2개(깃대처럼 엇갈려 꽂음) / S2 등 바인더 바깥면에 한쪽 2개(세로)
"""
import numpy as np

from flag_vox import box, cbox, poly, cyl
import aero_r1 as A
import aero_legs_d as D

WHITE, LGRAY, FRAME, BLACK, ACC, GLOW, METAL = 2, 10, 3, 4, 1, 6, 7
SPIKES = []
LEN = 64


def _spike_mask(G, cx, cy, z0, axis="z"):
    """못 하나(축 = z, 촉이 아래 z0). v2: v1(촉 10 · 큰 흰 머리 + 네모 발광 창)은 가로등·손전등처럼 읽힘 →
    긴 마름모 촉(24) · 강조색 고리 · 십자 날개(화살 깃처럼 아래로 좁아짐) · 짧은 머리(발광 고리 한 줄) · 위도 뾰족 = 양끝 뾰족한 말뚝."""
    X, Y, Z = G
    dx, dy, t = np.abs(X - cx), np.abs(Y - cy), Z - z0
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    out = {}
    tip = (t >= 0) & (t < 24) & (dx + dy <= t * 0.21 + 0.6)                                   # 마름모 단면, 1:5 로 좁아지는 긴 촉
    ring = (t >= 24) & (t < 27) & (dx <= 4) & (dy <= 4) & (dx + dy <= 6)
    body = (t >= 27) & (t < 52) & (dx <= 3) & (dy <= 3) & (dx + dy <= 5)
    fin = (t >= 31) & (t <= 50) & (((dy <= 0.5) & (dx <= 3 + (t - 31) * 0.2)) | ((dx <= 0.5) & (dy <= 3 + (t - 31) * 0.2)))   # 십자 날개, 위로 넓어짐(끝 6.8)
    head = (t >= 52) & (t <= 64) & (dx + dy <= np.minimum(6, 64 - t + 0.5))                 # 위도 뾰족(피라미드)
    glow_ring = (t >= 55) & (t <= 56) & (dx + dy <= 6)
    out[LGRAY] = body
    out[WHITE] = fin | (head & ~glow_ring & (t >= 57))
    out[FRAME] = head & (t < 57) & ~glow_ring
    out[METAL] = tip
    out[ACC] = ring
    out[GLOW] = glow_ring & (dx + dy >= 5)                                                     # 바깥 둘레만 발광(전기가 나오는 고리)
    out["cut"] = np.zeros(shp, bool)
    return {k: np.broadcast_to(v, shp) for k, v in out.items()}


def _add_spike(p, G, cx, cy, z0):
    m = _spike_mask(G, cx, cy, z0)
    for c in (LGRAY, METAL, ACC, WHITE, FRAME):
        p.add(m[c], c)
    p.cut(m["cut"])
    p.add(m[GLOW], GLOW)


def mount_wing(M):
    """S1: 날개 뒤 판(y 36~39) 뒤에 한 날개당 2개, 날개 긴 축을 따라 엇갈려 — 깃대처럼."""
    for name, cx, z0 in (("SpikeL1", 33, 128), ("SpikeL2", 44, 160)):
        p = M.part(name, (cx - 9, 36, z0 - 2), (cx + 10, 53, z0 + LEN + 3), pivot=(cx, 45, z0 + LEN // 2), parent="WingL")
        G = p.g()
        _add_spike(p, G, cx, 45, z0)
        p.add(box(G, (cx - 2, cx + 2), (39, 41), (z0 + 28, z0 + 50)), FRAME)                  # 거치 받침(날개 판과 이음)
        M.mirror(name, name.replace("L", "R"), "WingR")
        SPIKES.extend([name, name.replace("L", "R")])


def mount_binder(M):
    """S2: 등 바인더 바깥면(x 30~31)에 한쪽 2개 세로, 촉이 아래."""
    for name, cy in (("SpikeL1", 26), ("SpikeL2", 40)):
        p = M.part(name, (28, cy - 9, 178), (46, cy + 10, 252), pivot=(37, cy, 214), parent="BinderL")
        G = p.g()
        _add_spike(p, G, 38, cy, 182)
        p.add(box(G, (32, 34), (cy - 2, cy + 2), (210, 232)), FRAME)                          # 거치 받침
        M.mirror(name, name.replace("L", "R"), "BinderR")
        SPIKES.extend([name, name.replace("L", "R")])


def build(kind="S1"):
    SPIKES.clear()
    M = D.build()
    (mount_wing if kind == "S1" else mount_binder)(M)
    return M


def build_all():
    return build("S1")


def spike_only():
    import flag_vox as fv
    M = fv.Model()
    p = M.part("Spike", (-9, -9, -2), (10, 10, LEN + 3), pivot=(0, 0, 32))
    _add_spike(p, p.g(), 0, 0, 0)
    return M


def zone_scene():
    """박힌 못 4개(사각형 한 변 240칸 ≈ 24스터드 [추측]) + 머리끼리 이어진 전기 + 바닥 경계선 + 가운데 Aero(크기 비교)."""
    import flag_vox as fv
    M = D.build()
    H = 120
    g = M.part("Zone", (-H - 12, -H - 12, -2), (H + 13, H + 13, 60))
    G = g.g(); X, Y, Z = G
    corners = [(-H, -H), (H, -H), (H, H), (-H, H)]
    sink = 10                                                                                  # 촉이 땅에 묻힘
    for cx, cy in corners:
        _add_spike(g, G, cx, cy, -sink)
    rng = np.random.default_rng(3)
    zh = LEN - sink - 8                                                                        # 머리 발광 고리 높이
    for (ax_, ay_), (bx_, by_) in zip(corners, corners[1:] + corners[:1]):
        n = 48
        for i in range(n + 1):
            u = i / n
            jit = (rng.random() - 0.5) * 6 * np.sin(np.pi * u)                                # 가운데가 더 흔들리는 전기
            x = ax_ + (bx_ - ax_) * u + (jit if ax_ == bx_ else 0)
            y = ay_ + (by_ - ay_) * u + (jit if ay_ == by_ else 0)
            z = zh + (rng.random() - 0.5) * 6 * np.sin(np.pi * u)
            g.add((np.abs(X - x) <= 0.6) & (np.abs(Y - y) <= 0.6) & (np.abs(Z - z) <= 1.1), GLOW)
        # 바닥 경계선(판정 = 이 사각형)
        g.add(box(G, (min(ax_, bx_) - 1, max(ax_, bx_) + 1), (min(ay_, by_) - 1, max(ay_, by_) + 1), (-1, -1)), ACC)
    g.add(box(G, (-H - 12, H + 12), (-H - 12, H + 12), (-2, -2)), BLACK)                       # 바닥
    return M


if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    import aero_colors as Cc
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    sch = Cc.SCHEMES["C1 흰·주황"]
    rows = []
    # 1) 못 하나
    Ms = spike_only(); Bs = Ms.blocks()
    ims = [vp.render(Bs, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=6, ss=2, size=((-16, 16), (-4, 68)), ao_amt=0.5)
           for y, p in ((0, 6), (35, 14), (90, 4), (35, -30))]
    rows.append(vp.sheet(ims, ["spike front", "3/4", "side", "from below"]))
    print("spike", round(time.time() - t0, 1), flush=True)
    # 2) 장착 안
    for k in ("S1", "S2"):
        M = build(k); B = M.blocks(pose=A.STANCE)
        ims = [vp.render(B, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=pc, ss=2, size=sz, ao_amt=0.5)
               for y, p, pc, sz in ((0, 4, 1.6, ((-110, 110), (-10, 320))), (150, 12, 1.6, ((-110, 110), (-10, 320))),
                                    (180, 10, 1.6, ((-110, 110), (-10, 320))), (130, 10, 3.0, ((-70, 70), (120, 290))))]
        rows.append(vp.sheet(ims, ["%s  front" % k, "back 3/4", "back", "back close"]))
        print(k, round(time.time() - t0, 1), flush=True)
    # 3) 박힌 장면
    Mz = zone_scene(); Bz = Mz.blocks(pose=A.STANCE)
    ims = [vp.render(Bz, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=0.9, ss=2, size=((-190, 190), (-60, 300)), ao_amt=0.5) for y, p in ((20, 28), (45, 55))]
    rows.append(vp.sheet(ims, ["zone 3/4", "zone high"]))
    print("zone", round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
