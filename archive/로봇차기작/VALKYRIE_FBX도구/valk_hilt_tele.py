"""valk_hilt_tele.py — 11-04 19:14 유저 "A로 가자": 칼 모드에서 칼등(가드 앞 하우징)의 앞쪽 절반이 가드 쪽으로 미끄러져 들어감(총 모드에선 뻗어 총열).
  valk_hilt2 의 HiltGuard · HiltBarrel 을 z(칼끝 −) 로 자름: CUT = −26 (하우징 −50 ~ −1 의 앞 절반 · 미끄러짐 24칸 = 2.4 스터드)
    VBladeGuard(새) = HiltGuard z ≥ CUT+1 · VBladeTip = HiltGuard z ≤ CUT + HiltBarrel z ≤ CUT(총구 포함) · VBladeBarrel(새) = HiltBarrel z ≥ CUT+1
    Ref_Guard · Ref_Barrel = 옛 메시 그대로(가져온 뒤 Studio 의 옛 VBladeGuard/VBladeBarrel 에 맞춰 자리를 잡는 기준 — 맞춘 뒤 지움)
  python3 valk_hilt_tele.py → out/export/ValkyrieBladeTele_20261104.glb"""
import io, contextlib, numpy as np
with contextlib.redirect_stdout(io.StringIO()):
    import valk_hilt2 as HL
import export_valk as EV
CUT = -26
SLIDE = 24
M, h = HL.build()
g, b = M.parts["HiltGuard"], M.parts["HiltBarrel"]
def sub(p, keep):
    a = p.a.copy(); z = np.arange(p.a.shape[2]) + p.lo[2]
    a[:, :, ~keep(z)] = 0
    return a
pieces = {
    "Ref_Guard": [(g, lambda z: z == z)], "Ref_Barrel": [(b, lambda z: z == z)],
    "VBladeGuard": [(g, lambda z: z > CUT)], "VBladeBarrel": [(b, lambda z: z > CUT)],
    "VBladeTip": [(g, lambda z: z <= CUT), (b, lambda z: z <= CUT)],
}
parts = []
for name, srcs in pieces.items():
    lo = np.min([s.lo for s, _ in srcs], 0); hi = np.max([np.array(s.lo) + np.array(s.a.shape) - 1 for s, _ in srcs], 0)
    q = M.part(name, tuple(lo), tuple(hi + 1), pivot=g.pivot)
    for s, keep in srcs:
        a = sub(s, keep); ijk = np.argwhere(a > 0)
        q.a[tuple((ijk + s.lo - q.lo).T)] = a[tuple(ijk.T)]
    q.trim()
    V, N, UV, I, nq = EV.part_mesh(q, M.world(name))
    parts.append((name, V, N, UV, I))
    print(name, "칸", int((q.a > 0).sum()), "삼각형", len(I) // 3)
EV.write_glb("out/export/ValkyrieBladeTele_20261104.glb", parts, dict(HL.PAL), "ValkBladePaletteMat")
print("ok")
