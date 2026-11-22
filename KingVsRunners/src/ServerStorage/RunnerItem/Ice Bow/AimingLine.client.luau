-- Ice Bow 조준선 (차징 중 사거리 시각화)
-- HRP 위치에서 마우스 방향으로 직선/점선 표시.
-- 길이 = min(마우스까지 거리, 현재 차징 사거리)
-- 색상: 마우스가 사거리 안이면 시안, 밖이면 빨강 (사거리 더 차징해야 닿음)

local Tool = script.Parent
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ── 설정 ────────────────────────────────────────────────
local MIN_RANGE        = 180
local MAX_RANGE        = 1800
local MAX_CHARGE_TIME  = 0.8
local MIN_POWER_DISPLAY = 0.05   -- 이 이상부터 라인 표시 (시각 안정)

local COLOR_IN_RANGE   = Color3.fromRGB(140, 220, 255)  -- 시안 (사거리 안)
local COLOR_OUT_RANGE  = Color3.fromRGB(255, 110, 110)  -- 빨강 (사거리 밖)

-- ── 상태 ────────────────────────────────────────────────
local mouse = nil
local charging = false
local chargeStartTime = 0
local endpointPart = nil
local originAttachment = nil
local endpointAttachment = nil
local beam = nil
local heartbeatConn = nil

local function getPower()
	if not charging then return 0 end
	return math.clamp((tick() - chargeStartTime) / MAX_CHARGE_TIME, 0, 1)
end

local function createBeam()
	-- 캐릭터 HRP에 origin attachment
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 이미 있으면 정리
	if originAttachment then originAttachment:Destroy() end
	if endpointPart then endpointPart:Destroy() end

	originAttachment = Instance.new("Attachment")
	originAttachment.Name = "IceBowAimOrigin"
	originAttachment.Parent = hrp

	endpointPart = Instance.new("Part")
	endpointPart.Name = "IceBowAimEnd"
	endpointPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endpointPart.Transparency = 1
	endpointPart.CanCollide = false
	endpointPart.Anchored = true
	endpointPart.Parent = workspace

	endpointAttachment = Instance.new("Attachment")
	endpointAttachment.Name = "IceBowAimEnd"
	endpointAttachment.Parent = endpointPart

	beam = Instance.new("Beam")
	beam.Name = "IceBowAimBeam"
	beam.Attachment0 = originAttachment
	beam.Attachment1 = endpointAttachment
	beam.Width0 = 0.55           -- 0.2 → 0.55 (굵게)
	beam.Width1 = 0.55
	beam.LightEmission = 0.6     -- 1 → 0.6 (너무 빛나서 흐려보이는 거 완화)
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(COLOR_IN_RANGE)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),       -- 0.2 → 0 (시작 완전 불투명)
		NumberSequenceKeypoint.new(0.92, 0.1),  -- 0.4 → 0.1 (대부분 길이 거의 불투명)
		NumberSequenceKeypoint.new(1, 1),       -- 끝부분 페이드 아웃 유지
	})
	-- 점선 패턴: Texture 사용 + TextureSpeed로 흐르는 효과
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 2
	beam.TextureSpeed = 1
	beam.Parent = originAttachment
	beam.Enabled = false
end

local function destroyBeam()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	if beam then beam:Destroy(); beam = nil end
	if endpointAttachment then endpointAttachment:Destroy(); endpointAttachment = nil end
	if endpointPart then endpointPart:Destroy(); endpointPart = nil end
	if originAttachment then originAttachment:Destroy(); originAttachment = nil end
end

local function setLineVisible(visible)
	if not beam then return end
	beam.Enabled = visible
end

-- 매 프레임 endpoint 위치 갱신
local function updateLine()
	if not beam or not endpointPart or not originAttachment then return end
	if not mouse then return end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local power = getPower()
	if power < MIN_POWER_DISPLAY then
		setLineVisible(false)
		return
	end

	local startPos = hrp.Position
	local mousePos = mouse.Hit and mouse.Hit.Position
	if not mousePos then return end

	local toMouse = mousePos - startPos
	local distanceToMouse = toMouse.Magnitude
	if distanceToMouse < 0.1 then return end
	local direction = toMouse.Unit

	-- 현재 차징 사거리
	local currentRange = MIN_RANGE + (MAX_RANGE - MIN_RANGE) * power

	-- 실제 라인 길이: 마우스까지 거리와 사거리 중 작은 값
	local lineLength = math.min(distanceToMouse, currentRange)
	local endPos = startPos + direction * lineLength

	endpointPart.Position = endPos

	-- 색상: 마우스가 사거리 밖이면 빨강
	local color
	if distanceToMouse > currentRange then
		color = COLOR_OUT_RANGE
	else
		color = COLOR_IN_RANGE
	end
	beam.Color = ColorSequence.new(color)

	setLineVisible(true)
end

-- ── BindableEvent 수신 ──────────────────────────────────
local function onChargeEvent(event, power)
	if event == "start" then
		charging = true
		chargeStartTime = tick()
		createBeam()
		-- 매 프레임 라인 갱신
		if heartbeatConn then heartbeatConn:Disconnect() end
		heartbeatConn = RunService.Heartbeat:Connect(updateLine)
	elseif event == "update" then
		-- updateLine이 직접 power를 계산하므로 추가 작업 불필요
	elseif event == "end" or event == "cancel" then
		charging = false
		destroyBeam()
	end
end

task.spawn(function()
	local bindable = Tool:WaitForChild("ChargeBindable", 10)
	if bindable then
		bindable.Event:Connect(onChargeEvent)
	end
end)

-- ── Tool 라이프사이클 ──────────────────────────────────
Tool.Equipped:Connect(function(mouseObj)
	mouse = mouseObj
end)

Tool.Unequipped:Connect(function()
	mouse = nil
	charging = false
	destroyBeam()
end)

Tool.Destroying:Connect(destroyBeam)
LocalPlayer.CharacterRemoving:Connect(destroyBeam)
