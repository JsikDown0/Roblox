-- RobuxStoreClient — Robux/패키지 상점 (코인 상점과 분리)
-- 1a: 껍데기 + 진입점(코인 "+" 버튼) + 토글. 섹션 콘텐츠(게임패스/코인팩)는 이후 슬라이스.
-- 자기완결형: 롤백하려면 이 스크립트만 삭제하면 됨.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PromoCarousel = require(ReplicatedStorage:WaitForChild("PromoCarousel"))
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))

-- 색 (ShopGui ITEM COLOR 다크 네이비 계열)
local NAVY_BG    = Color3.fromRGB(18, 24, 40)
local TEXT_MAIN  = Color3.fromRGB(235, 240, 255)

-- ── 경로 대기 헬퍼 ──
local function waitPath(root, ...)
	local cur = root
	for _, name in ipairs({...}) do
		cur = cur and cur:WaitForChild(name, 15)
	end
	return cur
end

-- ── ScreenGui ──
local gui = Instance.new("ScreenGui")
gui.Name = "RobuxStoreGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = playerGui

-- 딤 배경 (바깥 탭 시 닫힘)
local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.Text = ""
dim.AutoButtonColor = false
dim.Parent = gui

-- ── 패널 (모바일 우선: Scale + 데스크톱 폭 캡) ──
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true                       -- 패널 클릭이 딤으로 새는 것 차단
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.9, 0.85)
panel.BackgroundColor3 = NAVY_BG
panel.BorderSizePixel = 0
panel.Parent = gui

local sizeCon = Instance.new("UISizeConstraint")
sizeCon.MaxSize = Vector2.new(480, 900)   -- 데스크톱에서 폰 폭 유지
sizeCon.MinSize = Vector2.new(260, 380)
sizeCon.Parent = panel

-- 모바일: 패널 축소 (짧은 가로 화면에서 꽉 차지 않게)
if Scaler.isMobile() then
	panel.Size = UDim2.fromScale(0.7, 0.92)
	sizeCon.MaxSize = Vector2.new(370, 760)
	sizeCon.MinSize = Vector2.new(240, 200)   -- 짧은 화면에서 min 높이(380)가 화면을 초과시키던 것 방지
end

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 16)
panelCorner.Parent = panel

-- ── 헤더 (STORE + 닫기 X) ──
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 56)
header.BackgroundTransparency = 1
header.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.new(0, 18, 0.5, 0)
title.Size = UDim2.new(1, -72, 1, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.BuilderSansExtraBold
title.Text = "STORE"
title.TextColor3 = TEXT_MAIN
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextScaled = true
title.Parent = header
local titleCon = Instance.new("UITextSizeConstraint")
titleCon.MaxTextSize = 26
titleCon.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(44, 44)  -- 모바일 터치타깃 44+
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.BuilderSansExtraBold
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextScaled = true
closeBtn.Parent = header
local ccorner = Instance.new("UICorner")
ccorner.CornerRadius = UDim.new(0, 10)
ccorner.Parent = closeBtn
local closeCon = Instance.new("UITextSizeConstraint")
closeCon.MaxTextSize = 22
closeCon.Parent = closeBtn

-- ── 바디 (빈 세로 스크롤 — 섹션은 1b에서) ──
local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, 56)
body.Size = UDim2.new(1, 0, 1, -56)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 6
body.ScrollBarImageColor3 = Color3.fromRGB(90, 110, 150)
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.None  -- 수동 캔버스(refreshCanvas) — 열자마자 스크롤바
body.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 14)
pad.Parent = body

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 12)
list.Parent = body

-- ── 공통 색/헬퍼 ──
local MarketplaceService = game:GetService("MarketplaceService")

local NAVY_CARD = Color3.fromRGB(26, 34, 54)
local TEXT_SUB  = Color3.fromRGB(150, 160, 185)
local GREEN     = Color3.fromRGB(46, 178, 80)
local GREY_BTN  = Color3.fromRGB(70, 80, 100)

-- 토스트 (더미 클릭 안내 등)
local function toast(msg)
	local old = panel:FindFirstChild("_Toast")
	if old then old:Destroy() end
	local t = Instance.new("TextLabel")
	t.Name = "_Toast"
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 1, -14)
	t.Size = UDim2.fromOffset(220, 40)
	t.BackgroundColor3 = Color3.fromRGB(40, 48, 70)
	t.Text = msg
	t.Font = Enum.Font.BuilderSansMedium
	t.TextColor3 = TEXT_MAIN
	t.TextSize = 14
	t.ZIndex = 50
	t.Parent = panel
	Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)
	task.delay(1.6, function() if t and t.Parent then t:Destroy() end end)
end

local function sectionHeader(text, order)
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 22)
	h.BackgroundTransparency = 1
	h.Font = Enum.Font.BuilderSansExtraBold
	h.Text = text
	h.TextColor3 = TEXT_SUB
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.TextSize = 13
	h.LayoutOrder = order
	h.Parent = body
end

-- ── 게임패스 카드 (opts.passId 있으면 실물, 없으면 더미) ──
local FROST_DRAGON_PASS = 1713666153

-- 확률 상세 모달은 파일 하단에서 정의되지만 카드 생성부(아래)에서 참조하므로 전방 선언.
local openOddsModal

local function makeGamePassCard(opts)
	local passId = opts.passId          -- number | nil(더미)
	local card = Instance.new("Frame")
	card.Name = "Pass_" .. (passId or opts.name)
	card.Size = UDim2.new(1, 0, 0, 72)
	card.BackgroundColor3 = NAVY_CARD
	card.BorderSizePixel = 0
	card.LayoutOrder = opts.order
	card.Parent = opts.parent or body
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Size = UDim2.fromOffset(52, 52)
	icon.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
	icon.ClipsDescendants = true
	icon.Parent = card
	Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 8)
	local iconImg = Instance.new("ImageLabel")
	iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImg.Position = UDim2.fromScale(0.5 + (opts.iconOffsetX or 0), 0.5)
	local iconScl = opts.iconScale or (1 - (opts.iconInset or 0))
	iconImg.Size = UDim2.fromScale(iconScl, iconScl)
	iconImg.BackgroundTransparency = 1
	iconImg.Image = opts.icon or (passId and ("rbxthumb://type=GamePass&id=" .. passId .. "&w=150&h=150")) or ""
	iconImg.ScaleType = Enum.ScaleType.Fit
	iconImg.Parent = icon

	-- 다른 상품 아이콘 재활용 (Collector가 Color Skin Box 아이콘 그대로 사용)
	if opts.iconProductId then
		task.spawn(function()
			local ok, pinfo = pcall(function()
				return MarketplaceService:GetProductInfo(opts.iconProductId, Enum.InfoType.Product)
			end)
			if ok and pinfo and pinfo.IconImageAssetId and pinfo.IconImageAssetId ~= 0 then
				iconImg.Image = "rbxassetid://" .. pinfo.IconImageAssetId
			end
		end)
	end
	-- 수량 배지 (예: x5)
	if opts.qty then
		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, -2, 1, -2)
		badge.Size = UDim2.fromOffset(24, 16)
		badge.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		badge.BackgroundTransparency = 0.1
		badge.Font = Enum.Font.BuilderSansExtraBold
		badge.Text = "x" .. tostring(opts.qty)
		badge.TextColor3 = Color3.fromRGB(255, 232, 120)
		badge.TextScaled = true
		badge.ZIndex = 3
		badge.Parent = icon
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5)
		local bqc = Instance.new("UITextSizeConstraint"); bqc.MaxTextSize = 12; bqc.Parent = badge
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Position = UDim2.new(0, 72, 0, 12)
	nameLbl.Size = UDim2.new(1, -168, 0, 22)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.BuilderSansExtraBold
	nameLbl.Text = opts.name
	nameLbl.TextColor3 = TEXT_MAIN
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextScaled = true
	nameLbl.Parent = card
	local nc = Instance.new("UITextSizeConstraint"); nc.MaxTextSize = 16; nc.Parent = nameLbl

	local perk = Instance.new("TextLabel")
	perk.Position = UDim2.new(0, 72, 0, 38)
	perk.Size = UDim2.new(1, -168, 0, 18)
	perk.BackgroundTransparency = 1
	perk.Font = Enum.Font.BuilderSans
	perk.Text = opts.perk
	perk.TextColor3 = TEXT_SUB
	perk.TextXAlignment = Enum.TextXAlignment.Left
	perk.TextScaled = true
	perk.Parent = card
	local pc = Instance.new("UITextSizeConstraint"); pc.MaxTextSize = 12; pc.Parent = perk

	-- 확률 상세 진입 (유료 랜덤 박스만). 정책상 "Details" 같은 설명 단어가 필요 —
	-- (i) 아이콘 단독은 불충분. 터치 타깃 확보를 위해 카드 좌측 전체를 히트영역으로.
	if opts.oddsProductId then
		local dHit = Instance.new("TextButton")
		dHit.Name = "DetailsHit"
		dHit.Position = UDim2.new(0, 0, 0, 0)
		dHit.Size = UDim2.new(1, -104, 1, 0)   -- 구매 버튼 영역 제외
		dHit.BackgroundTransparency = 1
		dHit.Text = ""
		dHit.AutoButtonColor = false
		dHit.ZIndex = 1
		dHit.Parent = card
		local dLbl = Instance.new("TextLabel")
		dLbl.Position = UDim2.new(0, 72, 0, 55)
		dLbl.Size = UDim2.new(0, 84, 0, 14)
		dLbl.BackgroundTransparency = 1
		dLbl.Font = Enum.Font.BuilderSansExtraBold
		dLbl.Text = "Details >"
		dLbl.TextColor3 = Color3.fromRGB(120, 190, 255)
		dLbl.TextXAlignment = Enum.TextXAlignment.Left
		dLbl.TextScaled = true
		dLbl.ZIndex = 2
		dLbl.Parent = card
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = dLbl end
		dHit.MouseButton1Click:Connect(function()
			openOddsModal(nameLbl.Text, opts.oddsProductId)
		end)
	end

	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -10, 0.5, 0)
	buy.Size = UDim2.fromOffset(84, 44)   -- 모바일 터치타깃 44+
	buy.BackgroundColor3 = GREEN
	buy.Font = Enum.Font.BuilderSansExtraBold
	buy.Text = opts.price or "..."        -- 더미는 고정가, 실물은 GetProductInfo로 덮음
	buy.TextColor3 = Color3.fromRGB(255, 255, 255)
	buy.TextScaled = true
	buy.Parent = card
	Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 8)
	local bc = Instance.new("UITextSizeConstraint"); bc.MaxTextSize = 15; bc.Parent = buy

	local owned = false
	local function setOwned(v)
		owned = v
		if v then
			buy.Text = "Owned"
			buy.BackgroundColor3 = GREY_BTN
			buy.AutoButtonColor = false
		end
	end

	if passId then
		-- 실물: 이름/가격 + 소유확인 + 프롬프트
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
			end)
			if ok and info then
				if info.Name and info.Name ~= "" then nameLbl.Text = info.Name end
				if not owned then buy.Text = "R$ " .. tostring(info.PriceInRobux or "?") end
			elseif not owned then
				buy.Text = "Buy"
			end
		end)
		task.spawn(function()
			local ok, res = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if ok and res then setOwned(true) end
		end)
		buy.MouseButton1Click:Connect(function()
			if owned then return end
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
	elseif opts.productId then
		-- 개발자상품(소모형): 이름/가격/아이콘 GetProductInfo로 + 프롬프트 (소유확인 없음)
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(opts.productId, Enum.InfoType.Product)
			end)
			if ok and info then
				if info.Name and info.Name ~= "" then nameLbl.Text = info.Name end
				buy.Text = "R$ " .. tostring(info.PriceInRobux or "?")
				if not opts.icon and not opts.iconProductId and info.IconImageAssetId and info.IconImageAssetId ~= 0 then
					iconImg.Image = "rbxassetid://" .. info.IconImageAssetId
				end
			else
				buy.Text = "Buy"
			end
		end)
		buy.MouseButton1Click:Connect(function()
			MarketplaceService:PromptProductPurchase(player, opts.productId)
		end)
	else
		-- 더미: 클릭 안내
		buy.MouseButton1Click:Connect(function() toast("Coming soon") end)
	end


	-- 묶음 옵션(예: Color Skin Box ×5 = Collector). 메인 버튼 위로 축소 + 하단 골드 ×5 버튼.
	if opts.altProductId then
		buy.AnchorPoint = Vector2.new(1, 0)
		buy.Position = UDim2.new(1, -10, 0.5, -28)
		buy.Size = UDim2.fromOffset(88, 25)
		local buy2 = Instance.new("TextButton")
		buy2.AnchorPoint = Vector2.new(1, 0)
		buy2.Position = UDim2.new(1, -10, 0.5, 3)
		buy2.Size = UDim2.fromOffset(88, 25)
		buy2.BackgroundColor3 = Color3.fromRGB(240, 182, 42)
		buy2.Font = Enum.Font.BuilderSansExtraBold
		buy2.Text = "x" .. tostring(opts.altQty or 5) .. "  ..."
		buy2.TextColor3 = Color3.fromRGB(34, 26, 8)
		buy2.TextScaled = true
		buy2.Parent = card
		Instance.new("UICorner", buy2).CornerRadius = UDim.new(0, 8)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 13; c.Parent = buy2 end
		local saveBadge = Instance.new("TextLabel")
		saveBadge.Name = "SaveBadge"
		saveBadge.AnchorPoint = Vector2.new(1, 0)
		saveBadge.Position = UDim2.new(1, -10, 0, 2)
		saveBadge.Size = UDim2.fromOffset(52, 15)
		saveBadge.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		saveBadge.Font = Enum.Font.BuilderSansExtraBold
		saveBadge.Text = ""
		saveBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		saveBadge.TextScaled = true
		saveBadge.Visible = false
		saveBadge.ZIndex = 3
		saveBadge.Parent = card
		Instance.new("UICorner", saveBadge).CornerRadius = UDim.new(0, 5)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = saveBadge end
		task.spawn(function()
			local ok5, i5 = pcall(function()
				return MarketplaceService:GetProductInfo(opts.altProductId, Enum.InfoType.Product)
			end)
			local p5 = ok5 and i5 and i5.PriceInRobux or nil
			buy2.Text = "x" .. tostring(opts.altQty or 5) .. "  " .. (p5 and ("R$" .. p5) or "Buy")
			local ok1, i1 = pcall(function()
				return MarketplaceService:GetProductInfo(opts.productId, Enum.InfoType.Product)
			end)
			local p1 = ok1 and i1 and i1.PriceInRobux or nil
			if p1 and p5 and p1 > 0 then
				local full = p1 * (opts.altQty or 5)
				if full > 0 and p5 < full then
					local disc = math.floor((1 - p5 / full) * 100 + 0.5)
					if disc > 0 then
						saveBadge.Text = "-" .. disc .. "%"
						saveBadge.Visible = true
					end
				end
			end
		end)
		buy2.MouseButton1Click:Connect(function()
			MarketplaceService:PromptProductPurchase(player, opts.altProductId)
		end)
	end
	return setOwned
end

-- ── FEATURED 캐러셀 (맨 위 — LayoutOrder 음수) ──
sectionHeader("FEATURED", -2)
PromoCarousel.makeCarousel(body, {
	promos = PromoCarousel.PROMOS,
	height = 96,
	layoutOrder = -1,
	autoSec = 4,
	onClick = function(promo)
		if promo.passId then
			MarketplaceService:PromptGamePassPurchase(player, promo.passId)
		else
			toast("Coming soon")
		end
	end,
})
-- ── GAME PASSES 섹션 ──
sectionHeader("GAME PASSES", 1)
local frostSetOwned = makeGamePassCard({ passId = FROST_DRAGON_PASS, name = "Frost Dragon", perk = "Exclusive dragon King item", order = 2 })
local coinsSetOwned = makeGamePassCard({ passId = 1905787000, name = "2x Coins", perk = "Double all round rewards, forever", price = "R$ 399", icon = "rbxassetid://109002720549611", iconInset = 0.3, order = 3 })
local vipSetOwned = makeGamePassCard({ passId = 1906860989, name = "VIP", perk = "Gold name & tag, 2 map votes, +2 slots", price = "R$ 299", order = 4 })
makeGamePassCard({ productId = 3609286877, name = "King Priority", perk = "x3 chance to become the King", icon = "rbxassetid://115686709766938", order = 5, iconScale = 1.45 })

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	if plr == player and purchased then
		if passId == FROST_DRAGON_PASS then frostSetOwned(true)
		elseif passId == 1906860989 then vipSetOwned(true)
		elseif passId == 1905787000 then coinsSetOwned(true) end
	end
end)

-- ── COIN PACKS 섹션 (2×2 그리드, 더미) ──
sectionHeader("COIN PACKS", 6)

local coinGrid = Instance.new("Frame")
coinGrid.Name = "CoinGrid"
coinGrid.Size = UDim2.new(1, 0, 0, 218)   -- 2행 × 104 + 10 gap (고정 픽셀 높이 = 스크롤 안 함)
coinGrid.BackgroundTransparency = 1
coinGrid.LayoutOrder = 7
coinGrid.Parent = body

local coinLayout = Instance.new("UIGridLayout")
coinLayout.CellSize = UDim2.new(0.485, 0, 0, 104)   -- 폭 Scale(반응형) / 높이 고정 픽셀
coinLayout.CellPadding = UDim2.new(0.03, 0, 0, 10)
coinLayout.FillDirectionMaxCells = 2
coinLayout.SortOrder = Enum.SortOrder.LayoutOrder
coinLayout.Parent = coinGrid

local COIN_ICON = "rbxassetid://109002720549611"

local function makeCoinCard(opts)
	local card = Instance.new("TextButton")   -- 카드 전체 탭 가능(터치타깃)
	card.Name = "Coin_" .. opts.amount
	card.BackgroundColor3 = NAVY_CARD
	card.AutoButtonColor = true
	card.Text = ""
	card.LayoutOrder = opts.order
	card.Parent = coinGrid
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	if opts.best then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(120, 170, 255)
		stroke.Thickness = 2
		stroke.Parent = card
	end

	local icSize = opts.iconSize or 34
	-- 검정 외곽선: UIStroke가 이미지 알파를 못 따라가 사각박스가 됨 → 검정 틴트 복제본 8방향 오프셋으로 실루엣 아웃라인
	if opts.image then
		local T = opts.outlineT or 2
		for _, off in ipairs({ {-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1} }) do
			local o = Instance.new("ImageLabel")
			o.AnchorPoint = Vector2.new(0.5, 0.5)
			o.Position = UDim2.new(0.5, off[1] * T, 0, 26 + off[2] * T)
			o.Size = UDim2.fromOffset(icSize, icSize)
			o.BackgroundTransparency = 1
			o.Image = opts.image
			o.ImageColor3 = Color3.fromRGB(0, 0, 0)
			o.ScaleType = Enum.ScaleType.Fit
			o.ZIndex = 0
			o.Parent = card
		end
	end
	local ic = Instance.new("ImageLabel")
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0.5, 0, 0, 26)   -- 상단 영역 중앙 고정(커져도 대칭)
	ic.Size = UDim2.fromOffset(icSize, icSize)
	ic.BackgroundTransparency = 1
	ic.Image = opts.image or COIN_ICON
	ic.ScaleType = Enum.ScaleType.Fit
	ic.Parent = card

	local amt = Instance.new("TextLabel")
	amt.AnchorPoint = Vector2.new(0.5, 0)
	amt.Position = UDim2.new(0.5, 0, 0, 48)
	amt.Size = UDim2.new(1, -12, 0, 22)
	amt.BackgroundTransparency = 1
	amt.Font = Enum.Font.BuilderSansExtraBold
	amt.Text = "+" .. opts.amount
	amt.TextColor3 = TEXT_MAIN
	amt.TextScaled = true
	amt.Parent = card
	local ac = Instance.new("UITextSizeConstraint"); ac.MaxTextSize = 18; ac.Parent = amt

	local price = Instance.new("TextLabel")
	price.AnchorPoint = Vector2.new(0.5, 1)
	price.Position = UDim2.new(0.5, 0, 1, -10)
	price.Size = UDim2.new(1, -20, 0, 26)
	price.BackgroundColor3 = GREEN
	price.Font = Enum.Font.BuilderSansExtraBold
	price.Text = opts.price
	price.TextColor3 = Color3.fromRGB(255, 255, 255)
	price.TextScaled = true
	price.Parent = card
	Instance.new("UICorner", price).CornerRadius = UDim.new(0, 6)
	local prc = Instance.new("UITextSizeConstraint"); prc.MaxTextSize = 14; prc.Parent = price

	if opts.best then
		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -6, 0, 6)
		badge.Size = UDim2.fromOffset(42, 16)
		badge.BackgroundColor3 = Color3.fromRGB(120, 170, 255)
		badge.Font = Enum.Font.BuilderSansExtraBold
		badge.Text = "+20%"
		badge.TextColor3 = Color3.fromRGB(15, 20, 35)
		badge.TextScaled = true
		badge.Parent = card
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
	end

	card.MouseButton1Click:Connect(function()
		if opts.productId then
			MarketplaceService:PromptProductPurchase(player, opts.productId)
		else
			toast("Coming soon")
		end
	end)
end

makeCoinCard({ amount = "1,000",  price = "R$ 49",  order = 1, productId = 3609085669, image = "rbxassetid://109002720549611", outlineT = 1 })
makeCoinCard({ amount = "2,500",  price = "R$ 99",  order = 2, productId = 3609085736, image = "rbxassetid://133320278561255" })
makeCoinCard({ amount = "6,000",  price = "R$ 199", best = true, order = 3, productId = 3609085817, image = "rbxassetid://137216480849731", iconSize = 46 })
makeCoinCard({ amount = "15,000", price = "R$ 449", order = 4, productId = 3609085871, image = "rbxassetid://132934543872309", iconSize = 46 })

-- ── FEATURED BUNDLE 섹션 (더미) ──
sectionHeader("FEATURED BUNDLE", 8)

local bundle = Instance.new("TextButton")
bundle.Name = "Bundle_DragonSet"
bundle.Size = UDim2.new(1, 0, 0, 132)      -- 88 -> 132: 아트가 살려면 세로가 필요 (340/132=2.58 vs 아트 1.745)
bundle.BackgroundColor3 = NAVY_CARD
bundle.AutoButtonColor = true
bundle.Text = ""
bundle.LayoutOrder = 9
bundle.ClipsDescendants = true
bundle.Parent = body
Instance.new("UICorner", bundle).CornerRadius = UDim.new(0, 12)

-- ── 번들 아트 공용 상수 ──
-- FrostBundle4: decal 105703464785741 -> 실제 image id 99152952304504 (decal은 ImageLabel에 안 먹음, 실측 확인)
-- 좌표 전부 이전 아트와 동일(실측): X글리프(0.9821,0.0434) / 스트립 0.196·0.380·0.541·0.732
-- / 드래곤 피크 0.451 / 하단 빈구간 82~100%.
-- 아트가 담은 구성: Dragon·Sword·KillEffect·Trail(스트립) + Dash(우측 원형) = 5개. Emote는 UI 보너스 배지로 보완.
local BUNDLE_ART    = "rbxassetid://99152952304504"
local BUNDLE_ASPECT = 2736 / 1568          -- 1.7449 (원본 실측)

-- row 배경 크롭: 정규화 좌표 + Scale 배치 → 에셋 저장 해상도(1024x587)에 의존하지 않음
-- x0=-0.08 은 아트를 좌측으로 밀어 드래곤을 row 71% 지점으로 보냄(배지 x14~190과 분리).
-- 좌측 0~19% 구간엔 아트가 없지만 그라데이션이 40%까지 불투명이라 안 보임.
local BG = { x0 = -0.08, y0 = 0.166, wf = 0.75, hf = 0.508 }

do
	local bgArt = Instance.new("ImageLabel")
	bgArt.Name = "Art"
	bgArt.BackgroundTransparency = 1
	bgArt.Image = BUNDLE_ART
	bgArt.Size = UDim2.fromScale(1 / BG.wf, 1 / BG.hf)
	bgArt.Position = UDim2.fromScale(-BG.x0 / BG.wf, -BG.y0 / BG.hf)
	bgArt.ZIndex = 0
	bgArt.Parent = bundle

	-- 좌측 페이드: 40%까지 완전 불투명 -> 텍스트/배지 가독성 확보
	local bFade = Instance.new("Frame")
	bFade.Name = "Fade"
	bFade.Size = UDim2.fromScale(1, 1)
	bFade.BackgroundColor3 = NAVY_CARD
	bFade.BorderSizePixel = 0
	bFade.ZIndex = 0
	bFade.Parent = bundle
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.00),
		NumberSequenceKeypoint.new(0.40, 0.02),
		NumberSequenceKeypoint.new(0.68, 0.40),
		NumberSequenceKeypoint.new(1.00, 0.68),
	})
	g.Parent = bFade
end

local bTitle = Instance.new("TextLabel")
bTitle.Position = UDim2.new(0, 14, 0, 11)
bTitle.Size = UDim2.new(1, -92, 0, 22)
bTitle.BackgroundTransparency = 1
bTitle.Font = Enum.Font.BuilderSansExtraBold
bTitle.Text = "Frost Lord Bundle"
bTitle.TextColor3 = TEXT_MAIN
bTitle.TextXAlignment = Enum.TextXAlignment.Left
bTitle.TextScaled = true
bTitle.TextStrokeTransparency = 0                        -- 아트 위 가독성
bTitle.TextStrokeColor3 = Color3.fromRGB(6, 10, 22)
bTitle.Parent = bundle
local btc = Instance.new("UITextSizeConstraint"); btc.MaxTextSize = 17; btc.Parent = bTitle

-- 가격 799: 800 로벅스 팩($9.99)으로 딱 결제 가능한 상한. 899면 99가 모자라
-- $19.99 팩(1,700)으로 강제 점프 → 최대 구매층인 $9.99 유저가 통째로 이탈.
-- 다른 SKU(VIP 299 / Frost 300 / 2xCoins 399 / BP 499)도 전부 800 이하에 정렬됨.
--
-- SAVE 52% 근거 (개별 코인가 실측 / ShopSystem COSMETIC_PRICE·EMOTE_PRICE):
--   Ice Kill 25,000 + Ice Trail 10,000(Epic) + Ice Dash 10,000(Epic) + Frozen Emote 400(Normal)
--   = 45,400 코인 ÷ 33.4(코인팩 최고효율 15,000=R$449) ≈ R$1,359
--   + Frost Dragon 게임패스 R$300(실측) = 약 R$1,659
--   799 / 1,659 = 48.2% → 51.8% 할인. Frozen Sword(박스 전용, 코인가 없음)는 미포함이라 실제론 더 이득.
-- ⚠ 코인 시세나 패스 가격이 바뀌면 이 라벨도 다시 계산할 것.
local BUNDLE_PRICE_TEXT = "R$ 799"

local bBadge = Instance.new("TextLabel")
bBadge.AnchorPoint = Vector2.new(1, 0)
bBadge.Position = UDim2.new(1, -12, 0, 11)
bBadge.Size = UDim2.fromOffset(64, 20)
bBadge.BackgroundColor3 = Color3.fromRGB(60, 70, 95)
bBadge.Font = Enum.Font.BuilderSansExtraBold
bBadge.Text = "SAVE 52%"
bBadge.TextColor3 = Color3.fromRGB(220, 230, 255)
bBadge.TextScaled = true
bBadge.Parent = bundle
Instance.new("UICorner", bBadge).CornerRadius = UDim.new(0, 6)
local bbc = Instance.new("UITextSizeConstraint"); bbc.MaxTextSize = 11; bbc.Parent = bBadge

-- ── 구성품 배지 6개 (서브텍스트 대체) ──
-- 순서 = 태거아이템 / 러너웨폰 / 러너코스메틱 x2 / 공용 x2
-- 아트 하단 스트립 아이콘 4개는 아트에서 크롭(실측 좌표), 대시/이모트는 별도 업로드 에셋.
-- 주의: 아트의 베이크 라벨은 틀림 - 3번째 얼음큐브는 "Expression"이 아니라 Ice Kill.
-- 대시: 인벤(UnifiedInvenClient)과 동일한 아이콘을 씀.
-- dash2 사진(decal 80438028204134)은 26px에서 잔상5겹+눈송이가 뭉개져서 폐기.
-- ⚠ 색 스펙 출처: UnifiedInvenClient.DASH_ICON.dash_ice / RunnerDive.DASH_SKIN_COLORS (여기가 3번째 사본)
local DASH_ICON_ASSET   = "rbxassetid://125759196762053"   -- Images/dash_afterimage (AssetTypeId=1, 실측 확인)
local DASH_ICE_COLOR    = Color3.fromRGB(150, 235, 255)

-- 이모트: 게임에 이미 있는 emote_frozen 에셋을 EmoteData에서 읽음 (하드코딩 X -> 이미지 교체 시 자동 반영)
local BADGE_EMOTE_IMAGE = (function()
	local okE, data = pcall(function() return require(ReplicatedStorage:WaitForChild("EmoteData")) end)
	if okE and type(data) == "table" then
		for _, e in ipairs(data) do
			if e.id == "emote_frozen" and e.imageId and e.imageId ~= "" then return e.imageId end
		end
	end
	warn("[Store] emote_frozen not found in EmoteData")
	return nil
end)()

local BUNDLE_BADGES = {
	{ name = "Dragon",  crop  = { x0 = 0.1974, y0 = 0.7277, x1 = 0.2493, y1 = 0.8093 } },
	{ name = "Sword",   crop  = { x0 = 0.3739, y0 = 0.7277, x1 = 0.4251, y1 = 0.8093 } },
	{ name = "Dash",    dash  = true },
	{ name = "Trail",   crop  = { x0 = 0.7321, y0 = 0.7277, x1 = 0.7833, y1 = 0.8093 } },
	{ name = "IceKill", crop  = { x0 = 0.5413, y0 = 0.7277, x1 = 0.5925, y1 = 0.8093 } },
	{ name = "Emote",   image = BADGE_EMOTE_IMAGE },
}

local BADGE_SIZE, BADGE_GAP, BADGE_Y = 26, 4, 38
-- 셀 배경 = 아트에 그려진 아이콘 프레임 내부색 실측 median (dragon 34,50,88 / sword 35,52,94
-- / icekill 27,44,81 / trail 39,56,98). 크롭 배지는 이 색이 그림째 딸려오므로, 투명 배지(Dash/Emote)도
-- 같은 색을 깔아야 6칸이 통일됨.
local BADGE_BG = Color3.fromRGB(34, 49, 90)

for i, spec in ipairs(BUNDLE_BADGES) do
	local cell = Instance.new("Frame")
	cell.Name = "Badge_" .. spec.name
	cell.Position = UDim2.new(0, 14 + (i - 1) * (BADGE_SIZE + BADGE_GAP), 0, BADGE_Y)
	cell.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	cell.BackgroundColor3 = BADGE_BG
	cell.BorderSizePixel = 0
	cell.ClipsDescendants = true
	cell.Parent = bundle
	Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 4)
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(120, 175, 235)
	st.Thickness = 1
	st.Parent = cell

	local ic = Instance.new("ImageLabel")
	ic.Name = "Icon"
	ic.BackgroundTransparency = 1
	ic.Parent = cell
	if spec.crop then
		local cw = spec.crop.x1 - spec.crop.x0
		local ch = spec.crop.y1 - spec.crop.y0
		ic.Image = BUNDLE_ART
		ic.Size = UDim2.fromScale(1 / cw, 1 / ch)
		ic.Position = UDim2.fromScale(-spec.crop.x0 / cw, -spec.crop.y0 / ch)
	elseif spec.dash then
		-- 인벤 makeDashIcon과 동일 방식: 흰 실루엣 + UIGradient 색 + UIStroke 발광
		ic.Image = DASH_ICON_ASSET
		ic.ImageColor3 = Color3.fromRGB(255, 255, 255)
		ic.ScaleType = Enum.ScaleType.Fit
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Size = UDim2.fromScale(0.9, 0.9)
		local dg = Instance.new("UIGradient")
		dg.Color = ColorSequence.new(DASH_ICE_COLOR)
		dg.Parent = ic
		local ds = Instance.new("UIStroke")
		ds.Color = Color3.fromRGB(255, 255, 255)
		ds.Thickness = 1
		ds.Transparency = 0.4
		ds.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		ds.Parent = ic
	else
		ic.Image = spec.image or ""
		ic.ScaleType = Enum.ScaleType.Fit
		ic.Size = UDim2.fromScale(0.88, 0.88)
		ic.Position = UDim2.fromScale(0.06, 0.06)
	end
end

local bPrice = Instance.new("TextLabel")
bPrice.AnchorPoint = Vector2.new(0, 1)
bPrice.Position = UDim2.new(0, 14, 1, -14)          -- 우하단 -> 좌하단 (우측을 아트에 양보)
bPrice.Size = UDim2.fromOffset(96, 28)
bPrice.BackgroundColor3 = GREEN                      -- 초록 유지: 로벅스 결제 컨벤션
bPrice.Font = Enum.Font.BuilderSansExtraBold
bPrice.Text = BUNDLE_PRICE_TEXT
bPrice.TextColor3 = Color3.fromRGB(255, 255, 255)
bPrice.TextScaled = true
bPrice.Parent = bundle
Instance.new("UICorner", bPrice).CornerRadius = UDim.new(0, 6)
local bpc = Instance.new("UITextSizeConstraint"); bpc.MaxTextSize = 14; bpc.Parent = bPrice

-- ── 회전하는 서리 테두리 ──
-- UIStroke에 UIGradient를 붙이고 Rotation을 매 프레임 돌리면, 밝은 띠가 테두리를 따라 도는 효과.
-- 색은 전부 흰~얼음색이고 "투명도"에 밴드를 만들어 회전시킴 → 서리가 훑고 지나가는 느낌.
do
	local RunSvc = game:GetService("RunService")   -- ⚠ 이 파일의 local RunService는 아래쪽 선언이라 여기선 nil

	local frost = Instance.new("UIStroke")
	frost.Name = "FrostStroke"
	frost.Thickness = 2
	frost.Color = Color3.fromRGB(255, 255, 255)
	frost.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frost.Parent = bundle

	local fg = Instance.new("UIGradient")
	fg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(150, 215, 255)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(150, 215, 255)),
	})
	-- 대부분 흐리게 두고 좁은 구간만 선명 → 그 띠가 회전하며 테두리를 훑음
	fg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.80),
		NumberSequenceKeypoint.new(0.42, 0.75),
		NumberSequenceKeypoint.new(0.50, 0.05),
		NumberSequenceKeypoint.new(0.58, 0.75),
		NumberSequenceKeypoint.new(1.00, 0.80),
	})
	fg.Parent = frost

	RunSvc.Heartbeat:Connect(function()
		if not gui.Enabled then return end          -- 상점 닫혀 있으면 계산 스킵
		if not bundle.Visible then return end
		fg.Rotation = (os.clock() * 45) % 360       -- 8초에 한 바퀴
	end)
end

-- ── 번들 상세 모달 (아트 원본을 풀스크린으로) ──
-- 아트가 640px 이상에서만 베이크된 글자가 읽힘 → 88px row엔 썸네일만, 상세는 여기서.
-- 게임패스로 판매 (개발자상품 아님 — 중복 구매 방지. 지급은 서버 BundleGrant가 담당).
local BUNDLE_PASS_ID = 1918658457

local bundleModal = Instance.new("Frame")
bundleModal.Name = "BundleModal"
bundleModal.Size = UDim2.fromScale(1, 1)
bundleModal.BackgroundTransparency = 1
bundleModal.Visible = false
bundleModal.ZIndex = 50
bundleModal.Parent = gui

local mDim = Instance.new("TextButton")
mDim.Name = "Dim"
mDim.Size = UDim2.fromScale(1, 1)
mDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
mDim.BackgroundTransparency = 0.3
mDim.Text = ""
mDim.AutoButtonColor = false
mDim.ZIndex = 50
mDim.Parent = bundleModal

local mArt = Instance.new("ImageLabel")
mArt.Name = "Art"
mArt.AnchorPoint = Vector2.new(0.5, 0.5)
mArt.Position = UDim2.fromScale(0.5, 0.5)
mArt.Size = UDim2.fromScale(0.94, 0.94)
mArt.BackgroundTransparency = 1
mArt.Image = BUNDLE_ART
mArt.ZIndex = 51
mArt.Parent = bundleModal

local mAspect = Instance.new("UIAspectRatioConstraint")
mAspect.AspectRatio = BUNDLE_ASPECT           -- 1.7449, 아트 왜곡 방지
mAspect.Parent = mArt

-- 그려진 X 위에 얹는 진짜 버튼 (글리프 실측 중심: 0.9819, 0.0446)
local mClose = Instance.new("TextButton")
mClose.Name = "CloseHit"
mClose.AnchorPoint = Vector2.new(0.5, 0.5)
mClose.Position = UDim2.fromScale(0.9819, 0.0446)
mClose.Size = UDim2.fromScale(0.065, 0.11)
mClose.BackgroundTransparency = 1
mClose.Text = ""
mClose.ZIndex = 52
mClose.Parent = mArt
local mcSize = Instance.new("UISizeConstraint")
mcSize.MinSize = Vector2.new(44, 44)          -- 모바일 터치타깃
mcSize.Parent = mClose

-- 구매 버튼 (하단 빈 눈밭 구간 84~100% 실측 → 중심 0.92)
-- P2: 그림자 + 세로 그라데이션 + 테두리 + 상단 광택 + 텍스트 외곽선.
-- 래퍼로 묶어야 그림자/본체/광택이 화면 크기 바뀌어도 같이 움직임.
local mBuyWrap = Instance.new("Frame")
mBuyWrap.Name = "BuyWrap"
mBuyWrap.AnchorPoint = Vector2.new(0.5, 0.5)
mBuyWrap.Position = UDim2.fromScale(0.5, 0.92)
mBuyWrap.Size = UDim2.fromScale(0.26, 0.105)
mBuyWrap.BackgroundTransparency = 1
mBuyWrap.ZIndex = 51
mBuyWrap.Parent = mArt
local mbSize = Instance.new("UISizeConstraint")
mbSize.MinSize = Vector2.new(130, 40)
mbSize.Parent = mBuyWrap

local mBuyShadow = Instance.new("Frame")
mBuyShadow.Name = "Shadow"
mBuyShadow.Position = UDim2.new(0, 0, 0, 4)
mBuyShadow.Size = UDim2.fromScale(1, 1)
mBuyShadow.BackgroundColor3 = Color3.fromRGB(8, 40, 18)
mBuyShadow.BorderSizePixel = 0
mBuyShadow.ZIndex = 51
mBuyShadow.Parent = mBuyWrap
Instance.new("UICorner", mBuyShadow).CornerRadius = UDim.new(0, 10)

local mBuy = Instance.new("TextButton")
mBuy.Name = "Buy"
mBuy.Size = UDim2.fromScale(1, 1)
mBuy.BackgroundColor3 = Color3.fromRGB(255, 255, 255)   -- UIGradient가 실제 색을 칠함
mBuy.Font = Enum.Font.BuilderSansExtraBold
mBuy.Text = BUNDLE_PRICE_TEXT
mBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
mBuy.TextScaled = true
mBuy.TextStrokeTransparency = 0
mBuy.TextStrokeColor3 = Color3.fromRGB(10, 66, 28)
mBuy.AutoButtonColor = true
mBuy.ClipsDescendants = true                             -- 광택이 라운드 코너 따라 잘리도록
mBuy.ZIndex = 52
mBuy.Parent = mBuyWrap
Instance.new("UICorner", mBuy).CornerRadius = UDim.new(0, 10)

local mbGrad = Instance.new("UIGradient")
mbGrad.Rotation = 90
mbGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 238, 132)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 146, 58)),
})
mbGrad.Parent = mBuy

local mbStroke = Instance.new("UIStroke")
mbStroke.Color = Color3.fromRGB(12, 78, 34)
mbStroke.Thickness = 2
mbStroke.Parent = mBuy

local mbGloss = Instance.new("Frame")
mbGloss.Name = "Gloss"
mbGloss.Size = UDim2.fromScale(1, 0.45)
mbGloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
mbGloss.BorderSizePixel = 0
mbGloss.ZIndex = 53
mbGloss.Parent = mBuy
-- ClipsDescendants는 사각 경계로만 자름(UICorner 둥근 모양을 안 따라감).
-- -> 광택에도 같은 라운드를 줘야 상단 좌우 모서리에 흰 네모가 안 남음.
Instance.new("UICorner", mbGloss).CornerRadius = UDim.new(0, 10)
local mgGrad = Instance.new("UIGradient")
mgGrad.Rotation = 90
mgGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.70),
	NumberSequenceKeypoint.new(1, 1.00),
})
mgGrad.Parent = mbGloss

local mbText = Instance.new("UITextSizeConstraint"); mbText.MaxTextSize = 22; mbText.Parent = mBuy

-- ── +Emote 보너스 배지 ──
-- 아트는 5개(Dragon/Sword/KillEffect/Trail + Dash)만 담음. 6번째 Emote를 UI로 보완.
-- 위치: 스트립의 Trail 아이콘(실측 x 0.732~0.783, 중심 0.757) 바로 아래. 구매 버튼(x 0.37~0.63)과 분리됨.
local mBonus = Instance.new("Frame")
mBonus.Name = "EmoteBonus"
mBonus.AnchorPoint = Vector2.new(0.5, 0.5)
mBonus.Position = UDim2.fromScale(0.757, 0.90)
mBonus.Size = UDim2.fromScale(0.13, 0.085)
mBonus.BackgroundColor3 = Color3.fromRGB(12, 30, 62)
mBonus.BackgroundTransparency = 0.15
mBonus.BorderSizePixel = 0
mBonus.ZIndex = 52
mBonus.Parent = mArt
Instance.new("UICorner", mBonus).CornerRadius = UDim.new(0, 8)
local mbnSize = Instance.new("UISizeConstraint")
mbnSize.MinSize = Vector2.new(96, 34)
mbnSize.Parent = mBonus
local mbnStroke = Instance.new("UIStroke")
mbnStroke.Color = Color3.fromRGB(150, 220, 255)
mbnStroke.Thickness = 1.5
mbnStroke.Transparency = 0.2
mbnStroke.Parent = mBonus

local mbnIcon = Instance.new("ImageLabel")
mbnIcon.Name = "Icon"
mbnIcon.AnchorPoint = Vector2.new(0, 0.5)
mbnIcon.Position = UDim2.new(0, 4, 0.5, 0)
mbnIcon.Size = UDim2.new(0.82, 0, 0.82, 0)
-- ⚠ RelativeYY면 X도 "부모 높이" 기준이 됨. X를 0으로 두면 폭 0 = 이미지가 안 보임(로드는 됐어도).
--   X/Y 스케일을 같게 줘야 정사각.
mbnIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
mbnIcon.BackgroundTransparency = 1
mbnIcon.ScaleType = Enum.ScaleType.Fit
mbnIcon.Image = BADGE_EMOTE_IMAGE or ""
mbnIcon.ZIndex = 53
mbnIcon.Parent = mBonus

local mbnText = Instance.new("TextLabel")
mbnText.Name = "Label"
mbnText.AnchorPoint = Vector2.new(1, 0.5)
mbnText.Position = UDim2.new(1, -6, 0.5, 0)
mbnText.Size = UDim2.new(1, -40, 0.7, 0)
mbnText.BackgroundTransparency = 1
mbnText.Font = Enum.Font.BuilderSansExtraBold
mbnText.Text = "+ EMOTE"
mbnText.TextColor3 = Color3.fromRGB(215, 245, 255)
mbnText.TextXAlignment = Enum.TextXAlignment.Right
mbnText.TextScaled = true
mbnText.TextStrokeTransparency = 0
mbnText.TextStrokeColor3 = Color3.fromRGB(6, 20, 44)
mbnText.ZIndex = 53
mbnText.Parent = mBonus
local mbnTC = Instance.new("UITextSizeConstraint"); mbnTC.MaxTextSize = 14; mbnTC.Parent = mbnText

local function setBundleOpen(open)
	bundleModal.Visible = open
end

-- 보유 상태 반영: 이미 산 유저에게 가격을 보여주면 재구매를 유도하는 꼴.
-- 패스는 로블록스가 중복 결제를 막지만, UI도 같이 맞춰야 오해가 없음.
local bundleOwned = false
local function setBundleOwned(owned)
	bundleOwned = owned
	if owned then
		mBuy.Text = "OWNED"
		mBuy.AutoButtonColor = false
		mbGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 130, 150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 68, 84)),
		})
		mbStroke.Color = Color3.fromRGB(40, 46, 58)
		mBuy.TextStrokeColor3 = Color3.fromRGB(30, 34, 44)
		bPrice.Text = "OWNED"
		bPrice.BackgroundColor3 = Color3.fromRGB(70, 78, 96)
		bBadge.Visible = false
	end
end

-- 조인 시 1회. UserOwnsGamePassAsync는 세션 캐시라 재폴링해도 안 바뀜 →
-- 세션 중 구매는 아래 PromptGamePassPurchaseFinished로만 잡힘.
task.spawn(function()
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, BUNDLE_PASS_ID)
	end)
	if ok and owns then setBundleOwned(true) end
end)

mClose.MouseButton1Click:Connect(function() setBundleOpen(false) end)
mDim.MouseButton1Click:Connect(function() setBundleOpen(false) end)
mBuy.MouseButton1Click:Connect(function()
	if bundleOwned then return end
	MarketplaceService:PromptGamePassPurchase(player, BUNDLE_PASS_ID)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	if plr == player and passId == BUNDLE_PASS_ID and purchased then
		setBundleOwned(true)
	end
end)

do
	local bHint = Instance.new("TextLabel")
	bHint.Name = "Hint"
	bHint.AnchorPoint = Vector2.new(1, 1)
	bHint.Position = UDim2.new(1, -12, 1, -12)
	bHint.Size = UDim2.fromOffset(96, 18)
	bHint.BackgroundTransparency = 1
	bHint.Font = Enum.Font.BuilderSansMedium
	bHint.Text = "Tap for details"
	bHint.TextColor3 = Color3.fromRGB(210, 215, 230)
	bHint.TextXAlignment = Enum.TextXAlignment.Right
	bHint.TextScaled = true
	bHint.TextStrokeTransparency = 0.4
	bHint.TextStrokeColor3 = Color3.fromRGB(6, 10, 22)
	bHint.ZIndex = 2
	bHint.Parent = bundle
	local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = bHint
end
bundle.MouseButton1Click:Connect(function() setBundleOpen(true) end)

-- ── PREMIUM SKINS 섹션 (더미 3개) ──
sectionHeader("STARTER PACKS", 10)

-- 배너 데칼 -> 실제 이미지 (InsertService 추출 완료)
local STARTER_PACKS = {
	{ key = "King",   name = "King Starter Pack",   passId = 1919324786,
	  art = "rbxassetid://89469915027432", bg = { x0 = -0.02, y0 = 0.14, wf = 0.75, hf = 0.508 } },
	{ key = "Runner", name = "Runner Starter Pack", passId = 1918070832,
	  art = "rbxassetid://77152147027397", bg = { x0 = -0.02, y0 = 0.14, wf = 0.75, hf = 0.508 } },
}

-- ── 공용 상세 모달 (배너 전체 + Buy) ──
local sModal = Instance.new("Frame")
sModal.Name = "StarterModal"
sModal.Size = UDim2.fromScale(1, 1)
sModal.BackgroundTransparency = 1
sModal.Visible = false
sModal.ZIndex = 60
sModal.Parent = gui

local sDim = Instance.new("TextButton")
sDim.Size = UDim2.fromScale(1, 1)
sDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
sDim.BackgroundTransparency = 0.35
sDim.Text = ""
sDim.AutoButtonColor = false
sDim.ZIndex = 60
sDim.Parent = sModal
sDim.MouseButton1Click:Connect(function() sModal.Visible = false end)

local sArt = Instance.new("ImageLabel")
sArt.AnchorPoint = Vector2.new(0.5, 0.5)
sArt.Position = UDim2.fromScale(0.5, 0.44)
sArt.Size = UDim2.fromScale(0.9, 0.62)
sArt.BackgroundTransparency = 1
sArt.ScaleType = Enum.ScaleType.Fit
sArt.ZIndex = 61
sArt.Parent = sModal

local sBuy = Instance.new("TextButton")
sBuy.AnchorPoint = Vector2.new(0.5, 0)
sBuy.Position = UDim2.fromScale(0.5, 0.78)
sBuy.Size = UDim2.fromOffset(210, 50)
sBuy.BackgroundColor3 = GREEN
sBuy.Font = Enum.Font.BuilderSansExtraBold
sBuy.Text = "R$ 199"
sBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
sBuy.TextScaled = true
sBuy.ZIndex = 62
sBuy.Parent = sModal
Instance.new("UICorner", sBuy).CornerRadius = UDim.new(0, 12)
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 20; c.Parent = sBuy end

local sClose = Instance.new("TextButton")
sClose.AnchorPoint = Vector2.new(0.5, 0.5)
sClose.Position = UDim2.fromScale(0.93, 0.12)
sClose.Size = UDim2.fromOffset(42, 42)
sClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
sClose.Font = Enum.Font.BuilderSansExtraBold
sClose.Text = "X"
sClose.TextColor3 = Color3.fromRGB(255, 255, 255)
sClose.TextScaled = true
sClose.ZIndex = 62
sClose.Parent = sModal
Instance.new("UICorner", sClose).CornerRadius = UDim.new(0, 10)
sClose.MouseButton1Click:Connect(function() sModal.Visible = false end)

local sCurPass = nil
sBuy.MouseButton1Click:Connect(function()
	if sCurPass then MarketplaceService:PromptGamePassPurchase(player, sCurPass) end
end)

-- ══════════════════════════════════════════════════════════════════
-- 확률 상세 모달 (로블록스 유료 랜덤 아이템 정책)
--   · 구매 전 접근 가능 · 전체 결과 + 수치 확률 · 합계 100%
--   · 중복 방지라 유저마다 다르므로 열 때마다 서버 조회 (캐시 금지)
-- ══════════════════════════════════════════════════════════════════
local oddsRF = ReplicatedStorage:WaitForChild("GetBoxOdds", 10)

local oddsModal = Instance.new("Frame")
oddsModal.Name = "OddsModal"
oddsModal.Size = UDim2.fromScale(1, 1)
oddsModal.BackgroundTransparency = 1
oddsModal.Visible = false
oddsModal.ZIndex = 70
oddsModal.Parent = gui

local oDim = Instance.new("TextButton")
oDim.Size = UDim2.fromScale(1, 1)
oDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
oDim.BackgroundTransparency = 0.35
oDim.Text = ""
oDim.AutoButtonColor = false
oDim.ZIndex = 70
oDim.Parent = oddsModal
oDim.MouseButton1Click:Connect(function() oddsModal.Visible = false end)

local oPanel = Instance.new("Frame")
oPanel.AnchorPoint = Vector2.new(0.5, 0.5)
oPanel.Position = UDim2.fromScale(0.5, 0.5)
oPanel.Size = UDim2.fromScale(0.88, 0.78)
oPanel.BackgroundColor3 = NAVY_BG
oPanel.BorderSizePixel = 0
oPanel.ZIndex = 71
oPanel.Parent = oddsModal
Instance.new("UICorner", oPanel).CornerRadius = UDim.new(0, 14)

local oTitle = Instance.new("TextLabel")
oTitle.Position = UDim2.new(0, 16, 0, 12)
oTitle.Size = UDim2.new(1, -70, 0, 24)
oTitle.BackgroundTransparency = 1
oTitle.Font = Enum.Font.BuilderSansExtraBold
oTitle.Text = "Details"
oTitle.TextColor3 = TEXT_MAIN
oTitle.TextXAlignment = Enum.TextXAlignment.Left
oTitle.TextScaled = true
oTitle.ZIndex = 72
oTitle.Parent = oPanel
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 18; c.Parent = oTitle end

local oSummary = Instance.new("TextLabel")
oSummary.Position = UDim2.new(0, 16, 0, 40)
oSummary.Size = UDim2.new(1, -32, 0, 34)
oSummary.BackgroundTransparency = 1
oSummary.Font = Enum.Font.BuilderSans
oSummary.Text = ""
oSummary.TextColor3 = TEXT_SUB
oSummary.TextXAlignment = Enum.TextXAlignment.Left
oSummary.TextYAlignment = Enum.TextYAlignment.Top
oSummary.TextWrapped = true
oSummary.TextSize = 12
oSummary.ZIndex = 72
oSummary.Parent = oPanel

local oScroll = Instance.new("ScrollingFrame")
oScroll.Position = UDim2.new(0, 12, 0, 78)
oScroll.Size = UDim2.new(1, -24, 1, -122)
oScroll.BackgroundTransparency = 1
oScroll.BorderSizePixel = 0
oScroll.ScrollBarThickness = 4
oScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
oScroll.ZIndex = 72
oScroll.Parent = oPanel
local oList = Instance.new("UIListLayout")
oList.Padding = UDim.new(0, 2)
oList.SortOrder = Enum.SortOrder.LayoutOrder
oList.Parent = oScroll

local oNote = Instance.new("TextLabel")
oNote.AnchorPoint = Vector2.new(0, 1)
oNote.Position = UDim2.new(0, 16, 1, -10)
oNote.Size = UDim2.new(1, -32, 0, 28)
oNote.BackgroundTransparency = 1
oNote.Font = Enum.Font.BuilderSans
oNote.Text = "Probabilities are rounded; displayed values may not total exactly 100%."
oNote.TextColor3 = Color3.fromRGB(150, 158, 180)
oNote.TextXAlignment = Enum.TextXAlignment.Left
oNote.TextWrapped = true
oNote.TextSize = 10
oNote.ZIndex = 72
oNote.Parent = oPanel

local oClose = Instance.new("TextButton")
oClose.AnchorPoint = Vector2.new(1, 0)
oClose.Position = UDim2.new(1, -10, 0, 10)
oClose.Size = UDim2.fromOffset(44, 44)
oClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
oClose.Font = Enum.Font.BuilderSansExtraBold
oClose.Text = "X"
oClose.TextColor3 = Color3.fromRGB(255, 255, 255)
oClose.TextScaled = true
oClose.ZIndex = 73
oClose.Parent = oPanel
Instance.new("UICorner", oClose).CornerRadius = UDim.new(0, 10)
oClose.MouseButton1Click:Connect(function() oddsModal.Visible = false end)

local RARITY_COLOR = {
	Normal    = Color3.fromRGB(210, 210, 210),
	Rare      = Color3.fromRGB(80, 200, 90),
	Epic      = Color3.fromRGB(170, 95, 240),
	Legendary = Color3.fromRGB(255, 180, 30),
}
local RARITY_ORDER = { Normal = 1, Rare = 2, Epic = 3, Legendary = 4 }
local KIND_LABEL = {
	skin = "Weapon skin", gcolor = "Gauntlet color", icolor = "Weapon color",
	killEffect = "Kill effect", trailSkin = "Trail", dashSkin = "Dash", crownSkin = "Crown",
}

local function oddsRow(text, color, bold, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 18)
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.BuilderSansExtraBold or Enum.Font.BuilderSans
	l.Text = text
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextSize = bold and 13 or 12
	l.LayoutOrder = order
	l.ZIndex = 72
	l.Parent = oScroll
end

openOddsModal = function(boxName, productId)
	oTitle.Text = boxName .. " — Odds"
	oSummary.Text = "Loading..."
	for _, c in ipairs(oScroll:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	oddsModal.Visible = true
	task.spawn(function()
		local ok, o = pcall(function() return oddsRF:InvokeServer(productId) end)
		if not oddsModal.Visible then return end
		if not ok or not o then
			oSummary.Text = "Could not load odds. Please try again."
			return
		end
		if o.total == 0 then
			oSummary.Text = "You already own every item in this box. Purchases now award coins instead."
			return
		end
		if o.each then
			oSummary.Text = string.format(
				"%d possible outcomes · each item %.4f%% · duplicates excluded, so odds update as you collect.",
				o.total, o.each)
		else
			oSummary.Text = string.format(
				"%d possible outcomes · odds shown per item below · duplicates excluded, so odds update as you collect.",
				o.total)
		end
		local order = 0
		local function section(title, tbl, colorFn)
			if not tbl then return end
			local keys = {}
			for k in pairs(tbl) do keys[#keys+1] = k end
			table.sort(keys, function(a, b)
				return (RARITY_ORDER[a] or 99) < (RARITY_ORDER[b] or 99) or
				       ((RARITY_ORDER[a] or 99) == (RARITY_ORDER[b] or 99) and a < b)
			end)
			order = order + 1
			oddsRow(title, TEXT_MAIN, true, order)
			for _, k in ipairs(keys) do
				local v = tbl[k]
				order = order + 1
				oddsRow(string.format("   %s — %.2f%%  (%d)", KIND_LABEL[k] or k, v.chance, v.count),
					colorFn and colorFn(k) or TEXT_SUB, false, order)
			end
		end
		section("By rarity", o.byRarity, function(k) return RARITY_COLOR[k] or TEXT_SUB end)
		section("By type", o.byKind or o.byCategory, nil)
		order = order + 1
		oddsRow(o.each and string.format("All items below: %.4f%% each", o.each) or "All items below (individual odds):", TEXT_MAIN, true, order)
		table.sort(o.items, function(a, b)
			local ra, rb = RARITY_ORDER[a.rarity] or 99, RARITY_ORDER[b.rarity] or 99
			if ra ~= rb then return ra > rb end
			return tostring(a.display) < tostring(b.display)
		end)
		for _, it in ipairs(o.items) do
			order = order + 1
			oddsRow(string.format("   %s — %.4f%%", tostring(it.display), it.chance),
				RARITY_COLOR[it.rarity] or TEXT_SUB, false, order)
		end
		oScroll.CanvasSize = UDim2.new(0, 0, 0, order * 20 + 12)
	end)
end

local function openStarterModal(pack, owned)

	sArt.Image = pack.art
	sCurPass = pack.passId
	if owned then
		sBuy.Text = "OWNED"
		sBuy.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
		sBuy.AutoButtonColor = false
	else
		sBuy.Text = "Buy  R$ 199"
		sBuy.BackgroundColor3 = GREEN
		sBuy.AutoButtonColor = true
	end
	sModal.Visible = true
end

-- ── 배너 아트 카드 빌더 (Frost Lord Bundle 방식) ──
local function makeStarterCard(pack, order)
	local card = Instance.new("TextButton")
	card.Name = "Starter_" .. pack.key
	card.Size = UDim2.new(1, 0, 0, 120)
	card.BackgroundColor3 = NAVY_CARD
	card.AutoButtonColor = true
	card.Text = ""
	card.LayoutOrder = order
	card.ClipsDescendants = true
	card.Parent = body
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local bg = pack.bg
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Image = pack.art
	art.Size = UDim2.fromScale(1 / bg.wf, 1 / bg.hf)
	art.Position = UDim2.fromScale(-bg.x0 / bg.wf, -bg.y0 / bg.hf)
	art.ZIndex = 0
	art.Parent = card

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = NAVY_CARD
	fade.BorderSizePixel = 0
	fade.ZIndex = 0
	fade.Parent = card
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.05),
		NumberSequenceKeypoint.new(0.42, 0.18),
		NumberSequenceKeypoint.new(0.70, 0.60),
		NumberSequenceKeypoint.new(1.00, 0.82),
	})
	g.Parent = fade

	local title = Instance.new("TextLabel")
	title.Position = UDim2.new(0, 14, 0, 12)
	title.Size = UDim2.new(1, -100, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.BuilderSansExtraBold
	title.Text = pack.name
	title.TextColor3 = TEXT_MAIN
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.TextStrokeTransparency = 0
	title.TextStrokeColor3 = Color3.fromRGB(6, 10, 22)
	title.ZIndex = 2
	title.Parent = card
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 17; c.Parent = title end

	local price = Instance.new("TextLabel")
	price.AnchorPoint = Vector2.new(0, 1)
	price.Position = UDim2.new(0, 14, 1, -12)
	price.Size = UDim2.fromOffset(74, 26)
	price.BackgroundColor3 = GREEN
	price.Font = Enum.Font.BuilderSansExtraBold
	price.Text = "R$ 199"
	price.TextColor3 = Color3.fromRGB(255, 255, 255)
	price.TextScaled = true
	price.ZIndex = 2
	price.Parent = card
	Instance.new("UICorner", price).CornerRadius = UDim.new(0, 6)
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 13; c.Parent = price end

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -12, 1, -12)
	hint.Size = UDim2.fromOffset(96, 18)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.BuilderSansMedium
	hint.Text = "Tap for details"
	hint.TextColor3 = Color3.fromRGB(210, 215, 230)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextScaled = true
	hint.TextStrokeTransparency = 0.4
	hint.TextStrokeColor3 = Color3.fromRGB(6, 10, 22)
	hint.ZIndex = 2
	hint.Parent = card
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = hint end

	local owned = false
	local function setOwned(v)
		owned = v
		if v then
			price.Text = "OWNED"
			price.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
			price.Size = UDim2.fromOffset(86, 26)
		end
	end
	task.spawn(function()
		local ok, res = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pack.passId)
		end)
		if ok and res then setOwned(true) end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
		if plr == player and passId == pack.passId and purchased then setOwned(true) end
	end)

	card.MouseButton1Click:Connect(function()
		openStarterModal(pack, owned)
	end)
end

makeStarterCard(STARTER_PACKS[1], 11)
makeStarterCard(STARTER_PACKS[2], 12)

-- ── SKIN BOXES 섹션 (유료 랜덤 — 정책 제한 시 섹션 통째로 숨김) ──
local boxSection = Instance.new("Frame")
boxSection.Name = "SkinBoxes"
boxSection.Size = UDim2.new(1, 0, 0, 0)
boxSection.AutomaticSize = Enum.AutomaticSize.Y
boxSection.BackgroundTransparency = 1
boxSection.LayoutOrder = 13
boxSection.Parent = body
do
	local l = Instance.new("UIListLayout", boxSection)
	l.FillDirection = Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end

local boxHeader = Instance.new("TextLabel")
boxHeader.Size = UDim2.new(1, 0, 0, 22)
boxHeader.LayoutOrder = 0
boxHeader.BackgroundTransparency = 1
boxHeader.Font = Enum.Font.BuilderSansExtraBold
boxHeader.Text = "SKIN BOXES"
boxHeader.TextColor3 = TEXT_SUB
boxHeader.TextXAlignment = Enum.TextXAlignment.Left
boxHeader.TextScaled = true
boxHeader.Parent = boxSection
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 13; c.Parent = boxHeader end

makeGamePassCard({ productId = 3609370373, oddsProductId = 3609370373, name = "Color Skin Box", perk = "Mostly weapon colors · some skins · no dupes", order = 1, parent = boxSection, altProductId = 3610453697, altQty = 5 })
makeGamePassCard({ productId = 3609370476, oddsProductId = 3609370476, name = "Rare+ Box", perk = "Random Rare/Epic · guaranteed Rare+",         order = 2, parent = boxSection, iconScale = 1.5, iconOffsetX = -0.08 })
makeGamePassCard({ productId = 3609370535, oddsProductId = 3609370535, name = "Epic+ Box", perk = "Random Epic/Legendary · guaranteed Epic+",    order = 3, parent = boxSection, iconScale = 1.4 })
makeGamePassCard({ productId = 3609608159, oddsProductId = 3609608159, name = "Cosmetic Box", perk = "Random trail, dash, crown or kill effect", order = 4, parent = boxSection, iconScale = 1.4, iconOffsetX = -0.1 })

-- 정책 게이트: NoPaidRandom(유료 랜덤 제한)이 명시적 false(허용)일 때만 노출. nil/true면 숨김(보수적).
local function refreshBoxPolicy()
	boxSection.Visible = (player:GetAttribute("NoPaidRandom") == false)
end
refreshBoxPolicy()
player:GetAttributeChangedSignal("NoPaidRandom"):Connect(refreshBoxPolicy)
-- ── 토글 + 스크롤바 ──
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
body.ScrollBarThickness = 8
body.ScrollBarImageTransparency = 0.35

-- 세로 리스트(픽셀 행높이)라 AbsoluteContentSize 안정적 → 캔버스 수동 계산(첫 클릭 없이 스크롤 가능)
local function refreshCanvas()
	body.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 16)
end
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)
refreshCanvas()

-- 스크롤바 점멸 (스크롤 가능함을 알림. 모바일은 rest에서 바가 자동숨김이라 이걸로 인지)
local function pulseBar()
	if body.CanvasSize.Y.Offset > body.AbsoluteSize.Y + 4 then
		for _ = 1, 2 do
			TweenService:Create(body, TweenInfo.new(0.22), { ScrollBarImageTransparency = 0 }):Play()
			task.wait(0.26)
			TweenService:Create(body, TweenInfo.new(0.22), { ScrollBarImageTransparency = 0.35 }):Play()
			task.wait(0.26)
		end
	end
end

local function setOpen(open)
	gui.Enabled = open
	if not open then
		bundleModal.Visible = false   -- 모달 켠 채 스토어 닫으면 다음 오픈에 남아있는 것 방지
	end
	if open then
		task.spawn(function()
			RunService.Heartbeat:Wait()
			refreshCanvas()
			pulseBar()   -- 열자마자 점멸 (모바일에서도 열 때 스크롤 가능 인지)
		end)
	end
end

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
dim.MouseButton1Click:Connect(function() setOpen(false) end)

-- 주기 점멸 (열려있을 때 2.5초마다)
task.spawn(function()
	while true do
		task.wait(2.5)
		if gui.Enabled then pulseBar() end
	end
end)

-- 외부에서 열기용 전역 (이후 광고 카드/딥링크에서 재사용)
-- 외부에서 열기용 전역. section="coins"면 COIN PACKS 섹션으로 스크롤.
-- (HUD 코인 패널의 + 버튼이 이 경로로 진입)
_G.openRobuxStore = function(section)
	setOpen(true)
	if section ~= "coins" then return end
	task.defer(function()
		local target
		for _, d in ipairs(body:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == "COIN PACKS" then target = d break end
		end
		if not target then return end
		-- 헤더의 캔버스 내 Y = (헤더 절대Y - 스크롤 절대Y) + 현재 캔버스 오프셋
		local y = (target.AbsolutePosition.Y - body.AbsolutePosition.Y) + body.CanvasPosition.Y
		body.CanvasPosition = Vector2.new(0, math.max(0, y - 8))
	end)
end

-- 임시 테스트 진입: 서버 /robux 커맨드가 플레이어 속성 세팅 → 여기서 감지해 열기
player:GetAttributeChangedSignal("_OpenRobuxStore"):Connect(function()
	setOpen(true)
end)

print("✅ RobuxStoreClient 준비! (껍데기 + 코인+ 진입)")
