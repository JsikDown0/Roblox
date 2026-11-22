-- MobileUIScaler — 화면 크기 기반 UI 자동 스케일링
-- 책임:
--   "MobileScaled" 태그 가진 ScreenGui 들에 UIScale 인스턴스 자동 추가
--   화면 크기 변경 시 Scale 값 동적 갱신
--   PC 풀스크린에서는 1.0 (그대로), 모바일/작은 창에서는 자동 축소
--
-- 사용법:
--   대상 ScreenGui 에 CollectionService 태그 "MobileScaled" 추가하면 자동 적용.
--   EmotionBarGui 같이 자체 UIScale 시스템 있는 GUI 는 태그 안 붙이고 그대로 두면 됨.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ════════════ 튜닝 ════════════
local TAG_NAME    = "MobileScaled"
local BASE_W      = 1280   -- 기준 해상도 너비 (이보다 작은 화면에서는 축소 시작)
local BASE_H      = 720    -- 기준 해상도 높이
local FILL_FACTOR = 0.95   -- 화면을 얼마나 채울지 (1.0 = 가득, 0.85 = 살짝 여유)
local MAX_SCALE   = 1.0    -- PC 풀스크린에서 더 크게 안 만듦 (UI 가 비대해지지 않게)
local MIN_SCALE   = 0.55   -- 너무 작은 모바일에서도 가독성 최저선 유지
-- ════════════════════════════

-- 등록된 UIScale 추적 (약한 참조처럼 작동 — Parent 사라지면 자동 정리)
local activeScales = {}

local function computeScale()
	local vp = Camera.ViewportSize
	if vp.X == 0 or vp.Y == 0 then return 1.0 end
	local s = math.min((vp.X * FILL_FACTOR) / BASE_W, (vp.Y * FILL_FACTOR) / BASE_H, MAX_SCALE)
	return math.max(s, MIN_SCALE)
end

local function updateAllScales()
	local s = computeScale()
	for scale, _ in pairs(activeScales) do
		if scale.Parent then
			scale.Scale = s
		else
			activeScales[scale] = nil  -- 정리됨
		end
	end
end

local function applyToGui(gui)
	if not gui:IsA("ScreenGui") then return end
	-- ⚠️ 이미 다른 스케일러가 관리 중인 ScreenGui 는 건드리지 않는다.
	--    ResponsiveScaler.getOrMakeScale 은 FindFirstChildOfClass 로 기존 UIScale 을
	--    그대로 재사용한다. 둘 다 적용되면 하나의 객체를 두고 값을 서로 덮어쓰는데,
	--    FILL_FACTOR 가 여기는 0.95, 저쪽은 0.85 라 결과가 갈린다.
	--    양쪽 다 ViewportSize 변경에 연결돼 있어 나중에 발동한 쪽이 이긴다 → 실행마다 결과가 달라짐.
	--    실측(2026-08): HUD 가 0.70/0.55 를 오가며 코인바와 버튼이 겹쳤다.
	--    (작은 화면에서는 양쪽 다 하한 0.55 에 걸려 증상이 가려진다. 뷰포트 높이 약 466 초과부터 드러남)
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("UIScale") and c.Name ~= "AutoMobileScale" then
			warn("[MobileUIScaler] " .. gui.Name .. " 은 이미 자체 UIScale 이 있어 건너뜀")
			return
		end
	end
	-- 이미 처리한 GUI 면 스킵 (중복 UIScale 방지)
	local existing = gui:FindFirstChild("AutoMobileScale")
	if existing and existing:IsA("UIScale") then
		activeScales[existing] = true
		existing.Scale = computeScale()
		return
	end
	-- 새 UIScale 추가
	local uiScale = Instance.new("UIScale")
	uiScale.Name   = "AutoMobileScale"
	uiScale.Scale  = computeScale()
	uiScale.Parent = gui
	activeScales[uiScale] = true
end

-- 1) 이미 태그 가진 모든 GUI 에 즉시 적용
for _, gui in ipairs(CollectionService:GetTagged(TAG_NAME)) do
	applyToGui(gui)
end

-- 2) 나중에 태그 붙는 GUI 도 자동 적용
CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(applyToGui)

-- 3) 화면 크기 변경 시 모든 UIScale 갱신 (창 리사이즈, 회전 등)
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAllScales)

-- 4) 카메라 자체가 바뀌었을 때도 대응
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
	updateAllScales()
end)

print(string.format("✅ MobileUIScaler 활성 (base %d×%d, fill %.2f, scale %.3f)",
	BASE_W, BASE_H, FILL_FACTOR, computeScale()))
