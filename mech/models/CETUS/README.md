# HT-02 CETUS 모델 파일 (flag_vox/1 JSON)

| 파일 | 내용 | 삼각형 | 쓰임 |
|---|---|---|---|
| `CETUS_full.json` | 원래 해상도 원본(칸 0.05) · 24 파트 · 섬 0 | 146,676 | 보관 · 2D 카드 그림/아이콘 렌더 |
| `CETUS_half.json` | **절반 해상도 정리판**(2×2×2 칸 → 1칸, 원래 격자에 2배로 저장) · 24 파트 · 섬 0 · 파트당 1만 미만 | 49,614 | **게임(전투·뽑기 화면 모두)** |

- 만드는 코드: `mech/code/cetus/cetus_half.py`(→ `cetus_final.py` → `cetus_r12.py` …). 다시 만들기:
  `cd mech/code/cetus && PYTHONPATH=../flagship_tools python3 cetus_half.py <그림 폴더> ../../models/CETUS`
- 불러오기: `flag_vox.Model.load(path)` — 파트마다 lo/hi/pivot/parent/rot + 색 칸 런.
- 관절 계층: Pelvis(뿌리) → Torso → Head · Collar · ShoulderL/R(→ ShoulderBaseL/R) · UpperArmL/R → LowerArmL/R(→ ClawL · DrillR) · Back / Pelvis → BoosterMain · UpperLegL/R → LowerLegL/R(→ KneeL/R) → FootL/R.
- 색 번호: 1 청록 · 2 뼈색 · 3 짙은 쇠 · 4 검정 홈 · 5 황동(금속 재질) · 6 발광 · 7 강철 · 8 궁극기 유리(드릴 이음새) · 9 밧줄 갈색 · 10 궁극기 줄(가슴 세로 홈). 8·10 은 평소 어두운 색, 궁극기 때 호박 발광. 9·10 은 공용 팔레트에 없는 새 칸.
- 게임에서 붙일 자리: DrillR(궁극기 회전) · ClawL(집게 발사) · BoosterMain 노즐 2(주부스터 불꽃) · Back 기둥 아래 나팔 2(증기) · 종아리 노즐(보조 불꽃).
