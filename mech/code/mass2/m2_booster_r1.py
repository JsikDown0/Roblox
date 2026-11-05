"""새 표준 양산기 ST-10 부스터 r1 (2026-11-04) — 유저 "부스터 구멍은 달긴 해야 할 것 같아" → 자리 P1 · P3 만 [결정 11-04 "p1 p3 만 보여줘"].
원칙 [제안 11-04]: 등 위쪽(가슴 뒤 z196~243)은 나중 백팩 자리로 비움 → 부스터는 그 아래.
  P1 허리 뒤: 배(z174~189, 뒤 Y≤11)와 등 아래 끝(z192, Y≤16) 사이에 짙은 부스터 상자(위 모래 덮개) + 뒤를 향한 노즐 2.
     노즐 = 강철 종(목 r4 → 입 r6) + 짙은 테 · 안쪽은 평소 검정(부스트 때만 발광 — GLOW).
  P3 = P1 + 종아리 뒤 작은 보조 노즐(좌우 1개씩, z74~84, 다리 축 위, 짙은 받침 + 강철 노즐 + 발광).
파트: Booster(부모 Pelvis) · CalfBoosterL/R(부모 LowerLegL/R)."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
from flag_vox import cyl, cbox  # noqa: E402
import m2_frame as fr  # noqa: E402
import m2_carbine_r1 as C  # noqa: E402
import m2_leg_r1 as lg  # noqa: E402

PAL, EMISSIVE = C.PAL, C.EMISSIVE
NAMES = {"P1": "P1 허리 뒤 노즐 2", "P3": "P3 = P1 + 종아리 뒤 보조 노즐"}


GLOW = False                  # 1차: 안쪽 청록 발광 2개가 나란히 → 뒤에서 두 눈(얼굴 함정, CETUS 와 같은 문제) → 평소엔 검정, 게임에서 부스트할 때만 발광·불꽃(Studio)


def nozzle(P, G, x, z, y0, r0, r1, L, glow=None):
    """+Y(뒤)를 향한 종 노즐: y0 에서 시작, 길이 L, 반지름 r0 → r1(1칸마다 커짐), 벽 1.2칸, 안쪽 바닥 발광."""
    X, Y, Z = G
    rr = np.sqrt((X - x) ** 2 + (Z - z) ** 2)
    t = np.clip((Y - y0) / max(L, 1), 0, 1)
    rad = r0 + (r1 - r0) * t
    body = (Y >= y0) & (Y <= y0 + L) & (rr <= rad)
    P.add(body, 7)
    P.cut((Y >= y0 + 2) & (Y <= y0 + L) & (rr <= rad - 1.3))
    P.add((Y >= y0 + L - 1) & (Y <= y0 + L) & (rr <= rad) & (rr > rad - 1.3), 3)                      # 입 테(짙은)
    glow = GLOW if glow is None else glow
    P.add((Y == y0 + 1) & (rr <= r0 - 0.8), 6 if glow else 4)                                         # 목 안쪽(평소 검정 · 부스트 때 발광 자리)


def booster(M):
    ox, oy, oz = (int(v) for v in fr.hp("BackLower")[0])                                               # 장착점 BackLower (0, 19, 183)
    B = M.part("Booster", (ox - 22, oy - 15, oz - 13), (ox + 23, oy + 13, oz + 17), pivot=(0, 0, 160), parent=fr.HARDPOINTS["BackLower"]["parent"])
    G = B.g(); X, Y, Z = G
    B.add(cbox(G, (ox - 17, ox + 17), (oy - 11, oy), (oz - 8, oz + 9), {"xy": 3, "+y+z": 3, "+y-z": 3}), 3)   # 부스터 상자(짙은 프레임)
    B.add(cbox(G, (ox - 15, ox + 15), (oy - 11, oy - 2), (oz + 9, oz + 11), {"xy": 2, "+yz": 2}), 1)         # 위 모래 덮개(등 아래 끝 밑)
    B.emboss((np.abs(X - ox) <= 13) & (Z >= oz - 6) & (Z <= oz + 7) & (Y > oy - 1), 2)                       # 뒤 판(짙은 회색) 1칸
    for sx in (1, -1):
        nozzle(B, G, ox + sx * 8, oz, oy, 4.0, 6.0, 7)                                                 # 1차 입 r5 · 길이 6 → 작아 보여 r6 · 7
    B.trim()


def calf(M):
    for s, nm in ((1, "L"), (-1, "R")):
        x, oy, oz = (int(v) for v in fr.hp("Calf" + nm)[0])                                            # 장착점 CalfL/R (±23, 16, 79)
        P = M.part("CalfBooster" + nm, (x - 8, oy - 8, oz - 15), (x + 9, oy + 10, oz + 17), pivot=lg.KNEE if s > 0 else (-lg.KNEE[0], lg.KNEE[1], lg.KNEE[2]), parent=fr.HARDPOINTS["Calf" + nm]["parent"])
        G = P.g(); X, Y, Z = G
        P.add(cbox(G, (x - 5, x + 5), (oy - 6, oy), (oz - 7, oz + 8), {"xy": 2, "+yz": 2}), 2)         # 받침(종아리 뒤)
        nozzle(P, G, x, oz, oy, 2.5, 3.5, 4)
        P.trim()


def build_all(kind="P1", stow=None):
    M = C.build_final(stow)
    booster(M)
    if kind == "P3":
        calf(M)
    return M


if __name__ == "__main__":
    out = sys.argv[1]
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model as cm
    FN = next(p for p in ('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', '/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf') if os.path.exists(p))
    f = ImageFont.truetype(FN, 24); ft = ImageFont.truetype(FN, 28)
    R = lambda M, y, pt, ppc, sk=(): vp.render(M.blocks(skip=sk, pose=lg.ARM_SPLAY), PAL, EMISSIVE, yaw=y, pitch=pt, ppc=ppc, ss=2, ao_amt=0.5, bg=(213, 215, 216), light=(-0.75, -0.55, 0.6), metal={7: 1.0})

    def cells(M, n):
        p = M.parts[n]; T = M.world(n, lg.ARM_SPLAY); ijk = np.argwhere(p.a > 0) + p.lo
        return set(map(tuple, np.round(ijk @ T[:3, :3].T + T[:3, 3]).astype(int)))
    rows = []
    for k in ("P1", "P3"):
        M = build_all(k); cm.check(M)
        bs = [n for n in M.parts if "Booster" in n]
        for st in ("S1", "S2", "S3"):
            M2 = build_all(k, st)
            print(k, st, "수납∩부스터", sum(len(cells(M2, "CarbineStowed") & cells(M2, b)) for b in bs))
        print(k, {b: {n: len(cells(M, b) & cells(M, n)) for n in M.parts if n != b and len(cells(M, b) & cells(M, n))} for b in bs})
        sk = [n for n in M.parts if "Arm" in n or "Hand" in n or n == "Carbine"]
        ims = [R(M, y, pt, 2.4) for y, pt in ((180, 3), (150, 10), (-90, 3))] + [R(M, y, pt, 4.5, sk) for y, pt in ((150, 12), (120, 5))]
        rows.append((NAMES[k] + " · 오른쪽 2장 = 팔·카빈 빼고 확대", ims))
    H = max(i.height for _, r in rows for i in r); W = max(sum(i.width + 14 for i in r) for _, r in rows) + 20
    sh = Image.new("RGB", (W, len(rows) * (H + 44) + 70), (24, 25, 28)); d = ImageDraw.Draw(sh)
    d.text((14, 14), "새 양산기 부스터 r1 — 등 위쪽은 백팩 자리로 비움 · P1 허리 뒤 / P3 + 종아리 보조", fill=(235, 235, 235), font=ft)
    y = 64
    for t, r in rows:
        d.text((14, y), t, fill=(240, 200, 120), font=f); x = 14; y += 36
        for im in r:
            sh.paste(im, (x, y + (H - im.height) // 2)); x += im.width + 14
        y += H + 8
    p = os.path.join(out, "시안_부스터r1.png"); sh.save(p); print(p, sh.size)


FINAL = "P3"                  # [결정 11-04 "p3 으로 가자"]
STOW = "S1"                   # [결정 11-04 "s1 로 가고 나이프 만들자"] 카빈 수납 = 등 대각선


def build_final(stow=STOW):
    return build_all(FINAL, stow)
