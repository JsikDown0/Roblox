-- PromoCarousel — 재사용 프로모 캐러셀 (상점 상단 피처드 + HUD 광고 배너 공용)
-- UIPageLayout 기반: 터치 스와이프 내장 + 4초 자동순환 + 점 인디케이터 + (넓은 모드)좌우 화살표 + 무한 루프.
-- makeCarousel(parent, opts): opts = { promos, height, layoutOrder, autoSec, onClick(promo), compact, size, position }
--   compact=true → HUD 배너용 세로 레이아웃(아이콘+이름, 화살표 없음)
--   size/position → 컨테이너 크기·위치 오버라이드(HUD처럼 free-position 부모용). 없으면 폭 100%(UIListLayout 부모용).

local PromoCarousel = {}

-- 공용 프로모 데이터 (passId 있으면 실물 게임패스, 없으면 더미)
-- ⚠ passId가 없으면 클릭 시 "Coming soon"만 뜨고 구매가 안 됨. 실물 패스는 반드시 채울 것.
PromoCarousel.PROMOS = {
	{ passId = 1713666153, name = "Frost Dragon",     perk = "Exclusive dragon King item",         price = "R$ 300" },
	{ name = "2x Coins",          perk = "Double all round rewards, forever",     price = "R$ 399", icon = "rbxassetid://109002720549611", passId = 1905787000 },
	{ name = "VIP",               perk = "Gold name & tag, 2 map votes, +2 slots", price = "R$ 299", passId = 1906860989 },
}

local NAVY_CARD = Color3.fromRGB(26, 34, 54)
local TEXT_MAIN = Color3.fromRGB(235, 240, 255)
local TEXT_SUB  = Color3.fromRGB(150, 160, 185)
local GREEN     = Color3.fromRGB(46, 178, 80)

-- ── 보유 필터 ────────────────────────────────────────────────
-- 이미 산 패스를 광고하는 건 슬롯 낭비 + "View" 누르면 "이미 보유중" 팝업만 뜨는 막다른 길.
-- passId 없는 더미는 판정 불가라 항상 노출.
local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")

-- 클라 스크립트들(RobuxStoreClient / HudButtonClient)이 같은 모듈 인스턴스를 공유하므로 캐시도 공유됨.
local ownedCache = {}

local function ownsPass(passId)
	local lp = Players.LocalPlayer
	if not lp then return false end            -- 서버에서 require된 경우 방어
	if ownedCache[passId] == nil then
		local ok, res = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(lp.UserId, passId)
		end)
		ownedCache[passId] = (ok and res) or false
	end
	return ownedCache[passId]
end

if Players.LocalPlayer then
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
		if purchased and plr == Players.LocalPlayer then ownedCache[passId] = true end
	end)
end

function PromoCarousel.filterOwned(promos)
	local out = {}
	for _, p in ipairs(promos) do
		if not (p.passId and ownsPass(p.passId)) then
			table.insert(out, p)
		end
	end
	-- 전부 보유 → 빈 캐러셀(UIPageLayout 0페이지 + 점 인디케이터 폭 0)이 되므로 원본으로 폴백.
	if #out == 0 then return promos end
	return out
end

local function promoIcon(promo)
	return promo.passId and ("rbxthumb://type=GamePass&id=" .. promo.passId .. "&w=150&h=150") or (promo.icon or "")
end

-- 넓은 카드 (상점 상단): 아이콘 + 이름 + 퍽 + 가격태그 (가로)
local function makeWidePage(promo, index)
	local page = Instance.new("TextButton")
	page.Name = "Promo_" .. index
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundColor3 = NAVY_CARD
	page.AutoButtonColor = false
	page.Text = ""
	page.LayoutOrder = index
	Instance.new("UICorner", page).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
	icon.Size = UDim2.fromOffset(46, 46)
	icon.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
	icon.Parent = page
	Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 8)
	local iconImg = Instance.new("ImageLabel")
	iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImg.Position = UDim2.fromScale(0.5, 0.5)
	iconImg.Size = UDim2.fromScale(1 - (promo.iconInset or 0), 1 - (promo.iconInset or 0))
	iconImg.BackgroundTransparency = 1
	iconImg.Image = promoIcon(promo)
	iconImg.ScaleType = Enum.ScaleType.Fit
	iconImg.Parent = icon

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Position = UDim2.new(0, 72, 0, 14)
	nameLbl.Size = UDim2.new(1, -168, 0, 22)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.Text = promo.name
	nameLbl.TextColor3 = TEXT_MAIN
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextScaled = true
	nameLbl.Parent = page
	local nc = Instance.new("UITextSizeConstraint"); nc.MaxTextSize = 16; nc.Parent = nameLbl

	local perk = Instance.new("TextLabel")
	perk.Position = UDim2.new(0, 72, 0, 38)
	perk.Size = UDim2.new(1, -168, 0, 16)
	perk.BackgroundTransparency = 1
	perk.Font = Enum.Font.Gotham
	perk.Text = promo.perk
	perk.TextColor3 = TEXT_SUB
	perk.TextXAlignment = Enum.TextXAlignment.Left
	perk.TextScaled = true
	perk.Parent = page
	local pc = Instance.new("UITextSizeConstraint"); pc.MaxTextSize = 12; pc.Parent = perk

	local tag = Instance.new("TextLabel")
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, -16, 0.5, 0)
	tag.Size = UDim2.fromOffset(70, 30)
	tag.BackgroundColor3 = GREEN
	tag.Font = Enum.Font.GothamBold
	tag.Text = promo.price or "View"
	tag.TextColor3 = Color3.fromRGB(255, 255, 255)
	tag.TextScaled = true
	tag.Parent = page
	Instance.new("UICorner", tag).CornerRadius = UDim.new(0, 6)
	local tc = Instance.new("UITextSizeConstraint"); tc.MaxTextSize = 13; tc.Parent = tag

	return page
end

-- 컴팩트 카드 (HUD 배너): 아이콘(왼쪽) + 이름(오른쪽), 가로 — 짧은 높이에도 안 겹침
local function makeCompactPage(promo, index)
	local page = Instance.new("TextButton")
	page.Name = "Promo_" .. index
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundColor3 = NAVY_CARD
	page.AutoButtonColor = false
	page.Text = ""
	page.LayoutOrder = index
	Instance.new("UICorner", page).CornerRadius = UDim.new(0, 10)

	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.Size = UDim2.fromOffset(30, 30)
	icon.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
	icon.Parent = page
	Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 6)
	local iconImg = Instance.new("ImageLabel")
	iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImg.Position = UDim2.fromScale(0.5, 0.5)
	iconImg.Size = UDim2.fromScale(1 - (promo.iconInset or 0), 1 - (promo.iconInset or 0))
	iconImg.BackgroundTransparency = 1
	iconImg.Image = promoIcon(promo)
	iconImg.ScaleType = Enum.ScaleType.Fit
	iconImg.Parent = icon

	local nameLbl = Instance.new("TextLabel")
	nameLbl.AnchorPoint = Vector2.new(0, 0.5)
	nameLbl.Position = UDim2.new(0, 44, 0.5, 0)
	nameLbl.Size = UDim2.new(1, -50, 0.7, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.Text = promo.name
	nameLbl.TextColor3 = TEXT_MAIN
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextScaled = true
	nameLbl.Parent = page
	local nc = Instance.new("UITextSizeConstraint"); nc.MaxTextSize = 14; nc.Parent = nameLbl

	return page
end

function PromoCarousel.makeCarousel(parent, opts)
	opts = opts or {}
	local promos = opts.promos or PromoCarousel.PROMOS
	-- 보유한 패스 제외 (opts.filterOwned = false 로 끌 수 있음)
	-- ⚠ yield 발생(UserOwnsGamePassAsync). 캐러셀은 시작 시 1회 빌드라 게임플레이엔 영향 없음.
	--   빌드 후 구매한 건 반영 안 됨(재접속 시 사라짐) — 캐러셀은 재빌드하지 않으므로.
	if opts.filterOwned ~= false then
		promos = PromoCarousel.filterOwned(promos)
	end
	local height = opts.height or 96
	local autoSec = opts.autoSec or 4
	local compact = opts.compact == true

	local container = Instance.new("Frame")
	container.Name = "PromoCarousel"
	container.Size = opts.size or UDim2.new(1, 0, 0, height)
	if opts.position then container.Position = opts.position end
	container.BackgroundTransparency = 1
	container.LayoutOrder = opts.layoutOrder or 0
	container.Parent = parent

	-- 뷰포트(클립) — 카드 영역 (하단 점 인디케이터 공간 12px 남김)
	local dotH = 12
	local viewH = height - dotH
	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.new(1, 0, 0, viewH)
	viewport.BackgroundTransparency = 1
	viewport.ClipsDescendants = true
	viewport.Parent = container

	local pageLayout = Instance.new("UIPageLayout")
	pageLayout.FillDirection = Enum.FillDirection.Horizontal
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Circular = true
	pageLayout.TouchInputEnabled = true
	pageLayout.GamepadInputEnabled = false
	pageLayout.ScrollWheelInputEnabled = false
	pageLayout.EasingStyle = Enum.EasingStyle.Quad
	pageLayout.EasingDirection = Enum.EasingDirection.Out
	pageLayout.TweenTime = 0.4
	pageLayout.Padding = UDim.new(0, 0)
	pageLayout.Parent = viewport

	for i, promo in ipairs(promos) do
		local page = compact and makeCompactPage(promo, i) or makeWidePage(promo, i)
		page.Parent = viewport
		page.MouseButton1Click:Connect(function()
			if opts.onClick then opts.onClick(promo) end
		end)
	end

	-- 점 인디케이터 (container 자식 — pageLayout 영향 밖)
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.AnchorPoint = Vector2.new(0.5, 1)
	dots.Position = UDim2.new(0.5, 0, 1, 0)
	dots.Size = UDim2.new(0, #promos * 13, 0, dotH)
	dots.BackgroundTransparency = 1
	dots.Parent = container
	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dotLayout.Padding = UDim.new(0, 5)
	dotLayout.Parent = dots
	local dotObjs = {}
	for i = 1, #promos do
		local d = Instance.new("Frame")
		d.Name = "Dot" .. i
		d.Size = UDim2.fromOffset(6, 6)
		d.BackgroundColor3 = Color3.fromRGB(90, 100, 125)
		d.BorderSizePixel = 0
		d.LayoutOrder = i
		d.Parent = dots
		Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		dotObjs[i] = d
	end
	local function updateDots(idx)
		for i, d in ipairs(dotObjs) do
			d.BackgroundColor3 = (i == idx) and Color3.fromRGB(230, 235, 255) or Color3.fromRGB(90, 100, 125)
		end
	end
	updateDots(1)

	local lastInteract = os.clock()

	-- 좌우 화살표 (넓은 모드만). container 자식 = pageLayout 영향 밖, 뷰포트 세로 중앙 오버레이
	if not compact then
		local function arrow(txt, ax, px, edge)
			local a = Instance.new("TextButton")
			a.Size = UDim2.fromOffset(24, 40)
			a.AnchorPoint = Vector2.new(ax, 0.5)
			a.Position = UDim2.new(px, edge, 0, viewH / 2)
			a.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			a.BackgroundTransparency = 0.55
			a.Text = txt
			a.Font = Enum.Font.GothamBold
			a.TextColor3 = Color3.fromRGB(255, 255, 255)
			a.TextSize = 20
			a.ZIndex = 5
			a.Parent = container
			Instance.new("UICorner", a).CornerRadius = UDim.new(0, 6)
			return a
		end
		local leftArrow  = arrow("<", 0, 0, 4)
		local rightArrow = arrow(">", 1, 1, -4)
		leftArrow.MouseButton1Click:Connect(function() lastInteract = os.clock(); pageLayout:Previous() end)
		rightArrow.MouseButton1Click:Connect(function() lastInteract = os.clock(); pageLayout:Next() end)
	end

	-- 페이지 정착 시 점 갱신 + 자동순환 타이머 리셋(스와이프 포함)
	pageLayout.Stopped:Connect(function(currentPage)
		lastInteract = os.clock()
		if currentPage then updateDots(currentPage.LayoutOrder) end
	end)

	-- 4초 자동순환
	task.spawn(function()
		while container.Parent do
			task.wait(1)
			if os.clock() - lastInteract >= autoSec then
				lastInteract = os.clock()
				pageLayout:Next()
			end
		end
	end)

	return container
end

return PromoCarousel
