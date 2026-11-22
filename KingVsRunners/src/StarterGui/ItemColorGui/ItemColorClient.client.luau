-- ItemColorClient: 아이템 색/재질 커스텀 UI (Noob 부위별 + Spear 단색+재질 등)
-- 인벤이 screen:SetAttribute("CurrentItem", 아이템명) 설정하면 열림.
-- 다부위면 부위탭, 재질지원+단부위면 재질탭(부위탭 자리) + 색그리드 + 회전 프리뷰
-- + APPLY(ItemColorRemote, form 스킨 해제 포함) + CLOSE.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local screen = script.Parent

local palette = require(ReplicatedStorage:WaitForChild("NoobColorPalette"))
local itemRemote = ReplicatedStorage:WaitForChild("ItemColorRemote")
local setPlayerSkin = ReplicatedStorage:WaitForChild("SetPlayerSkin")

local tabBar = screen:WaitForChild("ZoneTabs")
local paletteBar = screen:WaitForChild("PaletteBar")
local grid = paletteBar:WaitForChild("ColorGrid")
local selName = paletteBar:WaitForChild("SelectedName")
local applyBtn = paletteBar:WaitForChild("ApplyBtn")
local closeBtn = screen:WaitForChild("CloseBtn")
local vp = screen:WaitForChild("WeaponPreview")
grid.BackgroundTransparency = 1  -- 그리드 전체 배경 없음 (검정 셀만 개별 감싸기)
do
	local gl = grid:FindFirstChildOfClass("UIGridLayout")
	if gl then
		gl.CellSize = UDim2.new(0, 50, 0, 50)  -- 색 많아져도(최대 16색) 한 줄에 들어가게
		gl.CellPadding = UDim2.new(0, 6, 0, 6)
	end
end

-- ===== ViewportFrame 프리뷰 셋업 =====
local camera = Instance.new("Camera")
camera.Parent = vp
vp.CurrentCamera = camera
vp.Ambient = Color3.fromRGB(150, 150, 165)
vp.LightColor = Color3.fromRGB(255, 250, 240)
vp.LightDirection = Vector3.new(-0.4, -0.7, -0.6)
local world = Instance.new("WorldModel")
world.Parent = vp

local previewModel, rotateConn

local function clearPreview()
	if rotateConn then rotateConn:Disconnect(); rotateConn = nil end
	if previewModel then previewModel:Destroy(); previewModel = nil end
end

-- 탭 템플릿 확보 (부위탭/재질탭 둘 다 이걸로 복제)
local tabTemplate
do
	local t = tabBar:FindFirstChildWhichIsA("TextButton")
	if t then tabTemplate = t:Clone() end
end

-- 재질 바 (부위탭 자리에 동적 생성, 재질 지원 + 단부위 아이템만 표시)
local matBar = Instance.new("Frame")
matBar.Name = "MaterialBar"
matBar.BackgroundTransparency = 1
matBar.AnchorPoint = tabBar.AnchorPoint
matBar.Position = tabBar.Position + UDim2.new(0, 24, 0, 46)  -- 부위 탭 아래 + 들여쓰기(종속 느낌)
matBar.Size = tabBar.Size
matBar.Visible = false
matBar.Parent = screen
do
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, 8)
	ll.VerticalAlignment = Enum.VerticalAlignment.Center
	ll.Parent = matBar
end

local currentItem, currentCfg, activeZone
local pendingColor = {}  -- zone → colorName
local pendingMat = {}    -- zone → materialName

-- ===== 임시: preview 위치/크기 실시간 조정 모드 (방향키) =====
-- 값 확정 후 이 블록 + loadPreview 안의 tuneInit() 호출 한 줄만 지우면 됨.
local TUNE_ENABLED = false  -- 보관: 프리뷰 실시간 조정 모드. 다시 쓸 때 true로 바꾸면 방향키/Q·E 활성화
local TUNE = { dist = nil, yoff = nil, pitch = nil, active = false }
local tuneLabel
local function tuneRefresh()
	if tuneLabel then
		tuneLabel.Text = string.format("[조정모드] previewDistScale=%.2f  previewYOffset=%.2f  previewPitch=%.2f   (Up/Down=크기, Left/Right=높이, Q/E=시점각도)", TUNE.dist or 0, TUNE.yoff or 0, TUNE.pitch or 0)
	end
end
local function tuneInit()
	if not TUNE_ENABLED then return end  -- 보관 모드: 비활성 (카메라는 config 값 그대로 사용)
	TUNE.dist = (currentCfg and currentCfg.previewDistScale) or 0.9
	TUNE.yoff = (currentCfg and currentCfg.previewYOffset) or 0
	TUNE.pitch = (currentCfg and currentCfg.previewPitch) or 0.1
	TUNE.active = (currentCfg and (not currentCfg.singlePart or currentCfg.previewRotate)) and true or false  -- 회전 프리뷰 무기만
	if not tuneLabel then
		tuneLabel = Instance.new("TextLabel")
		tuneLabel.Name = "TuneLabel"
		tuneLabel.Size = UDim2.new(0.82, 0, 0, 48)
		tuneLabel.Position = UDim2.new(0.5, 0, 0, 95)
		tuneLabel.AnchorPoint = Vector2.new(0.5, 0)
		tuneLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		tuneLabel.BackgroundTransparency = 0.35
		tuneLabel.TextColor3 = Color3.fromRGB(255, 228, 120)
		tuneLabel.Font = Enum.Font.GothamBold
		tuneLabel.TextSize = 16
		tuneLabel.ZIndex = 50
		Instance.new("UICorner", tuneLabel).CornerRadius = UDim.new(0, 8)
		tuneLabel.Parent = screen
	end
	tuneLabel.Visible = TUNE.active
	tuneRefresh()
end
UserInputService.InputBegan:Connect(function(input, gp)
	if not TUNE.active then return end
	if screen:IsA("ScreenGui") and not screen.Enabled then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.Up then TUNE.dist = math.max(0.2, (TUNE.dist or 0.9) - 0.02)
	elseif k == Enum.KeyCode.Down then TUNE.dist = (TUNE.dist or 0.9) + 0.02
	elseif k == Enum.KeyCode.Left then TUNE.yoff = (TUNE.yoff or 0) - 0.05
	elseif k == Enum.KeyCode.Right then TUNE.yoff = (TUNE.yoff or 0) + 0.05
	elseif k == Enum.KeyCode.Q then TUNE.pitch = (TUNE.pitch or 0.1) + 0.1
	elseif k == Enum.KeyCode.E then TUNE.pitch = (TUNE.pitch or 0.1) - 0.1
	else return end
	tuneRefresh()
end)
-- ===== 임시 블록 끝 =====

-- 전용색 시스템: cfg에 colors/colorOrder/colorOwnPrefix 있으면 그걸, 없으면 공유 팔레트
local function colorDefs() return (currentCfg and currentCfg.colors) or palette.COLORS end
local function colorList() return (currentCfg and currentCfg.colorOrder) or palette.ORDER end
local function isFreeColor(name)
	if currentCfg and currentCfg.colorOrder then
		for _, e in ipairs(currentCfg.colorOrder) do
			if e.k == name then return e.free end
		end
		return false
	end
	return palette.isFree(name)
end
local function owns(colorName)
	if isFreeColor(colorName) then return true end
	local prefix = (currentCfg and currentCfg.colorOwnPrefix) or "NoobColor"
	return player:GetAttribute("Has_" .. prefix .. "_" .. colorName) and true or false
end

-- 프리뷰에 pending 색+재질 적용
local function applyPreview()
	if not previewModel or not currentCfg then return end
	for _, zone in ipairs(currentCfg.zones) do
		local colorName = pendingColor[zone]
		if colorName and colorDefs()[colorName] then
			local col = colorDefs()[colorName]
			local matName = pendingMat[zone]
			if currentCfg.vertexTint then
				-- solidHSV 무기: SpecialMesh VertexColor 색조(텍스처 유지) + Metal + Reflectance (SwordScript 재현)
				local mul = 1.8
				local vc = Vector3.new(col.R * mul, col.G * mul, col.B * mul)
				local fin = matName and palette.FINISHES[matName]
				local mat = (fin and Enum.Material[fin.material]) or Enum.Material.Metal
				local refl = (mat == Enum.Material.Metal) and 0.5 or 0
				for _, p in ipairs(previewModel:GetDescendants()) do
					local sm = p:IsA("BasePart") and p:FindFirstChildOfClass("SpecialMesh")
					if sm and sm.TextureId ~= "" then
						sm.VertexColor = vc
						p.Material = mat
						p.Reflectance = refl
					end
				end
			elseif currentCfg.paintTagged then
				for _, p in ipairs(previewModel:GetDescendants()) do
					if p:IsA("BasePart") and p:GetAttribute("SkinPaintPart") then
						if matName then
							palette.applyFinish(p, matName, col)
						elseif currentCfg.previewNeon then
							p.Color = col
							p.Material = Enum.Material.Neon
						else
							p.Color = col
						end
					end
				end
			elseif currentCfg.singlePart then
				for _, p in ipairs(previewModel:GetDescendants()) do
					if p:IsA("BasePart") then
						if matName then
							palette.applyFinish(p, matName, col)
						else
							p.Color = col
						end
					end
				end
			else
				for _, partName in ipairs(currentCfg.zoneParts[zone]) do
					local p = previewModel:FindFirstChild(partName)
					if p and p:IsA("BasePart") then
						if matName then
							palette.applyFinish(p, matName, col)
						else
							p.Color = col
						end
					end
				end
			end
		end
	end
end

local function loadPreview(itemName)
	clearPreview()
	camera.FieldOfView = 70  -- 기본값 리셋 (previewLookDir 분기에서 필요 시 변경)
	if tuneLabel then tuneLabel.Visible = false end  -- 임시: 조정 라벨 숨김 (회전무기면 tuneInit가 다시 켬)
	local folder = ReplicatedStorage:FindFirstChild("SkinPreviews")
	local src = folder and folder:FindFirstChild(itemName)
	if not src then
		-- 태거 아이템(배럴 등)은 TaggerItemPreviews에 있음
		local tp = ReplicatedStorage:FindFirstChild("TaggerItemPreviews")
		src = tp and tp:FindFirstChild(itemName)
	end
	if not src then vp.Visible = false; return end
	previewModel = src:Clone()
	previewModel.Parent = world
	local cf, size = previewModel:GetBoundingBox()
	local center = cf.Position
	local upright = currentCfg and currentCfg.singlePart and not currentCfg.previewRotate
	applyPreview()
	if currentCfg and currentCfg.previewLookDir then
		-- 인벤 썸네일과 동일한 고정 비스듬 카메라(회전 없음). dirV 방향에서 center를 바라봄.
		camera.FieldOfView = currentCfg.previewFOV or 35
		local d = currentCfg.previewLookDir
		local dirV = Vector3.new(d[1], d[2], d[3]).Unit
		local maxDim = math.max(size.X, size.Y, size.Z)
		local dist = maxDim * (currentCfg.previewDistScale or 2.8)
		camera.CFrame = CFrame.new(center + dirV * dist, center)
	elseif upright then
		-- 긴 막대(Spear): 긴 축 = 화면 세로(up, 창날이 위로 오게 음수 방향), 넓은 면이 카메라 정면.
		local sx, sy, sz = size.X, size.Y, size.Z
		local up
		if sx >= sy and sx >= sz then up = Vector3.new(-1, 0, 0)
		elseif sy >= sx and sy >= sz then up = Vector3.new(0, -1, 0)
		else up = Vector3.new(0, 0, -1) end
		-- 넓은 면 정면: up(긴축) 제외 두 축 중 넓은 축 쪽에서 카메라 (옆으로 90도)
		local front
		if up.X ~= 0 then
			front = (sy >= sz) and Vector3.new(0, 1, 0) or Vector3.new(0, 0, 1)
		elseif up.Y ~= 0 then
			front = (sx >= sz) and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
		else
			front = (sx >= sy) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		end
		local dist = math.max(sx, sy, sz) * (currentCfg.previewDistScale or 0.75)
		camera.CFrame = CFrame.lookAt(center + front * dist, center, up)
	else
		-- bounding box 대각선(Magnitude)은 L자 모델에서 손잡이 빈 공간까지 포함해 과대평가 → 최대 축 기준
		local maxAxis = math.max(size.X, size.Y, size.Z)
		tuneInit()  -- 임시 조정 모드: TUNE 초기화 + 라벨 표시
		local angle = 0
		rotateConn = RunService.RenderStepped:Connect(function(dt)
			angle += dt * 0.5
			local ds = TUNE.dist or (currentCfg and currentCfg.previewDistScale) or 0.9
			local yo = TUNE.yoff or (currentCfg and currentCfg.previewYOffset) or 0
			local dist = maxAxis * ds
			local yLift = yo * size.Y
			local hm = TUNE.pitch or (currentCfg and currentCfg.previewPitch) or 0.1
			local offset = CFrame.Angles(0, angle, 0) * Vector3.new(0, size.Y * hm, dist)
			camera.CFrame = CFrame.lookAt(center + offset, center + Vector3.new(0, yLift, 0))
		end)
	end
	vp.Visible = true
end

local TAB_ON = Color3.fromRGB(255, 200, 50)
local TAB_OFF = Color3.fromRGB(110, 112, 125)
local refreshGrid, refreshMatBar

-- 부위탭
local function refreshTabs()
	for _, tab in ipairs(tabBar:GetChildren()) do
		if tab:IsA("TextButton") then
			tab.BackgroundColor3 = (tab:GetAttribute("Zone") == activeZone) and TAB_ON or TAB_OFF
		end
	end
end

local function buildTabs(zones)
	for _, c in ipairs(tabBar:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, zone in ipairs(zones) do
		local tab = tabTemplate:Clone()
		tab.Name = "Tab_" .. zone
		tab.Text = string.upper(zone)
		tab:SetAttribute("Zone", zone)
		tab.Parent = tabBar
		tab.Activated:Connect(function()
			activeZone = zone
			refreshTabs()
			refreshGrid()
		end)
	end
end

-- 재질 바 (재질 지원 아이템)
function refreshMatBar()
	for _, c in ipairs(matBar:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	if not (currentCfg and currentCfg.materials) then return end
	for _, matName in ipairs(currentCfg.materials) do
		local btn = tabTemplate:Clone()
		btn.Name = "Mat_" .. matName
		btn.Size = UDim2.fromOffset(88, 30)   -- 부위 탭(110x38)보다 작게 = 하위 종속 느낌
		btn.TextSize = 14
		local mc = btn:FindFirstChildOfClass("UICorner")
		if mc then mc.CornerRadius = UDim.new(0, 10) end  -- 더 둥글게 (칩 느낌)
		btn.Text = (currentCfg.materialLabels and currentCfg.materialLabels[matName]) or string.upper(matName)
		btn:SetAttribute("Mat", matName)
		btn.BackgroundColor3 = (pendingMat[activeZone] == matName) and Color3.fromRGB(80, 160, 255) or Color3.fromRGB(70, 90, 120)
		btn.Parent = matBar
		btn.Activated:Connect(function()
			pendingMat[activeZone] = matName
			applyPreview()
			refreshMatBar()
		end)
	end
end

function refreshGrid()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, entry in ipairs(colorList()) do
		if currentCfg and currentCfg.hideColors and currentCfg.hideColors[entry.k] then
			continue
		end
		-- 뉴비 전용 색(NoobYellow/NoobGreen)은 뉴비(isNoob) 아이템 팔레트에서만 노출
		if entry.noobOnly and not (currentCfg and currentCfg.isNoob) then
			continue
		end
		local sw = Instance.new("TextButton")
		sw.Name = entry.k
		sw.Text = ""
		local col = colorDefs()[entry.k]
		sw.BackgroundColor3 = col
		sw.BorderSizePixel = 0
		Instance.new("UICorner", sw).CornerRadius = UDim.new(0.18, 0)
		local stroke = Instance.new("UIStroke", sw)
		stroke.Color = Color3.fromRGB(255, 255, 255)
		local lum = 0.299 * col.R + 0.587 * col.G + 0.114 * col.B
		-- 검정 등 어두운 색만 흰 테두리(가시성). 나머지는 평소 테두리 없음.
		if lum < 0.3 then
			stroke.Thickness = 2
		else
			stroke.Enabled = false
		end
		local locked = not owns(entry.k)
		if locked then
			local lk = Instance.new("TextLabel")
			lk.Size = UDim2.fromScale(1, 1)
			lk.BackgroundTransparency = 1
			lk.Text = "🔒"
			lk.TextScaled = true
			lk.Parent = sw
		end
		if pendingColor[activeZone] == entry.k then
			stroke.Enabled = true
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.Thickness = 3
		end
		sw.Parent = grid
		sw.Activated:Connect(function()
			if locked then
				selName.Text = entry.name .. " (Locked)"
				return
			end
			pendingColor[activeZone] = entry.k
			selName.Text = (#currentCfg.zones > 1) and (string.upper(activeZone) .. ": " .. entry.name) or entry.name
			applyPreview()
			refreshGrid()
		end)
	end
end

local function openFor(itemName)
	local cfg = palette.getConfig(itemName)
	if not cfg then return end
	currentItem = itemName
	currentCfg = cfg
	pendingColor = {}
	pendingMat = {}
	for _, zone in ipairs(cfg.zones) do
		pendingColor[zone] = player:GetAttribute(cfg.colorAttr .. "_" .. zone) or cfg.zoneDefault[zone] or "White"
		if cfg.materialAttr then
			pendingMat[zone] = player:GetAttribute(cfg.materialAttr .. "_" .. zone) or cfg.materialDefault
		end
	end
	activeZone = cfg.zones[1]
	local multiZone = (#cfg.zones > 1)
	-- 부위탭: 부위 여러개일 때만
	buildTabs(cfg.zones)
	tabBar.Visible = true  -- 단일 존이어도 부위 탭 표시(고정 선택 느낌)
	refreshTabs()
	-- 재질탭: 재질 지원 + 단부위일 때 (부위탭 자리에)
	matBar.Visible = (cfg.materials ~= nil)  -- 재질 지원하면 항상 표시 (다중존은 존탭 위에 별도 배치)
	refreshMatBar()
	refreshGrid()
	loadPreview(itemName)
	selName.Text = "—"
	screen.Enabled = true
end

applyBtn.Activated:Connect(function()
	-- "내 커스텀 입기": form 스킨 해제 → 커스텀 색/재질이 실제로 보이게
	if currentItem then
		setPlayerSkin:FireServer(currentItem, nil)
	end
	if currentCfg then
		for _, zone in ipairs(currentCfg.zones) do
			local colorName = pendingColor[zone]
			if colorName and owns(colorName) then
				itemRemote:FireServer(currentItem, zone, colorName, pendingMat[zone])
			end
		end
	end
	clearPreview()
	screen.Enabled = false
end)

closeBtn.Activated:Connect(function()
	clearPreview()
	screen.Enabled = false
end)

-- 열기 트리거: 인벤이 CurrentItem 속성 설정
screen:GetAttributeChangedSignal("CurrentItem"):Connect(function()
	local item = screen:GetAttribute("CurrentItem")
	if item and item ~= "" then openFor(item) end
end)
