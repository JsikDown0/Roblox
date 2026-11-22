-- FirePressureCountdownClient
-- 라운드 시작 후 불꽃벽이 발생하기까지의 카운트다운을 화면에 표시.
--
-- 서버에서 매초 "tick" 이벤트로 남은 시간을 받음.
-- "started"는 발생 시점, "clear"는 라운드 도중 종료 시.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local countdownEvent = ReplicatedStorage:WaitForChild("FirePressureCountdown")

-- ── 상태 ────────────────────────────────────────────────
local gui = nil
local frame = nil
local label = nil
local fillBar = nil
local totalDuration = 10  -- 서버 DELAY와 동일 (첫 tick 시 자동 갱신)

-- 상단 축소 (GameUIScaler 의 타이머 축소와 반드시 같은 값이어야 함)
-- 경고창은 TimerFrame 바로 아래에 붙으므로, 타이머가 줄면 이쪽 Y 도 같이 올라간다.
-- 예전엔 Y=60 으로 하드코딩돼 있었다(타이머 8+44=52 기준). 이제 계산으로 맞춘다.
local Camera       = workspace.CurrentCamera
local TOP_BASE_H   = 900
local TOP_MIN_S    = 0.62
local TOP_PAD      = 4
local TIMER_BASE_H = 44
-- 경고창은 타이머를 '가리는' 것이 아니라 '덮어쓴다'. 같은 위치·같은 크기다.
-- 3초 카운트다운 중에 남은 라운드 시간은 볼 이유가 없고, 세로 공간을 추가로 먹지 않는다.

local function topScale()
	local vp = Camera.ViewportSize
	if vp.Y <= 0 then return 1 end
	return math.clamp(vp.Y / TOP_BASE_H, TOP_MIN_S, 1)
end

-- ─────────────────────────────────────────────────────────────
-- UI 생성
-- ─────────────────────────────────────────────────────────────
local function buildUI()
    if gui and gui.Parent then return end

    gui = Instance.new("ScreenGui")
    gui.Name = "FirePressureCountdownGui"
    gui.ResetOnSpawn = false
    -- 라운드 UI(GameUI)와 동일한 ScreenInsets=None 사용 → 둘 다 화면 진짜 상단부터 시작
    pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
    gui.Enabled = false
    gui.DisplayOrder = 6
    gui.Parent = localPlayer:WaitForChild("PlayerGui")

    -- 컨테이너 프레임 (TimerFrame 바로 아래, 작은 상단 배지 스타일)
    -- TimerFrame: Position(0.5, 0, 0, 8), Size(0.22, 0, 0, 44) → 차지 영역: Y = 8 ~ 52
    -- 카운트다운 UI: TimerFrame 끝(52) + 8px 간격 = Y=60 시작
    frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0, 60)
    frame.Size = UDim2.new(0.2, 0, 0, 40)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0   -- 타이머를 완전히 덮으므로 불투명
    frame.BorderSizePixel = 0
    frame.Parent = gui

    -- 사이즈 캡 (TimerFrame 과 일관된 모바일 친화 사이즈)
    local frameSizeConstraint = Instance.new("UISizeConstraint")
    frameSizeConstraint.MaxSize = Vector2.new(280, 40)
    frameSizeConstraint.MinSize = Vector2.new(160, 34)
    frameSizeConstraint.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Name = "Stroke"
    stroke.Color = Color3.fromRGB(255, 130, 60)
    stroke.Thickness = 2
    stroke.Parent = frame

    -- 진행 바 배경 (프레임 하단)
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.AnchorPoint = Vector2.new(0.5, 1)
    barBg.Position = UDim2.new(0.5, 0, 1, -6)
    barBg.Size = UDim2.new(1, -16, 0, 6)
    barBg.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    barBg.BorderSizePixel = 0
    barBg.Parent = frame

    local barBgCorner = Instance.new("UICorner")
    barBgCorner.CornerRadius = UDim.new(1, 0)
    barBgCorner.Parent = barBg

    -- 진행 바 채움 (시간이 지날수록 줄어듦)
    fillBar = Instance.new("Frame")
    fillBar.Name = "Fill"
    fillBar.Size = UDim2.new(1, 0, 1, 0)
    fillBar.BackgroundColor3 = Color3.fromRGB(255, 130, 60)
    fillBar.BorderSizePixel = 0
    fillBar.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fillBar

    -- 메인 라벨 (텍스트, TextScaled 로 사이즈 자동)
    label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -16, 1, -10)  -- 좌우 8 + 진행 바 높이만큼 빼기
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = ""
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 0.6
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Parent = frame

    -- 텍스트 사이즈 캡
    local labelTextConstraint = Instance.new("UITextSizeConstraint")
    labelTextConstraint.MaxTextSize = 18
    labelTextConstraint.MinTextSize = 10
    labelTextConstraint.Parent = label

	-- 뷰포트에 맞춰 크기/위치 갱신 (타이머 바로 아래에 정렬)
	local function applyTopScale()
		local sc = topScale()
		local timerH = math.floor(TIMER_BASE_H * sc + 0.5)
		-- timerH 하나만 쓴다 (GameUIScaler 의 타이머 높이 계산과 동일)
		frame.Position = UDim2.new(0.5, 0, 0, TOP_PAD)
		frame.Size     = UDim2.new(0.22, 0, 0, timerH)   -- 타이머와 동일
		-- MinSize > MaxSize 인 순간을 피하려고 0 으로 낮췄다가 올린다
		frameSizeConstraint.MinSize = Vector2.new(0, 0)
		frameSizeConstraint.MaxSize = Vector2.new(320, timerH)
		frameSizeConstraint.MinSize = Vector2.new(150, timerH)
		labelTextConstraint.MinTextSize = 10
		labelTextConstraint.MaxTextSize = math.max(11, math.floor(20 * sc + 0.5))
	end
	applyTopScale()
	Camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyTopScale)
end

-- ─────────────────────────────────────────────────────────────
-- 표시 갱신
-- ─────────────────────────────────────────────────────────────
-- 테마별 카운트다운 라벨 (이모지는 utf8.char로 인코딩 안전하게 생성)
local THEME_LABEL = {
    water = utf8.char(0x1F30A) .. " Tsunami",
    lava = utf8.char(0x1F525) .. " Firewall",
}
local currentLabel = THEME_LABEL.lava  -- 서버 tick에서 테마 받아 갱신

local function updateUI(remaining)
    buildUI()
    gui.Enabled = true

    label.Text = string.format("%s in %ds", currentLabel, remaining)

    -- 진행 바: 남은 시간이 적을수록 짧아짐
    local progress = math.clamp(remaining / totalDuration, 0, 1)
    fillBar.Size = UDim2.new(progress, 0, 1, 0)

    -- 마지막 3초는 빨간색 + 깜박임 강조
    if remaining <= 3 then
        local stroke = frame:FindFirstChild("Stroke")
        if stroke then stroke.Color = Color3.fromRGB(255, 60, 60) end
        fillBar.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
        label.TextColor3 = Color3.fromRGB(255, 200, 200)

        -- 깜박임 효과 (TweenService로 배경 투명도 변동)
        local pulseTween = TweenService:Create(
            frame,
            TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true),
            { BackgroundTransparency = 0.05 }
        )
        pulseTween:Play()
    else
        local stroke = frame:FindFirstChild("Stroke")
        if stroke then stroke.Color = Color3.fromRGB(255, 130, 60) end
        fillBar.BackgroundColor3 = Color3.fromRGB(255, 130, 60)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

local function showStarted()
    if not gui then return end
    -- 발생 순간 강한 강조
    label.Text = currentLabel .. " incoming!"
    label.TextColor3 = Color3.fromRGB(255, 220, 100)
    fillBar.Size = UDim2.new(0, 0, 1, 0)

    -- 1초 후 자동 숨김
    task.delay(1.5, function()
        if gui then gui.Enabled = false end
    end)
end

local function hideUI()
    if gui then gui.Enabled = false end
end

-- ─────────────────────────────────────────────────────────────
-- 서버 이벤트 처리
-- ─────────────────────────────────────────────────────────────
countdownEvent.OnClientEvent:Connect(function(eventType, value, themeName)
    if themeName then currentLabel = THEME_LABEL[themeName] or currentLabel end
    if eventType == "tick" then
        -- 첫 tick에서 totalDuration 자동 보정 (서버 DELAY 변경 대응)
        if value > totalDuration then
            totalDuration = value
        end
        updateUI(value)
    elseif eventType == "started" then
        showStarted()
    elseif eventType == "clear" then
        hideUI()
    end
end)

-- 캐릭터 재생성 시 UI 정리
localPlayer.CharacterAdded:Connect(function()
    hideUI()
end)

print("✅ FirePressureCountdownClient 활성화")
