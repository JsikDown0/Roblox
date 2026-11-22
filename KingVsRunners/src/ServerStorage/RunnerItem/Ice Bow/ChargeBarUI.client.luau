-- Ice Bow 차징 게이지 UI
-- FireInput이 BindableEvent로 ("start"/"update"/"end"/"cancel", power 0~1) 신호 보냄
-- 화면 가운데 가로 게이지 표시

local Tool = script.Parent
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")

-- ── 색상 ────────────────────────────────────────────────
local COLOR_LOW    = Color3.fromRGB(100, 160, 200)   -- 차징 초기 (어두운 파랑)
local COLOR_MID    = Color3.fromRGB(140, 220, 255)   -- 중간 (밝은 파랑)
local COLOR_FULL   = Color3.fromRGB(255, 255, 220)   -- 만렙 (흰빛 노랑)
local FULL_THRESHOLD = 0.95                            -- 이 이상이면 "만렙" 표시

-- ── 상태 ────────────────────────────────────────────────
local gui = nil
local barFill = nil
local barFrame = nil
local stroke = nil
local fullBlink = nil

local function getColorForPower(power)
	if power < 0.5 then
		return COLOR_LOW:Lerp(COLOR_MID, power * 2)
	else
		return COLOR_MID:Lerp(COLOR_FULL, (power - 0.5) * 2)
	end
end

local function createUI()
	if gui then return end
	local pg = Player:WaitForChild("PlayerGui")
	local stale = pg:FindFirstChild("IceBowChargeBar")
	if stale then stale:Destroy() end

	gui = Instance.new("ScreenGui")
	gui.Name = "IceBowChargeBar"
	gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = pg

	barFrame = Instance.new("Frame", gui)
	barFrame.Name = "Bar"
	barFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	barFrame.Position = UDim2.new(0.5, 0, 0.62, 0)  -- 화면 중앙 살짝 아래
	barFrame.Size = UDim2.fromOffset(220, 16)
	barFrame.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	barFrame.BackgroundTransparency = 0.3
	barFrame.BorderSizePixel = 0
	barFrame.Visible = false  -- 차징 시작할 때 보이게

	local corner = Instance.new("UICorner", barFrame)
	corner.CornerRadius = UDim.new(0, 6)

	stroke = Instance.new("UIStroke", barFrame)
	stroke.Color = COLOR_MID
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4

	barFill = Instance.new("Frame", barFrame)
	barFill.Name = "Fill"
	barFill.AnchorPoint = Vector2.new(0, 0.5)
	barFill.Position = UDim2.new(0, 3, 0.5, 0)
	barFill.Size = UDim2.new(0, 0, 1, -6)  -- 너비는 power에 따라
	barFill.BackgroundColor3 = COLOR_LOW
	barFill.BorderSizePixel = 0

	local fillCorner = Instance.new("UICorner", barFill)
	fillCorner.CornerRadius = UDim.new(0, 4)

	-- "POWER" 라벨 (게이지바 왼쪽 바깥)
	local label = Instance.new("TextLabel", barFrame)
	label.Name = "PowerLabel"
	label.AnchorPoint = Vector2.new(1, 0.5)
	label.Position = UDim2.new(0, -10, 0.5, 0)   -- barFrame 왼쪽 10 px 떨어진 위치
	label.Size = UDim2.fromOffset(70, 20)
	label.BackgroundTransparency = 1
	label.Text = "POWER"
	label.TextColor3 = Color3.fromRGB(210, 235, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center

	local labelStroke = Instance.new("UIStroke", label)
	labelStroke.Color = Color3.fromRGB(0, 0, 0)
	labelStroke.Thickness = 1.5
	labelStroke.Transparency = 0.3
end

local function destroyUI()
	if fullBlink then fullBlink:Cancel(); fullBlink = nil end
	if gui then
		gui:Destroy()
		gui = nil
		barFill, barFrame, stroke = nil, nil, nil
	end
end

local function showBar(visible)
	if not barFrame then return end
	barFrame.Visible = visible
end

local function updateBar(power)
	if not barFill or not barFrame or not stroke then return end
	local fullWidth = 220 - 6  -- 양옆 3 padding
	barFill.Size = UDim2.new(0, fullWidth * power, 1, -6)
	local c = getColorForPower(power)
	barFill.BackgroundColor3 = c
	stroke.Color = c

	-- 만렙 도달 시 깜빡임 (이미 깜빡임 중이면 새로 안 만듦)
	if power >= FULL_THRESHOLD then
		if not fullBlink then
			-- stroke transparency를 부드럽게 깜빡임
			fullBlink = TweenService:Create(stroke,
				TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{Transparency = 0})
			fullBlink:Play()
		end
	else
		if fullBlink then
			fullBlink:Cancel()
			fullBlink = nil
			stroke.Transparency = 0.4
		end
	end
end

-- ── BindableEvent 수신 ──────────────────────────────────
local function onChargeEvent(event, power)
	if event == "start" then
		createUI()
		updateBar(0)
		showBar(true)
	elseif event == "update" then
		updateBar(power)
	elseif event == "end" or event == "cancel" then
		showBar(false)
		if fullBlink then fullBlink:Cancel(); fullBlink = nil end
		if stroke then stroke.Transparency = 0.4 end
	end
end

-- Tool 안의 BindableEvent를 기다림 (FireInput이 생성)
task.spawn(function()
	local bindable = Tool:WaitForChild("ChargeBindable", 10)
	if bindable then
		bindable.Event:Connect(onChargeEvent)
	end
end)

-- ── Tool/Character 라이프사이클 ─────────────────────────
Tool.Unequipped:Connect(function()
	showBar(false)
end)
Tool.Destroying:Connect(destroyUI)
Player.CharacterRemoving:Connect(destroyUI)
