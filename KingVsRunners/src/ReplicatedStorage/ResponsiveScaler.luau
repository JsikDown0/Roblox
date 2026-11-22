-- ResponsiveScaler
-- 모든 UI 의 디바이스(모바일/PC)별 반응형 스케일 + 위치를 한 곳에서 관리.
-- 각 UI 클라이언트 스크립트는 이 모듈을 require 해서 한 줄로 호출.
--
-- 사용 예시:
--   local Scaler = require(game.ReplicatedStorage.ResponsiveScaler)
--
--   -- 중앙 패널형 (투표/결과/로드아웃): UIScale 만 디바이스별로
--   Scaler.applyPanel(panel, {
--       baseW = 580, baseH = 460,
--       Mobile = { frac = 0.85, minScale = 0.55 },
--       PC     = { frac = 0.85, minScale = 0.55 },
--   })
--
--   -- 가장자리 고정형 (HUD/이모트/스킬바): 위치 + 스케일 디바이스별로
--   Scaler.applyEdge(screenGui, targetFrame, {
--       baseW = 1280, baseH = 720,
--       Mobile = { pos = UDim2.new(1,-20,1,-200), minScale = 0.7 },
--       PC     = { pos = UDim2.new(1,-20,1,-200), minScale = 0.7 },
--   })

local UserInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera

local Scaler = {}

-- ── 디바이스 판정 (전 UI 통일) ──────────────────────────────────
-- 터치만 있고 키보드/마우스가 없으면 모바일. (마우스 연결 태블릿은 PC 취급)
-- 뷰포트가 준비될 때까지 짧게 대기한다.
-- ⚠️ 부팅 직후 CurrentCamera.ViewportSize 가 (0,0) 인 순간이 있다. 그때 isMobile() 을
--    호출하면 아래 "vp.Y > 0" 조건이 실패해 PC 로 판정되고, HudButtonClient 처럼
--    cfg 를 최상단에서 한 번만 읽는 스크립트는 그 값으로 굳어버린다.
--    → 같은 세션에서 PC/Mobile 레이아웃이 섞여 좌측 HUD 가 간헐적으로 찌그러졌다(실측).
local function waitForViewport()
	if camera and camera.ViewportSize.Y > 0 then return end
	local t0 = os.clock()
	while os.clock() - t0 < 3 do
		camera = workspace.CurrentCamera or camera
		if camera and camera.ViewportSize.Y > 0 then return end
		task.wait()
	end
end

function Scaler.isMobile()
	local UIS = UserInputService
	-- 실기기 모바일: 터치 O + 키보드·마우스 X (뷰포트와 무관하게 판정 가능)
	if UIS.TouchEnabled and not UIS.KeyboardEnabled and not UIS.MouseEnabled then
		return true
	end
	-- 그 외에는 뷰포트 크기가 필요하므로 준비를 기다린다
	waitForViewport()
	-- Studio 폰 에뮬레이터 대응: 키보드/마우스가 남아있어도 화면이 폰 크기면 모바일 취급.
	-- ⚠️ TouchEnabled 조건이 반드시 함께 필요하다.
	--    이 조건이 없으면 PC 에서 창을 줄이거나 Studio 출력창을 크게 열어 뷰포트 높이가
	--    500 이하가 될 때마다 모바일로 판정된다. 게다가 HudButtonClient 는 부팅 시
	--    cfg 를 한 번만 읽는데 ViewportSize 변화에 반응하는 UI 스크립트가 17개나 있어,
	--    같은 세션에서 PC/Mobile 설정이 섞여 좌측 HUD 가 간헐적으로 찌그러졌다(실측).
	--    에뮬레이터는 터치를 켜주므로 이 조건으로도 정상 감지된다.
	if UIS.TouchEnabled then
		local vp = camera.ViewportSize
		if vp.Y > 0 and math.min(vp.X, vp.Y) <= 500 then
			return true
		end
	end
	return false
end

function Scaler.device()
	return Scaler.isMobile() and "Mobile" or "PC"
end

-- ── UIScale 헬퍼 ────────────────────────────────────────────────
local function getOrMakeScale(target)
	return target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", target)
end

-- ── 중앙 패널형 ─────────────────────────────────────────────────
-- target(보통 Panel/Frame) 에 UIScale 을 디바이스별 설정으로 적용.
-- cfg = { baseW, baseH, Mobile = {frac, minScale}, PC = {frac, minScale} }
function Scaler.applyPanel(target, cfg)
	local dev = Scaler.device()
	local d   = cfg[dev]
	local baseW, baseH = cfg.baseW or 580, cfg.baseH or 460
	local frac     = d.frac or 0.85
	local minScale = d.minScale or 0.55

	local uiScale = getOrMakeScale(target)
	local function update()
		local vp = camera.ViewportSize
		local s = math.min((vp.X * frac) / baseW, (vp.Y * frac) / baseH, 1)
		uiScale.Scale = math.max(s, minScale)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return uiScale
end

-- ── 가장자리 고정형 ─────────────────────────────────────────────
-- screenGui 에 UIScale, targetFrame 에 위치를 디바이스별로 적용.
-- cfg = { baseW, baseH, anchor?, Mobile = {pos, minScale, frac?}, PC = {...} }
-- pos 가 nil 이면 위치는 건드리지 않음 (스케일만 적용).
function Scaler.applyEdge(screenGui, targetFrame, cfg)
	local dev = Scaler.device()
	local d   = cfg[dev]
	local baseW, baseH = cfg.baseW or 1280, cfg.baseH or 720
	local frac     = d.frac or 0.85
	local minScale = d.minScale or 0.55

	-- 위치 적용 (옵션)
	if targetFrame and d.pos then
		if cfg.anchor then targetFrame.AnchorPoint = cfg.anchor end
		targetFrame.Position = d.pos
	end

	-- 스케일 적용
	local uiScale = getOrMakeScale(screenGui)
	local function update()
		local vp = camera.ViewportSize
		local s = math.min((vp.X * frac) / baseW, (vp.Y * frac) / baseH, 1)
		uiScale.Scale = math.max(s, minScale)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return uiScale
end

return Scaler
