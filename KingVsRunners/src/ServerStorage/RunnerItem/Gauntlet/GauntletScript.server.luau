-- GauntletScript: 건틀렛 (서버)
-- ▸ 일반 공격(클릭/Activated): 단순 펀치, 데미지 PUNCH_DMG.
-- ▸ 스킬(DashRemote): 2단계 수동 연계.
--    1) 차징 돌진 — 누르는 시간=차징량. 차징 중 CHARGE_ANIM 재생. 떼면 돌진.
--       돌진이 태거에 명중하면 "오라오라 준비" 상태로 전환 → 클라에 "hitReady" 통보.
--    2) 오라오라 — 준비 상태에서 버튼을 다시 누르면 난타 발동. (※ 난타 본체는 다음 단계에서 구현)
-- 밸런스: 무한 접근 방지(쿨다운=플레이어 속성), 도망 악용 방지(빗나가면 후딜), 넉백 거의 없음.
-- 모든 수치는 상단 상수 — F5로 보며 튜닝.

local Players    = game:GetService("Players")
local Debris     = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

-- 컬러 커스텀 팔레트 모듈(부위별 색 적용). 없으면 색 적용은 조용히 건너뜀(기능 누락만, 에러 X).
local ColorPalette = nil
do
	local mod = ServerStorage:FindFirstChild("GauntletColorPalette")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then ColorPalette = result end
	end
end

-- ── 무지개 순환 스킨 ──────────────────────────────────────────
-- "rainbow"는 정적 색이 아니라 효과(매 프레임 hue 순환)라 별도 루프로 처리.
-- 부위별 독립: zoneColors에서 값이 "rainbow"인 부위(들)만 순환시킴.
-- (예: Body=흰색 고정 + Point=무지개 → 포인트만 hue가 돈다)
local RAINBOW_CYCLE = 3.0   -- 한 바퀴(빨~보~빨) 도는 시간(초)
local rainbowRunning = false
local rainbowConn = nil

local function stopRainbow()
	rainbowRunning = false
	if rainbowConn then rainbowConn:Disconnect(); rainbowConn = nil end
end

-- zoneColors를 보고, "rainbow"인 부위가 하나라도 있으면 그 부위들만 순환 시작.
-- 정적 색 부위는 applyZoneColors가 이미 칠했으므로 건드리지 않음.
local function startRainbow(zoneColors)
	stopRainbow()
	-- 무지개 대상 부위 집합
	local rainbowZones = {}
	local anyRainbow = false
	for _, zone in ipairs({"Body", "Point", "Handle"}) do
		if zoneColors[zone] == "rainbow" then
			rainbowZones[zone] = true
			anyRainbow = true
		end
	end
	if not anyRainbow then return end

	-- 무지개 부위 파트 목록 캐싱(매 프레임 GetDescendants 안 하도록)
	-- Tool 변수는 이 함수보다 아래(약 92줄)에서 정의되므로 여기선 script.Parent를 직접 사용.
	local toolRef = script.Parent
	local parts = {}
	for _, p in ipairs(toolRef:GetDescendants()) do
		if p:IsA("BasePart") then
			local z = p:GetAttribute("SkinZone")
			if z and rainbowZones[z] then
				p.Material = Enum.Material.Neon   -- 무지개는 발광이 예쁨
				p.Reflectance = 0                 -- 금색(반사0.4)에서 넘어와도 반사 잔존 방지
				table.insert(parts, p)
			end
		end
	end
	if #parts == 0 then return end

	rainbowRunning = true
	rainbowConn = RunService.Heartbeat:Connect(function()
		if not rainbowRunning then return end
		local hue = (tick() % RAINBOW_CYCLE) / RAINBOW_CYCLE
		local col = Color3.fromHSV(hue, 1, 1)
		for _, p in ipairs(parts) do
			if p.Parent then p.Color = col end
		end
	end)
end

-- 돌진이 박으면 안 되는 "벽" 개체 수집 (castle 폴더 전체 + Forest wall segment)
-- 정면에 이게 가까우면 박기 전에 멈춤 → 캐릭터 제어불가 방지.
local function collectWalls()
	local walls = {}
	local map1 = workspace:FindFirstChild("map1")
	if map1 then
		local castle = map1:FindFirstChild("map1 castle")
		if castle then table.insert(walls, castle) end   -- castleWall, left/right castle wall 전부
		for _, c in ipairs(map1:GetChildren()) do
			if c.Name:find("Forest map wall segment") then table.insert(walls, c) end
		end
	end
	return walls
end

local Tool       = script.Parent
local Handle     = Tool:WaitForChild("Handle")
local DashRemote = Tool:WaitForChild("DashRemote")
local ChargeSound = Handle:WaitForChild("ChargeSound")  -- 차징 중 재생(루프)
local HitSound    = Handle:WaitForChild("HitSound")     -- 돌진 적중 시 재생
local OverchargeSound = Handle:WaitForChild("OverchargeSound")  -- 차징 사운드 끝나도 홀딩 시 과충전 감전음
local FullChargeSound = Handle:WaitForChild("FullChargeSound")  -- 풀차징(2초) 도달 시 완료 사운드
local SwingSound = Handle:WaitForChild("SwingSound")  -- 일반공격(펀치) 스윙 사운드 (명중 여부 무관)

-- 과충전 시 켤 파티clos: 스파크(shock_Part.SparkAttachment) + 스모크(Handle의 GauntletSmoke)
local shockPart = Tool:FindFirstChild("shock_Part")
local sparkEmitters = {}
if shockPart then
	local att = shockPart:FindFirstChild("SparkAttachment")
	if att then
		for _, pe in ipairs(att:GetChildren()) do
			if pe:IsA("ParticleEmitter") then sparkEmitters[#sparkEmitters+1] = pe end
		end
	end
end
-- Handle에 부착한 스모크도 같은 목록에 추가 → 스파크와 완전 동일하게 켜고 꺼짐
for _, pe in ipairs(Handle:GetChildren()) do
	if pe:IsA("ParticleEmitter") and pe:GetAttribute("IsGauntletSmoke") then
		sparkEmitters[#sparkEmitters+1] = pe
	end
end
local function setSparks(on)
	for _, pe in ipairs(sparkEmitters) do
		pe.Enabled = on
		if on then pe:Emit(10) end   -- 켜는 순간 즉시 확 분사 (짧은 시간 안에 보이게)
	end
end
-- 부스터 제트(메카 건틀릿 스킨 전용): _SkinMesh의 BoosterFX Jet emitter를 스킬 중에만 켬.
local function setBoosters(on)
	local skinMesh = Handle:FindFirstChild("_SkinMesh")
	if not skinMesh then return end
	for _, pe in ipairs(skinMesh:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then
			pe.Enabled = on
			if on then pe:Emit(45) end
		end
	end
end
-- 평타(펀치): 부스터를 아주 짧게 켰다 끔 (순간 분사). 차징/돌진이 시작되면 punchBoostId를 올려 이 끄기를 무효화.
local punchBoostId = 0
local function punchBoosterFlash()
	punchBoostId = punchBoostId + 1
	local myId = punchBoostId
	setBoosters(true)
	task.delay(0.16, function()
		if myId == punchBoostId then setBoosters(false) end
	end)
end

-- 차징 중 활성화할 core 펄스 파티clos (core.AttachmentcorePoint 안) — flame tail에서 가져옴
local corePart = Tool:FindFirstChild("core")
local coreEmitters = {}
if corePart then
	local cp = corePart:FindFirstChild("AttachmentcorePoint")
	if cp then
		for _, pe in ipairs(cp:GetChildren()) do
			if pe:IsA("ParticleEmitter") then coreEmitters[#coreEmitters+1] = pe end
		end
	end
end
local function setCorePulse(on)
	for _, pe in ipairs(coreEmitters) do
		pe.Enabled = on
		if on then
			-- Rate가 낮아 천천히 누적되므로, 켜는 순간 Emit으로 즉시 확 분사 (짧은 시간 안에 다 보이게)
			pe:Emit(8)
		end
	end
end

-- ── 일반 공격(펀치) 상수 ─────────────────────────────────────
local PUNCH_DMG       = 28     -- 강철 건틀렛 평타
-- 🔺 [밸런스 2026-09-08] 22 → 28 / 돌진 20→26, 36→46 (약 1.28배).
--   [왜] 1대1 통제 실험(킹 HP 975 고정, 8종 20판)에서 7.3 DPS 로 하위권이었다.
--     Legendary 인데 기본 무기(ClassicSword 8.4)보다 낮다 — 등급과 성능이 어긋난다.
--   ⚠️ 아래 [계산]의 25.2 는 '펀치가 계속 들어간다' 가정이라 실측과 3배 넘게 벌어진다.
--     실측 타당 24.4(3위) · 타수 22회(최소) · 완주율 48~62%.
--     → 한 방은 무거운데 때릴 기회 자체가 적다. 원인은 구조다:
--       ① 사거리가 없어 반드시 붙어야 한다(해머로우처럼 거리를 둘 수 없다)
--       ② 붙으면 킹 강타(도달 12, 40딜)에 노출된다
--       ③ 차징 2.0초 > 킹 차징 1.5초 — 동시에 차징하면 킹이 먼저 터진다
--     "접근이 강제되는데 접근하면 맞는" 구조라, 위험 대비 총딜이 안 돌아온다.
--   ⚠️ 벽 슬램 보너스 50 은 실전에서 거의 안 나온 것으로 보인다(타당 24.4 가 그 증거 —
--     70~86 이 섞였다면 훨씬 높았을 것). 2단계 중정에 판정 가능한 벽이 드물다.
--     그래서 '벽을 성공시켜야 목표에 닿는' 설계가 하한을 낮게 만들었다. 하한 자체를 올린다.
--   ⚠️ 쿨(CD_FIXED 6.0)·차징 시간·벽 보너스는 건드리지 않는다. CC 가동률과 얽혀 있다.
--   ⚠️ 되돌릴 값: PUNCH_DMG 22 / DMG_MIN 20 / DMG_MAX 36
-- ⚠️ [밸런스 2026-08-29] 13 → 22 (돌진 12→20 / 24→36, 벽 보너스 14→50 과 세트).
--   [계산] Legendary 목표 28 DPS. 실효 사이클 = dashTime(0.18~0.42) + CD_FIXED 6 ≈ 6.4초.
--     돌진 중에는 펀치가 잠긴다(Tool.Activated 의 `if dashing then return end`).
--       펀치 22/1.0 × (5.7/6.4)   = 19.6 DPS
--       풀차징 돌진 36 / 6.4      =  5.6 DPS  → 기본 25.2
--       벽 슬램 시 (36+50)/6.4    = 13.4 DPS  → 벽   33.0
--   ⚠️ 벽을 성공시켜야 목표에 닿는 구조다. 판정이 3.5 stud 로 좁고(SLAM_REACH),
--     노리다 자기가 박으면 WALL_STUN 1.5초를 먹는다 — 보상과 위험이 같은 조건이다.
--   ⚠️ CD_FIXED 는 6.0 을 유지한다. 벽 슬램 스턴이 CC 라, 쿨을 내리면
--     러너 여럿이 들었을 때 태거가 상시 CC 에 걸린다(가동률이 인원수만큼 곱해진다).
local PUNCH_ANIM      = "rbxassetid://102834871677949"  -- 펀치 애니메이션
local PUNCH_ANIM_SPEED= 0.7
local PUNCH_WINDOW    = 0.45   -- 데미지 판정 열림 시간
local PUNCH_COOLDOWN  = 1.0    -- 펀치 간 쿨다운 (강철 건틀렛: 묵직하게 끊어 침. 망치 1.8보단 빠름)
local PUNCH_HIT_CD    = 0.5    -- 같은 대상 재타격 방지

-- ── 스킬: 차징 돌진 상수 ─────────────────────────────────────
local DMG_MIN        = 26      -- 미차징 돌진 데미지 (20 → 26, 2026-09-08)
local DMG_MAX        = 46      -- 풀차징 돌진 데미지 (36 → 46, 2026-09-08)
local WALL_SLAM_BONUS = 50     -- 태거를 벽에 실제로 처박았을 때 추가 (→ 총 70~86)
-- ⚠️ [밸런스 2026-08-29] 12/24/14 → 20/36/50. 위 PUNCH_DMG 와 한 세트.
--   벽 보너스를 3.5배로 키운 건 판정이 그만큼 어렵기 때문이다:
--     ① 차징 타이밍(4초 넘기면 과충전 페널티) ② 각도 ③ 벽까지 3.5 stud 이내
--   무작정 쓰면 기본값, 숙련하면 벽 보너스 — 격차가 곧 실력 보상이다.
local DASH_SPEED_MIN = 60
local DASH_SPEED_MAX = 110
local DASH_TIME_MIN  = 0.18
local DASH_TIME_MAX  = 0.42
local GRAB_DRAG_TIME = 0.3   -- 명중 후 최소 끌기 시간(초). 초근거리에서 명중해도 이만큼은 끌고 감.
local CD_FIXED       = 6.0     -- 돌진(그랩) 쿨다운. CC 스킬이라 6초로 상향 (3→6).
-- 과충전 패널티 (4초 풀차징을 넘겨 떼거나 5초에 강제발사되면 적용 — 뚝 떨어지는 고정값)
local OVERCHARGE_DMG_MULT = 0.5   -- 데미지 절반
-- 과충전 거리 = 미차징(최소) 거리: DASH_SPEED_MIN × DASH_TIME_MIN
local WHIFF_STUN     = 0.5     -- 빗나감 후딜(미차징)
local WHIFF_STUN_MAX = 0.9     -- 빗나감 후딜(풀차징)
local WALL_STUN      = 1.5     -- 벽 충돌 패널티 후딜(정면 벽에 박았을 때). 산데비스탄 탈진 모션 재사용.
local WALL_STUN_ANIM = "rbxassetid://86265615635745"  -- 산데비스탄 탈진(Sleep) 모션 — 벽 충돌 후딜에 재사용
local DASH_HIT_RADIUS = 7      -- 돌진 중 명중 판정 반경(studs). 손·몸 두 중심 + 선분 검사로 고속에도 안 놓침
local CHARGE_ANIM    = "rbxassetid://131608026122219"  -- 차징 도중 재생할 애니
local CHARGE_ANIM_SPEED = 1.0
local CHARGE_FREEZE_TIME = 0.12  -- 차징 애니를 이 시점에서 정지(애니 길이 0.2보다 앞이어야 멈춤이 걸림)
local DASH_ANIM      = "rbxassetid://102834871677949"  -- 돌진(주먹) 애니 — 펀치와 동일 사용
local ORAORA_WINDOW  = 2.0     -- 명중 후 오라오라 입력 가능 시간(초). 지나면 취소.

-- ── 펀치 임팩트 VFX / 히트스톱 ───────────────────────────────
local PUNCH_VFX_HIT   = 8     -- 돌진 명중(붙잡는 순간) 임팩트 이미지 크기(studs 비례)
local PUNCH_VFX_SLAM  = 14    -- 패대기(던질 때) 임팩트 이미지 크기(클라이맥스 — 가장 큼)
local PUNCH_VFX_FIST  = 5     -- 주먹(건틀렛) 보조 임팩트 크기
local HITSTOP_ENABLED = false -- ★ 히트스톱 on/off. 빼려면 false 하나면 됨.
local HITSTOP_TIME    = 0.07  -- 패대기 순간 정지 시간(초) ≈ 2~4프레임

-- ── 상태 ────────────────────────────────────────────────────
local Char, Hum, Plyr, HRP, animator
local punchTrack, chargeTrack, dashTrack
local canPunchDamage = false
local lastPunch = 0
local punchHitTime = {}

-- 🔬 [진단 2026-09-04] 돌진 정리 경로 추적. 확인 끝나면 false 로.
--   [무엇을 보나] 라운드 종료 회수 시 Unequipped / Destroying 이 실제로 발화하는지,
--     그리고 emergencyMobilityRestore 가 캐릭터 역추적에 성공하는지.
--   ⚠️ 아래 hitConn 의 '루프 자체 종료'는 진단이 아니라 실제 수정이다.
--     DASH_DIAG 를 false 로 해도 그 종료 로직은 그대로 동작한다.
local DASH_DIAG = false
local dashing = false
local dashHitSomeone = false
local dashId = 0
local lastDashFire = 0   -- 마지막 돌진 발동 시각(중복 발사 디바운스용)
local chargeAnimId = 0   -- 차징 애니/사운드/과충전 타이머 세션 가드 (dash·cancel 시 증가시켜 예약된 콜백 무효화)
local lastDashHitChar = nil
local oraReady = false         -- 오라오라 발동 가능 상태
local oraId = 0                -- 오라오라 준비 세션(타임아웃 가드)

-- 차징 중 이동 감속
local CHARGE_SLOW_MULT = 0.8   -- 차징 중 이동속도 (-20%)
local DEFAULT_WALKSPEED = 16   -- 러너 기본 WalkSpeed(산데비스탄과 동일 기준). 모든 후딜/슬로우 복원은

-- 다운 상태 인지 복원: 다운 중이면 원속 대신 다운 패널티 속도로 복원(이속 초기화 버그 방지).
-- DownSystem이 character에 "Downed" 속성을 박고 WalkSpeed=16*0.25로 낮춰둠. 스킬 종료 시 이걸 존중.
local DOWN_WALKSPEED_MULT = 0.25
local function restoreWalkSpeed(hum)
	if not hum then return end
	local char = hum.Parent
	if char and char:GetAttribute("Downed") then
		hum.WalkSpeed = DEFAULT_WALKSPEED * DOWN_WALKSPEED_MULT
	else
		hum.WalkSpeed = DEFAULT_WALKSPEED
	end
end                               -- 스냅샷이 아니라 이 고정값으로 → 여러 시스템이 WalkSpeed를 동시에 만져도
                               -- "0이나 슬로우값을 원래값으로 잘못 저장"하는 경합이 원천 차단됨.
local DEFAULT_JUMPPOWER = 50   -- 러너 기본 JumpPower
local charging = false         -- 차징 중 여부(서버 기준)
local origWalkSpeed = nil      -- 차징 시작 전 원래 WalkSpeed (복구용)

-- 차징 감속 시작: 85%로 (복원은 고정 기본값으로 하므로 origWalkSpeed 스냅샷 불필요)
local function applyChargeSlow()
	if not Hum or not Hum.Parent then return end
	if charging then return end   -- 이미 차징 중이면 중복 적용 안 함
	charging = true
	Hum.WalkSpeed = DEFAULT_WALKSPEED * CHARGE_SLOW_MULT
end
-- 차징 감속 해제: 기본 속도로 복구(스냅샷 대신 고정값 → 경합 방지)
local function clearChargeSlow()
	charging = false
	if Hum and Hum.Parent then
		restoreWalkSpeed(Hum)
	end
	origWalkSpeed = nil
end

-- ── 처치자 태그 ──────────────────────────────────────────────
local function UntagHumanoid(h)	for _, c in ipairs(h:GetChildren()) do if c.Name == "creator" then c:Destroy() end end
end
local function TagHumanoid(h, plr)
	UntagHumanoid(h)
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"; tag.Value = plr; tag.Parent = h
	Debris:AddItem(tag, 2)
end

-- ── 진영 체크: 태거만 공격 ───────────────────────────────────
local function isValidTarget(character)
	if character == Char then return false end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		if player == Plyr then return false end
		return player:GetAttribute("Role") == "Tagger"
	else
		if character:GetAttribute("AIRunner") or character:GetAttribute("RunnerBot") then return false end
		return true
	end
end

local function loadAnim(id, priority)
	if not animator then return nil end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local t = animator:LoadAnimation(a)
	t.Priority = priority or Enum.AnimationPriority.Action
	return t
end

-- ── 펀치 임팩트 VFX 헬퍼: 투명 PNG를 ParticleEmitter로 씬 안에서 버스트(깊이 처리 + 팝/페이드 + 랜덤 회전). ──
local PUNCH_IMG = "rbxassetid://9660494013"  -- 타격 임팩트 이미지(검은 배경). 명중 spawn은 LightEmission=1로 검은색 투명 처리.
local function emitPunchVfx(atCFrame, sizeStuds)
	if not atCFrame then return end
	-- 서버 :Emit은 복제 안 됨 + 갓 만든 emitter는 복제 전이라 클라가 못 봄 →
	-- 위치만 전체 클라에 보내고, 각 클라가 자기 화면에서 직접 emitter 생성+Emit (복제 경쟁 없음).
	local ev = game:GetService("ReplicatedStorage"):FindFirstChild("PunchVfxEmit")
	if ev then
		ev:FireAllClients(atCFrame.Position, sizeStuds or 10)
	else
		warn("[PunchVfx] PunchVfxEmit RemoteEvent 없음 — Ctrl+S 후 새 F5 필요")
	end
end

-- ════════════════════════════════════════════════════════════
-- 일반 공격(펀치)
-- ════════════════════════════════════════════════════════════
local function onPunchTouch(hit)
	if not canPunchDamage then return end
	if not hit or not hit.Parent then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	local character = hit.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if not isValidTarget(character) then return end
	local now = os.clock()
	if punchHitTime[character] and (now - punchHitTime[character]) < PUNCH_HIT_CD then return end
	punchHitTime[character] = now
	TagHumanoid(humanoid, Plyr)
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
	humanoid:TakeDamage(PUNCH_DMG)
	-- 🔢 [2026-09-06] 데미지 표기 (무기 공용 _G.ShowDamage).
	if _G.ShowDamage and Plyr then
		local root = character:FindFirstChild("HumanoidRootPart")
		_G.ShowDamage(Plyr,
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, PUNCH_DMG)) or PUNCH_DMG,
			root and root.Position, false)
	end
	HitSound:Play()   -- 일반공격(펀치) 적중 사운드
end
Handle.Touched:Connect(onPunchTouch)
-- 펀치 판정을 건틀렛 전체로 확장: Handle뿐 아니라 모든 파트에 닿으면 판정
for _, p in ipairs(Tool:GetDescendants()) do
	if p:IsA("BasePart") and p ~= Handle then
		p.Touched:Connect(onPunchTouch)
	end
end

Tool.Activated:Connect(function()
	if not Char or not Hum or Hum.Health <= 0 then return end
	if dashing then return end   -- 돌진 중엔 펀치 금지
	local now = os.clock()
	if (now - lastPunch) < PUNCH_COOLDOWN then return end
	lastPunch = now
	if punchTrack then
		punchTrack:Stop()
		punchTrack:Play()
		punchTrack:AdjustSpeed(PUNCH_ANIM_SPEED)
	end
	canPunchDamage = true
	SwingSound:Play()   -- 펀치 스윙 사운드(명중 안 해도 재생)
	punchBoosterFlash()   -- 부스터 순간 분사
	task.delay(PUNCH_WINDOW, function() canPunchDamage = false end)
end)

-- ════════════════════════════════════════════════════════════
-- 스킬 1단계: 차징 돌진
-- ════════════════════════════════════════════════════════════
local function doDash(chargeRatio, overcharged)
	if dashing or oraReady then return end
	-- 중복 발사 차단: 마지막 발동 후 짧은 시간 내 재호출 무시(클라 중복 입력 방어)
	local nowDb = os.clock()
	if lastDashFire and (nowDb - lastDashFire) < 0.3 then return end
	lastDashFire = nowDb
	if not Char or not Hum or not HRP or Hum.Health <= 0 then return end
	-- 🕒 [버그수정 2026-09-20] os.clock() → workspace:GetServerTimeNow()
	--   [증상] 라이브에서 돌진 쿨이 317초로 뜨고 스킬이 아예 안 나갔다(스튜디오는 정상).
	--   [원인] os.clock() 은 "그 피어의 Lua VM 이 시작된 뒤 흐른 시간"이다. 서버가 이 시계로
	--     찍은 절대시각을 클라(ChargeClient)가 자기 os.clock() 과 비교해서,
	--     차이 =(서버 가동시간 − 클라 프로세스 시간)이 그대로 "남은 쿨"로 보였다.
	--     스튜디오는 서버·클라가 같은 순간에 시작해 차이가 0이라 증상이 안 보인다.
	--   ⚠️ 이 now 는 아래 cdUntil 비교와 SetAttribute 두 곳에만 쓴다. 위 nowDb(중복발사 디바운스)는
	--     서버 내부끼리만 비교하므로 os.clock() 그대로 둔다 — 습관적으로 같이 바꾸지 말 것.
	--   ✅ 선례: ItemSpawnHandler 의 TaggerGlobalCDUntil 이 이미 GetServerTimeNow() 를 쓰고
	--     TaggerItemCooldownClient 도 같은 시계로 읽는다. 그 형태를 따른 것이다.
	local now = workspace:GetServerTimeNow()
	local cdUntil = Plyr and Plyr:GetAttribute("GauntletDashCdUntil") or 0
	if now < cdUntil then return end

	chargeRatio = math.clamp(chargeRatio or 0, 0, 1)
	local function lerp(a, b) return a + (b - a) * chargeRatio end
	local damage    = lerp(DMG_MIN, DMG_MAX)
	local dashSpeed = lerp(DASH_SPEED_MIN, DASH_SPEED_MAX)
	-- 끌기 거리 = dashSpeed × dashTime인데 둘 다 chargeRatio 선형이라 거리가 chargeRatio² 처럼 벌어짐
	-- → 중간 차징이 유독 짧음. dashTime에 sqrt 보정을 줘 중간 구간 끌기 거리를 끌어올림.
	local timeRatio = math.sqrt(chargeRatio)
	local dashTime  = DASH_TIME_MIN + (DASH_TIME_MAX - DASH_TIME_MIN) * timeRatio
	local cooldown  = CD_FIXED   -- 고정 쿨다운(차징 무관)
	local whiffStun = lerp(WHIFF_STUN, WHIFF_STUN_MAX)

	-- 과충전 패널티(4초 풀차징을 넘김): 데미지 절반 + 거리 최소(뚝 떨어지는 고정값)
	if overcharged then
		damage    = DMG_MAX * OVERCHARGE_DMG_MULT   -- 풀차징 데미지의 절반
		dashSpeed = DASH_SPEED_MIN                   -- 최소 거리 = 미차징 속도·시간
		dashTime  = DASH_TIME_MIN
		cooldown  = CD_FIXED + 1                     -- 쿨다운은 길게(욕심낸 처벌)
		whiffStun = WHIFF_STUN_MAX
	end

	Tool:SetAttribute("PendingDamage", damage)
	if Plyr then Plyr:SetAttribute("GauntletDashCdUntil", now + dashTime + cooldown) end

	dashId = dashId + 1
	local myDashId = dashId
	dashing = true
	dashHitSomeone = false
	lastDashHitChar = nil


	-- 차징 애니 정지(있으면) + 돌진(주먹) 애니 재생
	chargeAnimId = chargeAnimId + 1   -- 예약된 과충전 타이머 무효화(dash 후 뒤늦게 켜지는 것 방지)
	if chargeTrack then chargeTrack:Stop() end
	ChargeSound:Stop()   -- 차징 사운드 정지(떼는 순간)
	OverchargeSound:Stop()   -- 과충전음도 정지
	setSparks(false)   -- 과충전 스파크 OFF
	setCorePulse(false)   -- 발사(돌진) → core 펄스 소멸
	clearChargeSlow()   -- 차징 감속 해제(원래 속도 복구)
	-- 돌진(주먹) 애니 재생.
	if dashTrack then dashTrack:Stop(); dashTrack:Play(); dashTrack:AdjustSpeed(1.5) end   -- 돌진 애니도 1.5배 빠르게

	-- 돌진 물리: 정면으로 LinearVelocity (벽이 자연히 막음)
	local dir = HRP.CFrame.LookVector * Vector3.new(1, 0, 1)
	dir = dir.Magnitude > 0.01 and dir.Unit or HRP.CFrame.LookVector
	local att = HRP:FindFirstChild("_GauntletDashAtt")
	if not att then att = Instance.new("Attachment"); att.Name = "_GauntletDashAtt"; att.Parent = HRP end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "_GauntletDashLV"   -- Unequipped 등에서 이름으로 찾아 정리하기 위함
	lv.Attachment0 = att
	-- ★ 무한 힘 금지: 충돌 시 솔버가 발산(numerical explosion)해 캐릭터를 수백만 stud 밖으로 순간이동시킴.
	--   특히 gold=Metal로 질량↑이면 더 쉽게 터짐. 질량비례 유한값이면 힘이 유계라 발산 없음(충돌 시 자연히 멈춤/슬라이드).
	--   가속도 10000 → 어떤 색/질량이든 0.01초 내 dashSpeed 도달(원래 무한 힘과 체감 동일).
	lv.MaxForce = math.max(HRP.AssemblyMass, 1) * 10000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = dir * dashSpeed + Vector3.new(0, HRP.AssemblyLinearVelocity.Y, 0)
	lv.Parent = HRP

	-- 계단/경사 추적용 레이캐스트 파라미터 (본인 캐릭터 무시)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { Char }

	-- 정면 벽 감지용: 벽 개체만 Include로 검사 (그 외엔 안 잡힘 → 계단·바닥엔 안 멈춤)
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Include
	wallParams.FilterDescendantsInstances = collectWalls()

	-- TaggerWall 감지용: 붙잡은 태거가 거점 벽을 못 넘게(게임 규칙). TaggerWalls 폴더만 검사.
	local taggerWallParams = RaycastParams.new()
	taggerWallParams.FilterType = Enum.RaycastFilterType.Include
	do
		local tw = {}
		local map1 = workspace:FindFirstChild("map1")
		local folder = map1 and map1:FindFirstChild("TaggerWalls")
		if folder then
			table.insert(tw, folder)
			-- TaggerWall은 CanQuery가 꺼져 있으면 레이캐스트가 못 잡음 → 켜줌(저장 누락/롤백 대비)
			for _, c in ipairs(folder:GetChildren()) do
				if c:IsA("BasePart") then c.CanQuery = true end
			end
		end
		-- map2: 태거 거점 벽이 map2.Wall 폴더 안에 개별로 있음(TaggerWall_West_map2 등) → 이름으로 추가
		local map2 = workspace:FindFirstChild("map2")
		local wallFolder2 = map2 and map2:FindFirstChild("Wall")
		if wallFolder2 then
			for _, c in ipairs(wallFolder2:GetChildren()) do
				if c:IsA("BasePart") and c.Name:find("TaggerWall") then
					table.insert(tw, c)
					c.CanQuery = true
				end
			end
		end
		taggerWallParams.FilterDescendantsInstances = tw
	end

	local hitConn
	local finished = false
	local lastHitCheckPos = nil  -- 직전 프레임 HRP 위치(고속 선분 명중 판정용)
	local grabbedChar = nil    -- 붙잡은 태거 캐릭터(세트 궁 스타일)
	local grabbedHum = nil
	local grabbedRoot = nil
	local grabbedCollSaved = nil   -- 잡은 태거 파트들의 원래 CanCollide(끌기 끝나면 복원)
	local grabDamage = Tool:GetAttribute("PendingDamage") or DMG_MIN   -- 끝점에서 줄 데미지(보류)
	local grabFinishScheduled = false   -- 명중 후 끌기 보장 타이머가 이미 걸렸는지(중복 방지)

	-- 돌진 종료 처리 (끝점: 벽 감지 OR dashTime 만료). 붙잡은 태거가 있으면 둘 다 처박힘.
	-- hitWall=true면 "정면 벽에 박아서 끝남" → 벽 충돌 패널티(긴 후딜 + 탈진 모션) 적용.
	local function finishDash(stopNow, hitWall)
		-- 🔬 [진단 2026-09-04] 종료 경로 추적. finished 가드보다 앞에 둔다 —
		--   "이미 끝났는데 또 불렸다"도 정보다(중복 호출인지 미호출인지 갈린다).
		if DASH_DIAG then
			warn(string.format("🔬 [Dash] finishDash(stop=%s wall=%s) | 이미종료=%s dashing=%s",
				tostring(stopNow), tostring(hitWall), tostring(finished), tostring(dashing)))
		end
		if finished then return end
		finished = true
		if hitConn then hitConn:Disconnect() end
		dashing = false
		setBoosters(false)   -- 부스터 제트 OFF (돌진 종료)
		-- ★ 근거리 끌기 수정: 돌진/끌기 중 켠 PlatformStand 복원(Humanoid 자체물리 재가동 → 정상 이동/정지)
		if Hum and Hum.Parent then Hum.PlatformStand = false end
		-- lv 즉시 제거(가속원 차단)
		if lv and lv.Parent then lv:Destroy() end
		-- ⚠️ [2026-09-07] 무버를 지워도 '이미 실린 속도'는 관성으로 남는다.
		--   [증상] 라운드 납치 시점에 돌진하면 돌진 상태가 영원히 이어진다.
		--     09-04 에 넣은 '루프 자체 종료'(Tool.Parent 검사)로 lv 는 지워지는데,
		--     AssemblyLinearVelocity 는 아무도 안 건드려서 캐릭터가 계속 미끄러졌다.
		--   [왜 여기가 맞나] 09-04 문서의 슈퍼아머 건과 정확히 짝이다 —
		--     그때는 무버가 속도를 이겼고(감쇠가 덮어써짐), 여기는 무버를 지워도 속도가 남는다.
		--     "무버와 속도는 별개의 채널" 이라는 같은 교훈의 뒷면이다.
		--   ⚠️ 정상 종료(벽 충돌·시간 만료)에서도 어차피 아래에서 속도를 정리하므로 무해하다.
		if HRP and HRP.Parent then
			HRP.AssemblyLinearVelocity  = Vector3.zero
			HRP.AssemblyAngularVelocity = Vector3.zero
		end

		-- 잡은 태거 충돌 복원(끌기 동안 꺼놨던 CanCollide 되돌림)
		if grabbedCollSaved then
			for gp, was in pairs(grabbedCollSaved) do
				if gp and gp.Parent then gp.CanCollide = was end
			end
			grabbedCollSaved = nil
		end

		-- (소유권 복귀는 정지/던짐 물리를 서버가 적용한 뒤 아래에서 시점차로 처리. grabEnd 신호는 클라 핀 폐기로 불필요.)
		-- ★ 끌기 중 잠갔던 태거 PlatformStand 해제(슬램 넘어짐이 정상 동작하도록). 죽었으면 무시.
		if grabbedHum and grabbedHum.Parent then grabbedHum.PlatformStand = false end
		-- 🛡️ 그랩 표식 해제. 이 시점부터 TaggerCcGuard 가 지속을 재고 면역을 건다.
		if grabbedChar and grabbedChar.Parent then grabbedChar:SetAttribute("Grabbed", nil) end

		if grabbedChar and grabbedHum and grabbedHum.Parent then
			-- ── 세트 궁 피니시: 붙잡은 태거를 메다꽂음 ──
			TagHumanoid(grabbedHum, Plyr)
			-- 벽 충돌 보너스: 태거가 "실제로" 벽에 처박혔는지 정확히 판정.
			-- 태거 HRP에서 진행 방향으로 짧은 레이(반신+약간=3.5 stud) → 그 안에 벽이 있으면 충돌.
			-- (10 stud "임박"과 달리 코가 벽에 닿았을 때만 인정)
			local slamBonus = 0
			if grabbedRoot and grabbedRoot.Parent then
				local SLAM_REACH = 3.5
				local wHit = workspace:Raycast(grabbedRoot.Position, dir * SLAM_REACH, wallParams)
				local twH  = workspace:Raycast(grabbedRoot.Position, dir * SLAM_REACH, taggerWallParams)
				if wHit or twH then
					slamBonus = WALL_SLAM_BONUS
				end
			end
			if not (_G.IsDamageImmune and _G.IsDamageImmune(grabbedHum.Parent)) then
			grabbedHum:TakeDamage(grabDamage + slamBonus)
			-- 🔢 패대기는 crit=true. ⚠️ 벽 보너스를 합산한 실제값을 보여준다 —
			--   기본값만 띄우면 "벽에 처박아도 숫자가 같다"로 읽혀 벽 활용의 보상이 안 보인다.
			if _G.ShowDamage and Plyr then
				local total = grabDamage + slamBonus
				_G.ShowDamage(Plyr,
					(_G.DisplayDamage and _G.DisplayDamage(grabbedHum.Parent, total)) or total,
					grabbedRoot and grabbedRoot.Position, true)
			end
			end   -- 끝점 데미지 + (벽 처박기 시 보너스)
			HitSound:Play()
			-- ★ 던지는 순간 일반공격(펀치) 모션 1회 — "돌진→붙잡고→펀치로 패대기"가 한 동작으로 읽히게.
			if punchTrack then
				if dashTrack then dashTrack:Stop() end
				punchTrack:Stop()
				punchTrack:Play()
				punchTrack:AdjustSpeed(PUNCH_ANIM_SPEED * 1.5)   -- 패대기는 1.5배 빠르게(일반 펀치보다 스냅)
			end
			SwingSound:Play()   -- 펀치 스윙 사운드
			-- ★ 패대기 임팩트 VFX: 태거(크게) + 주먹 보조 플래시
			if grabbedRoot and grabbedRoot.Parent then emitPunchVfx(CFrame.new(grabbedRoot.Position), PUNCH_VFX_SLAM) end
			if Handle then emitPunchVfx(Handle.CFrame, PUNCH_VFX_FIST) end

			-- 끝점 마무리(정지/세움 + 던짐). 히트스톱이 켜져 있으면 잠깐 멈췄다 실행하므로 task.spawn로 분리(finishDash 뒷정리 안 막게).
			local rRoot, tRoot = HRP, grabbedRoot
			local tHum, tChar = grabbedHum, grabbedChar
			task.spawn(function()
				-- ═══════════ 히트스톱 (빼려면 위 HITSTOP_ENABLED=false 하나면 됨) ═══════════
				if HITSTOP_ENABLED then
					local froze = {}
					for _, p in ipairs({ rRoot, tRoot }) do
						if p and p.Parent and not p.Anchored then
							p.AssemblyLinearVelocity = Vector3.zero
							p.AssemblyAngularVelocity = Vector3.zero
							p.Anchored = true
							froze[#froze + 1] = p
						end
					end
					task.wait(HITSTOP_TIME)
					for _, p in ipairs(froze) do if p and p.Parent then p.Anchored = false end end
				end
				-- ═══════════ 히트스톱 끝 ═══════════

				-- ★ 러너: 그 자리 정지 + 똑바로 세움(림프 해제 시 눕는 것 방지). 이 시점 서버 소유라 CFrame 안전.
				if rRoot and rRoot.Parent then
					rRoot.AssemblyLinearVelocity = Vector3.new(0, math.min(rRoot.AssemblyLinearVelocity.Y, 0), 0)
					rRoot.AssemblyAngularVelocity = Vector3.zero
					local flat = Vector3.new(dir.X, 0, dir.Z)
					if flat.Magnitude > 0.05 then
						rRoot.CFrame = CFrame.lookAt(rRoot.Position, rRoot.Position + flat.Unit)
					end
				end
				task.spawn(function()
					for _ = 1, 8 do
						RunService.Heartbeat:Wait()
						if rRoot and rRoot.Parent then
							rRoot.AssemblyLinearVelocity = Vector3.new(0, math.min(rRoot.AssemblyLinearVelocity.Y, 0), 0)
							rRoot.AssemblyAngularVelocity = Vector3.zero
						end
					end
				end)

				-- ★ 태거: 돌진 방향으로 멀리 던짐(살았든 죽었든). 서버 소유 유지 중이라 속도 적용됨.
				if tRoot and tRoot.Parent then
					if tHum and tHum.Health > 0 then
						local gp = tRoot.Position
						local surfParams = RaycastParams.new()
						surfParams.FilterType = Enum.RaycastFilterType.Exclude
						surfParams.FilterDescendantsInstances = { Char, tChar }
						local sHit = workspace:Raycast(gp + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), surfParams)
						if sHit then
							tRoot.CFrame = CFrame.new(sHit.Position + Vector3.new(0, 3, 0), sHit.Position + Vector3.new(0, 3, 0) + dir)
						end
					end
					-- 던지기 전 태거 충돌/그룹 보장: 던지는 순간 CG가 Default로 풀려 거점 벽(TaggerBarrier)을
					-- 통과하던 버그 방지 → TaggerCharacter로 강제해 map1/map2 벽 모두에 막히게.
					if tChar then
						for _, part in ipairs(tChar:GetDescendants()) do
							if part:IsA("BasePart") then
								part.CanCollide = true
								part.CollisionGroup = "TaggerCharacter"
							end
						end
					end
					local THROW_FORWARD = dashSpeed * 1.2   -- 던짐 세기(앞으로). 약하면 ↑ / 너무 멀면 ↓
					local THROW_UP = 30                     -- 던짐 포물선 높이
					tRoot.AssemblyLinearVelocity = dir * THROW_FORWARD + Vector3.new(0, THROW_UP, 0)
				end
				-- 자빠뜨림(R15 넘어짐) — 살아있을 때만(죽으면 기본 사망 처리가 쓰러뜨림)
				pcall(function()
					if tHum and tHum.Parent and tHum.Health > 0 then
						tHum:ChangeState(Enum.HumanoidStateType.FallingDown)
					end
				end)
			end)
		else
			-- 아무도 안 붙잡았으면(빗나감) 기존처럼 정지 + 후딜
			if HRP and HRP.Parent then
				HRP.AssemblyLinearVelocity = Vector3.new(0, math.min(HRP.AssemblyLinearVelocity.Y, 0), 0)
			end
			task.spawn(function()
				-- 벽 반발로 다시 튀는 것까지 잡으려면 더 오래·강하게 눌러야 함(12프레임).
				for _ = 1, 12 do
					RunService.Heartbeat:Wait()
					if HRP and HRP.Parent then
						HRP.AssemblyLinearVelocity = Vector3.new(0, math.min(HRP.AssemblyLinearVelocity.Y, 0), 0)
					end
				end
			end)
			if not dashHitSomeone and not hitWall and Hum and Hum.Health > 0 then
				Hum.WalkSpeed = 0; Hum.JumpPower = 0
				task.delay(whiffStun, function()
					-- 새 돌진이 시작됐어도 고정값으로 복원(영구 정지 방지). 고정값이라 새 돌진엔 영향 없음.
					if Hum and Hum.Parent then restoreWalkSpeed(Hum); Hum.JumpPower = DEFAULT_JUMPPOWER end
				end)
			end
		end

		-- ★ 끌기 중 서버로 넘겼던 소유권 복귀(서버→자동=각 클라). 정지/던짐 물리를 서버가 먼저 적용한 뒤 시점차 복귀.
		--   러너: 정지 박제 후, 태거: 던짐 비행 후. grab 안 했으면(빗나감) 둘 다 no-op.
		do
			local rRoot, tRoot = HRP, grabbedRoot
			task.delay(0.18, function()
				if rRoot and rRoot.Parent then pcall(function() rRoot:SetNetworkOwnershipAuto() end) end
			end)
			task.delay(0.6, function()
				if tRoot and tRoot.Parent then pcall(function() tRoot:SetNetworkOwnershipAuto() end) end
			end)
		end

		-- ── 벽 충돌 패널티 + 런어웨이 안전망 ──
		-- 패널티 본체(후딜 + 탈진 모션 + 스파크 + 속도 박제). 1회만 실행(중복 가드).
		-- 두 트리거 중 하나라도 걸리면 발동:
		--   ① hitWall=true  : 정면 벽 감지로 끝남(명백한 충돌)
		--   ② 런어웨이      : 종료 후 수평속도 130+ (감지를 놓쳤어도 "비정상 속도로 날아감"을 직접 차단)
		local wallPenaltyDone = false
		local function applyWallPenalty()
			if wallPenaltyDone then return end
			wallPenaltyDone = true
			if not (Hum and Hum.Parent and Hum.Health > 0) then return end
			Hum.WalkSpeed = 0; Hum.JumpPower = 0
			-- 물리 그물: 0.5초간 매 프레임 수평 속도를 0으로 눌러 반발로 날아가는 걸 못박음.
			local myNetId = dashId
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 0.5 do
					RunService.Heartbeat:Wait()
					if myNetId ~= dashId then break end
					if HRP and HRP.Parent then
						HRP.AssemblyLinearVelocity = Vector3.new(0, math.min(HRP.AssemblyLinearVelocity.Y, 0), 0)
					else
						break
					end
				end
			end)
			-- 탈진 모션(산데비스탄 패널티 재사용): 서버에서 직접 로드·재생
			local stunTrack
			pcall(function()
				if animator then
					local anim = Instance.new("Animation")
					anim.AnimationId = WALL_STUN_ANIM
					stunTrack = animator:LoadAnimation(anim)
					stunTrack.Priority = Enum.AnimationPriority.Action4
					stunTrack.Looped = true
					stunTrack:Play(0.15)
				end
			end)
			setSparks(true)   -- 과충전 스파크 재사용 → "벽에 박아 감전된 듯"
			local myStunId = dashId
			task.delay(WALL_STUN, function()
				-- 새 돌진이 시작됐어도(dashId 변경) WalkSpeed는 고정값으로 복원해야 안전.
				-- (복원 안 하면 이전 0이 남아 영구 정지 위험. 고정값이라 새 돌진엔 영향 없음)
				if Hum and Hum.Parent then restoreWalkSpeed(Hum); Hum.JumpPower = DEFAULT_JUMPPOWER end
				if stunTrack then pcall(function() stunTrack:Stop(myStunId == dashId and 0.2 or 0.15) end) end
				setSparks(false)
			end)
		end

		-- 트리거 ①: 정면 벽 감지로 끝났으면 패널티 — 단 "충분한 속도로 박았을 때만".
		-- 벽에 바짝 붙어 발사하면 아직 가속 전이라 실제 속도가 낮음(닿기만 함) → 패널티 없이 그냥 멈춤.
		-- 멀리서 가속해 박으면 속도가 높음 → 패널티. (벽 앞 차징 발사 오발동 방지)
		do
			local PENALTY_MIN_SPEED = 80
			local curSpeed = (HRP.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			if hitWall and curSpeed >= PENALTY_MIN_SPEED then
				applyWallPenalty()
			end
		end

		-- 트리거 ②: 런어웨이 안전망 — hitWall 여부와 무관하게 항상 감시.
		-- 정상 종료면 lv를 제거해 속도가 안 남음. 종료 후에도 수평속도 130+가 뜨면
		-- = 벽 반발로 날아가는 비정상 상태 → 즉시 박제. (정면 감지를 놓친 모든 각도 커버)
		do
			local RUNAWAY_SPEED = 130
			local myGuardId = dashId
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 0.5 do
					RunService.Heartbeat:Wait()
					if myGuardId ~= dashId then break end
					if not (HRP and HRP.Parent) then break end
					local sp = (HRP.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
					if sp >= RUNAWAY_SPEED then
						HRP.AssemblyLinearVelocity = Vector3.new(0, math.min(HRP.AssemblyLinearVelocity.Y, 0), 0)
						applyWallPenalty()   -- 연출도 일관되게(이미 실행됐으면 가드로 무시)
					end
				end
			end)
		end

		-- 클라에 돌진 종료 통보 → 인벤(백팩) 잠금 해제
		if Plyr then
			pcall(function() DashRemote:FireClient(Plyr, "dashEnded") end)
		end
	end

	-- 돌진 중 매 프레임 범위 검사로 명중 판정 (Touched는 고속 돌진 시 터널링으로 놓침).
	-- Handle(손)와 HRP(몸) 둘 다 중심으로 검사 → 손이 빗나가도 몸이 닿으면 맞고, 반대도 맞음.
	local dbgLastTick = 0   -- 🔬 [진단] 돌진 생존 로그 스로틀(1초). DASH_DIAG 와 한 짝.
	hitConn = RunService.Heartbeat:Connect(function()
		if finished or myDashId ~= dashId or not dashing then
			if hitConn then hitConn:Disconnect() end
			return
		end
		if not HRP or not HRP.Parent then return end

		-- 🛡️ [버그수정 2026-09-04] 툴 회수·파괴 시 루프가 스스로 끝난다 (결과 보장).
		--   [증상] 라운드 종료 직후 돌진 중 로비로 이동하면 돌진이 영원히 지속돼
		--     캐릭터가 계속 앞으로 달려나갔다.
		--   [왜 이벤트로는 못 막나] lv 정리는 Tool.Unequipped / Tool.Destroying 에만 걸려 있고,
		--     두 경로 모두 캐릭터를 Tool 에서 역추적한다(emergencyMobilityRestore).
		--     Tool 이 파괴되면 Tool.Parent 도 조상 Player 도 nil 이라 복원이 통째로 건너뛰어진다.
		--   [원칙] "누가 정리해주길" 기다리는 대신 루프가 매 프레임 자기 유효성을 확인한다.
		--     제외 목록이 아니라 결과를 보장하는 형태다(지면 법선 Y<0.4 → (0,1,0) 과 같은 꼴).
		--     Tool 이 캐릭터에 장착돼 있지 않으면 — 백팩 반환·회수·파괴 무엇이든 — 즉시 종료.
		--   ⚠️ Backpack 에는 Humanoid 가 없으므로 Unequip 만 돼도 걸린다. 의도한 것이다.
		do
			local tp = Tool.Parent
			if not tp or not tp:FindFirstChildOfClass("Humanoid") then
				if DASH_DIAG then
					warn(string.format("🔬 [Dash] 루프 자체 종료 — Tool.Parent=%s",
						tp and tp.Name or "nil"))
				end
				finishDash(true)
				return
			end
		end

		-- 🔬 [진단 2026-09-04] 돌진 생존 추적. 1초마다 상태를 남긴다.
		--   [왜 필요] 기존 진단은 '툴이 회수될 때'만 찍혀서, 회수가 안 일어나면
		--     아무 기록이 없다. 실측(15:05 판)에서 재현 순간의 로그가 통째로 비었고,
		--     Unequipped 로그(dashing=false)는 8초 앞선 다른 사건이었다.
		--   [읽는 법] 라운드 종료 시각 뒤에도 이 줄이 계속 찍히면 돌진이 살아 있는 것.
		--     끊겼는데 캐릭터가 계속 움직이면 범인은 lv 가 아니라 다른 이동 소스다.
		if DASH_DIAG and (os.clock() - dbgLastTick) >= 1.0 then
			dbgLastTick = os.clock()
			local sp = (HRP.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			warn(string.format("🔬 [Dash] 진행중 id=%d | dashing=%s lv=%s | 속도=%.1f (목표 %.0f)",
				myDashId, tostring(dashing),
				(lv and lv.Parent) and "살아있음" or "없음", sp, dashSpeed))
		end

		-- ── 벽 반발 폭주 감지: 실제 속도가 의도 속도를 크게 초과하면(벽에 박혀 튕긴 신호) 즉시 정지 ──
		-- 단, 계단 모서리에서 순간적으로 속도가 튀는 것까지 멈추면 계단을 못 오르므로 너그럽게(1.8배).
		do
			local vel = HRP.AssemblyLinearVelocity
			local horiz = vel * Vector3.new(1, 0, 1)
			-- 수평(기존 1.8배) + 위로 솟구침(1.5배; 정상 climbY는 ≤1.2배라 통과) + 총속도(2.2배; 대각/하강 폭주)
			if horiz.Magnitude > dashSpeed * 1.8 or vel.Y > dashSpeed * 1.5 or vel.Magnitude > dashSpeed * 2.2 then
				warn(string.format("[Gauntlet 폭주차단] vel=(%.0f,%.0f,%.0f) mag=%.0f dash=%.0f pos=(%.0f,%.0f,%.0f)", vel.X, vel.Y, vel.Z, vel.Magnitude, dashSpeed, HRP.Position.X, HRP.Position.Y, HRP.Position.Z))
				HRP.AssemblyLinearVelocity = Vector3.zero
				HRP.AssemblyAngularVelocity = Vector3.zero
				finishDash(true)
				return
			end
		end

		-- ── 계단/경사 추적(강화): 앞을 멀리·여러 지점 보고 부드럽게 오름. 오를 땐 살짝 감속 ──
		if lv and lv.Parent then
			local footY = HRP.Position.Y - 3   -- 대략 발 높이(HRP 중심에서 아래로)
			-- 속도에 비례해 더 멀리 앞을 봄(고속일수록 계단을 일찍 예측해 박기 전에 떠오름)
			local probeDist = math.max(5, dashSpeed * 0.08)
			-- 진행 방향 여러 거리에서 앞 지면 높이를 검사 → 가장 높은 단을 채택(연속 단 대응)
			local climbY = 0
			for _, d in ipairs({ probeDist * 0.4, probeDist * 0.7, probeDist }) do
				-- 충분히 높은 곳에서 아래로 쏨(큰 계단 단도 잡게 위로 12, 아래로 24)
				local aheadPos = HRP.Position + dir * d + Vector3.new(0, 12, 0)
				local result = workspace:Raycast(aheadPos, Vector3.new(0, -24, 0), rayParams)
				if result then
					local diff = result.Position.Y - footY
					if diff > 0.5 then
						local thisClimb = math.clamp(diff * 12, 0, dashSpeed * 1.2)
						if thisClimb > climbY then climbY = thisClimb end
					end
				end
			end
			-- 오를 땐 수평 속도를 줄여 모서리 충돌·튕김 완화(올라가는 중에만)
			local horizSpeed = dashSpeed
			if climbY > 0 then
				horizSpeed = dashSpeed * 0.75
			end
			local baseY = (climbY > 0) and climbY or HRP.AssemblyLinearVelocity.Y
			lv.VectorVelocity = dir * horizSpeed + Vector3.new(0, baseY, 0)
		end

		-- ── 붙잡은 태거를 러너 앞에 고정해 함께 끌고 감(세트 궁) ──
		if grabbedRoot and grabbedRoot.Parent and grabbedHum and grabbedHum.Health > 0 then
			-- 게임 규칙: 태거는 TaggerWall을 못 넘음. 태거 정면을 넉넉히(고정) 검사해
			-- 벽이 임박하면 옮기지 말고 즉시 끝점 처리(벽 앞에서 멈춤).
			local TW_LOOK = 10
			local twHit = workspace:Raycast(grabbedRoot.Position, dir * TW_LOOK, taggerWallParams)
			if twHit then
				finishDash(true)
				return
			end
			-- ★ 서버 권위 핀: 잡는 동안 러너+태거 둘 다 서버 소유(grab 시 설정)이므로
			--   서버가 매 프레임 태거를 러너 앞 3stud(수평)에 직접 배치. 같은 권위 → 상대 위치 정확 보존(지연0).
			--   러너가 PlatformStand로 기울 수 있어 dir 수평 기준으로 세워서 배치(태거 안 기울게).
			local flatDir = Vector3.new(dir.X, 0, dir.Z)
			if flatDir.Magnitude > 0.05 then
				flatDir = flatDir.Unit
				grabbedRoot.CFrame = CFrame.lookAt(HRP.Position + flatDir * 3, HRP.Position + flatDir * 6)
			end
			-- ★ 근거리 끌기 핵심 수정: 태거를 잡으면 Humanoid가 넘어짐/얽힘 상태로 빠져
			--   LinearVelocity(lv)가 물리 엔진에 무시당함(측정: lv가 110 명령해도 HRP실속도=0).
			--   → 러너 HRP에 속도를 직접 주입해서 lv 상쇄 상황을 우회. 수평만 강제, 수직(중력)은 보존.
			-- (직접 속도 주입 제거: 러너 서버 소유 전환 후 이게 실제로 먹혀 lv와 이중 작용 → 솟구침.
			--  PlatformStand+lv만으로 이동 충분. 이동은 lv 단독으로.)
		elseif grabbedRoot then
			-- 태거가 사라졌거나 죽음 → 붙잡기 해제 (클라 핀도 종료)
			if Plyr then DashRemote:FireClient(Plyr, "grabEnd") end
			grabbedChar = nil; grabbedHum = nil; grabbedRoot = nil
		end

		-- ── 정면 벽 감지: 벽(castle/Forest)이 코앞이면 박기 전 멈춤(제어불가 방지) ──
		do
			-- 고속일수록 멀리 봐야 터널링 안 됨(한 프레임 이동거리보단 크게, 단 너무 멀리서 멈추진 않게)
			local lookAhead = math.max(5, dashSpeed * 0.06)
			-- HRP 중심 + 위아래 두 높이에서 검사(벽 높이 어긋남 대비)
			local origins = {
				HRP.Position,
				HRP.Position + Vector3.new(0, -2, 0),
				HRP.Position + Vector3.new(0, 2, 0),
			}
			for _, org in ipairs(origins) do
				-- 일반 벽(castle/Forest) + TaggerWall 둘 다 정면 검사.
				-- 돌진 중엔 러너도 TaggerWall에 막힘(태거 끌고 있으면 거기서 처박힘 → 규칙 보존).
				local wallHit = workspace:Raycast(org, dir * lookAhead, wallParams)
				local twHit = workspace:Raycast(org, dir * lookAhead, taggerWallParams)
				if wallHit or twHit then
					finishDash(true, true)   -- hitWall=true → 벽 충돌 패널티
					return
				end
			end
		end

		-- ── 명중 판정: 아직 아무도 안 붙잡았을 때만 검사(한 번 잡으면 재검사 스킵 → 경합·중복 방지) ──
		if not grabbedChar then
			-- 검사 중심점: 몸(HRP) + 정면 앞쪽 점(좌우 대칭).
			-- 예전엔 Handle(오른손) 위치를 썼는데 그게 판정을 오른쪽으로 치우치게 만들어
			-- "정면 조준했는데 안 끌림 / 오른쪽만 잘 끌림" 비대칭이 났음.
			-- → 오른손 대신 HRP 정면(LookVector) 앞쪽 점으로 바꿔, 앞으로 뻗는 사거리는 유지하되 좌우 대칭.
			local centers = { HRP.Position }
			do
				local fwd = HRP.CFrame.LookVector * Vector3.new(1, 0, 1)
				if fwd.Magnitude > 0.01 then
					centers[#centers+1] = HRP.Position + fwd.Unit * 2.5
				end
			end
			-- 고속 보정: 이전 프레임 위치 → 현재 위치 선분도 검사(한 프레임에 태거를 지나쳐도 잡음)
			local prevPos = lastHitCheckPos or HRP.Position
			for _, m in ipairs(workspace:GetDescendants()) do
				if m:IsA("Model") and m ~= Char then
					local h = m:FindFirstChildOfClass("Humanoid")
					local root = m:FindFirstChild("HumanoidRootPart")
					if h and root and h.Health > 0 and isValidTarget(m) then
						local hit = false
						-- (1) 점-거리: 두 중심 중 하나라도 반경 안
						for _, c in ipairs(centers) do
							if (root.Position - c).Magnitude <= DASH_HIT_RADIUS then hit = true break end
						end
						-- (2) 선분-거리: 이전→현재 이동 경로가 태거를 스쳐 지나갔는지(터널링 방지)
						if not hit then
							local seg = HRP.Position - prevPos
							local segLen = seg.Magnitude
							if segLen > 0.01 then
								local t = math.clamp((root.Position - prevPos):Dot(seg) / (segLen * segLen), 0, 1)
								local closest = prevPos + seg * t
								if (root.Position - closest).Magnitude <= DASH_HIT_RADIUS then hit = true end
							end
						end
						if hit then
							dashHitSomeone = true
							-- 🛡️ [2026-09-02] CC 면역 중이면 붙잡지 않는다(TaggerCcGuard).
							--   [왜] 그랩은 이 게임에서 가장 강한 CC 다. PlatformStand 로 몸을
							--     장악하고 끌고 다니는 동안 킹은 이동·공격이 전부 막힌다.
							--     그런데 속성을 안 써서 ccActive() 가 감지할 방법이 없었고,
							--     면역 중에도 그대로 잡혔다(실측). 다른 CC 를 다 막아도 이거
							--     하나가 뚫리면 연속 봉쇄가 그대로 성립한다.
							--   ⚠️ 돌진·데미지는 그대로 둔다. 명중 보상까지 지우지는 않는다.
							if _G.IsCcImmune and _G.IsCcImmune(m) then
								-- 잡지 않고 지나친다. dashHitSomeone 은 위에서 이미 true 라
								-- 명중 판정·데미지는 정상 처리된다.
							else
							-- ── 세트 궁 스타일: 멈추지 않고 태거를 붙잡아 함께 끌고 감 ──
							grabbedChar = m
							grabbedHum = h
							grabbedRoot = root
							-- ★ 근거리 끌기 핵심 수정: 러너 Humanoid 자체물리(anti-slide/넘어짐 복구)가 lv를 매 프레임 상쇄 → PlatformStand로 꺼서 lv가 그대로 먹히게. finishDash에서 false 복원.
							if Hum and Hum.Parent then Hum.PlatformStand = true end
							-- ★ 태거도 PlatformStand 잠금: 안 하면 잡히는 순간 Humanoid가 넘어짐 상태로 들어가 몸이 픽 쓰러짐.
							if grabbedHum and grabbedHum.Parent then grabbedHum.PlatformStand = true end
							-- ★ 근거리 지연 해결(서버 권위): 잡는 동안 러너+태거 둘 다 서버 소유로 전환.
							--   같은 권위에서 서버가 매 프레임 태거를 러너 앞에 배치 → 상대 위치 정확 보존(지연0).
							--   (클라 핀 실패: 남의 플레이어 캐릭터 소유권은 러너 클라로 안 넘어가 스냅백)
							pcall(function() grabbedRoot:SetNetworkOwner(nil) end)
							pcall(function() HRP:SetNetworkOwner(nil) end)
							grabDamage = Tool:GetAttribute("PendingDamage") or DMG_MIN
							-- 계단 추적이 붙잡은 태거를 "계단"으로 오인해 그 위로 기어오르지 않게 제외
							rayParams.FilterDescendantsInstances = { Char, m }
							-- ★ 근거리 끌기 막힘 해결: 잡은 태거 충돌을 꺼서 러너가 태거에 밀려 멈추지 않게.
							--   (측정 결과 근거리에선 러너가 앞에 놓인 태거 콜리전에 막혀 14프레임이나 정지했음)
							--   태거 위치는 매 프레임 CFrame으로 직접 강제하므로 CanCollide 꺼도 바닥 안 뚫음. finishDash에서 복원.
							grabbedCollSaved = {}
							for _, gp in ipairs(m:GetDescendants()) do
								if gp:IsA("BasePart") then
									grabbedCollSaved[gp] = gp.CanCollide
									gp.CanCollide = false
								end
							end
							HitSound:Play()   -- 붙잡는 순간 효과음
							-- 🛡️ 그랩도 CC 다. 표식을 세워 TaggerCcGuard 가 '묶임'으로 세게 한다.
							--   해제 후 면역이 걸려 연속 그랩·CC 이어붙이기가 끊긴다.
							--   ⚠️ finishDash 에서 반드시 지운다("켜는 코드에는 끄는 코드를 같이").
							m:SetAttribute("Grabbed", true)
							-- ★ 명중 임팩트 VFX: 태거(접촉 지점, 작게) + 주먹 보조 플래시
							if root and root.Parent then emitPunchVfx(CFrame.new(root.Position), PUNCH_VFX_HIT) end
							if Handle then emitPunchVfx(Handle.CFrame, PUNCH_VFX_FIST) end
							-- (끌기 종료는 dashTime 만료가 맡음 → 충전한 거리만큼 끌고 가다 끝점에서 정지+던짐. 0.3초 컷 제거.)
							-- 데미지는 끝점(finishDash)에서. 여기선 멈추지 않고 돌진 계속.
							break
							end
						end
					end
				end
			end
		end
		lastHitCheckPos = HRP.Position   -- 다음 프레임 선분 검사용
	end)

	-- dashTime(=충전 거리) 만료 시 종료. 붙잡았든 빗나갔든 동일 → 끌기는 충전 거리만큼 지속.
	task.delay(dashTime, function()
		if myDashId ~= dashId then return end
		finishDash(false)
	end)
end

-- ════════════════════════════════════════════════════════════
-- 스킬 2단계: 오라오라 (※ 본체는 다음 단계 — 지금은 자리만)
-- ════════════════════════════════════════════════════════════
local function doOraOra()
	if not oraReady then return end
	oraReady = false
	oraId = oraId + 1   -- 타임아웃 가드 무효화
	-- TODO: 실제 오라오라 난타 구현 (다음 단계)
	-- 지금은 자리만: 클라에 종료 통보
	if Plyr then DashRemote:FireClient(Plyr, "oraDone") end
end

-- ── 클라 입력 수신 ───────────────────────────────────────────
DashRemote.OnServerEvent:Connect(function(plr, action, chargeRatio, overcharged)
	if plr ~= Plyr then return end
	if action == "dash" then
		doDash(chargeRatio, overcharged)
	elseif action == "oraora" then
		doOraOra()
	end
end)

-- ── 장착 / 해제 ──────────────────────────────────────────────
Tool.Equipped:Connect(function()
	Char = Tool.Parent
	Hum  = Char:FindFirstChildOfClass("Humanoid")
	Plyr = Players:GetPlayerFromCharacter(Char)
	HRP  = Char:FindFirstChild("HumanoidRootPart")
	if not Hum then return end
	animator = Hum:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = Hum end

	punchTrack  = loadAnim(PUNCH_ANIM)
	chargeTrack = loadAnim(CHARGE_ANIM)
	dashTrack   = loadAnim(DASH_ANIM)

	-- 컬러 커스텀: 플레이어가 선택한 부위별 색을 Tool에 적용(미선택 부위는 원본 기본색).
	-- SkinZone 태그 기반이라 색을 몇 번 바꿔도 안전. 모듈 없으면 건너뜀.
	if ColorPalette and Plyr then
		local zoneColors = ColorPalette.getPlayerZoneColors(Plyr)
		ColorPalette.applyZoneColors(Tool, zoneColors)
		-- "rainbow" 부위가 있으면 순환 시작(정적 색 부위는 위에서 이미 칠해짐)
		startRainbow(zoneColors)
	end

	-- 건틀릿이 오른손을 덮어도 손끝이 살짝 비쳐서, 장착 중엔 오른손을 숨김(해제 시 복원)
	local rhand = Char:FindFirstChild("RightHand") or Char:FindFirstChild("Right Arm")
	if rhand then rhand.Transparency = 1 end
end)

Tool.Unequipped:Connect(function()
	if DASH_DIAG then
		warn(string.format("🔬 [Dash] Unequipped 진입 — dashing=%s / Tool.Parent=%s",
			tostring(dashing), Tool.Parent and Tool.Parent.Name or "nil"))
	end
	dashing = false
	oraReady = false
	dashId = dashId + 1
	oraId = oraId + 1
	canPunchDamage = false
	for _, t in ipairs({punchTrack, chargeTrack, dashTrack}) do
		if t then t:Stop() end
	end
	setBoosters(false)   -- 부스터 제트 OFF (스킬 리셋/해제)
	ChargeSound:Stop()
	OverchargeSound:Stop()
	setSparks(false)
	setCorePulse(false)
	clearChargeSlow()
	stopRainbow()   -- 무지개 순환 정지(해제 시 루프 멈춤)
	-- ── 돌진 중 해제 시 물리 정리 (이게 없으면 lv가 남아 물리가 죽을 때까지 이상해짐) ──
	-- lv(LinearVelocity)는 doDash의 로컬 변수라 여기서 직접 못 만짐 → HRP에서 이름으로 찾아 제거.
	-- 그리고 잔여 속도 제거 + WalkSpeed/JumpPower를 기본값으로 복원(후딜 중 해제 대비).
	if HRP and HRP.Parent then
		local oldLV = HRP:FindFirstChild("_GauntletDashLV")
		if oldLV then oldLV:Destroy() end
		HRP.AssemblyLinearVelocity = Vector3.new(0, math.min(HRP.AssemblyLinearVelocity.Y, 0), 0)
	end
	if Hum and Hum.Parent then
		restoreWalkSpeed(Hum)
		Hum.JumpPower = DEFAULT_JUMPPOWER
	end
	-- 오른손 다시 보이게(장착 중 숨겼던 것 복원)
	if Char and Char.Parent then
		local rhand = Char:FindFirstChild("RightHand") or Char:FindFirstChild("Right Arm")
		if rhand then rhand.Transparency = 0 end
	end
end)

-- ── 차징 신호 (클라가 시간 판단 → 서버가 효과 동기화) ────────
-- chargeStart: 차징 시작(애니·사운드) / fullcharge: 4초 풀차징(core 펄스="떼라")
-- overcharge: 4초 넘겨 계속 홀딩(스파크+연기+감전음="패널티") / chargeCancel: 취소
DashRemote.OnServerEvent:Connect(function(plr, action)
	if plr ~= Plyr then return end
	if action == "chargeStart" then
		if dashing or oraReady then return end
		if chargeTrack then
			chargeAnimId = chargeAnimId + 1
			local myId = chargeAnimId
			chargeTrack.Looped = false
			chargeTrack.Priority = Enum.AnimationPriority.Action4  -- 최상위 우선순위로 idle/walk 위에 덮기
			chargeTrack:Stop()
			chargeTrack:Play()
			chargeTrack:AdjustSpeed(CHARGE_ANIM_SPEED)
			-- 차징 사운드 재생 — 차징하는 동안
			ChargeSound:Play()
			OverchargeSound:Stop()
			setSparks(false)     -- 차징 시작 시 효과 초기화
			setCorePulse(false)  -- 충전 중엔 core 펄스 OFF (4초 풀차징 때 켬)
			applyChargeSlow()    -- 차징 중 이동 감속(-15%)
			punchBoostId = punchBoostId + 1   -- 펀치 순간분사 끄기 예약 무효화(차징이 부스터 제어)
			setBoosters(true)    -- 부스터 제트 ON (차징 시작)
			-- 차징 애니를 끝까지 보낸 뒤 마지막 프레임에서 정지(speed 0) → 팔 당긴 자세 고정.
			task.delay(CHARGE_FREEZE_TIME, function()
				if myId ~= chargeAnimId then return end   -- 새 차징 시작됐으면 무시
				if not chargeTrack then return end
				if chargeTrack.IsPlaying then
					chargeTrack:AdjustSpeed(0)   -- 재생 중이면 그 프레임에 정지
				else
					-- 이미 끝났으면(애니가 짧아 종료됨): 다시 재생해서 마지막 프레임으로 보낸 뒤 정지
					chargeTrack:Play(0)
					chargeTrack.TimePosition = math.max(0, chargeTrack.Length - 0.001)
					chargeTrack:AdjustSpeed(0)
				end
			end)
		end
	elseif action == "fullcharge" then
		-- 4초 풀차징 도달: core 펄스 ON = "지금 떼라" 신호. 차징 사운드 정지.
		if dashing or oraReady then return end
		ChargeSound:Stop()
		setCorePulse(true)
		FullChargeSound:Play()   -- 풀차징 완료 사운드
	elseif action == "overcharge" then
		-- 4초 넘겨 계속 홀딩: 과충전 패널티 상태. 감전음 + 스파크 + 연기 ON.
		if dashing or oraReady then return end
		OverchargeSound:Play()
		setSparks(true)
	elseif action == "chargeCancel" then
		setBoosters(false)   -- 부스터 제트 OFF (차징 취소)
		chargeAnimId = chargeAnimId + 1
		if chargeTrack then chargeTrack:Stop() end
		ChargeSound:Stop()
		OverchargeSound:Stop()
		setSparks(false)
		setCorePulse(false)
		clearChargeSlow()
	end
end)

-- ═══ 비상 이동 복원 (라운드 종료 회수 대응) ═══════════════════════════
-- 스킬 시전 중(WalkSpeed 0·JumpPower 0·PlatformStand·BodyMover) 툴이 파괴/회수되면
-- 시퀀스 말미의 복원 코드가 실행 기회를 잃어 캐릭터가 영구 정지하는 문제 방지.
-- Destroying은 파괴 직전 동기 발화라 여기서 상태를 강제 복원한다.
local function emergencyMobilityRestore()
	local ch = Tool.Parent
	if not (ch and ch:IsA("Model") and ch:FindFirstChildOfClass("Humanoid")) then
		local plr = Tool:FindFirstAncestorWhichIsA("Player")
		ch = plr and plr.Character
	end
	-- 🔬 [진단 2026-09-04] 캐릭터 역추적 성공 여부.
	--   [가설] Tool 이 파괴된 뒤의 지연 재시도(0.6s·1.8s)에서는 Tool.Parent 도
	--     조상 Player 도 nil 이라 ch=nil 이 되어 아무것도 복원하지 못한다.
	--     즉 '재시도'가 재시도 역할을 못 한다. ch=nil 로그가 찍히면 이 가설이 확정된다.
	if DASH_DIAG then
		warn(string.format("🔬 [Dash] emergencyMobilityRestore ch=%s (Tool.Parent=%s)",
			ch and ch.Name or "nil", Tool.Parent and Tool.Parent.Name or "nil"))
	end
	if ch then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		local hrp = ch:FindFirstChild("HumanoidRootPart")
		if hum and hum.Parent then
			-- 다운 중이면 다운 감속 유지, 아니면 기본 복원
			hum.WalkSpeed = ch:GetAttribute("Downed") and (16 * 0.25) or 16
			hum.JumpPower = 50
			hum.PlatformStand = false
			-- 차징/스킬 애니 고정 방지: 이 스크립트(서버)가 재생한 모든 트랙 정지
			local animator = hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
					pcall(function() tr:Stop(0) end)
				end
			end
		end
		if hrp then
			for _, bm in ipairs(hrp:GetChildren()) do
				if bm:IsA("BodyVelocity") or bm:IsA("BodyPosition") or bm:IsA("BodyGyro") or bm:IsA("LinearVelocity") then
					bm:Destroy()
				end
			end
		end
	end
	-- 그랩 피해자도 해방 (그랩 중 파괴 시 PlatformStand 잔존 방지)
	if grabbedHum and grabbedHum.Parent then
		grabbedHum.PlatformStand = false
		-- 🛡️ 표식도 같이 지운다. 안 지우면 킹이 영영 '묶임' 상태로 남아
		--   TaggerCcGuard 가 CC 종료를 감지하지 못한다.
		local gc = grabbedHum.Parent
		if gc then gc:SetAttribute("Grabbed", nil) end
	end
end
-- 다단계 복원: Script가 파괴돼도 실행 중이던 스킬 스레드는 살아남아
-- 시퀀스 진행 중 WalkSpeed=0을 '복원 이후에' 다시 쓸 수 있다 (그리고 파괴된
-- 파트 참조 에러로 중단되면 자기 복원 라인엔 도달 못 함 → 영구 정지).
-- → 즉시 + 0.6s + 1.8s 세 번 덮어써서 어떤 잔존 스레드보다 마지막에 복원한다.
local function emergencyRestoreStaged()
	emergencyMobilityRestore()
	task.delay(0.6, emergencyMobilityRestore)
	task.delay(1.8, emergencyMobilityRestore)
end
Tool.Destroying:Connect(function()
	if DASH_DIAG then warn("🔬 [Dash] Tool.Destroying 발화") end
	emergencyRestoreStaged()
end)
Tool.Unequipped:Connect(function()
	if DASH_DIAG then warn("🔬 [Dash] Tool.Unequipped → emergencyRestoreStaged") end
	emergencyRestoreStaged()
end)
