-- WeaponTrialClient
-- Blacksmith 프롬프트로 열리는 무기 선택 패널.
--
-- ⚠️ MobileScaled 태그를 붙이지 않는다. UIScale 은 GUI 하나당 소유자가 하나여야 하는데
--   MobileUIScaler 와 자체 스케일러가 겹치면 크기가 튄다(HUD·KillLog 에서 겪은 문제).
--   대신 AnchorPoint + Scale 단위로만 배치해 해상도에 자연히 따라가게 한다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local openEvent  = ReplicatedStorage:WaitForChild("WeaponTrialOpen")
local pickEvent  = ReplicatedStorage:WaitForChild("WeaponTrialPick")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RARITY = {
    Normal    = Color3.fromRGB(150, 155, 160),
    Rare      = Color3.fromRGB( 70, 140, 235),
    Epic      = Color3.fromRGB(165,  95, 225),
    Legendary = Color3.fromRGB(240, 165,  55),
}

-- ── GUI 구성 ───────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "WeaponTrialGui"
gui.ResetOnSpawn   = false          -- 리스폰해도 살아 있어야 한다
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 50
gui.Enabled        = false
gui.Parent         = playerGui

local dim = Instance.new("TextButton")   -- 바깥 클릭 = 닫기
dim.Size                   = UDim2.fromScale(1, 1)
dim.BackgroundColor3       = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel        = 0
dim.Text                   = ""
dim.AutoButtonColor        = false
dim.Parent                 = gui

local panel = Instance.new("Frame")
panel.AnchorPoint       = Vector2.new(0.5, 0.5)
panel.Position          = UDim2.fromScale(0.5, 0.5)
panel.Size              = UDim2.fromScale(0.62, 0.68)
panel.BackgroundColor3  = Color3.fromRGB(28, 30, 36)
panel.BorderSizePixel   = 0
panel.Parent            = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", panel)
stroke.Color     = Color3.fromRGB(90, 95, 105)
stroke.Thickness = 2

local title = Instance.new("TextLabel")
-- ⚠️ 우측 상단에 탭(230) + 닫기(34) 가 있다. 제목이 전체 폭을 먹으면 겹친다.
--   패널이 fromScale(0.62) 이라 해상도마다 폭이 달라지므로, 고정 픽셀로 비워둔다.
title.Size                   = UDim2.new(1, -320, 0, 44)
title.Position               = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.Text                   = "Pick a weapon to try"
title.TextColor3             = Color3.fromRGB(240, 240, 245)
title.TextScaled             = true
title.Font                   = Enum.Font.GothamBold
title.TextXAlignment         = Enum.TextXAlignment.Left
title.Parent                 = panel

local hint = Instance.new("TextLabel")
hint.Size                   = UDim2.new(1, -24, 0, 22)
hint.Position               = UDim2.new(0, 12, 0, 50)
hint.BackgroundTransparency = 1
hint.Text                   = "Training only — you cannot take these into a round."
hint.TextColor3             = Color3.fromRGB(150, 155, 165)
hint.TextScaled             = true
hint.Font                   = Enum.Font.Gotham
hint.TextXAlignment         = Enum.TextXAlignment.Left
hint.Parent                 = panel

local close = Instance.new("TextButton")
close.AnchorPoint      = Vector2.new(1, 0)
close.Position         = UDim2.new(1, -10, 0, 10)
close.Size             = UDim2.fromOffset(34, 34)
close.BackgroundColor3 = Color3.fromRGB(52, 55, 63)
close.Text             = "X"
close.TextColor3       = Color3.fromRGB(230, 230, 235)
close.TextScaled       = true
close.Font             = Enum.Font.GothamBold
close.BorderSizePixel  = 0
close.Parent           = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

-- ── 역할 탭 (RUNNER / KING) ─────────────────────────────────────
-- ⚠️ [2026-09-08] NPC 를 둘로 나누는 대신 한 패널에서 탭으로 가른다.
--   [왜] 러너 무기와 태거 도구는 목표가 반대다(때린다 / 민다). 한 목록에 섞으면
--     역할 구분이 무너진다. 그렇다고 NPC 를 야드 양쪽에 두면 가로질러야 한다.
--   [해결] 같은 Blacksmith 에서 탭만 바꾼다. 개념은 나뉘고 동선은 안 늘어난다.
local ROLE_RUNNER, ROLE_KING = "Runner", "King"
-- ⚠️ 이 블록은 `scroll`(아래 286행)보다 앞에 있다.
--   refreshCards 는 '함수 본문 안에서만' scroll 을 참조하고 실제 호출은 파일 맨 끝이라
--   실행 시점에는 이미 scroll 이 존재한다. 다만 이 순서에 의존하고 있으니,
--   탭 관련 코드를 옮기거나 refreshCards 를 위쪽에서 호출하면 nil 로 터진다.
local currentRole = ROLE_RUNNER
local tabButtons = {}

-- 🎨 진영색 — 임의로 정하지 않는다. RoundResultClient 가 이미 쓰는 값을 그대로 가져온다.
--   (승리 화면 좌측 역할 바: isTagger and (235,90,90) or (90,165,255))
--   같은 개념에 다른 색을 쓰면 플레이어가 두 번 배워야 한다.
local COL_RUNNER = Color3.fromRGB( 90, 165, 255)   -- 파랑
local COL_KING   = Color3.fromRGB(235,  90,  90)   -- 빨강
local COL_OFF    = Color3.fromRGB( 44,  47,  55)   -- 비활성 배경
local ROLE_COLOR = { [ROLE_RUNNER] = COL_RUNNER, [ROLE_KING] = COL_KING }

local tabBar = Instance.new("Frame")
tabBar.Name                   = "RoleTabs"
tabBar.AnchorPoint            = Vector2.new(1, 0)
tabBar.Position               = UDim2.new(1, -56, 0, 10)   -- 닫기(X) 왼쪽
tabBar.Size                   = UDim2.fromOffset(230, 38)  -- 168×30 → 키움
tabBar.BackgroundTransparency = 1
tabBar.Parent                 = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection  = Enum.FillDirection.Horizontal
tabLayout.Padding        = UDim.new(0, 6)
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
tabLayout.Parent         = tabBar

local refreshCards   -- 아래에서 정의 (탭이 먼저 필요해 미리 선언)

local function setRole(role)
	if currentRole == role then return end
	currentRole = role
	for r, btn in pairs(tabButtons) do
		local on = (r == role)
		btn.BackgroundColor3 = on and ROLE_COLOR[r] or COL_OFF
		btn.TextColor3       = on and Color3.fromRGB(255, 255, 255)
		                             or Color3.fromRGB(150, 155, 165)
	end
	if refreshCards then refreshCards() end
end

local function makeTab(role, text, order)
	local on = (role == currentRole)
	local b = Instance.new("TextButton")
	b.Name             = "Tab_" .. role
	b.LayoutOrder      = order
	b.Size             = UDim2.fromOffset(108, 38)   -- 78×30 → 키움
	b.BackgroundColor3 = on and ROLE_COLOR[role] or COL_OFF
	b.Text             = text
	b.TextColor3       = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,155,165)
	b.TextScaled       = true
	b.Font             = Enum.Font.GothamBold
	b.BorderSizePixel  = 0
	b.AutoButtonColor  = false
	b.Parent           = tabBar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local pad = Instance.new("UIPadding", b)
	pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
	b.Activated:Connect(function() setRole(role) end)
	tabButtons[role] = b
	return b
end

-- ⚠️ 순서는 솔로 역할 선택(SoloRoleClient) 과 맞춘다 — RUNNER 왼쪽 / KING 오른쪽.
--   [기준] 게임 흐름 자체가 그 방향이다. 러너가 언덕 아래(X -222)에서 출발해
--     킹의 성(X 741)으로 간다. 시작이 왼쪽, 목적지가 오른쪽.
--   ⚠️ 두 UI 가 어긋나면 "어느 쪽이 내 진영이지" 를 매번 다시 읽어야 한다.
--     한쪽 순서를 바꾸면 다른 쪽도 반드시 같이 본다.
-- ⚠️ UIListLayout 이 HorizontalAlignment=Right 라 LayoutOrder 가 작을수록 왼쪽이다.
makeTab(ROLE_RUNNER, "RUNNER", 1)
makeTab(ROLE_KING,   "KING",   2)

local scroll = Instance.new("ScrollingFrame")
scroll.Position               = UDim2.new(0, 12, 0, 80)
scroll.Size                   = UDim2.new(1, -24, 1, -92)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel        = 0
scroll.ScrollBarThickness     = 5
scroll.CanvasSize             = UDim2.new()
scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
scroll.Parent                 = panel

local grid = Instance.new("UIGridLayout", scroll)
grid.CellSize     = UDim2.new(0.5, -8, 0, 78)
grid.CellPadding  = UDim2.fromOffset(8, 8)
grid.SortOrder    = Enum.SortOrder.LayoutOrder

-- ── 카드 ───────────────────────────────────────────────────────
-- 🖼️ [2026-09-07] 3D 썸네일.
--   [왜 직접 안 만드나] LoadoutPreviewClient 가 makeViewport 를 _G.LP_makeViewport 로
--     노출해 두었고, 상점 코스메틱 썸네일이 이미 그걸 재사용하고 있다.
--     같은 코드를 또 쓰면 "같은 규칙이 두 곳" 이 되어 한쪽만 고쳐진다.
--   ⚠️ RunnerInvenClient 의 뷰포트 코드를 베끼면 안 된다 — 거기는 dist = maxDim * 2.8 로
--     하드코딩이라, 손으로 맞춰둔 DistMul(Katana 0.4 / Gauntlet 1.4)이 무시된다.
--     LP_makeViewport 는 DistMul · CameraDirection · CameraOffset 을 전부 읽는다.
--   ⚠️ 8종 프리뷰 합계 72파트라 렌더 부담은 무시할 수준이다(로비 원반 하나가 617파트).
-- 🔍 [2026-09-07] 썸네일 프레이밍 보정.
--   [증상] 카타나·클래식소드가 카드에서 얇은 선처럼 보였다.
--   [원인] 크기가 아니라 '형태와 각도'다. 실측 바운딩:
--       KatanaSword2 (1.0, 1.3, 6.9)  ClassicSword (1.0, 0.8, 4.0)
--     칼은 한 축만 길다. 최대변 기준 점유율은 74%로 멀쩡한데, 그 축을 비스듬히
--     보면 화면에는 얇은 선만 남는다.
--   [왜 DistMul 을 못 믿나] CameraDirection 이 정규화돼 있지 않고, LP_makeViewport 가
--     dv 를 그대로 거리에 곱한다 — |dv| 가 KatanaSword2 는 3.64, DiamondBlade 는 2.43 이다.
--     즉 같은 DistMul 이라도 무기마다 실제 거리가 최대 3배 차이 난다.
--     그 값들은 '인벤 슬롯 비율'에 맞춰 손으로 맞춘 것이라 62×62 정사각형 카드와는 다르다.
--   [해결] 공용 함수(_G.LP_makeViewport)는 건드리지 않는다 — 인벤·상점이 같이 쓴다.
--     여기서 만들어진 카메라만 사후 보정한다. 목표 점유율을 정해 거리를 다시 계산.
--   ⚠️ 카드별 수동 튜닝값 테이블을 만들지 않는다. 무기가 늘 때마다 손이 가고,
--     "같은 규칙이 두 곳" 이 된다. 형태에서 자동으로 계산한다.
local FILL_TARGET = 0.62   -- 카드 안에서 차지할 비율 (여백 포함)

-- ⚠️ [2026-09-07] 무기별 예외 — 훈련장 카드 전용.
--   [왜 자동 계산으로 안 되나] fitThumbnail 은 실루엣의 '긴 쪽'을 목표 비율에 맞춘다.
--     칼처럼 종횡비가 큰 무기는 긴 쪽이 기준을 채워도 짧은 쪽이 10px 안팎이라 선으로 보인다.
--     거리를 당겨도 해결되지 않는다 — 두께 자체가 1스터드라서다. 각도를 바꿔야 면이 보인다.
--   [왜 프리뷰 모델 속성이 아니라 여기인가] DistMul/CameraDirection 을 고치면 인벤·상점·
--     로드아웃 패널이 전부 같이 바뀐다. 거기는 슬롯 비율이 달라 지금 값이 맞다.
--     이 카드만 62×62 정사각형이라, 여기서만 다르게 잡는 게 옳다.
--   [값 출처] PreviewTunerClient(P키)로 직접 맞춘 [TUNE-OUT] 기록. 추정값이 아니다.
--   ⚠️ 새 무기가 가늘어 보이면 P 로 맞춘 뒤 [TUNE-OUT] 한 줄을 여기 추가하면 된다.
--     dist 는 튜너 공식 기준이다 — 실제 거리 = maxDim * dist (fitThumbnail 의 비율과 다름).
local TUNE_OVERRIDE = {
	-- [TUNE-OUT] 기록 — PreviewTunerClient(P키)로 직접 맞춘 값. 추정치 아님.
	KatanaSword2 = {
		dist = 0.70,
		dir  = Vector3.new(0.839, 0.041, 0.974),
		pan  = Vector3.new(-0.200, 0.000, 0.000),
	},
	ClassicSword = {
		dist = 0.50,
		dir  = Vector3.new(2.268, -0.132, 0.640),
		pan  = Vector3.new(0.000, 0.000, 0.000),
	},
	DragonFireSword = {
		dist = 1.26,
		dir  = Vector3.new(0.805, 0.044, 0.575),
		pan  = Vector3.new(0.000, 0.000, 0.000),
	},
	DiamondBladeSword = {
		dist = 1.05,
		dir  = Vector3.new(0.906, -0.203, 0.412),
		pan  = Vector3.new(0.000, 0.000, 0.000),
	},
	Gauntlet = {
		dist = 1.25,
		dir  = Vector3.new(0.254, 0.466, -0.847),
		pan  = Vector3.new(0.000, 0.000, 0.000),
	},
	HammerHigh = {
		dist = 1.64,
		dir  = Vector3.new(0.362, -0.226, 0.904),
		pan  = Vector3.new(0.000, 0.000, 0.000),
	},
}

local function fitThumbnail(holder, weaponId)
	local vp = holder:FindFirstChildOfClass("ViewportFrame")
	if not vp then return end
	local cam = vp.CurrentCamera
	local m = vp:FindFirstChildWhichIsA("Model") or vp:FindFirstChildWhichIsA("BasePart")
	if not cam or not m then return end

	local cf, sz
	if m:IsA("Model") then cf, sz = m:GetBoundingBox() else cf, sz = m.CFrame, m.Size end
	local md = math.max(sz.X, sz.Y, sz.Z, 0.1)

	-- ── 수동 튜닝값이 있으면 그걸 그대로 쓴다 (자동 계산 건너뜀) ──
	--   PreviewTunerClient:60~66 의 updateCam() 과 같은 공식이어야 한다.
	--     tgt  = center + pan * maxDim
	--     dist = maxDim * distMul
	--     cam  = CFrame.new(tgt + dir * dist, tgt)
	--   ⚠️ dir 을 정규화하지 않는다 — 튜너도 안 한다. 정규화하면 튜너에서 본 그림과 달라진다.
	local ov = TUNE_OVERRIDE[weaponId]
	if ov then
		local tgt = cf.Position + ov.pan * md
		cam.CFrame = CFrame.new(tgt + ov.dir * (md * ov.dist), tgt)
		vp:SetAttribute("_tuneDist", ov.dist)
		vp:SetAttribute("_tuneDir", ov.dir)
		vp:SetAttribute("_tuneTarget", ov.pan)
		vp:SetAttribute("PreviewId", weaponId)
		return
	end

	-- 카메라가 보는 방향에서의 '실루엣 크기'를 쓴다. 최대변이 아니라
	-- 시선축에 수직인 두 축의 크기가 화면을 채우는 실제 값이다.
	local look = cam.CFrame.LookVector
	local right, up = cam.CFrame.RightVector, cam.CFrame.UpVector
	local silW = math.abs(sz.X * right.X) + math.abs(sz.Y * right.Y) + math.abs(sz.Z * right.Z)
	local silH = math.abs(sz.X * up.X)    + math.abs(sz.Y * up.Y)    + math.abs(sz.Z * up.Z)
	local sil  = math.max(silW, silH, 0.1)

	-- 화면 높이 = 2 * dist * tan(FOV/2). sil / 화면높이 = 목표비율 이 되도록 dist 를 푼다.
	local fill = FILL_TARGET
	local halfTan = math.tan(math.rad(cam.FieldOfView / 2))
	local dist = sil / (2 * halfTan * fill)

	-- 방향은 기존 튜닝을 그대로 존중하고 거리만 바꾼다 (각도는 손으로 맞춰둔 값이 낫다)
	local dir = (cam.CFrame.Position - cf.Position)
	if dir.Magnitude < 0.001 then dir = Vector3.new(0.7, 0.5, 0.7) end
	cam.CFrame = CFrame.new(cf.Position + dir.Unit * dist, cf.Position)

	-- ⚠️ PreviewTunerClient(P키) 연동. 그 도구는 _tuneDist/_tuneDir/_tuneTarget 을 읽어
	--   updateCam() 으로 카메라를 다시 만든다(PreviewTunerClient:60~66).
	--   여기서 카메라만 바꾸고 속성을 안 고치면, 튜너를 켜는 순간 옛 값으로 되돌아가
	--   "P 를 눌렀더니 크기가 튄다" 가 된다. 보정 결과를 속성에도 반영해 둔다.
	--   튜너 공식: dist = maxDim * distMul  →  distMul = dist / maxDim
	vp:SetAttribute("_tuneDist", dist / md)
	vp:SetAttribute("_tuneDir", dir.Unit)
	vp:SetAttribute("PreviewId", weaponId)   -- 튜너 출력에 무기 이름이 찍히게
end

local function addThumbnail(card, weaponId)
	local holder = Instance.new("Frame")
	holder.Name                   = "Thumb"
	holder.AnchorPoint            = Vector2.new(1, 0.5)
	holder.Position               = UDim2.new(1, -10, 0.5, 0)
	holder.Size                   = UDim2.new(0, 62, 0, 62)
	holder.BackgroundTransparency = 1
	holder.Parent                 = card

	local fn = _G.LP_makeViewport
	if type(fn) ~= "function" then
		-- LoadoutPreviewClient 가 아직 안 떴을 수 있다. 잠깐 기다렸다 한 번 더.
		task.spawn(function()
			for _ = 1, 20 do
				task.wait(0.25)
				if type(_G.LP_makeViewport) == "function" then
					_G.LP_makeViewport(holder, "RunnerItemPreviews", weaponId)
					fitThumbnail(holder, weaponId)
					return
				end
			end
			warn("[WeaponTrial] _G.LP_makeViewport 없음 — 썸네일 생략: " .. weaponId)
		end)
		return
	end
	fn(holder, "RunnerItemPreviews", weaponId)
	fitThumbnail(holder, weaponId)
end

local function makeCard(w, order)
    local color = RARITY[w.rarity] or RARITY.Normal

    local card = Instance.new("TextButton")
    card.Name             = w.id
    card.LayoutOrder      = order
    card.BackgroundColor3 = Color3.fromRGB(40, 43, 50)
    card.BorderSizePixel  = 0
    card.Text             = ""
    card.AutoButtonColor  = false
    card.Parent           = scroll
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

    local edge = Instance.new("Frame")   -- 좌측 레어도 띠
    edge.Size             = UDim2.new(0, 4, 1, -16)
    edge.Position         = UDim2.new(0, 8, 0, 8)
    edge.BackgroundColor3 = color
    edge.BorderSizePixel  = 0
    edge.Parent           = card
    Instance.new("UICorner", edge).CornerRadius = UDim.new(0, 2)

    -- ⚠️ 텍스트 폭에서 썸네일 자리(우측 62 + 여백)를 뺀다. 안 빼면 긴 이름이 겹친다.
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size                   = UDim2.new(1, -100, 0, 24)
    nameLbl.Position               = UDim2.new(0, 20, 0, 10)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text                   = w.name
    nameLbl.TextColor3             = Color3.fromRGB(240, 240, 245)
    nameLbl.TextScaled             = true
    nameLbl.Font                   = Enum.Font.GothamBold
    nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
    nameLbl.Parent                 = card

    local rareLbl = Instance.new("TextLabel")
    rareLbl.Size                   = UDim2.new(1, -100, 0, 16)
    rareLbl.Position               = UDim2.new(0, 20, 0, 34)
    rareLbl.BackgroundTransparency = 1
    rareLbl.Text                   = string.upper(w.rarity)
    rareLbl.TextColor3             = color
    rareLbl.TextScaled             = true
    rareLbl.Font                   = Enum.Font.GothamBold
    rareLbl.TextXAlignment         = Enum.TextXAlignment.Left
    rareLbl.Parent                 = card

    local shortLbl = Instance.new("TextLabel")
    shortLbl.Size                   = UDim2.new(1, -100, 0, 18)
    shortLbl.Position               = UDim2.new(0, 20, 0, 52)
    shortLbl.BackgroundTransparency = 1
    shortLbl.Text                   = w.short
    shortLbl.TextColor3             = Color3.fromRGB(165, 170, 180)
    shortLbl.TextScaled             = true
    shortLbl.Font                   = Enum.Font.Gotham
    shortLbl.TextXAlignment         = Enum.TextXAlignment.Left
    shortLbl.Parent                 = card

    -- 🖼️ 3D 썸네일. 키는 modelName 이다 — RunnerItemPreviews 의 폴더 키가 그것이고,
    --   WeaponData 주석(2행)에 "modelName = RunnerItemPreviews 키(=id)" 로 명시돼 있다.
    addThumbnail(card, w.modelName)

    -- 상세 설명은 호버로. 카드에 다 넣으면 목록이 안 읽힌다.
    card.MouseEnter:Connect(function()
        card.BackgroundColor3 = Color3.fromRGB(54, 58, 68)
        hint.Text = w.desc
        hint.TextColor3 = Color3.fromRGB(200, 205, 215)
    end)
    card.MouseLeave:Connect(function()
        card.BackgroundColor3 = Color3.fromRGB(40, 43, 50)
        hint.Text = "Training only — you cannot take these into a round."
        hint.TextColor3 = Color3.fromRGB(150, 155, 165)
    end)

    card.Activated:Connect(function()
        pickEvent:FireServer(w.id)
        gui.Enabled = false
    end)
end

-- ── King 도구 정의 ─────────────────────────────────────────────
-- ⚠️ WeaponData 에 넣지 않는다. 그 모듈은 인벤·상점·로드아웃이 같이 읽으므로
--   PushTool 을 끼워넣으면 그쪽 목록에도 전부 나타난다.
--   훈련장 전용이니 여기서만 정의한다.
local KING_TOOLS = {
	{
		id       = "PushTool",
		name     = "King's Fist",
		rarity   = "Legendary",
		short    = "Push and slam",
		desc     = "The King's only melee tool. Tap to shove, hold to charge a heavy slam "
		        .. "that knocks runners down. Pushing them back into the item lane is how the King scores.",
		modelName = "PushTool",
	},
}

-- ── 카드 렌더 ──────────────────────────────────────────────────
-- ⚠️ 탭을 바꿀 때마다 다시 그린다. 부팅 시 한 번만 만들면 탭이 의미가 없다.
-- ⚠️ `function refreshCards()` 로 쓰면 안 된다 — 그건 전역 함수라
--   위의 `local refreshCards` 와 별개 변수가 되고, setRole 이 보는 로컬은 계속 nil 이다.
--   (문법 검사는 통과하고 탭만 조용히 안 먹는다)
--   반드시 `refreshCards = function()` 으로 로컬에 대입한다.
refreshCards = function()
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	-- UIListLayout 은 스크롤 자식이라 같이 지워진다 → 다시 만든다
	local lay = Instance.new("UIListLayout")
	lay.Padding   = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent    = scroll

	local list = (currentRole == ROLE_KING) and KING_TOOLS or WeaponData
	for i, w in ipairs(list) do
		makeCard(w, i)
	end
end

refreshCards()

-- ── 열고 닫기 ──────────────────────────────────────────────────
local function setOpen(open)
    gui.Enabled = open
end

openEvent.OnClientEvent:Connect(function()
    setOpen(true)
end)

close.Activated:Connect(function() setOpen(false) end)
dim.Activated:Connect(function() setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
        setOpen(false)
    end
end)

-- 라운드가 시작되면 열려 있어도 닫는다
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
    local phase = ReplicatedStorage:GetAttribute("RoundPhase")
    if phase and phase ~= "intermission" then setOpen(false) end
end)

print("✅ WeaponTrialClient 활성화 (무기 " .. #WeaponData .. "종)")
