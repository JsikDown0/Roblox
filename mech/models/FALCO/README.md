# FALCO(MechType "Aero") 비행 형태 — FalcoJet

변신 = 교체형 + 짧은 전조(C안 `[결정]`). 이 폴더 = 모델 · 부착점 · 이름까지. 코드 연결(변신 연출 · 이동 · 무장)은 다른 세션.

| 파일 | 내용 |
|---|---|
| **`FalcoJet_r2_20261106.glb`** (현재) | 유저 컨셉 c1 기준(`docs/레퍼런스/FALCO/concept_jet_c1.png` · `윤곽읽기_jet_r1.png`, `[결정 11-06 "이대로 · 제안값"]`). 메시 6개(X_JetBody · X_JetCockpit · X_JetWingL/R · X_JetTailL/R), 삼각형 5,200. 카나드 없음 |
| `FalcoJet_r1_20261106.glb` (버린 안) | 첫 시안 — 유저 "너무 육중 · 우주왕복선 같음". 메시 8개, 삼각형 8,998 |
| `FalcoJet_r2_20261106_parts.json` (r1 도 같은 형식) | 파트 크기·가운데·피벗 · 부착점 · 판정 상자 · 무게 중심 (템플릿 스터드, 원점 = HRP 중심) |
| `falco_jet_build.lua` | Studio 명령 바 조립 → `ReplicatedStorage.MechProto.FalcoJet` (지금 = r2 데이터) |

## Studio 순서
1. r2 glb 를 3D 가져오기로 workspace 에 넣는다(이름 `FalcoJet_r2_20261106` 그대로).
2. `falco_jet_build.lua` 전체를 명령 바에 붙여 실행 → 보고 문자열(크기·부착점 월드 위치)이 출력창에 나온다.
   - AeroTemplate 은 읽기만(Torso 의 SurfaceAppearance · 재질, Flame, GlowLight 복제). 이전 FalcoJet 은 `ServerStorage._FalcoJet_before_<시각>` 으로 옮김(지우지 않음). 가져온 원본은 `ServerStorage._Import_FalcoJet_r1_20261106`.
   - 가져오기 축이 예전(10-26 AELLO)과 다르면 assert 로 멈춤 → 메시지를 그대로 전달.

## 규약
- 축: 앞 −Z · 위 +Y · +X = 기체 오른쪽(인간형 템플릿과 같음). 모든 MeshPart 회전 0(꼬리 기울기는 메시에 구움).
- 부착점 축 = 모델 축 → 총구·미사일은 −Z, 노즐 분사는 +Z(Flame.EmissionDirection = Back, Enabled = false 로 넣음). 속성 `FireDir` 에 방향 표기.
- 날개·꼬리·카나드·조종석 `PivotOffset` = 뿌리(나중에 Motor6D 로 바꿀 때 축 자리). 동체 PivotOffset = 원점 → `FalcoJet:GetPivot()` = HRP 자리.
- 원본 코드: `mech/code/falco_jet/jet_r2.py`(복셀, r1 = `jet_r1.py`) · `jet_export.py OUT jet_r2`(glb·json·lua) · `jet_sheet_r2.py`(시트 `docs/레퍼런스/FALCO/시안_FalcoJet_r2.png`) · 윤곽 읽기 `jet_read_r1.py`.
- r2 답: 뒷전 곧게 · P = 미사일 포드(1·3 = 흡기구 밑 JetBody, 2·4 = 날개 밑) · K = 기관포 · 날씬한 몸(HRP 는 위아래로 튀어나옴 → 판정은 JetHitBox) · 가운데 엔진 = 발광만 · 발광은 홈 속 · 상반각 0(`jet_r2.DIHEDRAL`).
