"""회귀 검사 — 코드를 정리(모듈화)한 뒤 모델이 칸 하나까지 같은지 확인.
  저장: python3 m2_regress.py save <ref.npz> [모듈 함수]      (기본 m2_knife_r1 build_final = ZERDA 최종)
  비교: python3 m2_regress.py cmp  <ref.npz> [모듈 함수]      → "다른 파트 0 / N" 이면 같음
파트마다 칸 배열 · lo · 피벗 · rot · 부모를 비교한다. ref.npz 는 작업 폴더(scratchpad)에 둔다(레포에 넣지 않음)."""
import importlib
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "flagship_tools"))


def build(mod="m2_knife_r1", fn="build_final"):
    return getattr(importlib.import_module(mod), fn)()


def save(path, M):
    d = {}
    for n, p in M.parts.items():
        d[n + "|a"] = p.a; d[n + "|lo"] = np.array(p.lo); d[n + "|pv"] = np.array(p.pivot, float)
        d[n + "|rot"] = np.array(p.rot); d[n + "|par"] = np.array(str(p.parent))
    np.savez_compressed(path, **d)
    print("저장", path, len(M.parts), "파트")


def cmp(path, M):
    R = np.load(path); names = sorted({k.split("|")[0] for k in R.files}); bad = 0
    for n in names:
        if n not in M.parts:
            print("없음", n); bad += 1; continue
        p = M.parts[n]
        same = (R[n + "|a"].shape == p.a.shape and (R[n + "|a"] == p.a).all() and (R[n + "|lo"] == np.array(p.lo)).all()
                and np.allclose(R[n + "|pv"], p.pivot) and np.allclose(R[n + "|rot"], p.rot) and str(R[n + "|par"]) == str(p.parent))
        if not same:
            bad += 1; print("다름", n, R[n + "|a"].shape, p.a.shape, int((R[n + "|a"] > 0).sum()), int((p.a > 0).sum()))
    print("추가 파트", [n for n in M.parts if n not in names], "| 다른 파트", bad, "/", len(names))
    return bad


if __name__ == "__main__":
    act, path = sys.argv[1], sys.argv[2]
    M = build(*sys.argv[3:5]) if len(sys.argv) > 3 else build()
    (save if act == "save" else cmp)(path, M)
