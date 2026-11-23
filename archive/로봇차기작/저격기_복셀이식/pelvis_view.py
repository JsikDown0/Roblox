"""고간부 확대 — Rodin / 복셀 (앞 · 앞3/4 · 옆 · 아래3/4)."""
import sys
sys.path.insert(0, '/home/claude/sniper')
import sniper_v2 as S, cmp, head_view as HV
box = ((-28, 28), (-32, 18), (138, 212))
HV.box = box
HV.views = [(0, 4, '앞'), (35, 8, '앞 3/4'), (90, 3, '옆'), (25, -25, '아래 3/4')]


def rows(variants, ppc=7.0, ref=("Pelvis", "UpperLegL", "UpperLegR", "Torso")):
    out = []
    for name, fn in variants:
        M = S.build_all()
        if fn: fn(M)
        B = M.blocks(); rr, oo = [], []
        for y, p, lab in HV.views:
            r, o = cmp.pair(B, box, y, p, ppc, list(ref), lab)
            rr.append(r); oo.append(o)
        if not out: out.append(("Rodin", rr))
        out.append((name, oo))
    return out

if __name__ == '__main__':
    HV.save(rows([("지금", None)]), sys.argv[1])
