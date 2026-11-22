-- BattlePassClient — 배틀패스 (더미 단계)
-- /robux(RobuxStoreClient) 패턴: /pass 임시커맨드 + _G.openBattlePass. 실물 지급/저장(DataStore)은 이후.
-- 슬라이스 1: 껍데기(가로 패널 + 헤더 + EXP게이지 + 푸터 + 토글). 티어 사다리는 슬라이스 2.
-- 자기완결형: 롤백은 이 스크립트 삭제.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))

-- 색 (다크 네이비, 상점과 통일)
local NAVY_BG   = Color3.fromRGB(40, 130, 200)   -- summer sea base (panel uses gradient below)
local NAVY_CARD = Color3.fromRGB(26, 78, 120)    -- card / tile on sea
local TEXT_MAIN = Color3.fromRGB(255, 255, 255)
local TEXT_SUB  = Color3.fromRGB(214, 236, 250)
local GREEN     = Color3.fromRGB(52, 199, 108)   -- free / claim (palm green)
local BLUE      = Color3.fromRGB(95, 205, 255)   -- accent (tier badge, sky cyan)
local GOLD      = Color3.fromRGB(255, 201, 64)   -- premium (summer sun)
local SKY       = Color3.fromRGB(88, 182, 238)   -- panel gradient top
local SEA       = Color3.fromRGB(28, 96, 158)    -- panel gradient bottom

-- ── ScreenGui ──
local gui = Instance.new("ScreenGui")
gui.Name = "BattlePassGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 60   -- SpectateGui(50) 위로 → Settings/관전이 패널 안 가림
gui.Enabled = false
gui.Parent = playerGui

-- 딤 (바깥 탭 시 닫힘)
local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.Text = ""
dim.AutoButtonColor = false
dim.Parent = gui

-- ── 패널 (가로형 — 배틀패스는 넓음) ──
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(900, 500)
panel.BackgroundColor3 = Color3.new(1, 1, 1)   -- white base so the panel gradient shows true
panel.BorderSizePixel = 0
panel.Parent = gui
local sizeCon = Instance.new("UISizeConstraint")
sizeCon.MaxSize = Vector2.new(1000, 620)
sizeCon.MinSize = Vector2.new(320, 240)
sizeCon.Parent = panel
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
-- summer sky -> sea vertical gradient on the panel
local panelGrad = Instance.new("UIGradient")
panelGrad.Rotation = 90
panelGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, SKY),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB(38, 180, 190)),   -- ocean teal
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(247, 214, 150)),  -- warm sand
})
panelGrad.Parent = panel

-- 헤더 일러스트 (여름 비치 배너). Decal 122347151340570 → LoadAsset resolve된 실제 Image ID.
-- 타이틀/진행바 뒤(ZIndex 0)에 상단 밴드로. UICorner로 패널 상단 라운드 코너 맞춤.
local headerArt = Instance.new("ImageLabel")
headerArt.Name = "HeaderArt"
headerArt.Position = UDim2.new(0, 0, 0, 0)
headerArt.Size = UDim2.new(1, 0, 0, 140)
headerArt.BackgroundTransparency = 1
headerArt.Image = "rbxassetid://72810938231561"
headerArt.ScaleType = Enum.ScaleType.Crop
headerArt.ZIndex = 0
headerArt.Parent = panel
Instance.new("UICorner", headerArt).CornerRadius = UDim.new(0, 18)

-- 하단 배너 (여름 비치 스트립). Decal 87091493959183 → LoadAsset resolve된 Image ID. 푸터 뒤(ZIndex 0) 밴드.
local footerArt = Instance.new("ImageLabel")
footerArt.Name = "FooterArt"
footerArt.AnchorPoint = Vector2.new(0, 1)
footerArt.Position = UDim2.new(0, 0, 1, 0)
footerArt.Size = UDim2.new(1, 0, 0, 110)
footerArt.BackgroundTransparency = 1
footerArt.Image = "rbxassetid://84627361423202"
footerArt.ScaleType = Enum.ScaleType.Crop
footerArt.ZIndex = 0
footerArt.Parent = panel
Instance.new("UICorner", footerArt).CornerRadius = UDim.new(0, 18)

-- 반응형 스케일 (중앙 패널형 — 작은 화면에서 전체 균일 축소)
Scaler.applyPanel(panel, { baseW = 900, baseH = 500, Mobile = { frac = 0.94, minScale = 0.4 }, PC = { frac = 0.92, minScale = 0.5 } })

-- ── 헤더 (BATTLE PASS + 시즌 + 닫기 X) ──
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundTransparency = 1
header.Parent = panel

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.5, 0)
title.Size = UDim2.new(0, 210, 0, 30)
title.BackgroundTransparency = 1
title.Font = Enum.Font.BuilderSansExtraBold
title.Text = "BATTLE PASS"
title.TextColor3 = TEXT_MAIN
title.TextXAlignment = Enum.TextXAlignment.Center
title.TextScaled = true
title.Parent = header
local titleStroke = Instance.new("UIStroke"); titleStroke.Color = Color3.fromRGB(10, 28, 52); titleStroke.Thickness = 2; titleStroke.Transparency = 0.15; titleStroke.Parent = title
local tc = Instance.new("UITextSizeConstraint"); tc.MaxTextSize = 24; tc.Parent = title

-- ── 시즌 / 남은 기간 배지 ──────────────────────────────────
-- ⚠️ 이전에는 "Season 1 · ends in 29d" 가 하드코딩이라 시즌이 실제로 끝나도
--    영원히 29d 로 표시됐다. R$499 상품을 파는 화면에서 마감을 오인시키면
--    "예고 없이 끝났다"는 배신감으로 직결되므로 SeasonConfig 로 실계산한다.
--    또한 작은 회색 글씨(13px)라 눈에 띄지 않아, 배지 + 강조색으로 시인성을 올린다.
local SeasonConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("SeasonConfig"))

local seasonBadge = Instance.new("Frame")
seasonBadge.Name = "SeasonBadge"
seasonBadge.AnchorPoint = Vector2.new(1, 0.5)
seasonBadge.Position = UDim2.new(1, -64, 0.5, 0)
seasonBadge.Size = UDim2.new(0, 190, 0, 34)
seasonBadge.BackgroundColor3 = Color3.fromRGB(12, 30, 56)
seasonBadge.BackgroundTransparency = 0.25
seasonBadge.BorderSizePixel = 0
seasonBadge.Parent = header
local sbCorner = Instance.new("UICorner"); sbCorner.CornerRadius = UDim.new(0, 8); sbCorner.Parent = seasonBadge
local sbStroke = Instance.new("UIStroke")
sbStroke.Color = Color3.fromRGB(255, 190, 80)
sbStroke.Thickness = 1.5
sbStroke.Transparency = 0.3
sbStroke.Parent = seasonBadge

local season = Instance.new("TextLabel")
season.Name = "SeasonText"
season.Size = UDim2.new(1, -12, 0.55, 0)
season.Position = UDim2.new(0, 6, 0, 1)
season.BackgroundTransparency = 1
season.Font = Enum.Font.BuilderSansBold
season.Text = "SEASON " .. SeasonConfig.SEASON_NUMBER
season.TextColor3 = Color3.fromRGB(255, 255, 255)
season.TextXAlignment = Enum.TextXAlignment.Right
season.TextScaled = true
season.Parent = seasonBadge
local ssc = Instance.new("UITextSizeConstraint"); ssc.MaxTextSize = 15; ssc.Parent = season

local seasonTimer = Instance.new("TextLabel")
seasonTimer.Name = "SeasonTimer"
seasonTimer.Size = UDim2.new(1, -12, 0.45, 0)
seasonTimer.Position = UDim2.new(0, 6, 0.53, 0)
seasonTimer.BackgroundTransparency = 1
seasonTimer.Font = Enum.Font.BuilderSansBold
seasonTimer.TextColor3 = Color3.fromRGB(255, 200, 90)
seasonTimer.TextXAlignment = Enum.TextXAlignment.Right
seasonTimer.TextScaled = true
seasonTimer.Parent = seasonBadge
local stc = Instance.new("UITextSizeConstraint"); stc.MaxTextSize = 14; stc.Parent = seasonTimer

-- 남은 기간 갱신: 30초마다. 3일 이하로 남으면 붉은색으로 경고.
local function refreshSeasonTimer()
	local left = SeasonConfig.secondsLeft()
	seasonTimer.Text = (left > 0) and ("Ends in " .. SeasonConfig.timeLeftText()) or "SEASON ENDED"
	if left <= 0 then
		seasonTimer.TextColor3 = Color3.fromRGB(255, 110, 110)
		sbStroke.Color = Color3.fromRGB(255, 110, 110)
	elseif left <= 3 * 86400 then
		seasonTimer.TextColor3 = Color3.fromRGB(255, 130, 110)   -- 마감 임박 경고
		sbStroke.Color = Color3.fromRGB(255, 130, 110)
	else
		seasonTimer.TextColor3 = Color3.fromRGB(255, 200, 90)
		sbStroke.Color = Color3.fromRGB(255, 190, 80)
	end
end
refreshSeasonTimer()
task.spawn(function()
	while seasonBadge.Parent do
		task.wait(30)
		refreshSeasonTimer()
	end
end)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(40, 40)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.BuilderSansExtraBold
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextScaled = true
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)
local ccc = Instance.new("UITextSizeConstraint"); ccc.MaxTextSize = 20; ccc.Parent = closeBtn

-- ── EXP 게이지 (Tier 배지 + 진행 바 + XP) ──
local expRow = Instance.new("Frame")
expRow.Name = "Exp"
expRow.Position = UDim2.new(0, 0, 0, 78)
expRow.Size = UDim2.new(1, 0, 0, 40)
expRow.BackgroundTransparency = 1
expRow.Parent = panel

local tierBadge = Instance.new("TextLabel")
tierBadge.Name = "TierBadge"
tierBadge.AnchorPoint = Vector2.new(0, 0.5)
tierBadge.Position = UDim2.new(0, 18, 0.5, 0)
tierBadge.Size = UDim2.fromOffset(70, 26)
tierBadge.BackgroundColor3 = BLUE
tierBadge.Font = Enum.Font.BuilderSansExtraBold
tierBadge.Text = "Tier 7"
tierBadge.TextColor3 = Color3.fromRGB(6, 18, 43)
tierBadge.TextScaled = true
tierBadge.Parent = expRow
Instance.new("UICorner", tierBadge).CornerRadius = UDim.new(0, 8)
local tbc = Instance.new("UITextSizeConstraint"); tbc.MaxTextSize = 14; tbc.Parent = tierBadge

local barBg = Instance.new("Frame")
barBg.Name = "Bar"
barBg.AnchorPoint = Vector2.new(0, 0.5)
barBg.Position = UDim2.new(0, 98, 0.5, 0)
barBg.Size = UDim2.new(1, -98 - 124, 0, 14)
barBg.BackgroundColor3 = Color3.fromRGB(16, 54, 88)
barBg.BorderSizePixel = 0
barBg.Parent = expRow
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0.64, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 154, 61)
barFill.BorderSizePixel = 0
barFill.Parent = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 209, 102), Color3.fromRGB(255, 122, 66))   -- sun -> coral
fillGrad.Rotation = 90
fillGrad.Parent = barFill

local xpLbl = Instance.new("TextLabel")
xpLbl.Name = "XP"
xpLbl.AnchorPoint = Vector2.new(1, 0.5)
xpLbl.Position = UDim2.new(1, Scaler.isMobile() and -18 or -38, 0.5, -3)
xpLbl.Size = UDim2.fromOffset(96, 20)
xpLbl.BackgroundTransparency = 1
xpLbl.Font = Enum.Font.BuilderSansExtraBold
xpLbl.Text = "320 / 500 XP"
xpLbl.TextColor3 = TEXT_SUB
xpLbl.TextXAlignment = Enum.TextXAlignment.Right
xpLbl.TextScaled = true
xpLbl.Parent = expRow
local xpStroke = Instance.new("UIStroke"); xpStroke.Color = Color3.fromRGB(10, 28, 52); xpStroke.Thickness = 1.5; xpStroke.Transparency = 0.1; xpStroke.Parent = xpLbl
local xpc = Instance.new("UITextSizeConstraint"); xpc.MaxTextSize = 12; xpc.Parent = xpLbl

-- ── 바디 (티어 사다리는 슬라이스 2에서 채움) ──
local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, 118)
body.Size = UDim2.new(1, 0, 1, -118 - 54)
body.BackgroundTransparency = 1
body.Parent = panel

-- (티어 사다리는 아래 사다리 섹션에서 body 에 추가)

-- ── 푸터 (Skip Tiers + Claim All) ──
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, 0)
footer.Size = UDim2.new(1, 0, 0, 54)
footer.BackgroundTransparency = 1
footer.Parent = panel

local skipBtn = Instance.new("TextButton")
skipBtn.Name = "SkipTiers"
skipBtn.AnchorPoint = Vector2.new(0, 0.5)
skipBtn.Position = UDim2.new(0, 18, 0.5, 0)
skipBtn.Size = UDim2.fromOffset(130, 40)
skipBtn.BackgroundColor3 = NAVY_CARD
skipBtn.Font = Enum.Font.BuilderSansExtraBold
skipBtn.Text = "Skip Tiers"
skipBtn.TextColor3 = TEXT_MAIN
skipBtn.TextScaled = true
skipBtn.Parent = footer
Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 10)
local skc = Instance.new("UITextSizeConstraint"); skc.MaxTextSize = 15; skc.Parent = skipBtn

local claimAll = Instance.new("TextButton")
claimAll.Name = "ClaimAll"
claimAll.AnchorPoint = Vector2.new(1, 0.5)
claimAll.Position = UDim2.new(1, -18, 0.5, 0)
claimAll.Size = UDim2.fromOffset(140, 42)
claimAll.BackgroundColor3 = GREEN
claimAll.Font = Enum.Font.BuilderSansExtraBold
claimAll.Text = "Claim All"
claimAll.TextColor3 = Color3.fromRGB(4, 20, 10)
claimAll.TextScaled = true
claimAll.Parent = footer
Instance.new("UICorner", claimAll).CornerRadius = UDim.new(0, 12)
local caGrad = Instance.new("UIGradient")
caGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 206, 206))
caGrad.Rotation = 90
caGrad.Parent = claimAll
local cac = Instance.new("UITextSizeConstraint"); cac.MaxTextSize = 16; cac.Parent = claimAll

-- ── 토스트 (더미 클릭 안내) ──
-- [BP-FEEDBACK] 보상 내역을 사람이 읽는 문구로.
--   ⚠️ box 보상은 서버(grantReward)가 이미 상자 컷신을 띄운다. 중복 연출을 피해
--      호출부에서 box 일 때는 토스트를 생략한다.
local function rewardText(r)
	if type(r) ~= "table" then return "Claimed!" end
	if r.coins then return "+" .. r.coins .. " Coins" end
	if r.effect then
		local n = tostring(r.effect):gsub("_", " ")
		return "Unlocked: " .. n
	end
	if r.skin then return "Skin unlocked!" end
	return "Claimed!"
end

local function toast(msg)
	local old = panel:FindFirstChild("_Toast")
	if old then old:Destroy() end
	local t = Instance.new("TextLabel")
	t.Name = "_Toast"
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 1, -60)
	t.Size = UDim2.fromOffset(220, 40)
	t.BackgroundColor3 = Color3.fromRGB(20, 64, 104)
	t.Text = msg
	t.Font = Enum.Font.BuilderSansMedium
	t.TextColor3 = TEXT_MAIN
	t.TextSize = 14
	t.ZIndex = 50
	t.Parent = panel
	Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)
	task.delay(1.6, function() if t and t.Parent then t:Destroy() end end)
end

-- ══ 티어 사다리 (더미 30) ══════════════════════════════════════
-- 실 서버 데이터 (BattlePassSystem이 BP_XP / BP_Tier 속성으로 미러링)
local XP_PER_TIER = 800
local function getXP()   return player:GetAttribute("BP_XP") or 0 end
local function getTier() return math.clamp(player:GetAttribute("BP_Tier") or 1, 1, 30) end   -- 30 = #TIERS (TIERS는 아래 정의라 #TIERS 못 씀)
local hasPremium = player:GetAttribute("BP_HasPremium") == true   -- slice 4: premium purchase
-- [BP-FEEDBACK] 수령 연출. 퀘스트·출석·상자와 같은 모듈을 재사용한다(사운드 포함).
local ConfettiEffect = require(ReplicatedStorage:WaitForChild("ConfettiEffect"))

local claimFn = ReplicatedStorage:WaitForChild("BattlePassClaim")   -- 서버 수령 (state/claim/claimAll)
local MarketplaceService = game:GetService("MarketplaceService")
local PREMIUM_PRODUCT_ID = 3609062110   -- dev product: Summer S1 premium (must match BattlePassSystem)

-- Season reward layout (Summer, 30 tiers): coin ramp + seasonal skin milestones.
local TIERS = {
	{ free = {ic="🪙", v="150", coins=true, prev="coin"}, prem = {ic="🪙", v="300", coins=true, prev="coin"} },   -- T1
	{ free = {ic="🪙", v="150", coins=true, prev="coin"}, prem = {ic="👑", v="Crown", prev={vp="CrownPreviews",key="Cyan"}} },   -- T2
	{ free = {ic="🍉", v="Trail", prev={trail="trail_watermelon"}},           prem = {ic="🪙", v="300", coins=true, prev="coin"} },   -- T3
	{ free = {ic="🪙", v="200", coins=true, prev="coin"}, prem = {ic="🌈", v="Rainbow", prev={img="rbxassetid://107296032420423"}} },           -- T4
	{ free = {ic="🪙", v="200", coins=true, prev="coin"}, prem = {ic="🪙", v="350", coins=true, prev="coin"} },   -- T5
	{ free = {ic="🪙", v="250", coins=true, prev="coin"}, prem = {ic="🎭", v="Emote", prev={img="rbxassetid://86886948456897"}} },   -- T6
	{ free = {ic="📦", v="Box", prev={vp="RareChestPreview"}}, prem = {ic="🪙", v="350", coins=true, prev="coin"} },   -- T7
	{ free = {ic="🪙", v="250", coins=true, prev="coin"}, prem = {ic="🪙", v="400", coins=true, prev="coin"} },   -- T8
	{ free = {ic="🪙", v="300", coins=true, prev="coin"}, prem = {ic="🪙", v="400", coins=true, prev="coin"} },   -- T9
	{ free = {ic="🏄", v="Summer", prev={vp="SkinPreviews",key="SummerNoob"}}, prem = {ic="👑", v="Crown", prev={vp="CrownPreviews",key="Emerald"}} },   -- T10 milestone
	{ free = {ic="🪙", v="300", coins=true, prev="coin"}, prem = {ic="🪙", v="450", coins=true, prev="coin"} },   -- T11
	{ free = {ic="🪙", v="350", coins=true, prev="coin"}, prem = {ic="🎭", v="Emote", prev={img="rbxassetid://81178726118141"}} },   -- T12
	{ free = {ic="🍉", v="Dash", prev={dash="dash_watermelon"}},            prem = {ic="🪙", v="450", coins=true, prev="coin"} },   -- T13
	{ free = {ic="🪙", v="350", coins=true, prev="coin"}, prem = {ic="📦", v="Box+", prev={vp="RareChestPreview"}} },   -- T14
	{ free = {ic="🪙", v="400", coins=true, prev="coin"}, prem = {ic="🪙", v="500", coins=true, prev="coin"} },   -- T15
	{ free = {ic="💧", v="Water Kill", prev={img="rbxassetid://107520640685638", scale=1.5}},      prem = {ic="🪙", v="500", coins=true, prev="coin"} },   -- T16
	{ free = {ic="🪙", v="400", coins=true, prev="coin"}, prem = {ic="🪙", v="550", coins=true, prev="coin"} },   -- T17
	{ free = {ic="🪙", v="450", coins=true, prev="coin"}, prem = {ic="🪙", v="550", coins=true, prev="coin"} },   -- T18
	{ free = {ic="🪙", v="450", coins=true, prev="coin"}, prem = {ic="🪙", v="600", coins=true, prev="coin"} },   -- T19
	{ free = {ic="🥥", v="Coconut", prev={vp="SkinPreviews",key="Coconut"}}, prem = {ic="🍉", v="Melon", prev={vp="SkinPreviews",key="WatermelonFist"}} },   -- T20 milestone
	{ free = {ic="🪙", v="500", coins=true, prev="coin"}, prem = {ic="🪙", v="600", coins=true, prev="coin"} },   -- T21
	{ free = {ic="🪙", v="500", coins=true, prev="coin"}, prem = {ic="🎭", v="Emote", prev={img="rbxassetid://112844986822281"}} },   -- T22
	{ free = {ic="🪙", v="550", coins=true, prev="coin"}, prem = {ic="🪙", v="650", coins=true, prev="coin"} },   -- T23
	{ free = {ic="🏐", v="Ball", prev={vp="SkinPreviews",key="BeachBall"}}, prem = {ic="🪙", v="650", coins=true, prev="coin"} },   -- T24
	{ free = {ic="🪙", v="550", coins=true, prev="coin"}, prem = {ic="🪙", v="700", coins=true, prev="coin"} },   -- T25
	{ free = {ic="🪙", v="600", coins=true, prev="coin"}, prem = {ic="🪙", v="700", coins=true, prev="coin"} },   -- T26
	{ free = {ic="📦", v="Box", prev={vp="RareChestPreview"}}, prem = {ic="🪙", v="750", coins=true, prev="coin"} },   -- T27
	{ free = {ic="🪙", v="600", coins=true, prev="coin"}, prem = {ic="📦", v="Box+", prev={vp="RareChestPreview"}} },   -- T28
	{ free = {ic="🪙", v="600", coins=true, prev="coin"}, prem = {ic="🪙", v="800", coins=true, prev="coin"} },   -- T29
	{ free = {ic="🌴", v="Palm", prev={vp="SkinPreviews",key="PalmTree"}}, prem = {ic="🏊", v="Noodle", prev={vp="SkinPreviews",key="PoolNoodle"}} },   -- T30 grand
}

local claimedFree = {}
local claimedPrem = {}

-- 서버에서 현재 상태(도달 티어 / 수령 여부 / 프리미엄) 받아 로컬 캐시에 반영
local function fetchState()
	local ok, st = pcall(function() return claimFn:InvokeServer("state") end)
	if ok and type(st) == "table" then
		claimedFree = st.claimedFree or {}
		claimedPrem = st.claimedPrem or {}
		hasPremium = st.hasPremium == true
	end
end

local COL_W, TILE, NODE_H = 114, 104, 34
local COL_H = TILE + NODE_H + TILE
local TOP = 34

-- 타일 스크림: 여름 그라디언트 위 반투명 어두운 밴드 → 네이비 타일이 배경에 안 묻힘 (헤더 sky / 푸터 sand는 노출)
local gridScrim = Instance.new("Frame")
gridScrim.Name = "GridScrim"
gridScrim.Position = UDim2.new(0, 10, 0, TOP - 8)
gridScrim.Size = UDim2.new(1, -20, 0, COL_H + 16)
gridScrim.BackgroundColor3 = Color3.fromRGB(6, 20, 40)
gridScrim.BackgroundTransparency = 0.4
gridScrim.BorderSizePixel = 0
gridScrim.ZIndex = 0
gridScrim.Parent = body
Instance.new("UICorner", gridScrim).CornerRadius = UDim.new(0, 14)

-- ── 좌측 사이드바 (Free/Premium 라벨 + Unlock) ──
local side = Instance.new("Frame")
side.Name = "Sidebar"
side.Position = UDim2.new(0, 16, 0, TOP)
side.Size = UDim2.fromOffset(104, COL_H + 46)
side.BackgroundTransparency = 1
side.Parent = body

local function trackLabel(text, y, txtCol, tint)
	local l = Instance.new("TextLabel")
	l.Position = UDim2.new(0, 0, 0, y)
	l.Size = UDim2.fromOffset(104, TILE)
	l.BackgroundColor3 = tint
	l.BackgroundTransparency = 0.12
	l.Font = Enum.Font.BuilderSansExtraBold
	l.Text = text
	l.TextColor3 = Color3.fromRGB(8, 40, 66)
	l.TextScaled = true
	l.Parent = side
	Instance.new("UICorner", l).CornerRadius = UDim.new(0, 10)
	local ls = Instance.new("UIStroke"); ls.Color = Color3.fromRGB(255, 255, 255); ls.Transparency = 0.55; ls.Thickness = 1; ls.Parent = l
	local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = l
end
trackLabel("Free", 0, GREEN, GREEN)
trackLabel("Premium", TILE + NODE_H, GOLD, GOLD)

local unlockBtn = Instance.new("TextButton")
unlockBtn.Position = UDim2.new(0, 0, 0, COL_H + 8)
unlockBtn.Size = UDim2.fromOffset(104, 38)
unlockBtn.BackgroundColor3 = GOLD
unlockBtn.Font = Enum.Font.BuilderSansExtraBold
unlockBtn.Text = "Unlock  R$499"
unlockBtn.TextColor3 = Color3.fromRGB(70, 46, 6)
unlockBtn.TextScaled = true
unlockBtn.Parent = side
Instance.new("UICorner", unlockBtn).CornerRadius = UDim.new(0, 10)
local ulGrad = Instance.new("UIGradient")
ulGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 206, 206))
ulGrad.Rotation = 90
ulGrad.Parent = unlockBtn
local uc = Instance.new("UITextSizeConstraint"); uc.MaxTextSize = 13; uc.Parent = unlockBtn
unlockBtn.MouseButton1Click:Connect(function()
	if PREMIUM_PRODUCT_ID ~= 0 then
		MarketplaceService:PromptProductPurchase(player, PREMIUM_PRODUCT_ID)
	else
		toast("Coming soon")   -- product ID not set yet
	end
end)

-- ── 사다리 (가로 스크롤: 컬럼 고정 픽셀 + AutomaticCanvasSize.X → 폭주 안전) ──
local ladder = Instance.new("ScrollingFrame")
ladder.Name = "Ladder"
ladder.Position = UDim2.new(0, 130, 0, TOP)
ladder.Size = UDim2.new(1, -130 - 16, 0, COL_H + 12)
ladder.BackgroundTransparency = 1
ladder.BorderSizePixel = 0
ladder.ScrollingDirection = Enum.ScrollingDirection.X
ladder.ScrollBarThickness = 6
ladder.ScrollBarImageColor3 = Color3.fromRGB(90, 110, 150)
ladder.CanvasSize = UDim2.new(0, 0, 0, 0)
ladder.AutomaticCanvasSize = Enum.AutomaticSize.X
ladder.Parent = body
local llist = Instance.new("UIListLayout")
llist.FillDirection = Enum.FillDirection.Horizontal
llist.SortOrder = Enum.SortOrder.LayoutOrder
llist.Padding = UDim.new(0, 8)
llist.VerticalAlignment = Enum.VerticalAlignment.Top
llist.Parent = ladder

-- 클레임 ✓ 표시 (로컬)
local function markClaimed(tile)
	if tile:FindFirstChild("Chk") then return end
	tile.BackgroundTransparency = 0.35
	for _, l in ipairs(tile:GetChildren()) do
		if l:IsA("TextLabel") then l.TextTransparency = 0.5 end
	end
	local oldStroke = tile:FindFirstChildWhichIsA("UIStroke"); if oldStroke then oldStroke:Destroy() end
	local chk = Instance.new("TextLabel")
	chk.Name = "Chk"; chk.AnchorPoint = Vector2.new(1, 0); chk.Position = UDim2.new(1, -4, 0, 4)
	chk.Size = UDim2.fromOffset(17, 17); chk.BackgroundColor3 = GREEN; chk.Text = "✓"
	chk.Font = Enum.Font.BuilderSansExtraBold; chk.TextColor3 = Color3.fromRGB(4, 20, 10); chk.TextScaled = true; chk.ZIndex = 3
	chk.Parent = tile
	Instance.new("UICorner", chk).CornerRadius = UDim.new(1, 0)
end

-- 타일 아이콘 비주얼: reward.prev = "coin"(코인이미지) / {img=..}(이미지) / {vp=폴더,key=..}(3D뷰포트) / 없으면 이모지
local COIN_IMG = "rbxassetid://109002720549611"

-- 배틀패스 티어 3D 썸네일 카메라 튜닝 (인벤 P키 PreviewTunerClient로 잡은 [TUNE-OUT] 값을 여기 박음).
-- key = prev.key(있으면) 또는 prev.vp. 테이블에 없으면 BP_CAM_DEFAULT 사용.
local BP_CAM = {
	-- 스샷 [TUNE]값 반영. 스킨=prev.key / 크라운은 일괄 "Crown".
	Crown          = { dist = 1.00, dir = Vector3.new(0.40, 0.60, 1.00), target = Vector3.new(0.00, 0.00, 0.00) },  -- Cyan로 튜닝, 전 크라운 공유
	PalmTree       = { dist = 1.00, dir = Vector3.new(0.20, 0.30, 1.00), target = Vector3.new(0.00, 0.05, -0.05) },
	WatermelonFist = { dist = 0.40, dir = Vector3.new(-0.20, 2.90, 1.00), target = Vector3.new(0.10, 0.15, -0.15) },
	RareChestPreview = { dist = 1.20, dir = Vector3.new(-0.40, 0.30, -1.00), target = Vector3.new(0.00, 0.00, 0.00) },
	SummerNoob       = { dist = 0.70, dir = Vector3.new(-0.10, 0.00, -1.00), target = Vector3.new(0.00, 0.05, -0.25) },
	Coconut          = { dist = 1.00, dir = Vector3.new(0.40, 0.30, 1.00), target = Vector3.new(0.00, 0.00, 0.00) },
	BeachBall        = { dist = 1.10, dir = Vector3.new(0.40, 0.30, 1.00), target = Vector3.new(0.00, 0.00, 0.00) },
	PoolNoodle       = { dist = 0.80, dir = Vector3.new(0.40, -0.50, 1.00), target = Vector3.new(0.00, 0.00, 0.00) },
}
local BP_CAM_DEFAULT = { dist = 1.90, dir = Vector3.new(0.4, 0.3, 1), target = Vector3.new(0, 0, 0) }

local function iconVisual(tile, reward)
	local prev = reward.prev
	local imgId
	if prev == "coin" then imgId = COIN_IMG
	elseif type(prev) == "table" and prev.img and prev.img ~= "" then imgId = prev.img end

	if imgId then
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5); img.Position = UDim2.fromScale(0.5, 0.40)
		local sc = (type(prev) == "table" and prev.scale) or 0.68   -- 리워드별 크기 오버라이드
		img.Size = UDim2.fromScale(sc, sc); img.BackgroundTransparency = 1
		img.Image = imgId; img.ScaleType = Enum.ScaleType.Fit; img.Parent = tile
		return img
	elseif type(prev) == "table" and prev.vp then
		local root = ReplicatedStorage:FindFirstChild(prev.vp)
		local model = prev.key and root and root:FindFirstChild(prev.key) or root
		if model and (model:IsA("Model") or model:IsA("BasePart")) then
			local vp = Instance.new("ViewportFrame")
			vp.Name = "_ItemVP"   -- PreviewTunerClient(P키)가 잡는 이름
			vp.AnchorPoint = Vector2.new(0.5, 0.5); vp.Position = UDim2.fromScale(0.5, 0.40)
			vp.Size = UDim2.fromScale(0.84, 0.84); vp.BackgroundTransparency = 1; vp.Parent = tile
			local clone = model:Clone(); clone.Parent = vp
			local cam = Instance.new("Camera"); cam.Parent = vp; vp.CurrentCamera = cam
			-- 카메라 튜닝값: BP_CAM[key] (없으면 기본). 튜너와 동일 공식(dir 비정규화 + target pan).
			local key = (prev.vp == "CrownPreviews") and "Crown" or (prev.key or prev.vp)   -- 크라운은 일괄(Crown 키 공유)
			local cfg = BP_CAM[key] or BP_CAM_DEFAULT
			local distMul, dir, target = cfg.dist, cfg.dir, cfg.target
			local cf, size
			if clone:IsA("Model") then
				local ok, c, s = pcall(function() return clone:GetBoundingBox() end)
				if ok then cf, size = c, s end
			elseif clone:IsA("BasePart") then
				cf, size = clone.CFrame, clone.Size   -- 단일 Part(BeachBall MeshPart 등)는 GetBoundingBox 없음
			end
			if cf then
				local maxDim = math.max(size.X, size.Y, size.Z, 0.1)
				local tgt = cf.Position + target * maxDim
				cam.CFrame = CFrame.new(tgt + dir * (maxDim * distMul), tgt)
			end
			-- 튜너 연동: 클릭 시 이 값에서 시작 + [TUNE-OUT] 라벨에 key 표시
			vp:SetAttribute("PreviewId", key)
			vp:SetAttribute("_tuneDist", distMul)
			vp:SetAttribute("_tuneDir", dir)
			vp:SetAttribute("_tuneTarget", target)
			return vp
		end
	elseif type(prev) == "table" and prev.trail and _G.LP_makeTrailRibbon then
		if _G.LP_makeTrailRibbon(tile, prev.trail) then
			local rib = tile:FindFirstChild("_TrailRibbon")
			if rib then rib.ZIndex = 3 end   -- 리본은 ZIndex 0 생성(인벤용) → 타일 위로
			return rib
		end
	elseif type(prev) == "table" and prev.dash and _G.LP_makeDashIcon then
		if _G.LP_makeDashIcon(tile, prev.dash) then
			local di = tile:FindFirstChild("_DashIcon")
			if di then di.ZIndex = 3 end
			return di
		end
	end
	-- fallback: emoji
	local ic = Instance.new("TextLabel")
	ic.AnchorPoint = Vector2.new(0.5, 0.5); ic.Position = UDim2.fromScale(0.5, 0.40)
	ic.Size = UDim2.fromScale(0.70, 0.70); ic.BackgroundTransparency = 1
	ic.Font = Enum.Font.BuilderSansExtraBold; ic.Text = reward.ic; ic.TextScaled = true; ic.Parent = tile
	return ic
end

-- 타일 생성
local function makeTile(parent, reward, y, state)
	local tile = Instance.new("TextButton")
	tile.AnchorPoint = Vector2.new(0.5, 0)
	tile.Position = UDim2.new(0.5, 0, 0, y)
	tile.Size = UDim2.fromOffset(TILE, TILE)
	tile.AutoButtonColor = false
	tile.Text = ""
	tile.BackgroundColor3 = (state == "locked") and Color3.fromRGB(22, 29, 48) or NAVY_CARD
	tile.Parent = parent
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 14)
	if state == "current" then
		local st = Instance.new("UIStroke"); st.Color = BLUE; st.Thickness = 2; st.Parent = tile
	end
	local ic = iconVisual(tile, reward)
	local v = Instance.new("TextLabel")
	v.AnchorPoint = Vector2.new(0.5, 1)
	v.Position = UDim2.new(0.5, 0, 1, -7)
	v.Size = UDim2.new(1, -8, 0, 15)
	v.BackgroundTransparency = 1
	v.Font = Enum.Font.BuilderSansExtraBold
	v.Text = reward.v
	v.TextColor3 = reward.coins and GOLD or TEXT_MAIN
	v.TextScaled = true
	v.Parent = tile
	local vc = Instance.new("UITextSizeConstraint"); vc.MaxTextSize = 16; vc.Parent = v
	if state == "claimed" then
		markClaimed(tile)
	elseif state == "locked" then
		if ic:IsA("TextLabel") then ic.TextTransparency = 0.45
		elseif ic:IsA("ImageLabel") then ic.ImageTransparency = 0.45 end
	end
	return tile
end

-- 노드 (번호 + 진행선)
local function makeNode(parent, num, nodeState, lineDone)
	local node = Instance.new("Frame")
	node.Position = UDim2.new(0, 0, 0, TILE)
	node.Size = UDim2.new(1, 0, 0, NODE_H)
	node.BackgroundTransparency = 1
	node.Parent = parent
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(0.5, 0, 0.5, 0)
	line.Size = UDim2.new(1, 8, 0, 4)
	line.BackgroundColor3 = lineDone and GREEN or Color3.fromRGB(43, 54, 84)
	line.BorderSizePixel = 0
	line.Parent = node
	local nn = Instance.new("TextLabel")
	nn.AnchorPoint = Vector2.new(0.5, 0.5)
	nn.Position = UDim2.new(0.5, 0, 0.5, 0)
	nn.Size = UDim2.fromOffset(24, 24)
	nn.BackgroundColor3 = (nodeState == "done") and GREEN or ((nodeState == "now") and BLUE or Color3.fromRGB(43, 54, 84))
	nn.Text = tostring(num)
	nn.Font = Enum.Font.BuilderSansExtraBold
	nn.TextColor3 = (nodeState == "locked") and Color3.fromRGB(205, 214, 240) or Color3.fromRGB(6, 18, 43)
	nn.TextScaled = true
	nn.ZIndex = 2
	nn.Parent = node
	Instance.new("UICorner", nn).CornerRadius = UDim.new(1, 0)
	local nc = Instance.new("UITextSizeConstraint"); nc.MaxTextSize = 13; nc.Parent = nn
end

-- 빌드 (실 서버 데이터: BP_XP / BP_Tier)
local claimables = {}   -- Claim All 용 (현재 클레임 가능한 free 타일)

-- 진행 바 / 티어 배지 / XP 라벨을 현재 XP로 갱신
local function refreshProgress()
	local xp = getXP()
	local tier = getTier()
	local inTier = (tier >= #TIERS) and XP_PER_TIER or (xp % XP_PER_TIER)
	-- 만렙 표기를 진입점(HudButtonClient)과 통일: "Tier 30" 대신 "MAX"
	tierBadge.Text = (tier >= #TIERS) and "MAX" or ("Tier " .. tier)
	barFill.Size = UDim2.new(math.clamp(inTier / XP_PER_TIER, 0, 1), 0, 1, 0)
	xpLbl.Text = (tier >= #TIERS) and "COMPLETE" or (inTier .. " / " .. XP_PER_TIER .. " XP")
end

-- 티어 사다리를 현재 티어 기준으로 (재)빌드
local function buildLadder()
	for _, c in ipairs(ladder:GetChildren()) do
		if c:IsA("Frame") and c.Name:match("^Tier%d+$") then c:Destroy() end
	end
	table.clear(claimables)
	local CURRENT_TIER = getTier()

	for i, t in ipairs(TIERS) do
		local col = Instance.new("Frame")
		col.Name = "Tier" .. i
		col.Size = UDim2.fromOffset(COL_W, COL_H)
		col.BackgroundTransparency = 1
		col.LayoutOrder = i
		col.Parent = ladder

		-- free tile: claimed(server) / current(reached + unclaimed) / locked
		local fstate
		if claimedFree[i] then fstate = "claimed"
		elseif i <= CURRENT_TIER then fstate = "current"
		else fstate = "locked" end
		local ftile = makeTile(col, t.free, 0, fstate)
		if fstate == "current" then
			claimables[#claimables + 1] = { tile = ftile, tier = i, track = "free" }
			ftile.MouseButton1Click:Connect(function()
				if _G.previewTunerActive then return end   -- 튜닝 중 클릭은 클레임 X
				if claimedFree[i] then return end
				local res = claimFn:InvokeServer("claim", i, "free")
				if res and res.ok then
					claimedFree[i] = true
					markClaimed(ftile)
					-- [BP-FEEDBACK] 무엇을 받았는지 알린다.
					--   ⚠️ box 보상은 서버(grantReward)가 이미 상자 컷신을 띄운다 → 중복 연출 방지.
					if not (res and res.box) then
						toast(rewardText(res and res.reward))
						ConfettiEffect.play()
					end
					if _G.RefreshBattlePassBadge then pcall(_G.RefreshBattlePassBadge) end
				else
					toast(res and res.msg or "Failed")
				end
			end)
		else
			ftile.MouseButton1Click:Connect(function()
				toast(fstate == "locked" and "Locked" or "Already claimed")
			end)
		end

		local nodeState = (i < CURRENT_TIER) and "done" or ((i == CURRENT_TIER) and "now" or "locked")
		makeNode(col, i, nodeState, i <= CURRENT_TIER)   -- lineDone: reached tier -> green line

		-- premium tile: needs premium; then claimed / current / locked
		local pstate
		if not hasPremium then pstate = "locked"
		elseif claimedPrem[i] then pstate = "claimed"
		elseif i <= CURRENT_TIER then pstate = "current"
		else pstate = "locked" end
		local ptile = makeTile(col, t.prem, TILE + NODE_H, pstate)
		if not hasPremium then ptile.BackgroundTransparency = 0.55 end
		if pstate == "current" then
			ptile.MouseButton1Click:Connect(function()
				if _G.previewTunerActive then return end   -- 튜닝 중 클릭은 클레임 X
				if claimedPrem[i] then return end
				local res = claimFn:InvokeServer("claim", i, "prem")
				if res and res.ok then
					claimedPrem[i] = true
					markClaimed(ptile)
					if not (res and res.box) then
						toast(rewardText(res and res.reward))
						ConfettiEffect.play()
					end
					if _G.RefreshBattlePassBadge then pcall(_G.RefreshBattlePassBadge) end
				else
					toast(res and res.msg or "Failed")
				end
			end)
		else
			ptile.MouseButton1Click:Connect(function()
				toast(hasPremium and "Already claimed" or "Premium required")
			end)
		end
	end
end

-- 열 때 / XP 변할 때 전체 갱신
local function refresh()
	fetchState()
	buildLadder()
	refreshProgress()
end

local _bpOk, _bpErr = pcall(refresh)   -- 초기 빌드 (에러나도 스크립트는 계속 → _G.openBattlePass 정의 보장)
if not _bpOk then warn("[BattlePass] init refresh failed:", _bpErr) end

-- Claim All (더미)
local function claimAllTiers()
	local res = claimFn:InvokeServer("claimAll")
	local n = 0
	if res and res.ok and res.claimed then
		for _, c in ipairs(res.claimed) do
			if c.track == "free" then claimedFree[c.tier] = true else claimedPrem[c.tier] = true end
			n = n + 1
		end
	end
	buildLadder()   -- reflect claimed state
	toast(n > 0 and ("Claimed " .. n .. "!") or "Nothing to claim")
	-- [BP-FEEDBACK] 일괄 수령도 연출 + 배지 갱신
	if n > 0 then ConfettiEffect.play() end
	if _G.RefreshBattlePassBadge then pcall(_G.RefreshBattlePassBadge) end
end

-- ── 토글 ──
local function setOpen(open)
	gui.Enabled = open
	if open then refresh() end   -- 열 때 실 데이터로 갱신
end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
dim.MouseButton1Click:Connect(function() setOpen(false) end)
skipBtn.MouseButton1Click:Connect(function() toast("Coming soon") end)
claimAll.MouseButton1Click:Connect(function() claimAllTiers() end)

-- 외부에서 열기용 전역 + 임시 /pass 진입 (RobuxStore와 동일 패턴)
_G.openBattlePass = function() setOpen(true) end
player:GetAttributeChangedSignal("_OpenBattlePass"):Connect(function()
	setOpen(true)
end)

-- XP/티어 변경 시 패널이 열려 있으면 실시간 갱신
player:GetAttributeChangedSignal("BP_XP"):Connect(function()
	if gui.Enabled then refresh() end
end)
player:GetAttributeChangedSignal("BP_Tier"):Connect(function()
	if gui.Enabled then refresh() end
end)
player:GetAttributeChangedSignal("BP_HasPremium"):Connect(function()
	if gui.Enabled then refresh() end   -- premium purchased -> re-render premium track
end)

print("✅ BattlePassClient 준비! (껍데기 + /pass 진입)")
