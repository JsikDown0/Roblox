"""APIS 머리 r2 (다시) — 윤곽 읽기 r3 기준, 비율 3안 (2026-11-02)

[결정 11-02] r3 답: ① 귀 원반 가운데 청록 = 빛남 ② 곰 귀 혹 = 뺌 ③ 웃는 표정 = 인게임에서 따로 그림
 → 바이저는 평평한 화면 한 장(따로 파트 "Visor")으로 두고, 표정은 게임에서 SurfaceGui/데칼로 그림(표정 바꾸기 가능).
머리 = 납작하고 앞뒤로 긴 쐐기: 코끝(앞)이 낮고 뒤로 갈수록 높음.
 H2 가운데 흰 판(정수리 앞 → 코끝) + 통풍구 · H3 양옆 노랑 껍데기(바이저 끝으로 비스듬히) · H4 바이저 화면 · H5 짙은 주둥이 2단 · H6 귀 원반.
비율 3안: A 읽은 그대로(앞 21 → 뒤 31 · 길이 35) · B 더 납작·길게(17 → 27 · 38) · C 덜 기울게·짧게(21 → 28 · 32).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))
import flag_vox as fv  # noqa: E402
from flag_vox import cbox, cyl, box  # noqa: E402
import apis_r1 as r1  # noqa: E402

PAL, EMISSIVE = r1.PAL, r1.EMISSIVE
VARS = {"A": dict(hf=21, hb=31, L=35), "B": dict(hf=17, hb=27, L=38), "C": dict(hf=21, hb=28, L=32)}
ZB = 225          # 머리 밑면
W2 = 12.5         # 반폭


def build_head(M, hf, hb, L):
    M.parts.pop("Head", None); M.parts.pop("Visor", None)
    yf = -20; yb = yf + L
    H = M.part("Head", (-20, yf - 6, 216), (21, yb + 3, ZB + hb + 4), pivot=(0, -2, r1.NECK_Z), parent="Torso")
    G = H.g(); X, Y, Z = G; ax = np.abs(X)
    k = np.clip((Y - yf) / float(L), 0, 1)
    ztop = ZB + hf + (hb - hf) * np.sqrt(k)                                     # 앞 낮고 뒤로 갈수록 높아짐(볼록)
    yface = yf + 2                                                               # 얼굴 앞면
    shell = (X == X) & (Y >= yface) & (Y <= yb) & (Z >= ZB) & (Z <= ztop)
    shell &= ax <= W2 - np.maximum(0, Z - (ztop - 7)) * 0.9                      # 윗모서리 둥글게
    shell &= Y <= yb - np.maximum(0, Z - (ZB + hb - 12)) * 0.7 - np.maximum(0, ZB + 6 - Z) * 0.8   # 뒤통수 둥글게
    H.add(shell, 1)
    H.add(cyl(G, "z", (0, 3), 9, rng=(219, ZB + 1)), 3)                          # 목
    # H2 흰 판: 윗면 가운데 띠(1칸 돋움) → 앞으로 튀어나온 흰 코끝(앞면 위쪽)
    top = (ax <= 6) & (Y <= yb - 9) & (Z >= ztop - 1) & (Z <= ztop + 1)
    H.add(top & (Y >= yface), 2)
    vz0, vz1 = ZB + 9, ZB + 12                                                   # 바이저 높이(가는 띠)
    nose = (ax <= 8 - np.maximum(0, (vz1 + 2) - Z) * 0) & (Y >= yf - 3 + np.maximum(0, (vz1 + 4) - Z) * 1.0) & (Y <= yface + 3) & (Z >= vz1 + 1) & (Z <= ZB + hf + 1)
    nose &= ax <= 8 - np.maximum(0, Z - (ZB + hf - 2)) * 1.5
    H.add(nose, 2)
    H.paint(shell & (Y <= yface + 1) & (Z > vz1) & (ax <= 8), 2)
    H.groove(box(G, x=(-3, 3), y=(yf - 4, yf), z=(ZB + hf - 5, ZB + hf - 4)), 4)   # 통풍구
    # H3 양옆 노랑 눈썹판: 흰 코 양옆, 바이저 끝으로 비스듬히 내려옴(1칸 돋움)
    brow = (ax >= 7) & (ax <= W2) & (Y >= yface - 1) & (Y <= yface) & (Z >= vz1 + 1 - (ax - 7) * 0.5) & (Z <= ZB + hf - (ax - 7) * 0.4)
    H.add(brow, 1)
    # H4 바이저 자리: 앞면 띠를 3칸 파고, 양옆으로 감김
    wrap = np.maximum(0, ax - 8) * 1.3
    slot = (ax <= W2) & (Z >= vz0) & (Z <= vz1) & (Y <= yface + 2 + wrap) & (Y >= yf - 4)
    H.cut(slot & ~nose)
    H.add((ax <= W2 - 0.5) & (Z >= vz0) & (Z <= vz1) & (Y >= yface + 3 + wrap) & (Y <= yface + 4 + wrap), 3)   # 바이저 뒤 벽
    # H5 짙은 주둥이 2단(바이저 밑, 앞으로 나옴)
    H.cut(shell & (Z <= vz1) & (Y <= yf + 11))                                   # 아래 앞(옆까지)은 바이저·주둥이 자리 — 옆에서도 보이게
    H.add(cbox(G, (-12, 12), (yf - 2, yf + 14), (ZB + 3, vz0 - 1), {"xz": 3, "-y-z": 3, "-y+z": 1}), 3)   # 윗단
    H.add(cbox(G, (-9, 9), (yf, yf + 12), (ZB - 3, ZB + 2), {"xz": 2, "-y-z": 3}), 3)                     # 아랫단
    H.groove(box(G, x=(-11, 11), y=(yf - 3, yf + 2), z=(ZB + 2, ZB + 2)), 4)
    H.add((ax <= W2 - 3) & (Y >= yf + 6) & (Y <= yf + 12) & (Z >= ZB) & (Z <= vz1) & ~(H.a > 0), 3)   # 바이저·주둥이 뒤 짙은 심
    # H6 귀 원반(짙은 고리 + 가운데 청록 발광, 1칸 오목) [결정: 빛남]
    for s_ in (1, -1):
        H.add(cyl(G, "x", (yf + 17, ZB + 13), 6.5, rng=(s_ * (W2 - 1), s_ * (W2 + 3))), 3)
        H.groove(cyl(G, "x", (yf + 17, ZB + 13), 3.2, rng=(s_ * (W2 + 2), s_ * (W2 + 4))), 6)
    H.trim()
    # 바이저 화면(따로 파트, 2칸 두께라 끊기지 않음): 게임에서 표정 그림을 올림
    V = M.part("Visor", (-14, yf - 2, vz0 - 1), (15, yf + 20, vz1 + 2), pivot=(0, yf + 4, (vz0 + vz1) / 2.0), parent="Head")
    G = V.g(); X, Y, Z = G; ax = np.abs(X)
    wrap = np.maximum(0, ax - 8) * 1.3
    V.add((ax <= W2 - 0.5) & (Z >= vz0) & (Z <= vz1) & (Y >= yface + 1 + wrap) & (Y <= yface + 3.6 + wrap) & (ax <= W2), 6)
    V.trim()
    return H, V


def build_all(var="A"):
    M = r1.build_all()
    build_head(M, **VARS[var])
    return M


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    from PIL import Image, ImageDraw, ImageFont
    import vox_preview as vp
    from scipy import ndimage
    from check_model import greedy_quads
    f = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 20)
    t = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "지원기", "concept_v1_삼면도.webp")).convert("RGB")
    a = Image.open(os.path.join(HERE, "..", "..", "docs", "레퍼런스", "지원기", "concept_v1_수리장면.webp")).convert("RGB")
    rows = []
    for key in VARS:
        M = build_all(key)
        for n in ("Head", "Visor"):
            p = M.parts[n]; _, kk = ndimage.label(p.a > 0)
            print(key, n, "tris", 2 * greedy_quads(p.a), "섬", kk - 1)
        B = M.blocks(skip=[n for n in M.parts if n not in ("Head", "Visor")])
        ims = [vp.render(B, PAL, EMISSIVE, yaw=y, pitch=p, ppc=9, ss=2, ao_amt=0.5) for y, p in ((0, 4), (-35, 10), (-90, 2), (-150, 12))]
        rows.append((key, ims))
    H = max(i.height for _, ims in rows for i in ims)
    refs = [t.crop((220, 125, 335, 245)), t.crop((600, 125, 730, 245)), a.crop((660, 80, 880, 270))]
    refs = [r.resize((int(r.width * H / r.height), H)) for r in refs]
    W = max(sum(i.width + 16 for i in ims) for _, ims in rows)
    W = max(W, sum(r.width + 16 for r in refs))
    sh = Image.new("RGB", (W, (len(rows) + 1) * (H + 40)), (18, 19, 22)); d = ImageDraw.Draw(sh)
    x = 0
    for r, lab in zip(refs, ("원본 삼면도 앞", "원본 삼면도 옆", "원본 수리 장면")):
        sh.paste(r, (x, 0)); d.text((x + 8, H + 6), lab, fill=(220, 220, 220), font=f); x += r.width + 16
    for ri, (key, ims) in enumerate(rows):
        y0 = (ri + 1) * (H + 40); x = 0
        for im, lab in zip(ims, ("정면", "앞 3/4", "옆", "뒤 3/4")):
            sh.paste(im, (x, y0 + H - im.height)); d.text((x + 8, y0 + H + 6), "%s %s · %s" % (key, {"A": "읽은 비율", "B": "더 납작·길게", "C": "덜 기울게"}[key], lab), fill=(220, 220, 220), font=f)
            x += im.width + 16
    sh.save(os.path.join(out, "apis_head_r2.png")); print(sh.size)
