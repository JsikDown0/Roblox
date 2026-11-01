-- 메카 수치 한 곳에서 조절 (기체 2배 크기 기준: 키 약 21스터드)
local CFG = {
	MaxHealth = 1000,
	WalkSpeed = 18,
	-- 점프 (2026-10-25): 기본 점프 그대로, 착지 뒤 JumpCooldown 동안만 못 뜀(누르고 있어도 연속으로 안 튐)
	-- 무게감(10-25 안 3): 오를 땐 중력을 약하게(천천히 솟음), 내려올 땐 그보다 세게(쿵). 큰 물체는 느리게 움직여야 커 보인다
	--   10-25 1차: 오름 118 / 내림 기본 196.2 → 높이 8.2 · 체공 0.66초
	--   10-25 2차(유저 "체공과 높이를 대폭"): 점프력 44 → 높이 15.6 · 체공 1.18초
	--   10-25 3차(유저 "약간 높이자"): 높이 = 48² / (2·62) ≈ 18.6 (몸 키의 약 70%) · 오름 0.77초 + 내림 √(2·18.6/139) ≈ 0.52초 = 체공 ≈ 1.29초
	JumpPower = 48,            -- 뜨는 순간 위 속도(스터드/초)
	JumpRiseGravity = 62,      -- 오르는 동안 중력(기본 196.2). 내 화면이 기체 몸에 위쪽 힘(VectorForce)을 더해 만든다
	JumpFallGravity = 139,     -- 내려올 때 중력(점프 아닌 낙하도 같음 — 0.1초 넘게 떠 있으면). 오를 때보다 세서 묵직하게 떨어진다
	-- 도약 웅크림(10-25 2차, 유저 "좀 느리더라도 힘을 모아 확실히 구부렸다 펴면서"): 누르면 이만큼 땅에서 웅크렸다가 뜬다
	JumpWindup = 0.4,          -- 웅크리는 시간(초) = 누르고 실제로 뜨기까지 (10-25: 0.22 → 0.4, 유저 "힘을 모으는 시간을 더")
	JumpWindupMove = 0.35,     -- 웅크리는 동안 이동 입력 배율(힘 모으는 동안 거의 멈춤)
	-- 빔사벨 휘두르는 속도(10-25): 뽑아 베기·1~3타의 동작·판정·연결 시각·내딛기를 전부 이 배율로 늘림(1 = 원래, 1.25 = 25% 느리게).
	-- 쿨다운은 그대로(동작이 쿨보다 길어지지 않는지 확인: 뽑아 베기 0.66×1.25=0.83 < 쿨 0.9). 주먹은 해당 없음
	SaberSlow = 1.25,
	JumpCooldown = 0.9,
	StrideLength = 19,          -- 걷기 한 주기에 나아가는 거리(스터드). 발이 미끄러져 보이면 조절
	FireInterval = 0.12,       -- 연사 간격(초)
	Damage = 20,
	Range = 450,
	-- 장탄 (2026-10-25). 탄창 안에선 167 DPS, 장전 포함 지속 DPS = 30*20 / (3.6 + 1.8) ≈ 111
	MagSize = 30,              -- 한 탄창(발) = 3.6초 연사
	ReloadTime = 1.8,          -- 빈 탄창이면 자동, E 로 수동. 장전 중 무장을 바꾸면 취소(남은 발 그대로)
	MaxEnergy = 100,
	EnergyRegen = 22,          -- 초당 회복
	BoostCost = 30,
	BoostSpeed = 115,
	BoostLift = 12,
	BoostTime = 0.32,
	BoostCooldown = 0.45,
	-- 지속 부스트(2026-10-25): 톡 누르면 위 대시, 누르고 있으면 대시 뒤 수평 추진이 이어짐(땅·공중 모두, 떼면 즉시 멈춤).
	--   공중에서도 높이는 안 올려 줌(중력 그대로) → 체공은 안 늘고 앞으로만 멀리. 공중 대시(톡)는 점프 한 번에 1회
	BoostHoldSpeed = 60,       -- 지속 추진 수평 속도(걷기 18 의 약 3.3배)
	BoostHoldDrain = 30,       -- 지속 중 초당 게이지 소모(가득 → 약 3.3초). 공중은 × BoostAirDrainMul
	BoostAirDrainMul = 1.5,
	AirRegen = true,           -- 떠 있는 동안에도 게이지가 참(공용). AELLO 는 false = 땅에서만 참(10-27) — 판정은 MechServer airborne(서버 광선)
	BoostOverheat = 1.2,       -- 지속으로 게이지를 바닥까지 쓰면 이 시간 동안 회복 정지(과열). 다시 쓰려면 키를 뗐다 눌러야 함
	BoostAirCarryTau = 0.9,    -- 공중 관성: 추진·대시가 끝난 뒤 착지까지 수평 속도가 줄어드는 시간 상수(초). 공중에서 툭 멈추지 않게
	JumpWindupBoost = 0.15,    -- 부스트 중 점프: 웅크림을 짧게, 달리던 속도를 실어 뜀(부스트 점프)
	-- 미사일 컨테이너(2026-10-25): 종아리 양쪽 3연장 포드 = 6발. G 로 일괄 사출 → 포드를 버림. 출격마다 한 번(새 기체만 다시 달고 나옴)
	-- 조준 사격(10-25 13:15, 유저 "A로 가자"): 록온 없음. 라이플처럼 6발 모두 조준점으로 곧게 사출(부채꼴 없음) +
	--   쏘는 순간 조준점 MissileSeekCone 안의 적이 있으면 그 몸 가운데로 아주 약하게 꺾임(초당 MissileTurnRate, MissileGuideTime 동안).
	--   예전: 14° 록온 즉시(13:01 영상 "조준 안 해도 맞음") → 13:05 록온 시간(5° 0.8초) → 비교 뒤 이 방식.
	--   [시뮬] 서 있는 적: 멀리서 조준 오차 약 6~7° 까지 끌어옴(유도 대상은 5° 안만) / 옆으로 걷는 적(18)·몸 가운데 겨눔(리드 없음):
	--   20 에서 5/6 · 50 3/6 · 80 2/6 · 120 1/6 → 반 박자 앞을 겨누면 50~120 6/6. 150 이상은 걷기만 해도 빠져나감
	MissileDamage = 70,        -- 한 발. 6발 다 맞으면 420(체력의 42%)
	MissileSpeed = 150,        -- 초속(스터드)
	MissileLife = 3.2,         -- 초. 최대 거리 약 480
	MissileTurnRate = 10,      -- 유도: 초당 최대 회전(도). 예전 50(록온 시절) → 10 "약간의 유도"(20 만 돼도 멀리서 11° 빗나간 조준을 끌어온다)
	MissileArm = 0,            -- 사출 뒤 이 시간은 유도 없이 직진. 부채꼴을 없애 0(유도가 바로 시작)
	MissileSeekCone = 5,       -- 유도 대상: 쏘는 순간 조준점(카메라 정면)에서 이 각(도) 안의 가장 가까운 적. 서버가 정한다. 없으면 곧게만
	MissileStagger = 0.06,     -- 한 발씩 나가는 간격(초) → 6발 0.3초
	MissileProximity = 7,      -- 근접 신관: 다른 기체 몸 가운데와 이 거리 안이면 터짐
	MissileJettisonDelay = 0.45, -- 마지막 발이 나간 뒤 포드를 버리기까지(초)
	-- 밸런스(10-25, 유저 "근거리는 당연하고 먼 거리에서도 꽤 잘 맞는다"): 화력(70×6)은 그대로 두고
	MissileGuideTime = 0.6,    -- 유도는 사출(+MissileArm) 뒤 이 시간만. 그 뒤엔 직진 → 먼 거리에서 걷는 적은 빠져나간다
	MissileSplashRadius = 14,  -- 터진 곳에서 이 거리(몸 가운데 기준) 안의 나 자신 + 적이 맞는다. 아군은 안 맞음(트롤 방지)
	MissileSplashDamage = 30,  -- (적) 터진 곳 바로 옆 30 → 반경 끝 0 (직선). 직접 맞은 기체는 그 발의 스플래시를 또 받지 않는다
	-- 자기 피해(10-25 13:01, 유저 "적 쪽이 압도적으로 높아 리스크가 거의 없다. 적에게 100% 면 나에게 90% 정도로"):
	--   내 미사일이 내 몸 가운데에서 MissileSelfRadius 안에서 터지면 한 발에 MissileDamage × MissileSelfMul(63) 전부,
	--   그 바깥 MissileSelfFade 에 걸쳐 0 으로(1스터드 차이로 63 ↔ 0 이 갈리지 않게). 적이 맞았든 안 맞았든 터진 거리로만 정한다
	--   [시뮬] 몸 중심끼리 16 안에서 쏘면 적 420 · 나 378(90%), 20 에서 나 35%, 24 이상 거의 0
	MissileSelfMul = 0.9,
	MissileSelfRadius = 14,
	MissileSelfFade = 6,
	-- 기체 물리 안전장치(10-25 13:26, 유저 영상 "부스트→빔사벨로 적에 부딪히면 공중으로 급상승") — MechPhysics 참고
	BodyBlockDist = 8,         -- 몸통(HRP) 중심끼리 수평 거리가 이 안이면 "닿음": 그쪽으로 미는 속도 성분을 지운다(HRP 6×4 둘이 닿는 4~7 + 여유)
	BodyBlockAccel = 100,      -- 닿아 있는 동안 수평 속도 제약의 힘 = 질량 × 이 값(무한 → 유한, 중력 196 보다 약하게 = 위로 못 밀어 올림)
	RiseCap = 25,              -- 점프로 오르는 중이 아니면 위로 이 속도(스터드/초) 넘게 못 오른다. 공중 대시 띄움 BoostLift 12 보다 위
	RiseCapJump = 60,          -- 점프로 오르는 중 상한(점프력 48 + 여유)
	-- 10-27 카메라 = 메카 브레이크식 "가운데 · 머리 위로 넘겨 봄"(유저 "메카 브레이크 시점으로 옮겨보자"). 옛 값: 거리 30 · 옆 6.5 · 위 2.2 · 초점 6.4 · 줌 24 / 7.5
	--   조준선(화면 가운데)은 늘 초점보다 CameraShoulderY 위로 지남 → 초점 + 위 = 머리 꼭대기 + 여유(중장갑 1.75 를 키 비례). 기체 머리가 화면 가운데 바로 아래(MB 실측 53%)
	--   [팔콘 소개 영상 프레임 실측 · 복셀 렌더 scratchpad/gatling/camtry.py · aello_cam.py]. 옛 값 백업 = ServerStorage._CameraMB_before_20261027
	CameraDistance = 30,       -- 키 21.3(중장갑 28.4 의 0.75) → 중장갑 40 × 0.75 (13:13 확대 시험, 옛 34.5)
	CameraShoulderX = 0,
	CameraShoulderY = 3.6,
	CameraFocusHeight = 8.0,   -- 머리 꼭대기 9.8 · 등 칼자루 11.0 [실측 템플릿] → 조준선 11.6
	CameraLookUpRise = 1.0,    -- 위를 볼수록 카메라를 이만큼 더 올림(× sin 피치) — 위를 보면 등·머리가 조준선 쪽으로 올라오므로
	-- 줌(오른쪽 클릭, 2026-10-25): 라이플 급. 저격총(출시 예정)이 3~4배를 쓰도록 여기선 1.3배까지만
	ZoomMag = 1.3,             -- 배율. 시야각 70 → 약 56.6 (2·atan(tan(35°)/1.3))
	ZoomSpeed = 8,             -- 들어가고 나오는 빠르기(1/초) → 약 0.13초
	ZoomCameraDistance = 25,   -- 줌 때 카메라 거리(평소 CameraDistance 30). 조금 다가가 조준하는 느낌
	ZoomShoulderX = 0,         -- 10-27 가운데 카메라라 줌도 옆으로 안 비킴(옛 7.5)
	-- 줌의 역할(10-25 11:36 유저 결정): 라이플 줌 = "보기 편한 기능". 대가도 이점도 없다(오버워치식).
	--   진짜 줌의 맛은 저격총이 가져간다. 라이플은 기동하며 언제 쏴도 믿을 만한 주무기
	--   (이력: 11:30 탄 퍼짐 + 줌 감속 60% 를 넣었다가 "스톰트루퍼 같다 · 타르코프 장르 아님" → 되돌림)
	ZoomMoveMul = 1,           -- 줌 중 이동 속도 배율(1 = 감속 없음). 다른 무기가 쓸 수 있게 손잡이만 남김
	-- 탄 퍼짐(원뿔 반각, 도): 라이플은 전부 0 = 조준점에 정확히. 계산 코드는 남겨 둠 → 기관총·샷건 같은 무기의 개성용
	--   (쓸 때 참고: 각도 1° = 300스터드에서 반지름 약 5.2, 기체 폭 약 14)
	SpreadBase = 0,            -- 서서 첫 발
	SpreadPerShot = 0,         -- 한 발 쏠 때마다 더해짐(연사 블룸)
	SpreadBloomMax = 2.5,      -- 블룸 상한
	SpreadRecover = 5,         -- 쏘기를 멈추면 초당 줄어드는 블룸
	SpreadMove = 0,            -- 걸을 때 더함(걷기 속도 비례)
	SpreadAir = 0,             -- 공중
	SpreadBoost = 0,           -- 부스트 중
	ZoomSpreadMul = 0.35,      -- 줌하면 전체 퍼짐 × 이 값(퍼짐이 0 이면 효과 없음)
	MouseSensitivity = 0.0032,
	RespawnDelay = 6,
	MaxMechs = 6,
	-- 무게감
	Accel = 3.2,               -- 출발 가속(클수록 빨리 최고 속도)
	Decel = 4.5,               -- 정지 감속
	TurnResponsiveness = 12,   -- 몸이 카메라 방향을 따라 도는 반응
	TurnRate = 3.2,            -- 최대 회전 속도(라디안/초, 약 180도/초)
	AimTurnRate = 10,         -- 사격/조준 중 회전 속도(라디안/초)
	TwistLimit = 100,         -- 상체(허리)가 조준 방향으로 먼저 돌 수 있는 최대 각도
	FireArc = 120,            -- 기체 정면에서 이 각도 안이면 발사 (상체 비틀기로 대부분 커버)
	StepShake = 0.15,          -- 발 디딜 때 카메라 흔들림
	BoostShake = 0.4,         -- 부스트 때 카메라 흔들림
	-- 소리(발소리 크기 StepVolume · 효과음 Sfx*)는 2026-10-25 MechProto.SoundManager 의 SOUNDS / GROUPS 로 옮김
	-- 적 메카 (MechEnemy, 탑승 불가. 위치·방향은 workspace.MechTestRange.EnemySpawn 파트)
	EnemyRespawn = 5,          -- 파괴된 뒤 다시 나타날 때까지(초)
	EnemyTint = Color3.fromRGB(255, 165, 150),   -- 적 색조(SurfaceAppearance.Color 곱하기). 흰색이면 원래 색
	EnemyAI = true,            -- false 면 서 있는 표적(움직이지도 쏘지도 않음)
	EnemyStartActive = false,  -- 시작할 때 전투 상태인지. false 면 대기(서 있는 표적) → 시험장 EnemyButton 을 밟으면 전환
	EnemySight = 220,          -- 이 거리 안의 '탑승한' 메카를 노린다
	EnemyKeepFar = 70,         -- 이보다 멀면 다가온다
	EnemyKeepNear = 32,        -- 이보다 가까우면 물러난다
	EnemyMeleeRange = 30,      -- 이 안이면 내딛어 벤다(16 안이면 주먹). 내딛기는 플레이어와 같은 고정 거리(2026-10-25 38 → 30)
	EnemyMeleeCooldown = 3.5,
	EnemyBurst = 6,            -- 한 번에 쏘는 발 수 (간격 = FireInterval x 1.5)
	EnemyBurstGap = 1.3,       -- 연사 사이 쉬는 시간(초)
	EnemySpread = 3.5,         -- 조준 흔들림(스터드, 상대 몸통 기준). 클수록 덜 맞는다
	EnemyBoostEvery = 5,       -- 평균 이 초마다 옆으로 부스트 회피(±1.5초)
	-- 근접: 빔사벨 (R, 왼손). 판정은 서버가 누른 뒤 SaberStrike 초에 기체 앞 부채꼴로 한 번
	SaberDamage = 120,         -- R 뽑아 베기. 2026-10-25 150 → 120 (반복 시 133 DPS < 라이플 167)
	SaberCooldown = 0.9,       -- 다시 휘두를 수 있을 때까지(초)
	SaberTime = 0.66,          -- 전체(초): 백팩 칼 잡기 0.10 → 뽑아 올리기 0.17(빔 점화 0.15) → 내려베기 0.31 → 마무리 0.43 → 복귀(빔 소등 0.58). 단계 시각은 MechClient 에 고정
	SaberStrike = 0.30,        -- 판정 순간(초). 날이 15스터드 앞 기체를 지나는 시각 (뽑기 동작을 넣기 전엔 0.24)
	SaberRange = 20,           -- 몸 중심끼리 수평 거리(스터드). 서버가 상대 몸 반지름(메카 4)을 더한다
	SaberArc = 70,             -- 휘두르는 방향 좌우 이 각도 안이면 맞음
	SaberColor = Color3.fromRGB(90, 230, 255),
	-- 근접 내딛기 (2026-10-25 너프). 적 쪽으로 끌려가거나 방향을 트는 거리 보정(유도)은 삭제:
	-- 늘 화면 정면으로 종류별 고정 거리만 내딛는다(전엔 50 안의 적에게 최대 30까지 끌려감).
	-- 앞에 기체가 있으면 몸이 겹치기 전에 멈추기만 한다(줄이기만, 늘리거나 틀진 않음)
	SaberLunge = 8,            -- R 뽑아 베기
	LungeTime = 0.22,          -- R 뽑아 베기 내딛는 시간(초). 판정(0.30) 전에 끝난다
	LungeBodyGap = 11,         -- 앞 기체 몸 중심까지 이만큼은 남긴다(공통)
	-- 근접: 주먹 (V, 왼손 스트레이트). 빔사벨보다 짧고 빠르고 약하다
	PunchDamage = 60,
	PunchCooldown = 0.5,
	PunchTime = 0.4,           -- 당기기 0.08 → 뻗기 0.16 → 멈춤 0.22 → 복귀 (단계 시각은 MechClient 에 고정)
	PunchStrike = 0.15,        -- 판정 순간(초). 주먹이 다 뻗는 시각
	PunchRange = 9,            -- 몸 중심끼리 수평 거리(+ 상대 몸 반지름 4). 주먹 끝은 정면 10.3스터드
	PunchArc = 45,
	PunchLunge = 4,            -- 주먹 내딛기(고정). 2026-10-25 적에게 최대 20 → 고정 4
	PunchLungeTime = 0.13,     -- 판정(0.15) 직전에 끝난다
	-- 무장 교체 (1 라이플 / 2 빔사벨). 단계 시각은 MechClient 에 고정
	EquipTime = 0.32,          -- 빔사벨 들기: 백팩 칼 잡기 0.10 → 뽑아 올리기 0.17(빔 점화 0.15) → 겨눔 0.32. 그 전엔 못 벤다
	UnequipTime = 0.25,        -- 라이플로: 겨눔 → 백팩에 꽂기 0.15(빔은 0.04에 끔) → 평상 0.25. 그 전엔 못 쏜다
	-- 빔사벨 상태 좌클릭 베기 (뽑는 동작이 없어 R 뽑아 베기보다 빠르다)
	SlashDamage = 100,         -- 2026-10-25 150 → 100 (빔사벨 DPS 하향)
	SlashCooldown = 0.9,
	SlashTime = 0.52,          -- 겨눔 → 들어올리기 0.08 → 내려베기 0.22 → 마무리 0.34 → 겨눔 복귀
	SlashStrike = 0.21,        -- 판정 순간(초). 날이 15스터드 앞 기체를 지나는 시각
	SlashLunge = 6,            -- 1타 내딛기(고정). 2026-10-25 최대 24 → 고정 6
	SlashLungeTime = 0.15,     -- 판정(0.21) 전에 끝난다
	-- 빔사벨 3연격 (위 Slash* = 1타). 좌클릭을 누르고 있으면 1→2→3 이어진다. 단계 시각은 MechClient 에 고정
	SlashChain1 = 0.34,        -- 1타 시작 후 이 시각에 2타가 이어진다(1타 판정 뒤에 누르면 예약)
	Slash2Damage = 70,         -- 2타: 오른쪽→왼쪽 가로베기(가슴~허리 높이). 2026-10-25 100 → 70
	Slash2Time = 0.48,
	Slash2Strike = 0.15,       -- 날이 15스터드 앞 기체를 지나는 시각
	SlashChain2 = 0.28,        -- 2타 시작 후 이 시각에 3타가 이어진다
	Slash2Lunge = 3,           -- 2타는 반 걸음만
	Slash2LungeTime = 0.10,
	Slash3Damage = 140,        -- 3타: 찌르기(마무리). 2026-10-25 올려베기 → 찌르기, 180 → 140
	Slash3Time = 0.62,         -- 왼쪽 허리로 당김 0.09 → 찌름 0.17 → 유지 0.32 → 겨눔 복귀
	Slash3Strike = 0.16,       -- 날이 15스터드 앞 기체 안으로 들어간 시각(0.14 에 닿기 시작)
	Slash3Range = 22,          -- 찌르기는 더 멀리, 대신 좁게
	Slash3Arc = 35,
	-- 판정 구간(10-25 14:24, 유저 "대시 연계 시 찌르기 판정이 들쭉날쭉" → 1·2타도 같이): 예전엔 strike 한 순간만 봤다.
	--   이제 strike ~ 아래 시각(동작표 시각, 실제 = × SaberSlow)까지 매 프레임 검사, 대상마다 한 번. 날이 보이는 구간 = 판정 구간
	--   (대시로 파고들다 날이 닿으면 맞음 + 서버가 내 위치를 늦게 보는 차이도 구간 안에서 따라잡힘). 사거리·각도는 그대로
	SlashActiveEnd = 0.30,     -- 1타: 내려베기(0.08~0.22) 뒤 마무리 앞쪽까지. 2타로 잇는 0.34 전에 끝
	Slash2ActiveEnd = 0.24,    -- 2타: 가로베기(0.07~0.19) 뒤 조금. 3타로 잇는 0.28 전에 끝
	Slash3ActiveEnd = 0.32,    -- 3타: 찌름(0.17) 뒤 날을 뻗고 있는 유지 끝까지
	Slash3Lunge = 8,           -- 찌르며 한 걸음(고정)
	Slash3LungeTime = 0.13,    -- 판정(0.16) 전에 끝난다
	Slash3Cooldown = 1.3,      -- 3타 뒤 다시 1타부터 시작하려면 3타 시작 뒤 이만큼(마무리 뒤 빈틈)
	-- 1·2타에서 멈췄다면 그 타 시작 뒤 SlashCooldown(위) 이 지나야 다시 1타
	-- DPS(2026-10-25 하향): 3연격 다 맞힘 310 / (0.62 + 1.3) ≈ 161, 1타만 반복 ≈ 111, 라이플 167
}
-- ================= 주무기 (2026-10-25 14:36 저격총) =================
-- 기체 속성 Gun("rifle" | "sniper", 없으면 rifle)으로 고른다. 시험장 무기 거치대(WeaponRack)에서 바꾼다.
-- ⚠️ 손에 든 파트 이름은 둘 다 "Rifle"(= 주무기 자리 이름), 등은 "RifleStowed". 정체는 이름이 아니라 기체 속성 Gun 으로 판단한다.
-- 라이플 값은 위 Damage·FireInterval·MagSize·ReloadTime·Range·ZoomMag 그대로(적 AI 는 위 값을 직접 씀)
-- 저격총(유저 결정): 줌 3배 · 쏘는 순간 맞는 한 발(피해 크고 연사 느림, 탄도선 보임) · 줌 안 해도 똑같이 쏨
CFG.Guns = {
	rifle = { Label = "라이플", Damage = CFG.Damage, FireInterval = CFG.FireInterval, MagSize = CFG.MagSize, ReloadTime = CFG.ReloadTime,
		Range = CFG.Range, ZoomMag = CFG.ZoomMag, Kick = 1, Tracer = "rifle", FireSound = "GunFire" },
	sniper = { Label = "저격총",
		Damage = 220,          -- 한 발. 1000 체력에 5발(4발이면 880). 라이플 탄창 한 통(30발 600)의 약 1/3
		FireInterval = 1.4,    -- 볼트 당김 포함. 지속 화력 ≈ 220/1.4 = 157(장전 포함 약 110) — 라이플 탄창 안 167 보다 낮게
		MagSize = 5,
		ReloadTime = 2.4,
		Range = 900,           -- 라이플 450 의 두 배
		ZoomMag = 3,           -- 시야각 70 → 약 26.3 (2·atan(tan(35°)/3)). 마우스 감도도 1/3
		Kick = 2.5,            -- 반동(자세·카메라) 배율
		Tracer = "sniper", FireSound = "SniperFire" },
	-- 10-27 FELSEN 개틀링. 처음(10:26)엔 "과열이 탄창 대신"(Heat = true) → 16:16 유저 결정: 탄창·장전(E)으로
	--   ("과열 상태를 적만 보고 정작 본인이 못 보잖아" — 실측: 뒤 카메라에선 어느 자세든 달궈진 총열이 안 보임 [rig/hip_anim.py]).
	--   Heat = false → 라이플과 같은 장전 길(MagSize · ReloadTime, 비면 자동 장전). 되돌리기 = Heat = true(과열 규칙 코드는 그대로 있음)
	--   HeatLook = 겉모습만: 쏠수록 총열이 달궈져 보이고(서버가 GunHeat 속성을 적음) 멈추면 식음 — 막는 규칙 없음(적에게 "오래 쏘는 중" 신호)
	--   회전: 방아쇠를 당기면 SpinUp 초 뒤부터 나감(서버도 속성 GunSpinAt 으로 확인, 장전 중엔 안 돎) · 도는 동안 걷기 × MoveMul · 퍼짐 Spread(도, 원뿔 반각)
	--   화력 [계산]: 탄창 안 9 × 18 = 162/초(라이플 167) · 100발(5.6초) + 장전 3초 → 지속 약 105 = 옛 과열 주기(100발 + 강제 냉각 3초)와 같음(라이플 장전 포함 111)
	--   거리별(옆으로 걷는 표적, 조준 가정 sim/duel.py, 과열 때 값): 50·100·200·300 = 98·92·61·38 (라이플 111·108·90·68) — 퍼짐 때문에 멀수록 약함
	gatling = { Label = "개틀링",
		Damage = 9, FireInterval = 1 / 18, Range = 350, ZoomMag = 1.3, Kick = 0.6, Tracer = "rifle", FireSound = "GunFire",
		Heat = false, HeatLook = true, HeatPerShot = 0.01, CoolDelay = 0.4, CoolRate = 0.35, OverheatTime = 3.0,   -- 과열 수치는 HeatLook(겉모습)이 씀
		SpinUp = 0.6, MoveMul = 0.6, Spread = 1.5,
		MagSize = 100, ReloadTime = 3.0 },
}
-- 과열 총의 지금 과열(0~1)과 강제 냉각 중인지. 속성 GunHeat(그 시각 값)·GunHeatAt(서버 시각)·GunLockUntil(서버 시각) → 시각으로 계산(식히는 루프 없음)
function CFG.gunHeat(m, now)
	local G = CFG.gun(m)
	if not (G.Heat or G.HeatLook) then return 0, false end   -- 10-27 HeatLook = 겉모습만(GunLockUntil 은 Heat 총만 적으므로 강제 냉각 없음)
	local lock = m:GetAttribute("GunLockUntil")
	if lock and now < lock then return math.clamp((lock - now) / G.OverheatTime, 0, 1), true end
	local h, at = m:GetAttribute("GunHeat") or 0, m:GetAttribute("GunHeatAt") or 0
	if lock and at < lock then return 0, false end   -- 강제 냉각이 끝났으면 0 부터
	return math.max(0, h - G.CoolRate * math.max(0, now - at - G.CoolDelay)), false
end
function CFG.gun(model)        -- 그 기체의 주무기 수치표
	local g = model and model:GetAttribute("Gun")
	local G = (g and CFG.Guns[g]) or CFG.Guns.rifle
	-- 10-30 SKADI: 궁극기 사격 창(active) = Modes.Ult(×1.5 · 0.7초 · 탄창 무한) > 다 꿇은 앵커(on) = Modes.Anchor(×1.4 · 줌 6배 · 반동 0). 표가 없는 총·그 상태가 아닌 기체는 그대로
	if G.Modes then
		if G.Modes.Ult and model:GetAttribute("UltStart") and CFG.ultPhase(model) == "active" then return G.Modes.Ult end
		if model:GetAttribute("AnchorAt") and CFG.anchorPhase(model) == "on" then return G.Modes.Anchor or G end
	end
	return G
end

-- ================= 손목 미사일 런처 (G, 2026-10-26 23:27 유저 "런처 그레네이드도 구현하자(기존 미사일 기능)") =================
-- 기체 속성 SubWeapon = "Grenade"(AeroTemplate 에 박음 — 이름은 런처 이름일 뿐) → G 가 종아리 포드 대신 이것.
-- 23:54 유저 "포물선 말고 내가 생각했던 건 미사일" → 비행·피해·화면 = 미사일 것 그대로(서버 fireSalvo 에 손목 관 하나를 넘김:
--   곧게 + 약한 유도 + 근접 신관 + Missile* 수치). 다른 건 탄 수뿐: 출격당 6발 한 번(포드 버림) 대신 2발 + 다시 참.
--   발사관 = 왼아래팔 Attachment "GrenadeTube1/2". 23:27 의 곡사(자체 탄도)는 걷어냄
CFG.GrenadeAmmo = 2              -- 발 수. 다 쓰면 GrenadeRefill 초 뒤 두 발이 한꺼번에 다시 참 [결정 10-26 20:24]
CFG.GrenadeRefill = 8            -- [제안]
CFG.GrenadeInterval = 0.35       -- 두 발 사이 최소 간격(초) [제안]
CFG.GrenadeMuzzleTrust = 16      -- 화면이 보낸 총구 자리를 믿는 거리. 서버의 팔은 차렷(애니는 화면에서만)이라 든 팔의 총구와 다름.
                                 -- 어깨→손목 약 9 → 팔을 90° 들면 손목이 약 12.7 옮겨감 [계산: 관절 자리] + 여유
-- 지금 쏠 수 있는 발 수. 다 썼어도 GrenadeReadyAt(서버 시각)이 지났으면 꽉 참 — 시각으로 저절로 풀려서 "다시 채우는 코드"가 따로 없다
function CFG.grenadeAmmo(m, now)
	local a = m:GetAttribute("GrenadeAmmo") or 0
	if a <= 0 then
		local at = m:GetAttribute("GrenadeReadyAt")
		if at and now >= at then return CFG.GrenadeAmmo end
	end
	return a
end

-- ================= 10-30 SKADI 보조: 센서 지뢰 (G, 템플릿 속성 SubWeapon = "Mine") [결정 10-29 22:37 · 22:39 — 저격기_현재상태 4절] =================
-- G → 기체 앞 Front 스터드 땅에 하나 깜(골반 왼쪽에서 떨어짐) → ArmTime 뒤 켜짐 → 적 기체가 감지 범위에 들어오면 Warn 초 깜빡임(예고 + 땅에 범위 원)
--   → 폭발: 그 순간 범위 안 적 전부 Damage + 경직 Stun(작살 그랩과 같은 StunUntil). 예고 원 = 판정 범위(같은 모양)
-- 감지·피해 범위 = 수평 거리 Radius 안 · 높이 차(기체 루트 − 지뢰) −4 ~ 그 기체 루트 높이 + 6 → 위로 날아 지나가는 기체는 안 터뜨림 [제안]
-- 대상 = 조종 중이거나 적 AI(EnemyMech)인 다칠 수 있는 기체(MechDamage.canDamage) — 보급대에 서 있는 빈 기체는 안 터뜨림 [제안]
-- 개수 = 손목 그레네이드와 같은 규칙: 두 개 다 쓰면 Refill 초 뒤 한꺼번에 다시 참(속성 MineAmmo · MineReadyAt). 필드 최대 MaxField(넘으면 가장 오래된 것 사라짐)
-- 서버 = MechServer MINE(상주 Heartbeat 하나가 켜기·감지·폭발·정리) · 화면 = MechClient(렌즈 깜빡임·범위 원·폭발) · 모델 = ServerStorage.SkadiMine
CFG.Mine = {
	Ammo = 2, Refill = 15,
	ArmTime = 2, Radius = 12, Warn = 0.5,
	Damage = 150, Stun = 0.5,
	MaxField = 2,
	Front = 8,          -- 기체 앞 이만큼 땅에 놓음 [제안]
	DropTime = 0.35,    -- 골반 옆에서 땅까지 떨어지는 시간(켜지는 시각은 깐 순간부터 ArmTime)
	Interval = 0.35,    -- 연속으로 깔 때 최소 간격 [제안 — 그레네이드와 같은 값]
	RiseAbove = 6, Below = 4,   -- 높이 차 허용: 루트 높이 + RiseAbove 위까지 · Below 아래까지
}
function CFG.mineAmmo(m, now)
	local a = m:GetAttribute("MineAmmo") or 0
	if a <= 0 then
		local at = m:GetAttribute("MineReadyAt")
		if at and now >= at then return CFG.Mine.Ammo end
	end
	return a
end

-- ================= 시그니처: 작살 그랩 (10-27 FELSEN, 유저 "시그니처가 작살 그랩" · 왼손목) =================
-- 기체 속성 Signature == "Grab" 이면 C 로 왼손목에서 작살을 쏨(F 는 하차라 C) [제안]. 맞으면 상대를 내 앞 Front 스터드 땅으로
--   PullTime 초에 끌어오고, 끌려오는 동안 + 그 뒤 Stun 초 동안 상대는 아무것도 못 함(이동·사격·부스트·상승·근접) → 도끼 뽑아 베기(R)로 이음.
-- 나는 기체도 끌어내린다(공중 AELLO 를 땅으로). 맞든 안 맞든 Cooldown. 작살은 서버가 날림(곧게, 유도 없음, 벽에 막힘).
CFG.Grab = {
	Cooldown = 8, Range = 135, Speed = 330, HitRadius = 6, PullTime = 0.45, Stun = 1.0, Front = 14,   -- 10-31 00:09 유저 동의: 끌기 0.7 → 0.45(처음 천천히 · 끝에 가속 = PullEase "in" · 도착 쾅)   -- 10-30 23:25 유저: 사거리 1.5배(90 → 135) · 탄속도 1.5배(날아가는 시간 0.41초 그대로) · 끌기 0.5 → 0.7(먼 거리 순간이동처럼 안 보이게) · 끌려온 뒤 행동 불가 0.7 → 1.0
	AimHold = 0.45, SendDelay = 0.1,   -- 왼팔을 조준 자세로 드는 시간 · 든 팔 손목 자리를 보내기까지(AELLO 손목 런처와 같은 값)
	Key = Enum.KeyCode.C,
	Windup = 0.2,         -- 10-31 준비 동작(팔을 뒤로 당김 — 상대에겐 예고) · 클라가 누르면 "wind" → 이만큼 뒤 쏨
	Recover = 0.3,        -- 10-30 19:23 유저 "그랩 사용중에는 게틀링이나 도끼 같은 다른 동작 수행 불가 · 팔과 다리를 뻗는 그랩 전용 모션" — 줄이 다 감긴 뒤 자세를 푸는 시간
}
-- 10-30 그랩 중(쏨 → 날아감 → 감김 → 자세 풂) = 스스로 거는 잠금(CFG.stunned 에 들어감 — 사격·근접·부스트·이동 다 막힘)
--   서버 속성 GrabAt(쏜 서버 시각) · GrabHitAt(맞음·빗나감·벽 = 날아가기 끝) · GrabEnd(줄이 다 감기는 시각 = 맞으면 + PullTime + 0.15 · 아니면 + 0.25)
--   "fly"(GrabHitAt 전 — 넘지 않게 Range/Speed + 0.15 까지만) · "reel"(GrabHitAt ~ GrabEnd) · "recover"(GrabEnd ~ + Recover)
function CFG.grabPhase(m, now)
	local at = m and m:GetAttribute("GrabAt")
	now = now or workspace:GetServerTimeNow()
	local G = CFG.Grab
	local w = m and m:GetAttribute("GrabWindAt")   -- 10-31 준비 동작("wind"): 쏘기 전 Windup(+ 여유 0.35 — 쏘기 신호가 안 오면 풀림)
	if w and (not at or at < w) then
		if now - w >= 0 and now - w < G.Windup + 0.35 then return "wind", math.clamp((now - w) / G.Windup, 0, 1) end
		return nil
	end
	if not at then return nil end
	local hit, e = m:GetAttribute("GrabHitAt"), m:GetAttribute("GrabEnd")
	if hit and e and hit >= at then
		if now < e then return "reel", math.clamp((now - hit) / math.max(0.05, e - hit), 0, 1) end
		if now < e + G.Recover then return "recover", (now - e) / G.Recover end
		return nil
	end
	local fly = G.Range / G.Speed + 0.15
	if now - at >= 0 and now - at < fly then return "fly", (now - at) / fly end
	return nil
end
function CFG.stunned(m, now)   -- 끌려오는 중 또는 경직 중 · 10-30 SKADI 앞차기 공중제비 중(맞힌 순간 ~ 착지 — 사격·부스트·근접·앵커 등 다 막힘)
	now = now or workspace:GetServerTimeNow()
	if (m:GetAttribute("StunUntil") or 0) > now then return true end
	local fa = m:GetAttribute("FlipAt")
	if fa ~= nil and now < fa + CFG.Kick.Flip.Time then return true end
	if CFG.leapPhase(m, now) ~= nil or CFG.chargePhase(m, now) ~= nil or CFG.grabPhase(m, now) ~= nil then return true end   -- 10-30 FELSEN 그랩 중도   -- 10-30 FELSEN 돌진도   -- 10-30 FELSEN 궁극기 도약 중(날아감 ~ 내려찍고 도끼 거둠까지 — 스스로 거는 잠금)
	return CFG.riderPhase(m, now) ~= nil   -- 10-30 FALCO 라이더킥 중(누름 ~ 착지·자세 풀림까지 — 스스로 거는 잠금, 앞차기 공중제비와 같은 형태)
end

-- ================= 지하 땅굴 사출(2026-10-25 16:24, 유저 "육전형이라 땅굴 → 지상 격납고 문이 더 어울림") =================
-- 구조물 = Range.UndergroundLaunch(경로 F1..F4: 땅굴 출발 → 경사 아래 → 경사 위(격납고) → 문 밖). 보급대(BayPad) = F1.
-- 출격 단말기 E → 서버가 LaunchAt(가속 시작 서버 시각) → 조종 클라가 경로를 직접 따라가게 몬다(PlatformStand) → 문 밖에서 놓아 주고 땅을 긁으며 미끄러져 섬
CFG.LaunchPrep = 2.0            -- 탄 뒤 가속까지(발진 패널 ABORT → CLEAR → LAUNCH)
CFG.LaunchAccelTime = 1.0       -- 이 시간에 0 → LaunchSpeed (가속 거리 = 속도 × 시간 / 2 = 60 = 땅굴 평지 길이)
CFG.LaunchSpeed = 120           -- 경사·격납고·문을 지나는 속도. 땅굴 끝까지 약 2.0초
CFG.LaunchSkidTime = 0.75       -- 문 밖에서 120 → 0 으로 미끄러지는 시간. 끝나면 조작 돌려줌
CFG.LaunchSkidPow = 2           -- 감속 곡선 지수: 속도 = 120 × (1 − 경과/시간)^지수. 2 = 처음에 세게 잡힘(땅 마찰).
                                -- 미끄러지는 거리 = 120 × 시간 / (지수 + 1) → 30 (16:46 유저 "지상은 마찰이 있으니 약간 짧게": 예전 0.9초 직선 감속 = 54)
CFG.LaunchReturn = 0.45         -- 원래 카메라로 섞는 시간
CFG.LaunchServerGuard = 4.0     -- 서버: LaunchAt 뒤 이 시간 동안 하차 금지·출발점에 새 기체 안 놓음(주행 약 2.0 + 미끄러짐 0.9 + 여유)

-- ================= (보관) 공중 캐터펄트 사출(2026-10-25, 유저 결정: 탈 때 자동 사출 · 공중 터널형 · 발진 패널·컷 전환·불꽃/굉음) =================
-- 16:24 지하 땅굴로 바꾸며 구조물은 ServerStorage._AerialCatapult_20261025 로, 그 코드 버전은 _Underground_before_20261025 의 MechClient 로 보관. 아래 값은 그 코드용
-- 보급대(Range.BayPad) = 공중 터널 캐터펄트(Range.Catapult) 출발점. 거기 있는 기체에 타면(땅의 출격 단말기 E) 서버가 기체 속성
-- LaunchAt(가속이 시작되는 서버 시각)을 박고, 조종 클라가 준비 → 가속 → 출구 이탈을 직접 몬다. 다른 화면은 LaunchAt 으로 자세·불꽃·셔틀을 그린다.
CFG.CatapultPrep = 2.0          -- 탄 뒤 가속까지(발진 패널 ABORT → CLEAR → LAUNCH, 문 열림)
CFG.CatapultAccelTime = 1.2     -- 가속 시간
CFG.CatapultExitSpeed = 150     -- 출구 속도. 가속 거리 = 속도 × 시간 / 2 = 90 (출발 z 162 → 72, 입구 z 66)
CFG.CatapultExitUp = 20         -- 출구를 벗어날 때 위로 주는 속도(16:03 15 → 20)
-- 활공(16:03 유저 "호기롭게 출발한 것에 비해 뚝 떨어지는 느낌" → 멀리): 이탈 뒤 이 시간 동안 부스터로 버팀 = 중력 약하게 + 수평 속도 그대로.
-- 끝나면 평소 낙하(중력 139 · 공중 관성 줄어듦). 계산: 예전 0.80초·79 → 1.55초·약 197 (출구 높이 36 기준, 최고 +6.6)
CFG.CatapultGlideTime = 0.8
CFG.CatapultGlideGravity = 30
CFG.CatapultExitShot = 0.9      -- 출구 밖 카메라 컷 길이. 이 뒤 조작을 돌려줌
CFG.CatapultReturn = 0.45       -- 원래 카메라로 섞는 시간
-- ===== 기체 종류별 수치(10-25 18:24 유저: "공중형인 만큼 지상 프로토와 차별점") =====
-- 기체 속성 MechType(템플릿에 박음 — AeroTemplate = "Aero") → 아래 표에 있는 키만 덮어씀. 없는 키는 위 공용 값(지상 프로토 = 덮어쓰기 없음).
-- 종류마다 다를 수 있는 값을 읽는 곳은 CFG.stat(기체, 키) 를 쓴다: 이속 · 게이지 · 지속 부스트 · 상승 · 낙하 중력 · 위 속도 안전장치
CFG.Types = {
	Aero = {   -- 공중 프로토
		WalkSpeed = 14,           -- 걷기(지상 18): 땅에선 느리고 하늘에서 강함 [결정 18:24 "공중 프로토 이속 낮춤"]
		-- 10-26 23:54 유저 "부스트 게이지를 확 늘려줘. 비행 기체라기엔 비행 시간이 너무 짧아" → 용량 150 → 450(×3), 회복 30 → 45.
		--   상승(공중 소모 45/초) 꽉 찬 게이지로 3.3초 → 10초 · 다 쓴 뒤 다시 참 5초 → 10초 · 대시(30)는 5번 → 15번 [계산]
		MaxEnergy = 450,          -- 게이지 용량(지상 100) [결정 18:24 "게이지 용량·회복 증가" → 23:54 확 늘림]
		EnergyRegen = 45,         -- 초당 회복(지상 22)
		BoostHoldSpeed = 75,      -- 지속 부스트 속도(지상 60) [결정 "지속 부스트 더 빠르게"]
		Climb = true,             -- 공중에서 점프 키를 누르고 있으면 상승(제트팩) [결정 "공중에서 점프 키 누르면 상승"]
		ClimbSpeed = 32,          -- 상승 속도(스터드/초). 게이지는 지속 부스트와 같은 통로로 깎임(공중 = BoostHoldDrain × BoostAirDrainMul = 36/초 → 꽉 찬 450 으로 쉬지 않고 약 12.5초)
		-- 10-27 유저 "지금도 부스트는 나쁘지 않아. 공중 부스트 소모는 좀 줄이되 게이지의 회복은 땅에서만":
		--   예전(공중 회복 45/초 = 상승 소모 45/초)은 오르내리기만 하면 게이지가 안 줄어 끝없이 떠 있었음(오를 때 수평 부스트도 같은 통로라 공짜) [시뮬 rig 밖 sim/duel.py]
		--   → 공중 소모 45 → 36(×1.2) + 땅에서만 회복. 띠 44~56 오르내리며 오를 때 수평 부스트: 꽉 찬 게이지로 약 29초 떠 있음(45 였다면 23 · 30 이면 34) → 내려와 10초면 다시 가득 [시뮬]
		BoostAirDrainMul = 1.2,
		AirRegen = false,
		ClimbAccel = 140,         -- 상승 힘 = 질량 × (중력 + 이것) → 약 0.23초에 ClimbSpeed
		JumpFallGravity = 70,     -- 내려올 때 중력(지상 139): 상승을 놓으면 천천히 내려옴
		RiseCap = 40,             -- 위 속도 안전장치(지상 25 — 충돌 솟구침 대비). 상승 32 를 막지 않게 올림
		-- 10-26 23:1x 템플릿이 LF-01 AELLO(리메이크, 키 27.7 — 옛 엔진형 17.8)로 바뀜 → 몸 크기 값만 중장갑 식으로. 성능·비행 수치는 위 그대로
		StrideLength = 28.6,      -- 다리 허벅지 6.21 + 정강이 7.80 = 14.0 [실측 관절] → 중장갑 24.5 × 14.0 / 12.0
		-- 카메라 10-27 메카 브레이크식(옛 8.2 / 37 / 8.2 / 2.8 / 줌 30 / 9.4): 머리 꼭대기 9.87 [실측] + 여유 1.75 = 조준선 11.6.
		--   펼친 날개(공중 55° · 공중 부스트 35°+28°)는 화면 양옆으로만 감 — 위를 65° 봐도 조준점 안 가림 [복셀 렌더 aello_cam.py]
		CameraFocusHeight = 6.8,
		CameraDistance = 40,      -- 13:13 유저 "거리 40 으로 다시 보고 싶어"(46 에서 확대 시험)
		CameraShoulderX = 0,
		CameraShoulderY = 4.8,
		CameraLookUpRise = 1.5,
		ZoomCameraDistance = 33,  -- 거리 40 에 맞춰(38 × 40/46)
		ZoomShoulderX = 0,
		-- 10-26 23:27 유저 "빔사벨 색을 노랑으로" — AELLO 만(중장갑은 10-27 부터 열선 도끼 주황 — Heavy 쪽). 읽는 곳: MechClient meleeHit(적중 번쩍) · saberParts(빛 막대·궤적·불빛)
		--   날 심(SaberBlade)은 템플릿 파트 색이라 AeroTemplate 쪽을 따뜻한 흰색으로 바꿈
		SaberColor = Color3.fromRGB(255, 205, 40),
	},
	Heavy = {  -- 대표 기체 중장갑 r2(10-26): 키 28.5 = 프로토 22.6 의 1.26배. 성능 수치는 프로토 그대로(밸런스 미정), 몸 크기에 따른 값만
		StrideLength = 24.5,      -- 다리 1.3배(허벅지 5.0·정강이 7.0) → 보폭도 그만큼. 안 그러면 같은 속도에 발이 미끄러져 보임
		-- 카메라 10-27 메카 브레이크식(옛 8.2 / 37 / 8.2 / 2.8 / 줌 30 / 9.4): 조준선 = 뿌리 위 14.8 = 머리 13.05 · 백팩 13.4 [실측] 위.
		--   기체 화면 가로 39~61% · 머리 52%(MB 팔콘 41~59% · 53%). 정면 적 조준 시 보이는 몫 34~41% → 62~67% [복셀 렌더 camtry.py · occl_enemy.py]
		CameraFocusHeight = 10,
		CameraDistance = 40,      -- 13:13 유저 "거리 40 으로 다시 보고 싶어"(46 에서 확대 시험)
		CameraShoulderX = 0,
		CameraShoulderY = 4.8,
		CameraLookUpRise = 1.5,   -- 없으면 위 65° 에서 안테나 끝이 조준점 0.8% 아래까지 옴
		ZoomCameraDistance = 33,  -- 거리 40 에 맞춰(38 × 40/46)
		ZoomShoulderX = 0,
		-- 10-27 근접 무기 = 열선 도끼(빔사벨 자리 그대로: R 뽑아 베기 · 2 들기 · 3연격). 열선 주황 = 팔레트 발광색(6) — 궤적·불빛·적중 번쩍
		SaberColor = Color3.fromRGB(255, 150, 60),
		-- 10-27 20:xx 열선 도끼 두 손 3연격(유저 18:33 "무겁다는 컨셉이니 두 손으로 잡고 때리게" · 19:54 "보상 없음 · 데미지 120/100/180 동의 · R 뽑아 베기는 한 손 그대로").
		--   근접 수치를 기체별로(아래 Melee — 서버 meleeSpecFor · 클라 meleeSpec 가 읽음). 없는 기체(AELLO·프로토·적)는 위 공통 Slash* 그대로.
		--   시각 = 실제 초(slow 1 — 공통 SaberSlow 1.25 는 이 기체 3연격엔 안 곱함, R 뽑아 베기 'saber' 는 공통 그대로).
		--   자세·판정 시각 [rig/axe2h.py · axe2h_export.py]: 들기·감기·당기기를 길게, 내려치는 순간은 짧게 — 맞는 시각 1타 0.42 · 2타 0.38 · 3타 0.33(빔사벨 × 1.25 = 0.26 · 0.19 · 0.20)
		--   초당 피해: 3연격 다 맞힘 400 / (0.56 + 0.52 + 1.5) ≈ 155 (빔사벨 149) · 1타만 반복 120 / 1.1 ≈ 109 (빔사벨 111)
		Melee = {
			-- 10-27 23:2x 유저 "육중한 맛을 더 · 공속 더 느리게 · 데미지 그대로 · 멈칫+흔들림 넣기": 모으기 길게 → 꼭대기 정지 → 치기는 빠르게 → 마무리 처짐 정지 → 천천히 복귀.
			--   3연격 2.1 → 3.1초 · 맞는 시각 1타 0.62 · 2타 0.56 · 3타 0.53(옛 0.42 · 0.38 · 0.33) [rig/axe2h_heavy.py SEQ_H · MELEE_H, 시각표 _preview_1027/axe_heavy_timing.png]
			--   초당 피해 400 / (0.90 + 0.82 + 1.85) ≈ 112(옛 155) · 1타만 반복 120 / 1.45 ≈ 83
			--   hitStop = 맞으면 휘두르는 쪽 동작이 그만큼 멈칫(초, 클라 meleeHold) · hitShake = 그때 내 화면 흔들림(옛 근접 0.3 · 착지 1.0)
			slow = 1,
			slash3Cooldown = 1.85,   -- 3타 시작 뒤 다시 1타까지(3타 동작 1.37)
			slash1 = { time = 1.40, strike = 0.62, activeEnd = 0.74, chain = 0.90, lunge = 6, lungeTime = 0.55, damage = 120, cooldown = 1.45, trail = { 0.50, 0.90 }, swingAt = 0.50, hitStop = 0.08, hitShake = 0.6 },
			slash2 = { time = 1.32, strike = 0.56, activeEnd = 0.70, chain = 0.82, lunge = 3, lungeTime = 0.48, damage = 100, cooldown = 1.45, trail = { 0.46, 0.82 }, swingAt = 0.46, hitStop = 0.06, hitShake = 0.45 },
			slash3 = { time = 1.37, strike = 0.53, activeEnd = 0.82, chain = 99, lunge = 8, lungeTime = 0.48, damage = 180, cooldown = 1.45, range = 22, arc = 35, trail = { 0.48, 0.66 }, swingAt = 0.48, hitStop = 0.10, hitShake = 0.9 },
		},
	},
	-- 10-28 HORKOS(ST-01, 주인공 딜러 · Rodin 몸 2칸 블록): 성능 수치는 공용(지상 프로토) 그대로, 몸 크기에 따른 값만 [rig/horkos_template_data.py]
	Horkos = {
		StrideLength = 24.9,      -- 허벅지 4.29 + 정강이 7.89 = 12.2 [관절 거리] → 중장갑 24.5 × 12.2 / 12.0
		-- 카메라 = 중장갑 식: 머리(머리카락) 꼭대기 뿌리 위 13.15 [복셀] + 여유 1.75 = 조준선 14.9 → 10 + 4.8
		CameraFocusHeight = 10,
		CameraDistance = 40,
		CameraShoulderX = 0,
		CameraShoulderY = 4.8,
		CameraLookUpRise = 1.5,
		ZoomCameraDistance = 33,
		ZoomShoulderX = 0,
		SaberColor = Color3.fromRGB(90, 235, 255),   -- 빔사벨 = 몸 발광색(청록, 팔레트 6)
	},
	-- 10-29 SKADI(LT-01 · SNIPER · 경량 지상 저격, 전용 저격총 = 공용 Guns.sniper 수치): 성능 수치는 공용 그대로, 몸 크기에 따른 값만 [sniper/skadi_template_data.py]
	Skadi = {
		StrideLength = 28.0,      -- 허벅지 6.30 + 정강이 7.40 = 13.7 [템플릿 관절점] → 중장갑 24.5 × 13.7 / 12.0
		-- 카메라 = AELLO 식: 머리 꼭대기 뿌리 위 9.03 [에디트 실측 SkadiTemplate] + 여유 1.75 = 조준선 10.8 → 6.0 + 4.8
		CameraFocusHeight = 6.0,
		CameraDistance = 40,
		CameraShoulderX = 0,
		CameraShoulderY = 4.8,
		CameraLookUpRise = 1.5,
		ZoomCameraDistance = 33,
		ZoomShoulderX = 0,
		SaberColor = Color3.fromRGB(90, 255, 160),   -- 빔사벨 = 몸 발광색(초록, 팔레트 6). 근접은 나중에 발차기로 바뀔 예정(스킬 결정 10-29)
	},
}
-- 땅굴 출격대(BayPad · UndergroundLaunch)에 보급할 기체 = MechProto 안 템플릿 이름(10-26 유저 "땅굴 출격으로 연결").
-- "MechTemplate" 로 바꾸면 옛 지상 프로토가 나온다. 적 메카(MechEnemy)는 계속 프로토
CFG.GroundTemplate = "HeavyTemplate"
-- 10-30 SKADI 앞차기(근접 R — 템플릿 속성 Melee = "Kick", 빔사벨 없음): 왼다리 정강이 칼날 앞차기 1타 · 맞으면 넉백 + 경직 [저격기_현재상태_20261029 4절 결정]
--   자세 = MechClient SHAPES.Skadi.kick(당기기 C · 뻗기 X) [sniper/rig/kick_check.py: 몸·총·팔과 겹침 0, 키 사이 경로 포함] · 뻗은 발끝 = 몸 앞 17.5
--   판정 = 서버 MELEE.kick(주먹과 같은 한 번 판정, SaberSlow 안 곱함). 넉백 = 작살 그랩과 같은 끌림 속성(PullTo · PullTime · StunUntil) — 맞은 쪽 화면이 직접 밀려남
CFG.Kick = {
	Damage = 60, Cooldown = 4,
	Time = 0.75,        -- 동작 전체(당기기 0~0.12 · 뻗기 ~0.20 · 버팀 ~0.32 · 복귀)
	Strike = 0.18,      -- 판정 순간(다 뻗기 직전)
	Range = 13, Arc = 45,   -- 몸 중심끼리 수평 거리 − 상대 몸 반지름(4). 발끝 17.5 앞 → 13 + 4
	Lunge = 4, LungeTime = 0.14,   -- 내딛기(주먹과 같은 고정 거리, 판정 전에 끝남)
	KnockDist = 16, KnockTime = 0.3, Stun = 0.3,   -- 밀려나는 거리·시간 · 그 뒤 경직(벽이 있으면 벽 앞 4 에서 멈춤). 10-30 10:5x 유저 넉백 14 → 22 · 11:37 "상대가 덜 밀려도 좋으니 후퇴를 더 멀리" → 16
	-- 10-30 10:48 유저 "발차기를 하는 동시에 상대 기체를 디딤발 삼아 뒤로 공중제비 돌아서 한 바퀴 돌아 착지" · 10:5x 결정: 맞았을 때만 · 내 후퇴 약 15
	--   맞으면 서버가 찬 기체 속성 FlipAt(뜨는 서버 시각 = 판정 + Delay) · FlipTo(착지 자리, 뒤 Back — 벽이 있으면 그 4 앞) · FlipFace(찬 방향)
	--   → 조종 화면이 포물선(꼭대기 Height)을 직접 따라감(MechClient GR.flipDrive) · 모든 화면이 웅크리고 뒤로 한 바퀴(SHAPES.Skadi.flip, PO.flipPose)
	--   동안 = 경직처럼 아무것도 못 함(CFG.stunned 에 포함 — 판정 순간부터 착지까지). 끌리면(작살·넉백) 공중제비 취소
	--   [sniper/rig/flip_check.py H 8 · T 0.8: 공중 최저 3.7(총구) · 다리 ↔ 몸·총·팔 겹침 0 · 키 사이 41 등분]
	--   10-30 11:22 유저 "제자리 공중제비 같은 느낌 — 돌면서 멀어져야" → 잼(rig/flip_travel.py): 옛 회전 중심(골반 앞 3.3)이 앞 절반 동안 몸을 그만큼
	--     앞으로 휘게 해 뒤로 간 거리를 지웠음(k 0.45 에 골반 0.2 뒤 = 제자리). → 중심 = 골반(SHAPES.Skadi.flip.center) · 수평 = 박차고 빠르게(GR.flipDrive u(2−u))
	--     → k 0.45 에 골반 10 뒤. 중심을 옮기니 총구가 땅에 0.9 까지 내려와 꼭대기 8 → 11(공중 최저 3.4 · 겹침 0)
	--   11:37 유저 "후퇴를 더 멀리" → Back 15 → 25(넉백 22 → 16 과 맞바꿈 — 둘 사이 벌어짐 37 → 41). 수평 이동만 늘어 땅 여유·겹침 검사 결과는 같음
	--   11:38 유저 "공중제비 동작 자체도 좀 더 길게" → Time 0.8 → 1.1 [flip_check.py H 11 · T 1.1: 공중 최저 3.4 · 겹침 0 — 0.8 과 같음]
	--   11:40 유저 "0.9초로 해보자" → Time 1.1 → 0.9 (0.8 · 1.1 둘 다 검사 통과 — 사이 값이라 같음)
	Flip = { Delay = 0.06, Time = 0.9, Back = 25, Height = 11 },
}
function CFG.flipPhase(m, now)   -- 공중제비 진행 0~1(뜬 뒤 · 착지 전) 아니면 nil. 끄는 코드 없이 시각으로(FlipAt 은 남아 있어도 지나면 nil)
	local at = m and m:GetAttribute("FlipAt")
	if not at then return nil end
	local e = (now or workspace:GetServerTimeNow()) - at
	if e < 0 or e >= CFG.Kick.Flip.Time then return nil end
	return e / CFG.Kick.Flip.Time
end
-- ================= 10-30 SKADI 시그니처: 앵커 자세 (C — F 는 하차라 FELSEN 작살과 같은 키, 템플릿 속성 Signature = "Anchor") =================
-- 오른 무릎을 꿇고 정강이 칼날을 땅에 박음(MechClient SHAPES.Skadi.anchor [sniper/rig/anchor_solve.py]) · 꿇기 Kneel · 풀기 Rise [결정 10-29]
-- 동안: 이동·점프·부스트·근접 못 함(회전만) · 다 꿇으면(on) 저격총 Modes.Anchor = 피해 ×1.4(308) · 줌 6배 · 반동 0 · 시간 제한 없음 · 꿇거나 일어나는 중엔 못 쏨
-- 다시 C(또는 넉백·끌림)로 풀림 → Rise 뒤 Cooldown. 끌리면(작살·앞차기 넉백) 바로 일어나기 시작
-- 상태 = 서버 속성 AnchorAt(꿇기 시작) · AnchorRiseAt(일어나기 시작) · AnchorReadyAt(다시 쓸 수 있는 시각) — 끄는 코드 없이 시각으로 계산(고착 없음)
CFG.Anchor = {
	Kneel = 0.4, Rise = 1.0, Cooldown = 6,
	DamageMul = 1.4, ZoomMag = 6,
	PitchMin = -30,   -- 꿇은 채 아래로 겨누는 한계(도). −40° 면 총구가 땅에 닿음 [에디트 FK: 총구 높이 0° 13.9 · −20° 6.5 · −40° −0.1]
	Drop = 8.15,      -- 꿇으면 골반이 내려가는 거리(스터드, 루트 관절 기준) [anchor_scan "-28_11"]. 읽는 곳 = MechClient 꿇기 자세 · 카메라 높이
	                  --   (서버 사격은 화면이 보낸 총구를 씀 — MechServer gunReach 여유 10 이 이 값을 덮음)
}
local function sm01(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
-- 돌려주는 값: 상태("kneel" | "on" | "rise" | nil), 꿇은 정도 0~1. 꿇다가 풀면 그때 정도에서 일어남
function CFG.anchorPhase(m, now)
	local at = m and m:GetAttribute("AnchorAt")
	if not at then return nil, 0 end
	now = now or workspace:GetServerTimeNow()
	local A = CFG.Anchor
	local rise = m:GetAttribute("AnchorRiseAt")
	if rise then
		local e = now - rise
		if e >= A.Rise then return nil, 0 end
		return "rise", sm01((rise - at) / A.Kneel) * (1 - sm01(e / A.Rise))
	end
	local e = now - at
	if e < A.Kneel then return "kneel", sm01(e / A.Kneel) end
	return "on", 1
end
do   -- 저격총 앵커 표: 저격총 값 복사 + 피해 ×DamageMul · 줌 ZoomMag · 반동 0
	local s = CFG.Guns.sniper
	local a = {}
	for k, v in pairs(s) do a[k] = v end
	a.Damage = math.floor(s.Damage * CFG.Anchor.DamageMul + 0.5)
	a.ZoomMag = CFG.Anchor.ZoomMag
	a.Kick = 0          -- 반동 자세·화면 튐 없음
	a.BigFlash = true   -- 총구 불꽃은 저격총 그대로 크게(옛 판정 "Kick > 1" 이 0 이 되며 작아지지 않게)
	s.Modes = { Anchor = a }
end

-- ================= 10-30 궁극기 공용 게이지 (X) — 유저 10-30 "Dealt + taken" (10-26 제안 그대로) =================
-- 모든 기체 공용: 게이지 = 준 피해 + 받은 피해 × TakenMul(받는 쪽이 더 빨리 참 = 역전 장치). Max 가 차면 X 로 그 기체의 궁극기 발동 → 0 부터 다시
--   (기체의 궁극기 = 템플릿 속성 Ultimate. 지금은 SKADI "ForcedAnchor" 하나 — 없는 기체는 게이지만 참)
-- 셈: 가해자가 있는 피해만(시험장 피해 발판·자기 미사일 X) · 실제로 깎인 HP 만큼(넘친 피해 X) · 궁극기 쓰는 동안은 안 참
-- 서버 = MechDamage.hurt(가해자 있는 TakeDamage 는 전부 이걸 거침) → 기체 속성 UltGauge(0~Max) · 화면 = HUD 오른쪽 BOOST 밑 ULT 막대
CFG.Ult = { Max = 1500, TakenMul = 1.5, Key = Enum.KeyCode.X }
-- SKADI 궁극기 "강제 앵커 연사"(Ultimate = "ForcedAnchor") [결정 10-29 22:37 · 22:39 — 저격기_현재상태 4절]
--   X → 그 자리에서 강제 앵커: 이미 다 꿇었으면 바로 · 아니면 꿇기(Kneel 0.4) 끝나는 순간부터 Duration 초 사격 창
--   창 동안: 저격총 Modes.Ult = 피해 ×DamageMul(330) · 간격 FireInterval(0.7) · 탄창 무한(최대 9발) · 지형 관통 없음(보통 사격과 같은 판정) · 총구에서 초록 레이저(모든 화면)
--   C(앵커 풀기) 막힘 · 끌림·넉백에 안 밀림(경직은 먹음 — 쏘지 못함) [제안] · 끝나면 탄창 가득 · 원래 앵커였으면(UltKeep) 꿇은 채, 아니었으면 일어남(Rise 1.0 → 앵커 쿨 6)
--   상태 = 속성 UltStart · UltEnd(서버 시각) · UltKeep — 시각으로 계산(끄는 코드에 못 가도 저절로 끝남). 끝 처리(탄창·일어남)는 MechServer ULT.step
CFG.ForcedAnchor = { Duration = 6, DamageMul = 1.5, FireInterval = 0.7 }
function CFG.ultPhase(m, now)   -- "pending"(꿇는 중 — 창 전) | "active"(사격 창) | nil
	local s, e = m:GetAttribute("UltStart"), m:GetAttribute("UltEnd")
	if not (s and e) then return nil end
	now = now or workspace:GetServerTimeNow()
	if now >= e then return nil end
	if now < s then return "pending" end
	return "active"
end
do   -- 저격총 궁극기 표: 앵커 표 복사 + 피해 ×1.5 · 간격 0.7 · 탄창 무한(NoAmmo)
	local s = CFG.Guns.sniper
	local u = {}
	for k, v in pairs(s.Modes.Anchor) do u[k] = v end
	u.Damage = math.floor(s.Damage * CFG.ForcedAnchor.DamageMul + 0.5)
	u.FireInterval = CFG.ForcedAnchor.FireInterval
	u.NoAmmo = true
	-- 10-30 10:37 유저 "궁극기 광선도 빨강 — 레이저 조준이랑 약간 다르게 분홍빛 도는 빨강": 탄도선 색만(굵은 저격 탄도선 모양 그대로)
	--   조준 레이저 = MechClient GR.ULT_RED (255, 56, 72) · 광선 = 분홍 쪽 빨강 → "겨누는 중" 과 "쐈다" 가 색으로도 갈림. 평소·앵커 탄도선은 청백 그대로
	u.TracerGlow = Color3.fromRGB(255, 80, 145)
	u.TracerCore = Color3.fromRGB(255, 225, 238)
	s.Modes.Ult = u
end
-- ================= 10-30 FALCO 시그니처: 라이더킥 (C — 템플릿 속성 Signature = "RiderKick") =================
-- 유저 10-30 "컨셉으로만 남겨뒀던 팔코 스킬들을 구현하자" · 결정: 공중에서만 · 맞으면 튕겨 나와 착지(상대는 찬 방향으로 밀림 + 짧은 경직) · 피해 120 · 쿨 8 · 사거리 70 · 속도 120
--   설계 = aero_r1.md 17절(조준 방향 고정 사선 급강하 · 사용 중 슈퍼아머 = CC 면역, 피해는 받음 · 날개 = 부스트 자세) · 자세 = 유저 레퍼런스(가면라이더 V3 킥 피규어)
-- 흐름: C → 조종 화면이 바로 시작(Ready 동안 그 자리에 멈춰 자세를 잡음 → Speed 로 RKDir 따라 곧게, PlatformStand · 매 프레임 CFrame)
--   맞음 = 조종 화면이 발끝 ↔ 상대 몸(세로 막대 CFG.bodyDist)으로 재서 "hit" → 서버가 다시 재고 피해·넉백·경직 → 나는 뒤로 튕겨 땅에 내려섬(Bounce)
--   땅·벽에 발이 닿거나 Range 를 다 가면 "stop" → Recover 동안 자세 풀림(물리로 떨어짐)
-- 상태 = 서버 속성 RKAt(시작) · RKDir · RKFrom · RKHitAt · RKStopAt · RKReadyAt(쿨) — 시각으로 계산(끄는 코드 없음, 다 가면 저절로 끝)
-- 동안 = CFG.stunned 에 포함(사격·부스트·근접·다른 기술 다 막힘) · 슈퍼아머 = CFG.superArmor(끌림·넉백·경직을 안 받음)
-- 화면 = MechClient.MechFalco · 판정 = MechServer RK
CFG.RiderKick = {
	Damage = 120, Cooldown = 8,
	Range = 70, Speed = 120,          -- 급강하 길이·속도 → 최대 0.58초
	Ready = 0.18,                     -- 누르고 그 자리에서 자세를 잡는 시간 [제안]
	MinDown = 20, MaxDown = 45,       -- 급강하 각(수평 아래, 도). 조준이 이보다 얕으면(위를 봐도) MinDown · 가파르면 MaxDown — 10-30 유저 "가장 가파른 각 45도"(옆차기가 60° 부터 내려찍기처럼 보임, 그 전 80)
	HitRadius = 7,                    -- 발끝 ↔ 상대 몸 세로 막대(CFG.bodyDist) 거리 [제안]
	-- 10-30 맞으면(유저 "상대를 밀고 가다 마지막에 크게 날림 · 추가 동작 없이 만화풍으로 피해를 누적받다 날아가는 느낌") [제안]:
	--   Carry = 찬 방향(수평)으로 Time 동안 Dist 끌고 감(앞차기 넉백과 같은 길 — 벽 앞 4 에서 멈춤) · 닿는 순간부터 Gap 마다 TickDamage × Ticks
	--   Launch = 끌고 간 끝에서 나머지 피해(Damage − Ticks × TickDamage = 60) + 찬 방향 Dist 날림(꼭대기 Arc 포물선) + 경직 Stun
	--   합계 피해 = Damage 그대로(120). 나(찬 기체)는 끌고 가는 동안 상대를 따라가고(슈퍼아머) 날리면 Bounce 대로 튕김
	Carry = { Time = 0.5, Dist = 24, Stun = 0.3, Ticks = 5, Gap = 0.1, TickDamage = 12 },
	Launch = { Dist = 60, Time = 0.7, Arc = 12, Stun = 0.5 },
	Bounce = { Time = 0.5, Back = 14, Height = 6, Drop = 30 },   -- 나: 맞힌 자리에서 뒤로 Back 땅에 내려섬(꼭대기 Height, 한 번에 Drop 까지만 내려옴 — 더 높으면 그 뒤 떨어짐) [제안]
	Recover = 0.3,                    -- 안 맞고 끝나면 자세가 풀리는 시간
	-- 10-30 날아 옆차기(MechFalco F.POSE): 다리를 옆으로 35° 든 키 자세 → 몸을 차는 반대쪽으로 젖히는 각 = Alpha − 급강하 각(Alpha = 90 − 35)
	--   (급강하 20° 면 35° 젖힘 · 45° 면 10° — 차는 다리가 늘 급강하 방향과 한 줄) [에디트 FK 실측, 그 전 앞으로 내지르기 자세는 70]
	Alpha = 55,
}
-- 조준 방향 → 급강하 방향(수평은 그대로, 아래 각만 MinDown ~ MaxDown 으로)
function CFG.riderDir(v)
	local K = CFG.RiderKick
	local fl = Vector3.new(v.X, 0, v.Z)
	local flat = fl.Magnitude > 1e-3 and fl.Unit or Vector3.new(0, 0, -1)
	local down = math.clamp(math.deg(math.atan2(-v.Y, fl.Magnitude)), K.MinDown, K.MaxDown)
	local r = math.rad(down)
	return flat * math.cos(r) - Vector3.new(0, math.sin(r), 0)
end
-- "ready"(자세 잡기) | "dive"(급강하) | "carry"(맞고 끌고 감 — 속성 RKCarry 초) | "bounce"(맞고 튕김) | "recover"(안 맞고 끝 — 자세 풀림) | nil, 진행 0~1
function CFG.riderPhase(m, now)
	local at = m and m:GetAttribute("RKAt")
	if not at then return nil end
	now = now or workspace:GetServerTimeNow()
	local K = CFG.RiderKick
	local e = now - at
	if e < 0 then return nil end
	if e < K.Ready then return "ready", e / K.Ready end
	local hit, stop = m:GetAttribute("RKHitAt"), m:GetAttribute("RKStopAt")
	if hit and hit < at then hit = nil end
	if stop and stop < at then stop = nil end
	if hit then
		local eb = now - hit
		if eb < 0 then return "dive", 1 end
		local c = m:GetAttribute("RKCarry")   -- 10-30 끌고 가는 시간(서버가 맞을 때 씀 · 아군·슈퍼아머·기체 아님이면 없음)
		if typeof(c) == "number" then
			if eb < c then return "carry", eb / c end
			eb -= c
		end
		if eb < K.Bounce.Time then return "bounce", eb / K.Bounce.Time end
		return nil
	end
	local diveT = K.Range / K.Speed
	local endT = stop or (at + K.Ready + diveT)
	if now < endT then return "dive", math.clamp((e - K.Ready) / diveT, 0, 1) end
	local er = now - endT
	if er < K.Recover then return "recover", er / K.Recover end
	return nil
end
function CFG.superArmor(m, now)   -- 끌림·넉백·경직을 안 받음(피해는 받음)
	return CFG.riderPhase(m, now) ~= nil or CFG.leapPhase(m, now) == "fly" or CFG.chargePhase(m, now) ~= nil   -- 10-30 FELSEN 궁극기 날아가는 동안 · 돌진 내내
end
-- 점 p 와 기체 몸(뿌리 아래 RootHeight × 0.75 ~ 위 8 의 세로 막대) 사이 거리 — 라이더킥 맞음(화면·서버 같은 식)
function CFG.bodyDist(o, p)
	local r = o and o:FindFirstChild("HumanoidRootPart")
	if not r then return math.huge end
	local c = r.Position
	local rh = o:GetAttribute("RootHeight") or 10
	local y = math.clamp(p.Y, c.Y - rh * 0.75, c.Y + 8)
	return Vector3.new(c.X - p.X, y - p.Y, c.Z - p.Z).Magnitude
end
-- ================= 10-30 FALCO 궁극기: 마비 덫 (X — 템플릿 속성 Ultimate = "ParalysisTrap") =================
-- 결정(현재상태_20261026 5-6 · 10-30 한 변 32): 조준 지점 둘레에 등의 못 4개를 박고(위치는 누르는 순간 고정) 0.5초 뒤 못끼리 전기가 이어지면
--   그 사각형 안이 5초 마비 지대 — 보이는 전기선 = 판정 경계. 효과 = 둔화(이동·부스트·선회 ÷1.5) + 동작 지연(빔사벨·사격 간격·사격 동작·장전 ×1.5),
--   사격은 가능 · 높이 제한(공중은 안 걸림) · 아군 제외. 공중에서도 쏠 수 있음
-- 상태 = 쏜 기체 속성 TrapAt · TrapPos(가운데 땅) · TrapYaw → CFG.trapPhase. 걸린 기체 = SlowUntil(서버가 안에 있는 동안 계속 늘림 — 나가면 저절로 만료) · SlowAt(이번 둔화 시작)
-- 배율은 CFG.slowMul 하나를 곱하는 곳마다(이미 시작한 동작은 시작할 때 배율로 끝까지 — 속성 MeleeSlow · ReloadSlow)
CFG.Trap = {
	Side = 32,              -- 사각형 한 변 [결정 10-30]
	Range = 150,            -- 조준점이 이보다 멀면 이 거리까지 [제안]
	FlyTime = 0.45,         -- 못이 날아가 박히기까지 [제안]
	LinkDelay = 0.5,        -- 박히고 전기가 이어지기까지 [결정 10-26]
	Duration = 5,           -- 지대 [결정]
	SlowMul = 1.5,          -- [결정 10-26 20:24]
	Rise = 6, Below = 4,    -- 높이 제한: 뿌리가 땅 + RootHeight + Rise 보다 높으면(공중) 안 걸림 [제안 — 지뢰와 같은 값]
	Refresh = 0.3,          -- 안에 있으면 SlowUntil = 지금 + 이것(남은 게 0.15 아래일 때만 다시 씀 — 매 틱 복제 안 하게)
	-- 10-30 14:2x 유저 "스카디 궁 밸류에 비해 팔코 궁이 너무 약해 — 조준이 쉬운 것도 범위가 넓은 것도 아니고" → 고른 안 = 전기선을 벽으로
	--   (그때 덫은 부스트 한 번이면 빠져나감 — 둔화 대시 77 × 0.32초 = 24.5 > 반 변 16 [계산])
	--   지대가 켜지는 순간 각 적이 안/밖 어느 쪽인지 기억 → 지대 동안 반대쪽으로 넘으면 감전: 피해 + 경직 + 원래 쪽으로 끌려 돌아감
	--   = 안의 적은 못 나가고 밖의 적은 못 들어옴 · 아군은 그냥 지나감 · 발이 벽 위(WallHeight)면 넘어감(점프 18.6 으로는 못 넘고 FALCO 상승으로는 넘음)
	WallHeight = 30,        -- 벽 높이(땅에서) = 화면의 전기 벽 높이 [제안]
	ShockDamage = 80,       -- 넘으려 할 때 피해 [제안]
	ShockStun = 0.6,        -- 끌려 돌아간 뒤 경직 [제안]
	ShockPull = 0.25,       -- 끌려 돌아가는 시간
	ShockPush = 5,          -- 벽에서 이만큼 안쪽(또는 바깥쪽)으로 돌려놓음
	ShockGap = 0.5,         -- 같은 기체 다시 감전까지(끌려가는 동안 두 번 맞지 않게)
}
function CFG.trapEnd(m)
	local at = m and m:GetAttribute("TrapAt")
	local T = CFG.Trap
	return at and (at + T.FlyTime + T.LinkDelay + T.Duration) or nil
end
-- "fly"(못이 날아감) | "arm"(박힘 — 전기 전) | "on"(지대) | nil, 진행 0~1
function CFG.trapPhase(m, now)
	local at = m and m:GetAttribute("TrapAt")
	if not at then return nil end
	now = now or workspace:GetServerTimeNow()
	local T = CFG.Trap
	local e = now - at
	if e < 0 then return nil end
	if e < T.FlyTime then return "fly", e / T.FlyTime end
	e -= T.FlyTime
	if e < T.LinkDelay then return "arm", e / T.LinkDelay end
	e -= T.LinkDelay
	if e < T.Duration then return "on", e / T.Duration end
	return nil
end
-- ================= 10-30 FELSEN 궁극기: 도끼 도약 내려찍기 (X — 템플릿 속성 Ultimate = "AxeLeap") =================
-- 유저 10-30 16:25~16:38: 조준 위치로 도끼를 머리 위로 들고 뛰어들어 착지하며 내려찍고 땅을 흔듦 · 가운데일수록 큰 피해 + 큰 흔들림 ·
--   착지 원은 적에게도 보임 · 날아가다 공중 적에 부딪히면 직격 피해(부딪혀도 그대로 날아감) · 날아가는 시간 1.2초 고정(거리 무관) · 준비 동작 없음
--   · 날아가다 몸 충돌은 공중에 뜬 적만(땅의 적은 착지 원으로만 맞음 — 멀리 쏴서 앞의 적을 몸으로 치고 지나가는 공짜 한 방 막기)
-- 판정 = MechServer LEAP · 화면 = MechClient.MechFelsen. 상태 = 속성 LeapAt(서버 시각) · LeapFrom · LeapTo · LeapGround → CFG.leapPhase(끄는 코드 없음)
CFG.Leap = {
	Range = 80,            -- 조준점까지 수평 최대(더 멀면 여기까지) [제안 · 유저 동의]
	Time = 1.2,            -- 날아가는 시간(거리 무관) [결정 16:32]
	Height = 25,           -- 포물선 꼭대기(출발·착지를 잇는 선 위로) [제안 · 동의]
	Radius = 20,           -- 착지 원(수평) = 화면 원 [제안 · 동의]
	CoreRadius = 6,        -- 가운데(가장 셈) [제안 · 동의]
	Core = 300,            -- 가운데 · 공중 직격 피해 [제안 · 동의]
	Edge = 80,             -- 원 가장자리 피해(가운데 → 가장자리로 곧게 줄어듦) [제안 · 동의]
	Down = 1.0,            -- 가운데 · 공중 직격 = 쓰러짐(경직) [제안 · 동의]
	HitHeight = 12,        -- 착지 피해 = 발이 원 바닥 ±이 안(땅 근처) [제안 · 동의]
	AirHeight = 12,        -- 공중 적 = 발밑 이 안에 아무것도 없음 [제안 — HitHeight 와 같은 값]
	AirHit = 10,           -- 날아가는 FELSEN 뿌리 ↔ 적 몸 막대(CFG.bodyDist) 이 안이면 부딪힘 [제안]
	DownTime = 0.45,       -- 부딪힌 공중 적이 바로 아래 땅으로 떨어지는 시간 [제안]
	Wall = 6,              -- 가는 길이 막히면 막힌 곳에서 이만큼 내 쪽에 내려찍음 [제안]
	Recover = 0.75,        -- 착지 뒤 도끼를 거두기까지(잠금) — 도끼 1타 마무리 길이(0.64 → 1.39) [실측: SHAPES.Heavy.combo2h slash1]
}
function CFG.leapPhase(m, now)   -- "fly"(날아감) | "land"(내려찍고 거둠) | nil, 진행 0~1
	local at = m and m:GetAttribute("LeapAt")
	if not at then return nil end
	now = now or workspace:GetServerTimeNow()
	local L = CFG.Leap
	local e = now - at
	if e < 0 then return nil end
	if e < L.Time then return "fly", e / L.Time end
	e -= L.Time
	if e < L.Recover then return "land", e / L.Recover end
	return nil
end
-- ================= 10-30 FELSEN 궁극기: 돌진 내려찍기 (X — 템플릿 속성 Ultimate = "AxeCharge") — 도약(AxeLeap)은 보관 =================
-- 유저 10-30 16:58 "사이온의 궁극기로": 긴 선딜(1초) + 앞으로 돌진하며 점점 가속(최대치) + 부딪힌 적·지형지물이 있으면 즉시 도끼를 내려찍으며 정지 +
--   맞은 적 큰 피해 · 주변 광역 · 17:02 꺾기 가능 · 멀리서 달려올수록 피해 · 공중 적도 멈추고 내려찍기 · 옆에 닿으면 밀쳐내고 계속
-- 판정 = MechServer CHG · 화면 = MechClient.MechFelsen. 상태 = 속성 ChargeAt · ChargeHitAt · ChargeHitPos → CFG.chargePhase(끄는 코드 없음)
CFG.Charge = {
	Windup = 1.0,          -- 선딜(도끼를 치켜들며 웅크림 · 방향은 카메라로 잡음) [결정 16:58]
	StartSpeed = 30, MaxSpeed = 110, AccelTime = 1.5,   -- 30 에서 1.5초에 최대 110 [제안 · 동의]
	MaxTime = 3.0,         -- 최대 달리기(약 270) — 다 달리면 그 자리에서 내려찍음 [제안 · 동의]
	TurnRate = 60,         -- 카메라 쪽으로 초당 꺾이는 각(도) [제안 · 동의]
	FrontAngle = 45,       -- 앞 부채꼴(진행 방향 좌우) — 여기 닿으면 멈추고 내려찍음 · 바깥은 옆(밀쳐냄) [제안 · 동의]
	Contact = 12,          -- 내 가슴 점 ↔ 상대 몸 막대(CFG.bodyDist) 이 안이면 닿음 [제안]
	BaseDamage = 150, PerStud = 1, MaxDamage = 400,   -- 직격 = 150 + 달린 거리(최대 400 — 거리 250) [제안 · 동의]
	Launch = { Air = 0.8, Height = 12, Total = 1.5 },   -- 10-30 18:09 유저 "맞은 적이 공중에 잠시 띄워지며 행동불능 1.5초" = 직격 기체를 그 자리에서 Height 만큼 띄웠다
	                       --   Air 초에 그 아래 땅으로 떨어뜨림(startPull 포물선 — FALCO 라이더킥 날림과 같은 길) · 맞은 때부터 Total 초 경직 [높이·체공 제안]
	AoeRadius = 15, AoeMul = 0.5, AoeStun = 0.5,   -- 광역 = 내려찍은 땅 둘레 · 직격의 절반 · 경직 [제안 · 동의]
	SideDamage = 50, SideStun = 0.3, SidePush = 12, SidePull = 0.25,   -- 옆에 닿음 = 밀쳐냄(돌진 계속) [제안 · 동의]
	Reach = 10,            -- 도끼가 땅에 닿는 자리 = 내 뿌리 앞 [제안]
	Swing = 0.22,          -- 멈추고 도끼가 땅에 닿기까지(피해 시각) = 자세 CH → W1 → S1 [MechFelsen 도끼 시각]
	Slam = 0.9,            -- 멈추고 도끼를 거두기까지(잠금) — 자세 1.0 → 1.9
}
function CFG.chargeDist(t)   -- 달리기 t 초에 간 거리(30 → 110 곧게 가속, 뒤는 일정)
	local C = CFG.Charge
	local a = C.AccelTime
	if t <= a then return C.StartSpeed * t + 0.5 * (C.MaxSpeed - C.StartSpeed) / a * t * t end
	return (C.StartSpeed + C.MaxSpeed) * 0.5 * a + C.MaxSpeed * (t - a)
end
function CFG.chargeSpeed(t)
	local C = CFG.Charge
	return C.StartSpeed + (C.MaxSpeed - C.StartSpeed) * math.clamp(t / C.AccelTime, 0, 1)
end
function CFG.chargePhase(m, now)   -- "windup" | "run" | "slam" | nil, 진행 0~1
	local at = m and m:GetAttribute("ChargeAt")
	if not at then return nil end
	now = now or workspace:GetServerTimeNow()
	local C = CFG.Charge
	local hit = m:GetAttribute("ChargeHitAt")
	if hit and hit >= at then
		local eh = now - hit
		if eh < 0 then return "run", 1 end
		if eh < C.Slam then return "slam", eh / C.Slam end
		return nil
	end
	local e = now - at
	if e < 0 then return nil end
	if e < C.Windup then return "windup", e / C.Windup end
	if e < C.Windup + C.MaxTime + 0.6 then return "run", math.clamp((e - C.Windup) / C.MaxTime, 0, 1) end
	return nil
end
function CFG.slowMul(m, now)   -- 마비 지대에 걸렸으면 1.5, 아니면 1
	local u = m and m:GetAttribute("SlowUntil")
	if u and u > (now or workspace:GetServerTimeNow()) then return CFG.Trap.SlowMul end
	return 1
end
-- 줌 배율: 꿇는 정도(0~1)만큼 기본 → 앵커 배율로 서서히(꿇기 끝나는 순간 3 → 6 으로 튀지 않게). 앵커 표가 없는 총은 그대로
function CFG.zoomMag(m)
	local g = m and m:GetAttribute("Gun")
	local G = (g and CFG.Guns[g]) or CFG.Guns.rifle
	local A = G.Modes and G.Modes.Anchor
	if not A then return G.ZoomMag end
	local _, w = CFG.anchorPhase(m)
	return G.ZoomMag + (A.ZoomMag - G.ZoomMag) * w
end
-- 10-29 조종사 제트팩(걸어 다니는 내 캐릭터 — ServerStorage.PilotJetpack · PilotJetpack* 스크립트, 유저 23:55 "Shift 누르면 게이지 소모하면서 부스트").
--   Shift 를 누른 채 움직이면 게이지를 쓰며 빨라짐. 시험장 이동용 수치(밸런스 아님). 읽는 곳: PilotJetpackClient
CFG.Jetpack = {
	BoostSpeed = 50,   -- 부스트 이속(기본 걷기 16 = StarterPlayer.CharacterWalkSpeed)
	Max = 100,         -- 게이지
	Drain = 20,        -- 초당 소모 → 꽉 찬 게이지로 5초
	Regen = 25,        -- 초당 회복 → 빈 게이지에서 4초
	RegenDelay = 0.6,  -- 부스트를 멈춘 뒤 회복 시작까지(초)
	MinRestart = 20,   -- 다 쓰면 Shift 를 떼고 이만큼 찰 때까지 못 씀(0 근처 깜빡임 방지)
}
-- 10-27 기체별 근접 수치(Types[MechType].Melee). 없으면 nil = 공통 Slash* 를 씀
function CFG.meleeOver(m)
	local t = m and m:GetAttribute("MechType")
	local o = t and CFG.Types[t]
	return o and o.Melee or nil
end
function CFG.stat(m, key)
	local t = m and m:GetAttribute("MechType")
	local o = t and CFG.Types[t]
	local v = o and o[key]
	if v ~= nil then return v end
	return CFG[key]
end

return CFG
