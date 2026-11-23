"""
chest_r2.py — r2 중장갑 흉부 리메이크(마인크래프트 건담 흉부 양식) + 머리 U2(뒤로 누운 뿔, 길이 20) (2026-10-26)

흉부 양식(유저 제공 타임랩스 분석):
  - 위가 넓고 둥근 통(어깨 쪽 윗모서리 둥글게, 윗면은 목 → 앞·바깥으로 계단).
  - 가운데 콕핏 해치가 앞으로 톡 튀어나옴 + 강조색 테두리가 V 로 감쌈(위는 깃까지, 아래는 뾰족).
  - 해치 아래 양옆에 통풍 덕트(회색 틀 + 검은 가로 살 2줄).
  - 흉부 아래 배는 좁게(가운데 용골 하나).
r2 의 ChestPlate(눕힌 흰 판 + 세로 발광 틈)는 빼고, 새 파트 ChestNew(부모 Torso)를 몸통 앞에 덧씌운다.
  C1 흰 흉부 / C2 흑연 흉부
"""
import numpy as np

import flag_vox as fv
import flagship_heavy as fh
from flag_vox import box, cbox, poly
import unicorn_heads as uh


def _yf(ax):
    """통 앞면 y: 가운데(|x|≤14)는 -36, 바깥(40)으로 갈수록 -28 까지 뒤로 물러남(위에서 본 얕은 V)."""
    return -36.0 + np.clip(ax - 14.0, 0, None) * (8.0 / 26.0)


def build_chest(M, main=1):
    """main=1: 흰 통 + 흑연 해치 / main=2: 흑연 통 + 흰 해치."""
    hatch_c = 2 if main == 1 else 1
    p = M.part("ChestNew", (-46, -52, 166), (47, 26, 252), pivot=(0, -30, 210), parent="Torso")
    G = p.g(); X, Y, Z = G; ax = np.abs(X)
    Ga = (ax, Y, Z)
    yf = _yf(ax)
    # 통: 위에서 얕은 V, 앞에서 윗모서리 둥글게, 옆에서 앞 윗모서리를 계단으로 깎아 목 쪽으로
    front = poly(G, "y", [(-0.6, 196), (40, 196), (40, 225), (35, 234), (26, 240), (-0.6, 241)], sym=True)
    side = poly(G, "x", [(-37, 196), (-37, 229), (-31, 236), (-21, 241), (18, 241), (18, 196)])
    barrel = front & side & (Y >= yf) & (Y <= 18)
    p.add(barrel, main)
    # 콕핏 해치: 위에서 화살촉(앞 끝 y -48), 옆에서 아래가 가장 튀어나오고 위는 깃으로 눕는 포드
    h_front = poly(G, "y", [(-0.6, 203.5), (3.5, 203.5), (10.5, 214), (11.5, 240.5), (-0.6, 240.5)], sym=True)
    h_plan = (Y >= -48 + ax * (7.0 / 11.5)) & (Y <= -30)
    h_side = poly(G, "x", [(-49, 203), (-49, 226), (-43, 236), (-33, 241), (-28, 241), (-28, 203)])
    hatch = h_front & h_plan & h_side
    # 테두리(주황): 해치를 2.5칸 크게, 해치보다 2.5칸 뒤 — 해치가 테두리 밖으로 톡 튀어나옴
    r_front = poly(G, "y", [(-0.6, 199.5), (5.5, 199.5), (13.6, 212.5), (14.6, 241), (-0.6, 241)], sym=True)
    r_plan = (Y >= -45.5 + ax * (7.0 / 11.5)) & (Y <= -30)
    r_side = poly(G, "x", [(-46.5, 199), (-46.5, 228), (-41, 237), (-31, 241.5), (-28, 241.5), (-28, 199)])
    ring = r_front & r_plan & r_side
    p.add(ring & ~hatch, 5)
    p.add(hatch, hatch_c)
    # 해치 아래쪽 가로 이음선 한 줄(작은 점·구멍은 넣지 않음 — 얼굴로 읽힘)
    p.paint(hatch & (np.abs(Z - 216) <= 0.5), 4 if hatch_c == 1 else 3)
    # 통풍 덕트(테두리 바깥 아래): 회색 틀 + 검은 가로 살 2줄, 통 앞면을 따라 비스듬히
    duct = (ax >= 16) & (ax <= 36) & (Z >= 198.5) & (Z <= 212.5) & (Y >= yf - 2.5) & (Y <= yf + 6)
    p.add(duct, 7)
    for z0 in (201.0, 205.8):
        sl = (ax >= 18) & (ax <= 34) & (Z >= z0) & (Z <= z0 + 2.4)
        p.cut(sl & (Y < yf + 0.5) & (Y >= yf - 3))
        p.add(sl & (Y >= yf + 0.5) & (Y <= yf + 1.5), 4)
    # 배: 좁게 + 가운데 용골
    p.add(cbox(G, (-20, 20), (-27, 12), (174, 197), {"x-y": (4, 4), "-zx": (4, 4)}), 2)
    p.add(cbox(G, (-6, 6), (-31, -24), (176, 200), {"x-y": (2, 2), "-z-y": (3, 3)}), 3 if main == 2 else 2)
    p.add(box(G, (-21, 21), (-28, 13), (196, 197.5)), 3)
    return p


def build(main=1):
    M = fh.build_all()
    del M.parts["ChestPlate"]
    del M.parts["Head"]
    uh.head_U2m(M)
    build_chest(M, main)
    return M


VARIANTS = {"C1 white chest / graphite hatch": 1, "C2 graphite chest / white hatch": 2}
UPPER = ("Head", "Torso", "ChestNew", "ShoulderL", "ShoulderR", "Backpack", "UpperArmL", "UpperArmR", "Pelvis",
         "SkirtFL", "SkirtFR")

if __name__ == "__main__":
    import sys, time
    from PIL import Image
    import vox_preview as vp
    t0 = time.time()
    out = sys.argv[1] if len(sys.argv) > 1 else "chest.png"
    A = fh.SCHEMES["A"]

    def frame(M, yaw, pitch, names=("Head", "ChestNew"), mx=14, top=6, bot=8):
        d, f, r, u = vp._basis(yaw, pitch)
        P = []
        for n in names:
            q = M.parts[n]
            Q = np.argwhere(q.a > 0) + q.lo
            T = M.world(n)
            P.append(Q @ T[:3, :3].T + T[:3, 3])
        P = np.concatenate(P)
        sx, sy = P @ r, P @ u
        cx = (sx.min() + sx.max()) / 2
        hh = (sy.max() + top) - (sy.min() - bot)
        half = max((sx.max() - sx.min()) / 2 + mx, hh * 0.62)
        return ((cx - half, cx + half), (sy.min() - bot, sy.max() + top))

    rows = []
    for name, main in VARIANTS.items():
        M = build(main)
        ims = []
        for y, pc in ((0, 5), (32, 9), (-34, 12), (90, 3)):
            near = ("ShoulderL", "UpperArmL") if y == 90 else ()
            Bu = M.blocks(pose=fh.STANCE, skip=[n for n in M.parts if n not in UPPER or n in near])
            ims.append(vp.render(Bu, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=4.5, ss=2, ao_amt=0.5, size=frame(M, y, pc)))
        Bf = M.blocks(pose=fh.STANCE)
        fulls = [vp.render(Bf, A, fh.EMISSIVE, yaw=y, pitch=pc, ppc=1.6, ss=2, ao_amt=0.5) for y, pc in ((0, 4), (30, 6))]
        H = ims[0].height
        ims = [im.resize((int(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
        fulls = [f_.resize((int(f_.width * H / f_.height), H), Image.LANCZOS) for f_ in fulls]
        rows.append(vp.sheet(ims + fulls, [name + "  front", "3/4", "3/4 (other side)", "side", "full front", "full 3/4"]))
        print(name, "%.1fs" % (time.time() - t0), flush=True)
    W = max(r.width for r in rows)
    S = Image.new("RGB", (W, sum(r.height for r in rows)), (13, 14, 17))
    yy = 0
    for r in rows:
        S.paste(r, (0, yy)); yy += r.height
    S.save(out)
    print("done %.1fs" % (time.time() - t0), S.size)
