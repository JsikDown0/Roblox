-- TrapPlacementClient
-- 'bear_trap' placement 모드: 마우스 hit에 따라 청사진 표시 + 클릭 시 PlaceTrap 발사.
-- ItemSpawnHandler가 itemName=="bear_trap"이면 일반 spawn 대신 이 시스템에 위임 (placement 모드 활성).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local placeEvent = ReplicatedStorage:WaitForChild("PlaceTrap")
local enterMode  = ReplicatedStorage:WaitForChild("EnterTrapPlacement")  -- 서버가 발사

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

-- 조준 사거리. 최종 판정은 서버(TrapSystem.ZONE_BY_MAP)가 한다.
local MAX_RANGE = 120
local active = false
local blueprint = nil
local heartbeatConn = nil
local clickConn = nil
local keyConn = nil

-- ─── 청사진 생성 ──────────────────────────────────────────
local function makeBlueprint()
	-- 간단한 사각형 마커 + 빛
	local model = Instance.new("Model")
	model.Name = "TrapBlueprint"

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(4.5, 0.2, 4)
	base.Anchored = true
	base.CanCollide = false
	base.Transparency = 0.4
	base.Material = Enum.Material.Neon
	base.Color = Color3.fromRGB(255, 220, 0)  -- 노란색 (배치 가능)
	base.Parent = model

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 0)
	light.Range = 8
	light.Brightness = 2
	light.Parent = base

	-- 라벨
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 30)
	billboard.AlwaysOnTop = true
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Parent = base

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 220, 0)
	label.Text = "🪤 TRAP"
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	model.PrimaryPart = base
	return model, base, light, label
end

local function exitMode()
	active = false
	if blueprint then blueprint:Destroy() end
	blueprint = nil
	if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
	if clickConn    then clickConn:Disconnect()    clickConn    = nil end
	if keyConn      then keyConn:Disconnect()      keyConn      = nil end
	mouse.TargetFilter = nil
	print("🪤 Placement mode exited")
end

local function enterModeFn()
	if active then return end
	active = true

	local model, base, light, label = makeBlueprint()
	model.Parent = workspace
	blueprint = model
	mouse.TargetFilter = model  -- 청사진 자체는 raycast에서 제외

	print("🪤 Placement mode entered — 클릭=설치, ESC=취소")

	-- 매 프레임 마우스 위치 추적
	heartbeatConn = RunService.RenderStepped:Connect(function()
		if not blueprint or not blueprint.Parent then return end
		local hit = mouse.Hit
		if not hit then return end

		local pos = hit.Position
		blueprint:PivotTo(CFrame.new(pos + Vector3.new(0, 0.1, 0)))

		-- 사거리 검증
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (pos - hrp.Position).Magnitude
			if dist > MAX_RANGE then
				-- 사거리 밖 = 빨강
				base.Color = Color3.fromRGB(255, 50, 50)
				light.Color = Color3.fromRGB(255, 50, 50)
				label.TextColor3 = Color3.fromRGB(255, 50, 50)
				label.Text = "🪤 OUT OF RANGE"
			else
				-- 사거리 안 = 노랑
				base.Color = Color3.fromRGB(255, 220, 0)
				light.Color = Color3.fromRGB(255, 220, 0)
				label.TextColor3 = Color3.fromRGB(255, 220, 0)
				label.Text = "🪤 TRAP"
			end
		end
	end)

	-- 클릭 = 설치
	clickConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local hit = mouse.Hit
			if not hit then return end
			local pos = hit.Position

			-- 사거리 검증 (클라이언트 측에서도 한번)
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			if (pos - hrp.Position).Magnitude > MAX_RANGE then
				print("❌ 사거리 밖, 설치 불가")
				return
			end

			placeEvent:FireServer(pos)
			exitMode()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			exitMode()
		end
	end)
end

-- 서버가 placement 모드 진입 신호 보내면 시작
enterMode.OnClientEvent:Connect(enterModeFn)

print("✅ TrapPlacementClient ready")
