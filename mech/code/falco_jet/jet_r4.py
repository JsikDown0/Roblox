"""
jet_r4.py — FalcoJet r4 = r3 에서 윗면 흰 판·주황 조각만 r2 로 되돌림 (2026-11-06)
유저(r3 평): "몸 위 흰 판들은 이전으로 되돌려줘. 지저분해 보여" → 흡기구 겹 · 주황 발톱 · 안쪽 포드 계단 앞 = r3 그대로,
윗면(척추 2번째 판 · 엔진 사이 판 · 엔진 위 2장 · 뒤 덮개 위 판 · 날개 뿌리 위 판 · 그 옆 주황 조각 · V 팔 끝 주황 마개) = r2(S 판 1 + 엔진 위 1장씩).
"""
import jet_r3 as R3

TAG = "FalcoJet_r4_20261106"
HERE, Mm, T, STUD, HRP = R3.HERE, R3.Mm, R3.T, R3.STUD, R3.HRP
attachments, hitbox, stats, world_cells = R3.attachments, R3.hitbox, R3.stats, R3.world_cells


def build_all():
    old = R3.TOP_PLATES
    R3.TOP_PLATES = False
    try:
        return R3.build_all()
    finally:
        R3.TOP_PLATES = old


if __name__ == "__main__":
    import json
    import check_model as C
    M = build_all()
    C.check(M)
    print(json.dumps({k: v for k, v in stats(M).items() if k != "parts"}, ensure_ascii=False))
