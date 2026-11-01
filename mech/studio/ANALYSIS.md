# 스크립트 분석 (2026-11-01, Mech.rbxlx 라이브 20개)

근거: 코드 읽기 `[실측: 코드]` · 추측은 `[추측]`. 줄 번호는 이 레포 `src/` 기준.

## 1. 큰 그림
- **판정 = 서버, 이동·물리 = 조종 클라 소유.** `board` 가 `player.Character = mech` + `root:SetNetworkOwner(player)` (MechServer 119–143).
- 스크립트끼리는 `require`(공유 모듈) + `_G`(`MechStartMelee`·`MechMeleeStrike`·`MechGrabFire`·`MechSetGun`).
- 원격은 전부 `MechProto.Remotes`. 서버→클라 = `MechFX` 하나에 종류 문자열(fire·missile·grab·melee·sfx…). **매 프레임 보내는 원격은 없음.**
- MechClient 는 local 200개·Source 20만 자 한도에 닿아 새 기능을 `GR` 표·자식 모듈(MechFalco·MechFelsen·MechPoses·MechHUD)로 뺀다.

## 2. MechServer 구간
출격대 `BAYS` 14–42 · 탑승/하차 66–143 · `spawnMech`·보급 145–218 · 조준·장전·점프 245–290 · 사격 292–402 · 부스트 404–431 · 미사일·그레네이드 433–686 · 개틀링 688–700 · 작살 그랩 702–862 · 지뢰 863–979 · 앵커 981–1006 · 궁극기 1008–1452 · 라이더킥 1454–1569 · 근접 1587–1777 · 무장 교체 1779–1860 · 에너지 1862–1897 · 시험장 1904–

## 3. MechClient 구간
상태·JOINTS 1–117 · VFX 120–203 · 탑승/하차 209–306 · 미사일 317–444 · 손목 런처 446–482 · 지뢰 483–546 · 궁극기 547–739 · FELSEN 개틀링·그랩·앵커 741–1084 · 부스트 1086–1174 · 근접 1176–1473 · 입력 1475–1536 · 사출 1551–1823 · 카메라·이동·사격·HUD 1826–2158 · 원격 사격 FX 2160 · **애니 2175–2782** · 사출장 FX 2784–

## 4. 애니메이션
- `Motor6D.Transform` 만 씀(C0 안 건드림). `RenderStepped`(2771)에서 기체마다 `pcall(animOne)`, 끝에 JOINTS 27개 중 있는 관절 전부를 매 프레임 씀(Heavy 21개).
- **대상 = 모든 기체**: 태그 `Mech` + `MechDisplay`(2186). 남의 기체·적·빈 주차 기체·전시 기체 모두 같은 전체 경로. 거리 컬링·LOD 없음.
- 남의 기체 자세 = 속성(AimPitch·AimYaw·AimZoom·MeleeAt·Weapon…) + `AssemblyLinearVelocity`.
- 기체·프레임마다 표·CFrame 할당 다수, `CFG.gun(m)` 5회 이상, 0.5초마다 없는 관절 재귀 재탐색(2212–2221). 줌·허리 사격이면 IK(`twoHandPose`) 매 프레임.
- 다른 RenderStepped 루프들이 각자 매 프레임 `GetTagged` → 프레임당 배열 약 10개 할당.

## 5. 기체 종류
- 속성 `MechType` → 클라 `SHAPES[t]`(MechPoses, Aero←Heavy, Horkos·Skadi←Aero 상속) · `CFG.Types[t]`.
- 기능 = 문자열 속성 `Gun`·`Signature`·`Ultimate`·`SubWeapon`·`Melee` + 관절 유무.
- `CFG.Types`: (프로토) · Heavy · Aero · Horkos · Skadi. **HP 1000 전 기체 같음.** HP·점프·부스트 비용/쿨은 `CFG.stat` 을 안 거쳐 기체별로 못 바꿈(MechServer 157·158·425–430).
- **SAVIOR 추가에 필요한 것**: 템플릿(관절 이름 규약, Rifle/Muzzle, RifleStowed, HRP+BoardPrompt, 속성) · `BAYS` 블록 · `CFG.Types.Savior` · `SHAPES.Savior` · 새 기술마다 원격+서버 핸들러+`ULT.kinds`+`*Phase`+`stunned`/`superArmor`+`park` 지울 속성 목록+클라 입력 분기·HUD·자식 모듈.

## 6. 4v4(8명+)를 막는 것
1. **`CFG.MaxMechs = 6`**(MechConfig 103) — 적·버린 기체·파괴 중 기체까지 셈(MechServer 147–148). 처음에 적 1 + 출격대 4 = 5 → 약 5명 넘게 기체를 못 받음. **버린 기체를 치우는 코드 없음.**
2. **팀 없음**: `MechDamage.teamOf`(속성 Team → Player.Team) 자리만 있고 정하는 곳 없음 → 모두 FFA. 출격대·리스폰·적 AI 도 팀 모름.
3. 애니 비용이 기체 수에 비례(컬링 없음) → **MechStress 로 측정**.
4. 원격 사격 FX: 한 발마다 받는 클라마다 파트 약 7개 + 트윈. 개틀링 1정 ≈ 클라당 초당 126파트.
5. 서버: 사격마다 레이캐스트 + FireAllClients, 미사일 발마다 Heartbeat 레이캐스트 + 전 기체 순회, 지뢰 × 기체 매 프레임, 에너지 10Hz 속성 복제, `SM.play` 거리 무관 전원 전송.

## 7. 보안(클라 믿음)
- 이동 검증 없음(순간이동·속도 핵, 끌림·넉백 무시 가능).
- 사격 원점: `gunReach + 속도×0.15` 안이면 클라 총구를 믿음(MechServer 371) — 속도를 부풀리면 반경이 커짐.
- 돌진 slam 약 90스터드(1411–1414)·라이더킥 hit 약 93스터드(1544–1545)를 시야 검사 없이 받음.
- 사격 허용각 `FireArc + 20 = 140°`(380). MechAim 서버 빈도 제한 없음.

## 8. 버그·정리 후보
- 근접 판정이 `task.delay` 예약이라 누른 뒤 내려도 나감(MechServer 1733).
- 미사일 유도·스플래시가 빈 주차 기체도 잡음(624, 498).
- SkadiTemplate 에 `RifleStowed`/`Backpack` 없음 → 거치대 총 교체 조용히 실패(1814).
- MechServer 가 `MechTemplate` 을 `WaitForChild` 로 꼭 기다림(11) — 없으면 멈춤.
- 클라: `meleeHold`(1218) 강한 키라 지우지 않음(누수) · `updateWeaponHUD()` 한 프레임 2번(2139·2156) · 덮개 관절 재귀 탐색 매 프레임(735) · `exclude()`·`worldParams()` 가 RaycastParams 를 매번 새로 · 사출장 셔틀 `followS` 동시 사출 시 덮어씀(2865) `[추측: 동시 출격 시]`.
- 약한 키 표(`animState` 등): 코드 주석에 에디트 실측으로 0.5초 안에 비었다는 기록(487–489, 553) → 남의 기체 상태 리셋 가능 `[추측: 플레이 확인 필요]`.
