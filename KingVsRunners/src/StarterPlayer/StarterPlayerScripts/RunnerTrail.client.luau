-- RunnerTrail: 러너 캐릭터 뒤로 휘날리는 트레일 (정식 스킨)
-- 플레이어 속성 "TrailSkin"으로 결정. 스킨 시스템이 SetAttribute("TrailSkin", "<skinKey>")만 세팅하면 됨.
-- 빈 문자열/"none"이면 트레일 미표시. 속성이 바뀌면 즉시 반영(장착/해제).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- 트레일 스킨 스펙 (skinKey → 표현). EffectSystem TRAIL_SKINS의 skinKey와 일치해야 함.
--   solid        : color 한 색
--   gradient     : from(머리) → to(꼬리) 2색 ColorSequence
--   rainbow      : 스펙트럼이 트레일 길이에 정적으로 박힘
--   rainbowcycle : 시간에 따라 전체 색이 hue 순환(루프)
local TRAIL_SKINS_SPEC = {
	-- 단색 (저등급)
	White   = { kind = "solid", color = Color3.fromRGB(255, 255, 255) },
	Crimson = { kind = "solid", color = Color3.fromRGB(255, 60, 40) },
	Cyan    = { kind = "solid", color = Color3.fromRGB(80, 220, 255) },
	Violet  = { kind = "solid", color = Color3.fromRGB(170, 70, 255) },
	Toxic   = { kind = "solid", color = Color3.fromRGB(120, 255, 60) },
	Amber   = { kind = "solid", color = Color3.fromRGB(255, 140, 20) },
	Black   = { kind = "solid", color = Color3.fromRGB(10, 10, 12), light = 0 },
	-- 그라데이션 (머리 → 꼬리)
	Sunset    = { kind = "gradient", from = Color3.fromRGB(255, 140, 20), to = Color3.fromRGB(255, 79, 160) },
	Vaporwave = { kind = "gradient", from = Color3.fromRGB(40, 220, 255), to = Color3.fromRGB(255, 60, 200) },
	Ocean     = { kind = "gradient", from = Color3.fromRGB(32, 224, 192), to = Color3.fromRGB(32, 80, 255) },
	Ice       = { kind = "layered", layers = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 205, 255), Color3.fromRGB(255, 255, 255) }, light = 0.7, particle = "rbxassetid://85698671947685", particleStyle = "snow", particleY = 0 },
	Shadow    = { kind = "gradient", from = Color3.fromRGB(130, 130, 138), to = Color3.fromRGB(15, 15, 20), light = 0 },
	-- 무지개
	Rainbow      = { kind = "rainbow" },
	RainbowCycle = { kind = "rainbowcycle" },
	-- Watermelon (summer season): red/black repeating stripes + watermelon pieces bouncing around the trail
	Watermelon = { kind = "stripes", colors = { Color3.fromRGB(255, 55, 70), Color3.fromRGB(18, 14, 16) }, bands = 4, light = 0.4, particle = "rbxassetid://128895687730453", particleStyle = "bounce", particleY = 0 },
}

-- 정적 무지개: 스펙트럼이 트레일 길이를 따라 박힘
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 64, 64)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 154, 32)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 230, 40)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(88, 232, 74)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(1.0, Color3.fromRGB(176, 96, 255)),
})

local CYCLE_SPEED = 0.6   -- rainbowcycle hue 초당 바퀴수
local SWAY_SPEED  = 7      -- 좌우 나풀거림 진동 속도(rad/s)
local SWAY_AMOUNT = 0.13   -- 좌우 나풀거림 폭(스터드) — "약간"

-- ✨ [2026-08-30] 연결을 캐릭터별로 보관한다.
--   [왜] 예전엔 cycleConn/swayConn 이 단일 변수였다. 대상이 내 캐릭터 하나뿐이라 충분했다.
--     그런데 디코이 분신에도 같은 트레일을 붙이게 되면서 대상이 둘이 됐고,
--     단일 변수면 분신 트레일을 만드는 순간 내 트레일 애니메이션이 끊긴다.
--   ⚠️ 새 대상을 추가할 때 이 표를 안 쓰면 같은 사고가 난다 — 항상 character 를 키로 쓸 것.
local cycleConns = {}   -- [character] = Heartbeat 연결 (rainbowcycle)
local swayConns  = {}   -- [character] = Heartbeat 연결 (좌우 나풀거림)

local function currentCharacter()
	return player.Character
end

local function stopCycle(character)
	local c = cycleConns[character]
	if c then c:Disconnect(); cycleConns[character] = nil end
end

local function stopSway(character)
	local c = swayConns[character]
	if c then c:Disconnect(); swayConns[character] = nil end
end

-- 캐릭터에서 기존 트레일 요소 제거
local function clearTrail(character)
	if not character then return end
	stopCycle(character)
	stopSway(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for _, x in ipairs(hrp:GetChildren()) do
		local nm = x.Name
		if nm:sub(1,9) == "_TrailAtt" or nm:sub(1,12) == "_RunnerTrail" or nm == "_TrailParticle" then
			x:Destroy()
		end
	end
end

-- 스펙대로 트레일 생성
local function buildTrail(character, spec)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	clearTrail(character)

	if spec.kind == "layered" then
		-- 폭 방향 적층: 층 수만큼 얇은 트레일을 위→아래로 쌓아 각 층에 다른 색
		local layers = spec.layers or { Color3.fromRGB(255,255,255) }
		local n = #layers
		local top, bottom = 0.9, -0.9
		-- 층별 두께 = weights (없으면 균등). 예: {2,1,2} → 가운데 얇음
		local weights = spec.weights or {}
		local wsum = 0
		for i = 1, n do wsum = wsum + (weights[i] or 1) end
		local boundaries = { [0] = top }
		local acc = 0
		for i = 1, n do
			acc = acc + (weights[i] or 1)
			boundaries[i] = top - (acc / wsum) * (top - bottom)
		end
		local atts = {}
		for i = 0, n do
			local a = Instance.new("Attachment")
			a.Name = "_TrailAttL" .. i
			a.Position = Vector3.new(0, boundaries[i], 0)
			a.Parent = hrp
			atts[i] = a
		end
		for i = 1, n do
			local tr = Instance.new("Trail")
			tr.Name = "_RunnerTrailL" .. i
			tr.Attachment0 = atts[i-1]
			tr.Attachment1 = atts[i]
			tr.Lifetime = 0.6
			tr.MinLength = 0.1
			tr.FaceCamera = true
			tr.LightEmission = spec.light or 0.5
			tr.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			tr.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.2),
			})
			tr.Color = ColorSequence.new(layers[i])
			tr.Parent = hrp
		end
		swayConns[character] = RunService.Heartbeat:Connect(function()
			if not (atts[0] and atts[0].Parent) then stopSway(character) return end
			local x = math.sin(tick() * SWAY_SPEED) * SWAY_AMOUNT
			for i = 0, n do
				if atts[i] and atts[i].Parent then atts[i].Position = Vector3.new(x, boundaries[i], 0) end
			end
		end)
	else
	local a0 = Instance.new("Attachment")
	a0.Name = "_TrailAtt0"
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = hrp

	local a1 = Instance.new("Attachment")
	a1.Name = "_TrailAtt1"
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = hrp

	-- 좌우로 약간씩 나풀거림: 어태치먼트 X를 sin으로 흔들어 트레일 경로가 물결치게(모든 스킨 공통)
	swayConns[character] = RunService.Heartbeat:Connect(function()
		if not (a0.Parent and a1.Parent) then stopSway(character) return end
		local x = math.sin(tick() * SWAY_SPEED) * SWAY_AMOUNT
		a0.Position = Vector3.new(x, 0.9, 0)
		a1.Position = Vector3.new(x, -0.9, 0)
	end)

	local trail = Instance.new("Trail")
	trail.Name = "_RunnerTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6   -- 기본 길이(길수록 뒤로 길게 남음)
	trail.MinLength = 0.1
	trail.FaceCamera = true   -- 항상 카메라를 향하게 → 정후면 등 어느 각도에서도 보임(false면 옆날로 보여 사라짐)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.LightEmission = spec.light or 0.5

	-- 색 적용 (스펙 종류별)
	if spec.kind == "stripes" then
		local kps = {}
		local n = spec.bands or (#spec.colors)
		local eps = 0.001
		for i = 0, n - 1 do
			local col = spec.colors[(i % #spec.colors) + 1]
			local a = i / n
			local b = (i + 1) / n
			if i > 0 then a = a + eps end
			if b > 1 then b = 1 end
			table.insert(kps, ColorSequenceKeypoint.new(a, col))
			table.insert(kps, ColorSequenceKeypoint.new(b, col))
		end
		trail.Color = ColorSequence.new(kps)
	elseif spec.kind == "gradient" then
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, spec.from),   -- 머리(어태치먼트 쪽)
			ColorSequenceKeypoint.new(1, spec.to),     -- 꼬리(끝)
		})
	elseif spec.kind == "rainbow" then
		trail.Color = RAINBOW_SEQ
	elseif spec.kind == "rainbowcycle" then
		trail.Color = ColorSequence.new(Color3.fromHSV(0, 1, 1))
		cycleConns[character] = RunService.Heartbeat:Connect(function()
			if not trail.Parent then stopCycle(character) return end
			local hue = (tick() * CYCLE_SPEED) % 1
			trail.Color = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
		end)
	else  -- solid
		trail.Color = ColorSequence.new(spec.color)
	end

	trail.Parent = hrp
	end

	-- optional particle: if spec.particle set, pieces pop and bounce around the trail
	if spec.particle then
		local pAtt = Instance.new("Attachment")
		pAtt.Name = "_TrailParticle"
		pAtt.Position = Vector3.new(0, spec.particleY or 0, 0.3)   -- emit from top/bottom of trail via particleY
		pAtt.Parent = hrp

		local pe = Instance.new("ParticleEmitter")
		pe.Texture = spec.particle
		pe.Rate = 16
		pe.Lifetime = NumberRange.new(0.5, 0.9)
		pe.Speed = NumberRange.new(1.5, 3)        -- gentle pop, not a back-jet
		pe.SpreadAngle = Vector2.new(80, 80)      -- burst in all directions around the trail
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-200, 200)  -- lively tumbling
		pe.Acceleration = Vector3.new(0, -6, 0)   -- light gravity, little bounce arcs
		pe.Drag = 1
		pe.LightEmission = 0
		pe.LockedToPart = false
		if spec.particleStyle == "snow" then
			-- 눈: 느리고 floaty하게 아래로 흩날림
			pe.Rate = 24
			pe.Lifetime = NumberRange.new(1.0, 1.8)
			pe.Speed = NumberRange.new(0.5, 1.5)
			pe.SpreadAngle = Vector2.new(120, 120)
			pe.Acceleration = Vector3.new(0, -2.5, 0)   -- 약한 중력 = 천천히 낙하
			pe.RotSpeed = NumberRange.new(-60, 60)
			pe.Drag = 2.5
			pe.LightEmission = 0.35
		end
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.15, 0.8),
			NumberSequenceKeypoint.new(1, 0.3),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Parent = pAtt
	end
end

-- 현재 TrailSkin 속성을 읽어 적용(없으면 제거)
-- 트레일은 역할 공용 코스메틱이다 — 대시(러너 스킬)나 크라운(태거 상징)과 달리
-- "움직인 흔적"이라 어느 역할에 달아도 어색하지 않고 밸런스 영향도 없다.
-- 태거는 이미 왕관·HP바로 노출되어 있어 위치 정보가 추가로 새지 않는다.
-- (스크립트 이름은 RunnerTrail 이지만 역할 제한 없음 — 이름은 하위호환으로 유지)
local function applyTrailSkin()
	local character = currentCharacter()
	if not character then return end
	local skinKey = player:GetAttribute("TrailSkin")
	local spec = skinKey and skinKey ~= "" and TRAIL_SKINS_SPEC[skinKey]
	if spec then
		buildTrail(character, spec)
	else
		clearTrail(character)  -- 미장착/해제 → 트레일 없음
	end
end

-- 캐릭터 스폰 시 적용
player.CharacterAdded:Connect(function()
	task.wait(0.2)  -- HRP 준비 여유
	applyTrailSkin()
end)
if player.Character then
	applyTrailSkin()
end

-- 속성 변경 시 즉시 반영(UI에서 장착/해제)
player:GetAttributeChangedSignal("TrailSkin"):Connect(applyTrailSkin)

-- 🎭 [2026-08-30] 디코이 분신에도 같은 트레일을 붙인다.
--   [왜] 분신의 목적은 태거가 진짜와 구분하지 못하는 것이다. 잔상 색(DashSkin)은 이미
--     맞춰뒀는데 트레일만 없으면 오히려 표식이 되어 분신이 먼저 걸러진다.
--   [어떻게] 서버가 분신 모델에 IsDecoy + TrailSkin 을 박아둔다(DecoySystem).
--     클라는 그 모델을 보고 '내 캐릭터'와 같은 코드로 트레일을 만든다.
--   ⚠️ 내 분신만이 아니라 남의 분신도 붙어야 한다 — 모델 속성만 보고 판단하므로 자동으로 된다.
--   ⚠️ 분신이 사라질 때 정리해야 한다. cycleConns/swayConns 는 캐릭터를 키로 잡고 있어
--     모델이 없어져도 연결이 남으면 매 프레임 죽은 어태치먼트를 본다.
local function hookDecoy(model)
	if not model:IsA("Model") then return end
	if model:GetAttribute("IsDecoy") ~= true then return end
	task.spawn(function()
		local key = model:GetAttribute("TrailSkin")
		local spec = key and key ~= "" and TRAIL_SKINS_SPEC[key]
		if not spec then return end
		if not model:FindFirstChild("HumanoidRootPart") then
			model:WaitForChild("HumanoidRootPart", 5)
		end
		if not model.Parent then return end
		buildTrail(model, spec)
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then clearTrail(model) end
	end)
end

for _, m in ipairs(workspace:GetChildren()) do hookDecoy(m) end
workspace.ChildAdded:Connect(hookDecoy)
