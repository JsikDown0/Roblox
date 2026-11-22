-- MetaUIResponsiveScaler
-- NewGui 의 메타/메뉴 UI 들에 일괄적으로 UIScale + ScreenInsets 적용.
-- 이 UI 들은 자체 LocalScript가 없어서 별도 글로벌 스케일러가 필요.

local newGui = script.Parent  -- NewGui Folder
local camera = workspace.CurrentCamera

-- 메타/메뉴 UI 목록 (Store, Codes, Rewards 등)
-- HUD, Inven 류는 이미 자체 LocalScript에서 처리하므로 여기서 제외.
local META_UIS = {
	"Store",
	"Codes",
	"Rewards",
	"Quests",
	"Index",
	"Settings",
	"Dialogue",
	"Egg",
	"Teleport",
}

local BASE_W, BASE_H = 1280, 720

local function applyToGui(gui)
	-- 모바일 노치/펀치홀 자동 회피
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

	-- 반응형 UIScale
	local uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", gui)
	local function update()
		local vp = camera.ViewportSize
		local s = math.min((vp.X * 0.85) / BASE_W, (vp.Y * 0.85) / BASE_H, 1)
		uiScale.Scale = math.max(s, 0.55)  -- 모바일 작은 화면 보호 (최소 55%)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
end

-- 각 메타 UI 에 적용
for _, name in ipairs(META_UIS) do
	local gui = newGui:WaitForChild(name, 5)
	if gui and gui:IsA("ScreenGui") then
		applyToGui(gui)
	else
		warn("MetaUIResponsiveScaler: " .. name .. " 를 찾을 수 없음 (또는 ScreenGui 가 아님)")
	end
end

print("✅ MetaUIResponsiveScaler 적용 완료 (" .. #META_UIS .. "개 메타 UI)")
