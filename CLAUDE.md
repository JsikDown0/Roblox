# CLAUDE.md

이 레포 = 로블록스 작업 두 갈래. 한국어로 답한다.
- `mech/` — **로봇 차기작(메카 대전, PlaceId 127133285131400 "Mech")**. 본 작업.
- `assets/pets/`, `tools/blender/` — 복셀 펫 테스트(bpy).

## 클라우드 세션에서
- Studio·Studio MCP·유저 PC 는 연결 안 됨 → 복셀 모델·렌더·검사·Lua 작성까지만. Studio 반영과 플레이 확인은 유저 몫.
- 준비: `bash mech/tools/setup_cloud.sh <작업폴더>` → `heavy/`(FELSEN·Aero·rig) · `skadi/` · `victory/` 평평한 폴더(`_r2` 접미사 뗀 이름)를 만든다.
  - 확인: `cd <작업폴더>/heavy && python3 check_model.py final_m2b` → 삼각형 32,662 · OK.
- 산출물(PNG·json)은 작업 폴더에서 만들고, 유저가 고른 것만 레포에 커밋.

## 작업 규칙 (자세한 건 문서)
- **새 기체·부위 디자인 전에 `mech/docs/기체디자인_스타일가이드.md` 를 읽는다.** 컨셉 아트가 있으면 6절(윤곽 읽기 먼저 확인받기).
- Studio 스크립트 분석·성능 측정 → `mech/studio/ANALYSIS.md` · `mech/studio/stress/README.md`.
- 머리 작업 → `mech/docs/VALKYRIE_머리_디자인기록_20261030.md` 5·6절.
- 동작 작업 → 스타일 가이드 5절(선례에서 출발 · 키 사이 구간까지 검사 · 키 시트 먼저 보내기).
- 칸 0.05, 머리 꼭대기 약 260칸, +X = 기체 왼쪽 · −Y = 정면 · +Z = 위. 색 번호 1~7 공통.
- 2~3안을 확정본과 나란히 보여 주고 고르는 건 유저. 버린 안도 새 이름으로 남긴다.
- 숫자로 검사: check_model(파트당 삼각형 1만 미만 · 섬 0), 색 면적.
- 근거 표기: `[결정]` 유저 확정 · `[실측]` · `[관찰]` · `[판단]`/`[제안]` Claude.

## 문서 지도 (`mech/docs/`)
| 문서 | 언제 |
|---|---|
| **`세션인계_20261105_양산형.md`** | **양산형(BISON · ZERDA) 이어서 할 때 먼저**: 지금 상태 · 다음 할 일(BISON 탱커 → ZERDA 스나이퍼 → ZERDA 지휘관) · 모듈화(`m2_frame.py`) · 명령 · 유저 선호 |
| **`결정기록_20261102.md`** | **최신 결정**: 4:4 거점전 · 뽑기/구매 해금 · 최대 3성 · FELSEN 시그니처 = 도끼 투척 · HT-02 CETUS · 지원기 APIS(7절) · **양산형 HT-10 BISON(8절, 옛 ST-10, 모델 `mech/models/BISON/`, 코드 `mech/code/mass/`)** · 새 표준 양산기 **ZERDA ST-10**(8-2·8-3절, 전신 확정 `mech/models/ST10/ST10_full.json`, 코드 `mech/code/mass2/`). 아래 문서와 겹치면 이게 우선 |
| `현재상태_20261026.md` | 최신 전체 상태(FELSEN·FALCO·카메라·HUD·게임 방향). 앞 문서 `_20261025`·`_20261024` 는 프로토 상세 |
| `저격기_현재상태_20261029.md` | LT-01 SKADI(6판 시안, 스킬, 남은 일) |
| `VALKYRIE_머리_디자인기록_20261030.md` | VALKYRIE 머리 r13 확정 · 교훈 |
| `컨텍스트_NOVA평가_메카헤드가이드_20261025.md` | 메카 머리 조사 · 체크리스트 |
| `대표기체_시안/` · `승리포즈/` · `flagship_tools/지침_병렬시안.md` | 시안 기록 · 승리 포즈 · 병렬 시안 지침 |

## 코드 (`mech/code/`, 원본 폴더 구조 그대로 — `README.txt`)
- 빠진 것: `valk_*`(VALKYRIE 머리 빌더), `ref/ref_mesh.npz`(SKADI Rodin 비교 → `present_full.py` 안 돌아감, 복셀만 렌더 가능), `pads`·`nova_mesh`·`bust` 모듈, rig json 들, `axe2h*`·`felsen_gatling*`·`mech_voxel.py`.
- `vox_preview.py` 는 `shadow_res`/`shadow_k` 인자 추가 전 판(VALKYRIE 때 추가한 판은 미포함).
- `[실측 11-01 클라우드]` SKADI `sniper_v2` check_model: ShoulderL/R 에 섬 2개씩(아직 고치지 않음).
