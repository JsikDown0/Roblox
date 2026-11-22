local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

-- ── 모바일 대응 UIScale + 노치 회피 ────────────────────────────
do
	local _gui = script.Parent
	pcall(function() _gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	local _camera = workspace.CurrentCamera
	local _uiScale = _gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", _gui)
	local _BASE_W, _BASE_H = 1280, 720
	local function _update()
		local vp = _camera.ViewportSize
		-- [INVEN-SCALE] 0.85 → 0.72 (2026-08-21): PC 에서 패널이 화면을 너무 많이 차지했다.
		--   뷰포트의 몇 %를 기준 해상도(1280×720)에 할당할지를 정하는 계수다.
		--   ⚠️ 아래 하한(0.55)은 모바일 가독성 하한이라 건드리지 않는다.
		local s = math.min((vp.X * 0.72) / _BASE_W, (vp.Y * 0.72) / _BASE_H, 1)
		_uiScale.Scale = math.max(s, 0.55)
	end
	_camera:GetPropertyChangedSignal("ViewportSize"):Connect(_update)
	_update()
end

local player = Players.LocalPlayer

local uniGui    = script.Parent
local canvas    = uniGui:WaitForChild("Canvas")
local mainFrame = canvas:WaitForChild("Main")
local mainImg   = mainFrame:WaitForChild("Main")  -- 어두운 ImageLabel (건드리지 않음)

-- 패널 색 관련 ImageLabel (탭 전환 시 Image+ImageColor3만 스왑)
local colorImg = mainFrame:FindFirstChild("Color")
local glowImg  = mainFrame:FindFirstChild("Glow")

-- UI 요소
local container   = mainFrame:WaitForChild("Container")
local closeBtn    = mainFrame:WaitForChild("Close")
local equipBtn    = mainFrame:WaitForChild("Equip")
local tooltip     = mainFrame:WaitForChild("Tooltip")
local tooltipMain = tooltip:WaitForChild("Main")

local checkmarkSource = uniGui:FindFirstChild("checkmark")
if checkmarkSource then checkmarkSource.Visible = false end

_G.openUnifiedInven  = function() end
_G.closeUnifiedInven = function() end
canvas.Visible = false

-- ── Remotes ──────────────────────────────────────────────────
local getLoadout        = ReplicatedStorage:WaitForChild("GetPlayerLoadout")
local setLoadout        = ReplicatedStorage:WaitForChild("SetPlayerLoadout")
local getRunnerLoadout  = ReplicatedStorage:WaitForChild("GetRunnerLoadout")
local setRunnerLoadout  = ReplicatedStorage:WaitForChild("SetRunnerLoadout")
local getEffectData     = ReplicatedStorage:WaitForChild("GetEffectData")
local setEquippedEffect = ReplicatedStorage:WaitForChild("SetEquippedEffect")

-- ── 탭 정의 ──────────────────────────────────────────────────
-- theme: 원본 UI의 Color/Glow ImageLabel 설정을 그대로 사용 (색 왜곡 방지)
local TABS = {
    {
        id="Tagger", label="King", btnColor=Color3.fromRGB(210,50,50),
        maxEquip=4, multiEquip=true, scrollColor=Color3.fromRGB(220,50,50),
        theme={
            colorImage="rbxassetid://17631641332",   colorTint=Color3.fromRGB(210,50,50),
            glowImage="rbxassetid://85236543747195",  glowTint=Color3.fromRGB(255,255,255),
            glowSize=UDim2.new(1.062,0,1.035,0),
            titleImage="rbxassetid://17631640835",
            -- 탭 버튼 tint: 이미지가 반투명이라 IC3로 색을 직접 제공
            tabTint=Color3.fromRGB(220,50,50),
        },
    },
    {
        id="Runner", label="Runner", btnColor=Color3.fromRGB(30,130,255),
        maxEquip=4, multiEquip=true, scrollColor=Color3.fromRGB(30,130,255),
        theme={
            colorImage="rbxassetid://17631641332",   colorTint=Color3.fromRGB(30,146,255),
            glowImage="rbxassetid://17631641572",     glowTint=Color3.fromRGB(30,145,254),
            glowSize=UDim2.new(1.124,0,1.300,0),
            titleImage="rbxassetid://17631640835",
            tabTint=Color3.fromRGB(30,130,255),
        },
    },
    {
        id="KillEffect", label="Kill Effects", btnColor=Color3.fromRGB(140,55,210),
        maxEquip=1, multiEquip=false, scrollColor=Color3.fromRGB(150,80,220),
        theme={
            colorImage="rbxassetid://96390466983137", colorTint=Color3.fromRGB(255,255,255),
            glowImage="rbxassetid://86262873565243",   glowTint=Color3.fromRGB(85,0,127),
            titleImage="rbxassetid://135955394920556",
            glowSize=UDim2.new(1.124,0,1.300,0),
            -- 이미지 자체에 보라색이 있으므로 흰색 유지
            tabTint=Color3.fromRGB(255,255,255),
        },
    },
    {
        id="Emote", label="Emotes", btnColor=Color3.fromRGB(45,190,75),
        maxEquip=6, multiEquip=true, scrollColor=Color3.fromRGB(50,200,80),
        theme={
            colorImage="rbxassetid://93274134837793",  colorTint=Color3.fromRGB(255,255,255),
            glowImage="rbxassetid://112337885815958",   glowTint=Color3.fromRGB(254,254,254),
            titleImage="rbxassetid://70444162484959",
            glowSize=UDim2.new(1.129,0,1.300,0),
            -- 이미지 자체에 초록색이 있으므로 흰색 유지
            tabTint=Color3.fromRGB(255,255,255),
        },
    },
}

local activeTab = TABS[1]
local runnerFilter       = "item"  -- Runner 탭 하위 필터: "item"(로드아웃) | "weapon"(2단계무기) | "dash" | "trail"
local taggerFilter       = "item"  -- Tagger 탭 하위 필터: "item"(로드아웃) | "weapon"(푸시툴) | "crown"(왕관 스킨)

-- ── 트레일 썸네일 리본 (UIGradient 색띠) ──────────────────────────
-- 트레일은 ViewportFrame(3D)으로 못 보여줌(Trail은 어태치먼트 이동 궤적이라 정적 미리보기 불가).
-- → 리본 PNG 1장에 UIGradient로 색(머리→꼬리)+투명도 페이드를 입혀 표현.
-- 색 스펙은 RunnerTrail.TRAIL_SKINS_SPEC와 동기화 필요(트레일 추가/색변경 시 양쪽 수정).
local RunService = game:GetService("RunService")
local TRAIL_RIBBON_ASSET = "rbxassetid://119908323751613"
local TRAIL_RIBBON = {
	trail_white        = { kind="solid", c=Color3.fromRGB(255,255,255) },
	trail_crimson      = { kind="solid", c=Color3.fromRGB(255,60,40) },
	trail_cyan         = { kind="solid", c=Color3.fromRGB(80,220,255) },
	trail_violet       = { kind="solid", c=Color3.fromRGB(170,70,255) },
	trail_toxic        = { kind="solid", c=Color3.fromRGB(120,255,60) },
	trail_amber        = { kind="solid", c=Color3.fromRGB(255,140,20) },
	trail_black        = { kind="solid", c=Color3.fromRGB(10,10,12) },
	trail_sunset       = { kind="grad", from=Color3.fromRGB(255,140,20), to=Color3.fromRGB(255,79,160) },
	trail_vaporwave    = { kind="grad", from=Color3.fromRGB(40,220,255), to=Color3.fromRGB(255,60,200) },
	trail_ocean        = { kind="grad", from=Color3.fromRGB(32,224,192), to=Color3.fromRGB(32,80,255) },
	trail_ice          = { kind="stripes", a=Color3.fromRGB(255,255,255), b=Color3.fromRGB(120,205,255) },
	trail_shadow       = { kind="grad", from=Color3.fromRGB(130,130,138), to=Color3.fromRGB(15,15,20) },
	trail_rainbow      = { kind="rainbow" },
	trail_rainbowcycle = { kind="cycle" },
	trail_watermelon   = { kind="stripes", a=Color3.fromRGB(255,55,70), b=Color3.fromRGB(18,14,16) },
}
local TRAIL_RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255,64,64)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255,154,32)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255,230,40)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(88,232,74)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(40,200,255)),
	ColorSequenceKeypoint.new(1.0, Color3.fromRGB(176,96,255)),
})
local TRAIL_RIBBON_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),   -- 머리: 진함
	NumberSequenceKeypoint.new(1, 0.85),   -- 꼬리: 페이드
})
local function makeTrailRibbon(spec, parent)
	-- ⚪ [2026-09-02] 리본 뒤에 흰 리본을 살짝 크게 깔아 실루엣 테두리를 만든다.
	--   [증상] Black Trail 이 슬롯 배경(16,19,28)에 묻혀 형태가 안 보였다.
	--   [실패한 접근] img 에 UIStroke(ApplyStrokeMode.Contextual)를 걸었다. 두께를
	--     1.5 → 2.5 로 올려도 리본 윤곽이 아니라 '사각 프레임'만 진해졌다.
	--     원인: 이 ImageLabel 에는 UIGradient 가 씌워져 있고 꼬리 쪽 Transparency 가
	--     0.85 라, 스트로크가 알파를 제대로 따라가지 못한다.
	--   [해결] 같은 리본 에셋을 흰색으로 한 장 더 깔고 살짝 키운다. 형태가 정확히
	--     같으므로 가장자리에만 흰 테두리가 남는다. 그라디언트 영향도 안 받는다.
	--   ⚠️ 아웃라인에는 UIGradient 를 붙이지 않는다. 붙이면 본체와 같이 어두워져 무의미해진다.
	--   ⚠️ [필수] 이 인스턴스는 슬롯 정리 목록 3곳에 반드시 등록돼 있어야 한다
	--     (DYN 배열 / populate 의 제거 루프 / mainF 개별 제거). 하나라도 빠지면
	--     탭 전환 시 흰 리본이 남아 다음 아이템과 겹친다 — 실제로 그렇게 터졌다.
	local outline = Instance.new("ImageLabel")
	outline.Name = "_TrailRibbonOutline"
	outline.Image = TRAIL_RIBBON_ASSET
	outline.ImageColor3 = Color3.fromRGB(255, 255, 255)
	outline.ImageTransparency = 0.15
	outline.BackgroundTransparency = 1
	outline.ScaleType = Enum.ScaleType.Fit
	outline.Size = UDim2.new(0.96, 0, 0.96, 0)   -- 본체(0.9)보다 약간 크게 = 테두리 두께
	outline.AnchorPoint = Vector2.new(0.5, 0.5)
	outline.Position = UDim2.new(0.5, 0, 0.5, 0)
	outline.ZIndex = -1   -- 본체(0)보다 뒤. 둘 다 이름 라벨(ZIndex 1)보다 아래여야 한다
	outline.Parent = parent

	local img = Instance.new("ImageLabel")
	img.Name = "_TrailRibbon"
	img.Image = TRAIL_RIBBON_ASSET
	img.ImageColor3 = Color3.fromRGB(255,255,255)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.new(0.9, 0, 0.9, 0)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.ZIndex = 0   -- 텍스트(이름 라벨, ZIndex=1)보다 뒤로. Main 그룹에 넣어야 유효(Sibling 모드)
	local grad = Instance.new("UIGradient")
	grad.Rotation = -39   -- 리본 머리(좌하)→꼬리(우상) 축. F5로 미세조정
	grad.Transparency = TRAIL_RIBBON_TRANSPARENCY
	if spec.kind == "solid" then
		grad.Color = ColorSequence.new(spec.c)
	elseif spec.kind == "grad" then
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, spec.from),
			ColorSequenceKeypoint.new(1, spec.to),
		})
	elseif spec.kind == "rainbow" then
		grad.Color = TRAIL_RAINBOW_SEQ
	elseif spec.kind == "cycle" then
		grad.Color = ColorSequence.new(Color3.fromHSV(0, 1, 1))
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not img.Parent then conn:Disconnect() return end
			grad.Color = ColorSequence.new(Color3.fromHSV((tick()*0.6)%1, 1, 1))
		end)
	elseif spec.kind == "stripes" then
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, spec.a),
			ColorSequenceKeypoint.new(0.24, spec.a),
			ColorSequenceKeypoint.new(0.26, spec.b),
			ColorSequenceKeypoint.new(0.49, spec.b),
			ColorSequenceKeypoint.new(0.51, spec.a),
			ColorSequenceKeypoint.new(0.74, spec.a),
			ColorSequenceKeypoint.new(0.76, spec.b),
			ColorSequenceKeypoint.new(1.00, spec.b),
		})
	end
	grad.Parent = img
	-- ⚠️ [2026-09-02] 본체는 0 그대로 둔다. 아웃라인을 깔면서 1 로 올렸더니
	--   이름 라벨(ZIndex 1)과 같은 층이 되어 리본이 글자를 가렸다(실측).
	--   층 순서: 아웃라인(-1) < 본체(0) < 이름 라벨(1)
	img.Parent = parent
	return img
end

-- ── 대시 썸네일 (인간형 잔상 + UIGradient 색 + 빛 외곽선) ──────────
-- dash는 산데비스탄 잔상. 흰색 인간형 잔상 PNG 1장 + UIGradient로 색 입힘.
-- 모든 dash에 UIStroke 빛 외곽선 → Shadow(검정) 윤곽 살리고 사이버펑크 발광 효과.
-- 색 스펙은 RunnerDive.DASH_SKIN_COLORS / DASH_SKIN_SPECIAL과 동기화 필요.
local DASH_ICON_ASSET = "rbxassetid://125759196762053"
local DASH_ICON = {
	dash_default   = { kind="solid", c=Color3.fromRGB(80,220,255) },
	dash_red       = { kind="solid", c=Color3.fromRGB(255,60,40) },
	dash_violet    = { kind="solid", c=Color3.fromRGB(170,70,255) },
	dash_toxic     = { kind="solid", c=Color3.fromRGB(120,255,60) },
	dash_magenta   = { kind="solid", c=Color3.fromRGB(255,60,200) },
	dash_amber     = { kind="solid", c=Color3.fromRGB(255,140,20) },
	dash_cobalt    = { kind="solid", c=Color3.fromRGB(50,90,255) },
	dash_spectral  = { kind="solid", c=Color3.fromRGB(255,255,255) },
	dash_ice       = { kind="solid", c=Color3.fromRGB(150,235,255) },
	dash_solar     = { kind="solid", c=Color3.fromRGB(255,230,40) },
	dash_prism     = { kind="cycle" },
	dash_vaporwave = { kind="grad", from=Color3.fromRGB(40,220,255), to=Color3.fromRGB(255,60,200) },
	dash_shadow    = { kind="grad", from=Color3.fromRGB(120,120,130), to=Color3.fromRGB(30,28,42) },
	dash_watermelon = { kind="grad", from=Color3.fromRGB(255,55,70), to=Color3.fromRGB(70,200,80) },
}
local function makeDashIcon(spec, parent)
	local img = Instance.new("ImageLabel")
	img.Name = "_DashIcon"
	img.Image = DASH_ICON_ASSET
	img.ImageColor3 = Color3.fromRGB(255,255,255)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.new(0.9, 0, 0.9, 0)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.ZIndex = 0   -- 텍스트(이름 라벨)보다 뒤. Main 그룹에 넣어야 유효
	local grad = Instance.new("UIGradient")
	if spec.kind == "solid" then
		grad.Color = ColorSequence.new(spec.c)
	elseif spec.kind == "grad" then
		grad.Rotation = 0   -- 가로(왼쪽 잔상→오른쪽 메인). F5로 방향 조정
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, spec.to),    -- 왼쪽=잔상
			ColorSequenceKeypoint.new(1, spec.from),  -- 오른쪽=메인
		})
	elseif spec.kind == "cycle" then
		grad.Color = ColorSequence.new(Color3.fromHSV(0, 1, 1))
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not img.Parent then conn:Disconnect() return end
			grad.Color = ColorSequence.new(Color3.fromHSV((tick()*0.6)%1, 1, 1))
		end)
	end
	grad.Parent = img
	-- 빛 외곽선 (모든 dash 공통)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255,255,255)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = img
	img.Parent = parent
	return img
end
-- LoadoutPreview 재사용용: 대시/트레일 절차적 썸네일 노출 (같은 클라 _G 공유)
_G.LP_makeDashIcon = function(parent, id)
	local spec = DASH_ICON[id]
	if not spec then return false end
	makeDashIcon(spec, parent)
	return true
end
_G.LP_makeTrailRibbon = function(parent, id)
	local spec = TRAIL_RIBBON[id]
	if not spec then return false end
	makeTrailRibbon(spec, parent)
	return true
end

local applyTaggerFilterVisual  -- forward 선언 (탭 전환 시 칩 비주얼-필터값 동기화용)
local cachedItems        = {}
local templateMap        = {}
local equippedIds        = {}
local currentTooltipItem = nil
local warningThread      = nil
local warningTween       = nil

-- ── 레어리티 ─────────────────────────────────────────────────
local LOCKED_GRADIENT = ColorSequence.new(Color3.fromRGB(60,60,60), Color3.fromRGB(100,100,100))
local rarityGradient = {
    Normal    = ColorSequence.new(Color3.fromRGB(180,180,180), Color3.fromRGB(255,255,255)),
    Rare      = ColorSequence.new(Color3.fromRGB(40,160,40),   Color3.fromRGB(120,255,120)),
    Epic      = ColorSequence.new(Color3.fromRGB(120,40,200),  Color3.fromRGB(200,120,255)),
    Legendary = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255,200,0)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,130,0)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(255,200,0)),
    }),
}
-- 스킨 카드 테두리 단색 (ImageColor3 곱셈 틴트용: 밝은 테두리만 물들고 어두운 배경은 유지)
local RARITY_BORDER = {
    Normal    = Color3.fromRGB(210, 210, 210),
    Rare      = Color3.fromRGB(80, 200, 90),
    Epic      = Color3.fromRGB(170, 95, 240),
    Legendary = Color3.fromRGB(255, 180, 30),
}
-- 태거 아이템 기능 분류 배지. 원본은 LoadoutManager.ALL_ITEMS 의 category 필드.
-- ⚠️ 여기 없는 키(러너 아이템 등)는 배지를 안 붙이고 등급만 그대로 보여준다.
local CAT_LABEL = { roll = "ROLL", throw = "THROW", trap = "TRAP", aoe = "AOE" }

-- 🆓 무료 로테이션. ⚠️ 서버(LoadoutManager)와 같은 모듈을 써야 표시와 판정이 일치한다.
local FreeRotation = require(game:GetService("ReplicatedStorage"):WaitForChild("FreeRotation"))

-- 등급 라벨 기본색. ⚠️ 카드는 재사용되므로 FREE 표시로 초록이 된 라벨이
--    다음 카드에 그대로 남는다. 매번 명시적으로 되돌려야 한다.
local RARITY_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
-- Per-item inventory-card camera override (PreviewTuner-baked, world-space target model).
-- Keyed by item id. dist=DistMul, dir=CameraDirection, target=look target (x item size).
local ITEM_CAM = {
    ["tnt"] = { dist = 1.40, dir = Vector3.new(1.300, -0.050, 1.000), target = Vector3.new(-0.500, 0.000, -0.300) },
}
local GREEN_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(68,68,195)),
    ColorSequenceKeypoint.new(0.21, Color3.fromRGB(0,255,0)),
    ColorSequenceKeypoint.new(0.92, Color3.fromRGB(133,236,95)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(0,255,0)),
})
local RED_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(120,20,20)),
    ColorSequenceKeypoint.new(0.21, Color3.fromRGB(220,40,40)),
    ColorSequenceKeypoint.new(0.92, Color3.fromRGB(255,80,80)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(200,30,30)),
})

-- ⚔️ [2026-09-02] '장착 중이라 누를 게 없음'을 알리는 회색. 무기 탭 전용.
--   초록(Equip)·빨강(Unequip)과 달리 '동작 없음'이라 채도를 뺀다.
local GRAY_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(70,74,84)),
    ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(105,110,124)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(70,74,84)),
})

-- ── Tooltip 요소 ─────────────────────────────────────────────
local tooltipNameLabel, tooltipRarityLabel
local tidx = 0
for _, c in ipairs(tooltipMain:GetChildren()) do
    if c:IsA("TextLabel") then
        tidx += 1
        if tidx == 1 then tooltipNameLabel   = c end
        if tidx == 2 then tooltipRarityLabel = c end
    end
end
local tooltipEquip  = tooltipMain:FindFirstChild("Equip")
local tooltipSkin   = tooltipMain:FindFirstChild("Skin")
local tooltipClose2 = tooltipMain:FindFirstChild("Close2")
local equipTextLabel = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("TextLabel")
local equipGradient  = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("UIGradient")
-- tooltipSkin: showTooltip에서 탭별로 제어 (Tagger만 표시)

-- ── 하단 Equip 레이블 ─────────────────────────────────────────
local bottomEquipLabel = equipBtn
    and equipBtn:FindFirstChild("Main")
    and equipBtn.Main:FindFirstChildWhichIsA("TextLabel")

-- 단일 장착(최대 1개) 필터 집합. 여기 없는 것만 "N/최대" 멀티 카운터를 쓴다.
--   ⚠️ [버그수정 2026-09-02] 예전엔 조건을 or 로 나열했는데 dash·trail 이 빠져 있어
--     Trail 탭에서 "1/4 Equipped" 가 떴다(단일 장착인데 아이템 기준 maxEquip=4 사용).
--     목록 나열 방식은 항목이 늘 때마다 빠뜨린다 → 집합으로 뒤집는다.
--   ⚠️ 새 코스메틱 필터를 추가하면 여기에 등록할 것. 멀티 장착인 것만 빼면 된다
--     (현재 멀티: Runner/Tagger 의 item, 이모트).
local SINGLE_EQUIP_FILTER = {
    Runner = { weapon = true, dash = true, trail = true },
    Tagger = { crown = true, weapon = true, trail = true },
}

local function refreshBottomLabel()
    if not bottomEquipLabel then return end
    local n = #equippedIds
    local filt = (activeTab.id == "Runner") and runnerFilter
              or (activeTab.id == "Tagger") and taggerFilter
              or nil
    local isSingle = (not activeTab.multiEquip)
        or (filt ~= nil and SINGLE_EQUIP_FILTER[activeTab.id] ~= nil
            and SINGLE_EQUIP_FILTER[activeTab.id][filt] == true)
    if n == 0 then
        bottomEquipLabel.Text = "None Equipped"
    elseif isSingle then
        bottomEquipLabel.Text = "1 Equipped"
    else
        bottomEquipLabel.Text = n .. "/" .. activeTab.maxEquip .. " Equipped"
    end
end

-- ── 경고 UI ──────────────────────────────────────────────────
local oldWarn = mainFrame:FindFirstChild("_EquipWarning")
if oldWarn then oldWarn:Destroy() end
local warningFrame = Instance.new("Frame")
warningFrame.Name = "_EquipWarning"
warningFrame.Size = UDim2.new(0.75,0,0,60)
warningFrame.AnchorPoint = Vector2.new(0.5,0)
warningFrame.Position = UDim2.new(0.5,0,0,8)
warningFrame.BackgroundColor3 = Color3.fromRGB(200,50,50)
warningFrame.BackgroundTransparency = 0.1
warningFrame.ZIndex = 20
warningFrame.Visible = false
warningFrame.Parent = mainFrame
Instance.new("UICorner", warningFrame).CornerRadius = UDim.new(0,10)
local warnLabel = Instance.new("TextLabel", warningFrame)
warnLabel.Size = UDim2.new(1,-10,1,0)
warnLabel.Position = UDim2.new(0,5,0,0)
warnLabel.BackgroundTransparency = 1
warnLabel.TextColor3 = Color3.fromRGB(255,255,255)
warnLabel.TextScaled = true
warnLabel.Font = Enum.Font.GothamBold
warnLabel.ZIndex = 21

local function showWarning(msg)
    warnLabel.Text = "⚠️  " .. (msg or "You don't own this item!")
    if warningTween  then warningTween:Cancel() end
    if warningThread then task.cancel(warningThread) end
    warningFrame.BackgroundTransparency = 0.1
    warningFrame.Visible = true
    warningThread = task.delay(1.5, function()
        warningTween = TweenService:Create(warningFrame, TweenInfo.new(0.4), {BackgroundTransparency=1})
        warningTween:Play()
        warningTween.Completed:Connect(function()
            warningFrame.Visible = false
            warningFrame.BackgroundTransparency = 0.1
        end)
    end)
end

-- ── 테마 업데이트 (핵심: mainImg.ImageColor3 절대 건드리지 않음) ──
local function updateTheme()
    local t = activeTab.theme

    -- Color ImageLabel: 탭별 원본 이미지+tint 적용
    if colorImg then
        colorImg.Image        = t.colorImage
        colorImg.ImageColor3  = t.colorTint
    end
    -- Glow ImageLabel: 탭별 원본 이미지+tint 적용
    if glowImg then
        glowImg.Image       = t.glowImage
        glowImg.ImageColor3 = t.glowTint
        glowImg.Size        = t.glowSize
    end

    -- 스크롤바 색상 탭별 적용
    local container = mainFrame:FindFirstChild("Container")
    if container then container.ScrollBarImageColor3 = activeTab.scrollColor end

    -- 툴팁 테두리 색상 탭별 적용
    local tooltipStroke     = tooltip:FindFirstChildWhichIsA("UIStroke")
    local tooltipMainStroke = tooltipMain:FindFirstChildWhichIsA("UIStroke")
    local c1 = (activeTab and activeTab.btnColor) or Color3.fromRGB(255,255,255)
    local c2 = c1:Lerp(Color3.fromRGB(255,255,255), 0.3)
    local tabGradient = ColorSequence.new(c1, c2)
    if tooltipStroke then
        local grad = tooltipStroke:FindFirstChildWhichIsA("UIGradient")
        if grad then grad.Color = tabGradient
        else tooltipStroke.Color = c1 end
    end
    if tooltipMainStroke then
        local grad = tooltipMainStroke:FindFirstChildWhichIsA("UIGradient")
        if grad then grad.Color = tabGradient
        else tooltipMainStroke.Color = c1 end
    end

    -- Title 배너 텍스트 + 이미지 교체 (탭별 모양이 다름)
    local titleFrame = mainImg:FindFirstChild("Title")
    local titleMain  = titleFrame and titleFrame:FindFirstChild("Main")
    if titleMain then
        titleMain.Image       = t.titleImage
        titleMain.ImageColor3 = t.tabTint  -- Tagger=빨강, Runner=파랑, 나머지=흰색
        local tl = titleMain:FindFirstChild("TextLabel")
        if tl then tl.Text = activeTab.label end
    end

    -- 탭 버튼 활성/비활성 (투명도로 구분 + 각 탭 원본 이미지 적용)
    for _, def in ipairs(TABS) do
        local tab = canvas:FindFirstChild("_Tab_" .. def.id)
        if not tab then continue end
        local tabMain = tab:FindFirstChild("Main")
        if not tabMain then continue end
        tabMain.Image      = def.theme.titleImage
        tabMain.ImageColor3 = def.theme.tabTint  -- 탭별 정확한 tint 적용
        if def.id == activeTab.id then
            tabMain.ImageTransparency = 0
        else
            tabMain.ImageTransparency = 0.35
        end
    end

    -- Runner 필터 칩: Runner 탭에서만 표시. 필터값은 탭 사이를 오가도 유지(persist) — 인벤 새로 열 때만 item으로 초기화.
    local chip = mainFrame:FindFirstChild("_RunnerFilter")
    if chip then
        chip.Visible = (activeTab.id == "Runner")
    end

    -- Tagger 필터 칩: Tagger 탭에서만 표시. 필터값은 탭 사이를 오가도 유지(persist) — 인벤 새로 열 때만 item으로 초기화.
    local tchip = mainFrame:FindFirstChild("_TaggerFilter")
    if tchip then
        tchip.Visible = (activeTab.id == "Tagger")
        -- 칩 강조 표시를 현재 taggerFilter 값에 항상 맞춤 (비주얼↔값 동기화)
        if applyTaggerFilterVisual then applyTaggerFilterVisual() end
    end
end

-- ── 데이터 정규화 ─────────────────────────────────────────────
local function normalizeData(tabId)
    local result = {}
    if tabId == "Tagger" then
        if taggerFilter == "crown" then
            return getEffectData:InvokeServer("crownSkin") or {}
        elseif taggerFilter == "trail" then
            -- Runner 탭의 trail 과 완전히 동일한 소스 — 트레일은 역할 공용이라
            -- 어느 탭에서 장착하든 같은 TrailSkin 속성을 바꾼다.
            return getEffectData:InvokeServer("trailSkin") or {}
        elseif taggerFilter == "weapon" then
            -- 2단계 태거 무기: 푸시툴(자동 지급). 선택 없이 표시만(항상 장착됨).
            return {
                { id="PushTool", name="Push Tool", icon="", imageId="",
                  rarity="Rare", owned=true, equipped=true },
            }
        end
        -- item: 태거 로드아웃 전체 (멀티 장착)
        local data = getLoadout:InvokeServer()
        if not data then return result end
        local loadoutSet = {}
        for _, n in ipairs(data.loadout or {}) do loadoutSet[n] = true end
        for _, item in ipairs(data.allItems or {}) do
            local owned = not item.locked and not (item.premium and not data.hasPass)
            table.insert(result, {
                id=item.name, name=item.displayName or item.name,
                icon="", imageId=item.icon or "",
                rarity=item.rarity or "Normal", rotation=item.rotation or 0,
                owned=owned, equipped=loadoutSet[item.name]==true,
                -- 구매 가능 판정용. getLoadout이 ALL_ITEMS 항목을 통째로 복사해 보내므로 그대로 통과시킴.
                -- shopId 있으면 코인샵에서 살 수 있음 / premium=게임패스, unlockAttr=그룹보상 → 못 삼.
                shopId=item.shopId, premium=item.premium, unlockAttr=item.unlockAttr,
                -- 기능 분류(roll/throw/trap/aoe). LoadoutManager.ALL_ITEMS 에 선언되어 있다.
                -- ⚠️ 여기 명시적으로 안 적으면 클라까지 안 온다. 위 필드들처럼 하나씩 골라 담는 구조라
                --    ALL_ITEMS 에 필드를 추가하는 것만으로는 전달되지 않는다.
                category=item.category,
                -- 🆓 오늘의 무료 로테이션 여부 / 실제 보유 여부
                freeToday=item.freeToday, ownedReal=item.ownedReal,
            })
        end
    elseif tabId == "Runner" then
        if runnerFilter == "dash" then
            return getEffectData:InvokeServer("dashSkin") or {}
        elseif runnerFilter == "trail" then
            return getEffectData:InvokeServer("trailSkin") or {}
        elseif runnerFilter == "weapon" then
            -- 2단계 무기(칼 등): 단일 장착. 서버가 player의 EquippedWeapon 속성에 저장하므로
            -- 그 값을 읽어 현재 장착 무기를 체크 표시.
            local equippedWeapon = game.Players.LocalPlayer:GetAttribute("EquippedWeapon") or ""
            local WeaponData = require(game:GetService("ReplicatedStorage"):WaitForChild("WeaponData"))
            local lpW = game.Players.LocalPlayer
            local out = {}
            for _, w in ipairs(WeaponData) do
                out[#out + 1] = {
                    id = w.id, name = w.name, icon = "", imageId = "", rarity = w.rarity,
                    owned = (lpW:GetAttribute("OwnedItem_" .. w.id) == true) or (w.id == "ClassicSword"),
                    equipped = (equippedWeapon == w.id),
                }
            end
            return out
        end
        -- item: 러너 로드아웃 전체 (최대 4개 멀티 장착)
        local data = getRunnerLoadout:InvokeServer()
        if not data then return result end
        local loadoutSet = {}
        for _, n in ipairs(data.loadout or {}) do loadoutSet[n] = true end
        for _, item in ipairs(data.allItems or {}) do
            table.insert(result, {
                id=item.name, name=item.displayName or item.name,
                icon="", imageId=item.icon or "",
                rarity=item.rarity or "Normal",
                owned=not item.locked, equipped=loadoutSet[item.name]==true,
                count=item.consumable and ((data.consumables or {})[item.name] or 0) or nil,
                shopId=item.shopId, premium=item.premium, unlockAttr=item.unlockAttr,
            })
        end
    elseif tabId == "KillEffect" then
        -- 🔢 [정렬 2026-09-09] 예전엔 여기서 바로 return 해서 아래 정렬 블록을 건너뛰었다.
        --   결과가 서버가 준 순서(= 정의 순서) 그대로라 등급이 뒤섞여 보였다.
        --   result 에 담아 흘려보내면 무기·아이템과 같은 규칙으로 정렬된다.
        --   ⚠️ 서버 응답에 rarity 필드가 있어야 정렬된다. 없으면 전부 "Normal" 로
        --     묶여 원래 순서가 유지될 뿐, 깨지지는 않는다(RANK 폴백 99 아님 — or "Normal").
        result = getEffectData:InvokeServer("killEffect") or {}
    elseif tabId == "Emote" then
        -- ⚠️ 이모트는 등급 개념이 약해 정렬 대상에서 뺀다. 필요해지면 위와 같은 형태로 바꾼다.
        return getEffectData:InvokeServer("emote") or {}
    end

    -- ── 정렬: 보유구분(1차) → 등급(2차) → 기능(3차) → 원래 순서(4차) ──────────────
    -- [배경] 예전엔 정렬 코드가 아예 없어서 화면 순서 = ALL_ITEMS 선언 순서였다.
    --        새 아이템을 테이블 끝에 붙여왔으니 결과적으로 '만든 순서'로 보였고,
    --        Epic 다음에 Rare 가 오는 식으로 등급이 뒤섞여 있었다.
    -- [의도] 낮은 등급을 위에 둔다. 신규 유저가 당장 쓸 수 있는 것을 먼저 보고,
    --        아래로 내려갈수록 목표가 보이는 배치다.
    -- ⚠️ table.sort 는 불안정(unstable) 정렬이다. 마지막 키로 원래 인덱스를 반드시 넣어야
    --    같은 묶음 안에서 순서가 새로고침마다 흔들리지 않는다.
    --
    -- 🆓 [2026-09-20] 보유구분을 1차 키로 올린다 — [보유] → [무료 로테] → [나머지].
    --   [왜] 예전엔 보유 여부가 정렬에 아예 없어 보유·미보유가 등급별로 섞여 있었다.
    --     그래서 "오늘 공짜로 쓸 수 있는 것"이 미보유 Epic·Legendary 사이에 묻혔다.
    --     세 층이 되면 "내 것 / 지금만 내 것 / 목표"로 읽힌다.
    --   ⚠️ 기존 의도("낮은 등급을 위에")는 죽지 않았다 — 각 블록 **안에서** 그대로 돈다.
    --     바뀐 건 블록 경계뿐이다.
    --   ♻️ 로테가 끝나면 자동 복구된다. freeToday 가 false 가 되면서 3번 블록으로
    --     돌아가고 그 안 순서는 등급·기능·원래순서라 예전과 완전히 같아진다.
    --     되돌리는 코드를 따로 두지 않는 이유다 — 상태가 아니라 파생값이다.
    --   ⚠️ 탭 이름으로 가르지 않는다. ownedReal / freeToday 속성으로 판별하므로
    --     그 필드가 없는 탭(Runner·KillEffect·Emote)은 전부 3번으로 떨어져 예전과
    --     같은 결과가 나온다("이름 목록보다 속성").
    --     실측: 이 파일에서 ownedReal 을 세우는 곳은 Tagger 분기 한 곳뿐이다.
    --   ⚠️ owned 가 아니라 ownedReal 을 본다. owned 는 "지금 쓸 수 있나"라
    --     로테이션 항목까지 true 다 — 그걸 쓰면 1·2번 블록이 합쳐져 버린다.
    do
        local RANK = { Normal = 1, Rare = 2, Epic = 3, Legendary = 4 }
        local CAT_RANK = { roll = 1, throw = 2, trap = 3, aoe = 4 }
        local function ownGroup(it)
            if it.ownedReal then return 1 end   -- 보유
            if it.freeToday  then return 2 end   -- 오늘 무료 로테 중(미보유)
            return 3                             -- 나머지
        end
        for i, it in ipairs(result) do it._ord = i end
        table.sort(result, function(x, y)
            local gx, gy = ownGroup(x), ownGroup(y)
            if gx ~= gy then return gx < gy end
            local rx = RANK[x.rarity or "Normal"] or 99
            local ry = RANK[y.rarity or "Normal"] or 99
            if rx ~= ry then return rx < ry end
            local cx = CAT_RANK[x.category or ""] or 98
            local cy = CAT_RANK[y.category or ""] or 98
            if cx ~= cy then return cx < cy end
            return x._ord < y._ord
        end)
    end
    return result
end

-- ── 장착 여부 ─────────────────────────────────────────────────
local function isEquipped(id)
    for _, eid in ipairs(equippedIds) do
        if eid == id then return true end
    end
    return false
end

-- ── Tooltip ──────────────────────────────────────────────────
-- ⚔️👑💨 [2026-09-02] 필수 슬롯은 '해제'가 없다 — 빈칸이 존재할 수 없는 자리다.
--   [해당] 러너 무기 / 크라운 / 대시. 셋 다 기본값이 항상 장착돼 있다
--     (ClassicSword / crown_gold / dash_default — EffectSystem.grantFreeSkins).
--   [증상] 장착 중인 항목에 Unequip 이 떠서 눌렀는데 아무 반응이 없었다.
--     서버가 기본값으로 되돌릴 뿐이라 값이 안 바뀌고, 그게 "버튼 먹통"으로 읽힌다.
--   [해결] 버튼을 'Equipped' 회색 비활성으로 바꾸고 클릭을 막는다. 교체는 다른 걸 누르면 된다.
--   ⚠️ 아이템·이모트·트레일·킬이펙트는 제외한다. 그쪽은 '없음'이 유효한 상태다
--     (트레일은 실제로 안 낀 상태가 기본이고, 아이템은 다중 장착이라 해제가 의미 있다).
local function isEssentialSlot()
    if not activeTab then return false end
    if activeTab.id == "Runner" then
        return runnerFilter == "weapon" or runnerFilter == "dash"
    elseif activeTab.id == "Tagger" then
        return taggerFilter == "crown"
    end
    return false
end

local function refreshTooltipButtons()
    if not currentTooltipItem then return end
    local eq = isEquipped(currentTooltipItem.id)
    if isEssentialSlot() and eq then
        -- 이미 장착 중인 필수 항목: 누를 게 없다는 걸 색과 문구로 알린다.
        if equipTextLabel then equipTextLabel.Text = "Equipped" end
        if equipGradient  then equipGradient.Color = GRAY_GRADIENT end
        return
    end
    if equipTextLabel then equipTextLabel.Text = eq and "Unequip" or "Equip" end
    if equipGradient  then equipGradient.Color = eq and RED_GRADIENT or GREEN_GRADIENT end
end

-- 잠긴 아이템 중 "코인샵에서 살 수 있는 것"만 툴팁을 띄워 구매를 유도한다.
-- 못 사는 것(게임패스/그룹보상)은 툴팁이 무의미하므로 기존대로 무반응.
--   shopId    → 코인샵 판매 O
--   premium   → 게임패스 전용 (Frost Dragon)
--   unlockAttr→ 그룹 보상 (ItemNoob)
-- 러너 웨폰(WeaponData)은 shopId 필드가 없지만 전량 코인샵 판매라 탭/필터로 판정.
local function isPurchasable(itemData)
    if not itemData then return false end
    if activeTab and activeTab.id == "Runner" and runnerFilter == "weapon" then return true end
    if itemData.premium then return false end
    if itemData.unlockAttr and not itemData.shopId then return false end
    return itemData.shopId ~= nil
end

-- ════════════════════════════════════════════════════════════════
-- [ITEM-DESC] 아이템 설명 표시.
--   ⚠️ 설명은 ShopSystem 에만 정의돼 있어 인벤 툴팁에는 안 보였다.
--      상점을 안 열면 사용법(후크를 벽에 쏴야 한다 등)을 알 방법이 없다.
--      스타터킷으로 9종을 무료 지급하므로 상점에 갈 이유는 더 줄었다.
--   ⚠️ 설명을 여기 중복 정의하지 않는다 — 상점 정의가 단일 소스.
-- ════════════════════════════════════════════════════════════════
local itemDescs = nil
task.spawn(function()
    local fn = ReplicatedStorage:FindFirstChild("GetItemDescs")
    if not fn then return end
    local ok, res = pcall(function() return fn:InvokeServer() end)
    if ok and type(res) == "table" then itemDescs = res end
end)

-- Level 프레임(0.38)과 Equip 버튼(0.55) 사이 공백에 넣는다.
local tooltipDescLabel = tooltipMain:FindFirstChild("_DescLabel")
if not tooltipDescLabel then
    tooltipDescLabel = Instance.new("TextLabel")
    tooltipDescLabel.Name = "_DescLabel"
    tooltipDescLabel.AnchorPoint = Vector2.new(0.5, 0)
    -- ⚠️ Level(0.29~0.47) 과 Equip(0.49~0.61) 사이엔 0.02 밖에 안 남는다.
    --    설명은 이름·등급 바로 아래(0.28~0.38)에 넣고, 아래 요소들을 밀어낸다.
    tooltipDescLabel.Position = UDim2.fromScale(0.5, 0.275)
    -- 📝 [2026-08-29] 높이 0.105 → 0.235, 최소 폰트 8 → 11.
    --   [증상] 무기 설명 글자가 너무 작아 읽기 힘들었다.
    --   [원인] TextScaled=true + 높이 0.105 조합. 라벨이 20px 남짓이라
    --     긴 설명일수록 MinTextSize(8)까지 자동 축소됐다.
    --     ⚠️ TextSize 를 올려도 소용없다 — TextScaled 가 켜져 있으면 무시된다.
    --       글을 키우려면 '라벨 높이'를 키우고 '최소 폰트'를 올려야 한다.
    --   ⚠️ MinTextSize 를 11 로 올렸으므로, 아주 긴 설명은 라벨을 넘쳐 잘릴 수 있다.
    --     WeaponData 의 desc 를 140자 이내로 유지할 것.
    tooltipDescLabel.Size = UDim2.fromScale(0.86, 0.235)
    tooltipDescLabel.BackgroundTransparency = 1
    tooltipDescLabel.Font = Enum.Font.Gotham
    tooltipDescLabel.TextScaled = true
    tooltipDescLabel.TextWrapped = true
    tooltipDescLabel.TextColor3 = Color3.fromRGB(196, 202, 214)
    tooltipDescLabel.TextXAlignment = Enum.TextXAlignment.Center
    tooltipDescLabel.TextYAlignment = Enum.TextYAlignment.Top
    tooltipDescLabel.Text = ""
    tooltipDescLabel.ZIndex = 5
    tooltipDescLabel.Parent = tooltipMain
    local tc = Instance.new("UITextSizeConstraint", tooltipDescLabel)
    tc.MaxTextSize = 15 ; tc.MinTextSize = 11

    -- 설명이 들어갈 자리를 만들기 위해 아래 요소들을 한 번만 내린다.
    --   ⚠️ 템플릿 원본 좌표를 코드로 밀어내는 방식이라, 나중에 UI 편집기에서
    --      Tooltip 을 손보면 이 오프셋과 어긋날 수 있다.
    --   ⚠️ [2026-08-29] SHIFT 0.10 → 0.19. 설명 라벨을 0.105 → 0.235 로 키웠으므로
    --      밀어내는 양도 그만큼 늘려야 Equip 버튼과 겹치지 않는다.
    --      ⚠️ _DescShifted 마커 때문에 한 번만 적용된다. 이미 밀린 상태에서 이 값을
    --        바꾸면 F5 를 새로 해야 반영된다(StarterGui 는 매번 복제되므로 정상 동작).
    local SHIFT = 0.19
    for _, nm in ipairs({ "Level", "Exp", "Equip", "Skin" }) do
        local o = tooltipMain:FindFirstChild(nm)
        if o and o:IsA("GuiObject") and not o:GetAttribute("_DescShifted") then
            o.Position = UDim2.new(o.Position.X.Scale, o.Position.X.Offset,
                                   o.Position.Y.Scale + SHIFT, o.Position.Y.Offset)
            o:SetAttribute("_DescShifted", true)
        end
    end

    -- 📝 툴팁 자체를 키운다. 위에서 요소를 0.19 만큼 밀었으므로 원래 높이로는 넘친다.
    --   ⚠️ 비율(Scale)만 늘린다. Offset 을 쓰면 해상도마다 다르게 보인다.
    if not tooltip:GetAttribute("_DescResized") then
        tooltip.Size = UDim2.new(tooltip.Size.X.Scale * 1.30, 0,
                                 tooltip.Size.Y.Scale * 1.34, 0)
        tooltip:SetAttribute("_DescResized", true)
    end
end

local function showTooltip(itemData, isLocked, fromTemplate)
    currentTooltipItem = itemData
    if tooltipDescLabel then
        -- ⚠️ itemData.name 은 displayName(표시용, 예 "Revival Flag")이라
        --    상점 키("RevivalFlag")와 안 맞는다(실측 2026-08-21: 후크·깃발 설명 누락).
        --    id 가 원본 name 을 담고 있으므로(530행: id=item.name) 그걸 먼저 쓴다.
        local d = itemDescs and itemData
            and (itemDescs[itemData.id] or itemDescs[itemData.name])
        tooltipDescLabel.Text = d or ""
    end
    if tooltipNameLabel then
        local prefix = (itemData.icon and itemData.icon ~= "") and (itemData.icon.."  ") or ""
        tooltipNameLabel.Text = prefix .. (itemData.name or "")
    end
    if tooltipRarityLabel then
        tooltipRarityLabel.Text = itemData.rarity or ""
        local rColor = {
            Normal=Color3.fromHex("#9d9d9d"), Rare=Color3.fromHex("#4cd964"),
            Epic=Color3.fromHex("#b44fff"),   Legendary=Color3.fromHex("#ffd700"),
        }
        tooltipRarityLabel.TextColor3 = rColor[itemData.rarity] or Color3.fromHex("#9d9d9d")
    end
    -- 잠겼지만 살 수 있는 것 → Equip 버튼을 "🛒 Buy"로 재활용해 상점 점프.
    -- (기존엔 러너 웨폰 한정이었으나 isPurchasable로 일반화)
    local weaponBuy = isLocked and isPurchasable(itemData)
    if tooltipEquip then tooltipEquip.Visible = (not isLocked) or weaponBuy end
    if weaponBuy and equipTextLabel then equipTextLabel.Text = "🛒 Buy" end
    -- Skin 버튼: 태거 아이템 전체 + 스킨 지원하는 특정 러너 무기(클래식 소드)에 표시.
    local SKIN_SUPPORTED = { ClassicSword = true, KatanaSword2 = true, HammerLow = true, HammerHigh = true, SakuraBlade = true, Gauntlet = true, PushTool = true, ["Speed Potion"] = true, ["RevivalFlag"] = true, ["Wood Shield"] = true, DiamondBladeSword = true }  -- 스킨 있는 무기 목록
    if tooltipSkin then
        local hasSkin = (activeTab.id == "Tagger" and taggerFilter == "item") or (SKIN_SUPPORTED[itemData.id] == true)
        tooltipSkin.Visible = hasSkin and not isLocked
    end
    refreshTooltipButtons()
    if fromTemplate then
        local mAbs, mSz = mainFrame.AbsolutePosition, mainFrame.AbsoluteSize
        local tAbs, tSz = fromTemplate.AbsolutePosition, fromTemplate.AbsoluteSize
        local tipW = tooltip.AbsoluteSize.X / mSz.X
        local tipH = tooltip.AbsoluteSize.Y / mSz.Y
        local cx = (tAbs.X - mAbs.X + tSz.X*0.5) / mSz.X
        local cy = (tAbs.Y - mAbs.Y + tSz.Y*0.5) / mSz.Y
        local px = cx + tSz.X/mSz.X*0.5 - tipW*0.55
        if px + tipW > 1 then px = cx - tSz.X/mSz.X*0.5 - tipW*0.45 end
        tooltip.Position    = UDim2.new(math.clamp(px,0,1-tipW),0, math.clamp(cy,0.02,1-tipH-0.02),0)
        tooltip.AnchorPoint = Vector2.new(0,0)
    end
    tooltip.Visible = true
end

-- ── 체크마크 ─────────────────────────────────────────────────
local function ensureCheckMark(template)
    if template:FindFirstChild("_CheckMark") then return end
    local check
    if checkmarkSource then
        check = checkmarkSource:Clone()
    else
        check = Instance.new("TextLabel")
        check.BackgroundColor3       = Color3.fromRGB(30,170,60)
        check.BackgroundTransparency = 0
        check.Text                   = "✔"
        check.TextColor3             = Color3.fromRGB(255,255,255)
        check.TextScaled             = true
        check.Font                   = Enum.Font.GothamBold
        Instance.new("UICorner", check).CornerRadius = UDim.new(0.3,0)
    end
    check.Name="\_CheckMark"; check.Size=UDim2.new(0.35,0,0.35,0)
    check.AnchorPoint=Vector2.new(1,1); check.Position=UDim2.new(1,0,1,0)
    check.ZIndex=4; check.Visible=false; check.Parent=template
end

local function refreshCheckMarks()
    for template, itemData in pairs(templateMap) do
        local check = template:FindFirstChild("_CheckMark")
        if check then check.Visible = isEquipped(itemData.id) end
    end
end

-- ── 슬롯 채우기 ──────────────────────────────────────────────
local function populateSlots(items)
    local templates = {}
    for _, c in ipairs(container:GetChildren()) do
        if c:IsA("Frame") and c.Name == "Template" then
            table.insert(templates, c)
        end
    end
    -- 풀 부족 시 템플릿 복제로 확장 (아이템 수 > 미리 만든 슬롯 수일 때, 예: 크라운 20종 > 15슬롯).
    -- 복제본은 동적 자식(이전 populate 잔재)을 제거해 깨끗한 슬롯으로 시작.
    if #templates > 0 and #items > #templates then
        local DYN = {"_ClickBtn","_CheckMark","_EmojiIcon","_CountBadge","_IconImg","_ItemVP","_ItemBackdrop","_LockOverlay","_TrailRibbon","_TrailRibbonOutline","_DashIcon"}
        local src = templates[1]
        for _ = 1, (#items - #templates) do
            local nc = src:Clone()
            nc.Name = "Template"
            for _, n in ipairs(DYN) do
                local old = nc:FindFirstChild(n, true)
                while old do old:Destroy(); old = nc:FindFirstChild(n, true) end
            end
            nc.Parent = container
            table.insert(templates, nc)
        end
    end
    templateMap = {}

    for i, template in ipairs(templates) do
        local itemData = items[i]
        local mainF    = template:FindFirstChild("Main")

        for _, n in ipairs({"_ClickBtn","_CheckMark","_EmojiIcon","_CountBadge","_IconImg","_ItemVP","_TrailRibbon","_TrailRibbonOutline","_DashIcon"}) do
            local old = template:FindFirstChild(n, true); if old then old:Destroy() end
        end
        ensureCheckMark(template)

        if not itemData then
            template.Visible = false
        else
            template.Visible = true
            templateMap[template] = itemData

            -- 이름/등급 레이블 (Emote는 등급 표시 안 함)
            if mainF then
                local tIdx = 0
                for _, c in ipairs(mainF:GetChildren()) do
                    if c:IsA("TextLabel") then
                        tIdx += 1
                        if tIdx == 1 then
                            -- 등급 + 기능 배지 (Emote 는 등급 표시 안 함)
                            -- ⚠️ 카드에 빈 자리가 없어서 별도 라벨 대신 등급 라벨에 합쳤다.
                            --    길어서 글자가 뭉개지면 구분자를 없애거나 등급을 색으로만 남길 것.
                            local rTxt = itemData.rarity or ""
                            local cTxt = CAT_LABEL[itemData.category or ""]
                            -- ⚠️ 색을 먼저 기본값으로 되돌린다. 카드 재사용 때문에
                            --    이전 항목의 FREE 초록색이 남는다.
                            c.TextColor3 = RARITY_TEXT_COLOR
                            if activeTab.id == "Emote" then
                                c.Text = ""
                            elseif itemData.freeToday then
                                -- 🆓 오늘 무료 개방 중. 남은 시간까지 보여줘 "지금만"이라는 걸 알린다.
                                -- ⚠️ 보유자에게도 표시한다. "오늘 뭐가 무료인가"는 개인 소유와 무관한
                                --    게임 전체의 상태이고, 오늘 다른 태거가 뭘 들고 나올지를 알려준다.
                                --    (처음엔 보유자에게 숨겼는데, 대부분을 보유한 계정에서는
                                --     로테이션이 도는지 확인할 방법 자체가 사라졌다)
                                -- ⚠️ 다만 톤은 구분한다. 미보유자에게는 '기회', 보유자에게는 '정보'다.
                                c.Text = "FREE " .. FreeRotation.formatRemaining()
                                c.TextColor3 = itemData.ownedReal
                                    and Color3.fromRGB(120, 175, 130)   -- 보유 중: 차분한 초록
                                    or  Color3.fromRGB(120, 235, 140)   -- 미보유: 밝은 초록(눈에 띄게)
                            elseif cTxt and rTxt ~= "" then
                                c.Text = rTxt .. " · " .. cTxt
                            else
                                c.Text = rTxt
                            end
                        elseif tIdx == 2 then
                            c.Text = itemData.name or ""
                        end
                    end
                end
            end

            local isLocked = not itemData.owned

            -- 자물쇠 오버레이
            local lockOverlay = template:FindFirstChild("_LockOverlay")
            if not lockOverlay then
                lockOverlay = Instance.new("Frame")
                lockOverlay.Name="\_LockOverlay"; lockOverlay.Size=UDim2.new(1,0,1,0)
                lockOverlay.BackgroundColor3=Color3.fromRGB(0,0,0)
                lockOverlay.BackgroundTransparency=0.5; lockOverlay.ZIndex=5
                Instance.new("UICorner",lockOverlay).CornerRadius=UDim.new(0.1,0)
                local li=Instance.new("TextLabel",lockOverlay)
                li.Size=UDim2.new(1,0,0.6,0); li.AnchorPoint=Vector2.new(0.5,0.5)
                li.Position=UDim2.new(0.5,0,0.5,0); li.BackgroundTransparency=1
                li.Text="🔒"; li.TextScaled=true; li.ZIndex=6
                lockOverlay.Parent=template
            end
            lockOverlay.Visible = isLocked

            local lockedFrame = template:FindFirstChild("Locked")
            if lockedFrame then lockedFrame.Visible = isLocked end

            -- 아이콘 / 스트로크
            local strokeFrame = template:FindFirstChild("Stroke")
            if strokeFrame then
                local uistroke = strokeFrame:FindFirstChildWhichIsA("UIStroke")
                if uistroke then
                    local grad = uistroke:FindFirstChildWhichIsA("UIGradient")
                    if grad then
                        grad.Color = isLocked and LOCKED_GRADIENT
                            or (rarityGradient[itemData.rarity] or rarityGradient.Normal)
                    end
                end
                local iconLabel = strokeFrame:FindFirstChildWhichIsA("ImageLabel")
                if iconLabel then iconLabel.Visible = false end
                local glow = mainF and mainF:FindFirstChild("Glow")
                if glow then glow.ImageTransparency = 1 end

                local oldImg = mainF and mainF:FindFirstChild("_IconImg")
                if oldImg then oldImg:Destroy() end
                local oldVP = mainF and mainF:FindFirstChild("_ItemVP")
                if oldVP then oldVP:Destroy() end
                local oldBD = mainF and mainF:FindFirstChild("_ItemBackdrop")
                if oldBD then oldBD:Destroy() end
                local oldRibbon = mainF and mainF:FindFirstChild("_TrailRibbon")
                if oldRibbon then oldRibbon:Destroy() end
                -- ⚠️ [2026-09-02] 아웃라인은 본체와 '한 짝'이다. 여기서 같이 안 지우면
                --   탭을 바꿔도 흰 리본이 슬롯에 남아 다음 아이템과 겹친다(실측).
                local oldRibbonOL = mainF and mainF:FindFirstChild("_TrailRibbonOutline")
                if oldRibbonOL then oldRibbonOL:Destroy() end
                local oldDash = mainF and mainF:FindFirstChild("_DashIcon")
                if oldDash then oldDash:Destroy() end

                -- 슬롯 재사용 시 이전 imageId 아이템의 검정 배경이 남지 않게 기본색(11,11,11) 복원
                if mainF then mainF.BackgroundColor3 = Color3.fromRGB(11, 11, 11) end

                -- 트레일은 King 탭에도 노출되므로(역할 공용) 두 필터 모두에서 리본을 그린다.
                -- 조건을 runnerFilter 로만 두면 King 탭에서 빈 카드가 나온다.
                local isTrailView = (runnerFilter == "trail") or (taggerFilter == "trail")
                if isTrailView and TRAIL_RIBBON[itemData.id] and mainF then
                    makeTrailRibbon(TRAIL_RIBBON[itemData.id], mainF)
                elseif runnerFilter == "dash" and DASH_ICON[itemData.id] and mainF then
                    makeDashIcon(DASH_ICON[itemData.id], mainF)
                elseif mainF and itemData.imageId and itemData.imageId ~= "" then
                    -- 이미지 자체가 불투명 검정 배경을 포함 → 슬롯 배경을 그 검정에 맞춰 경계(사각형) 제거
                    mainF.BackgroundColor3 = (itemData.id == "Demonspear") and Color3.fromRGB(3, 3, 3) or Color3.fromRGB(0, 0, 0)
                    local img = Instance.new("ImageLabel")
                    img.Name               = "_IconImg"
                    img:SetAttribute("effectId", itemData.id)
                    img.Image              = itemData.imageId
                    img.ImageColor3        = Color3.fromRGB(255, 255, 255)
                    img.ImageTransparency  = 0
                    img.BackgroundTransparency = 1
                    img.ScaleType          = Enum.ScaleType.Fit
                    -- 배지별 크기/위치 미세조정: imgScale/imgOffX/imgOffY (EffectSystem 데이터). 없으면 기본값.
                    local _sc = itemData.imgScale or (itemData.id == "Frost Dragon" and 1.2) or 0.72
                    local _baseY = (activeTab.id == "Emote" or itemData.id == "Wood Log") and 0.42 or 0.5
                    img.Size               = UDim2.new(_sc, 0, _sc, 0)
                    img.AnchorPoint        = Vector2.new(0.5, 0.5)
                    img.Position           = UDim2.new(0.5 + (itemData.imgOffX or 0), 0, _baseY + (itemData.imgOffY or 0), 0)
                    img.Rotation           = itemData.rotation or 0
                    img.ZIndex             = 0
                    img.Parent             = mainF
                elseif mainF and itemData.icon and itemData.icon ~= "" and not (activeTab.id == "Tagger" and taggerFilter == "crown") then
                    local el = Instance.new("TextLabel")
                    el.Name = "_EmojiIcon"; el.Size = UDim2.new(0.6, 0, 0.5, 0)
                    el.AnchorPoint = Vector2.new(0.5, 0.5)
                    el.Position = UDim2.new(0.5, 0, 0.42, 0)
                    el.BackgroundTransparency = 1; el.Text = itemData.icon
                    el.TextScaled = true; el.ZIndex = 0; el.Parent = mainF
                else
                    -- ViewportFrame 3D 미리보기 (RunnerInvenClient와 동일)
                    -- 크라운 스킨은 CrownPreviews[skinKey], 그 외는 RunnerItemPreviews[id]
                    local previewModel
                    if activeTab.id == "Tagger" and taggerFilter == "crown" and itemData.skinKey then
                        local cp = game:GetService("ReplicatedStorage"):FindFirstChild("CrownPreviews")
                        previewModel = cp and cp:FindFirstChild(itemData.skinKey)
                    else
                        local RS_ = game:GetService("ReplicatedStorage")
                        -- 태거 탭 아이템은 TaggerItemPreviews 우선, 없으면 RunnerItemPreviews 폴백
                        local previewModel_
                        if activeTab.id == "Tagger" then
                            local tp = RS_:FindFirstChild("TaggerItemPreviews")
                            previewModel_ = tp and tp:FindFirstChild(itemData.id)
                        end
                        if not previewModel_ then
                            local previewFolder = RS_:FindFirstChild("RunnerItemPreviews")
                            previewModel_ = previewFolder and previewFolder:FindFirstChild(itemData.id)
                        end
                        previewModel = previewModel_
                    end
                    if previewModel and mainF then
                        -- 모델별 카메라/조명/백드롭 오버라이드 (속성으로 지정)
                        local customDir     = previewModel:GetAttribute("CameraDirection")
                        local customAmb     = previewModel:GetAttribute("Ambient")
                        local customDistMul = previewModel:GetAttribute("DistMul")
                        local customBackdrop = previewModel:GetAttribute("Backdrop")

                        -- 백드롭 (어두운 아이템 대비용 배경)
                        if customBackdrop then
                            local bd = Instance.new("Frame")
                            bd.Name                   = "_ItemBackdrop"
                            local bdSz                = previewModel:GetAttribute("BackdropSize")
                            bd.Size                   = bdSz and UDim2.new(bdSz.X, 0, bdSz.Y, 0) or UDim2.new(0.68, 0, 0.58, 0)
                            bd.AnchorPoint            = Vector2.new(0.5, 0.5)
                            bd.Position               = UDim2.new(0.5, 0, 0.5, 0)
                            bd.BackgroundColor3       = customBackdrop
                            bd.BackgroundTransparency = 0.15
                            bd.BorderSizePixel        = 0
                            bd.ZIndex                 = 0
                            Instance.new("UICorner", bd).CornerRadius = UDim.new(0.18, 0)
                            bd.Parent = mainF
                        end

                        local vp = Instance.new("ViewportFrame")
                        vp.Name                   = "_ItemVP"
                        vp:SetAttribute("PreviewId", itemData.id)
                        vp.Size                   = UDim2.new(0.88, 0, 0.88, 0)
                        vp.AnchorPoint            = Vector2.new(0.5, 0.5)
                        vp.Position               = UDim2.new(0.5, 0, (itemData.id == "Spear" or itemData.id == "bear_trap") and 0.42 or (itemData.id == "Decoy Wand" and 0.63 or 0.5), 0)
                        vp.BackgroundTransparency = 1
                        vp.LightDirection         = Vector3.new(-1, -2, -1)
                        vp.LightColor             = Color3.new(1, 1, 1)
                        vp.Ambient                = customAmb or Color3.fromRGB(120, 120, 160)
                        vp.ZIndex                 = 0
                        vp.Parent                 = mainF
                        local clone = previewModel:Clone()
                        clone.Parent = vp
                        if itemData.id == "Demonspear" then
                            local hl = Instance.new("Highlight")
                            hl.Adornee = clone
                            hl.FillTransparency = 1
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.OutlineTransparency = 0
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Parent = clone
                        end
                        local cam = Instance.new("Camera")
                        cam.FieldOfView = 35
                        cam.Parent      = vp
                        vp.CurrentCamera = cam
                        local cf, size
                        if clone:IsA("Model") then
                            cf, size = clone:GetBoundingBox()
                        elseif clone:IsA("BasePart") then
                            cf, size = clone.CFrame, clone.Size
                        else
                            cf, size = CFrame.new(), Vector3.new(4, 4, 4)
                        end
                        local maxDim = math.max(size.X, size.Y, size.Z)
                        local dist   = maxDim * (customDistMul or 2.8)
                        local dirV   = customDir or Vector3.new(0.3, 0.25, 1)
                        local camPos = cf.Position + dirV * dist
                        local lookOff = clone:GetAttribute("CameraLookOffset")
                        if lookOff then
                            -- 화면 기준 pan: 타겟을 카메라 right/up으로 밀면 모델이 반대쪽으로 치우침 (양수 X = 모델이 좌측)
                            local baseCF = CFrame.new(camPos, cf.Position)
                            cam.CFrame = CFrame.new(camPos, cf.Position + baseCF.RightVector * lookOff.X + baseCF.UpVector * lookOff.Y)
                        else
                            cam.CFrame = CFrame.new(camPos, cf.Position)
                        end
                        local _ov = ITEM_CAM[itemData.id]
                        if _ov then
                            -- PreviewTuner-baked camera (world-space target model), e.g. tnt
                            local _d   = maxDim * _ov.dist
                            local _tgt = cf.Position + _ov.target * maxDim
                            cam.CFrame = CFrame.new(_tgt + _ov.dir * _d, _tgt)
                        end
                    end
                end
            end

            -- 소모품 수량 배지 (Runner)
            if itemData.count and itemData.count > 0 then
                local badge=Instance.new("TextLabel")
                badge.Name="_CountBadge"; badge.Size=UDim2.new(0.38,0,0.28,0)
                badge.AnchorPoint=Vector2.new(1,0); badge.Position=UDim2.new(1,0,0,0)
                badge.BackgroundColor3=Color3.fromRGB(20,20,20)
                badge.BackgroundTransparency=0.3; badge.Text="x"..itemData.count
                badge.TextScaled=true; badge.Font=Enum.Font.GothamBold
                badge.TextColor3=Color3.fromRGB(255,215,0); badge.ZIndex=4
                Instance.new("UICorner",badge).CornerRadius=UDim.new(0.3,0)
                badge.Parent=template
            end

            local capturedItem=itemData; local capturedLocked=isLocked
            local clickBtn=Instance.new("TextButton")
            clickBtn.Name="_ClickBtn"; clickBtn.Size=UDim2.new(1,0,1,0)
            clickBtn.BackgroundTransparency=1; clickBtn.Text=""
            clickBtn.ZIndex=2; clickBtn.Parent=template
            clickBtn.MouseButton1Click:Connect(function()
                if _G.badgeTunerActive then return end
                if _G.previewTunerActive then return end
                -- 잠긴 것도 "살 수 있으면" 툴팁을 띄워 🛒 Buy로 유도.
                -- 못 사는 것(게임패스/그룹보상)은 무반응 유지.
                if capturedLocked and not isPurchasable(capturedItem) then return end
                showTooltip(capturedItem, capturedLocked, template)
            end)
        end
    end
    -- ── 스크롤 영역(CanvasSize) 강제 보정 ──────────────────────────
    -- AutomaticCanvasSize가 AspectRatio 셀과 안 맞아 꼬이므로 직접 계산.
    -- 한 줄에 들어가는 칸 수 → 줄 수 → 전체 높이.
    do
        local grid = container:FindFirstChildOfClass("UIGridLayout")
        if grid then
            local visibleCount = 0
            for _, c in ipairs(container:GetChildren()) do
                if c:IsA("Frame") and c.Name == "Template" and c.Visible then
                    visibleCount += 1
                end
            end
            local cellW = grid.AbsoluteCellSize.X
            local cellH = grid.AbsoluteCellSize.Y
            local padX  = grid.CellPadding.X.Offset
            local padY  = grid.CellPadding.Y.Offset
            local availW = container.AbsoluteSize.X
            local perRow = math.max(1, math.floor((availW + padX) / math.max(1, cellW + padX)))
            local rows = math.ceil(math.max(1, visibleCount) / perRow)
            local totalH = rows * cellH + math.max(0, rows - 1) * padY + padY * 2
            container.AutomaticCanvasSize = Enum.AutomaticSize.None
            container.CanvasSize = UDim2.new(0, 0, 0, math.ceil(totalH))
        end
    end

    refreshCheckMarks()
    refreshBottomLabel()
end

-- ── All / Owned 토글 ─────────────────────────────────────────
local toggleFrame = mainFrame:FindFirstChild("_OwnedToggle")
local toggleFill  = toggleFrame and toggleFrame:FindFirstChild("_Fill")
local lblAll      = toggleFrame and toggleFrame:FindFirstChild("_LblAll")
local lblOwned    = toggleFrame and toggleFrame:FindFirstChild("_LblOwned")
local toggleBtn   = toggleFrame and toggleFrame:FindFirstChild("_ToggleBtn")
local ownedOnly   = false

local function applyToggleVisual()
    if not toggleFill then return end
    TweenService:Create(toggleFill,TweenInfo.new(0.15),
        {Position=ownedOnly and UDim2.new(0.5,0,0,0) or UDim2.new(0,0,0,0)}):Play()
    toggleFill.BackgroundColor3 = ownedOnly and Color3.fromRGB(50,160,255) or Color3.fromRGB(80,80,80)
    if lblAll   then lblAll.TextColor3   = ownedOnly and Color3.fromRGB(180,180,180) or Color3.fromRGB(255,255,255) end
    if lblOwned then lblOwned.TextColor3 = ownedOnly and Color3.fromRGB(255,255,255) or Color3.fromRGB(180,180,180) end
end
if toggleFrame then
    toggleFrame.Size=UDim2.new(0.11,0,0.09,0); toggleFrame.Position=UDim2.new(0.82,0,0.095,0)
    -- All/Owned 글자 크기 통일 (TextScaled 끄고 동일 고정 크기 → Owned 기준 균일)
    if lblAll   then lblAll.TextScaled=false;   lblAll.TextSize=18;   lblAll.Text="All"   end
    if lblOwned then lblOwned.TextScaled=false; lblOwned.TextSize=18; lblOwned.Text="Owned" end
end
if toggleBtn then
    toggleBtn.MouseButton1Click:Connect(function()
        ownedOnly = not ownedOnly; applyToggleVisual()
        tooltip.Visible=false; currentTooltipItem=nil
        local filtered={}
        for _, item in ipairs(cachedItems) do
            if not ownedOnly or item.owned then table.insert(filtered,item) end
        end
        populateSlots(filtered)
    end)
end

-- ── 데이터 로드 ───────────────────────────────────────────────
local function loadData()
    cachedItems = normalizeData(activeTab.id)
    equippedIds = {}
    for _, item in ipairs(cachedItems) do
        if item.equipped then table.insert(equippedIds,item.id) end
    end
    applyToggleVisual()
    local filtered={}
    for _, item in ipairs(cachedItems) do
        if not ownedOnly or item.owned then table.insert(filtered,item) end
    end
    populateSlots(filtered)
end

-- ── 프리셋 전환 시 인벤 갱신 (서버가 로드아웃/장착 변경 → 현재 탭 재읽기) ──
do
    local presetChangedE = ReplicatedStorage:WaitForChild("PresetChanged", 10)
    if presetChangedE then
        presetChangedE.OnClientEvent:Connect(function()
            if not activeTab then return end
            task.spawn(function()
                task.wait(0.1)
                pcall(loadData)
            end)
        end)
    end
end

-- ── Runner 하위 필터 칩 (Weapon / Dash / Trail) ───────────────
local FILTER_KEYS = {"item", "weapon", "dash", "trail"}
local FILTER_LABELS = {item="Item", weapon="Weapon", dash="Dash", trail="Trail"}
local FILTER_ACCENT = Color3.fromRGB(50, 160, 255)  -- 선택 강조색(러너 파랑)

-- 칩을 코드로 생성(없을 때만). execute_luau 인스턴스는 저장 안 하면 날아가므로,
-- 런타임에 스크립트가 직접 만들어 영속성 문제를 회피.
local function ensureFilterChip()
    local existing = mainFrame:FindFirstChild("_RunnerFilter")
    if existing then return existing end

    local chip = Instance.new("Frame")
    chip.Name = "_RunnerFilter"
    chip.Position = UDim2.new(0.45, 0, 0.095, 0)
    chip.Size = UDim2.new(0.34, 0, 0.09, 0)
    chip.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    chip.BackgroundTransparency = 0.2
    chip.BorderSizePixel = 0
    chip.Visible = false
    chip.ZIndex = 10
    chip.Parent = mainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = chip

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 100, 100)
    stroke.Thickness = 1.5
    stroke.Parent = chip

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = chip

    for i, key in ipairs(FILTER_KEYS) do
        local btn = Instance.new("TextButton")
        btn.Name = "_Btn_" .. key
        btn.Size = UDim2.new(1/4, 0, 1, 0)
        btn.BackgroundColor3 = FILTER_ACCENT
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel = 0
        btn.Text = FILTER_LABELS[key]
        btn.Font = Enum.Font.GothamBold
        btn.TextScaled = true
        btn.TextColor3 = Color3.fromRGB(170, 170, 170)
        btn.AutoButtonColor = false
        btn.LayoutOrder = i
        btn.ZIndex = 11
        btn.Parent = chip
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0.18,0); pad.PaddingBottom = UDim.new(0.18,0)
        pad.PaddingLeft = UDim.new(0,2); pad.PaddingRight = UDim.new(0,2)
        pad.Parent = btn
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 5)
        bc.Parent = btn
    end
    return chip
end
local filterFrame = ensureFilterChip()
local function applyFilterVisual()
    if not filterFrame then return end
    for _, key in ipairs(FILTER_KEYS) do
        local btn = filterFrame:FindFirstChild("_Btn_" .. key)
        if btn then
            local selected = (runnerFilter == key)
            btn.BackgroundTransparency = selected and 0 or 1
            btn.BackgroundColor3 = FILTER_ACCENT
            btn.TextColor3 = selected and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,170,170)
        end
    end
end
if filterFrame then
    for _, key in ipairs(FILTER_KEYS) do
        local btn = filterFrame:FindFirstChild("_Btn_" .. key)
        if btn then
            local capKey = key
            btn.MouseButton1Click:Connect(function()
                if runnerFilter == capKey then return end
                runnerFilter = capKey
                applyFilterVisual()
                tooltip.Visible=false; currentTooltipItem=nil
                loadData()
            end)
        end
    end
end
applyFilterVisual()  -- 초기 시각 상태(Weapon 강조)

-- ── Tagger 하위 필터 칩 (Item / Weapon / Crown) ───────────────
-- ⚠️ trail 은 Runner 탭에도 같은 목록이 있다(의도된 중복 노출).
--    트레일은 역할 공용 코스메틱인데 Runner 탭에만 두면 태거 위주 유저가 못 찾는다.
--    장착 상태는 플레이어 속성 TrailSkin 하나로 관리되므로 어느 탭에서 바꾸든 즉시 동기화된다.
local TAGGER_FILTER_KEYS = {"item", "weapon", "crown", "trail"}
local TAGGER_FILTER_LABELS = {item="Item", weapon="Weapon", crown="Crown", trail="Trail"}
local TAGGER_FILTER_ACCENT = Color3.fromRGB(225, 75, 65)  -- 선택 강조색(태거 빨강)

local function ensureTaggerFilterChip()
    local existing = mainFrame:FindFirstChild("_TaggerFilter")
    if existing then return existing end
    local chip = Instance.new("Frame")
    chip.Name = "_TaggerFilter"
    chip.Position = UDim2.new(0.42, 0, 0.095, 0)
    chip.Size = UDim2.new(0.36, 0, 0.09, 0)   -- 칩 4개(Item/Weapon/Crown/Trail) 수용
    chip.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    chip.BackgroundTransparency = 0.2
    chip.BorderSizePixel = 0
    chip.Visible = false
    chip.ZIndex = 10
    chip.Parent = mainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = chip
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 100, 100)
    stroke.Thickness = 1.5
    stroke.Parent = chip
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = chip
    for i, key in ipairs(TAGGER_FILTER_KEYS) do
        local btn = Instance.new("TextButton")
        btn.Name = "_Btn_" .. key
        btn.Size = UDim2.new(1 / #TAGGER_FILTER_KEYS, 0, 1, 0)  -- 칩 개수에 맞춰 균등 분할
        btn.BackgroundColor3 = TAGGER_FILTER_ACCENT
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel = 0
        btn.Text = TAGGER_FILTER_LABELS[key]
        btn.Font = Enum.Font.GothamBold
        btn.TextScaled = true
        btn.TextColor3 = Color3.fromRGB(170, 170, 170)
        btn.AutoButtonColor = false
        btn.LayoutOrder = i
        btn.ZIndex = 11
        btn.Parent = chip
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0.18,0); pad.PaddingBottom = UDim.new(0.18,0)
        pad.PaddingLeft = UDim.new(0,2); pad.PaddingRight = UDim.new(0,2)
        pad.Parent = btn
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 5)
        bc.Parent = btn
    end
    return chip
end
local taggerFilterFrame = ensureTaggerFilterChip()
function applyTaggerFilterVisual()
    if not taggerFilterFrame then return end
    for _, key in ipairs(TAGGER_FILTER_KEYS) do
        local btn = taggerFilterFrame:FindFirstChild("_Btn_" .. key)
        if btn then
            local selected = (taggerFilter == key)
            btn.BackgroundTransparency = selected and 0 or 1
            btn.BackgroundColor3 = TAGGER_FILTER_ACCENT
            btn.TextColor3 = selected and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,170,170)
        end
    end
end
if taggerFilterFrame then
    for _, key in ipairs(TAGGER_FILTER_KEYS) do
        local btn = taggerFilterFrame:FindFirstChild("_Btn_" .. key)
        if btn then
            local capKey = key
            btn.MouseButton1Click:Connect(function()
                if taggerFilter == capKey then return end
                taggerFilter = capKey
                applyTaggerFilterVisual()
                tooltip.Visible=false; currentTooltipItem=nil
                loadData()
            end)
        end
    end
end
applyTaggerFilterVisual()

if tooltipEquip then
    tooltipEquip.MouseButton1Click:Connect(function()
        if not currentTooltipItem then return end
        -- ⚔️👑💨 [2026-09-02] 장착 중인 필수 항목(무기·크라운·대시)은 눌러도 아무 일이 없다.
        --   서버로 보내도 기본값으로 되돌릴 뿐이라 값이 안 바뀌고, 그게 "먹통"으로 읽혔다.
        if isEssentialSlot() and currentTooltipItem.owned and isEquipped(currentTooltipItem.id) then
            return
        end
        if not currentTooltipItem.owned then
            -- 살 수 있는 잠긴 아이템 → 코인샵으로 점프(인벤 위에 겹침). 못 사는 건 경고만.
            if isPurchasable(currentTooltipItem) and _G.OpenShopToItem then
                local tabHint, subHint
                if activeTab.id == "Runner" then
                    tabHint = "runner"
                    subHint = (runnerFilter == "weapon") and "weapon" or "item"
                elseif activeTab.id == "Tagger" then
                    tabHint = "tagger"
                    subHint = "item"
                end
                if tabHint then
                    _G.OpenShopToItem(currentTooltipItem.name, subHint, tabHint)
                    return
                end
            end
            showWarning("You don't own this item!") return
        end
        local id  = currentTooltipItem.id
        local tab = activeTab

        -- [ROUND-LOCK] 라운드 중에는 서버가 장착 요청을 무시한다
        --   (LoadoutManager / EffectSystem / SkinManager / *ColorServer 모두 RoundPhase 가드).
        --   ⚠️ 클라 표시는 갱신되므로 안내가 없으면 "바뀐 줄 알았는데 안 바뀜"이 된다.
        --      "변경할 수 없다"가 아니라 "반영되지 않는다"가 사실에 맞는 표현이다.
        do
            local ph = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
            if ph == "stage1" or ph == "stage2" then
                showWarning("Changes won't apply during a round")
                return
            end
        end

        if tab.id == "Tagger" then
            if taggerFilter == "crown" then
                -- 왕관 스킨: 단일 장착, 해제 불가(항상 하나 착용) — 이미 장착된 건 무시
                if isEquipped(id) then return end
                equippedIds = {id}
                setEquippedEffect:FireServer("crownSkin", id)
            elseif taggerFilter == "trail" then
                -- 트레일: 역할 공용. Runner 탭과 같은 TrailSkin 을 조작하므로
                -- 어느 탭에서 바꾸든 즉시 양쪽에 반영된다.
                equippedIds = isEquipped(id) and {} or {id}
                setEquippedEffect:FireServer("trailSkin", equippedIds[1] or "none")
            elseif taggerFilter == "weapon" then
                -- 푸시툴은 2단계에 자동 지급 → 선택 불가(표시만)
                showWarning("Auto-equipped in Stage 2")
                return
            else
                if isEquipped(id) then
                    if #equippedIds <= 1 then showWarning("At least 1 item must be equipped!") return end
                    for i,eid in ipairs(equippedIds) do if eid==id then table.remove(equippedIds,i) break end end
                else
                    if #equippedIds >= tab.maxEquip then showWarning("Max "..tab.maxEquip.." items!") return end
                    table.insert(equippedIds,id)
                end
                setLoadout:FireServer(equippedIds)
            end
        elseif tab.id == "Runner" then
            if runnerFilter == "dash" then
                -- 대시 스킨: 단일 장착 (KillEffect와 동일 패턴)
                equippedIds = isEquipped(id) and {} or {id}
                setEquippedEffect:FireServer("dashSkin", equippedIds[1] or "none")
            elseif runnerFilter == "trail" then
                -- 트레일 스킨: 단일 장착
                equippedIds = isEquipped(id) and {} or {id}
                setEquippedEffect:FireServer("trailSkin", equippedIds[1] or "none")
            elseif runnerFilter == "weapon" then
                -- 2단계 무기: 단일 장착(최대 1개). 서버에 저장 → Stage2가 지급.
                equippedIds = isEquipped(id) and {} or {id}
                setEquippedEffect:FireServer("weapon", equippedIds[1] or "none")
            else
                if isEquipped(id) then
                    for i,eid in ipairs(equippedIds) do if eid==id then table.remove(equippedIds,i) break end end
                else
                    if #equippedIds >= tab.maxEquip then showWarning("Max "..tab.maxEquip.." items!") return end
                    table.insert(equippedIds,id)
                end
                setRunnerLoadout:FireServer(equippedIds)
            end
        elseif tab.id == "KillEffect" then
            equippedIds = isEquipped(id) and {} or {id}
            setEquippedEffect:FireServer("killEffect", equippedIds[1] or "none")
        elseif tab.id == "Emote" then
            if isEquipped(id) then
                for i,eid in ipairs(equippedIds) do if eid==id then table.remove(equippedIds,i) break end end
            else
                if #equippedIds >= tab.maxEquip then showWarning("Max "..tab.maxEquip.." emotes!") return end
                table.insert(equippedIds,id)
            end
            setEquippedEffect:FireServer("emote",id)
        end

        for _, item in ipairs(cachedItems) do item.equipped = isEquipped(item.id) end
        refreshCheckMarks(); refreshTooltipButtons(); refreshBottomLabel()
        if _G.LoadoutPreviewRefresh then _G.LoadoutPreviewRefresh() end
    end)
end
if tooltipClose2 then
    tooltipClose2.MouseButton1Click:Connect(function()
        tooltip.Visible=false; currentTooltipItem=nil
    end)
end

-- ── 탭 클릭 ──────────────────────────────────────────────────
for _, def in ipairs(TABS) do
    local tab = canvas:FindFirstChild("_Tab_"..def.id)
    local btn = tab and tab:FindFirstChild("_ClickBtn")
    if btn then
        local capDef = def
        btn.MouseButton1Click:Connect(function()
            if activeTab.id == capDef.id then return end
            activeTab = capDef
            tooltip.Visible=false; currentTooltipItem=nil; ownedOnly=false
            updateTheme()
            loadData()
            applyFilterVisual()  -- Runner 필터 칩 시각 동기화 (weapon 리셋 반영)
        end)
    end
end

-- ── 열기 / 닫기 ──────────────────────────────────────────────
local function openInven(startTabId)
    if startTabId then
        for _, def in ipairs(TABS) do
            if def.id == startTabId then activeTab=def; break end
        end
    end
    -- 새로 열 때는 하위 필터를 기본(item)으로 초기화. (열려 있는 동안 탭 사이 전환은 각자 유지됨)
    runnerFilter = "item"
    taggerFilter = "item"
    tooltip.Visible=false; currentTooltipItem=nil; ownedOnly=false
    updateTheme()
    loadData()
    applyFilterVisual()
    if applyTaggerFilterVisual then applyTaggerFilterVisual() end
    canvas.Visible=true
    -- [STARTER-KIT] 인벤을 열었음을 서버에 알린다. 서버가 최초 1회만 맛보기를 지급한다.
    --   ⚠️ 매번 보내도 안전하다 — 지급 여부는 서버가 StarterKitGiven 으로 판정한다.
    --      여기서 자체 플래그로 막으면 지급 실패 시 재시도 기회가 사라진다.
    task.spawn(function()
        local ev = game:GetService("ReplicatedStorage"):FindFirstChild("StarterKitOpened")
        if ev then pcall(function() ev:FireServer() end) end
    end)
end

local function closeInven()
    canvas.Visible=false; tooltip.Visible=false; currentTooltipItem=nil
    if warningThread then task.cancel(warningThread) end
    warningFrame.Visible=false
end

_G.openUnifiedInven  = openInven
_G.closeUnifiedInven = closeInven
closeBtn.MouseButton1Click:Connect(closeInven)

print("✅ UnifiedInvenClient 준비!")

-- ── Skin UI (동적 스크롤 그리드) ────────────────────────────
local skinUI       = uniGui:FindFirstChild("skin ui")
local skinClose    = skinUI and skinUI:FindFirstChild("skin close")
local skinScroll   = skinUI and skinUI:FindFirstChild("_SkinScroll", true)  -- Holder 안에 있어도 재귀로 탐색
local skinGrid     = skinScroll and skinScroll:FindFirstChild("_SkinGrid")
local slotTemplate = skinUI and skinUI:FindFirstChild("_SkinSlotTemplate")
local _skinCanvasConn = nil  -- 스킨 스크롤 CanvasSize 자동 동기화 연결

local getPlayerSkin = ReplicatedStorage:WaitForChild("GetPlayerSkin")
local setPlayerSkin = ReplicatedStorage:WaitForChild("SetPlayerSkin")
local itemColorRemote = ReplicatedStorage:WaitForChild("ItemColorRemote")  -- 색 커스텀 적용/해제(원본 복귀)
local noobPalette = require(ReplicatedStorage:WaitForChild("NoobColorPalette"))  -- 색 속성 zone 조회용
local currentSkinItem = nil

-- ── 스킨 썸네일 카메라 튜닝값 (스킨별) ────────────────────────────
-- PreviewTunerClient(P키)로 카드 뷰포트를 클릭→조정→Enter, 콘솔의 [TUNE-OUT] 값을 여기에 입력.
-- 형식: [스킨명] = { dist = 거리배율, dir = Vector3.new(x,y,z), target = Vector3.new(x,y,z) }
-- 등록 안 된 스킨은 기본값(dist 1.8, dir (0.3,0.2,1))으로 잡힘.
local SKIN_CAM = {
	IceCrystalBlade = { dist = 1.90, dir = Vector3.new(0.500, 0.100, 1.000), target = Vector3.new(0.000, 0.000, 0.000) },  -- Ice Crystal Blade (Diamond Blade skin)
	MechGauntlet = { dist = 1.10, dir = Vector3.new(-1.400, 0.200, -0.400), target = Vector3.new(0.000, 0.000, 0.000) },  -- Mech Gauntlet (3/4: 주먹+부스터)
	IceCrusher = { dist = 0.70, dir = Vector3.new(2.650, -0.100, 1.000), target = Vector3.new(-0.300, 0.000, -0.050) },  -- Ice Crusher (HammerHigh skin)
	FlameHammer = { dist = 1.80, dir = Vector3.new(0.500, 0.100, 1.000), target = Vector3.new(0.000, 0.000, 0.000) },  -- Flame Hammer (HammerHigh skin)
	-- 예: RainbowStone = { dist = 1.60, dir = Vector3.new(0.400, 0.350, 0.900), target = Vector3.new(0.000, 0.000, 0.000) },
	GlitchNoob = { dist = 1.40, dir = Vector3.new( 1.100, 0.200,  1.000), target = Vector3.new(0.000, 0.000, 0.000) },
	SuitNoob   = { dist = 1.10, dir = Vector3.new( 1.700, 0.200,  1.000), target = Vector3.new(0.000, 0.000, 0.000) },
	KingNoob   = { dist = 0.50, dir = Vector3.new(-2.300, 0.200, -2.400), target = Vector3.new(0.000, 0.000, 0.000) },
	SummerNoob = { dist = 0.40, dir = Vector3.new( 0.300, 0.200, -4.700), target = Vector3.new(0.000, 0.000, 0.000) },
	Demonspear = { dist = 2.80, dir = Vector3.new( 0.300, 0.250,  1.000), target = Vector3.new(0.000, 0.000, 0.000) },  -- 새 메시(A) 튜닝값 (Original+Rainbow+9색 공유)
	RainbowSpear = { dist = 2.60, dir = Vector3.new( 0.000, 0.300, 0.100), target = Vector3.new(0.000, 0.000, 0.000) },
	Spear        = { dist = 1.00, dir = Vector3.new(-1.000, 1.250, 0.500), target = Vector3.new(0.000, 0.000, 0.000) },  -- Original(무기 원본)
	PushTool     = { dist = 0.80, dir = Vector3.new( 1.700, 0.200, 1.000), target = Vector3.new(-0.150, 0.000, 0.000) },  -- Original
	ClassicSword = { dist = 0.50, dir = Vector3.new( 4.100, 0.250, 1.600), target = Vector3.new( 0.000, 0.100, 0.000) },  -- Original
	HammerHigh   = { dist = 0.80, dir = Vector3.new( 0.200, 0.000, 0.800), target = Vector3.new( 0.250, -0.350, 0.000) },  -- Original
	HammerLow    = { dist = 0.90, dir = Vector3.new( 0.300, 0.700, 1.000), target = Vector3.new( 0.000, 0.000, 0.000) },  -- Original+Lightning+Rainbow 공유 (PreviewTuner 값)
	SakuraBlade     = { dist = 0.80, dir = Vector3.new( 0.500, 0.200, 1.000), target = Vector3.new(-0.100, -0.050, 0.000) },
	KatanaSword2    = { dist = 0.60, dir = Vector3.new( 1.000, 0.200, 1.000), target = Vector3.new(-0.250, -0.100, 0.000) },
	-- Crimson Fang(Legendary 모델교체): 칼날이 -Z로 뻗음(원본과 축 다름) → 별도 튜닝.
	-- 값이 안 맞으면 PreviewTunerClient(P키)로 조정 후 [TUNE-OUT] 값을 여기 기입.
	LegendKatana    = { dist = 0.70, dir = Vector3.new( 1.000, -0.100, 0.000), target = Vector3.new(-0.100, 0.000, 0.000) },
	["Wood Shield"] = { dist = 2.80, dir = Vector3.new( 0.000, 0.250, 1.000), target = Vector3.new(-0.050, 0.000, 0.000) },
	LegendShield    = { dist = 1.60, dir = Vector3.new( 0.000, 0.200, 1.000), target = Vector3.new( 0.000, 0.000, 0.000) },
	RiotShield      = { dist = 1.30, dir = Vector3.new(0.438, 0.300, -1.153), target = Vector3.new( 0.000, 0.000, 0.000) },
	SFShield        = { dist = 1.70, dir = Vector3.new(0.259, 0.200, -0.966), target = Vector3.new( 0.000, 0.000, 0.000) },
	CrusaderBarrel  = { dist = 1.40, dir = Vector3.new( 0.800, 0.900, 1.000), target = Vector3.new(-0.050, -0.100, -0.050) },
	OilDrum         = { dist = 1.50, dir = Vector3.new( 0.700, 0.100, 1.000), target = Vector3.new( 0.000, -0.100, 0.000) },
	["Wooden Barrel"] = { dist = 1.40, dir = Vector3.new( 0.600, 0.200, 1.000), target = Vector3.new( 0.000, -0.050, 0.000) },
	WatermelonFist  = { dist = 1.30, dir = Vector3.new( 0.500, -1.800, 0.100), target = Vector3.new( 0.000, 0.050, -0.100) },
	GlitchFist      = { dist = 1.30, dir = Vector3.new( 0.500, -1.800, 0.100), target = Vector3.new( 0.000, 0.050, -0.100) },  -- match WatermelonFist
	CursorFist      = { dist = 1.30, dir = Vector3.new( 0.500, -1.800, 0.100), target = Vector3.new( 0.000, 0.050, -0.100) },  -- match WatermelonFist
}

-- 슬롯 하나를 skinData로 채움 (아이콘/3D프리뷰/이름/잠금/Equip버튼)
local function updateSkinSlot(skinBar, equipBtn, skinData)
    if not skinBar or not skinData then return end

    -- 아이콘
    local iconLabel = skinBar:FindFirstChild("_SkinIcon")
    if not iconLabel then
        iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "_SkinIcon"
        iconLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        iconLabel.Position = UDim2.new(0.5, 0, 0.455, 0)
        iconLabel.Size = UDim2.new(0.95, 0, 0.58, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.ScaleType = Enum.ScaleType.Fit
        iconLabel.ZIndex = skinBar.ZIndex + 1
        iconLabel.Parent = skinBar
    end
    local oldVP = skinBar:FindFirstChild("_SkinVP")
    if oldVP then oldVP:Destroy() end
    local oldBrush = skinBar:FindFirstChild("_SkinBrush")
    if oldBrush then oldBrush:Destroy() end

    if skinData.icon and skinData.icon ~= "" then
        iconLabel.Image = skinData.icon
        iconLabel.ImageTransparency = 0
        iconLabel.Visible = true
        iconLabel.Size = UDim2.new(0.68, 0, 0.42, 0)  -- icon images render smaller than 3D previews
        if skinData.skinName == "MechGauntlet" then
            iconLabel.Size = UDim2.new(0.98, 0, 0.62, 0)  -- 메크 건틀릿: 이미지 크게
        end
        if skinData.skinName == "Vishnu" then
            iconLabel.Size = UDim2.new(1.0, 0, 0.95, 0)  -- Ascendant: 썸네일 확 크게
        end
        if skinData.skinName == "GlitchFist" then
            -- black hand blends into the dark card; give it a lighter backing so it reads
            iconLabel.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
            iconLabel.BackgroundTransparency = 0.1   -- 거의 불투명한 흰 배경 (글리치 손 가시성)
        else
            iconLabel.BackgroundTransparency = 1
        end
    else
        iconLabel.ImageTransparency = 1
        iconLabel.Visible = false
        local skinPreviews = game:GetService("ReplicatedStorage"):FindFirstChild("SkinPreviews")
        -- Original 카드는 무기 원본 모델을 보여준다(skinName이 아니라 현재 아이템으로 조회)
        local lookupName = skinData.skinName or ""
        if skinData.isOriginal then lookupName = currentSkinItem or "" end
        local previewModel = skinPreviews and skinPreviews:FindFirstChild(lookupName)
        if not previewModel then
            -- 태거 아이템 스킨(배럴/Crusader 등)은 TaggerItemPreviews에 있음
            local tp = game:GetService("ReplicatedStorage"):FindFirstChild("TaggerItemPreviews")
            previewModel = tp and tp:FindFirstChild(lookupName)
        end
        if skinData.isCustom then
            -- 색 커스텀 카드: 팔레트 이모지
            local emo = Instance.new("TextLabel")
            emo.Name = "_SkinBrush"
            emo.AnchorPoint = Vector2.new(0.5, 0.5)
            emo.Position = UDim2.new(0.5, 0, 0.455, 0)
            emo.Size = UDim2.new(0.7, 0, 0.5, 0)
            emo.BackgroundTransparency = 1
            emo.Text = "🎨"
            emo.TextScaled = true
            emo.ZIndex = skinBar.ZIndex + 1
            emo.Parent = skinBar
        elseif previewModel then
            local vp = Instance.new("ViewportFrame")
            vp.Name                   = "_SkinVP"
            vp.Size                   = UDim2.new(0.85, 0, 0.58, 0)
            vp.AnchorPoint            = Vector2.new(0.5, 0.5)
            vp.Position               = UDim2.new(0.5, 0, 0.455, 0)
            vp.BackgroundTransparency = 1
            vp.LightDirection         = Vector3.new(-1, -2, -1)
            vp.LightColor             = Color3.new(1, 1, 1)
            vp.Ambient                = Color3.fromRGB(120, 120, 160)
            vp.ZIndex                 = skinBar.ZIndex + 1
            vp.Parent                 = skinBar
            local clone = previewModel:Clone()
            clone.Parent = vp
            -- 어두운 본체 스킨은 뷰포트 배경에 묻힘 → 흰 아웃라인으로 실루엣 확보
            if currentSkinItem == "Demonspear" or skinData.skinName == "LegendKatana" then
                local hl = Instance.new("Highlight")
                hl.Adornee = clone
                hl.FillTransparency = 1
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.OutlineTransparency = 0
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = clone
            end
            local cam = Instance.new("Camera")
            cam.FieldOfView = 35
            cam.Parent       = vp
            vp.CurrentCamera = cam
            -- 바운딩: Model은 GetBoundingBox, 단일 Part는 CFrame/Size (PreviewTuner와 동일 공식)
            local bcf, bsize
            if clone:IsA("Model") then
                bcf, bsize = clone:GetBoundingBox()
            elseif clone:IsA("BasePart") then
                bcf, bsize = clone.CFrame, clone.Size
            else
                bcf, bsize = CFrame.new(), Vector3.new(10, 10, 10)
            end
            local maxDim = math.max(bsize.X, bsize.Y, bsize.Z)
            -- 카메라 튜닝값 (Original은 무기 원본이라 무기명 키, 나머지는 스킨명 키)
            local camKey = (skinData.isOriginal and currentSkinItem) or skinData.skinName or ""
            local camCfg = SKIN_CAM[camKey]
            local distMul = camCfg and camCfg.dist or 1.8
            local dir     = camCfg and camCfg.dir or Vector3.new(0.3, 0.2, 1)
            local target  = camCfg and camCfg.target or Vector3.new(0, 0, 0)
            local dist = maxDim * distMul
            local tgt  = bcf.Position + target * maxDim
            cam.CFrame = CFrame.new(tgt + dir * dist, tgt)
            -- 튜너 연동: 클릭 시 이 값에서 시작하도록 속성 기록
            vp:SetAttribute("PreviewId", camKey)
            vp:SetAttribute("_tuneDist", distMul)
            vp:SetAttribute("_tuneDir", dir)
            vp:SetAttribute("_tuneTarget", target)
            -- 레인보우 스킨: 뷰포트 안에서는 clone된 _RainbowCycle 스크립트가 실행되지 않으므로
            -- 게임과 동일한 방식(SPEED 0.222, 채도 0.7)으로 색을 직접 순환시킨다
            if (skinData.skinName or ""):find("Rainbow") then
                local RunService = game:GetService("RunService")
                local cycleScript = clone:FindFirstChild("_RainbowCycle", true)
                local target = cycleScript and cycleScript.Parent
                local cycleParts = {}
                if target and target:IsA("BasePart") then
                    cycleParts[#cycleParts+1] = target
                elseif target and target:IsA("Model") then
                    for _, d in ipairs(target:GetDescendants()) do
                        if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
                            cycleParts[#cycleParts+1] = d
                        end
                    end
                end
                if #cycleParts > 0 then
                    local conn
                    conn = RunService.Heartbeat:Connect(function()
                        if not vp.Parent then conn:Disconnect(); return end
                        local hue = (tick() * 0.222) % 1
                        local col = Color3.fromHSV(hue, 0.7, 1)
                        for _, p in ipairs(cycleParts) do p.Color = col end
                    end)
                end
            end
        else
            -- 전용 모델이 없는 색놀이 스킨: 무기 원본에 스킨 색을 입혀 뷰포트로 표시
            local weaponModel = skinPreviews and skinPreviews:FindFirstChild(currentSkinItem or "")
            local styleColor, styleCycle = nil, false
            if skinData.cycle or skinData.rainbow then
                styleCycle = true
            elseif skinData.solidHSV then
                styleColor = Color3.fromHSV(skinData.solidHSV[1], skinData.solidHSV[2], skinData.solidHSV[3])
            elseif skinData.color then
                styleColor = Color3.fromRGB(skinData.color[1], skinData.color[2], skinData.color[3])
            end
            if weaponModel and (styleColor or styleCycle) then
                local vp = Instance.new("ViewportFrame")
                vp.Name                   = "_SkinVP"
                vp.Size                   = UDim2.new(0.85, 0, 0.58, 0)
                vp.AnchorPoint            = Vector2.new(0.5, 0.5)
                vp.Position               = UDim2.new(0.5, 0, 0.455, 0)
                vp.BackgroundTransparency = 1
                vp.LightDirection         = Vector3.new(-1, -2, -1)
                vp.LightColor             = Color3.new(1, 1, 1)
                vp.Ambient                = Color3.fromRGB(120, 120, 160)
                vp.ZIndex                 = skinBar.ZIndex + 1
                vp.Parent                 = skinBar
                local clone = weaponModel:Clone()
                clone.Parent = vp
                if currentSkinItem == "Demonspear" then
                    local hl = Instance.new("Highlight")
                    hl.Adornee = clone
                    hl.FillTransparency = 1
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.OutlineTransparency = 0
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Parent = clone
                end
                local cam = Instance.new("Camera")
                cam.FieldOfView = 35
                cam.Parent = vp
                vp.CurrentCamera = cam
                -- 색 입힐 파트 수집 + 재질 적용
                local skinMat = skinData.material and Enum.Material[skinData.material]
                local parts = {}
                local function collect(p)
                    if p:IsA("BasePart") then
                        if styleCycle then p.Material = Enum.Material.Neon
                        elseif skinMat then p.Material = skinMat end
                        parts[#parts+1] = p
                    end
                end
                if clone:IsA("BasePart") then collect(clone) end
                for _, d in ipairs(clone:GetDescendants()) do collect(d) end
                local function paint(c)
                    for _, p in ipairs(parts) do
                        p.Color = c
                        if p:IsA("MeshPart") then p.TextureID = "" end
                        local sm = p:FindFirstChildWhichIsA("SpecialMesh")
                        if sm then sm.TextureId = ""; sm.VertexColor = Vector3.new(c.R, c.G, c.B) end
                    end
                end
                if styleCycle then
                    local RunService = game:GetService("RunService")
                    local conn
                    conn = RunService.Heartbeat:Connect(function()
                        if not vp.Parent then conn:Disconnect(); return end
                        paint(Color3.fromHSV((tick() * 0.222) % 1, 0.7, 1))
                    end)
                elseif styleColor then
                    paint(styleColor)
                end
                -- 카메라: 무기 원본 기준(SKIN_CAM[무기명] 공유)
                local bcf, bsize
                if clone:IsA("Model") then
                    bcf, bsize = clone:GetBoundingBox()
                elseif clone:IsA("BasePart") then
                    bcf, bsize = clone.CFrame, clone.Size
                else
                    bcf, bsize = CFrame.new(), Vector3.new(10, 10, 10)
                end
                local maxDim = math.max(bsize.X, bsize.Y, bsize.Z)
                local camCfg = SKIN_CAM[currentSkinItem or ""]
                local distMul = camCfg and camCfg.dist or 1.8
                local dir     = camCfg and camCfg.dir or Vector3.new(0.3, 0.2, 1)
                local target  = camCfg and camCfg.target or Vector3.new(0, 0, 0)
                local dist = maxDim * distMul
                local tgt  = bcf.Position + target * maxDim
                cam.CFrame = CFrame.new(tgt + dir * dist, tgt)
                vp:SetAttribute("PreviewId", currentSkinItem)
                vp:SetAttribute("_tuneDist", distMul)
                vp:SetAttribute("_tuneDir", dir)
                vp:SetAttribute("_tuneTarget", target)
            else
                -- 색·모델 정보가 모두 없을 때만 붓 이모지
                local brush = Instance.new("TextLabel")
                brush.Name = "_SkinBrush"
                brush.AnchorPoint = Vector2.new(0.5, 0.5)
                brush.Position = UDim2.new(0.5, 0, 0.455, 0)
                brush.Size = UDim2.new(0.7, 0, 0.5, 0)
                brush.BackgroundTransparency = 1
                brush.Text = "🖌️"
                brush.TextScaled = true
                brush.ZIndex = skinBar.ZIndex + 1
                brush.Parent = skinBar
            end
        end
    end

    -- 이름
    local nameLabel = skinBar:FindFirstChild("_SkinName")
    if not nameLabel then
        nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "_SkinName"
        nameLabel.AnchorPoint = Vector2.new(0.5, 0)
        nameLabel.Position = UDim2.new(0.5, 0, 0.02, 0)
        nameLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.ZIndex = skinBar.ZIndex + 1
        nameLabel.Parent = skinBar
    end
    nameLabel.Text = skinData.isOriginal and "Original" or (skinData.isCustom and "🎨 Custom" or (skinData.displayName or ""))

    -- 잠금 오버레이
    local lockOverlay = skinBar:FindFirstChild("_LockOverlay")
    if not skinData.owned then
        if not lockOverlay then
            lockOverlay = Instance.new("Frame")
            lockOverlay.Name = "_LockOverlay"
            lockOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
            lockOverlay.Position = UDim2.new(0.5, 0, 0.455, 0)
            lockOverlay.Size = UDim2.new(0.85, 0, 0.58, 0)
            lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            lockOverlay.BackgroundTransparency = 0.5
            lockOverlay.ZIndex = skinBar.ZIndex + 2
            lockOverlay.Parent = skinBar
            Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0.05, 0)
            local lockIcon = Instance.new("TextLabel")
            lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            lockIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
            lockIcon.Size = UDim2.new(1, 0, 0.5, 0)
            lockIcon.BackgroundTransparency = 1
            lockIcon.Text = "🔒"
            lockIcon.TextScaled = true
            lockIcon.ZIndex = skinBar.ZIndex + 3
            lockIcon.Parent = lockOverlay
        end
        -- 뷰포트를 완전히 덮도록 크기 강제(재사용/기존 카드 대비)
        lockOverlay.Size = UDim2.new(0.85, 0, 0.58, 0)
        lockOverlay.Position = UDim2.new(0.5, 0, 0.455, 0)
        lockOverlay.Visible = true
    elseif lockOverlay then
        lockOverlay.Visible = false
    end

    -- Equip 버튼 라벨
    if equipBtn then
        local btnLabel = equipBtn:FindFirstChild("_EquipLabel")
        if not btnLabel then
            btnLabel = Instance.new("TextLabel")
            btnLabel.Name = "_EquipLabel"
            btnLabel.AnchorPoint = Vector2.new(0.5, 0.5)
            btnLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
            btnLabel.Size = UDim2.new(1, 0, 1, 0)
            btnLabel.BackgroundTransparency = 1
            btnLabel.TextScaled = true
            btnLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
            btnLabel.ZIndex = equipBtn.ZIndex + 1
            btnLabel.Parent = equipBtn
        end
        if skinData.isOriginal then
            btnLabel.Text = skinData.originalActive and "✅ Original" or "Original"
            btnLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
        elseif skinData.isCustom then
            btnLabel.Text = skinData.customActive and "✅ Customize" or "🎨 Customize"
            btnLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
        elseif not skinData.owned then
            btnLabel.Text = "🔒 Locked"
            btnLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        elseif skinData.equipped then
            btnLabel.Text = "✅ Unequip"
            btnLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
        else
            btnLabel.Text = "Equip"
            btnLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
        end
    end

    -- 카드 테두리 = 스킨 등급색 (텍스트 뱃지 없이 색으로만 구분)
    if skinData.isOriginal or skinData.isCustom then
        skinBar.ImageColor3 = Color3.fromRGB(255, 255, 255)
    else
        skinBar.ImageColor3 = RARITY_BORDER[skinData.rarity] or Color3.fromRGB(210, 210, 210)
    end
end

-- 스킨 장착/해제 처리 (skinData 직접 전달)
local function handleSkinEquip(skinData)
    if not currentSkinItem or not skinData then return end
    -- 원본 카드: 장착 스킨 해제 + 색/재질 속성 제거 → 원본 텍스처로 복귀
    if skinData.isOriginal then
        setPlayerSkin:FireServer(currentSkinItem, nil)
        itemColorRemote:FireServer(currentSkinItem, "__RESET_ALL__")
        task.wait(0.1)
        refreshSkinUI(currentSkinItem)
        return
    end
    -- 커스텀 카드: 스킨 장착이 아니라 컬러 커스텀 화면을 연다
    if skinData.isCustom then
        local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
        if currentSkinItem == "Gauntlet" then
            local customGui = pg and pg:FindFirstChild("GauntletCustomGui")
            if customGui then
                customGui.Enabled = true
            else
                showWarning("커스텀 화면을 찾을 수 없어요")
            end
        else
            -- ItemNoob 등: 부위별 컬러 UI 열기 (CurrentItem 재설정 → ItemColorClient가 openFor)
            local colorGui = pg and pg:FindFirstChild("ItemColorGui")
            if colorGui then
                colorGui:SetAttribute("CurrentItem", "")
                colorGui:SetAttribute("CurrentItem", currentSkinItem)
            else
                showWarning("컬러 화면을 찾을 수 없어요")
            end
        end
        return
    end
    if not skinData.owned then
        showWarning("You don't own this skin!")
        return
    end
    if skinData.equipped then
        setPlayerSkin:FireServer(currentSkinItem, nil)
    else
        setPlayerSkin:FireServer(currentSkinItem, skinData.skinName)
    end
    task.wait(0.1)
    refreshSkinUI(currentSkinItem)
end

-- 스킨 목록 새로고침 (동적 그리드)
function refreshSkinUI(itemName)
    if not skinUI or not skinScroll or not slotTemplate then return end
    currentSkinItem = itemName

    -- 기존 동적 슬롯 제거
    for _, c in ipairs(skinScroll:GetChildren()) do
        if c:IsA("GuiObject") and c.Name == "_SkinCard" then
            c:Destroy()
        end
    end

    local skinList = getPlayerSkin:InvokeServer(itemName) or {}

    -- 건틀렛: 서버 스킨 목록 맨 앞에 "커스텀" 카드를 끼운다.
    -- (커스텀은 색 팔레트 화면을 여는 특수 카드. 나중에 레인보우 건틀렛 등 고정 스킨은
    --  서버 skinList로 추가되어 이 커스텀 카드 옆에 나란히 표시됨)
    if itemName == "Gauntlet" then
        table.insert(skinList, 1, {
            skinName = "_Custom",
            isCustom = true,
            owned = true,      -- 항상 접근 가능(잠금 표시 안 함)
            equipped = false,
        })
    elseif itemName == "ItemNoob" or itemName == "Spear" or itemName == "stone" or itemName == "bear_trap" or itemName == "PushTool" or itemName == "ClassicSword" or itemName == "KatanaSword2" or itemName == "HammerLow" or itemName == "SakuraBlade" or itemName == "HammerHigh" or itemName == "tsunami" or itemName == "tox_box" or itemName == "tnt" or itemName == "Demonspear" or itemName == "Wooden Barrel" then
        -- 색 스킨 숨기고 색/재질 _Custom 카드로 대체 (effect/form 스킨은 유지)
        local COLOR_SKINS = {
            ItemNoob = {OrangeNoob=true,YellowNoob=true,GreenNoob=true,BlueNoob=true,IndigoNoob=true,VioletNoob=true},
            Spear = {GoldSpear=true,SilverSpear=true,PinkSpear=true,BlueSpear=true,GreenSpear=true,BlackSpear=true},
            stone = {BlueStone=true,GoldStone=true,GreenStone=true,PinkStone=true,SilverStone=true},
            bear_trap = {BlueBearTrap=true,BronzeBearTrap=true,CobaltBearTrap=true,CrimsonBearTrap=true,DeepPurpleBearTrap=true,EmeraldBearTrap=true,GoldBearTrap=true,GreenBearTrap=true,ObsidianBearTrap=true,OrangeBearTrap=true,RedBearTrap=true,ToxicBearTrap=true,VioletBearTrap=true,YellowBearTrap=true},
            PushTool = {RedFist=true,OrangeFist=true,YellowFist=true,GreenFist=true,BlueFist=true,VioletFist=true,PinkFist=true},
            ClassicSword = {RedSword=true,OrangeSword=true,YellowSword=true,GreenSword=true,BlueSword=true,IndigoSword=true,VioletSword=true},
            KatanaSword2 = {RedKatana=true,OrangeKatana=true,YellowKatana=true,GreenKatana=true,CyanKatana=true,IndigoKatana=true,VioletKatana=true,WhiteKatana=true},
            HammerLow = {RedHammer=true,OrangeHammer=true,GreenHammer=true,BlueHammer=true,PurpleHammer=true,PinkHammer=true,WhiteHammer=true,BlackHammer=true},
            SakuraBlade = {RedSakura=true,OrangeSakura=true,GreenSakura=true,BlueSakura=true,IndigoSakura=true,VioletSakura=true,GoldSakura=true,SilverSakura=true,BlackSakura=true},
            HammerHigh = {RedRocketHammer=true,OrangeRocketHammer=true,GreenRocketHammer=true,BlueRocketHammer=true,IndigoRocketHammer=true,VioletRocketHammer=true,GoldRocketHammer=true,WhiteRocketHammer=true,BlackRocketHammer=true},
        }
        local colorSkins = COLOR_SKINS[itemName] or {}
        local filtered = {}
        for _, s in ipairs(skinList) do
            if not colorSkins[s.skinName] then table.insert(filtered, s) end
        end
        skinList = filtered
        -- form/effect 스킨이 하나도 장착 안 됐으면 색 커스텀 또는 원본이 적용 중
        local anyEquipped = false
        for _, s in ipairs(skinList) do
            if s.equipped then anyEquipped = true; break end
        end
        -- 색/재질 속성이 하나라도 있으면 색 커스텀 적용 중, 없으면 원본 상태
        local hasColorCustom = false
        local ccfg = noobPalette.getConfig(itemName)
        if ccfg then
            local plr = game:GetService("Players").LocalPlayer
            for _, z in ipairs(ccfg.zones) do
                if plr:GetAttribute(ccfg.colorAttr .. "_" .. z) ~= nil then hasColorCustom = true; break end
            end
        end
        table.insert(skinList, 1, {
            skinName = "_Custom",
            isCustom = true,
            owned = true,
            equipped = false,
            customActive = (not anyEquipped) and hasColorCustom,
        })
        -- 원본 카드(맨 앞): 장착 스킨 + 색 모두 해제 → 원본 텍스처
        table.insert(skinList, 1, {
            skinName = "_Original",
            isOriginal = true,
            owned = true,
            equipped = false,
            originalActive = (not anyEquipped) and (not hasColorCustom),
        })
    end

    -- 출시 예정 문구
    local comingSoon = skinUI:FindFirstChild("_ComingSoon")
    if #skinList == 0 then
        if not comingSoon then
            comingSoon = Instance.new("TextLabel")
            comingSoon.Name               = "_ComingSoon"
            comingSoon.Size               = UDim2.new(0.7, 0, 0.25, 0)
            comingSoon.AnchorPoint        = Vector2.new(0.5, 0.5)
            comingSoon.Position           = UDim2.new(0.5, 0, 0.5, 0)
            comingSoon.BackgroundColor3   = Color3.fromRGB(30, 30, 30)
            comingSoon.BackgroundTransparency = 0.3
            comingSoon.TextColor3         = Color3.fromRGB(180, 150, 40)
            comingSoon.Text               = "🎨 Skins Coming Soon!"
            comingSoon.TextScaled         = true
            comingSoon.Font               = Enum.Font.GothamBold
            comingSoon.ZIndex             = (skinUI.ZIndex or 1) + 5
            Instance.new("UICorner", comingSoon).CornerRadius = UDim.new(0.15, 0)
            local stroke = Instance.new("UIStroke", comingSoon)
            stroke.Color = Color3.fromRGB(255, 200, 50)
            stroke.Thickness = 2
            comingSoon.Parent = skinUI
        end
        comingSoon.Visible = true
        -- skinScroll.Visible은 끄지 않음: Visible 토글이 레이아웃(AbsoluteSize)을
        -- 무너뜨려 이후 정상 호출 때 스크롤이 깨지는 문제 방지. 카드만 비워두면 충분.
        return
    elseif comingSoon then
        comingSoon.Visible = false
    end
    skinScroll.Visible = true

    -- 슬롯 동적 생성
    for i, skinData in ipairs(skinList) do
        local card = slotTemplate:Clone()
        card.Name = "_SkinCard"
        card.Visible = true
        card.LayoutOrder = i
        card.Size = UDim2.fromScale(1, 1)  -- 셀(고정 픽셀)을 꽉 채움
        card.Parent = skinScroll
        local equipBtn = card:FindFirstChild("ImageButton")
        updateSkinSlot(card, equipBtn, skinData)
        if equipBtn then
            equipBtn.MouseButton1Click:Connect(function()
                handleSkinEquip(skinData)
            end)
        end
    end

    -- ── CanvasSize: 행 수 기반 Scale로 한 번만 고정 설정 ──
    -- 핵심: 카드를 셀 크기(1,1)에 맞췄으므로 잘 작동하는 King 아이템 인벤(Container)과
    -- 동일하게 CanvasSize를 픽셀(Offset)로 설정한다. AbsoluteCellSize는 실측 셀 높이라
    -- 카드 높이와 정확히 일치한다(카드 Size=1,1로 고정했으므로).
    do
        skinScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
        skinScroll.CanvasPosition = Vector2.new(0, 0)
        if _skinCanvasConn then _skinCanvasConn:Disconnect(); _skinCanvasConn = nil end

        local cols = math.max(1, skinGrid.FillDirectionMaxCells)
        local rows = math.ceil(#skinList / cols)

        -- ★ 근본 원인: 셀이 Scale(0.42)이면 CanvasSize를 픽셀로 키울 때 셀이 늘어난
        --   캔버스 기준으로 재계산되어 폭주(120→711px)한다. 이 악순환을 끊으려면
        --   셀을 고정 픽셀(Offset)로 박아야 한다. 그러면 캔버스 크기와 무관하게 셀이 고정됨.
        local function rebuild()
            local scrollH = skinScroll.AbsoluteSize.Y
            local scrollW = skinScroll.AbsoluteSize.X
            if scrollH < 1 or scrollW < 1 then return end
            -- 현재 스크롤 크기 기준으로 셀/패딩을 픽셀로 환산해 고정
            local cellWpx = 0.30 * scrollW
            local cellHpx = 0.55 * scrollH  -- 세로 크기 (0.42→0.55로 키움)
            local padWpx  = 0.02 * scrollW
            local padHpx  = 0.05 * scrollH
            skinGrid.CellSize    = UDim2.fromOffset(math.floor(cellWpx), math.floor(cellHpx))
            skinGrid.CellPadding = UDim2.fromOffset(math.floor(padWpx), math.floor(padHpx))
            -- 캔버스 = 행수×셀 + (행수-1)×패딩 + 바닥 여유(셀 절반)
            local totalPx = rows * cellHpx + math.max(0, rows - 1) * padHpx + cellHpx * 0.5
            skinScroll.CanvasSize = UDim2.fromOffset(0, math.ceil(totalPx))
        end

        rebuild()
        task.defer(rebuild)
        task.delay(0.3, rebuild)
    end
end

local function openSkinUI(itemName)
    if not skinUI then return end
    tooltip.Visible = false
    skinUI.Visible = true
    task.wait()
    refreshSkinUI(itemName)
end

local function closeSkinUI()
    if not skinUI then return end
    skinUI.Visible = false
    currentSkinItem = nil
end

if tooltipSkin then
    tooltipSkin.MouseButton1Click:Connect(function()
        if currentTooltipItem then
            openSkinUI(currentTooltipItem.id)
        end
    end)
end

if skinClose then
    skinClose.MouseButton1Click:Connect(closeSkinUI)
end

-- ItemColorGui(부위별 컬러 UI) 닫히면 스킨 목록 새로고침 → 커스텀 적용 시 체크 즉시 반영
do
    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    local colorGui = pg:WaitForChild("ItemColorGui", 10)
    if colorGui then
        colorGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not colorGui.Enabled and currentSkinItem then
                task.wait(0.15)
                if currentSkinItem then refreshSkinUI(currentSkinItem) end
            end
        end)
    end
end

print("✅ Skin UI 연결 완료! (동적 스크롤 그리드)")
