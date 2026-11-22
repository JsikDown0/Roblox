-- GameUIScaler — RoundSystem 이 동적으로 만드는 GameUI 의 모바일 적응
-- GameUI 의 SlotFrame 에 미리 부착된 UIScale("SlotScale") 을 ViewportSize 에 따라 자동 업데이트.
-- 500×400 원본 디자인 기준으로 화면에 맞게 비례 축소.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- SlotFrame 의 원본 디자인 사이즈
local BASE_W, BASE_H = 500, 400

local function applySlotScale(slotFrame)
	local uiScale = slotFrame:FindFirstChild("SlotScale")
	if not uiScale or not uiScale:IsA("UIScale") then
		-- 서버가 부착하지 않은 경우 fallback 생성
		uiScale = Instance.new("UIScale")
		uiScale.Name = "SlotScale"
		uiScale.Parent = slotFrame
	end

	local function update()
		local vp = camera.ViewportSize
		-- 화면의 90% 이하만 차지하도록 (SlotFrame 은 큰 모달이라 가독성 우선)
		local s = math.min((vp.X * 0.9) / BASE_W, (vp.Y * 0.9) / BASE_H, 1)
		uiScale.Scale = math.max(s, 0.45)  -- 작은 모바일에서도 최소 45%
	end


	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
end

-- 상단 타이머 축소 (세로가 짧은 화면 대응)
-- TimerFrame 은 서버(RoundSystem.createTimerUI)가 만들며 높이가 44px 로 고정이다.
-- 뷰포트가 짧은 모바일에서는 이 44px 가 화면 높이의 8% 를 먹어,
-- 위에서 굴러 내려오는 태거 아이템을 가린다 (실측: 뷰포트 약 540 높이).
-- 뷰포트 높이에 비례해 줄이되 1080 이상이면 원래 크기 그대로 → PC 영향 없음.
-- ⚠️ FirePressureCountdownClient 의 경고창이 이 수식에 맞춰 바로 아래에 붙는다.
--    TOP_BASE_H / TOP_MIN_S / TOP_PAD 를 바꾸면 그쪽도 같이 고쳐야 한다.
local TOP_BASE_H = 900     -- 이 높이 이상이면 배율 1.0
local TOP_MIN_S  = 0.62    -- 하한 (더 줄이면 글자가 안 읽힘)
local TOP_PAD    = 4       -- 화면 상단 여백
local TIMER_BASE_H = 44    -- 서버가 만드는 원래 높이

local function topScale()
	local vp = camera.ViewportSize
	if vp.Y <= 0 then return 1 end
	return math.clamp(vp.Y / TOP_BASE_H, TOP_MIN_S, 1)
end

local function applyTimerScale(timerFrame)
	local sizeCon = timerFrame:FindFirstChildOfClass("UISizeConstraint")
	local label   = timerFrame:FindFirstChild("TimerLabel")
	local textCon = label and label:FindFirstChildOfClass("UITextSizeConstraint")
	local function update()
		local sc = topScale()
		local h = math.floor(TIMER_BASE_H * sc + 0.5)
		timerFrame.Position = UDim2.new(0.5, 0, 0, TOP_PAD)
		timerFrame.Size     = UDim2.new(0.22, 0, 0, h)
		if sizeCon then
			-- MinSize > MaxSize 인 순간이 생기지 않도록 0 으로 낮췄다가 다시 올린다
			sizeCon.MinSize = Vector2.new(0, 0)
			sizeCon.MaxSize = Vector2.new(320, h)
			sizeCon.MinSize = Vector2.new(150, h)
		end
		if textCon then
			textCon.MinTextSize = 10
			textCon.MaxTextSize = math.max(11, math.floor(22 * sc + 0.5))
		end
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
end

-- ── 대상 발견 방식 ────────────────────────────────────────────
-- 예전엔 ScreenGui(GameUI/GameAnnounceUI) 를 잡아 그 안에서 프레임을 찾았는데,
-- 생성 순서·부모 대입 시점에 계속 의존해서 두 번이나 놓쳤다 (실측):
--   1) WaitForChild("SlotFrame",10) 뒤에 뒀더니 10초간 미적용
--   2) `A or B` 로 하나만 잡아 GameUI 가 아예 처리되지 않음
-- → 이름으로 직접 감시한다. 언제·어디서 생기든 잡힌다.
local function handle(d)
	if not d:IsA("GuiObject") then return end
	if d:GetAttribute("_ScalerApplied") then return end   -- 중복 연결 방지
	if d.Name == "TimerFrame" then
		d:SetAttribute("_ScalerApplied", true)
		applyTimerScale(d)
	elseif d.Name == "SlotFrame" then
		d:SetAttribute("_ScalerApplied", true)
		applySlotScale(d)
	end
end

for _, d in ipairs(playerGui:GetDescendants()) do
	task.spawn(handle, d)
end
playerGui.DescendantAdded:Connect(function(d)
	task.spawn(handle, d)
end)

print("✅ GameUIScaler 준비")
