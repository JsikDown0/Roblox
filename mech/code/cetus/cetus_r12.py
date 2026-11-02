"""HT-02 CETUS — r12 = r11 확정본 + 부스터 (2026-11-02)

[결정 11-02 "ABC 모두 채용. A 주부스터 · B 증기 배출구 · C 보조"] (논의 그림 레퍼런스/CETUS/논의_부스터자리_하체뒤.png)
A 허리 뒤 주부스터: 골반 뒤 짙은 쇠 상자 + 청록 덮개 + 큰 종 노즐 2(강철 테, 안쪽 깊숙이 발광)
B 증기 배출구: 등 'ㅠ' 배관 기둥 아래 끝이 바깥·뒤로 꺾여 황동 나팔 입(안은 검정) — 게임에선 흰 증기 파티클
C 종아리 보조 노즐: 피스톤 사이 작은 노즐 1(발광), 황동 띠는 위로 짧게
노즐 안 발광 = 색 6, 1~2칸 안쪽(오목) [판단: "발광 더 늘림" 결정에 맞춰 평소에도 은은히. 부스트 때 세기는 게임에서].
뒤판(허벅지·종아리 뒤 청록 판)은 답이 없어 넣은 안 / 뺀 안 둘 다 보여 줌.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
from flag_vox import cbox, cyl, box  # noqa: E402
import cetus_r6 as r6  # noqa: E402
import cetus_r11 as r11  # noqa: E402

PAL, EMISSIVE, METAL = r11.PAL, r11.EMISSIVE, r11.METAL
SHIN_X = 40          # 정강이 축(세계 x, r10 CX 35 + 밀기 5)
THIGH_X = 38


def grow(p, lo, hi):
    """파트 경계를 넓힌다(trim 된 파트에 덧붙일 때)."""
    lo = np.minimum(p.lo, lo); hi = np.maximum(p.hi, hi)
    a = np.zeros(tuple(hi - lo), np.uint8)
    o = p.lo - lo
    a[o[0]:o[0] + p.a.shape[0], o[1]:o[1] + p.a.shape[1], o[2]:o[2] + p.a.shape[2]] = p.a
    p.a, p.lo, p.hi = a, np.array(lo), np.array(hi)


def nozzle_y(P, G, cx, cz, y0, y1, r0, r1, wall=2.2, glow_depth=3):
    """뒤(+y)로 벌어지는 종 노즐: 반지름 r0(y0) → r1(y1). 강철 벽 + 끝 테, 안은 검정, 목 안쪽 발광."""
    X, Y, Z = G
    k = np.clip((Y - y0) / float(y1 - y0), 0, 1)
    r = r0 + (r1 - r0) * k ** 1.5
    d = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2)
    inside = (Y >= y0) & (Y <= y1)
    P.add(inside & (d <= r + 0.25), 7)
    P.cut(inside & (d <= r - wall) & (Y > y0 + glow_depth))
    P.add(inside & (d <= r - wall) & (Y > y0 + glow_depth - 1) & (Y <= y0 + glow_depth), 6)
    P.paint(inside & (d <= r + 0.25) & (d > r - wall) & (Y >= y1 - 1), 5)       # 입 테 황동


def add_main_booster(M):
    P = M.parts["Pelvis"]
    grow(P, (-34, -38, 124), (35, 46, 177))
    G = P.g(); X, Y, Z = G
    P.add(cbox(G, (-24, 24), (16, 30), (138, 168), {"xz": 6, "+y+z": 4, "+y-z": 3}), 3)    # 부스터 상자
    cov = cbox(G, (-22, 22), (18, 31), (161, 169), {"xz": 4, "+y+z": 4})
    P.add(cov, 1)                                                                          # 위 청록 덮개
    P.paint(cov & (Z <= 161), 5)
    for s in (1, -1):
        P.add(cyl(G, "y", (s * 12, 150), 8.5, rng=(29, 31)), 3)                           # 노즐 받침 고리
        nozzle_y(P, G, s * 12, 150, 30, 42, 6.5, 10.5)


def add_steam_vents(M):
    Bk = M.parts["Back"]
    grow(Bk, (-40, 14, 156), (41, 48, 253))
    G = Bk.g(); X, Y, Z = G
    for s in (1, -1):
        x0 = s * r11.PX
        path = [(x0, 27, 173), (x0 + s * 3, 29, 166), (x0 + s * 8, 33, 162)]
        t = r6.path_tube(G, path, 4.2)
        Bk.add(t & ~(Bk.a > 0), 3)
        # 나팔 입: 바깥·뒤·아래를 향함 — 축 방향 u, 입 지름 4 → 6.5
        a = np.array(path[-1], float); u = np.array([s * 0.55, 0.55, -0.62]); u /= np.linalg.norm(u)
        tt = (X - a[0]) * u[0] + (Y - a[1]) * u[1] + (Z - a[2]) * u[2]
        px, py, pz = X - a[0] - tt * u[0], Y - a[1] - tt * u[1], Z - a[2] - tt * u[2]
        rad = np.sqrt(px ** 2 + py ** 2 + pz ** 2)
        rr = 4.2 + 2.6 * np.clip(tt / 6.0, 0, 1)
        bell = (tt >= 0) & (tt <= 6) & (rad <= rr + 0.25)
        Bk.add(bell, 5)
        Bk.add(bell & (rad <= rr - 1.6) & (tt >= 2.5), 4)                                  # 안은 검정(증기 나오는 구멍)


def add_calf_jet(M, plates):
    L = M.parts["LowerLegL"]
    grow(L, (9, -36, 20), (73, 32, 118))
    G = L.g(); X, Y, Z = G
    L.cut(box(G, x=(SHIN_X - 3, SHIN_X + 3), y=(15, 20), z=(52, 69)))                   # 황동 띠 아랫부분 비움
    L.add(cbox(G, (SHIN_X - 6, SHIN_X + 6), (14, 19), (52, 68), {"xz": 3}), 3)           # 노즐 받침
    nozzle_y(L, G, SHIN_X, 60, 18, 25, 3.8, 5.5, wall=1.6, glow_depth=2)
    if plates:   # 종아리 뒤 청록 판(피스톤 위, 무릎 밑) + 황동 아래 테
        pl = cbox(G, (SHIN_X - 13, SHIN_X + 13), (16, 22), (72, 92), {"xz": 4, "+y-z": 3, "+y+z": 2})
        L.add(pl & ~(L.a > 0), 1)
        L.paint(pl & (Z <= 73), 5)
    U = M.parts["UpperLegL"]
    if plates:   # 허벅지 뒤 청록 판 + 황동 띠
        grow(U, (18, -28, 102), (58, 22, 156))
        G = U.g(); X, Y, Z = G
        pl = cbox(G, (THIGH_X - 15, THIGH_X + 14), (10, 18), (112, 146), {"xz": 5, "+y-z": 4, "+y+z": 4})
        U.add(pl & ~(U.a > 0), 1)
        U.groove(pl & (Z == 129) & (Y >= 15), 4)
    M.mirror("UpperLegL", "UpperLegR", "Pelvis")
    M.mirror("LowerLegL", "LowerLegR", "UpperLegR")
    M.mirror("FootL", "FootR", "LowerLegR")


def build_all(plates=True):
    M = r11.build_all()
    add_main_booster(M)
    add_steam_vents(M)
    add_calf_jet(M, plates)
    for n in ("Pelvis", "Back", "UpperLegL", "UpperLegR", "LowerLegL", "LowerLegR"):
        M.parts[n].trim()
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    import check_model
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    LB = (0.55, 0.75, 0.85)
    rows = []
    for plates, name in ((False, "a 부스터만"), (True, "b 부스터 + 뒤판")):
        M = build_all(plates)
        print("==", name); check_model.check(M)
        B = M.blocks()
        ims = [(vp.render(B, PAL, EMISSIVE, yaw=180, pitch=6, ppc=2.5, ss=2, ao_amt=0.5, metal=METAL, light=LB), "뒤"),
               (vp.render(B, PAL, EMISSIVE, yaw=145, pitch=10, ppc=2.5, ss=2, ao_amt=0.5, metal=METAL, light=LB), "뒤 3/4"),
               (vp.render(B, PAL, EMISSIVE, yaw=90, pitch=4, ppc=2.5, ss=2, ao_amt=0.5, metal=METAL, light=(0.8, 0.3, 0.85)), "옆"),
               (vp.render(B, PAL, EMISSIVE, yaw=-30, pitch=6, ppc=2.5, ss=2, ao_amt=0.5, metal=METAL), "앞 3/4")]
        rows.append((name, ims))
    H = max(im.height for _, ims in rows for im, _ in ims)
    W = max(sum(im.width + 16 for im, _ in ims) for _, ims in rows)
    sh = Image.new("RGB", (W, 2 * (H + 44)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    for ri, (name, ims) in enumerate(rows):
        x = 0; y0 = ri * (H + 44)
        for im, t in ims:
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 8, y0 + H + 8), name + " · " + t, fill=(220, 220, 220), font=f)
            x += im.width + 16
    sh.save(os.path.join(out, "cetus_r12_compare.png")); print(sh.size)
