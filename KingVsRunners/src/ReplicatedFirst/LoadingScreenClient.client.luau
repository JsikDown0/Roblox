-- LoadingScreenClient — 커스텀 로딩화면 (ReplicatedFirst: 접속 즉시 실행)
-- 구조: 기본 로딩화면 제거 → 로고+진행바+팁 표시 → (프리로드 완료 or 상한시간) 후 페이드아웃
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local LOGO_ID = "rbxassetid://134961557718458"
local MIN_TIME = 3        -- 최소 표시 (너무 빨리 닫히면 깜빡임처럼 보임)
local MAX_TIME = 30       -- 상한 (스킵 버튼 있으니 길게 가려줌)
local SKIP_AFTER = 3      -- 스킵 버튼 등장 시점
local STABLE_NEED = 3     -- 인스턴스 수가 이만큼(초) 안정되면 "스트리밍 정착"으로 판정
local TIPS = {
	"Runners can dash with Q — perfect for dodging the KING's items!",
	"Reach Stage 2 to unlock weapons and fight back!",
	"Hold E next to a downed teammate to revive them.",
	"Downed? Press Q to send an SOS to your team.",
	"Complete daily quests to earn coins and skin boxes.",
	"The KING rolls items downhill — keep moving!",
	"Watch the fire wall — stay ahead or get burned!",
	"Open skin boxes in the shop for rare weapon skins.",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [측정] 로딩화면 표시 시각 기록 (TEST ONLY: 릴리스 전 제거 가능)
local _probeT0 = os.clock()
print(string.format("[JoinProbe] 로딩화면 표시 시작 | %s", os.date("%X")))

-- ── UI 구성 ──────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ResetOnSpawn = false
gui.Parent = playerGui

-- ── 진입 사운드 (게임 첫 진입 = 로딩화면 표시 시점에 1회 재생) ──
-- 체감 음량은 단순 Volume 증폭보다 컴프레서(다이내믹 축소 + 메이크업 게인)가 효과적.
local SoundService = game:GetService("SoundService")
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "LoadingSfxGroup"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService

local comp = Instance.new("CompressorSoundEffect")   -- 작은 소리를 끌어올려 평균 음량 상승
comp.Threshold = -25
comp.Ratio = 6
comp.Attack = 0.01
comp.Release = 0.15
comp.GainMakeup = 12          -- dB 부스트
comp.Parent = sfxGroup

local eq = Instance.new("EqualizerSoundEffect")      -- 중음 강조 = 스피커에서 더 또렷하게
eq.LowGain = -4
eq.MidGain = 6
eq.HighGain = 2
eq.Parent = sfxGroup

local bgm = Instance.new("Sound")
bgm.Name = "LoadingEnterSfx"
bgm.SoundId = "rbxassetid://98973737803323"
bgm.Looped = false
-- 🔉 [하향 2026-09-09] 2.1 → 1.0. 너무 컸다(사용자 판단).
--   [왜 컸나] 증폭이 세 겹으로 중복돼 있었다:
--     Volume 2.1 (원래 0.7의 3배) × GainMakeup 12dB (약 4배) × MidGain 6dB
--     실효 약 12배. 주석은 "단순 Volume 증폭보다 컴프레서가 효과적"이라며
--     컴프레서를 넣었는데, 정작 Volume 도 3배로 같이 올려둔 상태였다.
--   [왜 Volume 만 내리나] 컴프레서·EQ 가 원래 의도(작은 소리를 끌어올려 또렷하게)다.
--     나중에 덧댄 Volume 증폭만 걷어내면 설계한 형태로 돌아간다. 실효 약 2.4배.
--   ⚠️ 더 줄여야 하면 GainMakeup(12) 을 6~8 로. 컴프레서를 끄지는 말 것 —
--     끄면 다이내믹이 살아나 조용한 구간이 안 들린다.
--   ⚠️ 되돌릴 값: 2.1
bgm.Volume = 1.0
bgm.SoundGroup = sfxGroup
bgm.Parent = SoundService
task.delay(1.5, function()
    if bgm and bgm.Parent then bgm:Play() end
end)
bgm.Ended:Connect(function()
    bgm:Destroy()
    sfxGroup:Destroy()
end)

local bg = Instance.new("Frame")
bg.Name = "BG"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(10, 14, 32)   -- 짙은 남색
bg.BorderSizePixel = 0
bg.Parent = gui

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 22, 48)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 11, 26)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 6, 16)),
})
grad.Rotation = 65
grad.Parent = bg

local logo = Instance.new("ImageLabel")
logo.Name = "Logo"
logo.BackgroundTransparency = 1
logo.Image = LOGO_ID
logo.ScaleType = Enum.ScaleType.Fit
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.42)
logo.Size = UDim2.fromScale(0.34, 0.4)
logo.Rotation = -2          -- 원본 로고의 미세 기울기 보정
logo.Parent = bg

-- 로고 은은한 펄스
task.spawn(function()
	while gui.Parent do
		local t1 = TweenService:Create(logo, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = UDim2.fromScale(0.36, 0.42)})
		t1:Play(); t1.Completed:Wait()
		if not gui.Parent then break end
		local t2 = TweenService:Create(logo, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = UDim2.fromScale(0.34, 0.4)})
		t2:Play(); t2.Completed:Wait()
	end
end)

-- 진행바 (골드)
local barBack = Instance.new("Frame")
barBack.Name = "BarBack"
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.72)
barBack.Size = UDim2.new(0.3, 0, 0, 10)
barBack.BackgroundColor3 = Color3.fromRGB(30, 36, 60)
barBack.BorderSizePixel = 0
barBack.Parent = bg
local backCorner = Instance.new("UICorner"); backCorner.CornerRadius = UDim.new(1, 0); backCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(240, 190, 40)   -- 골드
barFill.BorderSizePixel = 0
barFill.Parent = barBack
local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(1, 0); fillCorner.Parent = barFill

local pctLabel = Instance.new("TextLabel")
pctLabel.Name = "Pct"
pctLabel.BackgroundTransparency = 1
pctLabel.AnchorPoint = Vector2.new(0.5, 0)
pctLabel.Position = UDim2.new(0.5, 0, 0.72, 12)
pctLabel.Size = UDim2.new(0.3, 0, 0, 22)
pctLabel.Font = Enum.Font.GothamBold
pctLabel.TextSize = 16
pctLabel.TextColor3 = Color3.fromRGB(200, 205, 225)
pctLabel.Text = "Loading... 0%"
pctLabel.Parent = bg

-- 하단 팁
local tipLabel = Instance.new("TextLabel")
tipLabel.Name = "Tip"
tipLabel.BackgroundTransparency = 1
tipLabel.AnchorPoint = Vector2.new(0.5, 1)
tipLabel.Position = UDim2.new(0.5, 0, 1, -36)
tipLabel.Size = UDim2.new(0.62, 0, 0, 30)
tipLabel.Font = Enum.Font.GothamMedium
tipLabel.TextSize = 18
tipLabel.TextColor3 = Color3.fromRGB(235, 238, 250)
tipLabel.TextStrokeTransparency = 0.7
tipLabel.Text = ""
tipLabel.Parent = bg

task.spawn(function()
	local idx = math.random(1, #TIPS)
	while gui.Parent do
		tipLabel.Text = "Tip — " .. TIPS[idx]
		idx = (idx % #TIPS) + 1
		task.wait(4)
	end
end)

-- 스킵 버튼 (SKIP_AFTER 후 등장, 터치/클릭)
local skipRequested = false
local skipBtn = Instance.new("TextButton")
skipBtn.Name = "SkipBtn"
skipBtn.AnchorPoint = Vector2.new(1, 0.5)
skipBtn.Position = UDim2.new(1, -24, 0.72, 0)
skipBtn.Size = UDim2.new(0, 120, 0, 40)
skipBtn.BackgroundColor3 = Color3.fromRGB(30, 36, 60)
skipBtn.BackgroundTransparency = 0.25
skipBtn.BorderSizePixel = 0
skipBtn.Font = Enum.Font.GothamBold
skipBtn.TextSize = 17
skipBtn.TextColor3 = Color3.fromRGB(235, 238, 250)
skipBtn.Text = "SKIP >>"
skipBtn.Visible = false
skipBtn.Parent = bg
local skipCorner = Instance.new("UICorner"); skipCorner.CornerRadius = UDim.new(0, 8); skipCorner.Parent = skipBtn
local skipStroke = Instance.new("UIStroke"); skipStroke.Color = Color3.fromRGB(90, 100, 140); skipStroke.Thickness = 1; skipStroke.Parent = skipBtn
skipBtn.Activated:Connect(function() skipRequested = true end)
task.delay(SKIP_AFTER, function()
	if gui.Parent then skipBtn.Visible = true end
end)

-- ── 진행률 = 실제 개방 조건 3단계의 가중 합 (바 100% ≈ 화면 개방) ──
local ContentProvider = game:GetService("ContentProvider")
local W_PRELOAD, W_QUEUE, W_STABLE = 0.55, 0.15, 0.30
local stableFor = 0          -- 아래 대기 루프가 갱신 (0~STABLE_NEED)
local queuePeak = 0          -- 큐 최대치 기준으로 소진율 계산
local shown = 0
local hb
hb = RunService.Heartbeat:Connect(function(dt)
	-- ① 에셋 프리로드
	local pPre = ReplicatedStorage:GetAttribute("PreloadProgress") or 0
	if ReplicatedStorage:GetAttribute("PreloadDone") then pPre = 1 end

	-- ② 요청 큐 소진율
	local q = ContentProvider.RequestQueueSize
	if q > queuePeak then queuePeak = q end
	local pQueue = (queuePeak > 0) and math.clamp(1 - q / queuePeak, 0, 1) or 1

	-- ③ 스트리밍 안정화 (시간 비례)
	local pStable = math.clamp(stableFor / STABLE_NEED, 0, 1)

	local target = 0.05 + 0.95 * (pPre * W_PRELOAD + pQueue * W_QUEUE + pStable * W_STABLE)
	target = math.min(target, 0.99)   -- 100%는 실제 개방 순간에만
	shown = math.max(shown, shown + (target - shown) * math.min(dt * 3, 1))  -- 단조 증가
	barFill.Size = UDim2.fromScale(shown, 1)
	pctLabel.Text = string.format("Loading... %d%%", math.floor(shown * 100))
end)

-- ── 종료 조건 3중 구조 ──
-- ① 준비 완료 자동 감지: 프리로드 완료 + 에셋 큐 소진 + 인스턴스 수 STABLE_NEED초 안정
-- ② 스킵 버튼
-- ③ 상한 MAX_TIME
local t0 = os.clock()
if not game:IsLoaded() then game.Loaded:Wait() end

local lastCount = -1
local lastSample = 0
while os.clock() - t0 < MAX_TIME do
	local elapsed = os.clock() - t0
	if skipRequested and elapsed >= 1 then break end
	if elapsed >= MIN_TIME and ReplicatedStorage:GetAttribute("PreloadDone") then
		-- 1초마다 스트리밍 정착 샘플링
		if elapsed - lastSample >= 1 then
			lastSample = elapsed
			local count = #workspace:GetDescendants()
			if lastCount >= 0 and math.abs(count - lastCount) <= 5 then
				stableFor = stableFor + 1
			else
				stableFor = 0
			end
			lastCount = count
		end
		if ContentProvider.RequestQueueSize <= 0 and stableFor >= STABLE_NEED then
			break   -- 준비 완료: 상한 전 조기 개방
		end
	end
	task.wait(0.15)
end

-- 바를 100%로 마무리 후 페이드아웃
if hb then hb:Disconnect() end
barFill.Size = UDim2.fromScale(1, 1)
pctLabel.Text = "Loading... 100%"

-- [측정] 개방 시각·사유 기록
print(string.format("[JoinProbe] 로딩화면 종료 | 표시시간 %.1fs | 사유=%s | Role=%s | %s",
	os.clock() - _probeT0,
	skipRequested and "SKIP" or ((os.clock() - t0 >= MAX_TIME) and "상한도달" or "준비완료"),
	tostring(player:GetAttribute("Role")),
	os.date("%X")))

task.wait(0.25)

local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(bg, fadeInfo, {BackgroundTransparency = 1}):Play()
TweenService:Create(logo, fadeInfo, {ImageTransparency = 1}):Play()
TweenService:Create(barBack, fadeInfo, {BackgroundTransparency = 1}):Play()
TweenService:Create(barFill, fadeInfo, {BackgroundTransparency = 1}):Play()
TweenService:Create(pctLabel, fadeInfo, {TextTransparency = 1}):Play()
skipBtn.Visible = false
local lastTween = TweenService:Create(tipLabel, fadeInfo, {TextTransparency = 1})
lastTween:Play()
lastTween.Completed:Wait()
gui:Destroy()
