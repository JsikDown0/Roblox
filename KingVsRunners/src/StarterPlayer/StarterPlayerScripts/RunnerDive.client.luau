-- RunnerDive — 산데비스탄: 단시간 초고속 + 청록 잔상 + i-frame + 탈진 페널티
-- 페이즈:
--   Burst (0.5s)      : WalkSpeed 초과부스트 + 청록 하이라이트 + 잔상 + i-frame (앞 0.3s만)
--   Decay (0.15s)     : 하이라이트 페이드아웃
--   Exhaustion (1.0s) : WalkSpeed 절반 + Sleep 이모트(지친 느낌) — 잘못 쓰면 처형 구간
-- 위험-보상: 0.3s 안에 빠져나가야 안전, 못 빠져나가면 무방비 + 탈진 콤보로 응징당함.

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local RunService           = game:GetService("RunService")
local TweenService         = game:GetService("TweenService")
local Debris               = game:GetService("Debris")

local player = Players.LocalPlayer

-- 산데비스탄 발동 사운드 ID
local SANDEVISTAN_SOUND_ID = "rbxassetid://111623265887880"

-- i-frame은 서버 권위(RunnerDiveServer)가 소유. 클라는 RemoteEvent로 통보만 함.
-- (클라가 SetAttribute 한 값은 서버로 복제 안 되므로 서버 킬판정이 못 읽음)
local diveRemote = ReplicatedStorage:WaitForChild("RunnerDiveRemote")

-- ════════════════ 튜닝 상수 ════════════════
local DIVE_KEY        = Enum.KeyCode.Q

-- 페이즈 시간(초)
local BURST_TIME      = 0.50   -- 초고속 + 잔상
local DECAY_TIME      = 0.15   -- 하이라이트 페이드아웃
local EXHAUSTION_TIME = 1.00   -- 탈진(슬로우) 지속
local IFRAME_TIME     = 0.50   -- 발동 시점부터 = 버스트 전체. 끝나는 즉시 탈진(무방비)이라 카운터플레이 유지

-- 속도
local BURST_SPEED     = 80     -- 기본 16 대비 5배
-- ⚠️ [EXHAUST-SPEED] 배율이 아니라 '절대 속도'다.
--    예전엔 groundSpeed() × 0.25 였는데, 스피드 포션이 켜져 있으면
--    (16+12)×0.25 = 7 처럼 값이 흔들려 탈진 페널티가 일정하지 않았다.
--    → 6 으로 고정한다. 기본 16 대비 37.5%.
local EXHAUSTION_SPEED = 6   -- 탈진 시 기본 속도의 N배 (16 × 0.25 = 4)
local DEFAULT_WALKSPEED = 16   -- 러너 기본 속도(DownSystem과 동일 기준). 복구는 스냅샷이 아니라 이 값 기반 라이브 계산

-- 탈진 모션: 에셋 ID 기반 재생. (편집한 KeyframeSequence는 ServerStorage._Archive._AnimSaves.ExhaustAnim에 보관됨 — 다시 B로 가고 싶을 때 복귀 쉬움)
local EXHAUST_ANIM_ID    = "rbxassetid://86265615635745"
local EXHAUST_ANIM_SPEED = 1.0            -- 재생 배속(>1 = 호흡 더 가쁘게). 1.0 = 원본 속도

-- 잔상
local AFTERIMAGE_INTERVAL = 0.06
local AFTERIMAGE_FADE     = 0.40
-- 산데비스탄 색 스킨: 플레이어 속성 "DashSkin"으로 결정 (없으면 기본 청록)
-- 스킨 시스템이 player:SetAttribute("DashSkin", "<id>")만 세팅하면 색이 바뀐다.
local SANDE_COLOR_DEFAULT = Color3.fromRGB(80, 220, 255)   -- 기본 청록
local DASH_SKIN_COLORS = {
	Default  = Color3.fromRGB(80, 220, 255),   -- 청록(기본)
	Red      = Color3.fromRGB(255, 60, 40),    -- 붉은색 계열(테스트 스킨)
	Violet   = Color3.fromRGB(170, 70, 255),   -- 전기 보라
	Toxic    = Color3.fromRGB(120, 255, 60),   -- 형광 초록
	Magenta  = Color3.fromRGB(255, 60, 200),   -- 핫핑크
	Amber    = Color3.fromRGB(255, 140, 20),   -- 주황
	Cobalt   = Color3.fromRGB(50, 90, 255),    -- 순파랑
	Spectral = Color3.fromRGB(255, 255, 255),  -- 순백
	Ice      = Color3.fromRGB(150, 235, 255),  -- 얼음 청록백
	Solar    = Color3.fromRGB(255, 230, 40),   -- 노랑
}

-- 특수 대시 타입(단색 아님): DashSkin 키로 모드 결정 → 잔상 색을 시간 기반으로 동적 계산
local DASH_SKIN_SPECIAL = {
	Prism     = "prism",    -- 무지개 hue 순환
	Vaporwave = "vapor",    -- 청록→마젠타(트레일 진행에 따라 보간)
	Shadow    = "shadow",   -- 회색 ↔ near-black 교차
	Watermelon = "watermelon", -- red <-> green hard alternation + watermelon particle burst
}
local VAPOR_A = Color3.fromRGB(40, 220, 255)   -- Vaporwave 시작(청록)
local VAPOR_B = Color3.fromRGB(255, 60, 200)   -- Vaporwave 끝(마젠타)
local PRISM_HUE_SPEED = 2.0                     -- 초당 hue 순환 바퀴수(0.5초 대시 = 한 바퀴)
local SHADOW_A  = Color3.fromRGB(20, 18, 30)    -- Shadow 어두운 끝(near-black, 살짝 보라끼)
local SHADOW_B  = Color3.fromRGB(120, 120, 130) -- Shadow 밝은 끝(쿨 그레이)
local MONO_SPEED = 9.0                          -- Shadow 교차 진동 속도(rad/s)
-- Watermelon dash: red <-> green hard alternation + watermelon particle burst
local WMELON_RED       = Color3.fromRGB(255, 55, 70)   -- flesh red
local WMELON_GREEN     = Color3.fromRGB(70, 200, 80)   -- rind green
local WMELON_ALT_SPEED = 8                             -- red/green flips per second
local WMELON_PARTICLE  = "rbxassetid://87796474809920" -- 3D watermelon slice (pre-change image)
local ICE_PARTICLE     = "rbxassetid://85698671947685" -- 눈송이 (Ice dash)
-- 발동 시점에 호출: 현재 플레이어의 대시 색 반환
local function getSandeColor()
	local skinId = player:GetAttribute("DashSkin")
	if skinId and DASH_SKIN_COLORS[skinId] then
		return DASH_SKIN_COLORS[skinId]
	end
	return SANDE_COLOR_DEFAULT
end

-- 기타
local COOLDOWN        = 6      -- 대시 시작 기준. 버스트0.5+탈진1.5 제외 → 정상속도 노출 4.0초
local RUNNER_ONLY     = true

-- 속성 노출:
--   "Diving"     : Burst 중 true (클라 로컬용)
--   "Exhausted"  : 탈진 중만 true (HUD 슬로우 인디케이터 등에 사용 가능, 클라 로컬용)
--   "Invincible" : 서버(RunnerDiveServer)가 소유. 클라는 RemoteEvent로 요청만.
local SET_DIVING_ATTR     = true
local SET_EXHAUSTED_ATTR  = true
-- ════════════════════════════════════════════════════════════

local character, humanoid, root
local dashing = false
local readyAt = 0
local savedWalkSpeed = nil
local activeHighlight = nil
local currentDashColor = SANDE_COLOR_DEFAULT   -- 이번 대시의 색(발동 시 getSandeColor()로 갱신)
local dashColorMode = "single"   -- single | prism | vapor | shadow (특수 타입 잔상 색 모드)
local dashStartClock = 0         -- 이번 대시 시작 tick (vapor 진행도 계산용)
local afterimageConn = nil
local exhaustionToken = 0   -- 탈진 복귀 타이머 무효화용(쿨 1초 + 탈진 1초 겹침 대응)
local exhaustTrack = nil    -- 탈진 시 재생하는 Sleep 이모트 트랙

-- 현재 "지면 기준 속도" = 기본값 + 활성 부스트(스피드 포션의 SpeedBoost 속성 등).
-- 대시 복구 시 과거 스냅샷이 아니라 이 함수로 라이브 재계산해야
-- 부스트가 대시 도중 만료/시작돼도 잔존(영구 가속)·소실 없이 정확히 맞춰짐.
local function groundSpeed()
	return DEFAULT_WALKSPEED + ((character and character:GetAttribute("SpeedBoost")) or 0)
end

-- 🎨 [2026-08-31] 잔상 색 계산을 한 곳으로 모았다.
--   [증상] 분신(그리고 남의 캐릭터)의 대시 잔상이 늘 기본 청록으로 떴다.
--   [원인] 본인은 이 아래 afterimageColor() 가 시간 기반으로 계산하는데,
--     수신부는 DASH_SKIN_COLORS[skinId] 만 뒤졌다. 특수 4종(Prism·Vaporwave·
--     Shadow·Watermelon)은 그 테이블에 없고 DASH_SKIN_SPECIAL 에만 있어서
--     전부 nil → SANDE_COLOR_DEFAULT 로 떨어졌다(실측 15:19, DashSkin=Watermelon).
--   ⚠️ 색 로직이 두 벌이면 한쪽만 고쳐진다. 새 대시 스킨을 추가할 땐
--     DASH_SKIN_COLORS 나 DASH_SKIN_SPECIAL 에만 넣으면 양쪽에 동시에 반영된다.
--   ⚠️ mode 는 DASH_SKIN_SPECIAL 을 거친 값이다. skinId 를 그대로 넘기지 말 것.
local function dynamicDashColor(mode, startClock, fallback)
	if mode == "prism" then
		return Color3.fromHSV((tick() * PRISM_HUE_SPEED) % 1, 1, 1)
	elseif mode == "vapor" then
		local p = math.clamp((tick() - (startClock or tick())) / BURST_TIME, 0, 1)
		return VAPOR_A:Lerp(VAPOR_B, p)
	elseif mode == "shadow" then
		return SHADOW_A:Lerp(SHADOW_B, (math.sin(tick() * MONO_SPEED) + 1) * 0.5)
	elseif mode == "watermelon" then
		return (math.floor(tick() * WMELON_ALT_SPEED) % 2 == 0) and WMELON_RED or WMELON_GREEN
	end
	return fallback
end

-- 이번 잔상 한 장의 색: 특수 타입이면 시간 기반 동적, 아니면 고정색
local function afterimageColor()
	return dynamicDashColor(dashColorMode, dashStartClock, currentDashColor)
end

-- 잔상 스냅샷 1장. targetChar 를 주면 그 캐릭터로(= 남의 대시), 없으면 내 캐릭터로 만든다.
-- ⚠️ [복제 대상 필터] character:GetDescendants() 를 그대로 쓰면 안 된다.
--    액세서리 Handle(모자·가방), 장착 Tool(검·푸시툴), 아머 Vest, 부활 실드 구체까지
--    전부 딸려온다. 특히 부활 실드는 지름 9 짜리 구체라 잔상 7장에 복제되면
--    화면을 통째로 가리는 연출 사고가 된다.
--    → 캐릭터 '직계' BasePart 만 복제한다. R6 기준 몸통 6개(HRP 제외)면 충분하다.
local function snapshotAfterimage(targetChar, imgColorOverride)
	local char = targetChar or character
	if not char then return end

	local imgColor = imgColorOverride or afterimageColor()
	local model = Instance.new("Model")
	model.Name = "SandeAfterimage"

	for _, part in ipairs(char:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local clone = part:Clone()
			for _, child in ipairs(clone:GetDescendants()) do
				if not child:IsA("DataModelMesh") then
					pcall(function() child:Destroy() end)
				end
			end
			if clone:IsA("MeshPart") then
				pcall(function() clone.TextureID = "" end)
			end

			clone.Material = Enum.Material.Neon
			clone.Color = imgColor
			clone.Transparency = 0.5
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.Massless = true
			clone.Parent = model
		end
	end

	model.Parent = workspace

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			TweenService:Create(part,
				TweenInfo.new(AFTERIMAGE_FADE, Enum.EasingStyle.Linear),
				{Transparency = 1}
			):Play()
		end
	end

	Debris:AddItem(model, AFTERIMAGE_FADE + 0.1)
end

-- ── 탈진 모션: Sleep 이모트를 Animate 위에 덧씌움 ──
-- Animate를 끄지 않으므로, 소유권/ID 문제로 재생 실패해도 평범한 이동 애니가 그대로 보여
-- T포즈 없이 자연 폴백됨. EmoteAnimation 타입이라 카탈로그 ID 직접 로드 가능.
local function startExhaustAnim()
	if not (character and humanoid and humanoid.Parent) then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = EXHAUST_ANIM_ID
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		exhaustTrack = track
		track.Priority = Enum.AnimationPriority.Action4   -- 이동/기본 애니 위에 덮어씀
		track.Looped = true
		track:Play(0.2)
		track:AdjustSpeed(EXHAUST_ANIM_SPEED)   -- 호흡 주기 빠르게 = 더 가쁜 느낌
	end
end

local function stopExhaustAnim()
	if exhaustTrack then pcall(function() exhaustTrack:Stop(0.2) end); exhaustTrack = nil end
end

-- 대시 파티클(눈송이/수박) 정리 — 어떤 경로로 대시가 끝나든 잔존 방지
-- ⚠️ [2026-08-31] targetChar 를 받는다. 남·분신 대시에도 파티클을 붙이게 되면서
--   정리도 같은 함수로 해야 하기 때문이다. 켜는 코드와 끄는 코드는 짝으로 움직인다.
local function clearDashParticlesOn(targetChar)
	if not targetChar then return end
	local hrp = targetChar:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for _, a in ipairs(hrp:GetChildren()) do
		if a.Name == "_DashSnowAtt" or a.Name == "_DashWmelonAtt" then
			for _, e in ipairs(a:GetChildren()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			Debris:AddItem(a, 1.5)
		end
	end
end

local function clearDashParticles()
	clearDashParticlesOn(character)
end

-- 🍉❄️ [2026-08-31] 대시 파티클 부착. 로컬·남·분신 공용.
--   [왜 헬퍼인가] 예전엔 대시 시작부에 인라인이라 로컬 character 에만 붙었다.
--     잔상 색을 공유로 고친 뒤에도 파티클은 본인 화면에만 나와서, 수박 대시가
--     남의 눈엔 "색만 수박이고 조각은 안 튀는" 반쪽으로 보였다.
--   ⚠️ clearDashParticlesOn 과 한 짝이다. 부르는 쪽은 정리도 반드시 걸 것.
--   ⚠️ 부착 전 기존 것을 정리한다. 연속 대시로 같은 이름 Attachment 가 겹치면
--     정리 때 하나만 지워지고 나머지가 캐릭터에 눌러앉는다.
--   ⚠️ mode 는 DASH_SKIN_SPECIAL 을 거친 값, skinId 는 원본 키다. Ice 는 특수 모드가
--     아니라 단색 스킨이라 skinId 로 본다 — 둘을 같이 받는 이유다.
local function attachDashParticles(targetChar, skinId, mode)
	if not targetChar then return end
	local hrp = targetChar:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	clearDashParticlesOn(targetChar)

	-- watermelon dash: burst of watermelon pieces sprayed along the dash path
	if mode == "watermelon" then
		local pAtt = Instance.new("Attachment")
		pAtt.Name = "_DashWmelonAtt"
		pAtt.Parent = hrp
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = WMELON_PARTICLE
		pe.Rate = 45
		pe.Lifetime = NumberRange.new(0.5, 0.9)
		pe.Speed = NumberRange.new(6, 13)         -- fly outward for a burst feel
		pe.SpreadAngle = Vector2.new(180, 180)    -- all directions
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-300, 300)  -- 3D slice, spinning looks fine
		pe.Acceleration = Vector3.new(0, -14, 0)  -- gravity, pieces fall
		pe.Drag = 1.5
		pe.LightEmission = 0
		pe.LockedToPart = false                   -- left behind along the dash path
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.15, 0.9),
			NumberSequenceKeypoint.new(1, 0.35),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.75, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Parent = pAtt
	end

	-- ice dash: 눈송이가 대시 경로에 흩날림
	if skinId == "Ice" then
		local pAtt = Instance.new("Attachment")
		pAtt.Name = "_DashSnowAtt"
		pAtt.Parent = hrp
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = ICE_PARTICLE
		pe.Rate = 120
		pe.Lifetime = NumberRange.new(0.9, 1.6)
		pe.Speed = NumberRange.new(6, 12)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-120, 120)
		pe.Acceleration = Vector3.new(0, -4, 0)   -- 부드럽게 낙하
		pe.Drag = 2
		pe.LightEmission = 0.4
		pe.LockedToPart = false                    -- 경로에 남겨짐
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.2, 0.7),
			NumberSequenceKeypoint.new(1, 0.3),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.75, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Parent = pAtt
		pe:Emit(20)   -- 시작 순간 즉시 한 뭉치 (짧은 대시라 초반부터 보이게)
	end
end

-- 다운당함: RunnerDive의 모든 제어(애니/이펙트)를 즉시 포기하고 DownSystem에 양보.
-- ⚠️ [DASH-DOWN] WalkSpeed 는 '다운 감속값으로 직접 덮어쓴다'.
--    예전엔 "DownSystem 이 소유하니 건드리지 않는다"였는데, 그게 버그의 원인이었다:
--      · 서버 DownSystem:317 이 WalkSpeed = 16 × 0.25 = 4 로 내린다.
--      · 그런데 WalkSpeed 는 클라이언트가 소유하는 속성이라 서버 값이 그대로 유지되지 않는다.
--        대시 시작 때 클라가 넣은 BURST_SPEED(80)가 남아 다운 중에도 초고속이 유지됐다
--        (실측 2026-08-22: 대시 중 푸시→아이템 적중으로 다운되면 오히려 빨라짐).
--    → 소유권을 넘기되, 넘기기 전에 클라가 만든 부스트를 스스로 되돌린다.
--      DownSystem 과 같은 공식(DEFAULT_WALKSPEED × 0.25)을 쓰므로 값이 어긋나지 않는다.
local DOWN_SPEED_MULT = 0.25   -- DownSystem.DOWN_WALKSPEED_MULT 와 반드시 동일하게 유지
local function bailForDown()
	dashing = false
	exhaustionToken = exhaustionToken + 1   -- 펜딩 WalkSpeed 복구 타이머 전부 무효화
	if afterimageConn then afterimageConn:Disconnect(); afterimageConn = nil end
	if exhaustTrack then pcall(function() exhaustTrack:Stop(0) end); exhaustTrack = nil end
	if activeHighlight then pcall(function() activeHighlight:Destroy() end); activeHighlight = nil end
	clearDashParticles()
	-- [DASH-DOWN] 대시 부스트를 직접 되돌린다. 이걸 빼면 BURST_SPEED(80)가 다운 중에도 남는다.
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		humanoid.WalkSpeed = DEFAULT_WALKSPEED * DOWN_SPEED_MULT
	end
	savedWalkSpeed = nil          -- 이후 WalkSpeed 소유권은 DownSystem 것
	if SET_DIVING_ATTR then player:SetAttribute("Diving", false) end
	if SET_EXHAUSTED_ATTR then player:SetAttribute("Exhausted", false) end
end

-- Burst 종료 → 탈진 페이즈 진입
local function endDash()
	if not dashing then return end
	dashing = false

	if afterimageConn then afterimageConn:Disconnect(); afterimageConn = nil end

	-- 대시 파티클 정리 (수박/눈송이 잔존 방지, 모든 어태치먼트)
	clearDashParticles()
	if SET_DIVING_ATTR then player:SetAttribute("Diving", false) end
	-- Invincible 해제는 서버가 담당 (클라 해제는 복제 안 됨)

	-- 하이라이트 페이드아웃
	if activeHighlight then
		local hl = activeHighlight
		activeHighlight = nil
		pcall(function()
			TweenService:Create(hl,
				TweenInfo.new(DECAY_TIME, Enum.EasingStyle.Linear),
				{FillTransparency = 1, OutlineTransparency = 1}
			):Play()
		end)
		Debris:AddItem(hl, DECAY_TIME + 0.1)
	end

	-- 탈진 페이즈 진입
	if humanoid and humanoid.Parent
		and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
		and not (character and character:GetAttribute("Downed"))
		and savedWalkSpeed ~= nil then

		exhaustionToken = exhaustionToken + 1
		local myToken = exhaustionToken
		local myHum = humanoid

		myHum.WalkSpeed = EXHAUSTION_SPEED
		if SET_EXHAUSTED_ATTR then player:SetAttribute("Exhausted", true) end
		startExhaustAnim()   -- Sleep 이모트(지친 느낌)

		task.delay(EXHAUSTION_TIME, function()
			-- 새 대시가 시작됐거나 캐릭터가 바뀌면 무효화
			if myToken ~= exhaustionToken then return end
			if not myHum or not myHum.Parent then return end
			-- 탈진 도중 다운당했으면 DownSystem이 WalkSpeed 소유 → 복구 금지
			if character and character:GetAttribute("Downed") then
				savedWalkSpeed = nil
				return
			end
			myHum.WalkSpeed = groundSpeed()   -- 라이브 재계산(포션 만료/시작 반영, 잔존 부스트 차단)
			savedWalkSpeed = nil
			if SET_EXHAUSTED_ATTR then player:SetAttribute("Exhausted", false) end
			stopExhaustAnim()
		end)
	else
		-- 캐릭터가 죽었거나 비정상 상태 → 그냥 정리
		savedWalkSpeed = nil
		if SET_EXHAUSTED_ATTR then player:SetAttribute("Exhausted", false) end
	end
end

local function doDash()
	dashing = true
	if SET_DIVING_ATTR then player:SetAttribute("Diving", true) end
	-- 서버에 i-frame 요청 (서버가 Invincible 켜고 IFRAME_TIME 뒤 자동 해제)
	diveRemote:FireServer(IFRAME_TIME)
	-- 탈진 중에 다시 대시하면 탈진 상태/애니메이션 해제 (새 버스트가 덮어씀)
	if SET_EXHAUSTED_ATTR then player:SetAttribute("Exhausted", false) end
	stopExhaustAnim()

	-- WalkSpeed 초과부스트
	-- savedWalkSpeed는 "대시 사이클이 속도를 소유 중"이라는 플래그 역할.
	-- 실제 복구값은 항상 groundSpeed() 라이브 계산이라 여기 저장값은 쓰지 않음.
	if savedWalkSpeed == nil then
		savedWalkSpeed = groundSpeed()
	end
	-- 펜딩된 탈진 복귀 타이머 무효화
	exhaustionToken = exhaustionToken + 1

	humanoid.WalkSpeed = BURST_SPEED

	-- 이번 대시 색/모드 확정 (스킨 속성 반영) — 잔상/하이라이트가 공유
	dashStartClock = tick()
	local dashSkinId = player:GetAttribute("DashSkin")
	dashColorMode = (dashSkinId and DASH_SKIN_SPECIAL[dashSkinId]) or "single"
	if dashColorMode == "single" then
		currentDashColor = getSandeColor()
	else
		currentDashColor = afterimageColor()   -- 특수 타입 시작 대표색(루프가 이후 매 프레임 갱신)
	end

	-- 산데비스탄 하이라이트 (스킨 색)
	local hl = Instance.new("Highlight")
	hl.Name = "SandeHighlight"
	hl.FillColor = currentDashColor
	hl.OutlineColor = currentDashColor
	hl.FillTransparency = 0.4
	hl.OutlineTransparency = 0
	hl.Adornee = character
	hl.Parent = character
	activeHighlight = hl

	-- 🍉❄️ [2026-08-31] 대시 파티클. 본인·남·분신 공용.
	--   [왜 헬퍼인가] 예전엔 여기 인라인이라 character(로컬) 에만 붙었다.
	--     색을 공유로 고친 뒤에도 파티클만 본인 화면에서만 나와서, 수박 대시를 낀
	--     러너가 남의 눈엔 "색만 수박이고 조각은 안 튀는" 상태로 보였다.
	--   ⚠️ 부착 전 기존 것을 정리한다. 연속 대시로 Attachment 가 겹치면
	--     정리 때 하나만 지워지고 나머지가 캐릭터에 눌러앉는다.
	attachDashParticles(character, dashSkinId, dashColorMode)

	-- 잔상
	local lastImage = 0
	afterimageConn = RunService.Heartbeat:Connect(function()
		if not dashing then return end
		-- 특수 타입: 하이라이트(몸 발광)도 잔상과 같이 색 갱신
		if dashColorMode ~= "single" and activeHighlight then
			local c = afterimageColor()
			activeHighlight.FillColor = c
			activeHighlight.OutlineColor = c
		end
		local now = tick()
		if now - lastImage >= AFTERIMAGE_INTERVAL then
			snapshotAfterimage()
			lastImage = now
		end
	end)

	-- i-frame 해제는 서버(RunnerDiveServer)가 IFRAME_TIME 뒤 자동 처리.
	-- (클라에서 Invincible 끄는 건 서버에 복제 안 되므로 의미 없음)

	-- Burst 끝 → endDash (탈진 페이즈 진입)
	task.delay(BURST_TIME, function()
		if dashing then endDash() end
	end)
end

local function tryDash()
	if not (character and humanoid and root) then return end
	if humanoid:GetState() == Enum.HumanoidStateType.Dead then return end
	if character:GetAttribute("Downed") then return end   -- 다운 중엔 사용 불가 (다운 시스템 무력화 방지)
	-- 🚫 [2026-08-27] 배럴 웅덩이 안에서는 대시 봉인.
	--   웅덩이의 관성 유지 로직이 대시 속도(80)를 붙잡아 오히려 더 멀리 가게 만들었다.
	--   속성은 BarrelSlipClient 가 세우고 지운다(웅덩이 판정과 같은 곳).
	--   ⚠️ 발동 시점만 본다. 대시 중에 웅덩이로 들어오는 건 막지 않는다 —
	--     밖에서 뛰어넘는 건 "대시로 장애물을 통과했다" 라 의도된 사용이다.
	if character:GetAttribute("InBarrelSpill") then
		if _G.ShowDashBlocked then _G.ShowDashBlocked() end
		return
	end
	-- ⚠️ [2026-09-07] 로비 무기 체험장 예외.
	--   로비에선 Role 이 nil 이라 아래 검사에 걸려 Q 대시가 안 됐다.
	--   ⚠️ Role 을 임시로 "Runner" 로 바꾸는 방식은 쓰지 않는다 — RoundSystem·
	--     CaptureSystem·무기 히트 판정이 전부 Role 을 보므로 부작용 범위를 못 가둔다.
	--   대신 서버(WeaponTrialSystem)가 야드 안에서만 세우는 전용 속성을 본다.
	local trialActive = player:GetAttribute("WeaponTrialActive")
	-- ⚠️ [2026-09-08] King 도구를 든 동안에는 대시가 나가지 않는다.
	--   [왜] 실전에 존재하지 않는 조합이다 — 러너는 Q대시만, 태거는 PushTool만 갖는다.
	--     둘을 동시에 쓰게 두면 훈련장에서 익힌 감각이 실전과 어긋난다.
	--     특히 태거는 "밀고 → 물러나 던진다"가 한 동작인데(MIN_SPAWN_DIST 20),
	--     대시가 있으면 그 긴장이 사라져 실전에서 "왜 이렇게 답답하지"가 된다.
	--   ⚠️ WeaponTrialActive 를 끄는 방식은 쓰지 않는다 — 그 속성은 무기 회수·
	--     라운드 정리·PushTool 그리핑 차단이 함께 보는 표식이라 부작용 범위를 못 가둔다.
	--     여기서 '손에 든 것'만 본다.
	if trialActive and character:FindFirstChild("PushTool") then
		if _G.ShowDashBlocked then _G.ShowDashBlocked() end
		return
	end
	if RUNNER_ONLY and not trialActive and player:GetAttribute("Role") ~= "Runner" then return end
	if dashing then return end
	if tick() < readyAt then return end
	readyAt = tick() + COOLDOWN

	-- 산데비스탄 발동 사운드 (편집본 — 0초부터 효과음)
	local sound = Instance.new("Sound")
	sound.SoundId = SANDEVISTAN_SOUND_ID
	sound.Volume  = 1
	sound.Parent  = root
	sound:Play()
	Debris:AddItem(sound, 5)

	doDash()
end

-- 입력
local ACTION = "RunnerDiveAction"
local function onAction(_, state)
	if state == Enum.UserInputState.Begin then tryDash() end
	return Enum.ContextActionResult.Pass
end
-- false = ContextActionService 자동 모바일 터치 버튼 안 만듦 (커스텀 SkillBarGui 가 담당)
ContextActionService:BindAction(ACTION, onAction, false, DIVE_KEY)
ContextActionService:SetTitle(ACTION, "DASH")

local function onCharacterAdded(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	-- 🧪 스피드 포션 시작/만료 실시간 반영 (영구 가속 버그 수정):
	-- 이속 실소유자는 이 클라 스크립트인데, 서버의 만료 환원은 "값 비교 가드"가
	-- 서버-클라 WalkSpeed 비동기로 헛돌면 스킵되고, 클라 로컬 값(부스트 포함 복원값)은
	-- 아무도 덮지 못해 영구 잔존했다. → SpeedBoost 속성 변화를 직접 구독해 재적용.
	-- savedWalkSpeed ~= nil = 대시 사이클 소유 중 → 그땐 종료 복원이 라이브 계산으로 정합.
	char:GetAttributeChangedSignal("SpeedBoost"):Connect(function()
		-- 다운 중에는 WalkSpeed 소유권이 DownSystem 에 있다. bailForDown 이
		-- savedWalkSpeed=nil 로 만들기 때문에 가드가 없으면 이 조건이 항상 참이 되어,
		-- 다운 중 SpeedBoost 변화(포션 만료 등)가 다운 감속(x0.25)을 덮어쓴다.
		if savedWalkSpeed == nil and humanoid and humanoid.Parent and character == char and not char:GetAttribute("Downed") then
			humanoid.WalkSpeed = groundSpeed()
			print("🧪 [RunnerDive] SpeedBoost 변화 반영 → WalkSpeed", humanoid.WalkSpeed)
		end
	end)
	dashing = false
	readyAt = 0
	savedWalkSpeed = nil
	activeHighlight = nil
	exhaustionToken = exhaustionToken + 1   -- 이전 캐릭터의 펜딩 타이머 무효화
	if afterimageConn then afterimageConn:Disconnect(); afterimageConn = nil end
	if exhaustTrack then pcall(function() exhaustTrack:Stop(0) end); exhaustTrack = nil end
	if SET_DIVING_ATTR then player:SetAttribute("Diving", false) end
	if SET_EXHAUSTED_ATTR then player:SetAttribute("Exhausted", false) end
	humanoid.Died:Connect(endDash)

	-- 다운당하면(DownSystem이 캐릭터에 Downed=true 설정) RunnerDive 제어 즉시 포기
	char:GetAttributeChangedSignal("Downed"):Connect(function()
		if char:GetAttribute("Downed") then
			bailForDown()
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

-- ═══════════════════════════════════════════════════════════════
-- 📡 [DASH-BROADCAST 수신] 다른 러너의 대시 잔상
--
-- 잔상은 원래 이 LocalScript 가 workspace 에 파트를 직접 만드는 방식이라 본인만 봤다.
-- 대시 스킨은 판매 상품인데 남이 못 보면 구매 동기가 없고, 태거도 러너가 대시를
-- 썼는지(= 6초 쿨 시작) 읽을 수 없어 대응 정보가 사라진다. → 전원에게 보이게 한다.
--
-- ⚠️ 거리 컷오프: 멀리서 일어난 대시는 화면에 보이지도 않는데 파트만 만든다.
--    안 그려도 잃는 게 없으므로 여기서 잘라내는 게 가장 싼 절감이다.
-- ⚠️ 색은 받아오지 않는다. 상대의 DashSkin 속성을 직접 읽어 계산한다(값 불일치 방지).
-- ⚠️ [2026-08-31 정정] 예전엔 남의 잔상을 '단색'으로만 그렸다. 시간 변화 모드는
--    상대의 대시 시작 시각을 알아야 한다고 봤기 때문인데, 수신 시각을 시작으로
--    잡으면 충분했다(지연은 vapor 보간에만 영향이 있고 그마저 안 보인다).
--    단색만 그리던 시절엔 특수 4종이 DASH_SKIN_COLORS 에 없어 통째로 기본색이 됐다.
-- ═══════════════════════════════════════════════════════════════
local dashFxRemote = ReplicatedStorage:WaitForChild("RunnerDiveFxRemote")

local REMOTE_DRAW_DISTANCE = 260   -- 이 거리 밖의 대시는 아예 그리지 않는다

-- 🔬 [DashFx] 잔상 전파 진단. 대시 한 번에 여러 줄이 찍혀 로그를 덮으므로 평소엔 끈다.
--   ⚠️ 로그만 끄고 잔상 렌더 로직은 그대로 돈다. 남의 대시가 안 보이면 true 로.
local DASHFX_DIAG = false

dashFxRemote.OnClientEvent:Connect(function(who, duration)
	local function dbg(stage, extra)
		if not DASHFX_DIAG then return end
		print(string.format("[DashFx] %s | who=%s %s",
			stage, tostring(who and who.Name), tostring(extra or "")))
	end

	if not who or who == player then
		if who == player then dbg("skip: 본인") end
		return
	end
	dbg("수신")

	-- 🧍 [2026-08-30] who 는 Player 또는 Model(디코이 분신) 둘 다 올 수 있다.
	--   분신은 Player 가 아니라 .Character 가 없다 — 모델 자신이 곧 캐릭터다.
	--   ⚠️ 색은 분기하지 않는다. DecoySystem 이 분신 모델에 주인의 DashSkin 을 복사해 두므로
	--     아래 who:GetAttribute("DashSkin") 이 양쪽에서 그대로 동작한다.
	local otherChar = who:IsA("Player") and who.Character or (who:IsA("Model") and who or nil)
	if not otherChar then dbg("중단: Character 없음") return end
	local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
	if not otherRoot then dbg("중단: HRP 없음") return end

	-- 거리 컷오프 (내 캐릭터 기준. 없으면 카메라 기준)
	local myPos
	if character then
		local myRoot = character:FindFirstChild("HumanoidRootPart")
		myPos = myRoot and myRoot.Position
	end
	myPos = myPos or workspace.CurrentCamera.CFrame.Position
	local dist = (otherRoot.Position - myPos).Magnitude
	if dist > REMOTE_DRAW_DISTANCE then
		dbg("중단: 거리초과", string.format("%.0f > %d", dist, REMOTE_DRAW_DISTANCE))
		return
	end
	dbg("그리기 시작", string.format("거리 %.0f", dist))

	-- 상대의 대시 스킨 색.
	-- ⚠️ getSandeColor() 는 쓸 수 없다 — 그건 LocalPlayer 의 DashSkin 만 읽는다.
	--    남의 색이 필요하므로 스킨 id 를 직접 조회한다.
	-- ⚠️ [2026-08-31] 특수 4종은 DASH_SKIN_COLORS 에 없다. 단색 테이블만 보면
	--    Prism·Vaporwave·Shadow·Watermelon 이 전부 기본색으로 떨어진다.
	--    startClock 은 수신 시각으로 잡는다 — 상대의 실제 대시 시작과는 네트워크
	--    지연만큼 어긋나지만, vapor 보간 외에는 영향이 없고 그마저 눈에 띄지 않는다.
	local skinId    = who:GetAttribute("DashSkin")
	local mode      = skinId and DASH_SKIN_SPECIAL[skinId]
	local baseColor = (skinId and DASH_SKIN_COLORS[skinId]) or SANDE_COLOR_DEFAULT
	local startClock = tick()

	-- 🍉❄️ [2026-08-31] 파티클도 본인과 동일하게 붙인다.
	--   ⚠️ 아래 루프 끝에서 반드시 정리한다. 분신이 도중에 사라지면 break 로 빠지는데,
	--     그때도 정리를 거쳐야 파티클이 월드에 눌러앉지 않는다.
	attachDashParticles(otherChar, skinId, mode)

	-- 내 잔상과 동일한 간격/장수로 그린다. 실측상 대시 1회당 8장, 동시 최대 7장이고
	-- 파트가 전부 Anchored + CanCollide/Query/Touch=false 라 물리 비용이 0이다.
	-- 렉이 실제로 관측되면 그때 이 간격만 늘릴 것(품질이 직접 보이는 축이라 보수적으로).
	task.spawn(function()
		local endAt = tick() + math.min(tonumber(duration) or BURST_TIME, BURST_TIME)
		while tick() < endAt do
			if not otherChar.Parent then break end
			snapshotAfterimage(otherChar, dynamicDashColor(mode, startClock, baseColor))
			task.wait(AFTERIMAGE_INTERVAL)
		end
		clearDashParticlesOn(otherChar)
	end)
end)

-- ── HUD 버튼/외부 연동용 노출 ──
-- ⚠️ [2026-09-07] 훈련장 쿨다운 격리.
--   [문제] 로비 훈련장에서 Q 를 쓰면 그 쿨이 라운드로 그대로 넘어갔다.
--     라운드 시작 직전에 대시를 시험해 보면 초반 6초를 대시 없이 시작하게 된다.
--     체험장에 들어간 것이 실전 페널티가 되면 안 된다.
--   [무엇을 하나] 야드를 '벗어나는 순간'에만 readyAt 을 0 으로 되돌린다.
--     ⚠️ 훈련장 '안'에서는 쿨을 그대로 둔다 — 쿨 관리도 실전 감각의 일부라
--       무한 대시로 만들면 오히려 잘못 배운다.
--   WeaponTrialActive 는 WeaponTrialSystem 이 야드 진입/이탈에 맞춰 세우고 지운다.
player:GetAttributeChangedSignal("WeaponTrialActive"):Connect(function()
	if player:GetAttribute("WeaponTrialActive") then return end   -- 진입은 무시
	if readyAt > tick() then
		print(string.format("[RunnerDive] 훈련장 이탈 — 대시 쿨 %.1f초 초기화", readyAt - tick()))
	end
	readyAt = 0
end)

_G.RunnerDive = {
	try = tryDash,
	isReady = function() return (not dashing) and tick() >= readyAt end,
	cooldownRemaining = function() return math.max(0, readyAt - tick()) end,
	COOLDOWN = COOLDOWN,
}

print("✅ RunnerDive (산데비스탄) 준비!  (키:", DIVE_KEY.Name,
	"| 쿨:", COOLDOWN, "s | 버스트:", BURST_TIME, "s | iframe:", IFRAME_TIME,
	"s | 탈진:", EXHAUSTION_TIME, "s @속도", EXHAUSTION_SPEED, ")")
