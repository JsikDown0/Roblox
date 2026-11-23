"""저격기 기본 사격 자세(두 손 견착) 보기 — 앞3/4 · 옆 · 앞 · 뒤3/4 + 상체 확대."""
import sys, time, numpy as np
sys.path.insert(0, '/home/claude/sniper')
from PIL import Image
import sniper_aim as A, rifle_view as RV

TW, BUTT_T, SUP = -35, (-12, -30, 222), (24, -10, 6)

if __name__ == '__main__':
    t0 = time.time()
    M = A.build()
    P, info = A.solve(M, A.stance(TW), butt_t=BUTT_T, support=A.rest_pt(*SUP), starts=12)
    print(info, round(time.time() - t0, 1), flush=True)
    B = M.blocks(pose=P)
    lo, hi = np.array([-70, -200, -4]), np.array([70, 60, 272])
    r1 = [RV.tile(B, y, p, 2.0, lo, hi, lab) for y, p, lab in ((325, 6, '사격 앞 3/4'), (270, 3, '사격 옆'), (0, 4, '사격 앞'), (150, 10, '뒤 3/4'))]
    ulo, uhi = np.array([-60, -150, 150]), np.array([60, 40, 272])
    r2 = [RV.tile(B, y, p, 3.4, ulo, uhi, lab) for y, p, lab in ((320, 14, '상체 3/4'), (250, 4, '상체 옆'), (20, 30, '위에서'))]
    rows = [RV.row(r1, 640), RV.row(r2, 520)]
    Wd = max(r.width for r in rows)
    S = Image.new('RGB', (Wd, sum(r.height for r in rows)), RV.BG); y = 0
    for r in rows: S.paste(r, (0, y)); y += r.height
    S.save(sys.argv[1], quality=90); print(S.size, round(time.time() - t0, 1))
