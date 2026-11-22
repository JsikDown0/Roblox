-- ODM Gear 클라이언트: 마우스 클릭 → 서버로 발사 요청
local Tool = script.Parent
local RM = Tool:WaitForChild("RemoteEvent")
local hand = Tool:WaitForChild("hand")
local sound = hand:FindFirstChild("Sound")

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Player = Players.LocalPlayer

local MAX_DISTANCE = 110

-- ── 사거리 초과 경고 UI ──────────────────────────────────
local warnGui, warnLabel, warnStroke = nil, nil, nil
local warnVersion = 0

local function ensureWarnUI()
	if warnGui and warnGui.Parent then return end
	local pg = Player:WaitForChild("PlayerGui")
	warnGui = pg:FindFirstChild("GrappleWarn")
	if warnGui then warnLabel = warnGui:FindFirstChild("Label"); warnStroke = warnLabel and warnLabel:FindFirstChildOfClass("UIStroke"); return end

	warnGui = Instance.new("ScreenGui")
	warnGui.Name = "GrappleWarn"
	warnGui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
	warnGui.DisplayOrder = 10
	warnGui.Parent = pg

	warnLabel = Instance.new("TextLabel")
	warnLabel.Name = "Label"
	warnLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	warnLabel.Position = UDim2.new(0.5, 0, 0.32, 0)
	warnLabel.Size = UDim2.fromOffset(260, 48)
	warnLabel.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
	warnLabel.BackgroundTransparency = 1  -- 시작은 숨김
	warnLabel.BorderSizePixel = 0
	warnLabel.Font = Enum.Font.GothamBold
	warnLabel.TextSize = 20
	warnLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	warnLabel.TextTransparency = 1
	warnLabel.Text = ""
	warnLabel.Parent = warnGui

	local c = Instance.new("UICorner", warnLabel)
	c.CornerRadius = UDim.new(0, 8)

	warnStroke = Instance.new("UIStroke", warnLabel)
	warnStroke.Color = Color3.fromRGB(255, 70, 70)
	warnStroke.Thickness = 2
	warnStroke.Transparency = 1
end

local function showWarn(text)
	ensureWarnUI()
	warnVersion = warnVersion + 1
	local myVersion = warnVersion

	warnLabel.Text = text
	-- 즉시 표시 (페이드 진행 중이면 캔슬되고 새로 보임)
	warnLabel.BackgroundTransparency = 0.15
	warnLabel.TextTransparency = 0
	warnStroke.Transparency = 0.3

	-- 0.9초 후 페이드아웃 (그 사이 새 호출 들어오면 이 페이드 무시)
	task.delay(0.9, function()
		if myVersion ~= warnVersion then return end
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(warnLabel, info, {BackgroundTransparency = 1, TextTransparency = 1}):Play()
		TweenService:Create(warnStroke, info, {Transparency = 1}):Play()
	end)
end

-- ── 발사 로직 ───────────────────────────────────────────
local mouseConn = nil

Tool.Equipped:Connect(function(mouse)
	local char = Tool.Parent
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end

	mouseConn = mouse.Button1Down:Connect(function()
		if not Tool.Enabled then return end
		local charges = Tool:GetAttribute("Charges") or 0
		if charges <= 0 then
			showWarn("⛓  NO CHARGES LEFT")
			return
		end

		local targetCFrame = mouse.Hit
		local targetPart = mouse.Target
		if not targetCFrame then return end

		-- 자기 자신 차단
		if targetPart and targetPart:IsDescendantOf(char) then return end

		local distance = (root.Position - targetCFrame.Position).Magnitude
		if distance > MAX_DISTANCE then
			showWarn(string.format("⚠  OUT OF RANGE  (%d / %d)", math.floor(distance), MAX_DISTANCE))
			return
		end

		if sound then sound:Play() end
		RM:FireServer(root, targetCFrame, targetPart, humanoid)
	end)
end)

Tool.Unequipped:Connect(function()
	if mouseConn then
		mouseConn:Disconnect()
		mouseConn = nil
	end
end)
