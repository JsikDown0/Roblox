-- RareSkinRewardCard — rare 상자 보상 스킨 카드 토스트 (서버 RareSkinReward 수신)
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local player      = Players.LocalPlayer
local playerGui   = player:WaitForChild("PlayerGui")
local rewardEvent = ReplicatedStorage:WaitForChild("RareSkinReward")
local ConfettiEffect = require(ReplicatedStorage:WaitForChild("ConfettiEffect"))
local PickupConfig = require(ReplicatedStorage:WaitForChild("PickupConfig"))

-- 조명 파이프라인 프리워밍 (첫 PointLight가 렌더에서 누락되는 현상 방지 — 클라 로컬)
task.spawn(function()
	local warmPart = Instance.new("Part")
	warmPart.Anchored = true; warmPart.CanCollide = false; warmPart.Transparency = 1; warmPart.CastShadow = false
	warmPart.Size = Vector3.new(1, 1, 1)
	warmPart.CFrame = CFrame.new(0, -800, 0)   -- 멀리 아래 (안 보임)
	local warmLight = Instance.new("PointLight")
	warmLight.Brightness = 8; warmLight.Range = 40; warmLight.Shadows = false
	warmLight.Parent = warmPart
	warmPart.Parent = workspace
	task.delay(2.5, function() warmPart:Destroy() end)
end)

-- 사운드 프리로드 (첫 재생 지연 방지 — 킬이펙트 사운드 미리 캐시)
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local SoundService = game:GetService("SoundService")
	local soundIds = {
		"rbxassetid://127362823754161",  -- Sword Rain
		"rbxassetid://75422951",         -- Hellfire
		"rbxassetid://8482764467",       -- Rainbow
		-- Ascendant(Vishnu) 전용 사운드 (장착 지연 방지)
		"rbxassetid://105841275801305",  -- 장착음
		"rbxassetid://102162470318254",  -- 스윙/그랩음
	}
	-- Ascendant(Vishnu) push god effect 텍스처 (첫 버스트 빈 파티클 방지)
	-- ⚠ 텍스처는 ImageLabel로 프리로드 (Sound로 로드하면 "Asset type mismatch" 에러)
	local textureIds = {
		"rbxassetid://13278756202",  -- Scream
		"rbxassetid://10357952493",  -- Vortex
		"rbxassetid://12994153008",  -- OuterHeat
		"rbxassetid://12681289795",  -- Scream2
		"rbxassetid://8451174579",   -- Glow
		"rbxassetid://10598374841",  -- Mouthglow
		"rbxassetid://6032245879",   -- Specs
		"rbxassetid://547900945",    -- Heat
	}
	local assets = {}
	for _, id in ipairs(soundIds) do
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Parent = SoundService
		assets[#assets + 1] = snd
	end
	for _, id in ipairs(textureIds) do
		local img = Instance.new("ImageLabel")
		img.Image = id
		assets[#assets + 1] = img
	end
	pcall(function() ContentProvider:PreloadAsync(assets) end)
	for _, a in ipairs(assets) do a:Destroy() end
end)

local RARITY_COLOR = {
	Normal    = Color3.fromRGB(210, 210, 210),
	Rare      = Color3.fromRGB(80, 200, 90),
	Epic      = Color3.fromRGB(170, 95, 240),
	Legendary = Color3.fromRGB(255, 180, 30),
}

-- ── 썸네일 카메라 튜닝값 ─────────────────────────────────────────
-- PreviewTunerClient(P키)로 카드 뷰포트를 맞춘 뒤, 콘솔의 [TUNE-OUT] 값을 여기에 입력.
-- 등록 안 된 무기는 자동(바운딩박스 × DEFAULT_DIST)으로 잡힘.
local DEFAULT_DIST = 2.1
local DEFAULT_DIR  = Vector3.new(0.45, 0.35, 0.9)
local PER_WEAPON_CAM = {
	-- [무기id] = { dist = DistMul, dir = Vector3.new(x,y,z), target = Vector3.new(x,y,z) },
	-- 예: ClassicSword = { dist = 1.80, dir = Vector3.new(0.300, 0.250, 1.000), target = Vector3.new(0.00, 0.10, 0.00) },
	tnt          = { dist = 1.40, dir = Vector3.new( 0.450, 0.350, 0.900), target = Vector3.new(-0.150, -0.150, -0.100) },
	bear_trap    = { dist = 1.80, dir = Vector3.new( 0.250, 0.750, 0.900), target = Vector3.new( 0.000, -0.200,  0.000) },
	KatanaSword2 = { dist = 0.90, dir = Vector3.new( 0.550, 0.350, 1.000), target = Vector3.new(-0.100, -0.100,  0.000) },
	HammerHigh   = { dist = 0.70, dir = Vector3.new(-0.050, 0.350, 0.900), target = Vector3.new( 0.250, -0.300,  0.000) },
	PushTool     = { dist = 1.00, dir = Vector3.new( 1.450, 0.350, 0.900), target = Vector3.new(-0.150,  0.000,  0.000) },
	ClassicSword = { dist = 0.90, dir = Vector3.new( 1.950, 0.350, 0.900), target = Vector3.new( 0.000,  0.050,  0.000) },
	Spear        = { dist = 0.30, dir = Vector3.new( 0.350, 0.350, 0.000), target = Vector3.new( 0.000,  0.350,  0.000) },
	RainbowSpear = { dist = 0.30, dir = Vector3.new( 0.350, 0.350, 0.000), target = Vector3.new( 0.000,  0.350,  0.000) },  -- 색놀이 스피어와 동일
	HammerLow    = { dist = 1.60, dir = Vector3.new( 0.550, 0.750, 0.400), target = Vector3.new(-0.050,  0.000,  0.000) },
	SakuraBlade  = { dist = 1.40, dir = Vector3.new( 0.450, 0.350, 0.900), target = Vector3.new(-0.100, -0.050,  0.000) },
	Gauntlet     = { dist = 0.30, dir = Vector3.new( 2.950, 3.450, -4.800), target = Vector3.new( 0.000,  0.000,  0.000) },
	tsunami      = { dist = 2.10, dir = Vector3.new( 0.450, 0.350, 0.900), target = Vector3.new(-0.100, -0.100,  0.000) },
	SummerNoob   = { dist = 0.30, dir = Vector3.new( 3.550, 0.350, -9.500), target = Vector3.new( 0.000,  0.000,  0.000) },  -- 튜닝값 dist 0.40 → 더 가깝게
	SuitNoob     = { dist = 1.20, dir = Vector3.new( 1.550, 0.350,  0.400), target = Vector3.new( 0.000,  0.000,  0.000) },
	Demonspear   = { dist = 0.80, dir = Vector3.new( 2.050, 0.350,  0.900), target = Vector3.new( 0.000,  0.050,  0.000) },
}

-- 색/효과 결정: rainbow/cycle(순환) → solidHSV → color → 이름 기반 추론(특수 스킨)
local function resolveStyle(d)
	local n = ((d.skinName or "") .. " " .. (d.display or "")):lower()
	if d.cycle or d.rainbow or n:find("rainbow") then return nil, true end
	if d.solidHSV then return Color3.fromHSV(d.solidHSV[1], d.solidHSV[2], d.solidHSV[3]), false end
	if d.color then return Color3.fromRGB(d.color[1], d.color[2], d.color[3]), false end
	if n:find("demon")  then return Color3.fromRGB(135, 30, 205), false end
	if n:find("lava")   then return Color3.fromRGB(255, 85, 20),  false end
	if n:find("white") and n:find("flame") then return Color3.fromRGB(205, 230, 255), false end
	if n:find("flame")  then return Color3.fromRGB(255, 145, 35), false end
	return nil, false
end

-- 모델 파트에 색/효과 입히기 (SpecialMesh는 VertexColor가 색 결정)
local function paintModel(clone, styleColor, styleCycle, skinMat)
	local function paintPart(p, c)
		p.Color = c
		if p:IsA("MeshPart") then p.TextureID = "" end
		local sm = p:FindFirstChildWhichIsA("SpecialMesh")
		if sm then sm.TextureId = ""; sm.VertexColor = Vector3.new(c.R, c.G, c.B) end
	end
	if not (styleColor or styleCycle) then return end
	local parts = {}
	local function collect(p)
		if p:IsA("BasePart") then
			if styleCycle then p.Material = Enum.Material.Neon
			elseif skinMat then p.Material = skinMat end
			local sa = p:FindFirstChildWhichIsA("SurfaceAppearance")
			if sa then sa:Destroy() end  -- PBR 텍스처가 Color를 덮지 않게 제거(tnt 등)
			parts[#parts+1] = p
		end
	end
	if clone:IsA("BasePart") then collect(clone) end  -- 단일 Part 스킨(RainbowStone/RainbowSpear)
	for _, p in ipairs(clone:GetDescendants()) do collect(p) end
	if styleCycle then
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not clone.Parent then conn:Disconnect(); return end
			local c = Color3.fromHSV((os.clock() - t0) * 0.35 % 1, 0.85, 1)
			for _, p in ipairs(parts) do paintPart(p, c) end
		end)
	elseif styleColor then
		for _, p in ipairs(parts) do paintPart(p, styleColor) end
	end
end

-- 뷰포트에 모델 + 카메라 세팅 (PreviewTunerClient 호환: 이름 _ItemVP + PreviewId)
local function makeViewport(parent, model, id)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "_ItemVP"
	vp.Size = UDim2.fromScale(1, 1)
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.BackgroundTransparency = 1
	vp.LightDirection = Vector3.new(-1, -2, -1)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.Ambient = Color3.fromRGB(140, 140, 170)
	vp:SetAttribute("PreviewId", id or "?")
	vp.Parent = parent
	local clone = model:Clone()
	clone.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cfg = PER_WEAPON_CAM[id]
	local distMul = (cfg and cfg.dist) or DEFAULT_DIST
	local dir = (cfg and cfg.dir) or DEFAULT_DIR
	local target = (cfg and cfg.target) or Vector3.new(0, 0, 0)
	vp:SetAttribute("_tuneDist", distMul)
	vp:SetAttribute("_tuneDir", dir)
	vp:SetAttribute("_tuneTarget", target)
	local center, size
	if clone:IsA("Model") then
		-- Orbiter(궤도 이펙트: 뷰포트에선 정지해 bbox를 크게 오염)만 임시 제거 후 실제 bbox
		local hidden = {}
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") and string.find(p.Name, "Orbiter") then
				hidden[#hidden + 1] = { p, p.Parent }
				p.Parent = nil
			end
		end
		local cf, sz = clone:GetBoundingBox()
		center, size = cf.Position, sz
		for _, h in ipairs(hidden) do h[1].Parent = h[2] end
	else
		center, size = clone.Position, clone.Size
	end
	local maxDim = math.max(size.X, size.Y, size.Z)
	local tgt = center + target * maxDim
	cam.CFrame = CFrame.new(tgt + dir * (maxDim * distMul), tgt)
	return vp, clone
end

-- 색 순환/정적 스와치 (작은 원/사각)
local function makeSwatch(parent, styleColor, styleCycle, circular, sizeScale, anchor, pos)
	local sw = Instance.new("Frame")
	sw.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	sw.Position = pos or UDim2.fromScale(0.5, 0.5)
	sw.Size = UDim2.fromScale(sizeScale, sizeScale)
	sw.BackgroundColor3 = styleColor or Color3.fromRGB(255, 255, 255)
	sw.ZIndex = 5
	sw.Parent = parent
	Instance.new("UICorner", sw).CornerRadius = circular and UDim.new(1, 0) or UDim.new(0.18, 0)
	local st = Instance.new("UIStroke", sw)
	st.Color = Color3.fromRGB(255, 255, 255); st.Thickness = 2; st.Transparency = 0.4
	Instance.new("UIAspectRatioConstraint", sw).AspectRatio = 1
	if styleCycle then
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not sw.Parent then conn:Disconnect(); return end
			sw.BackgroundColor3 = Color3.fromHSV((os.clock() - t0) * 0.35 % 1, 0.85, 1)
		end)
	end
	return sw
end

local function showCard(data)
	if type(data) ~= "table" then warn("[RareCard] data가 table이 아님:", data); return end
	print("[RareCard] 수신:", data.display, "/", data.rarity, "/ weapon=", tostring(data.weapon))
	local rarity  = data.rarity or "Normal"
	local color   = RARITY_COLOR[rarity] or RARITY_COLOR.Normal
	local hasIcon = type(data.icon) == "string" and data.icon ~= ""
	local styleColor, styleCycle = resolveStyle(data)
	local skinMat = (data.material and Enum.Material[data.material]) or nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "RareSkinRewardCardGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 101   -- reward card: above the box cutscene (100)
	gui.Parent = playerGui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.4)
	-- [ITEM-GRID] 여러 아이템을 한 번에 보여줄 땐 카드를 넓힌다(3열 그리드가 들어가야 함).
	card.Size = data.itemGrid and UDim2.fromScale(0.40, 0.44) or UDim2.fromScale(0.24, 0.34)
	card.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0.07, 0)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = color; stroke.Thickness = 3
	local uiScale = Instance.new("UIScale", card)
	uiScale.Scale = 0

	local pad = Instance.new("UIPadding", card)
	pad.PaddingTop = UDim.new(0.06,0); pad.PaddingBottom = UDim.new(0.06,0)
	pad.PaddingLeft = UDim.new(0.08,0); pad.PaddingRight = UDim.new(0.08,0)
	local layout = Instance.new("UIListLayout", card)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.03, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local header = Instance.new("TextLabel")
	header.LayoutOrder = 1; header.Size = UDim2.fromScale(1, 0.13)
	header.BackgroundTransparency = 1
	-- [STARTER-KIT] data.header 가 있으면 그걸 우선 쓴다.
	--   소모품 맛보기처럼 스킨/코스메틱이 아닌 지급에도 이 카드를 재사용하기 위함.
	header.Text = data.header
		or ((data.kind == "cosmetic") and "COSMETIC UNLOCKED!"
		or (data.itemColorName or data.gcolorName) and "COLOR UNLOCKED!"
		or "SKIN UNLOCKED!")
	header.Font = Enum.Font.GothamBlack; header.TextColor3 = color; header.TextScaled = true
	header.Parent = card

	local iconHolder = Instance.new("Frame")
	iconHolder.LayoutOrder = 2
	-- [ITEM-GRID] 그리드 모드에선 정사각 아이콘 대신 가로로 넓은 영역을 쓴다.
	iconHolder.Size = data.itemGrid and UDim2.fromScale(1, 0.52) or UDim2.fromScale(0.62, 0.46)
	iconHolder.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	iconHolder.BackgroundTransparency = hasIcon and 1 or 0.25
	iconHolder.Parent = card
	Instance.new("UICorner", iconHolder).CornerRadius = UDim.new(0.1, 0)
	-- [ITEM-GRID] 그리드 모드에선 정사각 강제를 걸지 않는다(가로로 넓어야 3열이 들어감).
	if not data.itemGrid then
		Instance.new("UIAspectRatioConstraint", iconHolder).AspectRatio = 1
	end

	-- [ITEM-GRID] 여러 아이템 썸네일을 격자로 표시하고 나머지 분기는 건너뛴다.
	--   data.itemGrid = { "Speed Potion", "Wood Shield", ... } (RunnerItemPreviews 의 모델명)
	if data.itemGrid then
		iconHolder.BackgroundTransparency = 0.25
		local grid = Instance.new("UIGridLayout", iconHolder)
		grid.CellSize = UDim2.fromScale(0.30, 0.30)
		grid.CellPadding = UDim2.fromScale(0.02, 0.03)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		local gpad = Instance.new("UIPadding", iconHolder)
		gpad.PaddingTop = UDim.new(0.04, 0); gpad.PaddingBottom = UDim.new(0.04, 0)
		gpad.PaddingLeft = UDim.new(0.03, 0); gpad.PaddingRight = UDim.new(0.03, 0)

		local previews = ReplicatedStorage:FindFirstChild("RunnerItemPreviews")
		for idx, itemName in ipairs(data.itemGrid) do
			local cell = Instance.new("Frame")
			cell.LayoutOrder = idx
			cell.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
			cell.BackgroundTransparency = 0.2
			cell.Parent = iconHolder
			Instance.new("UICorner", cell).CornerRadius = UDim.new(0.15, 0)
			-- ⚠️ RunnerItemPreviews 는 이름 대소문자가 섞여 있다(Wood Shield / wood Shield).
			--    정확히 못 찾으면 대소문자 무시로 한 번 더 훑는다.
			local model = previews and previews:FindFirstChild(itemName)
			if not model and previews then
				for _, m in ipairs(previews:GetChildren()) do
					if m.Name:lower() == itemName:lower() then model = m break end
				end
			end
			if model then
				makeViewport(cell, model, "kit_" .. itemName)
			else
				local q = Instance.new("TextLabel", cell)
				q.Size = UDim2.fromScale(1, 1); q.BackgroundTransparency = 1
				q.Text = "?"; q.TextScaled = true; q.Font = Enum.Font.GothamBold
				q.TextColor3 = Color3.fromRGB(150, 150, 160)
			end
			-- 수량 배지
			if data.itemCount then
				local badge = Instance.new("TextLabel", cell)
				badge.AnchorPoint = Vector2.new(1, 1)
				badge.Position = UDim2.fromScale(0.97, 0.97)
				badge.Size = UDim2.fromScale(0.42, 0.28)
				badge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				badge.BackgroundTransparency = 0.25
				badge.Text = "x" .. tostring(data.itemCount)
				badge.Font = Enum.Font.GothamBold
				badge.TextColor3 = Color3.fromRGB(255, 235, 140)
				badge.TextScaled = true
				badge.ZIndex = 5
				Instance.new("UICorner", badge).CornerRadius = UDim.new(0.35, 0)
			end
		end
	elseif true then
	-- [ITEM-GRID] 위 그리드 모드가 아니면 기존 단일 썸네일 로직을 그대로 탄다.
	--   (elseif true 는 아래 원본 블록의 들여쓰기를 건드리지 않기 위한 것)

	local skinPreviews = ReplicatedStorage:FindFirstChild("SkinPreviews")
	-- 전용 모델 스킨(KingNoob/SunStone 등): skinName으로 먼저 찾음. 없으면 무기 원본(색놀이용)
	local dedicated   = skinPreviews and data.skinName and skinPreviews:FindFirstChild(data.skinName)
	local weaponModel = skinPreviews and data.weapon and skinPreviews:FindFirstChild(data.weapon)
	print(string.format("[RareCard분기] weapon=%s weaponModel=%s icon=[%s] gcolor=%s", tostring(data.weapon), tostring(weaponModel ~= nil), tostring(data.icon), tostring(data.gcolorName)))

	if data.kind == "cosmetic" then
		-- 코스메틱 썸네일: 종류별 분기 (트레일=리본 / 대시=아이콘 / 크라운=모델 / 킬=이미지 or 이모지)
		local cat = data.category
		local done = false
		if cat == "trailSkin" and _G.LP_makeTrailRibbon then
			done = _G.LP_makeTrailRibbon(iconHolder, data.id)
			local rib = iconHolder:FindFirstChild("_TrailRibbon")
			if rib then rib.ZIndex = 3 end   -- 리본은 ZIndex 0 생성(인벤 슬롯용) → 카드 배경 위로
		elseif cat == "dashSkin" and _G.LP_makeDashIcon then
			done = _G.LP_makeDashIcon(iconHolder, data.id)
			local di = iconHolder:FindFirstChild("_DashIcon")
			if di then di.ZIndex = 3 end
		elseif cat == "crownSkin" then
			local cp = ReplicatedStorage:FindFirstChild("CrownPreviews")
			local model = cp and data.skinKey and cp:FindFirstChild(data.skinKey)
			if model then makeViewport(iconHolder, model, "crown_" .. tostring(data.skinKey)); done = true end
		elseif cat == "killEffect" then
			if type(data.imageId) == "string" and data.imageId ~= "" then
				local img = Instance.new("ImageLabel", iconHolder)
				img.Size = UDim2.fromScale(1,1); img.BackgroundTransparency = 1
				img.Image = data.imageId; img.ScaleType = Enum.ScaleType.Fit
				done = true
			end
		end
		-- 폴백: 절차적/이미지 실패 시 이모지 텍스트 (imageId 없는 킬이펙트 등)
		if not done then
			local emo = Instance.new("TextLabel", iconHolder)
			emo.Size = UDim2.fromScale(1,1); emo.BackgroundTransparency = 1
			emo.Text = (type(data.icon) == "string" and data.icon ~= "") and data.icon or "★"
			emo.TextScaled = true; emo.Font = Enum.Font.GothamBold
			emo.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	elseif hasIcon then
		local img = Instance.new("ImageLabel", iconHolder)
		img.Size = UDim2.fromScale(1,1); img.BackgroundTransparency = 1
		img.Image = data.icon; img.ScaleType = Enum.ScaleType.Fit
	elseif dedicated then
		-- 전용 모델 스킨(KingNoob/SunStone 등): 모델 그대로 표시. 순환 계열만 Neon 순환
		local _, clone = makeViewport(iconHolder, dedicated, data.skinName)
		if styleCycle then paintModel(clone, nil, true, nil) end
	elseif weaponModel then
		-- 무기 3D 뷰포트 + 스킨 색(색놀이)
		local _, clone = makeViewport(iconHolder, weaponModel, data.weapon)
		paintModel(clone, styleColor, styleCycle, skinMat)
		-- 무기색 보상(icolor): 우상단 색 스와치 (건틀릿과 동일 UI)
		if data.itemColorName then
			makeSwatch(iconHolder, styleColor, styleCycle, true, 0.32, Vector2.new(1, 0), UDim2.fromScale(0.98, 0.02))
		end
	elseif data.gcolorName then
		-- 건틀릿: 중앙 건틀릿 모델 + 우상단 색 팔레트 아이콘
		local rip = ReplicatedStorage:FindFirstChild("RunnerItemPreviews")
		local gModel = rip and rip:FindFirstChild("Gauntlet")
		if gModel then
			makeViewport(iconHolder, gModel, "Gauntlet")
		end
		-- 색 팔레트 아이콘 (우상단, 원형, 작게)
		makeSwatch(iconHolder, styleColor, styleCycle, true, 0.32, Vector2.new(1, 0), UDim2.fromScale(0.98, 0.02))
	elseif styleColor or styleCycle then
		-- 무기/건틀릿 아님 → 색 스와치 (중앙)
		makeSwatch(iconHolder, styleColor, styleCycle, false, 0.72)
	else
		local star = Instance.new("TextLabel", iconHolder)
		star.Size = UDim2.fromScale(1,1); star.BackgroundTransparency = 1
		star.Text = "★"; star.TextColor3 = color; star.TextScaled = true
		star.Font = Enum.Font.GothamBold
	end
	end   -- [ITEM-GRID] 바깥 분기(itemGrid / 기존 로직) 닫기

	local nameLabel = Instance.new("TextLabel")
	nameLabel.LayoutOrder = 3; nameLabel.Size = UDim2.fromScale(1, 0.16)
	nameLabel.BackgroundTransparency = 1; nameLabel.Text = tostring(data.display or "???")
	nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
	nameLabel.TextScaled = true; nameLabel.Parent = card

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.LayoutOrder = 4; rarityLabel.Size = UDim2.fromScale(1, 0.10)
	rarityLabel.BackgroundTransparency = 1; rarityLabel.Text = string.upper(rarity)
	rarityLabel.Font = Enum.Font.GothamMedium; rarityLabel.TextColor3 = color
	rarityLabel.TextScaled = true; rarityLabel.Parent = card

	-- 애니: 팝인(Back) → 유지 → 스케일 아웃 (튜너 켜져 있으면 유지)
	--   [ITEM-GRID] 그리드 모드는 볼 게 9개라 2.6초로는 다 못 훑는다. 더 길게 준다.
	local HOLD = data.itemGrid and 6.0 or 2.6
	TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(HOLD, function()
		while _G.previewTunerActive do task.wait(0.4) end
		TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.32) }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.4)
		gui:Destroy()
	end)
end

-- RareSkinReward 핸들러는 아래(playBoxThenCard 정의 뒤)에서 연결
print("[RareCard] 준비 완료 — RareSkinReward 수신 대기")

-- ══ 상자 열림 컷신 (Skin Box 보상용) → 끝나면 showCard ══════════════
local function playBoxThenCard(data, onDone)
	onDone = onDone or function() end
	-- [COSMETIC-BOX-SKIN] 코스메틱 박스는 로벅스샵과 같은 전용 모델을 쓴다.
	--   ⚠️ 예전엔 일반 상자에 색만 입혔는데(아래 변주 블록) 형태가 같아 구분이 안 됐다.
	--      전용 모델이 없으면 기존 상자 + 색 변주로 폴백한다.
	local chestTemplate = (data.cosmeticBox and ReplicatedStorage:FindFirstChild("CosmeticBoxPreview"))
		or ReplicatedStorage:FindFirstChild("ItemChestPreview")
	local usingDedicated = (data.cosmeticBox and chestTemplate
		and chestTemplate.Name == "CosmeticBoxPreview") or false
	if not chestTemplate then
		showCard(data)   -- 상자 프리뷰 없으면 카드만
		onDone()
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BoxCutsceneGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100   -- reward cutscene: above battle pass panel (60)
	gui.Parent = playerGui

	local dim = Instance.new("TextButton")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = gui
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()

	local vp = Instance.new("ViewportFrame")
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.45)
	vp.Size = UDim2.fromScale(0.5, 0.55)
	vp.BackgroundTransparency = 1
	vp.LightDirection = Vector3.new(-1, -2, -0.6)
	vp.LightColor = Color3.fromRGB(255, 252, 245)
	vp.Ambient = Color3.fromRGB(120, 122, 135)   -- 78 → 120 (과하게 어두워서 상향, 메탈 대비는 유지)
	vp.Parent = gui
	local vpScale = Instance.new("UIScale", vp)
	vpScale.Scale = 0.2
	TweenService:Create(vpScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local chest = chestTemplate:Clone()
	chest.Parent = vp

	-- 코스메틱 박스: 외형 변주 (바이올렛 우드 + 골드 트림 + 발광 열쇠구멍) — 일반 스킨 박스와 구분
	if data.cosmeticBox and not usingDedicated then
		-- 전용 모델을 못 찾았을 때만 색으로 구분(폴백)
		local WOOD    = Color3.fromRGB(95, 45, 155)
		local METAL   = Color3.fromRGB(255, 200, 60)
		local KEYGLOW = Color3.fromRGB(180, 120, 255)   -- 바이올렛 계열 발광 (통일감 + 대비)
		for _, p in ipairs(chest:GetDescendants()) do
			if p:IsA("BasePart") then
				if p:IsA("UnionOperation") then p.UsePartColor = true end
				local n = p.Name
				if n == "WoodTop" or n == "WoodBottom" then
					p.Color = WOOD
					p.Material = Enum.Material.SmoothPlastic
				elseif n == "KeyHole" then
					p.Color = KEYGLOW
					p.Material = Enum.Material.Neon   -- 발광 → 골드 트림에 안 묻힘
				elseif n == "MetalTop" or n == "MetalBottom" then
					p.Color = METAL
					p.Material = Enum.Material.Metal
				end
			end
		end
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam

	local cf, size = chest:GetBoundingBox()
	local center = cf.Position
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dir = Vector3.new(0.4, 0.45, -1).Unit
	local wbF, wtF = chest:FindFirstChild("WoodBottom"), chest:FindFirstChild("WoodTop")
	if wbF and wtF then
		center = (wbF.Position + wtF.Position) / 2   -- 안 보이는 root 제외한 시각 중심
		local wc = wbF.CFrame   -- 상자 자체 방향 기준 (월드 회전 무관하게 앞면 보기)
		dir = (wc.LookVector * 0.85 + wc.UpVector * 0.5 + wc.RightVector * 0.32).Unit
	end
	cam.CFrame = CFrame.new(center + dir * (maxDim * 1.9), center)

	-- Lid 힌지 열림 준비 (Item Chest: WoodTop + 자식들을 WoodBottom 상단-뒤 모서리로 회전)
	local woodTop = chest:FindFirstChild("WoodTop")
	local woodBottom = chest:FindFirstChild("WoodBottom")
	local lidParts, lidPivot = {}, nil
	if woodTop and woodBottom then
		lidParts[#lidParts + 1] = woodTop
		for _, d in ipairs(woodTop:GetDescendants()) do
			if d:IsA("BasePart") then lidParts[#lidParts + 1] = d end
		end
		lidPivot = woodBottom.CFrame * CFrame.new(0, woodBottom.Size.Y / 2, woodBottom.Size.Z / 2)
	end

	-- "탭하여 열기" 프롬프트
	local prompt = Instance.new("TextLabel")
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.fromScale(0.5, 0.86)
	prompt.Size = UDim2.fromScale(0.7, 0.07)
	prompt.BackgroundTransparency = 1
	prompt.Font = Enum.Font.GothamBold
	prompt.Text = "Tap to open!"
	prompt.TextColor3 = Color3.fromRGB(255, 255, 255)
	prompt.TextScaled = true
	prompt.TextStrokeTransparency = 0.4
	prompt.Parent = gui
	TweenService:Create(prompt, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.5 }):Play()

	-- 클릭/탭하면 열림 (안전장치: 20초 후 자동)
	local opened = false
	local function openChest()
		if opened then return end
		opened = true
		if prompt.Parent then prompt:Destroy() end

		if lidPivot then
			local ang = math.rad(PickupConfig.CHEST_OPEN_ANGLE_DEG or 100)
			local info = TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			for _, part in ipairs(lidParts) do
				if part.Parent then
					local openCF = lidPivot * CFrame.Angles(ang, 0, 0) * lidPivot:Inverse() * part.CFrame
					TweenService:Create(part, info, { CFrame = openCF }):Play()
				end
			end
		end
		local s = Instance.new("Sound")
		s.SoundId = PickupConfig.SOUND_OPEN_NORMAL
		s.Volume = 0.8
		s.Parent = gui
		s:Play()
		game:GetService("Debris"):AddItem(s, 4)

		task.delay(1.2, function()
			if not gui.Parent then onDone(); return end
			local flash = Instance.new("Frame")
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			flash.BackgroundTransparency = 1
			flash.ZIndex = 10
			flash.Parent = gui
			TweenService:Create(flash, TweenInfo.new(0.16), { BackgroundTransparency = 0.1 }):Play()
			task.wait(0.16)
			showCard(data)   -- 기존 카드 팝업 (별도 gui, DisplayOrder 60)
			ConfettiEffect.play()   -- 팡파레 컨페티 (리워드 수령 연출 재사용)
			TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.wait(0.4)
			gui:Destroy()
			onDone()
		end)
	end

	dim.MouseButton1Click:Connect(openChest)
	task.delay(20, openChest)   -- 큐 스톨 방지	-- ⚠️ [ROUND-INTERRUPT] 라운드가 시작되면 즉시 연다.
	--    dim 이 화면 전체를 덮는데 20초 대기라, 그대로 두면 시야가 막힌다
	--    (실측 2026-08-21: Day 7 수령 직후 라운드 시작 → 화면이 가려짐).
	--    ※ 보상은 서버에서 이미 지급 완료(grantRandomSkin). 여기서는 연출만 정리한다.
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(0.2)
			local ph = workspace:GetAttribute("RoundPhase")
			if ph == "stage1" or ph == "stage2" then
				openChest()
				break
			end
		end
	end)
end

-- ══ 회전+펑 컷신 (item box — plus/mega 등급) → 끝나면 showCard ══════
local function playSpinBoxThenCard(data, onDone)
	onDone = onDone or function() end
	local template = ReplicatedStorage:FindFirstChild("MysteryBoxPreview")
	if not template or not template.PrimaryPart then
		showCard(data)
		onDone()
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BoxCutsceneGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Parent = playerGui

	local dim = Instance.new("TextButton")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = gui
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()

	local vp = Instance.new("ViewportFrame")
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.45)
	vp.Size = UDim2.fromScale(0.5, 0.55)
	vp.BackgroundTransparency = 1
	vp.LightDirection = Vector3.new(-1, -2, -1)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.Ambient = Color3.fromRGB(160, 160, 185)
	vp.Parent = gui
	local vpScale = Instance.new("UIScale", vp)
	vpScale.Scale = 0.2
	TweenService:Create(vpScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local box = template:Clone()
	box.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam

	local cf, size = box:GetBoundingBox()
	local center = cf.Position
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dir = Vector3.new(0.4, 0.4, -1).Unit
	cam.CFrame = CFrame.new(center + dir * (maxDim * 2.0), center)
	local baseCF = box.PrimaryPart.CFrame

	local prompt = Instance.new("TextLabel")
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.fromScale(0.5, 0.86)
	prompt.Size = UDim2.fromScale(0.7, 0.07)
	prompt.BackgroundTransparency = 1
	prompt.Font = Enum.Font.GothamBold
	prompt.Text = "Tap to open!"
	prompt.TextColor3 = Color3.fromRGB(255, 255, 255)
	prompt.TextScaled = true
	prompt.TextStrokeTransparency = 0.4
	prompt.Parent = gui
	TweenService:Create(prompt, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.5 }):Play()

	local opened = false
	local function openBox()
		if opened then return end
		opened = true
		if prompt.Parent then prompt:Destroy() end

		local RunService = game:GetService("RunService")
		local SPIN_TIME = 1.3
		local t0 = os.clock()
		local spinConn
		spinConn = RunService.RenderStepped:Connect(function()
			local el = os.clock() - t0
			if el >= SPIN_TIME or not box.PrimaryPart or not box.Parent then
				if spinConn then spinConn:Disconnect(); spinConn = nil end
				return
			end
			local speed = 6 + (el / SPIN_TIME) * 34   -- 가속
			box:PivotTo(baseCF * CFrame.Angles(0, el * speed, math.rad(el * 10)))
		end)

		task.delay(SPIN_TIME, function()
			if spinConn then spinConn:Disconnect(); spinConn = nil end
			if not gui.Parent then onDone(); return end
			vp.Visible = false   -- 박스 펑 (사라짐)

			local s = Instance.new("Sound")
			s.SoundId = PickupConfig.SOUND_OPEN_NORMAL
			s.Volume = 0.9
			s.Parent = gui
			s:Play()
			game:GetService("Debris"):AddItem(s, 4)

			-- 연기 펑 (UI 확장 원 여러 개)
			for i = 1, 9 do
				local sz = 0.06 + math.random() * 0.05
				local puff = Instance.new("Frame")
				puff.AnchorPoint = Vector2.new(0.5, 0.5)
				puff.Position = UDim2.fromScale(0.5, 0.45)
				puff.Size = UDim2.fromScale(sz, sz)
				puff.BackgroundColor3 = Color3.fromRGB(210, 210, 220)
				puff.BackgroundTransparency = 0.15
				puff.ZIndex = 9
				puff.Parent = gui
				Instance.new("UICorner", puff).CornerRadius = UDim.new(1, 0)
				local a = (i / 9) * math.pi * 2 + math.random() * 0.6
				local dist = 0.12 + math.random() * 0.1
				TweenService:Create(puff, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5 + math.cos(a) * dist, 0.45 + math.sin(a) * dist),
					Size = UDim2.fromScale(sz * 2.6, sz * 2.6),
					BackgroundTransparency = 1,
				}):Play()
				game:GetService("Debris"):AddItem(puff, 0.9)
			end

			local flash = Instance.new("Frame")
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			flash.BackgroundTransparency = 1
			flash.ZIndex = 10
			flash.Parent = gui
			TweenService:Create(flash, TweenInfo.new(0.12), { BackgroundTransparency = 0.2 }):Play()

			task.wait(0.48)
			showCard(data)
			ConfettiEffect.play()
			TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.wait(0.4)
			gui:Destroy()
			onDone()
		end)
	end

	dim.MouseButton1Click:Connect(openBox)
	task.delay(20, openBox)	-- ⚠️ [ROUND-INTERRUPT] 라운드가 시작되면 즉시 연다.
	--    dim 이 화면 전체를 덮는데 20초 대기라, 그대로 두면 시야가 막힌다
	--    (실측 2026-08-21: Day 7 수령 직후 라운드 시작 → 화면이 가려짐).
	--    ※ 보상은 서버에서 이미 지급 완료(grantRandomSkin). 여기서는 연출만 정리한다.
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(0.2)
			local ph = workspace:GetAttribute("RoundPhase")
			if ph == "stage1" or ph == "stage2" then
				openBox()
				break
			end
		end
	end)
end

-- 배틀패스 등에서 호출용 (연출 데모 — 실제 지급 없이 컷신만)
_G.playSkinBoxCutscene = function(data)
	playBoxThenCard(data or { kind = "gcolor", display = "Skin Box!", rarity = "Rare", gcolorName = "rainbow", cycle = true })
end

-- RareSkinReward 수신: fromBox 플래그면 상자 컷신, 아니면 카드만 (월드 픽업 등)
-- 박스 컷신 큐: 여러 개가 거의 동시에 와도(Claim All) 하나씩 순차 재생
local boxQueue = {}
local boxPlaying = false
local BOX_CUTSCENE_TIME = 5.2   -- box(~1.9s)+card(appears 1.9s, gone ~4.9s) + gap, so cards don't overlap

local function processBoxQueue()
	if boxPlaying then return end
	local d = table.remove(boxQueue, 1)
	if not d then return end
	boxPlaying = true
	local advance = function()
		boxPlaying = false
		processBoxQueue()
	end
	if d.boxGrade == "plus" or d.boxGrade == "mega" then
		playSpinBoxThenCard(d, advance)   -- Rare+/Epic+ : item box 회전+펑
	else
		playBoxThenCard(d, advance)       -- Basic : 기존 뚜껑 열림
	end
end

rewardEvent.OnClientEvent:Connect(function(data)
	if data and data.fromBox then
		boxQueue[#boxQueue + 1] = data
		processBoxQueue()
	else
		showCard(data)
	end
end)

-- 디버그: /kitcard → 스타터킷 카드 연출만 확인 (지급 없음)
--   ⚠️ 지급 테스트는 /resetkit(서버 채팅 커맨드) 후 인벤을 열어야 한다.
player.Chatted:Connect(function(msg)
	if msg:match("^/kitcard$") then
		playBoxThenCard({
			kind      = "cosmetic",
			header    = "RUNNER STARTER KIT!",
			display   = "8 Runner Items · x2 Each",
			rarity    = "Epic",
			itemGrid  = { "Speed Potion", "Wood Shield", "RevivalFlag",
			              "Gas Grenade", "ODM Gear",
			              "Ice Bow", "Mic Bomb", "Decoy Wand" },
			itemCount = 2,
		})
	end
end)

-- 디버그: /box → 상자 열림 컷신 + 더미 카드 (연출 확인용)
player.Chatted:Connect(function(msg)
	if msg:match("^/box$") then
		playBoxThenCard({ kind = "gcolor", display = "Gauntlet Rainbow", rarity = "Rare", gcolorName = "rainbow", cycle = true })
	end
end)

-- 디버그: /card <무기id> 채팅으로 임의 카드 띄우기 (카메라 튜닝용)
--   예: /card ClassicSword   /card SakuraBlade   /card stone   /card gauntlet
player.Chatted:Connect(function(msg)
	local w = msg:match("^/card%s+(%S+)$")
	if not w then return end
	if w:lower() == "gauntlet" then
		showCard({ kind = "gcolor", display = "Gauntlet Emerald", rarity = "Rare", gcolorName = "emerald", color = {0, 150, 90} })
	else
		showCard({ kind = "skin", display = w, rarity = "Epic", weapon = w })
	end
end)

-- (게임 시작 시 자동 뜨던 테스트 카드 제거됨)
