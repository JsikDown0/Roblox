# FALCO(MechType "Aero") 비행 형태 — FalcoJet

변신 = 교체형 + 짧은 전조(C안 `[결정]`). 이 폴더 = 모델 · 부착점 · 이름까지. 코드 연결(변신 연출 · 이동 · 무장)은 다른 세션.

| 파일 | 내용 |
|---|---|
| `FalcoJet_r1_20261106.glb` | 메시 8개(X_JetBody · X_JetCockpit · X_JetWingL/R · X_JetTailL/R · X_JetCanardL/R), 삼각형 8,998, 팔레트 UV = 인간형과 같은 배치 |
| `FalcoJet_r1_20261106_parts.json` | 파트 크기·가운데·피벗 · 부착점 · 판정 상자 · 무게 중심 (템플릿 스터드, 원점 = HRP 중심) |
| `falco_jet_build.lua` | Studio 명령 바 조립 → `ReplicatedStorage.MechProto.FalcoJet` |

## Studio 순서
1. glb 를 3D 가져오기로 workspace 에 넣는다(이름 `FalcoJet_r1_20261106` 그대로).
2. `falco_jet_build.lua` 전체를 명령 바에 붙여 실행 → 보고 문자열(크기·부착점 월드 위치)이 출력창에 나온다.
   - AeroTemplate 은 읽기만(Torso 의 SurfaceAppearance · 재질, Flame, GlowLight 복제). 이전 FalcoJet 은 `ServerStorage._FalcoJet_before_<시각>` 으로 옮김(지우지 않음). 가져온 원본은 `ServerStorage._Import_FalcoJet_r1_20261106`.
   - 가져오기 축이 예전(10-26 AELLO)과 다르면 assert 로 멈춤 → 메시지를 그대로 전달.

## 규약
- 축: 앞 −Z · 위 +Y · +X = 기체 오른쪽(인간형 템플릿과 같음). 모든 MeshPart 회전 0(꼬리 기울기는 메시에 구움).
- 부착점 축 = 모델 축 → 총구·미사일은 −Z, 노즐 분사는 +Z(Flame.EmissionDirection = Back, Enabled = false 로 넣음). 속성 `FireDir` 에 방향 표기.
- 날개·꼬리·카나드·조종석 `PivotOffset` = 뿌리(나중에 Motor6D 로 바꿀 때 축 자리). 동체 PivotOffset = 원점 → `FalcoJet:GetPivot()` = HRP 자리.
- 원본 코드: `mech/code/falco_jet/jet_r1.py`(복셀) · `jet_export.py`(glb·json·lua) · `jet_sheet.py`(시트 `mech/docs/레퍼런스/FALCO/시안_FalcoJet_r1.png`).
