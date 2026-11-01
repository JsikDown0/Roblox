"""final_m2b.py — 중장갑 r2 최종본(2026-10-26): 머리 U2(뿔 20) + 흉부 안 1(H1) + 허리 W2 + 하체 M2b
  + 손보기(02:16): 섬 정리 · 옆/앞 스커트 八 · 백팩 BP1(노즐 4개 + 빔사벨 랙 2개, 노즐 둘레 흰색).
  python3 final_m2b.py OUTDIR   → 4면 시트(A 색), 3/4 색 3종, 모델 json, 검사 결과
build_all() = 확정 모델(check_model.py 로도 검사 가능)."""
import sys, time
import numpy as np
import flagship_heavy as fh
import back_heavy as bh


def build_all():
    return bh.build("8", "BP1")


if __name__ == "__main__":
    from PIL import Image
    import vox_preview as vp
    import check_model as cm
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    t0 = time.time()
    M = build_all()
    B = M.blocks(pose=fh.STANCE)
    views = ((0, 4, "front"), (30, 6, "3/4"), (90, 2, "side"), (150, 12, "back 3/4"))
    ims = [vp.render(B, fh.SCHEMES["A"], fh.EMISSIVE, yaw=y, pitch=p, ppc=2.7, ss=2, ao_amt=0.5) for y, p, _ in views]
    vp.sheet(ims, [v[2] for v in views]).save(out + "/heavy_r2_final_views_A.png")
    print("views %.1fs" % (time.time() - t0), flush=True)
    names = {"A": "A ivory / graphite / orange", "B": "B sand / umber / amber", "C": "C gunmetal / black / red"}
    cols = [vp.render(B, fh.SCHEMES[k], fh.EMISSIVE, yaw=30, pitch=6, ppc=2.4, ss=2, ao_amt=0.5) for k in "ABC"]
    vp.sheet(cols, [names[k] for k in "ABC"]).save(out + "/heavy_r2_final_colors.png")
    print("colors %.1fs" % (time.time() - t0), flush=True)
    M.save(out + "/heavy_r2_final.json")
    cm.check(M)
    print("done %.1fs" % (time.time() - t0))
