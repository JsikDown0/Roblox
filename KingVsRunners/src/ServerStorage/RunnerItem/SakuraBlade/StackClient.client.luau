-- SakuraBlade 스택 표시 UI (클라이언트)
-- 🌸 + 숫자로 현재 가속 스택(0~5)을 표시. 무기 들면 보이고 놓으면 숨김.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Tool = script.Parent
local StackRemote = Tool:WaitForChild("StackRemote")

local STACK_MAX = 5

-- ── UI 생성 ──────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "SakuraStackGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = playerGui

-- 컨테이너 (이모지 + 숫자를 가로로)
local frame = Instance.new("Frame")
frame.Name = "StackFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
-- 화면 하단 중앙보다 위 (모바일 조이스틱과 겹치지 않게)
frame.Position = UDim2.new(0.5, 0, 0.82, 0)
frame.Size = UDim2.new(0.16, 0, 0.07, 0)
frame.BackgroundColor3 = Color3.fromRGB(40, 20, 35)
frame.BackgroundTransparency = 0.35
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.4, 0)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 150, 220)
stroke.Thickness = 2
stroke.Transparency = 0.2
stroke.Parent = frame

-- 가로 배치
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0.04, 0)
layout.Parent = frame

-- 벚꽃 이모지
local emoji = Instance.new("TextLabel")
emoji.Name = "Emoji"
emoji.BackgroundTransparency = 1
emoji.Size = UDim2.new(0.4, 0, 0.8, 0)
emoji.Text = "🌸"
emoji.TextScaled = true
emoji.Font = Enum.Font.GothamBold
emoji.TextColor3 = Color3.fromRGB(255, 255, 255)
emoji.LayoutOrder = 1
emoji.Parent = frame

-- 숫자
local count = Instance.new("TextLabel")
count.Name = "Count"
count.BackgroundTransparency = 1
count.Size = UDim2.new(0.4, 0, 0.8, 0)
count.Text = "0"
count.TextScaled = true
count.Font = Enum.Font.GothamBold
count.TextColor3 = Color3.fromRGB(255, 200, 235)
count.LayoutOrder = 2
count.Parent = frame

local countStroke = Instance.new("UIStroke")
countStroke.Color = Color3.fromRGB(120, 40, 90)
countStroke.Thickness = 1.5
countStroke.Parent = count

-- ── 스택 갱신 ────────────────────────────────────────────────
-- 평소 모습 / 풀스택 화려 모습 색상 정의
local NORMAL = {
	bg = Color3.fromRGB(40, 20, 35),
	bgTrans = 0.35,
	stroke = Color3.fromRGB(255, 150, 220),
	strokeThick = 2,
	strokeTrans = 0.2,
	count = Color3.fromRGB(255, 200, 235),
}
local FULL = {
	bg = Color3.fromRGB(120, 30, 80),
	bgTrans = 0.1,
	stroke = Color3.fromRGB(255, 230, 120),   -- 금빛 테두리
	strokeThick = 4,
	strokeTrans = 0,
	count = Color3.fromRGB(255, 240, 160),
}

local isFull = false           -- 현재 풀스택 연출 중인가
local fullPulseTween = nil     -- 테두리 맥동 트윈
local baseFrameSize = frame.Size

-- 풀스택 진입: 패널 화려하게 + 맥동 + 확대 펄스
local function enterFull()
	if isFull then return end
	isFull = true
	-- 색/배경/테두리 전환
	TweenService:Create(frame, TweenInfo.new(0.25), {
		BackgroundColor3 = FULL.bg,
		BackgroundTransparency = FULL.bgTrans,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.25), {
		Color = FULL.stroke,
		Thickness = FULL.strokeThick,
		Transparency = FULL.strokeTrans,
	}):Play()
	count.TextColor3 = FULL.count
	-- 확대 펀치 (살짝 커졌다 원래대로)
	frame.Size = baseFrameSize
	local punch = baseFrameSize + UDim2.new(0.03, 0, 0.015, 0)
	local up = TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = punch })
	up.Completed:Connect(function()
		if isFull then
			TweenService:Create(frame, TweenInfo.new(0.15), { Size = baseFrameSize }):Play()
		end
	end)
	up:Play()
	-- 테두리 맥동 루프 (밝기 깜빡)
	fullPulseTween = TweenService:Create(stroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.5 })
	fullPulseTween:Play()
end

-- 풀스택 해제: 평소 모습으로
local function exitFull()
	if not isFull then return end
	isFull = false
	if fullPulseTween then fullPulseTween:Cancel(); fullPulseTween = nil end
	TweenService:Create(frame, TweenInfo.new(0.2), {
		BackgroundColor3 = NORMAL.bg,
		BackgroundTransparency = NORMAL.bgTrans,
		Size = baseFrameSize,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), {
		Color = NORMAL.stroke,
		Thickness = NORMAL.strokeThick,
		Transparency = NORMAL.strokeTrans,
	}):Play()
	count.TextColor3 = NORMAL.count
end

local function setStack(n)
	n = math.clamp(n or 0, 0, STACK_MAX)
	count.Text = tostring(n)
	if n >= STACK_MAX then
		enterFull()
	else
		exitFull()
	end
end

StackRemote.OnClientEvent:Connect(function(n)
	setStack(n)
end)

-- ── 무기 장착/해제로 표시·숨김 ───────────────────────────────
Tool.Equipped:Connect(function()
	setStack(0)
	gui.Enabled = true
end)

Tool.Unequipped:Connect(function()
	exitFull()       -- 풀스택 연출/맥동 정리
	gui.Enabled = false
end)
