-- 건틀렛 커스텀 화면 (클라) — 프리뷰 + 부위탭 + 팔레트 + APPLY
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local screen = script.Parent
local vp = screen.WeaponPreview
local tabBar = screen.ZoneTabs
local paletteBar = screen.PaletteBar
local grid = paletteBar.ColorGrid
local selName = paletteBar.SelectedName
local applyBtn = paletteBar.ApplyBtn
local closeBtn = screen.CloseBtn
local remote = ReplicatedStorage:WaitForChild("GauntletColorRemote")

-- ── 팔레트 정의 (서버 모듈과 동일) ──
local PALETTE = {
	black  = Color3.fromRGB(20, 20, 20),    white  = Color3.fromRGB(245, 245, 245),
	gray   = Color3.fromRGB(120, 125, 130), navy   = Color3.fromRGB(27, 42, 53),
	beige  = Color3.fromRGB(254, 243, 187), orange = Color3.fromRGB(170, 85, 0),
	pink   = Color3.fromRGB(255, 80, 180),  red    = Color3.fromRGB(220, 30, 30),
	cyan   = Color3.fromRGB(0, 200, 220),   purple = Color3.fromRGB(160, 60, 255),
	lime    = Color3.fromRGB(80, 230, 60),  emerald = Color3.fromRGB(0, 150, 90),
	yellow  = Color3.fromRGB(255, 225, 40), royal   = Color3.fromRGB(40, 90, 230),
	crimson = Color3.fromRGB(150, 15, 30),
}
-- 표시 순서 + 이름
local COLOR_ORDER = {
	{k="black",  name="BLACK",  paid=false}, {k="white",  name="WHITE",  paid=false},
	{k="gray",   name="GRAY",   paid=false}, {k="navy",   name="NAVY",   paid=false},
	{k="beige",  name="BEIGE",  paid=false}, {k="orange", name="ORANGE", paid=false},
	{k="pink",   name="PINK",   paid=true},  {k="red",    name="RED",    paid=true},
	{k="cyan",   name="CYAN",   paid=true},  {k="purple", name="PURPLE", paid=true},
	{k="lime",    name="LIME",    paid=true},  {k="emerald", name="EMERALD", paid=true},
	{k="yellow",  name="YELLOW",  paid=true},  {k="royal",   name="ROYAL",   paid=true},
	{k="crimson", name="CRIMSON", paid=true},
	{k="rainbow", name="RAINBOW", paid=true, special=true},  -- 효과색: 무지개 순환
	{k="gold",   name="GOLD",   paid=true, finish=true},     -- 마감재색: 금색
	{k="silver", name="SILVER", paid=true, finish=true},     -- 마감재색: 실버
	{k="bronze", name="BRONZE", paid=true, finish=true},     -- 마감재색: 브론즈
}
local FREE = { black=true, white=true, gray=true, navy=true, beige=true, orange=true }
local SPECIAL = { rainbow = true }
-- FINISH: 색+재질+반사 묶음(서버 모듈과 동일값)
local FINISH = {
	gold   = { color = Color3.fromRGB(238, 200, 95), material = Enum.Material.SmoothPlastic, reflectance = 0.08 },
	silver = { color = Color3.fromRGB(220, 222, 228), material = Enum.Material.SmoothPlastic, reflectance = 0.08 },
	bronze = { color = Color3.fromRGB(175, 120, 70), material = Enum.Material.SmoothPlastic, reflectance = 0.08 },
}
local DEFAULT_ZONE = { Body="navy", Point="orange", Handle="beige" }

-- ── 현재 선택 상태 (프리뷰용, 미적용) ──
local activeZone = "Body"
local pending = {}  -- { Body=색, Point=색, Handle=색 } — 저장된 값으로 초기화

-- 플레이어가 색 보유했나
local function owns(colorName)
	if FREE[colorName] then return true end
	return player:GetAttribute("Has_GColor_" .. colorName) and true or false
end

-- ── ViewportFrame 셋업 ──
local camera = Instance.new("Camera")
camera.Parent = vp
vp.CurrentCamera = camera
vp.LightColor = Color3.fromRGB(255, 250, 240)
vp.LightDirection = Vector3.new(-0.4, -0.7, -0.6)
vp.Ambient = Color3.fromRGB(150, 150, 165)
local world = Instance.new("WorldModel")
world.Parent = vp

local previewModel, rotateConn, boundCF, boundCenter
local rainbowPreviewConn = nil

local function stopPreviewRainbow()
	if rainbowPreviewConn then rainbowPreviewConn:Disconnect(); rainbowPreviewConn = nil end
end

local function clearPreview()
	if rotateConn then rotateConn:Disconnect(); rotateConn = nil end
	stopPreviewRainbow()
	if previewModel then previewModel:Destroy(); previewModel = nil end
end

-- 부위별 원래 재질 (서버 모듈과 동일) — 무지개(Neon)였다가 일반색 와도 발광 안 남게 복원용
local ZONE_MATERIAL = {
	Body   = Enum.Material.SmoothPlastic,
	Point  = Enum.Material.Neon,
	Handle = Enum.Material.Plastic,
}
local RAINBOW_CYCLE = 3.0

-- 프리뷰 모델에 현재 pending 색 적용 (SkinZone 기반)
-- 정적 색은 Color+재질 복원, "rainbow" 부위는 순환 루프로 처리.
local function applyColorsToPreview()
	if not previewModel then return end
	stopPreviewRainbow()

	-- 1) 정적/마감재 색 부위 칠하기 + 무지개 대상 부위 수집
	local rainbowZones = {}
	local anyRainbow = false
	for _, p in ipairs(previewModel:GetDescendants()) do
		if p:IsA("BasePart") then
			local zone = p:GetAttribute("SkinZone")
			if zone then
				local key = pending[zone]
				if key == "rainbow" then
					rainbowZones[zone] = true
					anyRainbow = true
					p.Material = Enum.Material.Neon
					p.Reflectance = 0
				elseif key and FINISH[key] then
					-- 마감재(금색): 색 + 재질 + 반사
					local f = FINISH[key]
					p.Color = f.color
					p.Material = f.material
					p.Reflectance = f.reflectance or 0
				elseif key and PALETTE[key] then
					p.Color = PALETTE[key]
					local mat = ZONE_MATERIAL[zone]
					if mat then p.Material = mat end
					p.Reflectance = 0
				end
			end
		end
	end

	-- 2) 무지개 부위가 있으면 순환 루프 시작
	if anyRainbow then
		local parts = {}
		for _, p in ipairs(previewModel:GetDescendants()) do
			if p:IsA("BasePart") then
				local z = p:GetAttribute("SkinZone")
				if z and rainbowZones[z] then table.insert(parts, p) end
			end
		end
		rainbowPreviewConn = RunService.RenderStepped:Connect(function()
			local hue = (tick() % RAINBOW_CYCLE) / RAINBOW_CYCLE
			local col = Color3.fromHSV(hue, 1, 1)
			for _, p in ipairs(parts) do
				if p.Parent then p.Color = col end
			end
		end)
	end
end

local function setupPreview()
	clearPreview()
	local src = ReplicatedStorage:FindFirstChild("GauntletPreviewModel")
	if not src then warn("[GauntletCustom] GauntletPreviewModel 없음"); return end

	previewModel = src:Clone()
	if previewModel:IsA("Tool") then
		local m = Instance.new("Model")
		for _, c in ipairs(previewModel:GetChildren()) do
			if c:IsA("BasePart") or c:IsA("Model") then c.Parent = m end
		end
		previewModel:Destroy(); previewModel = m
	end
	previewModel.Parent = world
	for _, p in ipairs(previewModel:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false end
	end

	local cf, size = previewModel:GetBoundingBox()
	boundCF = cf; boundCenter = cf.Position
	local maxExtent = math.max(size.X, size.Y, size.Z)
	local dist = maxExtent * 1.15 + 1.5
	local camPos = boundCenter + Vector3.new(dist * 0.7, dist * 0.4, dist * 0.7)
	camera.CFrame = CFrame.lookAt(camPos, boundCenter)
	camera.FieldOfView = 45

	applyColorsToPreview()

	local angle = 0
	rotateConn = RunService.RenderStepped:Connect(function(dt)
		angle = angle + dt * 0.5
		if previewModel then
			previewModel:PivotTo(CFrame.new(boundCenter) * CFrame.Angles(0, angle, 0) * (CFrame.new(boundCenter):Inverse() * boundCF))
		end
	end)
end

-- ── 팔레트 색칸 생성 ──
local swatches = {}  -- colorName -> button
local function buildSwatches()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
	end
	swatches = {}
	for i, info in ipairs(COLOR_ORDER) do
		local sw = Instance.new("TextButton")
		sw.Name = "Sw_" .. info.k
		sw.Text = ""
		sw.AutoButtonColor = false
		sw.LayoutOrder = i
		sw:SetAttribute("ColorKey", info.k)
		local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 6); cor.Parent = sw
		-- 색칸 배경: 일반색은 단색, 무지개(special)는 무지개 그라데이션 띠
		if info.special then
			sw.BackgroundColor3 = Color3.new(1, 1, 1)
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
				ColorSequenceKeypoint.new(0.34, Color3.fromRGB(240, 240, 0)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 200, 0)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 130, 255)),
				ColorSequenceKeypoint.new(0.84, Color3.fromRGB(75, 0, 200)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(160, 0, 220)),
			})
			grad.Rotation = 45
			grad.Parent = sw
		elseif info.finish then
			-- 마감재(금색/실버): 해당 마감재 색 기준 밝은→진한 그라데이션으로 금속 광택 느낌
			local fc = (FINISH[info.k] and FINISH[info.k].color) or Color3.fromRGB(238, 200, 95)
			sw.BackgroundColor3 = fc
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.0, fc:Lerp(Color3.new(1, 1, 1), 0.45)),
				ColorSequenceKeypoint.new(0.5, fc),
				ColorSequenceKeypoint.new(1.0, fc:Lerp(Color3.new(0, 0, 0), 0.35)),
			})
			grad.Rotation = 90
			grad.Parent = sw
		else
			sw.BackgroundColor3 = PALETTE[info.k]
		end
		-- 선택 테두리(기본 숨김)
		local stroke = Instance.new("UIStroke")
		stroke.Name = "SelStroke"
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 0
		stroke.Parent = sw
		-- 미보유 색: 자물쇠 표시
		if info.paid and not owns(info.k) then
			local lock = Instance.new("TextLabel")
			lock.Name = "Lock"
			lock.Size = UDim2.fromScale(1, 1)
			lock.BackgroundColor3 = Color3.fromRGB(0,0,0)
			lock.BackgroundTransparency = 0.45
			lock.Text = "🔒"
			lock.TextScaled = true
			lock.Font = Enum.Font.GothamBold
			lock.TextColor3 = Color3.new(1,1,1)
			local lcor = Instance.new("UICorner"); lcor.CornerRadius = UDim.new(0,6); lcor.Parent = lock
			lock.Parent = sw
		end
		sw.Parent = grid
		swatches[info.k] = sw
	end
end

-- 선택 테두리 갱신
local function refreshSelection()
	local cur = pending[activeZone]
	for k, sw in pairs(swatches) do
		local stroke = sw:FindFirstChild("SelStroke")
		if stroke then stroke.Thickness = (k == cur) and 3 or 0 end
	end
	-- 이름 표시
	for _, info in ipairs(COLOR_ORDER) do
		if info.k == cur then
			selName.Text = info.name .. (info.paid and "  (Paid)" or "")
			break
		end
	end
end

-- 색칸 클릭 처리
local function onSwatchClick(colorName)
	if not owns(colorName) then
		selName.Text = "🔒 Locked - Unlock Required"
		return
	end
	pending[activeZone] = colorName
	applyColorsToPreview()
	refreshSelection()
end

-- ── 부위 탭 처리 ──
local function refreshTabs()
	for _, tab in ipairs(tabBar:GetChildren()) do
		if tab:IsA("TextButton") then
			local zk = tab:GetAttribute("ZoneKey")
			local active = (zk == activeZone)
			tab.BackgroundColor3 = active and Color3.fromRGB(245,245,250) or Color3.fromRGB(55,60,72)
			tab.TextColor3 = active and Color3.fromRGB(25,28,35) or Color3.fromRGB(200,205,215)
		end
	end
end

-- ── 초기화 / 연결 ──
local function loadPending()
	-- 저장된 색으로 초기화(없으면 기본). 정적 색(PALETTE) + 효과색(SPECIAL=rainbow) 모두 인식.
	for _, zone in ipairs({"Body","Point","Handle"}) do
		local saved = player:GetAttribute("GauntletColor_" .. zone)
		local valid = saved and (PALETTE[saved] ~= nil or SPECIAL[saved] == true or FINISH[saved] ~= nil)
		pending[zone] = valid and saved or DEFAULT_ZONE[zone]
	end
end

local function openUI()
	loadPending()
	buildSwatches()
	setupPreview()
	activeZone = "Body"
	refreshTabs()
	refreshSelection()
	-- 색칸 클릭 연결
	for k, sw in pairs(swatches) do
		sw.MouseButton1Click:Connect(function() onSwatchClick(k) end)
	end
end

-- 탭 클릭 연결(한 번만)
for _, tab in ipairs(tabBar:GetChildren()) do
	if tab:IsA("TextButton") then
		tab.MouseButton1Click:Connect(function()
			activeZone = tab:GetAttribute("ZoneKey")
			refreshTabs()
			refreshSelection()
		end)
	end
end

-- APPLY: 서버에 각 부위 색 저장
applyBtn.MouseButton1Click:Connect(function()
	for _, zone in ipairs({"Body","Point","Handle"}) do
		if pending[zone] then
			remote:FireServer(zone, pending[zone])
		end
	end
	selName.Text = "✅ Applied! (re-equip gauntlet)"
end)

closeBtn.MouseButton1Click:Connect(function()
	screen.Enabled = false
	clearPreview()
end)

screen:GetPropertyChangedSignal("Enabled"):Connect(function()
	if screen.Enabled then openUI() else clearPreview() end
end)

if screen.Enabled then openUI() end

print("✅ GauntletCustomClient 준비 (프리뷰+부위탭+팔레트+APPLY)")
