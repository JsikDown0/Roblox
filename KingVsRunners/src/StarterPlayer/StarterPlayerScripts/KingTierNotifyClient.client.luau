-- KingTierNotifyClient — 라운드 시작 시 봇 킹 난이도를 알려준다.
--
-- [왜] 티어(easy/normal/hard)는 로그에만 찍히고 화면엔 아무 단서가 없었다.
--   그래서 "져도 왜 졌는지, 이겨도 뭘 이긴 건지" 알 수 없었다.
--   난이도를 고를 수 있게 하는 대신, 무엇을 만났는지만 알려준다 —
--   선택지를 열면 유저는 유리한 쪽만 반복해 hard 가 죽은 콘텐츠가 된다.
--
-- [읽는 값] ReplicatedStorage 속성 두 개.
--   KingBotTier          : "easy" / "normal" / "hard"
--   KingIsBot            : 지금이 봇 킹 라운드인가 (유저 킹이면 false)
--   KingTierNewbieGuard  : 뉴비 보정으로 hard 가 제외됐는가
--   ⚠️ KingBotTier 는 라운드가 끝나도 값이 남는다. 반드시 KingIsBot 과 함께 볼 것 —
--     혼자 읽으면 유저 킹 라운드에서 이전 판 티어를 표시한다.
--
-- ⚠️ 표시 자리는 배너(Y=0.32)를 재사용한다. 3초 뒤 사라지므로 THRONE FALLEN 배너와
--   시점이 겹치지 않는다(그쪽은 2단계 중반). 상시 표시로 바꾸려면 좌상단처럼
--   빈 자리를 찾아야 한다 — 상단 중앙은 Round 타이머와 저주 HUD 가 이미 쓴다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local SHOW_TIME = 3.0

-- ⚠️ 아랫줄은 '난이도 설명'이지 왕에 대한 서술이 아니다.
--   [왜] King 은 이 게임의 고유명사(역할 이름)라, "The King strikes fast" 처럼 쓰면
--     처음 보는 사람은 난이도가 아니라 왕의 설정을 말하는 줄 읽는다.
--     윗줄이 이미 "KING: HARD" 로 대상을 밝혔으므로, 아랫줄은 난이도만 말한다.
local TIER_INFO = {
	easy   = { label = "EASY",   color = Color3.fromRGB(120, 230, 120),
	           desc  = "Difficulty: Easy — a forgiving match" },
	normal = { label = "NORMAL", color = Color3.fromRGB(255, 210, 90),
	           desc  = "Difficulty: Normal — a fair fight" },
	hard   = { label = "HARD",   color = Color3.fromRGB(255, 105, 95),
	           desc  = "Difficulty: Hard — expect no mercy" },
}

local gui = Instance.new("ScreenGui")
gui.Name = "KingTierNotify"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.32, 0)
frame.Size = UDim2.new(0, 420, 0, 84)
frame.BackgroundColor3 = Color3.fromRGB(18, 16, 22)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 0
frame.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 8)
title.Size = UDim2.new(1, -20, 0, 36)
title.BackgroundTransparency = 1
title.Font = Enum.Font.LuckiestGuy
title.TextScaled = true
title.TextStrokeTransparency = 0.4
title.Parent = frame

local sub = Instance.new("TextLabel")
sub.AnchorPoint = Vector2.new(0.5, 0)
sub.Position = UDim2.new(0.5, 0, 0, 46)
sub.Size = UDim2.new(1, -20, 0, 30)
sub.BackgroundTransparency = 1
sub.Font = Enum.Font.GothamMedium
sub.TextScaled = true
sub.TextColor3 = Color3.fromRGB(225, 225, 235)
sub.TextStrokeTransparency = 0.6
sub.Parent = frame

local hideTask = nil

local function show(tierName, newbieGuard)
	local info = TIER_INFO[tierName]
	if not info then return end
	title.Text = "KING: " .. info.label
	title.TextColor3 = info.color
	-- 뉴비 보정이 걸린 판은 그 사실을 알려준다. 모르면 "운이 좋았다"로만 읽힌다.
	-- 뉴비 보정도 난이도 이야기로 맞춘다. "Hard is off" 만 쓰면 무엇이 off 인지 모호하다.
	sub.Text = newbieGuard
		and (info.desc .. "  ·  Hard difficulty is locked for your first rounds")
		or info.desc

	gui.Enabled = true
	for _, o in ipairs({ title, sub }) do o.TextTransparency = 0 end
	frame.BackgroundTransparency = 0.25

	if hideTask then task.cancel(hideTask) end
	hideTask = task.delay(SHOW_TIME, function()
		local ti = TweenInfo.new(0.4)
		TweenService:Create(frame, ti, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, ti, { TextTransparency = 1 }):Play()
		local last = TweenService:Create(sub, ti, { TextTransparency = 1 })
		last:Play()
		last.Completed:Wait()
		gui.Enabled = false
	end)
end

-- 라운드가 시작될 때만 본다.
--   ⚠️ KingBotTier 변화를 듣지 않는다. 그 값은 봇 소환 시점에 세워지는데, 그때는
--     아직 RoundPhase 가 넘어오기 전일 수 있어 순서가 흔들린다. 페이즈를 기준으로 삼는다.
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	local ph = ReplicatedStorage:GetAttribute("RoundPhase")
	if ph ~= "stage1" then return end
	-- 속성이 아직 안 왔을 수 있어 한 번 기다린다.
	task.wait(0.25)
	if not ReplicatedStorage:GetAttribute("KingIsBot") then return end   -- 유저 킹 판이면 표시 안 함
	show(ReplicatedStorage:GetAttribute("KingBotTier"),
	     ReplicatedStorage:GetAttribute("KingTierNewbieGuard"))
end)

print("🏷️ KingTierNotifyClient 활성화")
