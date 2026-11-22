-- SoloRoleClient — 1인 서버 역할 선택 UI
-- 서버에 나 혼자 + 인터미션일 때만 하단 패널 표시:
--   ⚔️ Runner vs KING (기본) / 👑 Tagger vs AI
-- 선택은 SoloRoleChoice RemoteEvent로 서버(TaggerBotSystem)에 전달 → RoundSystem이 라운드 시작 시 반영.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local soloRoleEvent = ReplicatedStorage:WaitForChild("SoloRoleChoice")
local phaseEvent = ReplicatedStorage:WaitForChild("RoundPhaseEvent")

local COLOR_RUNNER      = Color3.fromRGB(30, 120, 220)
local COLOR_TAGGER      = Color3.fromRGB(200, 40, 40)
local COLOR_UNSELECTED  = Color3.fromRGB(55, 55, 60)

local currentChoice = "runner"   -- 기본값 (서버 기본과 일치)
local currentPhase = "intermission"

-- ── UI 구성 ──────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "SoloRoleGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

-- ⚠️ 고정 픽셀 크기라 모바일에서 화면을 크게 차지했다(가로 344px = 폰 화면의 40% 이상).
--    ResponsiveScaler 로 디바이스를 판별해 모바일에서만 축소한다.
--    (전 UI 가 같은 모듈로 디바이스를 판정하므로 기준이 어긋나지 않는다)
local Scaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))
local isMobile = Scaler.isMobile()

local PANEL_W  = isMobile and 250 or 344
local PANEL_H  = isMobile and 72  or 96
local BTN_W    = isMobile and 112 or 155
local BTN_H    = isMobile and 38  or 52
local BTN_Y    = isMobile and 26  or 34
local TITLE_SZ = isMobile and 11  or 15
local BTN_TSZ  = isMobile and 13  or 16
local GAP      = isMobile and 8   or 10

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -18)
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, isMobile and 20 or 26)
title.Position = UDim2.new(0, 0, 0, 4)
title.Font = Enum.Font.BuilderSansExtraBold
title.TextSize = TITLE_SZ
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.Text = "You're solo! Pick your role for next round"
title.Parent = panel

local function makeBtn(name, text, xPos)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(0, BTN_W, 0, BTN_H)
	b.Position = UDim2.new(0, xPos, 0, BTN_Y)
	b.Font = Enum.Font.BuilderSansExtraBold
	b.TextSize = BTN_TSZ
	b.TextScaled = false
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Text = text
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = panel
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = b
	local st = Instance.new("UIStroke"); st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Thickness = 2; st.Color = Color3.fromRGB(255,255,255); st.Transparency = 1; st.Parent = b
	return b, st
end

-- 좌우 균등 배치: 패널 폭에서 버튼 2개와 간격을 뺀 나머지를 양끝 여백으로
local sideMargin = (PANEL_W - BTN_W * 2 - GAP) / 2
local runnerBtn, runnerStroke = makeBtn("RunnerBtn", "Runner", sideMargin)
local taggerBtn, taggerStroke = makeBtn("TaggerBtn", "King", sideMargin + BTN_W + GAP)

local function refreshButtons()
	local isRunner = (currentChoice == "runner")
	runnerBtn.BackgroundColor3 = isRunner and COLOR_RUNNER or COLOR_UNSELECTED
	taggerBtn.BackgroundColor3 = (not isRunner) and COLOR_TAGGER or COLOR_UNSELECTED
	runnerStroke.Transparency = isRunner and 0 or 1
	taggerStroke.Transparency = (not isRunner) and 0 or 1
end

local function choose(choice)
	currentChoice = choice
	refreshButtons()
	soloRoleEvent:FireServer(choice)
end

runnerBtn.MouseButton1Click:Connect(function() choose("runner") end)
taggerBtn.MouseButton1Click:Connect(function() choose("tagger") end)

-- ── 표시 조건: 1인 서버 + 인터미션 ──────────────────
local function refreshVisibility()
	local solo = (#Players:GetPlayers() == 1)
	gui.Enabled = solo and (currentPhase == "intermission")
end

Players.PlayerAdded:Connect(refreshVisibility)
Players.PlayerRemoving:Connect(function(p)
	-- Removing 시점엔 아직 목록에 있으므로 한 프레임 뒤 재판정
	task.defer(refreshVisibility)
end)
phaseEvent.OnClientEvent:Connect(function(phase)
	currentPhase = phase
	refreshVisibility()
end)

refreshButtons()
refreshVisibility()
print("✅ SoloRoleClient 활성화 (1인 서버 역할 선택 UI)")
