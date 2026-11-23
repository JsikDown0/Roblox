"""
aero_launcher.py — Aero 보조무장: 왼손목 2연장 그레네이드 런처 (2026-10-26 21:06~)

결정: 손목 그레네이드 2발 · 두 발 다 쓰면 한꺼번에 다시 참(20:24) · 라이플 크기 = 길이 ×1.15 · 두께 ×1.35(21:06 "추천안대로").
유저 레퍼런스(19:30 사진 2): 팔뚝 장갑 덮개가 움직여 안쪽 발사관 두 개가 드러나는 구조 — 같은 '역할'만, 모양은 Aero 고유.
왼손목 = 오른손은 라이플, 한 손 사격 때 왼팔이 이미 앞으로 뻗음.
구성(쉬는 자세 기준, 팔 축 = Z, 앞 = -Y → 팔을 앞으로 들면 앞면이 위로 감):
  GLauncherL(아래팔 자식, 고정): 짙은 몸통 + 발사관 2개(팔 축을 따라, 총구는 손목 쪽 = 쏘는 방향) + 안의 탄두(빨강) — 손등보다 4칸 앞이라 주먹을 안 맞춤
  GLCoverL(아래팔 자식, 움직임): 흰 덮개. 닫힘 = 총구까지 덮음 / 열림 = 팔꿈치 쪽으로 10칸 밀려 총구 노출
"""
import numpy as np

from flag_vox import box, cbox, cyl, rotx, roty
import aero_r1 as A
import aero_rifle as R

WHITE, LGRAY, FRAME, BLACK, ACC, GLOW, METAL = 2, 10, 3, 4, 1, 6, 7
RED = 5                                     # 탄두 색(21:22 유저 "탄두 빨강으로") — aero_colors._base 5
TUBES = ((38.5, -16.0), (43.5, -16.0))     # 발사관 중심 (x, y)
MOUTH = 140                                 # 총구 z(손목 쪽 끝)
SLIDE = 10                                  # 열릴 때 덮개가 팔꿈치 쪽으로 밀리는 칸


def launcher(M):
    p = M.part("GLauncherL", (32, -24, 134), (50, -8, 178), pivot=(41, -16, 156), parent="LowerArmL")
    G = p.g(); X, Y, Z = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    B = lambda m: np.broadcast_to(m, shp)
    p.add(B(cbox(G, (36, 46), (-20, -12), (MOUTH + 2, 172), {"x-y": 2, "+z-y": 3})), FRAME)    # 몸통
    for tx, ty in TUBES:
        tube = cyl(G, "z", (tx, ty), 2.3, (MOUTH, 168))
        bore = cyl(G, "z", (tx, ty), 1.3, (MOUTH, 168))
        p.add(B(tube), METAL)
        p.cut(B(bore & (Z <= MOUTH + 1)))                                                       # 총구 한 칸 깊이
        p.add(B(bore & (Z == MOUTH + 2)), RED)                                                  # 안의 탄두(빨강)
    return p


def cover(M, open_=False):
    dz = SLIDE if open_ else 0
    p = M.part("GLCoverL", (32, -26, 134), (50, -8, 190), pivot=(41, -18, 160), parent="LowerArmL")
    G = p.g(); X, Y, Z = G
    shp = np.broadcast_shapes(X.shape, Y.shape, Z.shape)
    B = lambda m: np.broadcast_to(m, shp)
    z0 = MOUTH - 2 + dz
    shell = cbox(G, (34, 48), (-23, -12), (z0, 176 + dz), {"-z-y": (4, 4), "x-y": 3, "+z-y": 3})
    inner = box(G, (36, 46), (-20, -11), (z0 + 3, 177 + dz))                                   # 속 비움(발사관 자리). 앞 벽 3칸 — 2칸이면 x-y·-z-y 모따기가 모서리를 대각선으로만 이어 앞 판이 섬이 됨(r1 check)
    p.add(B(shell & ~inner), WHITE)
    p.paint(B((Z <= z0 + 4) & (Y <= -21)), ACC)                                                 # 손목 쪽 앞 끝만 강조색
    p.cut(B((Y <= -23) & (Z == z0 + 14) & (X >= 36) & (X <= 46)))                               # 가로 단차 홈
    p.cut(B((Y == -23) & (Z >= z0 + 20) & (Z <= z0 + 21) & (X >= 40) & (X <= 42)))             # 작은 등
    p.add(B((Y == -22) & (Z >= z0 + 20) & (Z <= z0 + 21) & (X >= 40) & (X <= 42)), GLOW)
    return p


def grenade(M, name, pos, parent=None):
    """날아가는 탄 하나(그림용): 짧은 캡슐, 앞 강조색, 뒤 발광."""
    x, y, z = pos
    p = M.part(name, (x - 4, y - 4, z - 6), (x + 5, y + 5, z + 7), pivot=pos, parent=parent)
    G = p.g(); X, Y, Z = G
    r = np.sqrt((X - x) ** 2 + (Y - y) ** 2)
    body = (r <= 2.2) & (Z >= z - 4) & (Z <= z + 4)
    p.add(body, LGRAY)
    p.paint(body & (Z <= z - 2), RED)                                                           # 탄두(앞 = 쏘는 방향) 빨강
    p.add((r <= 1.2) & (Z >= z + 5) & (Z <= z + 6), GLOW)                                       # 꼬리 불
    return p


def build(open_=False, shots=False):
    M = R.build("S2")
    launcher(M)
    cover(M, open_)
    if shots:                                                                                   # 쏘는 방향(팔 축 아래쪽)으로 두 발
        for i, ((tx, ty), dz) in enumerate(zip(TUBES, (26, 44))):
            grenade(M, "GrenadeL%d" % (i + 1), (int(tx), int(ty), MOUTH - dz), parent="LowerArmL")
    return M


def build_all():
    return build(False)


# 왼팔 앞으로(한 손 사격 때 왼팔 자세를 과장해서 — 런처 방향 확인용)
LEFT_FWD = dict(A.STANCE)                                                                      # 오른팔(라이플)은 쉬는 자세 — 두 팔이 겹쳐 런처가 가려짐(v1)
LEFT_FWD.update({"UpperArmL": rotx(-80) @ roty(6), "LowerArmL": np.eye(3), "ShoulderL": roty(6)})

if __name__ == "__main__":
    import sys, time
    import vox_preview as vp
    import aero_colors as Cc
    from PIL import Image
    t0 = time.time()
    out = sys.argv[1]
    sch = Cc.SCHEMES["C1 흰·주황"]
    rows = []
    ARM = {"UpperArmL", "LowerArmL", "GLauncherL", "GLCoverL", "GrenadeL1", "GrenadeL2", "ShoulderL"}
    for open_, lab in ((False, "closed"), (True, "open")):
        M = build(open_)
        B = M.blocks(pose={}, skip=[n for n in M.parts if n not in ARM])
        ims = [vp.render(B, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=5, ss=2, size=sz, ao_amt=0.5)
               for y, p, sz in ((0, 4, ((10, 70), (106, 200))), (300, 10, ((-10, 80), (106, 200))), (20, -40, ((10, 70), (100, 200))))]
        rows.append(vp.sheet(ims, ["%s  front" % lab, "3/4", "from below (muzzle)"]))
        print(lab, round(time.time() - t0, 1), flush=True)
    M = build(True, shots=True)
    B = M.blocks(pose=LEFT_FWD)
    ims = [vp.render(B, sch, A.EMISSIVE, yaw=y, pitch=p, ppc=pc, ss=2, size=sz, ao_amt=0.5)
           for y, p, pc, sz in ((40, 8, 1.4, ((-180, 180), (-10, 320))), (90, 4, 1.4, ((-180, 180), (-10, 320))), (70, 14, 3.0, ((-160, 120), (170, 280))))]
    rows.append(vp.sheet(ims, ["fire 3/4", "side", "close"]))
    print("fire", round(time.time() - t0, 1), flush=True)
    w = max(r.width for r in rows); h = sum(r.height for r in rows)
    S = Image.new("RGB", (w, h), (13, 14, 17)); y = 0
    for r in rows:
        S.paste(r, (0, y)); y += r.height
    S.save(out)
    print("done", round(time.time() - t0, 1))
