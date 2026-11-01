# MechStress — 4v4+ 성능 측정

기체 여러 대를 띄워 **실제 게임 코드 경로**로 부하를 걸고 FPS·메모리를 잰다.
- 복제 기체에 태그 `MechDisplay` → MechClient 가 진짜 애니(관절 Transform·IK·불꽃)로 그림. 서버 로직(보급·`MaxMechs`·미사일·적 AI)은 `Mech` 태그만 보므로 영향 없음.
- 서버가 `Humanoid:Move` 로 원을 따라 걷게 함(MechEnemy 와 같은 방식) → 걷기 자세 경로.
- 조준: `AimPitch/AimYaw` 10Hz 갱신 + 3초마다 `AimZoom`(두 손 IK 경로).
- 사격: 실제 `MechFX "fire"` 를 모든 클라에 보냄 → 탄도선·총구 불꽃·불꽃 튐·소리. HeavyTemplate 은 개틀링(1/18초)이라 최악 조건에 가깝다. 2초 쏘고 1초 쉼.

## 넣는 법
1. `MechStressServer.server.luau` 내용 → **ServerScriptService** 에 Script `MechStressServer`
2. `MechStressClient.client.luau` 내용 → **StarterPlayer > StarterPlayerScripts** 에 LocalScript `MechStressClient`
3. 플레이(F5) → 왼쪽 위 패널. 기체는 내 앞 170스터드에 반지름 110 원으로 생김(`중심 다시` 로 옮김).

## 측정
- **자동 측정** 버튼: 0 → 2 → 4 → 6 → 8 → 10 → 12대, 단계마다 4초 안정 + 10초 측정 → **출력(Output) 창에 결과 표**. 그 표를 그대로 복사해 주면 된다.
- 권장 3회:
  1. PC · 걷기+조준(사격 끔)
  2. PC · 걷기+조준+사격
  3. 모바일(실기기, Studio 기기 에뮬레이터 말고) · 걷기+조준+사격 — 게시된 플레이스에서
- 시험 중 화면: 기체들이 화면 안에 보이게 서 있기(안 보이면 그리기 비용이 빠진다).
- 섞인 기체로 재려면 서버 스크립트 맨 위 `Templates` 를 `{ "HeavyTemplate", "AeroTemplate", "SkadiTemplate", "HorkosTemplate" }` 로.

## 빠지는 것(이 측정이 못 보는 비용)
- 플레이어 수만큼의 네트워크(이동 복제·MechAim)와 서버 판정 — 봇은 서버 물리라 실제 8명 접속보다 가볍다.
- 미사일·궁극기·근접 이펙트, 맵 크기. 내 기체 조종(카메라 레이캐스트 등) 비용은 탑승하면 같이 잡힌다.

## 끝나면
두 스크립트와 `workspace.StressMechs` 폴더, `ReplicatedStorage.MechStressCmd` 를 지운다.
