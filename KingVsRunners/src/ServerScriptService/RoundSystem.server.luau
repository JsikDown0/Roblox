-- 서바이벌 라운드 시스템 (승리 조건 포함)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- 시즌 리더보드. ModuleScript는 require 되기 전엔 실행되지 않으므로 여기서 명시적으로 로드한다
-- (_G 등록도 이 require 시점에 일어남). 실패해도 라운드 진행은 계속되어야 하므로 pcall.
local LeaderboardService
do
    local ok, result = pcall(function()
        return require(script.Parent:WaitForChild("LeaderboardService", 10))
    end)
    if ok then
        LeaderboardService = result
    else
        warn("[RoundSystem] LeaderboardService 로드 실패 — 리더보드 기록 비활성:", result)
    end
end

-- 설정
-- ⚠️ [밸런스 2026-08-25] 180 → 120.
--    실측: 오늘 로그에서 180초를 채운 라운드가 한 판도 없었다.
--    (23초 전멸 / 30초 킹처치 / 79초 킹처치 / 44초 void — 최장 79초)
--    이론값도 1단계 50~60초 + 2단계 30~50초 = 90~110초.
--    시간 초과가 러너 승리이므로, 180초는 '버티면 이긴다'를 너무 관대하게 만든다.
--    ⚠️ 멀티에서는 킹 HP 가 100×러너수 라 결투가 길어진다. 8명이면 HP 800.
--       그 판을 돌려보고 부족하면 140~150 으로 올릴 것.
--
-- ⚠️ [밸런스 2026-08-26] 120 → 150. 위 예고대로 올린다.
--    [왜] 2단계 목표 길이를 60~90초로 정했는데, 2단계는 러너가 발판에
--    도달해야 시작되므로 실제 가용 창 = ROUND_TIME − 1단계 길이다.
--    실측 1단계는 37.6 / 37.9 / 52.1초 → 가용 창이 68~82초뿐이었다.
--    상한 90초가 물리적으로 불가능했고, 시간 초과 = 태거 승리라
--    "러너가 점령할 시간이 없어서 태거가 이긴다" 가 기본값이 된다.
--    150 이면 창이 98~112초가 되어 60~90 이 안쪽에 들어온다.
--    ⚠️ 늘어난 30초는 전부 2단계 시간이다. 불기둥은 2단계 진입 시
--    계단 앞에서 멈추므로(Stage2TriggerSystem) 1단계 압박에는 영향 없다.
local ROUND_TIME = 150
local INTERMISSION_TIME = 15

-- 맵과 스폰 포인트
local map1 = workspace:WaitForChild("map1")
local map2 = workspace:WaitForChild("map2")

local maps = {
    {
        folder = map1,
        name = "MAP 1",
        taggerSpawn = map1:WaitForChild("taggerspawn"),
        playerSpawn = map1:WaitForChild("playerspawn"),
        -- 유저 러너 스폰 후보들 (라운드 시작 시 이 중 랜덤으로 분산 스폰).
        -- playerSpawn(단수)은 AI 봇 스폰 기준점으로 계속 사용됨.
        playerSpawns = {
            map1:WaitForChild("playerspawn"),
            map1:WaitForChild("playerspawn2"),
            map1:WaitForChild("playerspawn3"),
        }
    },
    -- MAP 2 활성화
    
    {
        folder = map2,
        name = "MAP 2",
        taggerSpawn = map2:WaitForChild("taggerspawn2"),
        playerSpawn = map2:WaitForChild("playerspawn2"),
        playerSpawns = {
            map2:WaitForChild("playerspawn"),
            map2:WaitForChild("playerspawn2"),
            map2:WaitForChild("playerspawn3"),
        }
    }
    
}

local lobbySpawn = workspace:WaitForChild("Floating Lobby"):WaitForChild("SpawnLocation")

-- 맵 설정 이벤트
local setMapEvent = ReplicatedStorage:FindFirstChild("SetCurrentMap")

-- 🏆 승패 감상 화면 신호
-- ⚠️ [2026-08-26] 부팅 시점에 만든다.
--   [증상] 콘솔에 매 접속마다 `Infinite yield possible on
--     'ReplicatedStorage:WaitForChild("VictoryScreenEvent")'` (VictoryScreenClient:427).
--   [원인] 이 RemoteEvent 를 endRound 안에서 lazy 생성하고 있었다.
--     서버가 첫 라운드를 끝내기 전까지는 객체 자체가 없어서, 그전에 들어온
--     클라의 WaitForChild 가 무한 대기에 걸린다 — 첫 판 결과창이 통째로 안 뜨는 경로.
--   [해결] 선언을 부팅부로 올린다. endRound 쪽 FindFirstChild 폴백은 그대로 두되
--     이제는 항상 여기서 만든 걸 찾게 된다.
do
    local vsEvent = ReplicatedStorage:FindFirstChild("VictoryScreenEvent")
    if not vsEvent then
        vsEvent = Instance.new("RemoteEvent")
        vsEvent.Name = "VictoryScreenEvent"
        vsEvent.Parent = ReplicatedStorage
    end
end

-- 게임 상태
local currentTagger = nil
local currentRunners = {}
local npcRunners = {} -- NPC 러너 (테스트용 Noob 등)
-- AI 러너(농민 봇): 라운드에 편입되지만 승패 카운트/승리 귀속에서는 분리됨.
-- 동료(압박·총알받이) 역할만 하고, 태거 처치·생존 판정은 실제 유저 러너만 담당.
local aiRunners = {} -- { [model] = true } 정식 편입 AI 러너 목록
local noobOriginalCFrame = nil -- Noob 원래 위치 저장
-- 리더보드 자격 판정용: 라운드 시작 시점의 "유저" 러너 실인원 스냅샷 (AI 제외).
-- endRound 시점엔 사망·퇴장으로 currentRunners가 줄어들 수 있어 시작값을 따로 보관한다.
local roundUserRunnerCount = 0
local roundActive = false
-- 🛡️ [2026-09-05] AI 러너 중 내구도를 받은 수. spawnAIRunner 가 올리고,
--   스폰 직전에 0 으로 리셋한 뒤 스폰 로그에서 'N/M' 으로 출력한다.
local aiDurabilityGranted = 0
-- 🔒 [2026-09-04] 이 라운드가 이미 종료 처리됐는가. endRound 재진입 가드.
--   ⚠️ 반드시 라운드 시작에서 false 로 되돌릴 것. 안 하면 첫 라운드 뒤로 영영 안 끝난다.
local roundEnded = false
-- 🔒 [2026-09-04] 승패는 정해졌으나 연출 대기 중인 상태. lockRoundResult 가 채운다.
--   ⚠️ roundEnded 와 함께 라운드 시작에서 반드시 nil 로 되돌릴 것.
local pendingResult = nil
local roundPaused = false
_G.PauseRound  = function() roundPaused = true  print("⏸️ 라운드 일시정지") end
_G.ResumeRound = function() roundPaused = false print("▶️ 라운드 재개")     end
_G.IsRoundPaused = function() return roundPaused end

-- ─ NPC 러너 비주얼 헬퍼 ────────────────────────────────────
-- 주어진 NPC 모델에 RunnerProfile (NPC 라벨) 과 RunnerBeam (흰색 광선기둥) 을 생성.
-- 이미 존재하면 destroy 후 재생성.
-- 라운드 시작 외(예: /itemtest 테스트 환경)에서도 NPC를 러너처럼 보이게 하기 위함.
local function setupNpcRunnerVisuals(model)
	if not model then return end
	local head = model:FindFirstChild("Head")
	if not head then return end

	-- 기존 비주얼 제거 (idempotent)
	local existingProfile = head:FindFirstChild("RunnerProfile")
	if existingProfile then existingProfile:Destroy() end
	local existingBeam = head:FindFirstChild("RunnerBeam")
	if existingBeam then existingBeam:Destroy() end
	local existingHL = model:FindFirstChild("RunnerHighlight")
	if existingHL then existingHL:Destroy() end

	-- Profile (BillboardGui, 노란 원 + 'NPC' 텍스트)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RunnerProfile"
	billboard.Size = UDim2.new(10, 0, 10, 0)
	billboard.StudsOffset = Vector3.new(0, 52, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 2000
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
	frame.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "NPC"
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = frame
	billboard.Parent = head

	-- 빛기둥 대체: 빨강 UI 선 (BillboardGui)
	-- Beam은 낮은 그래픽에서 원거리 컬링으로 사라지므로, 그래픽 무관하게 보이는
	-- BillboardGui 세로 막대로 대체. Size를 stud(fromScale)로 줘 "고정 월드 길이"가 됨.
	local PILLAR_HEIGHT = 50   -- 기둥 높이(stud) — 기존 Beam(att1 y=50)과 동일
	local PILLAR_WIDTH  = 1.2  -- 기둥 폭(stud)
	local beamGui = Instance.new("BillboardGui")
	beamGui.Name = "RunnerBeam"   -- 기존 청소 로직과 이름 호환
	beamGui.Adornee = head
	beamGui.AlwaysOnTop = true
	beamGui.MaxDistance = 2000
	beamGui.LightInfluence = 0
	beamGui.Size = UDim2.fromScale(PILLAR_WIDTH, PILLAR_HEIGHT)
	-- 기둥이 머리에서 위로 솟도록 절반 높이만큼 위로 오프셋
	beamGui.StudsOffset = Vector3.new(0, PILLAR_HEIGHT / 2, 0)
	beamGui.Parent = head

	local pillar = Instance.new("Frame")
	pillar.Size = UDim2.fromScale(1, 1)
	pillar.BackgroundColor3 = Color3.fromRGB(255, 40, 40)  -- 빨강
	pillar.BackgroundTransparency = 0.15
	pillar.BorderSizePixel = 0
	pillar.Parent = beamGui
	-- 위로 갈수록 옅어지는 그라데이션(빛기둥 느낌)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	grad.Parent = pillar
	local pstroke = Instance.new("UIStroke")
	pstroke.Color = Color3.fromRGB(120, 0, 0)
	pstroke.Thickness = 1
	pstroke.Transparency = 0.4
	pstroke.Parent = pillar
end
_G.setupNpcRunnerVisuals = setupNpcRunnerVisuals

-- 캐릭터 스케일 정규화 (히트박스 통일)
local function normalizeAllPlayers(players)
    print("🔧 캐릭터 스케일 정규화 시작...")
    for _, player in ipairs(players) do
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                -- 스케일 강제 통일
                local scaleNames = {"BodyDepthScale", "BodyWidthScale", "BodyHeightScale", "HeadScale"}
                for _, scaleName in ipairs(scaleNames) do
                    local scale = humanoid:FindFirstChild(scaleName)
                    if scale then
                        scale.Value = 1
                    end
                end
                
                -- 투명한 파츠 수정 (악용 방지)
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.Transparency > 0.5 then
                        if part.Name ~= "HumanoidRootPart" then
                            part.Transparency = 0.3
                        end
                    end
                end
                
                print("  ✅", player.Name, "스케일 정규화 완료")
            end
        end
    end
    print("🔧 캐릭터 스케일 정규화 완료!")
end



print("=== 라운드 시스템 시작 ===")

-- ── 음악용 라운드 페이즈 브로드캐스트 ───────────────────────────
-- 클라이언트 MusicClient가 이 신호로 BGM을 전환함.
-- phase: "intermission" | "stage1"  (stage2는 Stage2Started 이벤트 사용)
local roundPhaseEvent = ReplicatedStorage:FindFirstChild("RoundPhaseEvent")
local function broadcastPhase(phase)
    -- 이벤트만으로는 부족하다. HUD 등 ResetOnSpawn=true 인 UI 는 리스폰마다
    -- 스크립트가 재시작돼, 이미 지나간 FireAllClients 를 영영 받지 못한다.
    -- 라운드 시작 시 텔레포트로 리스폰이 발생하므로 매 라운드 이 경합이 생긴다.
    -- 실측(2026-08): ROUND START 0.4초 뒤 HudButtonClient 가 재시작되어
    --   phase 가 intermission 으로 굳고 라운드 중에도 HUD 가 안 숨겨졌다.
    -- → 조회 가능한 상태로도 남겨 새로 뜬 스크립트가 현재 단계를 읽게 한다.
    ReplicatedStorage:SetAttribute("RoundPhase", phase)
    if roundPhaseEvent then
        -- phase와 함께 "이 단계 곡이 시작된 서버 시각"을 전달
        -- → 관전자가 곡의 현재 시간대(TimePosition)부터 들을 수 있음
        roundPhaseEvent:FireAllClients(phase, os.time())
    end
end

-- UI 생성 함수
local function createTimerUI(player)
    local playerGui = player:WaitForChild("PlayerGui")
    
    local oldUI = playerGui:FindFirstChild("GameUI")
    if oldUI then
        oldUI:Destroy()
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "GameUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = -10  -- TaggerItemUI(100)보다 낮게 설정
    -- 상단 가장자리까지 사용 (TimerFrame이 진짜 상단에 붙도록)
    pcall(function() screenGui.ScreenInsets = Enum.ScreenInsets.None end)
    
    -- 타이머 프레임 (작은 상단 배지 스타일, 모바일 친화적)
    local timerFrame = Instance.new("Frame")
    timerFrame.Name = "TimerFrame"
    timerFrame.AnchorPoint = Vector2.new(0.5, 0)
    timerFrame.Size = UDim2.new(0.22, 0, 0, 44)
    timerFrame.Position = UDim2.new(0.5, 0, 0, 8)
    timerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    timerFrame.BackgroundTransparency = 0.3
    timerFrame.BorderSizePixel = 0
    timerFrame.Parent = screenGui

    -- 사이즈 캡: PC 에서 너무 크지 않게, 모바일에서 너무 작지 않게
    local timerSizeConstraint = Instance.new("UISizeConstraint")
    timerSizeConstraint.MaxSize = Vector2.new(320, 44)
    timerSizeConstraint.MinSize = Vector2.new(180, 36)
    timerSizeConstraint.Parent = timerFrame

    local timerCorner = Instance.new("UICorner")
    timerCorner.CornerRadius = UDim.new(0, 12)
    timerCorner.Parent = timerFrame

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Size = UDim2.new(1, -16, 1, 0)
    timerLabel.Position = UDim2.new(0, 8, 0, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerLabel.TextScaled = true
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Text = "Preparing..."
    timerLabel.TextStrokeTransparency = 0.5
    timerLabel.Parent = timerFrame

    -- 텍스트 사이즈 캡 (TextScaled 의 상한/하한)
    local timerTextConstraint = Instance.new("UITextSizeConstraint")
    timerTextConstraint.MaxTextSize = 22
    timerTextConstraint.MinTextSize = 12
    timerTextConstraint.Parent = timerLabel
    
    -- 슬롯 프레임 (원본 픽셀 사이즈 + UIScale 로 모바일 적응)
    -- ⚠️ 킹 선정 발표는 "가장 앞"이어야 한다. screenGui 는 DisplayOrder = -10 인데
    --    (라운드 타이머가 TaggerItemUI 위로 튀지 않게 한 의도적 값), 발표 모달까지
    --    그 아래로 깔려 배틀패스 바·솔로 역할 패널이 발표를 덮었다(실측).
    --    → 발표만 별도 ScreenGui(DisplayOrder 200)로 분리한다. 타이머는 기존대로 유지.
    local announceGui = playerGui:FindFirstChild("GameAnnounceUI")
    if announceGui then announceGui:Destroy() end
    announceGui = Instance.new("ScreenGui")
    announceGui.Name = "GameAnnounceUI"
    announceGui.ResetOnSpawn = false
    announceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    announceGui.DisplayOrder = 200   -- TaggerItemUI(100)·BattlePass(60)보다 위
    announceGui.IgnoreGuiInset = true
    announceGui.Parent = playerGui

    local slotFrame = Instance.new("Frame")
    slotFrame.Name = "SlotFrame"
    slotFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    slotFrame.Size = UDim2.new(0, 500, 0, 400)
    slotFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    slotFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    slotFrame.BackgroundTransparency = 0.1
    slotFrame.BorderSizePixel = 0
    slotFrame.Visible = false
    slotFrame.Parent = announceGui

    -- UIScale 부착 (GameUIScaler LocalScript 가 ViewportSize 에 따라 자동 업데이트)
    local slotScale = Instance.new("UIScale")
    slotScale.Name = "SlotScale"
    slotScale.Scale = 1
    slotScale.Parent = slotFrame
    
    local slotCorner = Instance.new("UICorner")
    slotCorner.CornerRadius = UDim.new(0, 16)
    slotCorner.Parent = slotFrame
    
    local slotTitle = Instance.new("TextLabel")
    slotTitle.Name = "Title"
    slotTitle.Size = UDim2.new(1, 0, 0, 60)
    slotTitle.Position = UDim2.new(0, 0, 0, 20)
    slotTitle.BackgroundTransparency = 1
    slotTitle.TextColor3 = Color3.fromRGB(255, 255, 100)
    slotTitle.TextSize = 36
    slotTitle.Font = Enum.Font.GothamBold
    slotTitle.Text = "SELECTING..."
    slotTitle.Parent = slotFrame

    local kingChance = Instance.new("TextLabel")
    kingChance.Name = "KingChance"
    kingChance.Size = UDim2.new(1, 0, 0, 26)
    kingChance.Position = UDim2.new(0, 0, 0, 74)
    kingChance.BackgroundTransparency = 1
    kingChance.TextColor3 = Color3.fromRGB(255, 220, 120)
    kingChance.TextSize = 20
    kingChance.Font = Enum.Font.GothamMedium
    kingChance.Text = ""
    kingChance.Visible = false
    kingChance.Parent = slotFrame
    
    local displayContainer = Instance.new("Frame")
    displayContainer.Name = "DisplayContainer"
    displayContainer.Size = UDim2.new(0.8, 0, 0, 220)
    displayContainer.Position = UDim2.new(0.1, 0, 0, 100)
    displayContainer.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    displayContainer.BorderSizePixel = 0
    displayContainer.BackgroundTransparency = 1
    displayContainer.Parent = slotFrame
    
    local containerCorner = Instance.new("UICorner")
    containerCorner.CornerRadius = UDim.new(0, 12)
    containerCorner.Parent = displayContainer
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "TextLabel"
    textLabel.Size = UDim2.new(1, 0, 0, 80)
    textLabel.Position = UDim2.new(0, 0, 0, 15)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    textLabel.TextSize = 48
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Text = "???"
    textLabel.Parent = displayContainer
    
    local avatarImage = Instance.new("ImageLabel")
    avatarImage.Name = "Avatar"
    avatarImage.Size = UDim2.new(0, 120, 0, 120)
    avatarImage.Position = UDim2.new(0.5, -60, 0, 95)
    avatarImage.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    avatarImage.BackgroundTransparency = 1
    avatarImage.BorderSizePixel = 0
    avatarImage.ScaleType = Enum.ScaleType.Fit
    avatarImage.Visible = false
    avatarImage.Parent = displayContainer
    
    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0)
    avatarCorner.Parent = avatarImage
    
    local resultLabel = Instance.new("TextLabel")
    resultLabel.Name = "Result"
    resultLabel.Size = UDim2.new(1, 0, 0, 50)
    resultLabel.Position = UDim2.new(0, 0, 1, -70)
    resultLabel.BackgroundTransparency = 1
    resultLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    resultLabel.TextSize = 28
    resultLabel.Font = Enum.Font.GothamBold
    resultLabel.Text = ""
    resultLabel.Parent = slotFrame
    
    screenGui.Parent = playerGui
    return screenGui
end

-- UI 업데이트 함수들

-- ⚠️ SlotFrame 은 GameAnnounceUI(DisplayOrder 200) 로 분리했다.
--    GameUI(-10) 안에 두면 배틀패스 바·솔로 역할 패널이 발표를 덮기 때문.
--    아래 헬퍼로 위치를 한 곳에서만 관리한다(경로가 흩어지면 또 깨진다).
local function getSlotFrame(player)
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("GameAnnounceUI") or pg:FindFirstChild("GameUI")
    return gui and gui:FindFirstChild("SlotFrame")
end
local function updateAllTimers(text, color)
    for _, player in ipairs(Players:GetPlayers()) do
        local gui = player:FindFirstChild("PlayerGui"):FindFirstChild("GameUI")
        if gui then
            local lbl = gui.TimerFrame.TimerLabel
            lbl.Text = text
            lbl.TextColor3 = color or Color3.fromRGB(255, 255, 255)
        end
    end
end

local function showSlotToAll(visible)
    for _, player in ipairs(Players:GetPlayers()) do
        local slot = getSlotFrame(player)
        if slot then
            slot.Visible = visible
            if not visible then
                local kc = slot:FindFirstChild("KingChance")
                if kc then kc.Visible = false end
            end
            -- TimerFrame은 SlotFrame과 반대로 토글
            -- (TimerFrame 은 여전히 GameUI 소속 — 분리한 것은 SlotFrame 뿐)
            local pg = player:FindFirstChild("PlayerGui")
            local gameUI = pg and pg:FindFirstChild("GameUI")
            local timerFrame = gameUI and gameUI:FindFirstChild("TimerFrame")
            if timerFrame then
                timerFrame.Visible = not visible
            end
        end
        
        -- SlotFrame 숨길 때 MapVoteGui 다시 활성화 (다음 투표 대비)
        if not visible then
            local playerGui = player:FindFirstChild("PlayerGui")
            if playerGui then
                local mapVoteGui = playerGui:FindFirstChild("MapVoteGui")
                if mapVoteGui then
                    mapVoteGui.Enabled = true
                end
            end
        end
    end
end

local function updateSlotDisplay(text, showAvatar, avatarUserId)
    for _, player in ipairs(Players:GetPlayers()) do
        local slot = getSlotFrame(player)
        if slot then
            local container = slot.DisplayContainer
            container.TextLabel.Text = text
            
            if showAvatar and avatarUserId then
                container.Avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. avatarUserId .. "&width=150&height=150&format=png"
                container.Avatar.Visible = true
            else
                container.Avatar.Visible = false
            end
        end
    end
end

local function updateSlotTitle(text)
    for _, player in ipairs(Players:GetPlayers()) do
        local slot = getSlotFrame(player)
        if slot then
            slot.Title.Text = text
        end
    end
end

local function updateSlotResult(text)
    for _, player in ipairs(Players:GetPlayers()) do
        local slot = getSlotFrame(player)
        if slot then
            slot.Result.Text = text
        end
    end
end

-- 태거 확률 표시: 각 플레이어에게 자기 확률(%)을 슬롯 KingChance 라벨에 명시
local function showSlotOddsToAll(odds)
    for _, player in ipairs(Players:GetPlayers()) do
        local pg = player:FindFirstChild("PlayerGui")
        -- ⚠️ SlotFrame 은 GameUI 가 아니라 GameAnnounceUI(DisplayOrder 200) 로 옮겼다.
        --    구버전 경로(GameUI)도 폴백으로 확인해 이전 세션 잔여 GUI 와 호환.
        local gui = pg and (pg:FindFirstChild("GameAnnounceUI") or pg:FindFirstChild("GameUI"))
        local slot = gui and gui:FindFirstChild("SlotFrame")
        local lbl = slot and slot:FindFirstChild("KingChance")
        if lbl then
            local pct = odds and odds[player.UserId]
            if pct then
                lbl.Text = string.format("Your King chance: %d%%", math.floor(pct + 0.5))
                lbl.Visible = true
            else
                lbl.Visible = false
            end
        end
    end
end

-- 맵 선택 슬롯
local function selectMapWithSlot()
    showSlotToAll(true)
    updateSlotTitle("🗺️ SELECTING MAP")
    updateSlotResult("")
    
    for i = 1, 20 do
        local randomMap = maps[math.random(1, #maps)]
        updateSlotDisplay(randomMap.name, false)
        wait(0.05 + (i * 0.01))
    end
    
    local chosenMap = maps[math.random(1, #maps)]
    
    for i = 1, 3 do
        updateSlotDisplay("★★★", false)
        wait(0.2)
        updateSlotDisplay(chosenMap.name, false)
        wait(0.2)
    end
    
    updateSlotResult("Selected: " .. chosenMap.name)
    wait(1)
    
    return chosenMap
end

-- ── 태거 왕관 (Tagger Crown) ──────────────────────────────
local CROWN_TEMPLATE = ServerStorage:FindFirstChild("Crown")
if not CROWN_TEMPLATE then
    warn("[RoundSystem] Crown 템플릿을 ServerStorage에서 찾을 수 없습니다")
end

-- 왕관 스킨 비주얼 (skinKey → 색/재질). EffectSystem CROWN_SKINS의 skinKey와 일치해야 함.
--   Neon  : 단색 네온 글로우(텍스처 제거) / Metal : 텍스처 유지 + 금속 반사(재질 변형) / Glass : 유리(크리스탈)
local CROWN_SKIN_VISUAL = {
    Gold     = { color = Color3.fromRGB(187, 159, 59),  material = Enum.Material.Neon },
    Crimson  = { color = Color3.fromRGB(200, 41, 36),   material = Enum.Material.Neon },
    Cyan     = { color = Color3.fromRGB(64, 191, 232),  material = Enum.Material.Neon },
    Emerald  = { color = Color3.fromRGB(27, 182, 100),  material = Enum.Material.Neon },
    Amethyst = { color = Color3.fromRGB(120, 40, 190),  material = Enum.Material.Neon },
    Rose     = { color = Color3.fromRGB(232, 86, 159),  material = Enum.Material.Neon },
    Royal    = { color = Color3.fromRGB(212, 185, 90),  material = Enum.Material.Metal, keepTexture = true, reflectance = 0.2 },
    Diamond  = { color = Color3.fromRGB(175, 222, 250), material = Enum.Material.Glass, reflectance = 0.35, transparency = 0.4 },
    Silver   = { color = Color3.fromRGB(205, 210, 218), material = Enum.Material.Metal, reflectance = 0.3 },
    Black    = { color = Color3.fromRGB(24, 24, 28),    material = Enum.Material.Metal, reflectance = 0.12 },
    White    = { color = Color3.fromRGB(244, 244, 248), material = Enum.Material.SmoothPlastic, reflectance = 0.08 },
    Rainbow  = { color = Color3.fromRGB(255, 80, 80),   material = Enum.Material.Neon, cycle = true },

    -- 모델 스킨 (고유 메시 — 색 변경 X, 자기 텍스처/이펙트 유지).
    --   model=CrownModels 템플릿명, headScale=메시 배율(네이티브×배수), headOffset=머리 기준 오프셋, headRot=회전 보정.
    --   ⚠ 메시마다 크기/원점이 달라 F5로 보면서 headOffset/headScale/headRot 튜닝 필요.
    Flower      = { model = "Flower",      headScale = 1.56, headOffset = Vector3.new(0, -3.2, 0),  headRot = CFrame.Angles(math.rad(90), 0, 0) },
    Money       = { model = "Money",       headScale = 1.2,  headOffset = Vector3.new(0, 2.2, 0),    headRot = CFrame.Angles(0, 0, 0) },
    DarkRainbow = { model = "DarkRainbow", headScale = 1.5,  headOffset = Vector3.new(0, 2.1, 0),    headRot = CFrame.Angles(0, 0, 0) },
    Void        = { model = "Void",        headScale = 1.5,  headOffset = Vector3.new(0, 2.3, 0),    headRot = CFrame.Angles(0, 0, 0) },
    EightBit    = { model = "EightBit",    headScale = 1.6,  headOffset = Vector3.new(0, 2.1, -0.15), headRot = CFrame.Angles(0, 0, 0) },
    Blackstar   = { model = "Blackstar",   headScale = 1.7,  headOffset = Vector3.new(0, 2.0, 0),    headRot = CFrame.Angles(0, 0, 0) },

    -- 엔젤: 날개+후광(halo)이 한 메시(AngelWings)라 별도 크라운 안 붙임(headless). 후광이 곧 크라운. /wn 으로 전체 위치·크기 조절.
    Angel        = { headless = true, wings = "AngelWings",        wingScale = 1.6, wingOffset = Vector3.new(0, 1.5, 0.1), wingRot = CFrame.Angles(0, 0, 0) },
    MagentaAngel = { headless = true, wings = "MagentaAngelWings", wingScale = 1.6, wingOffset = Vector3.new(0, 1.5, 0.1), wingRot = CFrame.Angles(0, 0, 0) },
}
local DEFAULT_CROWN_SKIN = "Gold"

local function removeCrownFromPlayer(player)
    if not player or not player.Character then return end
    -- TaggerCrown 컨테이너가 여러 개여도 전부 제거 (중복 방지)
    for _, c in ipairs(player.Character:GetChildren()) do
        if c.Name == "TaggerCrown" then c:Destroy() end
    end
end

-- ════════════════════════════════════════════════════════════════
-- AI 러너 (농민 봇) 동적 스폰
-- ────────────────────────────────────────────────────────────────
-- Famer2를 템플릿으로 복제. 유저 러너 수에 따라 부족분을 AI로 채움(최소 군중 보장).
-- AI는 승패 카운트/승리 귀속에서 분리(세션1). 이동·회피·근접은 RunnerBotDriveController가 구동.
-- 컨셉: 폭군에게 도전하는 농민 군중. 압박·총알받이 역할.
-- ════════════════════════════════════════════════════════════════
-- ⚠️ 실전 규모 반영: 라이브에선 러너 10명 이상을 상정하는데, 목표 총원이 6이라
--    솔로 테스트가 실전의 절반 규모였다. 태거가 연습하는 압박감이 실제와 달라진다.
--    농민봇은 체력이 낮고 서로 살리는 기능도 없어 수가 많아도 개별 위협은 작다
--    ("학살하는 재미" 쪽이 컨셉과도 맞음). 성능은 F5 실측으로 조정.
local AI_TARGET_TOTAL = 11  -- 목표 러너 총원(유저+AI). 이 수에서 유저 수를 뺀 만큼 AI 보충.
-- 👑 [③ 2026-09-12] 히어로봇 정원. 자세한 근거는 spawnAIRunner 의 [③ 계층 분리] 주석.
--   H = max(0, HERO_TARGET - 유저러너수). 유저가 늘면 히어로가 줄어 총원은 그대로.
--   ⚠️ 4 는 "2단계 창 98~112초 안에 킹 907 을 깎을 수 있는 최소 인원"에서 나온 값이다.
--     히어로가 웨폰을 든다는 전제가 깨지면(농민 DPS 1~2) 151초가 되어 창을 넘긴다.
local HERO_TARGET     = 4
-- 🗡️ 히어로 무기. ⚠️ Stage2TriggerSystem 의 HERO_WEAPON 과 같은 값이어야 한다.
--   [2026-09-12] DragonFireSword(평타 전용) → HammerLow(스핀 스킬).
--     평타 배선이 검증됐으므로 스킬 있는 무기로 옮긴다.
--   ⚠️ 실제 지급은 2단계 진입 시점이다(유저와 같은 규칙). 여기 값은 기록·참조용.
local HERO_WEAPON     = "HammerLow"
-- 🪶 히어로 외형 표식. 스폰 시 장착(1단계부터 보여야 킹이 읽는다).
--   ⚠️ ServerStorage.HeroHat 은 프리뷰에서 위치·각도를 수동 조절한 뒤 승격시킨 것이다.
--     원본 workspace.FeatherHat 은 Handle 이 없는 빈 껍데기였다(그래서 모자가 안 보였다).
local HERO_HAT        = "HeroHat"
local heroQuota       = 0   -- 이번 라운드 히어로 수. 스폰 루프에서 확정, spawnAIRunner 가 읽는다
local AI_MIN_CROWD    = 2   -- 유저가 많아도 최소 이만큼 AI 유지(군중감)
local AI_MAX          = 10  -- 성능 상한(모바일). 측정 후 조정.
local AI_LANE_GAP     = 6   -- AI 간 스폰 간격(stud, Z축 분산)

-- 복제본 정제: 무료모델(Jeff The Killer) 잔재 + 무기 Tool의 입력/카메라 스크립트 제거.
-- AI는 B안(간이 근접 판정)이라 Tool의 실제 작동이 불필요 → 외형(갈퀴 Handle)만 남김.
local function sanitizeAIClone(model)
    -- 충돌 NPC AI 스크립트 + 기본 회복(Health) 잔재
    local badNames = { TheRakeMain = true, Respawn = true, AnimateSauce = true,
                       ["Sit on touch Script"] = true, Health = true }
    -- 무기 Tool 내부의 클라 입력/카메라 스크립트 (서버 AI에선 에러만 유발)
    local toolScriptNames = {
        ClickTransmitter = true, PitchScript = true, ModifierScript = true,
        CameraTransmitter = true, CameraTransmitterReceiver = true,
        LocalScript = true, MouseIcon = true,
    }
    for _, d in ipairs(model:GetDescendants()) do
        if (d:IsA("Script") or d:IsA("LocalScript")) then
            if badNames[d.Name] or toolScriptNames[d.Name] then
                d:Destroy()
            end
        end
    end
    -- Humanoid 이름 정상화 (무료모델이 AngryFarmer 등으로 바꿔놓은 경우 대비)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Name ~= "Humanoid" then
        hum.Name = "Humanoid"
    end
end

-- AI 러너 1체 생성 (index로 레인 분산)
-- index: 전체 통산 번호(이름/식별용), laneSeq/laneTotal: "이 스폰 지점 안에서의" 순번과 총원.
-- 스폰 지점을 여러 곳으로 나눈 뒤에도 같은 지점 안에서만 레인 오프셋을 계산해야
-- 지점끼리 겹치거나 한쪽으로 쏠리지 않는다.
local function spawnAIRunner(template, spawnCFrame, index, laneSeq, laneTotal)    local clone = template:Clone()
    clone.Name = "AIRunner_" .. index
    sanitizeAIClone(clone)

    -- 식별 속성: AIRunner(승패 분리용) + RunnerBot(컨트롤러 인식용) + BotIndex
    clone:SetAttribute("AIRunner", true)
    clone:SetAttribute("RunnerBot", true)
    clone:SetAttribute("BotIndex", index)

    -- 👑 [③ 계층 분리 2026-09-12] 히어로봇 / 농민봇.
    --
    -- [왜] 봇 10~11마리가 전부 같은 역할이라 2단계에서 문제가 생긴다 —
    --   ① 유저가 적을수록 2단계 전력이 부족하다(솔로면 웨폰 든 러너가 0명)
    --   ② 승패는 이미 봇을 제외한다(checkRunners: "AI 러너는 동료/총알받이일 뿐")
    --   즉 봇은 이미 '환경'인데, 환경만으로는 2단계 HP 소모전이 성립하지 않는다.
    --
    -- [구조] 히어로 = 유저 대역(웨폰 보유·2단계 복귀·내구도) / 농민 = 개잡졸(점령 담당)
    --   H = max(0, HERO_TARGET - 유저러너수)
    --   유저가 늘면 히어로가 줄어 총원은 그대로 — 2단계 전력이 인원과 무관하게 일정하다.
    --
    -- [왜 4인가] 2단계 창 98~112초 안에 킹을 깎을 수 있어야 한다.
    --   킹 HP 907(솔로 기준, 150×6.05) ÷ (4마리 × 웨폰 DPS 9) ≈ 25초.
    --   웨폰 DPS 는 09-08 1대1 통제 실험(킹 975 고정, 8종 20판) 중앙값 8.5 에
    --   그 뒤 상향분을 얹은 값이다.
    --   ⚠️ 농민 봇 DPS(마리당 1~2)로 계산하면 151초가 나와 창을 넘긴다 —
    --     히어로가 '웨폰을 든다'는 전제가 이 값의 핵심이다. 웨폰 지급을 빼면 4는 틀린 값이 된다.
    --
    -- ⚠️ 승패 참여는 조건부다 — 유저 러너가 0명일 때만 대역으로 센다.
    --   항상 세면 "유저는 다 죽었는데 히어로봇이 살아서 판이 안 끝나는" 교착이 생긴다.
    --   checkRunners 주석이 막으려던 것이 정확히 그것이다.
    local isHero = (heroQuota and index <= heroQuota) or false
    clone:SetAttribute("HeroRunner", isHero or nil)

    -- 🗡️ [③ 웨폰 지급 2026-09-12] 히어로는 실제 러너 무기를 든다.
    --
    -- [왜 진짜 Tool 인가 — 선례] 봇 킹이 이미 진짜 PushTool 을 구동한다.
    --   PushTool.Server 의 beginCharge 안에 봇 분기가 있고(botChargeTrack),
    --   CHARGE_TIME·CHARGED_COOLDOWN·HIT_WINDOW 를 유저와 그대로 공유한다.
    --   차이는 연출 경로뿐이다 — 유저는 FireClient, 봇은 서버가 직접 재생.
    --   그 주석이 근거도 남겼다: "서버가 봇의 네트워크 소유자라 지속 제어가 먹는다".
    --   ⚠️ 간이 판정으로 흉내내면 같은 구조가 두 벌이 되고, 웨폰 상수를 고칠 때
    --     두 곳을 고쳐야 한다. 진짜 툴을 쓰면 밸런스 수정이 자동으로 따라온다.
    --
    -- [왜 DragonFireSword 로 시작하나]
    --   ① 평타 배선이 전체 작업의 대부분이다 — 스킬은 그 위에 얹는 한 줄
    --   ② DragonFire 는 F 스킬이 없어(OnServerEvent 핸들러 없음) 변수가 하나 적다
    --      → "안 되면 배선 탓" 이 확정된다. 스킬이 섞이면 원인 분리가 안 된다
    --   ③ Plyr 참조 8곳 / FireClient 1곳 / Player 속성 저장 0곳 — 후보 중 최소
    --   ⚠️ 다음은 HammerLow(스핀). 그때 '스킬 호출 + 쿨다운 저장소 이전' 둘만 새로 푼다.
    --
    -- ⚠️ sanitizeAIClone 은 이름 목록으로 지운다(LocalScript·MouseIcon 등).
    --   SwordScript 같은 서버 스크립트는 애초에 안 지우므로 예외 처리가 필요 없다.
    -- ⚠️ 무기는 sanitizeAIClone '뒤에' 넣는다. 먼저 넣으면 무기 안의 클라 스크립트까지
    --   훑어서 지워지는데, 그중엔 툴 동작에 필요한 것이 있을 수 있다.
    -- ⚠️ [2026-09-12] 무기는 여기서 주지 않는다 — 2단계 진입 시 지급한다.
    --   [왜] 1단계에 히어로만 무기를 들고 있으면 유저가 "쟤는 있는데 나는 왜 없지?"
    --     가 된다. 유저 러너도 2단계에 ClassicSword 를 받는다(Stage2TriggerSystem:911).
    --     같은 규칙이어야 규칙으로 읽힌다.
    --   [지금] 스폰 시에는 '히어로 표식'만 세운다. 지급은 Stage2TriggerSystem 담당.
    --   ⚠️ 갈퀴·자루·밀짚모자는 여기서 제거한다. 1단계부터 외형이 달라야
    --     킹이 판 시작에 "누가 히어로인지" 읽을 수 있다(KILL_ROUND_CHANCE 주석의 의도).
    if isHero then
        -- 갈퀴 Tool 제거
        for _, t in ipairs(clone:GetChildren()) do
            if t:IsA("Tool") then t:Destroy() end
        end
        -- 밀짚모자(구형 Hat 클래스) 제거
        for _, c in ipairs(clone:GetChildren()) do
            if c:IsA("Hat") or c:IsA("Accessory") then c:Destroy() end
        end
        -- 자루
        local la = clone:FindFirstChild("Left Arm")
        local bag = la and la:FindFirstChild("Bag")
        if bag then bag:Destroy() end
        local kn = clone:FindFirstChild("Knife")
        if kn then kn:Destroy() end

        -- 🪶 깃털 모자 + 대장장이 복장
        --
        -- ⚠️ [2026-09-12] Accessory 를 그냥 Parent 하면 안 붙는다.
        --   [원인] Famer2 는 R6 구형 리그라 Head 에 HatAttachment 가 없다.
        --     Accessory 자동 용접은 양쪽 Attachment 짝맞춤으로 도는데 짝이 없으니
        --     모자가 원점에 남는다(프리뷰에서 머리와 418 stud 떨어져 있었다).
        --   [해결] 짝맞춤을 버리고 머리 기준 상대 좌표로 직접 용접한다.
        --     "끌려오게 말고 직접 놓고 묶는다" — 지침의 부착 원칙.
        --   [값] 프리뷰에서 수동 조절한 결과를 실측해 가져온 것이다.
        --     위치 (0, 0.379, -0.033) · 각도 X +15° (앞으로 살짝 기울임)
        --   ⚠️ 이 값을 바꾸려면 프리뷰에서 조절한 뒤 다시 재서 옮길 것. 눈대중 금지.
        local hatTmpl = ServerStorage:FindFirstChild(HERO_HAT)
        local headPart = clone:FindFirstChild("Head")
        if hatTmpl and headPart then
            local hat = hatTmpl:Clone()
            local hh = hat:FindFirstChild("Handle")
            hat.Parent = clone
            if hh then
                local rel = CFrame.new(0, 0.379, -0.033) * CFrame.Angles(math.rad(15), 0, 0)
                hh.CFrame = headPart.CFrame * rel
                local w = Instance.new("Weld")
                w.Name = "HeroHatWeld"
                w.Part0 = headPart
                w.Part1 = hh
                w.C0 = rel
                w.Parent = hh
            end
        else
            warn("🪶 [Hero] ServerStorage." .. HERO_HAT .. " 또는 Head 없음 — 모자 미지급")
        end
        local bs = workspace:FindFirstChild("Floating Lobby")
        bs = bs and bs:FindFirstChild("Forge") and bs.Forge:FindFirstChild("Blacksmith")
        if bs then
            local sh = clone:FindFirstChildOfClass("Shirt")
            local pa = clone:FindFirstChildOfClass("Pants")
            if sh and bs:FindFirstChildOfClass("Shirt") then
                sh.ShirtTemplate = bs:FindFirstChildOfClass("Shirt").ShirtTemplate
            end
            if pa and bs:FindFirstChildOfClass("Pants") then
                pa.PantsTemplate = bs:FindFirstChildOfClass("Pants").PantsTemplate
            end
        end
    end

    -- 체력 100 (약화)
    local hum = clone:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.MaxHealth = 100
        hum.Health = 100
        hum.WalkSpeed = 16
    end

    -- 🛡️ [2026-08-26 정식 편입] AI 러너도 유저 러너와 같은 내구도 1칸을 받는다.
    --
    -- [왜 정식인가] 봇은 "인원을 채우는 장식" 이 아니라 러너 진영의 일부다.
    --   유저는 2방, 봇은 1방이면 같은 아이템이 대상에 따라 다르게 작동하는 셈이라
    --   태거가 체감하는 규칙이 일관되지 않는다. 러너는 러너다.
    --
    -- [측정 측면] 지급 전에는 봇으로 잰 1단계 수치가 실제의 2배로 나와, 볼 때마다
    --   손으로 2를 나눠야 했다. 그 환산을 잊고 "1단계가 승부를 지배한다 →
    --   근본 설계가 틀렸다" 까지 갔던 오독이 실제로 있었다.
    --   (지급 전 9/10 처치 → 지급 후 3~4/10. 후자가 실제 러너 조건이다)
    --
    -- ⚠️ 지급이 여기 있는 이유: 유저 러너 쪽 지급은 라운드 시작부의
    --   `Players:GetPlayers()` 루프 안에 있어 봇에 닿지 않는다. 봇은 생성 시점이
    --   유일한 공통 경로다. 내구도 기본값을 바꿀 때는 두 자리를 함께 볼 것.
    -- ⚠️ 봇은 여전히 뭉치고, 좁은 길목에서 회피 공간을 잃는다.
    --   이 지급으로 세 가지 측정 오염 중 하나만 없어진다.
    -- 🛡️ [재조정 2026-09-05] 전원 지급 → 절반만 지급.
    --   [실측] easy(aimError 9) 판에서 50초간 11발 중 9건 명중했는데 다운은 3건뿐,
    --     1단계 처치 1/11 이었다. 명중의 67%가 내구도 1칸에 흡수됐다.
    --     명중률 문제가 아니라 '같은 대상을 두 번 맞혀야 한다'는 구조가 병목이다.
    --   [왜 절반인가] 위 판 기준 다운 3건 → 6건 대(목표 6)로 올라온다.
    --     전원 미지급(예상 9건)은 목표를 넘고, 3마리만 지급은 7건으로 역시 넘친다.
    --   ⚠️ 유저 러너는 그대로 1칸을 받는다. 이건 봇전 난이도만 건드리는 변경이고
    --     유저의 "한 번은 봐준다" 경험은 바뀌지 않는다.
    --   ⚠️ 위 [측정 측면] 주석이 경고한 오독은 이 변경에도 그대로 적용된다 —
    --     이제 1단계 수치는 '절반은 1방, 절반은 2방'인 혼합값이다. 봇전 수치를
    --     유저전으로 그대로 옮기지 말 것.
    --   ⚠️ 티어(easy/normal/hard)와 무관하게 전원 같은 규칙이다. 난이도 차등은
    --     aimError·fireInterval 두 축으로만 한다 — 축이 셋이 되면 원인 분리가 안 된다.
    --   [방식] index 홀짝. 라운드마다 같은 비율이 보장돼 측정이 흔들리지 않는다
    --     (확률 지급은 판별 편차가 커서 한 판 결과를 믿기 어렵다).
    -- 👑 [③ 변경 2026-09-12] 홀짝 → 히어로 전용.
    --   [왜] 홀짝이면 10마리 중 무작위 5마리가 질겨서 킹이 누가 질긴지 알 수 없다.
    --     히어로 전용이면 "한 방에 안 죽으면 히어로" 가 되어 노이즈가 신호로 바뀐다.
    --   ⚠️ 지급 수가 5 → H(보통 3~4)로 줄어 1단계 다운 건수가 늘어난다.
    --     위 [왜 절반인가] 의 목표 6건 기준이 흔들리므로 재측정할 것.
    --   ⚠️ 내구도는 1단계에서만 유효하다(2단계 소모 로그 0건). 히어로 전용으로 옮겨도
    --     2단계 밸런스에는 영향이 없다.
    -- 🔴 [변경 2026-09-20] 히어로 전용 → **AI 전원 미지급**. 내구도는 유저 러너만 받는다.
    --   [왜] "한 번은 봐준다"는 실제 사람에게 주는 구제다. AI 는 동료·총알받이라는 게
    --     이 게임의 선언이고(checkRunners 주석), 지급 규칙을 그 선언과 일치시킨다.
    --   [효과 범위 — 작다는 걸 알고 넣는다] 히어로 정원은 H = max(0, HERO_TARGET(4) − 유저러너수).
    --     유저가 4명 이상 모이면 히어로가 0 마리라 이 변경의 효과도 0 이다.
    --     실질적으로는 **솔로 태거 판(H=4)** 에서만 크게 작동한다 — 즉 멀티 밸런스가 아니라
    --     '처음 킹을 해보는 사람의 첫 판'을 겨냥한 변경이다. 라이브 멀티 0/11 의 해법이 아니다.
    --   [무엇을 잃나] 09-12 가 히어로 전용으로 바꾼 이유였던 읽기 단서를 버린다 —
    --     "한 방에 안 죽으면 히어로". 이제 전원 한 방이라 히어로 구분이 안 된다.
    --   ⚠️ [측정 함정] ItemDamageSystem 의 Spear HitCount 상향(2026-09-19)은 이제
    --     **봇전에서 효과가 정확히 0** 이다 — 뚫을 내구도가 아무에게도 없다.
    --     그 값을 봇전으로 재면 "상향이 무의미했다"는 거짓 결론이 나온다. 유저전으로만 잴 것.
    --   ⚠️ 스폰 로그의 `🛡️내구도 N/M` 이 이제 항상 0/M 이다. 그게 적용 확인선이다.
    --   🔴 [되돌리는 법] false → isHero (09-12 상태) / true (09-05 이전 전원 지급).
    local giveDurability = false
    if _G.DurabilitySystem and giveDurability then
        _G.DurabilitySystem.reset(clone)
        aiDurabilityGranted += 1
    end

    -- 스폰 위치: 해당 스폰 지점 기준 Z축 분산 (같은 지점 배정분끼리만 벌림)
    local seq   = laneSeq or index
    local total = laneTotal or 1
    local offsetZ = (seq - (total + 1) / 2) * AI_LANE_GAP
    clone:PivotTo(spawnCFrame * CFrame.new(0, 3, offsetZ))

    -- AI 전용 콜리전 그룹: 유저 러너·AI끼리 통과, 태거/아이템/지형과는 러너와 동일
    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "AIRunnerChar"
        end
    end

    clone.Parent = workspace
    aiRunners[clone] = true
    return clone
end

-- 유저 러너 수에 따라 AI를 동적 스폰. spawnRef = playerSpawn (Part 또는 CFrame).
-- AI 러너 전용 콜리전 그룹 (1회 지연 등록 — 모든 시스템의 그룹 등록이 끝난 라운드 시작 시점에 관계 복사)
-- 유저 러너·AI끼리는 서로 통과, 그 외(태거/태거아이템/지형/벽)는 RunnerCharacter와 동일하게 유지.
local aiCollisionReady = false
local function ensureAICollisionGroup()
    if aiCollisionReady then return end
    aiCollisionReady = true
    local PS = game:GetService("PhysicsService")
    if not PS:IsCollisionGroupRegistered("AIRunnerChar") then
        PS:RegisterCollisionGroup("AIRunnerChar")
    end
    for _, g in ipairs(PS:GetRegisteredCollisionGroups()) do
        if g.name ~= "AIRunnerChar" then
            local collidable = PS:CollisionGroupsAreCollidable("RunnerCharacter", g.name)
            PS:CollisionGroupSetCollidable("AIRunnerChar", g.name, collidable)
        end
    end
    PS:CollisionGroupSetCollidable("AIRunnerChar", "RunnerCharacter", false)  -- 유저 러너와 통과
    PS:CollisionGroupSetCollidable("AIRunnerChar", "AIRunnerChar", false)     -- AI끼리 통과 (끼임 방지)
    print("✅ AIRunnerChar 콜리전 그룹 준비 (유저·AI 통과 / 태거·아이템·지형 유지)")
end

local function spawnAIRunners(userRunnerCount, spawnRef, spawnList)
    ensureAICollisionGroup()
    -- Part가 들어오면 CFrame 추출 (teleportPlayer와 동일하게 playerSpawn Part 사용)
    local spawnCFrame = (typeof(spawnRef) == "CFrame") and spawnRef
        or (spawnRef and spawnRef.CFrame)
    if not spawnCFrame then
        warn("[AIRunner] 스폰 기준 위치 없음 — AI 스폰 생략")
        return 0
    end
    -- 스폰 지점 후보 목록(playerSpawns)이 있으면 AI도 유저와 같은 3곳에 분산한다.
    -- 없으면 단일 지점 폴백 — 이 경우 기존처럼 한 곳에 일렬로 늘어선다.
    local spawnCFs = {}
    if spawnList then
        for _, part in ipairs(spawnList) do
            if part and part.CFrame then table.insert(spawnCFs, part.CFrame) end
        end
    end
    if #spawnCFs == 0 then spawnCFs = { spawnCFrame } end
    -- 기존 AI 정리 (이전 라운드 잔재)
    for model in pairs(aiRunners) do
        if model and model.Parent then model:Destroy() end
    end
    aiRunners = {}

    -- 템플릿 확인: 처음엔 workspace에 있고, 한 번 ServerStorage로 옮겨 보관.
    -- 이후 라운드부터는 ServerStorage에서 찾음. (라운드 중 원본이 맵에 안 보이게)
    local template = ServerStorage:FindFirstChild("Famer2") or workspace:FindFirstChild("Famer2")
    if not template then
        warn("[AIRunner] Famer2 템플릿 없음 — AI 스폰 생략")
        return 0
    end
    -- workspace에 있으면 ServerStorage로 1회 이동 (보관처 통일)
    if template.Parent == workspace then
        template.Parent = ServerStorage
    end

    -- 보충 공식: 목표 총원 - 유저 수, 단 [최소군중, 최대AI] 범위로 클램프
    local need = AI_TARGET_TOTAL - userRunnerCount
    local aiCount = math.clamp(need, AI_MIN_CROWD, AI_MAX)
    -- 🛡️ [2026-09-05] 이 라운드에 내구도를 받은 AI 수. 스폰 로그에 'N/M' 으로 찍는다.
    --   [왜] 08-26 주석이 경고했듯 봇 내구도 지급이 조용히 실패하면 1단계 수치가
    --     실제와 달라지는데, 유저 쪽과 달리 봇에는 확인 수단이 없었다.
    --   ⚠️ 여기서 0 으로 초기화한다(aiCount 확정 직후 = 스폰 루프 직전).
    --     선언만 하고 리셋을 빠뜨리면 라운드마다 누적돼 숫자가 계속 커진다.
    aiDurabilityGranted = 0
    if aiCount <= 0 then return 0 end

    -- 스폰 지점별로 균등 분배: 3곳이면 각 지점에 1~2체씩 라운드로빈.
    -- 같은 지점에 배정된 AI끼리만 레인 오프셋을 적용해 서로 겹치지 않게 한다.
    local perSpawn = {}   -- [spawnIndex] = 그 지점에 배정된 수
    local seqInSpawn = {} -- [spawnIndex] = 현재까지 배치한 순번
    for i = 1, aiCount do
        local si = ((i - 1) % #spawnCFs) + 1
        perSpawn[si] = (perSpawn[si] or 0) + 1
    end
    -- 👑 [③ 2026-09-12] 히어로 정원 계산. spawnAIRunner 가 index <= heroQuota 로 가른다.
    --   ⚠️ index 1..H 가 히어로다. 스폰 지점 분산(라운드로빈)과 무관하게 번호로만 정해야
    --     "지점 하나에 히어로가 몰리는" 편중이 안 생긴다 — 분산은 si 가 따로 맡는다.
    --   ⚠️ 유저가 HERO_TARGET 이상이면 히어로 0. 그때는 유저가 이미 전력을 채운 것이다.
    heroQuota = math.max(0, math.min(HERO_TARGET - userRunnerCount, aiCount))
    if heroQuota > 0 then
        print(string.format("👑 [Hero] 히어로봇 %d체 / 농민 %d체 (유저 러너 %d명, 목표 히어로 %d)",
            heroQuota, aiCount - heroQuota, userRunnerCount, HERO_TARGET))
    end

    for i = 1, aiCount do
        local si = ((i - 1) % #spawnCFs) + 1
        seqInSpawn[si] = (seqInSpawn[si] or 0) + 1
        spawnAIRunner(template, spawnCFs[si], i, seqInSpawn[si], perSpawn[si])
    end

    print(string.format("🌾 AI 러너 %d체 스폰 (유저 러너 %d명 / 목표 총원 %d / 스폰지점 %d곳 분산) 🛡️내구도 %d/%d",
        aiCount, userRunnerCount, AI_TARGET_TOTAL, #spawnCFs,
        aiDurabilityGranted, aiCount))
    return aiCount
end

-- 단일 파트 메시 스케일 (MeshPart=Size 배율 / SpecialMesh=Mesh.Scale 배율)
local function scalePartMesh(part, mult)
    if not mult or mult == 1 then return end
    if part:IsA("MeshPart") then
        part.Size = part.Size * mult
    else
        local sm = part:FindFirstChildWhichIsA("SpecialMesh")
        if sm then sm.Scale = sm.Scale * mult else part.Size = part.Size * mult end
    end
end

local function weldPartTo(anchor, part)
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = anchor
    weld.Part1 = part
    weld.Parent = part
end

-- CrownModels 템플릿 모델 복제 + PrimaryPart 물리속성 정리. 반환: (model, primaryPart) 또는 nil.
local function cloneTemplateModel(templateName)
    local folder = ServerStorage:FindFirstChild("CrownModels")
    local tmpl = folder and folder:FindFirstChild(templateName)
    if not tmpl or not tmpl.PrimaryPart then return nil end
    local clone = tmpl:Clone()
    local pp = clone.PrimaryPart
    pp.Anchored = false
    pp.CanCollide = false
    pp.Massless = true
    return clone, pp
end

-- ── 크라운 스킨 인벤 프리뷰 (ReplicatedStorage.CrownPreviews) ──────────────
-- attachCrownToTagger의 조립 로직을 재활용해, 머리에 붙이는 대신 원점 기준 Anchored 모델로 만들어
-- 클라(UnifiedInvenClient)가 ViewportFrame으로 렌더 → 실제 착용과 동일한 색/재질/메시가 그대로 나옴.
local CROWN_PREVIEW_ROT = CFrame.Angles(math.pi / 2, 0, 0)  -- 기본 크라운 메시 세움(attachCrownToTagger와 동일)
-- 인벤 뷰포트 카메라 튜닝값(PreviewTunerClient로 잡은 [TUNE-OUT] 기록). skinKey → {dist, dir, pan}
-- 클라 UnifiedInvenClient가 DistMul/CameraDirection/CameraLookOffset 속성으로 읽음.
local CROWN_PREVIEW_TUNE = {
    Flower       = { dist = 2.40, dir = Vector3.new(0.3, 0.25, 0.8),  pan = Vector3.new(0, 0, 0) },
    Money        = { dist = 2.60, dir = Vector3.new(0.3, 0.25, 1.0),  pan = Vector3.new(-0.05, 0, 0) },
    DarkRainbow  = { dist = 3.40, dir = Vector3.new(0.3, 0.25, 1.0),  pan = Vector3.new(0, 0, 0) },
    Void         = { dist = 3.90, dir = Vector3.new(0.4, 0.25, -1.0), pan = Vector3.new(0.05, 0, 0) },
    EightBit     = { dist = 3.90, dir = Vector3.new(0.3, 0.25, 1.0),  pan = Vector3.new(0, 0, 0) },
    Blackstar    = { dist = 3.90, dir = Vector3.new(0.3, 0.25, 1.0),  pan = Vector3.new(0, 0, 0), backdrop = Color3.fromRGB(235, 235, 240), backdropSize = Vector2.new(0.85, 0.50) },
    Black        = { backdrop = Color3.fromRGB(235, 235, 240), backdropSize = Vector2.new(0.68, 0.50) },  -- 검정 크라운: 검정 뷰포트 배경에 묻혀 → 밝은 백드롭
    -- 엔젤 시리즈: crown_angel 로그 하나로 둘 다 적용
    Angel        = { dist = 3.50, dir = Vector3.new(0.3, 0.25, 1.0),  pan = Vector3.new(-0.05, -0.15, 0) },
    MagentaAngel = { dist = 3.50, dir = Vector3.new(0.3, 0.25, 1.0),  pan = Vector3.new(-0.05, -0.15, 0) },
}
local function buildCrownPreview(skinKey)
    local v = CROWN_SKIN_VISUAL[skinKey]
    if not v then return nil end
    local preview = Instance.new("Model")
    preview.Name = skinKey

    if v.model then
        -- 고유 메시 스킨 (Flower/Money/Void 등): 색 안 바꿈, 자기 텍스처/이펙트 유지
        local mdl, pp = cloneTemplateModel(v.model)
        if not mdl then return nil end
        scalePartMesh(pp, v.headScale or 1)
        pp.Anchored = true
        mdl:PivotTo(CFrame.new(0, 0, 0) * (v.headRot or CFrame.Angles(0, 0, 0)))
        mdl.Parent = preview
        preview.PrimaryPart = pp
    elseif v.wings then
        -- 엔젤: 날개+후광(halo) 메시
        local mdl, pp = cloneTemplateModel(v.wings)
        if not mdl then return nil end
        scalePartMesh(pp, v.wingScale or 1)
        pp.Anchored = true
        mdl:PivotTo(CFrame.new(0, 0, 0) * (v.wingRot or CFrame.Angles(0, 0, 0)))
        mdl.Parent = preview
        preview.PrimaryPart = pp
    elseif CROWN_TEMPLATE then
        -- 틴트 스킨: 기본 크라운 메시 + 색/재질
        local mdl = CROWN_TEMPLATE:Clone()
        local pp = mdl.PrimaryPart
        if not pp then return nil end
        pp.Anchored = true
        pp.CanCollide = false
        pp.Massless = true
        pp.Material = v.material
        pp.Color = v.color
        pp.Reflectance = v.reflectance or 0
        pp.Transparency = v.transparency or 0
        if not v.keepTexture then pp.TextureID = "" end
        mdl:PivotTo(CFrame.new(0, 0, 0) * CROWN_PREVIEW_ROT)
        mdl.Parent = preview
        preview.PrimaryPart = pp
    else
        return nil
    end
    -- 카메라 튜닝값 부착(있는 스킨만) → 클라 뷰포트가 읽어 각 왕관에 맞는 거리/방향/팬/배경 적용
    local tune = CROWN_PREVIEW_TUNE[skinKey]
    if tune then
        if tune.dist then preview:SetAttribute("DistMul", tune.dist) end
        if tune.dir then preview:SetAttribute("CameraDirection", tune.dir) end
        if tune.pan then preview:SetAttribute("CameraLookOffset", tune.pan) end
        if tune.backdrop then preview:SetAttribute("Backdrop", tune.backdrop) end   -- 어두운 왕관 대비용 밝은 배경
        if tune.backdropSize then preview:SetAttribute("BackdropSize", tune.backdropSize) end   -- 백드롭 가로/세로(Scale)
    end
    return preview
end

do
    local folder = ReplicatedStorage:FindFirstChild("CrownPreviews")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "CrownPreviews"
        folder.Parent = ReplicatedStorage
    end
    local n = 0
    for skinKey in pairs(CROWN_SKIN_VISUAL) do
        if not folder:FindFirstChild(skinKey) then
            local ok, pv = pcall(buildCrownPreview, skinKey)
            if ok and pv then
                pv.Parent = folder
                n += 1
            else
                warn("[CrownPreview] 생성 실패: " .. tostring(skinKey) .. " / " .. tostring(pv))
            end
        end
    end
    print("[CrownPreview] " .. n .. "종 프리뷰 생성 → ReplicatedStorage.CrownPreviews")
end

local function attachCrownToTagger(player)
    if not player or not player.Character then return end
    local char = player.Character
    local head = char:FindFirstChild("Head")
    if not head then return end

    -- DEBUG: 제거 전 TaggerCrown 개수
    local beforeN = 0
    for _, c in ipairs(char:GetChildren()) do if c.Name == "TaggerCrown" then beforeN += 1 end end
    removeCrownFromPlayer(player)

    local skinKey = player:GetAttribute("CrownSkin")
    local v = (skinKey and CROWN_SKIN_VISUAL[skinKey]) or CROWN_SKIN_VISUAL[DEFAULT_CROWN_SKIN]

    -- 런타임 넛지(미세조정) 값 — TestCommands /cn(머리) /wn(날개)이 설정. 기본 0/1.
    local cnX = player:GetAttribute("CN_X") or 0
    local cnY = player:GetAttribute("CN_Y") or 0
    local cnZ = player:GetAttribute("CN_Z") or 0
    local cnS = player:GetAttribute("CN_S") or 1
    local cnRX = player:GetAttribute("CN_RX") or 0
    local cnRY = player:GetAttribute("CN_RY") or 0
    local cnRZ = player:GetAttribute("CN_RZ") or 0
    local wnX = player:GetAttribute("WN_X") or 0
    local wnY = player:GetAttribute("WN_Y") or 0
    local wnZ = player:GetAttribute("WN_Z") or 0
    local wnS = player:GetAttribute("WN_S") or 1
    local wnRX = player:GetAttribute("WN_RX") or 0
    local wnRY = player:GetAttribute("WN_RY") or 0
    local wnRZ = player:GetAttribute("WN_RZ") or 0

    -- 컨테이너 모델: 머리 크라운 + 날개를 모두 담아 한 번에 제거 가능하게.
    local container = Instance.new("Model")
    container.Name = "TaggerCrown"

    local headDbg, wingDbg = "none", "none"

    -- ── 머리 ──────────────────────────────
    if v.model then
        -- 모델 스킨: 고유 메시 (색 변경 안 함, 자기 텍스처/이펙트 유지). PivotTo로 PivotOffset 반영.
        local mdl, pp = cloneTemplateModel(v.model)
        if mdl then
            local eScale = (v.headScale or 1) * cnS
            scalePartMesh(pp, eScale)
            local baseOff = v.headOffset or Vector3.new(0, 1.3, 0)
            local eOff = baseOff + Vector3.new(cnX, cnY, cnZ)
            local rot = (v.headRot or CFrame.Angles(0, 0, 0)) * CFrame.Angles(math.rad(cnRX), math.rad(cnRY), math.rad(cnRZ))
            mdl:PivotTo(head.CFrame * CFrame.new(eOff) * rot)
            weldPartTo(head, pp)
            mdl.Parent = container
            headDbg = ("model[%s] off=(%.2f,%.2f,%.2f) scale=%.2f rot=(%d,%d,%d)"):format(v.model, eOff.X, eOff.Y, eOff.Z, eScale, cnRX, cnRY, cnRZ)
        end
    elseif v.headless then
        -- 머리 크라운 없음: 날개 메시(AngelWings)에 후광(halo)이 포함돼 있어 별도 크라운 불필요.
        headDbg = "headless"
    elseif CROWN_TEMPLATE then
        -- 틴트 스킨: 기본 크라운 메시 + 색/재질. 모델 통째로 PivotTo (PivotOffset 회전보정 반영).
        local mdl = CROWN_TEMPLATE:Clone()
        local pp = mdl.PrimaryPart
        if pp then
            pp.Anchored = false
            pp.CanCollide = false
            pp.Massless = true
            local CROWN_SCALE = 1.6
            pp.Size = pp.Size * (CROWN_SCALE * cnS)
            pp.Material = v.material
            pp.Color = v.color
            pp.Reflectance = v.reflectance or 0
            pp.Transparency = v.transparency or 0
            if not v.keepTexture then pp.TextureID = "" end
            if v.cycle then
                local part = pp
                local conn
                conn = game:GetService("RunService").Heartbeat:Connect(function()
                    if not part or not part.Parent then conn:Disconnect() return end
                    part.Color = Color3.fromHSV((tick() * 0.4) % 1, 1, 0.9)
                end)
            end
            local CROWN_ROTATION = CFrame.Angles(math.pi / 2, 0, 0)
            local headHalf = head.Size.Y / 2
            local crownHalf = pp.Size.Z / 2
            local tintY = headHalf + crownHalf + 0.2 + cnY
            mdl:PivotTo(head.CFrame * CFrame.new(cnX, tintY, cnZ) * CROWN_ROTATION)
            weldPartTo(head, pp)
            mdl.Parent = container
            headDbg = ("tint[%s] dY=%.2f scale=%.2f"):format(tostring(skinKey), tintY, CROWN_SCALE * cnS)
        else
            mdl:Destroy()
        end
    end

    -- ── 날개 (엔젤 시리즈) ─────────────────────
    if v.wings then
        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        if torso then
            local mdl, pp = cloneTemplateModel(v.wings)
            if mdl then
                local eScale = (v.wingScale or 1) * wnS
                scalePartMesh(pp, eScale)
                local baseOff = v.wingOffset or Vector3.new(0, 0.5, 0.8)
                local eOff = baseOff + Vector3.new(wnX, wnY, wnZ)
                local wrot = (v.wingRot or CFrame.Angles(0, 0, 0)) * CFrame.Angles(math.rad(wnRX), math.rad(wnRY), math.rad(wnRZ))
                mdl:PivotTo(torso.CFrame * CFrame.new(eOff) * wrot)
                weldPartTo(torso, pp)
                mdl.Parent = container
                wingDbg = ("%s off=(%.2f,%.2f,%.2f) scale=%.2f rot=(%d,%d,%d)"):format(v.wings, eOff.X, eOff.Y, eOff.Z, eScale, wnRX, wnRY, wnRZ)
            end
        end
    end

    if #container:GetChildren() == 0 then
        container:Destroy()
        warn("[RoundSystem] 왕관 부착 실패 (skin=" .. tostring(skinKey) .. ")")
        return
    end
    container.Parent = char
    print(("[CrownDbg] skin=%s beforeRemove=%d | head=%s | wings=%s"):format(
        tostring(skinKey), beforeN, headDbg, wingDbg))
end

-- 테스트용 외부 노출
_G.attachCrownToTagger = attachCrownToTagger
_G.removeCrownFromPlayer = removeCrownFromPlayer

-- ── 관전 대상 조회 (SpectateSystem 연동) ──────────────────────
-- 반환: 관전 가능한 대상 엔트리 배열. 순서 = 태거 먼저, 러너들(플레이어+NPC).
-- 조건: Humanoid.Health > 0 (죽은 대상 제외 / 다운된 대상은 Health>0 이라 포함됨).
-- 엔트리 형식:
--   플레이어 → { kind="player", userId=..., name=..., isTagger=bool }
--   NPC     → { kind="npc",    model=<이름>, name=..., isTagger=false }
-- 라운드 중이 아니면 빈 배열.
local function isPlayerAlive(plr)
	if not plr or not plr.Parent then return false end
	if plr:GetAttribute("Eliminated") then return false end  -- 탈락자 제외 (리스폰해도)
	local char = plr.Character
	if not char then return false end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function isModelAlive(model)
	if not model or not model.Parent then return false end
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	return hum ~= nil and hum.Health > 0
end

_G.GetSpectateTargets = function()
	local targets = {}
	if not roundActive then return targets end
	-- ⚠️ 테스트 더미(taggerdummy / Noob / runnerdummy 계열)는 관전 대상에서 제외한다.
	--    _TestRigBoot 이 Studio 에서만 복원하는 히트박스 테스트용 오브젝트라,
	--    관전 목록에 뜨면 "아무도 없는 자리에 NPC 마커가 보이는" 혼란이 생긴다.
	--    (라이브에는 존재하지 않으므로 실제 유저에게는 영향 없음)
	--    승패 카운트에서도 이미 제외됨(npcRunners 미등록).
	-- 1) 태거 먼저
	if isPlayerAlive(currentTagger) then
		table.insert(targets, {
			kind = "player", userId = currentTagger.UserId,
			name = currentTagger.Name, isTagger = true,
		})
	end
	-- 2) 살아있는 플레이어 러너들 (currentRunners 순서 유지)
	for _, runner in ipairs(currentRunners) do
		if isPlayerAlive(runner) then
			table.insert(targets, {
				kind = "player", userId = runner.UserId,
				name = runner.Name, isTagger = false,
			})
		end
	end
	-- 3) 살아있는 AI 러너(농민봇) — 유저가 전부 탈락한 뒤에도 볼 대상이 남게
	for model in pairs(aiRunners) do
		if isModelAlive(model) then
			table.insert(targets, {
				kind = "npc", model = model.Name,
				name = model.Name, isTagger = false,
			})
		end
	end
	return targets
end

-- 특정 플레이어가 "라운드에 살아서 참여 중"인지 (관전 권한 판정용).
-- 살아서 참여 중이면 관전 불가 → false 면 관전 허용 (대기 중 or 탈락).
-- 사망 시 Eliminated=true 가 되므로, 죽고 리스폰해도 정확히 판정됨.
_G.IsPlayingAlive = function(plr)
	if not roundActive then return false end
	if plr:GetAttribute("Eliminated") then return false end  -- 탈락 → 관전 허용
	if currentTagger == plr then return true end
	for _, runner in ipairs(currentRunners) do
		if runner == plr then return true end
	end
	return false
end

-- 현재 태거 UserId (관전 UI 의 "태거" 표시용). 없으면 nil.
_G.GetCurrentTaggerUserId = function()
	if roundActive and isPlayerAlive(currentTagger) then
		return currentTagger.UserId
	end
	return nil
end


-- 플레이어 선택 슬롯
-- ── 태거 피티(Pity) 선택 ────────────────────────────────
-- TaggerPity(속성, 세션 한정) = 태거 안 한 지 몇 라운드. weight = 1 + pity.
-- 하드 개런티: pity가 임계값(max(6, 인원×2)) 이상인 사람 있으면 그 중 최고 pity에서 강제 선택.
-- 태거 선택 가중치: (1 + pity) × 부스트(Tagger Priority 토큰 보유 시 ×MULT)
local function weightOf(p)
    local w = 1 + (p:GetAttribute("TaggerPity") or 0)
    if _G.TaggerBoost and _G.TaggerBoost.hasBoost(p) then
        w = w * _G.TaggerBoost.MULT
    end
    return w
end

local function pickTaggerWithPity(players)
    if #players <= 1 then return players[1] end
    local threshold = math.max(6, #players * 2)
    -- 1) 하드 개런티: 임계 넘은 사람 중 최고 pity
    local forced, maxPity = {}, -1
    for _, p in ipairs(players) do
        local pity = p:GetAttribute("TaggerPity") or 0
        if pity >= threshold then
            if pity > maxPity then
                maxPity, forced = pity, { p }
            elseif pity == maxPity then
                table.insert(forced, p)
            end
        end
    end
    if #forced > 0 then
        return forced[math.random(1, #forced)]
    end
    -- 2) 가중 랜덤 (weight = 1 + pity)
    local total = 0
    for _, p in ipairs(players) do
        total += weightOf(p)
    end
    local r = math.random() * total
    local acc = 0
    for _, p in ipairs(players) do
        acc += weightOf(p)
        if r <= acc then return p end
    end
    return players[#players]  -- 부동소수 안전망
end

-- 선택 후 pity 갱신: 뽑힌 사람 0, 나머지 활성 플레이어 +1
local function updateTaggerPity(players, chosen)
    for _, p in ipairs(players) do
        if p == chosen then
            p:SetAttribute("TaggerPity", 0)
        else
            p:SetAttribute("TaggerPity", (p:GetAttribute("TaggerPity") or 0) + 1)
        end
    end
end

-- 표시용 확률 계산 (pickTaggerWithPity와 동일 규칙). 반환: {[UserId]=percent}
local function computeTaggerOdds(players)
    local odds = {}
    if #players == 0 then return odds end
    if #players == 1 then odds[players[1].UserId] = 100; return odds end
    local threshold = math.max(6, #players * 2)
    local forced, maxPity = {}, -1
    for _, p in ipairs(players) do
        local pity = p:GetAttribute("TaggerPity") or 0
        if pity >= threshold then
            if pity > maxPity then
                maxPity, forced = pity, { p }
            elseif pity == maxPity then
                table.insert(forced, p)
            end
        end
    end
    if #forced > 0 then
        local share = 100 / #forced
        for _, p in ipairs(players) do odds[p.UserId] = 0 end
        for _, p in ipairs(forced) do odds[p.UserId] = share end
        return odds
    end
    local total = 0
    for _, p in ipairs(players) do total += weightOf(p) end
    for _, p in ipairs(players) do
        odds[p.UserId] = weightOf(p) / total * 100
    end
    return odds
end

local function selectTaggerWithSlot(players)
    showSlotToAll(true)
    updateSlotTitle("👑 SELECTING KING")
    updateSlotResult("")
    showSlotOddsToAll(computeTaggerOdds(players))  -- 확률 명시 (pity 갱신 전 기준)
    
    for i = 1, 30 do
        local randomPlayer = players[math.random(1, #players)]
        updateSlotDisplay(randomPlayer.Name, true, randomPlayer.UserId)
        wait(0.06 + (i * 0.018))
    end
    
    local chosenTagger = pickTaggerWithPity(players)
    -- [Pity] 검증용: 갱신 전 각자 pity + 뽑힌 사람 (F5 로그 확인)
    do
        local dbg = {}
        for _, p in ipairs(players) do dbg[#dbg + 1] = p.Name .. "=" .. tostring(p:GetAttribute("TaggerPity") or 0) end
        print("[Pity] threshold=" .. math.max(6, #players * 2) .. " | " .. table.concat(dbg, "  ") .. "  → chosen: " .. chosenTagger.Name)
    end
    updateTaggerPity(players, chosenTagger)
    if _G.TaggerBoost then _G.TaggerBoost.consume(chosenTagger) end
    
    for i = 1, 3 do
        updateSlotDisplay("???", false)
        wait(0.2)
        updateSlotDisplay(chosenTagger.Name, true, chosenTagger.UserId)
        wait(0.2)
    end
    
    updateSlotResult("👑 KING: " .. chosenTagger.Name)
    wait(3)
    
    showSlotToAll(false)
    return chosenTagger
end

-- 텔레포트 코어: 동기 실행, 성공 여부를 반환한다.
-- 실패(HRP 미확보) 시 캐릭터를 다시 조회해 1회 재시도한다 — 낙사 직후에는
-- CharacterAdded 로 잡은 캐릭터가 한 번 더 교체될 수 있기 때문.
-- ⚠️ 배치 검증에 쓰인다: 라운드 시작 배치는 이 반환값으로 참가 여부를 확정한다.
--    (텔레포트 실패자가 currentRunners/Role 에 남으면 로비에서 생존자로 세어져
--     라운드가 안 끝나거나, 맵에 가지도 않고 참여/생존/승리 코인을 받는 어뷰징이 됨)
local function teleportPlayerCore(player, spawnPart)
    -- 살아있는 캐릭터 확보 헬퍼.
    -- ⚠️ HRP 존재만으로는 부족하다 — 죽은/죽어가는 캐릭터도 HRP 를 갖고 있어서,
    --    낙사 직후의 몸을 "성공적으로" 텔레포트한 뒤 리스폰으로 로비에 되돌아가는
    --    사례가 실측됨 (태거가 로비에 재생성된 채 왕관·Role 을 받은 버그, 2026-08).
    --    Health > 0 인 캐릭터만 유효로 보고, 죽어 있으면 리스폰(새 캐릭터)을 기다린다.
    local function acquireAliveCharacter(timeout)
        local t0 = os.clock()
        while os.clock() - t0 < timeout do
            if not player.Parent then return nil end
            local c = player.Character
            local hum = c and c.Parent and c:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then return c end
            task.wait(0.1)
        end
        return nil
    end

    for attempt = 1, 2 do
        if not player.Parent then return false end   -- 이미 퇴장

        -- 리스폰 대기까지 커버 (기본 RespawnTime ~5초)
        local character = acquireAliveCharacter(6)
        if character then
            local hrp = character.Parent and character:WaitForChild("HumanoidRootPart", 5)
            if hrp then
                local targetCF = spawnPart.CFrame + Vector3.new(0, 5, 0)
                -- 앵커로 물리 개입 차단 후 위치 고정 (맵 ServerStorage→WS 복귀 직후 바닥 미등록 대응)
                hrp.Anchored = true
                character:PivotTo(targetCF)
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero

                -- 발밑 CanCollide 바닥이 물리 등록될 때까지 대기 (최대 30프레임 ≈ 0.5s)
                local waited = 0
                for i = 1, 30 do
                    local rp = RaycastParams.new()
                    rp.FilterType = Enum.RaycastFilterType.Exclude
                    rp.FilterDescendantsInstances = {character}
                    rp.RespectCanCollide = true  -- CanCollide=false(스폰 플레이트 등)는 레이가 통과
                    local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -50, 0), rp)
                    if hit then break end
                    character:PivotTo(targetCF)  -- 대기 중 밀려나지 않게 재고정
                    task.wait()
                    waited = i
                end
                if waited > 0 then
                    warn(string.format("[Teleport] %s 바닥 등록 대기: %d프레임 (%s)", player.Name, waited, spawnPart.Name))
                end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.Anchored = false

                -- 최종 생존 확인: 대기 중(최대 ~0.5s) 사망했다면 리스폰으로 무효화될 몸이다
                local hum = character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and character.Parent then
                    return true
                end
                warn(string.format("[Teleport] 배치 직후 사망 감지: %s (시도 %d/2)", player.Name, attempt))
            else
                warn(string.format("[Teleport] HRP 없음: %s (시도 %d/2)", player.Name, attempt))
            end
        else
            warn(string.format("[Teleport] 살아있는 캐릭터 없음: %s (시도 %d/2)", player.Name, attempt))
        end
    end
    return false
end

-- 비동기 래퍼: 결과가 필요 없는 경로용 (라운드 종료 후 로비 복귀 등)
local function teleportPlayer(player, spawnPart)
    task.spawn(teleportPlayerCore, player, spawnPart)
end

-- 생존자 수 체크
-- ⚠️ 승패 판정용: 이 카운트가 0이면 "러너 전멸 → 태거 승리".
--    AI 러너(AIRunner 속성)는 동료/총알받이일 뿐 승패를 결정하지 않으므로 카운트에서 제외.
--    → 유저 러너가 전부 죽으면 AI가 살아있어도 태거 승리(라운드 교착 방지).
local function checkRunners()
    local aliveRunners = 0
    -- 플레이어 러너 체크
    -- ⚠️ Eliminated(사망 표시)를 반드시 먼저 본다.
    --    캐릭터 체력만 보면 "죽은 뒤 리스폰된 새 캐릭터"(체력 100)를 생존자로 오인한다.
    --    특히 얼음 킬 이펙트는 연출 종료 시 victimPlayer:LoadCharacter() 로 즉시 부활시켜서
    --    이 체크가 도는 시점엔 이미 새 몸이 서 있다 → 러너 전멸이 영영 감지되지 않아
    --    라운드가 끝나지 않는 버그가 있었다 (2026-08 라이브 재현).
    --    Eliminated 는 플레이어 속성이라 캐릭터가 교체돼도 유지된다.
    -- ⚰️ [2026-08-28] 처형 연출 중인 대상은 '사망'으로 센다 (유저·AI 공통 규칙).
    --   [증상] 카운트가 역행하고 같은 값이 반복됐다.
    --     (실측 10:26:25.111 alive=1 → 25.668/25.670 코핀 2건 발동 → 34.675 alive=2.
    --      3명이 죽는 사이에 오히려 늘었다)
    --   [원인] DownSystem.killDowned 가 처형으로 넘길 때 Downed 속성을 지운다.
    --     그 순간부터 Downed=nil + Health>0 이라 아래 두 루프가 다시 생존자로 센다.
    --     아래 AI 분기의 "다운은 사망으로 센다" 주석이 막으려던 구멍이,
    --     '처형 시작 시점에' 다시 열린 셈이다.
    --   ⚠️ 판정은 _G.IsInKillSequence 를 쓴다. 속성(CoffinSequence/PunchActive 등)을
    --     직접 검사하지 말 것 — 처형 이펙트가 6종이라 반드시 한쪽만 갱신된다.
    --   ⚠️ 유저 분기에도 같이 넣는다. 유저는 '다운=생존'(부활 가능)이 맞지만
    --     처형이 시작되면 부활 경로가 없어 그 시점부터는 사망이다.
    --   ⚠️ 연출이 잘릴 걱정은 없다. endRound / 인터미션 루프가 waitForKillEffects(20) 로
    --     기다리고, ExecuteKillEffect 가 핸들러 호출 '전에' MarkKillEffectBusy 를
    --     등록한다(코핀 18 / 나머지 8). 전멸 경로엔 task.wait(2) 도 앞에 있다.
    local function inKillSeq(char)
        return char ~= nil and _G.IsInKillSequence ~= nil and _G.IsInKillSequence(char)
    end
    for _, runner in ipairs(currentRunners) do
        if runner.Parent and not runner:GetAttribute("Eliminated")
           and runner.Character and runner.Character:FindFirstChild("Humanoid") then
            if runner.Character.Humanoid.Health > 0 and not inKillSeq(runner.Character) then
                aliveRunners = aliveRunners + 1
            end
        end
    end
    -- NPC 러너 체크 (레거시 Noob/Noob2 테스트 더미. 아카이브 이관 시 이 루프는 항상 0)
    for _, npc in ipairs(npcRunners) do
        -- ⚠️ NPC 도 다운은 사망으로 센다(부활 경로 없음)
        if npc.Parent and npc:FindFirstChild("Humanoid")
           and not npc:GetAttribute("Downed") and not npc:GetAttribute("AIRunner") then
            if npc.Humanoid.Health > 0 then
                aliveRunners = aliveRunners + 1
            end
        end
    end

    -- AI 러너(농민봇) 체크
    -- 기본 규칙: AI 는 동료/총알받이라 승패에서 제외 — 유저 러너가 전멸하면 AI 가 남아도 태거 승.
    -- ⚠️ 예외: "라운드 시작 시" 유저 러너가 0명인 판(솔로 태거 모드)에서는 AI 가 유일한 상대다.
    --    ⚠️ 판단 기준은 roundUserRunnerCount(시작 시점 스냅샷)여야 한다.
    --    현재 생존 수로 판단하면 유저 러너가 죽는 순간 AI 가 승패 대상으로 승격되어
    --    "유저 전멸 = 태거 승" 규칙이 깨지고 AI 끼리 라운드가 계속된다 (2026-08 실측).
    if (roundUserRunnerCount or 0) == 0 then
        for model in pairs(aiRunners) do
            if model and model.Parent then
                local hum = model:FindFirstChildOfClass("Humanoid")
                -- ⚠️ [2026-08-25] 다운 상태는 사망으로 센다.
                --   [왜] 처형 연출(아이스 킬 등)이 끝날 때까지 Health > 0 이라
                --   '생존'으로 세어졌다. 실측: 태거가 10명을 다 쓰러뜨렸는데
                --   처형 1초 전에 죽어 패배로 기록됐다.
                --
                --   [안전한 이유] ReviveSystem.findNearestDowned 는 플레이어를
                --   가리지 않아 AI 러너도 살릴 수 있다. 하지만 이 블록은
                --   roundUserRunnerCount == 0 (= 살릴 유저가 아무도 없음)
                --   일 때만 실행되므로, 여기서는 다운이 곧 확정 사망이다.
                --   ⚠️ 위 조건이 바뀌면 이 가정도 깨진다. 함께 확인할 것.
                --   그런데 처형 연출(아이스 킬 등)이 끝날 때까지 Health > 0 이라
                --   '생존'으로 세어졌다. 실측: 태거가 10명을 다 쓰러뜨렸는데
                --   처형 연출 1초 전에 죽어 패배로 기록됐다.
                --   → 쓰러뜨린 시점에 판정이 나야 한다.
                -- ⚰️ [2026-08-28] inKillSeq: 위 유저 분기와 같은 규칙. 주석은 그쪽 참조.
                if hum and hum.Health > 0 and not model:GetAttribute("Downed")
                   and not inKillSeq(model) then
                    aliveRunners = aliveRunners + 1
                end
            end
        end
    end

    return aliveRunners
end

-- ⚠️ [2026-08-26] 전멸 확정 시점에 "다운 상태" 러너를 킬 집계에 미리 반영한다.
--   [증상] 솔로 태거 판에서 10명을 다 쓰러뜨렸는데 결과창 Kills 가 7 로 나왔다.
--   [원인] checkRunners 는 다운을 사망으로 세어 라운드를 끝내는데(부활 불가라 정당),
--     실제 사망은 DOWN_DURATION(10초) 만료 후다. 결과창 정산은 그보다 먼저 돌고,
--     handleKill 은 Humanoid.Died 훅에서만 불리므로 그 N명이 통째로 누락된다.
--     (2026-08-26 실측: 22:54:32 종료 판정 → 22:54:41 에 AIRunner_4/6/9 사망. 7 + 3 = 10)
--   [해결] _G.RegisterKill 로 종료 직전에 등록한다. _KillCounted 가드가 있어
--     나중에 Died 가 도착해도 이중 집계되지 않는다(onKill 이 플래그 보고 조기 return).
--   ⚠️ checkRunners 가 "다운 = 사망" 으로 세는 규칙과 한 짝이다. 한쪽만 바꾸면 다시 어긋난다.
--   ⚠️ 전멸(elimination) 경로에서만 부른다. 타임아웃·러너 승리 때는 다운이 아직
--     부활 가능한 상태일 수 있어 킬로 확정하면 안 된다.
local function registerDownedAsKills()
    local tagger = currentTagger
    if not tagger or not tagger.Parent then return 0 end
    if type(_G.RegisterKill) ~= "function" then return 0 end
    local n = 0

    -- ☠️ [2026-08-27] 집계만 하지 않고 '실제로 죽인다'.
    --   [예전] _G.RegisterKill 로 킬만 등록하고 몸은 블리드아웃(10초)까지 살려뒀다.
    --     그래서 두 번 어긋났다:
    --       · 킬이펙트가 결과창/로비 '뒤'에 나와 아무도 못 봄 (실측 00:03)
    --       · 이펙트를 확정 시점으로 앞당겼더니 이번엔 '다운 상태인 산 몸' 위로
    --         무덤이 떴다 — 사망 8초 전 (실측 00:42:31 무덤 / 00:42:39 사망)
    --     즉 틀린 건 이펙트 시점이 아니라 '사망 시점'이었다.
    --   [지금] _G.KillDownedRunner 가 다운 정리·처형이펙트 위임·관절 파괴까지 하고
    --     Health=0 을 준다 → Humanoid.Died → onKill 이 평소 경로로 집계 + 이펙트.
    --     라운드 종료 대기(waitForKillEffects)도 그 연출을 자연히 기다린다.
    --   ⚠️ 전멸 확정 시점이라 부활 유예(10초)는 의미가 없다 — 부활시킬 사람이 없다.
    --   ⚠️ 폴백 유지: KillDownedRunner 는 DownSystem 내부 표에 없으면 false 를 준다.
    --     Downed 속성과 그 표가 어긋나면 킬이 통째로 누락되는데(원래 이 함수가
    --     생긴 이유가 그 누락이다), 그 경우엔 최소한 집계라도 남긴다.
    local function finish(character, displayName)
        if type(_G.KillDownedRunner) == "function"
           and _G.KillDownedRunner(character, tagger) then
            return true
        end
        return _G.RegisterKill(tagger, character, displayName)
    end

    for model in pairs(aiRunners) do
        if model and model.Parent and model:GetAttribute("Downed") then
            if finish(model, model.Name) then n += 1 end
        end
    end
    for _, runner in ipairs(currentRunners) do
        local ch = runner and runner.Parent and runner.Character
        if ch and ch:GetAttribute("Downed") then
            if finish(ch, runner.Name) then n += 1 end
        end
    end
    if n > 0 then
        print(string.format("💀 [정산] 다운 상태 러너 %d명 → 킬 확정 반영 (블리드아웃 전)", n))
    end
    return n
end

-- 승리 처리
-- endRound 정리(보상·로비 텔레포트·결과창) 완료 신호.
-- 메인 루프가 이걸 기다렸다 인터미션 타이머를 시작 — 유저가 아직 맵에 있는데
-- "Next game in" 카운트다운이 뜨는 어색함 방지. (초기 true: 서버 첫 인터미션은 대기 없음)
local roundCleanupDone = true
_G.IsRoundLive = function() return roundActive end  -- 종료 후 행동 차단용 (아이템 스폰/봇 AI 등)

-- 킬 이펙트(코핀 등) 연출 중이면 완료까지 대기 — 라운드 종료가 연출을 끊지 않게 (연출 가치 보존)
local function waitForKillEffects(maxWait)
    if not _G.KillEffectBusyUntil then return end
    local deadline = os.clock() + (maxWait or 20)
    -- 🔒 [버그수정 2026-09-04] '종료 시점에 이미 진행 중이던' 연출만 기다린다.
    --   [증상] 점령 승리(23:44:49) 후 정리가 12초나 늦었다. 그 사이 태거가 계속
    --     때려서 새 처형이 시작됐고(23:45:03, 23:45:04), 그때마다 KillEffectBusyUntil 이
    --     미래로 갱신돼 대기 종료선이 계속 밀렸다 — 때리는 한 무한히 늘어난다.
    --   [규칙] 진입 순간의 값을 고정해 그 이후 추가분은 안 기다린다.
    --     연출은 그대로 재생된다(중간에 끊지 않음). 기다리지 않을 뿐이다.
    --   ⚠️ deadline(20초) 은 상한일 뿐 이 문제를 못 막는다. 실측에서 12초를
    --     기다린 뒤에도 새 이펙트가 또 들어왔다 — 상한 안에서도 체감은 "안 끝남"이다.
    local frozen = _G.KillEffectBusyUntil() or 0
    if frozen > deadline then frozen = deadline end
    while os.clock() < frozen do
        task.wait(0.25)
    end
end

-- 📊 라운드 종료 사유 누적 (스톨링 메타 관찰용 — 서버 수명 동안 유지)
local roundEndCounts = {}

-- 📋 [2026-08-26] 라운드 요약용 관측값.
--
-- [왜] "1단계에 절반 죽고, 살아남은 러너와 태거가 비등하게" 가 목표인데,
--   그게 지켜졌는지 판마다 확인할 수단이 없었다. 로그를 눈으로 훑으며
--   타임스탬프를 빼고 킬을 세는 걸 반복했고, 그 과정에서 여러 번 오독했다.
--   → 한 줄로 요약해 목표 대비 자동 채점되게 한다.
-- ⚠️ 값 자체는 밸런스에 영향을 주지 않는다. 관측 전용.
local roundObs = {
    startAt      = 0,   -- 라운드 시작 시각
    stage2At     = 0,   -- 2단계 진입 시각 (0 = 도달 못함)
    runnersTotal = 0,   -- 시작 러너 총원 (유저 + 봇)
    stage2Alive  = 0,   -- 2단계 진입 시점 생존 러너 (다운 포함 실제 머릿수)
    stage2Downed = 0,   -- 그중 다운 상태였던 수
    stage2EffN   = 0,   -- 태거 HP 계산에 쓰인 환산치 (다운은 0.25)
    -- 🔬 [K측정 2026-09-04] 2단계 처치 페이스 관측. 밸런스에 영향 없음.
    s2Downs      = {},  -- { {t=2단계 진입 후 경과초, bot=봇여부, src=가해 아이템}, ... }
    s2Deaths     = 0,   -- 2단계 사망 건수 (다운 10초 경과 또는 처형)
    s2KingDmg    = 0,   -- 킹이 2단계에서 받은 총 피해 (유저·봇 공통 / 출혈·사망 이벤트 제외)
    s2KingHits   = 0,   -- 그 피격 횟수
    s2KingBleed  = 0,   -- 🩸 [2026-09-11] 저주검 출혈 누적. 러너의 타격이 아니므로 따로 센다
    -- 🎯 [계측 2026-09-20] 1단계 명중률 분리. 밸런스에 영향 없음. 두 곳이 채운다:
    --   ItemSpawnHandler.setGlobalCooldown  = 사용이 성공한 유일한 깔때기(호출 10곳 공통)
    --   ItemDamageSystem.processHit         = 히트 확정 지점(내구도 흡수 '직전')
    s1Spawns     = 0,   -- 1단계 아이템 사용 횟수 (쿨을 실제로 소모한 것만)
    s1Hits       = 0,   -- 1단계 유효 히트 (⚠️ 내구도 흡수분 포함 — 그게 요점이다)
}
_G.RoundObs = roundObs   -- Stage2TriggerSystem 이 진입 시각을 기록한다

-- 🔒 [2026-09-04] 승패 예약. 연출을 기다리는 동안 다른 승리 조건이 끼어드는 걸 막는다.
--   [왜 필요] 태거 사망 → 킬이펙트 대기(최대 19초) → endRound 순서인데, 그 대기 창에서
--     점령이 완료되면 그쪽이 먼저 처리돼 승리 '사유'가 뒤바뀐다(실측 23:09 판).
--   [무엇을 하나] ① 게이지 정지 ② roundActive 해제 ③ 예약된 승자 기록.
--     연출 시간 자체는 건드리지 않는다 — 호출부가 그 뒤에 그대로 기다린다.
--   ⚠️ endRound 를 여기서 부르지 않는다. 연출이 끝난 뒤 호출부가 부른다.
--   ⚠️ 이미 예약됐으면 무시한다. 먼저 성립한 조건이 이긴다.
local function lockRoundResult(winner, killerName, reason)
    if roundEnded or pendingResult then return end
    pendingResult = { winner = winner, killerName = killerName, reason = reason }
    roundActive = false                                   -- 타이머·전멸 감시 정지
    if _G.CaptureSystem then _G.CaptureSystem.stop() end   -- 게이지 정지
    print(string.format("🔒 [Round] 승패 확정 (연출 대기 중): %s%s",
        tostring(winner), killerName and (" / " .. killerName) or ""))
end

local function endRound(winner, killerName, voided, reason)
    -- 🔒 [버그수정 2026-09-04] 한 라운드는 한 번만 끝난다.
    --   [증상] 태거 사망(23:09:46)이 감지됐는데 실제 종료 처리는 23:10:05 에야 됐다.
    --     그 19초 동안 라운드가 살아 있어 게이지가 계속 올랐고, 점령 승리가 먼저
    --     처리된 뒤 태거 처치가 또 처리됐다 — 종료가 두 번, 코인도 +180 이 두 번.
    --   [원인] 처형 연출이 4초 걸린다([Punch] start → death). 그 사이 봇은 살아 있는
    --     것으로 세지고 종료 판정이 그걸 기다리는데, 그 대기 창에서 '다른 승리 조건'이
    --     새로 성립할 수 있다. 연출을 줄여도 창이 좁아질 뿐 사라지지 않는다.
    --   [규칙] 승패가 한 번 정해지면 그 뒤 판정은 전부 버린다. 어떤 경로로 늦게
    --     들어와도 안 깨지는 결과 보장형이다 — 09-01 문서의 "제외 목록보다 결과 보장".
    --   ⚠️ roundActive=false 만으로는 못 막는다. 종료 경로들이 각자 자기 조건을 보고
    --     endRound 를 부르지, roundActive 를 먼저 확인하지 않기 때문이다.
    if roundEnded then
        warn(string.format("🔒 [Round] 이미 종료된 라운드에 중복 종료 요청 무시 (winner=%s reason=%s)",
            tostring(winner), tostring(reason)))
        return
    end
    -- 🔒 [2026-09-04] 승패가 예약돼 있으면 그 값이 이긴다.
    --   연출 대기 중에 점령 100% 같은 다른 조건이 endRound 를 부르면 여기서 덮어쓴다.
    --   ⚠️ 무시가 아니라 '치환'이다. 예약자는 연출 뒤 자기가 endRound 를 부르는데,
    --     그때도 이 경로를 지나므로 그냥 막으면 라운드가 영영 안 끝난다.
    if pendingResult then
        if winner ~= pendingResult.winner or reason ~= pendingResult.reason then
            warn(string.format("🔒 [Round] 예약된 승패로 치환: 요청(%s/%s) → 확정(%s/%s)",
                tostring(winner), tostring(reason),
                tostring(pendingResult.winner), tostring(pendingResult.reason)))
        end
        winner     = pendingResult.winner
        killerName = pendingResult.killerName
        reason     = pendingResult.reason
        voided     = false
    end
    roundEnded = true
    roundActive = false
    -- 👑 점령 정지. 어떤 사유로 끝나든 게이지는 멈춰야 한다.
    -- ⚠️ 여기가 모든 종료 경로의 공통 지점이라 한 곳만 걸면 된다.
    if _G.CaptureSystem then _G.CaptureSystem.stop() end
    -- 온보딩 퍼널: 라운드 완주 (아직 서버에 남아 있는 유저 = 중도 이탈 아님)
    if _G.OnboardingFunnel then _G.OnboardingFunnel.roundEnded() end
    -- 종료 사유 판정 (reason 미지정 시 추론)
    local endReason = reason
    if not endReason then
        if voided then endReason = "voided"                              -- 태거 이탈 무효
        elseif winner == "Tagger" then endReason = "elimination"         -- 러너 전멸
        elseif winner == "Runner" and killerName then endReason = "tagger_slain"  -- 태거 처치
        -- ⚠️ [2026-08-25] timeout 은 이제 태거 승리이며 명시적으로 넘긴다.
        --    러너 승리인데 사유가 없으면 점령으로 본다.
        elseif winner == "Runner" then endReason = "capture"             -- 시간초과 생존
        else endReason = "unknown" end
    end
    roundEndCounts[endReason] = (roundEndCounts[endReason] or 0) + 1
    do
        local parts = {}
        for k, v in pairs(roundEndCounts) do parts[#parts + 1] = k .. "=" .. v end
        table.sort(parts)
        print("📊 라운드 종료: " .. endReason .. " | 누적: " .. table.concat(parts, ", "))
    end

    -- 📋 [2026-08-26] 라운드 요약 — 목표 대비 자동 채점
    --   목표: 1단계에 '절반' 처치 → 살아남은 러너와 태거가 비등하게
    -- ⚠️ 봇에게도 내구도를 준 뒤이므로, 여기 숫자는 실제 러너 조건과 같다.
    --   (그전에는 봇이 0칸이라 손으로 2를 나눠야 했고, 그 환산을 잊어 오독했다)
    do
        local now = os.clock()
        local total = roundObs.runnersTotal
        local s1Kills = (total > 0) and (total - roundObs.stage2Alive) or 0
        local s1Len = (roundObs.stage2At > 0 and roundObs.startAt > 0)
            and (roundObs.stage2At - roundObs.startAt) or 0
        local s2Len = (roundObs.stage2At > 0) and (now - roundObs.stage2At) or 0

        local verdict = "?"
        -- 🎯 [2026-09-05] 1단계 목표를 티어별로 나눈다.
        --   [기존] 총원의 절반(11명 → 5.5) 하나로 모든 난이도를 판정했다.
        --   [왜 바꾸나] easy 는 aimError 9 / fireInterval 4.5 라 1단계 60초에 약 13발이다.
        --     목표 5.5 를 맞추려면 명중률 46% 에 다운 전환율 100% 가 필요하다 —
        --     '쉬운 킹'에게 요구하기엔 과한 수치다. 반면 hard 는 2.5초 간격이라 23발이라
        --     같은 목표가 오히려 헐겁다. 하나의 기준이 양쪽 모두에 안 맞았다.
        --   [실측 근거] easy 5판: 8 / 3 / 2 / 3 / 6 → 평균 4.4
        --   ⚠️ 이건 '판정 기준'이지 밸런스 축이 아니다. 난이도 차등은 여전히
        --     aimError·fireInterval 두 축으로만 한다(699행 주석의 원칙 유지).
        --     여기서 바꾸는 건 "그 결과를 어떤 잣대로 읽을 것인가"뿐이다.
        --   ⚠️ 비율로 두는 이유: 총원은 유저 수에 따라 변한다. 절대값으로 박으면
        --     11명 기준에만 맞고 5명 판에서 무의미해진다.
        local TIER_GOAL_RATIO = {
            easy   = 0.36,   -- 11명 → 4.0
            normal = 0.50,   -- 11명 → 5.5 (기존 기준 유지)
            hard   = 0.64,   -- 11명 → 7.0
        }
        local tierName = game:GetService("ReplicatedStorage"):GetAttribute("KingBotTier")
        -- ⚠️ 유저가 킹인 라운드에서는 이 Attribute 가 이전 봇 라운드의 잔재다.
        --   그때는 티어 개념이 없으므로 기존 기준(0.5)으로 돌아간다.
        local ratio = (tierName and TIER_GOAL_RATIO[tierName]) or 0.50
        -- 📡 [2026-09-06] 라이브 텔레메트리 전송. 여기여야 하는 이유:
        --   승자·종료사유·티어가 모두 확정된 뒤이고, 아직 플레이어가 서버에 남아 있다.
        --   (LogCustomEvent 는 Player 인스턴스를 요구한다 — 더 늦으면 못 보낸다)
        --   ⚠️ 위 print 요약과 목적이 다르다. 저건 내가 Studio 에서 읽는 것이고,
        --     이건 라이브에서 수백 판이 쌓여야 답이 나오는 것이다.
        if _G.Telemetry_RoundEnd then
            pcall(_G.Telemetry_RoundEnd, {
                winner = winner, reason = endReason,
                tier = tierName or "기본",
            })
        end

        local goal = total * ratio
        if total > 0 and roundObs.stage2At > 0 then
            -- 목표 ±1명을 적정으로 본다
            if math.abs(s1Kills - goal) <= 1 then verdict = "✅ 적정"
            elseif s1Kills > goal then verdict = "⚠️ 1단계 과함"
            else verdict = "⚠️ 1단계 약함" end
        end

        -- 🎒 [2026-09-15] 로드아웃 열. 두 분기가 공유한다.
        --   [왜] 1단계 처치 수는 인지반경·내구도보다 '킹이 뭘 들고 왔나'에 훨씬 크게 흔들린다.
        --     그런데 그 열이 로그 어디에도 없어서 09-10 정렬표 7판이 전부 판독 불가가 됐다
        --     (기본 굴리기 판과 조합 판이 한 표에 섞여 있는데 구분이 안 된다).
        --     [Spawn] 은 요청 1줄짜리라 판 전체 구성을 주지 않는다 — 20~40줄을 역으로 세야 했다.
        --   ⚠️ _G.LM_getLoadouts 를 쓴다(LoadoutManager, PresetManager 가 이미 소비하는 선례).
        --     pruneExpiredRotation 을 먼저 돌려 '실제로 라운드에 나가는 목록'을 준다 —
        --     인벤 표시값이 아니다. 무료 로테이션 만료분이 걸러진 뒤의 값이어야 맞다.
        --   ⚠️ 봇 킹은 pseudoPlayer(평범한 Lua 테이블)라 그 함수에 넣으면 터진다.
        --     Instance 인지 먼저 보고, 봇이면 티어로 대체한다 — 봇 구성은 TIERS.items 가
        --     정하므로 티어 이름이 곧 로드아웃이다.
        local loadoutTag
        if typeof(currentTagger) == "Instance" and _G.LM_getLoadouts then
            local ok, ld = pcall(_G.LM_getLoadouts, currentTagger)
            local t = ok and ld and ld.tagger
            loadoutTag = (t and #t > 0) and table.concat(t, "·") or "?"
        else
            loadoutTag = "봇(" .. (tierName or "기본") .. ")"
        end

        if roundObs.stage2At > 0 then
            -- 다운자가 있으면 병기한다. "6명 진입" 이 온전한 6명인지
            -- 반쯤 죽은 6명인지가 판정에 결정적이라 숫자만으로는 오독된다.
            local downTag = (roundObs.stage2Downed > 0)
                and string.format("(다운 %d)", roundObs.stage2Downed) or ""
            print(string.format(
                "📋 [RoundSummary] 승자=%s(%s) | 1단계 %.0fs 처치 %d/%d (%s 목표 %.1f) %s | 2단계 %.0fs 진입 %d명%s | 환산 %.2f | 🎒 %s",
                tostring(winner), endReason, s1Len, s1Kills, total,
                tierName or "기본", goal, verdict,
                s2Len, roundObs.stage2Alive, downTag, roundObs.stage2EffN, loadoutTag))

            -- 🔬 [K측정 2026-09-04] 2단계 처치 페이스. 킹의 승리 조건 `T > N x K` 검증용.
            --   [왜 필요한가] 2단계 창은 98~112초인데 킹 생존시간 T 는 7.5~18초다.
            --     타임아웃(=태거 승)에 도달할 수 없으므로 킹의 실질 승리 경로는 전멸뿐이고,
            --     그러면 "러너 1명 처치에 몇 초 걸리나(K)"가 승패를 직접 결정한다.
            --   [읽는 법] `3.1bU/stone` = 진입 후 3.1초, b=봇 U=유저, 가해 아이템.
            --     같은 시각에 여러 건이 몰리면 광역(AoE) 처치다 — K 를 크게 낮추는 요인.
            --   ⚠️ 확인 끝나면 이 do 블록만 지우면 된다. 위 요약 줄은 안 건드렸다.
            do
                local d = roundObs.s2Downs or {}
                -- 🔬 킹이 받은 피해. 유저·봇 킹 공통(Stage2TriggerSystem 이 재산정 직후 훅을 건다).
                --   ⚠️ `[Duel] 킹 피격` 로그는 봇 킹 전용이라 유저가 킹인 판에서는 0줄이다.
                --     그 부재를 '피해 0'으로 읽는 오독을 이 줄이 막는다.
                local kd, kh = roundObs.s2KingDmg or 0, roundObs.s2KingHits or 0
                local kb = roundObs.s2KingBleed or 0
                -- 🩸 [2026-09-11] 출혈을 분리하고 '평균/회'를 같이 찍는다.
                --   봇 평타는 20.0 고정이므로 평균이 20.0 에서 벗어나면 계측이 또 오염된 것이다.
                --   한눈에 반증 가능한 불변식을 로그에 박아 두는 게 목적이다.
                local kingTag = string.format(" | 킹 피해 %.0f (%d회, %.1f/회, %.1f DPS) | 출혈 %.0f",
                    kd, kh, (kh > 0) and (kd / kh) or 0, (s2Len > 0) and (kd / s2Len) or 0, kb)
                if #d == 0 then
                    print(string.format("🔬 [K] 2단계 %.1fs | 다운 0건 — 킹이 한 명도 못 잡았다%s",
                        s2Len, kingTag))
                else
                    local ts, gaps, prev = {}, {}, 0
                    for _, e in ipairs(d) do
                        table.insert(ts, string.format("%.1f%s%s", e.t, e.bot and "b" or "U",
                            (e.src ~= "") and ("/" .. e.src) or ""))
                        table.insert(gaps, string.format("%.1f", e.t - prev))
                        prev = e.t
                    end
                    print(string.format(
                        "🔬 [K] 2단계 %.1fs | 다운 %d건 @ %s | 간격 %s | 평균 K=%.1fs | 사망 %d건%s",
                        s2Len, #d, table.concat(ts, " "), table.concat(gaps, "/"),
                        d[#d].t / #d, roundObs.s2Deaths or 0, kingTag))
                end
            end
        else
            -- 📋 [2026-09-15] 1단계에서 끝난 판도 숫자를 남긴다.
            --   [왜] 예전엔 승자·사유·총원만 찍었다. 그런데 봇 인지반경·아이템 튜닝이
            --     정확히 이 분기(2단계 미도달)에서 판정돼야 하는데 숫자가 없어서,
            --     [Spawn]·💀 줄을 손으로 세야 했다. 그래서 09-10 정렬표에 그 열이 없다.
            --   ⚠️ s1Kills / s1Len 을 그대로 쓰면 안 된다 —
            --     s1Kills = total - stage2Alive 인데 2단계 미도달이면 stage2Alive 가 0 이라
            --     항상 total 이 된다. 전멸 판은 우연히 맞지만 1단계 타임아웃 판에서 거짓말이 된다.
            --     s1Len 도 stage2At > 0 조건이라 여기선 항상 0 이다.
            --   ⚠️ checkRunners() 는 AI 의 '다운'을 사망으로 센다. 종료 정산
            --     (registerDownedAsKills)과 같은 기준이라 두 숫자가 어긋나지 않는다.
            local s1LenNow = (roundObs.startAt > 0) and (now - roundObs.startAt) or 0
            local aliveNow = checkRunners()
            print(string.format(
                "📋 [RoundSummary] 승자=%s(%s) | 1단계 %.0fs 처치 %d/%d (%s 목표 %.1f) | 2단계 미도달 | 🎒 %s",
                tostring(winner), endReason, s1LenNow, total - aliveNow, total,
                tierName or "기본", goal, loadoutTag))
        end

        -- 🎯 [계측 2026-09-20] 1단계 명중률·전환율 분리. ⚠️ 확인 끝나면 이 do 블록만 지운다.
        --   [왜] `처치 0/11` 하나로는 "못 맞혔다"와 "맞혔는데 내구도가 먹었다"가 구분이 안 된다.
        --     처방이 정반대다 — 전자는 조준·장비 축, 후자는 러너 구제 축이다.
        --     실측 2026-09-20 라이브: 바닥 로드아웃(굴리기 3종) 킹이 0/11 이었는데
        --     어느 쪽인지 가를 수단이 로그에 없었다.
        --   [읽는 법] 히트 0 → 조준/장비 문제. 히트는 있는데 처치 0 → 구제 문제.
        --     명중률 기준선: ItemSpawnHandler 292행 "굴리기 3종 86초에 스폰 30 · 명중 27%"
        --     (제작자 기준이다 — 뉴비·모바일은 이보다 낮아야 정상).
        --   ⚠️ 히트는 내구도 흡수분을 **포함**한다. 그게 이 계측의 요점이다.
        --   ⚠️ 2단계 진입 후는 안 센다(stage2At 게이트). 1단계 전용 수치다.
        --   ⚠️ 스폰은 '쿨을 소모한 사용'만 센다. 상한·구역 거부로 쿨을 안 먹은 건 빠진다
        --     (bear_trap 거부 경로 참조) — 실제로 나간 것만 분모에 들어가는 게 맞다.
        do
            local sp = roundObs.s1Spawns or 0
            local ht = roundObs.s1Hits or 0
            print(string.format("🎯 [1단계] 스폰 %d · 히트 %d · 명중 %.0f%%  (처치는 위 요약 줄)",
                sp, ht, (sp > 0) and (ht * 100 / sp) or 0))
        end
    end
    -- (무장해제는 킬 이펙트 '당사자'만: 코핀류의 몸 가로채기 + 다운 무장해제가 담당.
    --  승리 측 무기는 유지 — 전원 회수는 과잉이라 롤백. 후반 정리 루틴이 로비 복귀 시 회수.)

    -- ✅ [원인 확정 2026-09-06] 진단 결과 WalkSpeed 였다.
    --   [실측] 스핀 중 종료한 판 WS=8.0 / 스핀 끝난 뒤 종료한 판 WS=16.0.
    --     PlatformStand=false, Anchored=0, Action 트랙 0개 — 전부 정상이었다.
    --     "포즈가 굳는다"로 보였던 건 걷기 애니가 WalkSpeed 에 맞춰 느리게 재생된 것이다.
    --   [원인] HammerScript 의 startSpin 이 WalkSpeed 를 절반(SPIN_SLOW)으로 낮추는데,
    --     Unequipped 가 `if spinning then return end` 로 정리를 건너뛴다.
    --     "클라가 즉시 재장착한다"는 전제인데, 라운드 종료는 그 전제가 깨지는 경로다.
    --   ⚠️ 이 복구는 안전망이다. 근본 수정은 HammerScript 쪽에 따로 넣었다.
    --     둘 다 두는 이유: 새 스킬이 추가돼도 여기서 잡히고, 스킬 자신도 상태를 정리한다.
    local DIAG_ONLY = false

    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if not DIAG_ONLY and hum and hum.Health > 0 then
            pcall(function()
                hum.PlatformStand = false
                hum.AutoRotate    = true
                hum.WalkSpeed     = 16
                hum.JumpPower     = 50
            end)
            ch:SetAttribute("Stunned", nil)
        end
        if not DIAG_ONLY and ch then
            for _, d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") and d.Anchored then
                    pcall(function() d.Anchored = false end)
                end
            end
            -- 네트워크 소유권 반환 (건틀릿이 서버 소유로 뺏어간 채 끝날 수 있다)
            local root = ch:FindFirstChild("HumanoidRootPart")
            if root then pcall(function() root:SetNetworkOwnershipAuto() end) end
        end
    end

    -- ⛓️ [2026-09-06] 저주 사슬 제거. 모든 종료 경로의 공통 지점이라 여기 둔다 —
    --   킹 처치, 전멸, 타임아웃 어느 쪽으로 끝나도 사슬이 남지 않는다.
    --   [왜 킬이펙트 대기보다 앞인가] 코핀 등 킬이펙트도 사슬을 쓴다. 대기 뒤에 떼면
    --     그 연출 내내 두 사슬이 겹쳐 보인다.
    --   ⚠️ 유저 킹도 여기서 처리된다. 봇 전용 경로(KING 처치됨)만으로는 못 잡는다.
    if _G.ThroneChainsDetach then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then pcall(_G.ThroneChainsDetach, plr.Character) end
        end
        -- ⚠️ TaggerBot 에 getChar 같은 API 가 없다(전수 확인). 봇 킹은 워크스페이스에서
        --   ThroneFallen 표식으로 찾는다 — ThroneFall 이 붙인 그 표식이다.
        for _, m in ipairs(workspace:GetChildren()) do
            if m:IsA("Model") and m:GetAttribute("ThroneFallen") then
                pcall(_G.ThroneChainsDetach, m)
            end
        end
    end

    -- 킬 이펙트(코핀 등) 연출 중이면 완료까지 종료 처리(봇 파괴·텔레포트·화면 전환) 지연.
    -- 모든 종료 경로(태거 사망/전멸/시간초과) 공통 — 이펙트 미재생 시 즉시 통과.
    waitForKillEffects(20)
    -- 🤖 봇 태거(KING) 정리 (봇 모드가 아니면 no-op)
    if _G.TaggerBot and _G.TaggerBot.isActive() then _G.TaggerBot.stop() end
    -- 불꽃 압박 중지 신호
    local stopFireEvent = ReplicatedStorage:FindFirstChild('StopFirePressure')
    if stopFireEvent then stopFireEvent:Fire() end

    -- 라운드 진짜 종료 신호 (StopFirePressure는 Stage 2에서도 발사되므로 분리)
    -- 이 신호는 라운드가 실제로 끝났을 때만 발사됨 (승부 결정 / 모두 사망 등)
    local roundEndedEvent = ReplicatedStorage:FindFirstChild('RoundEnded')
    if roundEndedEvent then roundEndedEvent:Fire() end
    
    if winner == "Tagger" then
        updateAllTimers("King's Victory!")
    elseif winner == "Runner" then
        if killerName then
            updateAllTimers("Runner's Victory!\nEliminated by: " .. killerName)
        else
            updateAllTimers("Runner's Victory!")
        end
    else
        updateAllTimers(voided and ("Round Cancelled" .. string.char(10) .. "King Left") or "Round Finished!")
    end
    -- ── 종료 보상 계산 + 통계 수집 ──────────────────────────────
    local roundResultEvent = ReplicatedStorage:FindFirstChild("RoundResultEvent")
    local stats = {} -- { userId, name, role, coins, kills, revives, survived, won }

    for _, player in ipairs(Players:GetPlayers()) do
        local role = player:GetAttribute("Role")
        if not role then continue end

        local roundCoins   = player:GetAttribute("RoundCoins") or 0
        local roundKills   = player:GetAttribute("RoundKills") or 0
        local roundRevives = player:GetAttribute("RoundRevives") or 0
        local survived     = false
        local won          = false

        if role == "Runner" then
            -- 생존 확인 (체력 > 0)
            local hum = player.Character and player.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                survived = true
            end
            if winner == "Runner" then won = true end

            -- ── 전진 진행도 보상 (최대 +25) ──────────────────────
            -- 기본 참여 5 + 여기서 최대 25 = 종전 20~30 수준 유지.
            -- voided 라운드에서도 지급한다: 태거 이탈은 러너 잘못이 아니고,
            -- 이건 승리 보너스가 아니라 "실제로 전진한 만큼"의 참여 보상이기 때문.
            do
                local prog = player:GetAttribute("RunnerProgress") or 0
                local progCoins = math.floor(prog * 35 + 0.5)   -- 💰 [2026-08-29] 25→35
                if progCoins > 0 then
                    roundCoins = roundCoins + progCoins
                    print(string.format("📋 전진 보상 +%d (진행 %.0f%%): %s", progCoins, prog * 100, player.Name))
                end
            end

            -- 생존 보상 +30 (누적)
            if survived and not voided then
                roundCoins = roundCoins + 40   -- 💰 2단계 도달 30→40
                print("📋 생존 기록 +30:", player.Name)
            end
            -- 러너 승리 보상 차등: 태거 처치(적극 교전 35) > 기본 20 > 시간초과(버티기 15)
            -- 스톨링(도망 승리)의 유인을 줄이고 교전을 보상 (규칙은 그대로 — 시간초과도 승리)
            if won then
                local winBonus = 35   -- 💰 [2026-08-29] 20→35
                if endReason == "tagger_slain" or endReason == "bot_slain" then
                    winBonus = 55
                -- ⚠️ [2026-08-25] timeout 은 이제 태거 승리(버티기 성공)다.
                --    예전엔 러너가 "그냥 시간이 지나서" 이긴 것이라 15 로 낮췄는데,
                --    지금은 태거가 2단계 내내 방어해낸 결과이므로 낮출 이유가 없다.
                elseif endReason == "timeout" then
                    winBonus = 45
                end
                roundCoins = roundCoins + winBonus
                print("📋 러너 승리 기록 +" .. winBonus .. " (" .. endReason .. "):", player.Name)
            end
            -- 부활 보너스는 ReviveSystem이 즉시 누적했음 (RoundCoins에 이미 반영)
            if roundRevives > 0 then
                print("📋 부활 기록 (이미 즉시 지급된 합산): " .. roundRevives .. "회 →", player.Name)
            end

        elseif role == "Tagger" then
            if winner == "Tagger" then won = true end
            -- 태거 킬 코인 합산 (누적)
            if roundKills > 0 then
                local killCoins = roundKills * 30   -- 💰 킬당 20→30
                roundCoins = roundCoins + killCoins
                print("📋 태거 킬 기록 +" .. killCoins .. " (" .. roundKills .. "킬):", player.Name)
            end
            -- 태거 승리 보상 +20 (누적)
            if won then
                roundCoins = roundCoins + 40   -- 💰 완주 20→40
                print("📋 태거 승리 기록 +20:", player.Name)
            end
        end

        player:SetAttribute("RoundCoins", roundCoins)

        table.insert(stats, {
            userId   = player.UserId,
            name     = player.Name,
            role     = role,
            coins    = roundCoins,
            kills    = roundKills,
            aiKills  = player:GetAttribute("RoundAIKills") or 0,  -- 결과창 "(+N bots)" 병기용
            revives  = roundRevives,
            survived = survived,
            won      = won,
            -- 킹슬레이어: 이 러너가 태거에게 막타를 넣었는지 (결과창 배지용).
            -- ⚠️ [2026-08-30] bot_slain 추가. 봇 킹을 잡았을 때 배지가 안 떴다.
            --   [원인] 위 승리 보너스는 `tagger_slain or bot_slain` 둘 다 보는데
            --     여기만 tagger_slain 이었다. 같은 규칙이 두 곳에 있었고 한쪽만 갱신됐다.
            --   ⚠️ 리더보드 Kingslayer 보드는 봇 킬을 집계하지 않는다(별도 기준).
            --     여기는 '결과창 표시' 전용이라 봇도 인정한다 — 60코인을 실제로 받으므로
            --     보상은 주는데 표시가 없으면 유저가 인지하지 못한다.
            kingslayer = ((endReason == "tagger_slain" or endReason == "bot_slain")
                          and killerName == player.Name) or nil,
        })

        -- ── 시즌 리더보드 기록 ──────────────────────────────────
        -- 자격 판정(무효 라운드/봇 태거/저인원)과 보드별 조건은 LeaderboardService가 단독 담당.
        -- 내부에서 task.spawn + pcall 처리하므로 여기서 결과창이 지연되지 않는다.
        if LeaderboardService then
            LeaderboardService.recordRound({
                userId     = player.UserId,
                playerName = player.Name,
                role       = role,
                survived   = survived,
                won        = won,
                roundKills = roundKills,
            }, {
                endReason       = endReason,
                voided          = voided,
                killerName      = killerName,
                userRunnerCount = roundUserRunnerCount,
            })
        end

        -- ── 퀘스트 진행도 갱신 ──────────────────────────────────
        -- 라운드 결산에 모인 정보를 QuestSystem으로 전달.
        if _G.QuestSystem then
            -- 플레이(참여) 1회
            _G.QuestSystem.addProgress(player, "play", 1, role)
            -- 승리
            if won then
                _G.QuestSystem.addProgress(player, "win", 1, role)
            end
            -- 생존(러너)
            if survived and not voided then
                _G.QuestSystem.addProgress(player, "survive", 1, role)
            end
            -- 처치 (태거 킬 + 러너의 태거 처치 모두 RoundKills에 누적됨)
            if roundKills > 0 then
                _G.QuestSystem.addProgress(player, "kill", roundKills, role)
            end
            -- 라운드 중 순수 코인 획득량 (시작 기본값 20/30 제외)
            local baseCoins = (role == "Runner") and 20 or 30
            local earned = roundCoins - baseCoins
            if earned > 0 then
                _G.QuestSystem.addProgress(player, "coinsEarned", earned, role)
            end
            -- 2단계 도달 (Stage2TriggerSystem이 ReachedStage2 속성 세팅)
            if player:GetAttribute("ReachedStage2") then
                _G.QuestSystem.addProgress(player, "reachStage2", 1, role)
            end
        end
    end

    -- [SAVE-BURST] 퀘스트 진행도를 여기서 '한 번만' 저장한다.
    --   addProgress 는 이제 즉시 저장하지 않고 플래그만 세운다(QuestSystem:278).
    --   그대로 두면 플레이어당 6회 쓰기가 발생해 DataStore 쓰기 큐(30개)를 넘긴다.
    --   ⚠️ 플레이어별로 살짝 분산한다. 8명이 같은 프레임에 저장하면
    --      1회로 줄여도 여전히 8회 버스트가 되어 다른 시스템 저장과 겹칠 수 있다.
    --   ⚠️ 플레이어 루프 '바깥'이어야 한다. 안에 두면 분산이 의미가 없다.
    if _G.QuestSystem and _G.QuestSystem.flushDirty then
        task.spawn(function()
            for _, player in ipairs(Players:GetPlayers()) do
                pcall(_G.QuestSystem.flushDirty, player)
                task.wait(0.15)   -- 쓰기 큐가 소화할 시간을 준다
            end
        end)
    end

    -- (결과 전송은 로비 이동 완료 후 아래에서 처리)

    -- [BOARD-REFRESH] 라운드 종료 시 즉시 갱신은 제거했다.
    --   ⚠️ GetSortedAsync 는 Ordered List 한도가 매우 작다(솔로 기준 5+2=7회/분).
    --      보드 4종을 라운드마다 갱신하면 라운드 2분 기준으로 한도에 육박해
    --      "request was added to queue" 경고가 계속 났다(실측 2026-08-22, season1_ 키).
    --   리더보드는 부가적인 전시용이므로 즉시성보다 안정성을 택한다.
    --   → BoardDisplay 의 주기 갱신(REFRESH_INTERVAL)에만 맡긴다.

    -- 🏆 [승패 감상] 로비로 옮기기 전, 승부가 난 '그 자리'에서 결과를 알린다.
    -- ⚠️ 결과창(아래 FireClient)은 텔레포트와 보상 지급을 모두 마친 뒤라
    --    승리 판정에서 약 5.9초 뒤다(실측 2026-08-23: 판정 09.622 → 전송 15.398).
    --    거기에 감상 연출을 걸면 이미 로비로 옮겨진 뒤여서 "이겼다"는 감각이 사라진다.
    --    → 바로 아래 wait(3) 이 마침 '이동 전 여유' 구간이므로 그 직전에 신호를 보낸다.
    --       클라 감상 화면이 2초이므로 이 3초 안에 정확히 들어간다.
    -- ⚠️ stats 를 함께 보낸다. 클라가 내 역할을 알아야 승/패 그림이 갈리는데,
    --    Role 속성은 아래 1553행에서 지워지므로 속성으로는 알 수 없다.
    do
        local vsEvent = ReplicatedStorage:FindFirstChild("VictoryScreenEvent")
        if not vsEvent then
            vsEvent = Instance.new("RemoteEvent")
            vsEvent.Name = "VictoryScreenEvent"
            vsEvent.Parent = ReplicatedStorage
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            vsEvent:FireClient(plr, winner, stats, voided, endReason)
        end
    end

    -- ⚠️ 이 대기는 클라 감상 화면(VictoryScreenClient.HOLD = 3.5)과 한 쌍이다.
    --    이 값이 HOLD 보다 작으면 화면이 떠 있는 중에 로비로 텔레포트되어
    --    "승부가 난 자리에서 결과를 본다"는 의도가 깨진다.
    --    3 → 4.5 (감상 3.5 + 퇴장 여유 1.0). 바꿀 때는 반드시 양쪽을 같이.
    wait(4.5)
    
    -- 모든 플레이어 로비로 + 아이템 정리
    for _, player in ipairs(Players:GetPlayers()) do
        player:SetAttribute("Role", nil)
        if player.Character then
            -- 🛡️ 내구도/게이지 정리. 라운드 종료 시 캐릭터를 리스폰하지 않고
            --    같은 몸으로 로비에 보내므로, 안 지우면 머리 위 게이지가 로비까지 따라간다.
            if _G.DurabilitySystem then
                _G.DurabilitySystem.clear(player.Character)
            end
            -- ⚠️ [STAGE2-TAGGER-SLOW 복원] 2단계에서 감속된 태거를 기본 속도로 되돌린다.
            --    라운드 종료 시 캐릭터를 리스폰하지 않고 같은 몸으로 로비에 보내기 때문에,
            --    이걸 안 하면 감속이 로비까지 따라가 다음 라운드 1단계에도 남는다.
            --    ⚠️ 속성이 있는 경우에만 건드린다. 무조건 16으로 밀면 러너의 스피드 포션
            --       효과까지 같이 지워진다(WalkSpeed 하드코딩이 포션을 잃는 기존 문제와 동일 유형).
            do
                local shum = player.Character:FindFirstChildOfClass("Humanoid")
                if shum and shum:GetAttribute("Stage2Slowed") then
                    shum.WalkSpeed = 16
                    shum:SetAttribute("Stage2Slowed", nil)
                end
            end
            for _, item in ipairs(player.Character:GetChildren()) do
                if item:IsA("Tool") then item:Destroy() end
            end
            -- 러너 프로필 제거
            local head = player.Character:FindFirstChild('Head')
            if head then
                local profile = head:FindFirstChild('RunnerProfile')
                if profile then profile:Destroy() end
            end
            -- 광선 기둥 제거
            if head then
                local beam = head:FindFirstChild('RunnerBeam')
                if beam then beam:Destroy() end
            end
            -- Highlight 제거
            local hl = player.Character:FindFirstChild('RunnerHighlight')
            if hl then hl:Destroy() end
            -- 👑 태거 왕관 제거
            removeCrownFromPlayer(player)
        end
        if player:FindFirstChild('Backpack') then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") then item:Destroy() end
            end
        end
        -- 다운 상태 완전 해제: 로비 이동은 리스폰이 아니라 캐릭터가 유지되므로,
        -- 다운된 채 라운드가 끝나면 Downed 속성 + 재장착 차단 감시가 잔존해
        -- 다음 라운드 지급 무기가 장착 즉시 해제되는 문제 방지.
        if player.Character then
            pcall(function()
                local DS = require(game:GetService("ServerScriptService"):WaitForChild("DownSystem"))
                DS.cancelDeathTimer(player.Character)
                -- ⚠️ 1.0 = 풀피. 이건 부활이 아니라 '라운드 종료 정리'다.
                --   위 주석대로 로비 이동은 리스폰이 아니라 캐릭터가 유지되므로,
                --   기본값(0.5)을 쓰면 다운된 채 끝난 러너만 로비에서 반피로 남는다.
                DS.clearDown(player.Character, 1.0)
            end)
            -- 이중 안전: downInfo가 이미 소실된 채 속성만 남은 엣지도 확실히 소거
            player.Character:SetAttribute("Downed", nil)
        end
        -- 장착 중(캐릭터 안)인 툴도 정리: Backpack만 비우면 손에 든 무기(건틀릿 등)가
        -- 로비까지 살아남아 부착 모델/스킬 UI가 잔재하는 버그 방지.
        -- UnequipTools 먼저(Unequipped 발화 → 무기 스크립트의 부착물/UI 정리 루틴 실행),
        -- 이때 툴이 Backpack으로 돌아가므로 Backpack을 다시 비운다.
        if player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum:UnequipTools() end) end
            for _, item in ipairs(player.Character:GetChildren()) do
                if item:IsA("Tool") then item:Destroy() end
            end
        end
        if player:FindFirstChild('Backpack') then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") then item:Destroy() end
            end
        end
        -- 태거 HP 원복: 라운드 시작 시 유저 러너 수에 비례해 MaxHealth 를 100~500 으로 올려두므로
        -- 로비 복귀 시 기본값(100)으로 되돌린다. 안 하면 다음 라운드/로비에서 깎인 HP가 그대로 남는다.
        -- (러너였던 플레이어도 무해 — 이미 100/100 이면 값 변화 없음)
        if player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                hum.MaxHealth = 100
                hum.Health = 100
                pcall(function() hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged end)
            end
        end
        teleportPlayer(player, lobbySpawn)
    end
    
    -- Noob NPC 정리
    local noob = workspace:FindFirstChild('Noob')
    if noob then
        local npcHead = noob:FindFirstChild('Head')
        if npcHead then
            local profile = npcHead:FindFirstChild('RunnerProfile')
            if profile then profile:Destroy() end
            local npcBeam = npcHead:FindFirstChild('RunnerBeam')
            if npcBeam then npcBeam:Destroy() end
        end
        local npcHL = noob:FindFirstChild('RunnerHighlight')
        if npcHL then npcHL:Destroy() end
        if noob:FindFirstChild('Humanoid') then
            noob.Humanoid.Health = noob.Humanoid.MaxHealth
        end
    end
    local noob2 = workspace:FindFirstChild('Noob2')
    if noob2 then
        local npcHead2 = noob2:FindFirstChild('Head')
        if npcHead2 then
            local profile2 = npcHead2:FindFirstChild('RunnerProfile')
            if profile2 then profile2:Destroy() end
            local npcBeam2 = npcHead2:FindFirstChild('RunnerBeam')
            if npcBeam2 then npcBeam2:Destroy() end
        end
        local npcHL2 = noob2:FindFirstChild('RunnerHighlight')
        if npcHL2 then npcHL2:Destroy() end
        if noob2:FindFirstChild('Humanoid') then
            noob2.Humanoid.Health = noob2.Humanoid.MaxHealth
        end
    end
    npcRunners = {}

    -- 로비 이동 후 2.5초 대기 뒤 결과 화면 표시
    wait(2.5)

    -- ── 코인 일괄 지급 (결과창 표시 직전) ──────────────────────
    if _G.CoinSystem then
        for _, stat in ipairs(stats) do
            local player = Players:GetPlayerByUserId(stat.userId)
            if player then
                local reward = stat.coins
                if _G.Has2xCoins and _G.Has2xCoins(player) then reward = reward * 2 end
                _G.CoinSystem.addCoins(player, reward)
                if _G.BattlePass then
                    _G.BattlePass.addXP(player, _G.BattlePass.ROUND_XP, "round")
                    -- 친구 동시 접속 보너스 (배틀패스 XP, 코인 아님)
                    -- ⚠️ 코인으로 주면 안 된다: 코인은 코스메틱(유한)을 사고 로벅스 상품과
                    --    직접 경쟁하므로, 인플레가 목표 소멸 + 매출 감소로 이어진다.
                    --    배틀패스 XP 는 시즌마다 리셋되고 상한이 있어 어뷰징 이득이 제한된다.
                    if _G.FriendBonus and _G.FriendBonus.grant then
                        _G.FriendBonus.grant(player)
                    end
                end
                print("💰 일괄 지급 +" .. reward .. " →", player.Name, "(" .. stat.role .. (reward > stat.coins and " x2" or "") .. ")")
            end
        end
    end

    -- 결과창 전송
    if roundResultEvent then
        for _, player in ipairs(Players:GetPlayers()) do
            -- 🌊 [2026-09-01] 5번째 인자 hazardKill: 환경(밀려오는 벽 등)이 막타를 냈는가.
            --   [왜 endReason 이 아닌 별도 인자인가] 'bot_slain' 을 정확히 비교하는 곳이
            --     4군데라(보상 +55 차등, 부제, 승리 연출) 새 사유 값을 만들면 전부 놓친다.
            --   ⚠️ 소비 후 반드시 지운다(아래 nil 대입). 안 지우면 다음 라운드가
            --     이전 판 플래그로 잘못된 부제를 띄운다.
            roundResultEvent:FireClient(player, winner, stats, voided, endReason,
                _G.LastKillWasHazard == true)
        end
    end

    _G.LastKillWasHazard = nil  -- ⚠️ 소비 완료. 안 지우면 다음 판이 이전 플래그를 쓴다
    roundCleanupDone = true  -- 메인 루프의 인터미션 타이머 시작 허용
end

-- 👑 [CAPTURE-WIN] 왕좌 점령 완료 → 러너 승리.
-- ⚠️ endRound 정의 이후에 둬야 한다. 위에서 걸면 nil 참조가 된다.
-- ⚠️ 사유를 'capture' 로 따로 잡는다. 보상 서열을 나중에 붙일 수 있게
--    (태거 처치 > 점령 > 시간초과) — 그래야 "사냥이 더 이득, 점령은 안전한 정답"이 된다.
_G.CaptureWin = function()
    if not roundActive then return end
    print("👑 [Capture] 점령 승리 처리")
    endRound("Runner", nil, nil, "capture")
end

-- ── 라운드 중 이탈 처리 (좀비 라운드 방지) ──────────────────────────
-- 태거 이탈 = 라운드 void(참여보상만, 승리/생존 보너스 스킵). 러너 이탈 = 남은 실제 러너 재판정.
Players.PlayerRemoving:Connect(function(leaver)
    if not roundActive then return end
    if leaver == currentTagger then
        print("🚪 태거 이탈 → 라운드 void:", leaver.Name)
        endRound(nil, nil, true)   -- voided: 참여보상 유지 + 승리/생존 보너스 스킵
    else
        -- 러너(또는 무관) 이탈 → 한 프레임 뒤(Parent=nil 확정) 남은 러너 재판정.
        -- checkRunners는 runner.Parent 체크로 이탈자를 자동 제외함.
        task.defer(function()
            if not roundActive then return end
            if checkRunners() == 0 then
                print("🚪 유저 러너 전원 이탈/사망 → 태거 승리")
                registerDownedAsKills()
                endRound("Tagger")
            end
        end)
    end
end)

-- 플레이어 추가 시 UI 생성
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        wait(0.5)
        createTimerUI(player)
        
        -- 사망 감지 (러너 + 태거)
        local humanoid = player.Character:FindFirstChild('Humanoid')
        if humanoid then
            humanoid.Died:Connect(function()
                if not roundActive then return end
                -- 관전 시스템용: 라운드 중 사망한 플레이어를 탈락 표시
                player:SetAttribute("Eliminated", true)

                if player:GetAttribute("Role") == "Runner" then
                    print(player.Name, "Runner died!")
                    -- 💀 [2026-09-02] 조기 사망 측정. 라운드 150초에 1단계가 37~52초라
                    --   초반 사망자는 관전 130~140초 + 라운드 간 대기 34초를 기다린다.
                    --   퍼널은 선형이라 이걸 단계로 못 넣어서 커스텀 이벤트로 뺐다
                    --   (OnboardingFunnel 의 RunnerDied 주석 참조).
                    --   ⚠️ pcall. 애널리틱스가 없어도 라운드 진행은 멈추면 안 된다.
                    if _G.OnboardingFunnel and _G.OnboardingFunnel.runnerDied then
                        pcall(_G.OnboardingFunnel.runnerDied, player)
                    end
                    -- 📡 [2026-09-06] 사망 시각 기록. 위 runnerDied 와 목적이 다르다 —
                    --   저건 '조기 사망했다'는 사실(퍼널용)이고, 이건 '몇 초에 죽었나'다.
                    --   생존:관전 비율을 내려면 시각이 있어야 한다.
                    if _G.Telemetry_Death then pcall(_G.Telemetry_Death, player) end
                    local aliveRunners = checkRunners()
                    print("Alive runners:", aliveRunners)
                    if aliveRunners == 0 then
                        print("All runners eliminated!")
                        registerDownedAsKills()
                        task.wait(2)
                        endRound("Tagger")
                    end
                
                elseif player:GetAttribute("Role") == "Tagger" then
                    print(player.Name, "Tagger died!")
                    -- 처치자 찾기
                    local killerName = "Unknown"
                    local creator = humanoid:FindFirstChild('creator')
                    if creator and creator.Value then
                        killerName = creator.Value.Name
                    end

                    -- AI 러너 막타 판정: 승리는 유저 몫. 처치자가 AI 러너면 러너 승리로 치지 않음.
                    -- (AI는 세션3의 HP 하한 클램프로 애초에 태거를 죽일 수 없지만, 이중 안전장치)
                    local killedByAI = false
                    if creator and creator.Value then
                        local kv = creator.Value
                        -- creator.Value가 AI 모델이거나, AIRunner 속성을 가진 경우
                        if typeof(kv) == "Instance" and kv:IsA("Model") and kv:GetAttribute("AIRunner") then
                            killedByAI = true
                        end
                    end
                    if killedByAI then
                        -- 🎯 1인 태거 모드(유저 러너 0명): AI 하한 해제로 AI가 태거를 죽일 수 있음(긴장감).
                        --    이 경우 AI 막타도 정상 라운드 종료(러너 승리)로 처리한다.
                        local userRunners = 0
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p:GetAttribute("Role") == "Runner" then userRunners += 1 end
                        end
                        -- 🔴 [버그수정 2026-09-20] 조기 return 제거.
                        --   [불변식] 태거가 죽으면 라운드는 반드시 끝난다.
                        --   [증상] 태거 사망 후 라운드가 안 끝나고 타이머 만료 → 킹 승리.
                        --     정당하게 싸운 러너가 패배 처리됐다(실측 누적 timeout=3).
                        --   [원인] 위 2429행 전제 "AI는 하한 클램프로 태거를 못 죽인다"가 낡았다.
                        --     ATTACK_HP_FLOOR_RATIO 는 RunnerBotDriveController.attackTagger
                        --     (농민봇 '근접' 경로)에만 있다. 히어로봇은 무기로 때려 그 함수를
                        --     아예 안 타므로 클램프를 통째로 우회한다.
                        --     3092행이 2026-09-12 에 "히어로가 파이어 블레이드로 막타를 낼 수
                        --     있다"를 실측해놓고 봇 킹 쪽만 고쳤다 — 여기가 안 따라왔다.
                        --   [귀속] killerName="Unknown". 환경 막타가 이미 쓰는 검증된 경로다
                        --     (09-20 11:15 판 실측: Runner/Unknown → tagger_slain → 승리 +55,
                        --     킹슬레이어 배지 없음). 봇 이름을 남기면 결과창 승자가 봇이 된다.
                        --   ⚠️ 봇에겐 +60코인이 안 간다 — AI 모델에 Role 속성이 없어 아래
                        --     `Role == "Runner"` 검사가 false 다(RoundSystem 전수 확인).
                        --   ⚠️ 이 분기는 creator 가 'AIRunner 속성 Model' 일 때만 도달한다.
                        --     유저 막타(creator=Player)·환경 막타(creator 없음)는 안 들어온다.
                        if userRunners > 0 then
                            print("⚔️ 태거가 AI 러너에게 당함 → 러너 승리(막타 귀속 없음)")
                            killerName = "Unknown"
                        else
                            print("⚔️ [1인 태거] AI 러너가 태거 처치 → 라운드 종료")
                        end
                    end

                    -- 처치한 러너에게 +60코인 누적 (즉시 지급 X)
                    if creator and creator.Value then
                        local killer = creator.Value
                        if killer:GetAttribute("Role") == "Runner" then
                            killer:SetAttribute("RoundCoins", (killer:GetAttribute("RoundCoins") or 0) + 60)
                            print("📋 태거 처치 기록 +60:", killer.Name)
                        end
                    end
                    -- ⏳ [2026-08-27] 고정 2초 → 킬이펙트 완료 대기.
                    --   [증상] 태거 사망 시 연출이 끝나기 전에 라운드가 끝났다.
                    --   [원인] task.wait(2) 고정이라 이펙트 길이(코핀 약 17초)와 무관했다.
                    --     endRound 안에도 waitForKillEffects 가 있지만 그건 이 대기 '뒤'라
                    --     결과 판정이 먼저 나가는 순서였다.
                    --   ⚠️ 최소 2초는 유지한다 — 이펙트가 없을 때 즉시 전환되면 너무 급하다.
                    -- 🔒 [버그수정 2026-09-04] 대기에 들어가기 '전에' 승패를 못박는다.
                    --   [증상] 태거 사망(23:09:46) 뒤 이 대기(최대 19초) 동안 라운드가 살아
                    --     있어서 게이지가 계속 올랐고, 점령 승리가 먼저 처리됐다.
                    --     결과는 같은 러너 승이었지만 '사유'가 tagger_slain 이 아니라 capture 로
                    --     기록됐다 — 태거를 잡았는데 점령으로 이긴 것으로 남는다.
                    --   [규칙] 연출 시간은 그대로 둔다(킬이펙트는 승패를 보여주는 시간이자
                    --     주요 수입원이라 자르면 안 된다). 대신 그 창에서 '다른 승리 조건'만
                    --     잠근다 — 늦는 게 문제가 아니라 늦는 동안 끼어드는 게 문제였다.
                    --   ⚠️ lockRoundResult 는 게이지도 함께 멈춘다. 연출 중에 점령 100% 가
                    --     찍히는 그림 자체가 안 나와야 한다.
                    lockRoundResult("Runner", killerName)
                    task.wait(2)
                    waitForKillEffects(20)
                    endRound("Runner", killerName)
                end
            end)
        end
    end)
end)

-- 기존 플레이어 UI
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        createTimerUI(player)
    end
end

-- 메인 게임 루프
task.spawn(function()
    wait(2)
    
    while true do
        -- 킬 이펙트(코핀 등) 연출 중이면 인터미션 진입도 보류 — endRound 스레드와 같은
        -- 시각(busyUntil)에 정렬돼, 연출·보상·인터미션이 겹치지 않고 순차 진행된다.
        waitForKillEffects(20)
        -- endRound 정리(로비 텔레포트 포함)가 끝난 뒤 타이머 시작 (최대 12초 안전 타임아웃)
        do
            local deadline = os.clock() + 12
            while not roundCleanupDone and os.clock() < deadline do
                task.wait(0.1)
            end
        end
        print("\n=== INTERMISSION ===")
        if _G.SetLightingPreset then _G.SetLightingPreset("lobby") end  -- 💡 로비 무드 복귀
        broadcastPhase("intermission")  -- 음악: 로비 BGM으로
        for i = INTERMISSION_TIME, 1, -1 do
            while roundPaused do
                updateAllTimers("⏸️ PAUSED")
                wait(0.5)
            end
            updateAllTimers("Next game in: " .. i)
            wait(1)
        end
        
        -- 이전 라운드 태거 아이템 정리
        -- 톡스박스는 CollisionGroup이 "ToxBox"라 아래 TaggerItems 그물에 안 걸림 → 전용 정리 호출
        if _G.resetToxBox then pcall(_G.resetToxBox) end
        -- 🧍 [2026-09-20] 뉴비 단일 존재 잠금 해제 — 위 resetToxBox 와 같은 짝이다.
        --   [왜] 뉴비 잠금은 인스턴스의 Destroying 에서 풀린다. 아래 표식 그물이 실제로
        --     Destroy 하므로 정상 경로에서는 자동으로 풀리지만, 어떤 이유로든 그게 안 불리면
        --     그 태거는 다음 라운드 내내 뉴비를 못 쓴다("한쪽만 보내면 영구 잠김").
        --   ⚠️ 표식 그물(아래)보다 먼저 불러도 된다 — 이건 테이블·UI 초기화라 순서 무관하다.
        if _G.resetNoobLock then pcall(_G.resetNoobLock) end

        -- 🧹 [버그수정 2026-09-02] 표식(TaggerSpawnedItem) 그물. 이제 이게 주력이다.
        --   [증상] 뉴비가 라운드마다 러너 스폰 지역에 쌓였다(스크린샷으로 수십 개 확인).
        --   [원인] 아래 두 그물은 67종 중 'Wooden Barrel' 하나만 확실히 잡는다.
        --     · 그물①(CollisionGroup=="TaggerItems")은 BasePart 만 지운다. 게다가
        --       ItemNoob·GoldNeonNoob 등은 벽·산과 충돌해야 해서 '의도적으로' Default
        --       그룹을 쓴다(ItemSpawnHandler:1714 주석). 그래서 아예 안 걸린다.
        --     · 그물②의 "Wood Log" 분기는 죽은 코드다 — Wood Log 는 Model 이 아니라
        --       MeshPart 라 IsA("Model") 이 영원히 false 다.
        --   [해결] ItemSpawnHandler 가 스폰 시 두 경로 모두에서 TaggerSpawnedItem 을 붙인다
        --     (조준 레이캐스트 제외용으로 이미 쓰던 표식). 그걸 정리 기준으로도 쓴다.
        --     스킨 변형(GoldenLog·색상 뉴비 등)도 같은 폴더의 별도 템플릿을 같은 경로로
        --     스폰하므로 자동으로 커버된다. 이름 목록 방식은 67종+스킨까지 계속 늘어 유지 불가.
        --   ⚠️ 아래 두 그물을 지우지 않는다. 표식은 스폰된 '최상위 오브젝트'에만 붙으므로
        --     배럴 파열·스톤 분열로 흩어진 파편은 여전히 콜리전 그룹으로만 잡힌다.
        do
            local n = 0
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:GetAttribute("TaggerSpawnedItem") then
                    obj:Destroy()
                    n += 1
                end
            end
            if n > 0 then
                print(string.format("🧹 태거 아이템 표식 정리: %d개", n))
            end
        end

        local PhysicsService = game:GetService('PhysicsService')
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA('BasePart') then
                local ok, gn = pcall(function() return obj.CollisionGroup end)
                if ok and gn == "TaggerItems" then
                    obj:Destroy()
                end
            end
        end
        -- Model 태거 아이템도 정리
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and (obj.Name == "Wooden Barrel" or obj.Name == "Wood Log") then
                obj:Destroy()
            end
        end

        -- 🖐️ 그랩 잔해 정리.
        -- ⚠️ PushTool 의 손/경로는 workspace 에 Anchored 로 붙는데 Debris 타이머가 없고,
        --    그랩 시퀀스가 '정상 종료'될 때만 지워진다. 라운드가 중간에 끝나거나
        --    태거가 죽으면 그 분기를 못 타서 손이 공중에 영구히 남는다(실측 2026-08-23).
        -- ⚠️ 이름으로 지운다. 충돌그룹으로는 못 거른다 — 손은 TaggerItems 가 아니다.
        do
            local GRAB_JUNK = {
                ["_GrabFlyingHand"] = true,
                ["_VishnuGripHand"] = true,
                ["_GrabPath"]       = true,
            }
            local n = 0
            for _, obj in ipairs(workspace:GetChildren()) do
                if GRAB_JUNK[obj.Name] then
                    obj:Destroy()
                    n = n + 1
                end
            end
            if n > 0 then
                print(string.format("🖐️ 그랩 잔해 정리: %d개", n))
            end
        end

        print("🧹 태거 아이템 정리 완료")
        
        local activePlayers = Players:GetPlayers()
        if #activePlayers < 1 then
            print("No players. Waiting...")
            wait(5)
            continue
        end
        
        -- 일시정지 체크 (맵 선택 전)
        while roundPaused do
            updateAllTimers("⏸️ PAUSED")
            wait(0.5)
        end
        -- 맵 선택
        print("=== MAP SELECTION ===")
        local votedMapName = _G.MapVoteSystem.startVote(15)
        print("투표 결과:", votedMapName)
        
        -- 투표 결과를 maps 배열에서 찾기
        local selectedMap = nil
        for _, mapData in ipairs(maps) do
            if mapData.folder.Name == votedMapName then
                selectedMap = mapData
                break
            end
        end
        
        -- 투표 결과가 없거나 맵을 못 찾으면 첫 번째 맵 사용
        if not selectedMap then
            selectedMap = maps[1]
            print("⚠️ 투표 결과 없음, 기본 맵 사용:", selectedMap.name)
        else
            print("✅ 선택된 맵:", selectedMap.name)
        end
        
        -- 🔻 비선택 맵 비활성화: 선택 맵만 workspace, 나머지는 ServerStorage로 빼서
        -- 렌더링·물리·메모리 부담을 줄인다. 부팅 시 map1/map2 + 자식들을 이미 변수로
        -- 잡아둬서 Parent를 옮겨도 참조는 유효. 다음 라운드에 선택되면 자동 복원.
        for _, mapData in ipairs(maps) do
            -- [기본: 양 맵 상시 유지] 대륙 조망·테마 연속성 확보 (성능 측정: 스왑 절약분 소음 이하)
            -- 비상시 workspace 속성 EnableMapSwap=true로 예전 스왑 동작 복귀 가능 (백업 스위치)
            local swapOn = workspace:GetAttribute("EnableMapSwap") == true
            local targetParent = (mapData == selectedMap or not swapOn) and workspace or ServerStorage
            if mapData.folder.Parent ~= targetParent then
                mapData.folder.Parent = targetParent
            end
        end
        -- 💡 맵 무드 라이팅 전환 (map1 청명 낮 / map2 골든아워) — 프리셋 키는 폴더 이름(map1/map2)
        if _G.SetLightingPreset then _G.SetLightingPreset(selectedMap.folder.Name) end
        -- ⚠️ [2026-08-30] 예전 문구는 항상 "비선택 맵은 ServerStorage 보관"이라고 찍었는데
        --   실제로는 EnableMapSwap 이 켜졌을 때만 그렇다. 기본값은 양 맵 상시 workspace 유지다.
        --   이 문구 때문에 "map2 라운드면 map1 은 없겠지"라고 오판하기 쉽다(실제로 그런 일이 있었다).
        --   맵을 이름으로 찾는 코드는 반드시 SetCurrentMap 폴더를 우선 쓸 것.
        print("🗺️ 맵 활성화: " .. selectedMap.name ..
            (workspace:GetAttribute("EnableMapSwap") == true
                and " (스왑 ON — 비선택 맵은 ServerStorage 보관)"
                or  " (스왑 OFF — 양 맵 모두 workspace 유지)"))

        -- TaggerSystem에 맵 알리기
        if setMapEvent then
            setMapEvent:Fire(selectedMap.folder)
        end

        -- 🗺️ [2026-09-07] 클라이언트도 현재 맵을 알 수 있게 속성으로 남긴다.
        --   [왜 필요] SetCurrentMap 은 BindableEvent 라 서버 전용이다. 클라는 받을 채널이
        --     아예 없어서 맵을 구분할 수단이 없었다. 그래서 DragonEntranceClient 가
        --     map1 라운드에도 map2 좌표(Z≈891)로 스켈레톤 드래곤을 날렸다(실측).
        --   [왜 이벤트가 아니라 속성인가] RoundPhase 와 같은 이유다(RoundSystem:250 주석) —
        --     ResetOnSpawn=true 인 UI·나중에 뜨는 클라 스크립트는 이미 발사된 이벤트를
        --     영영 못 받는다. 조회 가능한 상태로 남겨야 새로 뜬 쪽도 읽는다.
        --   ⚠️ SetCurrentMap 을 대체하지 않는다. 서버 10개 시스템은 그대로 그 이벤트를 쓴다.
        --     여기는 '추가'다 — 같은 규칙을 두 곳에 만드는 게 아니라, 없던 채널을 하나 여는 것.
        --   ⚠️ 속성은 즉시 반영이라 Deferred 인 BindableEvent 보다 먼저 도착할 수 있다.
        --     읽기 전용 참조라 순서가 문제되지 않는다.
        ReplicatedStorage:SetAttribute("CurrentMap", selectedMap.folder and selectedMap.folder.Name or nil)
        
        -- 맵 투표 UI 강제 숨기기 (태거 선정 전)
        for _, player in ipairs(Players:GetPlayers()) do
            local playerGui = player:FindFirstChild("PlayerGui")
            if playerGui then
                -- MapVoteGui 완전 제거
                local mapVoteGui = playerGui:FindFirstChild("MapVoteGui")
                if mapVoteGui then
                    -- 모든 자손 요소 완전 투명화 + 숨기기
                    for _, desc in ipairs(mapVoteGui:GetDescendants()) do
                        if desc:IsA("GuiObject") then
                            desc.Visible = false
                            if desc:IsA("Frame") or desc:IsA("TextButton") or desc:IsA("ImageLabel") then
                                desc.BackgroundTransparency = 1
                            end
                        end
                    end
                    mapVoteGui.Enabled = false
                end
                
                -- TimerFrame 숨기기
                local gameUI = playerGui:FindFirstChild("GameUI")
                if gameUI then
                    local timerFrame = gameUI:FindFirstChild("TimerFrame")
                    if timerFrame then
                        timerFrame.Visible = false
                    end
                end
            end
        end
        print("🗳️ 맵 투표 UI 완전 숨김 완료")
        
        -- 술래 선택
        print("\n=== TAGGER SELECTION ===")
        -- ⚠️ [TEST] ForceRunner 처리 - 삭제 시: 이 블록 + _TestForceRunner 스크립트 + _TestForceRunnerGui 삭제
        -- 🔄 참여자 재수집: 맵 투표(15초) 중 입장한 유저도 이번 라운드에 포함.
        -- 수집이 투표 전이라, 1인 대기 중 신규 입장 시 옛 스냅샷(1명)으로 봇전이 시작되고
        -- 신규 유저가 한 라운드를 통째로 관전하게 되는 문제 방지 — 2명이면 정상 태거 선발.
        -- (투표 중 전원 퇴장 시엔 기존 목록 유지 → 기존 퇴장 처리 흐름에 위임)
        do
            local refreshed = Players:GetPlayers()
            if #refreshed >= 1 then activePlayers = refreshed end
        end

        local forceRunnerMode = false
        if _G.ForceRunnerPlayers then
            local filtered = {}
            for _, p in ipairs(activePlayers) do
                if not _G.ForceRunnerPlayers[p.UserId] then
                    table.insert(filtered, p)
                end
            end
            if #filtered >= 1 then
                activePlayers = filtered
            else
                forceRunnerMode = true  -- 전원 ForceRunner → 태거 없이 진행
            end
        end
        -- ⚠️ [TEST] ForceRunner 처리 끝
        -- 🤖 1인 서버 → 태거 봇(KING) 모드: 태거 배정 없이 전원 러너 + 봇이 태거 역할
        --    forceRunnerMode 경로(검증됨)를 재활용해 태거 선정/배치를 스킵한다.
        local botMode = false
        if #activePlayers == 1 and not forceRunnerMode and _G.TaggerBot then
            -- 솔로 역할 선택(SoloRoleClient): "runner"(기본)=KING 봇 상대 러너 / "tagger"=기존 태거+AI 러너 상대
            local soloChoice = activePlayers[1]:GetAttribute("SoloRoleChoice") or "runner"
            if soloChoice == "runner" then
                botMode = true
                forceRunnerMode = true
                print("🤖 [TaggerBot] 1인 서버 (선택: runner) → KING 봇 태거 모드")
            else
                print("👑 [TaggerBot] 1인 서버 (선택: tagger) → 기존 태거 모드 (AI 러너 상대)")
            end
        end
        local tagger = nil
        if not forceRunnerMode then
            -- 🔴 [버그수정 2026-09-20 #3] 왕 후보를 "지금 살아있는 캐릭터가 있는 사람"으로 좁힌다.
            --   [증상] 유령 라운드 — 로비 인원이 전부 맵으로 끌려갔는데 왕도 봇도 없이 전원 러너로
            --     서 있다가, 잠시 뒤 맵 투표 → 태거 선정을 거쳐 정상 라운드가 "다시" 시작됐다.
            --   [기전] 여기서 뽑힌 왕의 teleportPlayerCore 가 실패하면 :2995 가 라운드를 무효화한다.
            --     그런데 러너 텔레포트는 이미 병렬로 발사된 뒤(:2826~)라 러너는 맵에 도착해 있고,
            --     AI 러너 스폰(:3008)은 무효 검사 '뒤'라 봇은 하나도 안 나온다. 그 상태로
            --     배치 대기 상한 18초(:2986)를 버틴다 → "맵 위 · 왕 없음 · 봇 없음 · 전원 러너".
            --     그게 유령 라운드의 정체다. 이어서 endRound(voided) → continue → 다음 사이클이
            --     정상적으로 맵 투표부터 다시 도는 것이 "다시 시작"으로 보인 부분이다.
            --   [왜 여기인가] selectTaggerWithSlot 은 후보를 전혀 거르지 않는다. activePlayers 는
            --     바로 위(:2768)에서 Players:GetPlayers() 로 새로 채워지므로, 맵 투표 중 막 접속해
            --     캐릭터가 아직 없는 사람이나 로비에서 죽어 리스폰 대기 중인 사람도 왕이 된다.
            --     teleportPlayerCore 는 살아있는 캐릭터를 6초씩 2회 기다린 뒤 false 를 낸다.
            --     즉 한 명의 미로드가 서버 전원의 라운드를 날린다 — 단일 실패점이다.
            --   ⚠️ 이건 확률을 낮추는 수리지 봉쇄가 아니다. 선발 연출이 약 14초라 그 사이에
            --     죽으면 여전히 실패한다. 완전 봉쇄는 "실패 시 다른 왕 재추첨"이고 별건으로 남긴다.
            --   ⚠️ 후보가 0명이면 기존 동작(전체 목록)으로 되돌린다. 거름망이 라운드를 아예
            --     못 열게 만드는 쪽이 더 나쁘다("제외 목록보다 결과 보장" — 여기선 결과 = 라운드 개시).
            --   ⚠️ 제외된 사람은 updateTaggerPity 대상에서도 빠진다. 추첨에 없었으니 pity 가
            --     안 오르는 게 맞다(뽑힐 수 있었는데 안 뽑힌 게 아니다).
            --   ⚠️ activePlayers 자체는 건드리지 않는다 — 러너 배치 대상은 그대로다.
            local candidates = {}
            for _, p in ipairs(activePlayers) do
                local c = p.Character
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then table.insert(candidates, p) end
            end
            if #candidates == 0 then
                warn("[배치] 살아있는 왕 후보 0명 — 전체 목록으로 진행(기존 동작)")
                candidates = activePlayers
            elseif #candidates < #activePlayers then
                print(string.format("👑 [왕 후보] %d/%d명 — %d명 제외(캐릭터 미로드·리스폰 대기)",
                    #candidates, #activePlayers, #activePlayers - #candidates))
            end
            tagger = selectTaggerWithSlot(candidates)
            print("Tagger:", tagger.Name)
        else
            print("[TEST] ForceRunner 모드: 태거 없이 러너만 배치")
            showSlotToAll(false)
        end
        
        -- 🔴 [버그수정 2026-09-20 #4] 왕 확정 직전 재검증 — 실패하면 '라운드'가 아니라 '왕'을 바꾼다.
        --   [왜 필요] #3(후보 필터)은 선발 '시작' 시점만 본다. 그런데 선발 연출이 약 14초다
        --     (슬롯 30회 ≈10.2s + 확정 1.2s + 결과 대기 3s). 그 사이에 왕이 죽거나 나가면
        --     teleportPlayerCore 가 실패하고 :2995 가 **서버 전원의 라운드를 통째로 무효화**한다.
        --   [무엇이 이상한가] 실유저 3명이면 대체자가 두 명 서 있는데도 라운드를 버렸다(실측 09-20).
        --     "왕 없는 라운드는 성립 불가"라는 규칙은 맞지만, 결론이 '라운드 폐기'일 이유가 없다.
        --     보장해야 할 결과는 "왕이 선다"지 "이 사람이 왕이 된다"가 아니다.
        --   [왜 여기인가] 이 지점은 아직 아무도 텔레포트되지 않았고 currentRunners 도 비어 있다.
        --     콜리전 그룹·왕관·로드아웃 중 어떤 것도 적용 전이라 **되돌릴 것이 없다**.
        --     배치 루프가 돈 뒤에 교체하려 들면 러너 등록·콜리전을 되감아야 해서 위험하다.
        --   ⚠️ 대체자는 pity/가중치를 거치지 않는다. 비상 경로라 단순함을 택했다 —
        --     여기까지 왔다는 건 이미 라운드가 날아갈 상황이라는 뜻이다.
        --   ⚠️ 슬롯 UI 는 이미 원래 이름으로 닫혔다. 교체는 로그에만 남는다(표시는 별건).
        --   ⚠️ 이래도 안 되는 경우(대체자 0명)는 기존 무효 경로가 그대로 받는다. 제거 아님.
        if tagger and not forceRunnerMode then
            local function aliveNow(p)
                if not p or not p.Parent then return false end
                local c = p.Character
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                return hum ~= nil and hum.Health > 0
            end
            if not aliveNow(tagger) then
                local sub = nil
                for _, p in ipairs(activePlayers) do
                    if p ~= tagger and aliveNow(p) then sub = p; break end
                end
                if sub then
                    warn(string.format("[배치] 왕 %s 선발 직후 사망/이탈 → %s 로 교체 (라운드 유지)",
                        tagger.Name, sub.Name))
                    tagger:SetAttribute("Role", nil)
                    tagger = sub
                else
                    warn("[배치] 왕 " .. tagger.Name .. " 선발 직후 사망/이탈 — 살아있는 대체자 없음")
                end
            end
        end

        currentTagger = tagger
        currentRunners = {}
        
        -- 캐릭터 스케일 정규화 (공정한 히트박스)
        normalizeAllPlayers(activePlayers)
        
        -- 플레이어 배치
        -- ⚠️ "텔레포트 성공 = 참가 확정" 원칙 (MM2 등 라운드 게임 표준).
        --    이전에는 텔레포트를 발사만 하고 즉시 currentRunners 등록/로드아웃 지급을 해서,
        --    낙사·리스폰 지연 등으로 텔레포트가 실패한 플레이어가 로비에 남은 채 러너로 세어졌다:
        --      · checkRunners 가 그를 생존자로 카운트 → 죽지도 나가지도 않으면 라운드가 안 끝남
        --      · 맵에 가지도 않고 참여/생존/승리 코인 수령 → 고의 낙사 코인 파밍 어뷰징
        --    병렬 배치는 유지하되(전원 동시 발사) 루프 뒤에서 완료를 기다려 실패자를 정리한다.
        local placementPending = 0
        local placementClosed = false   -- 대기 상한 후 true — 늦게 성공한 배치가 라운드에 끼어들지 못하게 차단
        local taggerPlaced = true   -- 태거 배치가 없는 모드(봇/ForceRunner)는 통과값 유지
        for _, player in ipairs(activePlayers) do
            if not forceRunnerMode and player == tagger then
                player:SetAttribute("Role", "Tagger")
                taggerPlaced = false
                placementPending += 1
                task.spawn(function()
                    local ok = teleportPlayerCore(player, selectedMap.taggerSpawn)
                    if ok and placementClosed then
                        -- 대기 상한을 넘겨 뒤늦게 성공: 라운드는 이미 무효 판정을 냈다.
                        -- 로비(리스폰 위치)의 캐릭터에 왕관/HP 를 적용하면 안 되므로 여기서 폐기.
                        warn("[배치] 태거 늦은 배치 완료 — 무시:", player.Name)
                        if player.Parent then player:SetAttribute("Role", nil) end
                        placementPending -= 1
                        return
                    end
                    if ok then
                        taggerPlaced = true
                        -- 후속 처리(콜리전/왕관/HP)는 텔레포트 성공 후에 실행한다.
                        -- 재시도 중 캐릭터가 교체될 수 있어, 성공 시점의 캐릭터를 참조해야 한다.
                        -- ✅ 태거 캐릭터 파트에 TaggerCharacter 콜리전 그룹 적용
                        local char = player.Character
                        if char then
                            for _, part in ipairs(char:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CollisionGroup = "TaggerCharacter"
                                end
                            end
                        end
                        -- 👑 태거 왕관 부여
                        attachCrownToTagger(player)
                        -- 👑 태거 HP 산정 — 여기서 '확정'하지 않는다.
                        -- 🚪 [2026-08-29] 실제 확정은 Stage2TriggerSystem.finalizeTaggerHp 가
                        --   '성문 붕괴' 시점에 한다. 여기 계산은 두 가지 이유로 폐기했다.
                        --
                        --   [버그] 이 시점은 AI 러너 스폰 '전'이라, 세는 대상이 이번 라운드
                        --     러너가 아니라 '지난 라운드에 남아 있던 봇'이었다.
                        --     실측 2026-08-29: 1라운드(잔류 0) → HP 150 / 2라운드(잔류 9) → HP 742.
                        --     같은 10명 판인데 값이 달랐다.
                        --   [중복] 생존·다운 검사가 없어 Stage2 쪽 aliveWeight 와 규칙이 달랐다.
                        --     같은 계산이 두 곳에 있으면 한쪽만 고쳐진다.
                        --
                        -- ⚠️ 그럼 1단계 동안 태거 HP 는? 캐릭터 기본값(100)을 그대로 쓴다.
                        --   1단계에는 바리케이드가 러너를 막아 태거가 피해를 받을 경로가 없고
                        --   (곡사포·마법책은 태거 기물이라 러너의 원거리 딜도 없다),
                        --   붕괴 순간 finalizeTaggerHp 가 MaxHealth/Health 를 함께 세운다.
                        -- ⚠️ 되살릴 일이 생기면 반드시 'AI 러너 스폰 이후'로 옮기고
                        --   Stage2 쪽과 같은 aliveWeight 규칙을 쓸 것.
                        -- 밀쳐내기 도구 (PushTool)는 라운드 시작 시 지급하지 않음.
                        -- 러너 1명이라도 ItemSpawnPlate에 도달하면 Stage2TriggerSystem이 지급.
                        -- 1단계 = 통나무 압박, 2단계 = 결투 (밀쳐내기) 단계 분리.
                    end
                    placementPending -= 1
                end)
            else
                player:SetAttribute("Role", "Runner")

                -- 🛡️ 기본 내구도 지급은 아래 '배치 확정' 지점으로 옮겼다(2026-09-02).
                --   여기서는 player.Character 가 nil 이면 조용히 건너뛰어, 캐릭터가
                --   교체 중이던 라운드는 내구도 0 으로 시작했다. 근거는 옮긴 자리의 주석 참조.
                -- 러너는 여러 스폰 후보 중 랜덤으로 분산 스폰 (3군데에 골고루).
                -- playerSpawns 목록이 있으면 그 중 랜덤, 없으면 단일 playerSpawn 폴백.
                local spawnTarget = selectedMap.playerSpawn
                if selectedMap.playerSpawns and #selectedMap.playerSpawns > 0 then
                    spawnTarget = selectedMap.playerSpawns[math.random(1, #selectedMap.playerSpawns)]
                end
                placementPending += 1
                task.spawn(function()
                    local ok = teleportPlayerCore(player, spawnTarget)
                    if ok and placementClosed then
                        -- 대기 상한을 넘겨 뒤늦게 성공: 라운드 진행 중 끼어들면 스냅샷/AI 보충과 어긋난다.
                        warn("[배치] 러너 늦은 배치 완료 — 라운드 제외:", player.Name)
                        if player.Parent then player:SetAttribute("Role", nil) end
                        placementPending -= 1
                        return
                    end
                    if not ok then
                        -- 배치 실패: 이 라운드에서 제외한다.
                        -- Role 해제 → endRound 의 role 필터(if not role then continue)가 참여/생존/승리
                        -- 보상을 통째로 차단하고, currentRunners 미등록이라 생존 카운트에도 안 잡힌다.
                        player:SetAttribute("Role", nil)
                        warn("[배치] 러너 텔레포트 실패 → 라운드 제외:", player.Name)
                        placementPending -= 1
                        return
                    end
                    table.insert(currentRunners, player)

                    -- 🛡️ [버그수정 2026-09-02] 기본 내구도 지급. 첫 1회 피격을 흡수한다.
                    --   [증상] 09:09:53 판 — 유저가 내구도 소모 로그 없이 Wood Log 한 방에 다운.
                    --     같은 판 AI 러너는 전부 '소모 → 다음 히트에 다운' 이었다.
                    --   [원인] 예전 위치(위쪽 Role 지정 직후)는 player.Character 가 nil 이면
                    --     조용히 건너뛰었다. 캐릭터 교체 중이면 그 라운드는 내구도 0 으로 시작한다.
                    --     그 판은 태거 선정~소모품 지급 사이가 0.94초 비어 있었다(정상 1~3ms).
                    --   [왜 여기인가] teleportPlayerCore 성공 = 캐릭터 존재 보장이다.
                    --     nil 분기 자체가 사라진다. AI 는 RoundSystem:688 에서 clone 에 직접
                    --     주므로 원래 이 레이스가 없었다 — 그래서 AI 만 멀쩡했다.
                    --   ⚠️ grant 가 아니라 reset 이다. grant 는 '추가'라 라운드마다 누적된다.
                    --   ⚠️ 간헐적 현상이라 재현을 기다리는 비용이 크다. 그래서 지급 로그를
                    --     남겨 매 라운드 눈으로 확인할 수 있게 한다. DurabilitySystem.absorb 의
                    --     '부여된 적 없음' 경고와 짝이다 — 한쪽은 성공, 한쪽은 실패를 잡는다.
                    if _G.DurabilitySystem and player.Character then
                        _G.DurabilitySystem.reset(player.Character)
                        print(string.format("🛡️ 내구도 지급: %s (%d칸)",
                            player.Name, _G.DurabilitySystem.get(player.Character)))
                    else
                        warn("🛡️ [Durability] 지급 실패 — 캐릭터 없음:", player.Name)
                    end

                    -- (ClassicSword는 라운드 시작이 아니라 2단계 도달 시 Stage2TriggerSystem이 지급)
                    -- 러너 로드아웃 아이템 지급 (소모품 수량 체크) — 배치 확정 후에만 (실패자 소모품 차감 방지)
                    if _G.GetRunnerLoadout then
                        local runnerLoadout = _G.GetRunnerLoadout(player)
                        for _, itemName in ipairs(runnerLoadout) do
                            local itemTemplate = ServerStorage.RunnerItem:FindFirstChild(itemName)
                            if itemTemplate and itemTemplate:IsA("Tool") then
                                -- 지급 우선순위: 영구 소유 → 소모품 수량 → 미지급
                                if _G.OwnsPermanentItem and _G.OwnsPermanentItem(player, itemName) then
                                    -- 영구 SKU 소유(ODM/Ice Bow 영구) → 매판 무상 지급, 차감 없음
                                    itemTemplate:Clone().Parent = player.Backpack
                                    print("♾️ 영구 아이템 지급:", itemName, "→", player.Name)
                                else
                                    local count = _G.GetConsumableCount and _G.GetConsumableCount(player, itemName)
                                    if count == nil then
                                        -- 소모품 데이터 없음(=미구매) → 지급 안 함
                                        print("🚫 미보유(구매 필요):", itemName, "→", player.Name)
                                    elseif count > 0 then
                                        -- 소모품 + 보유 수량 있음 → 지급 + 차감(1라운드권 소멸)
                                        itemTemplate:Clone().Parent = player.Backpack
                                        -- [CONSUMABLE-ONUSE] 훅이 들어간 아이템은 여기서 깎지 않는다.
                                        --   실제 사용 시점에 툴이 _G.MarkConsumableUsed 를 불러 차감한다.
                                        --   (안 쓰고 죽거나 손도 안 대면 소모되지 않음)
                                        if _G.IsOnUseConsumable and _G.IsOnUseConsumable(itemName) then
                                            if _G.BeginConsumableRound then _G.BeginConsumableRound(player, itemName) end
                                            print("🧪 소모품 지급:", itemName, "(보유:", count, ", 사용 시 차감) →", player.Name)
                                        else
                                            if _G.UseConsumable then _G.UseConsumable(player, itemName) end
                                            print("🧪 소모품 지급:", itemName, "(남은:", count - 1, ") →", player.Name)
                                        end
                                    else
                                        print("🚫 소모품 소진:", itemName, player.Name)
                                    end
                                end
                            end
                        end
                    end
                    -- ✅ Runners 콜리전 그룹 적용 (태거 아이템에 안 밀림)
                    if player.Character then
                        for _, part in ipairs(player.Character:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CollisionGroup = "RunnerCharacter"
                            end
                        end
                    end
                    placementPending -= 1
                end)
            end
        end

        -- 전원 배치 완료 대기 (병렬 발사 → 가장 느린 1명 기준. 코어 최악 ~22초지만 통상 즉시. 상한 18초)
        do
            local t0 = os.clock()
            while placementPending > 0 and os.clock() - t0 < 18 do task.wait(0.1) end
            placementClosed = true   -- 이후 완료되는 배치는 성공이라도 라운드에 편입하지 않음
            if placementPending > 0 then
                warn("[배치] 대기 상한 도달 — 미완료 " .. placementPending .. "명은 실패로 간주")
            end
        end

        -- 태거 배치 실패 → 왕이 없는 라운드는 성립 불가. voided(참여보상만 유지, 보너스 없음)로 무효 처리.
        -- ⚠️ 여기는 메인 게임 루프(while true) 직속이므로 return 금지 — continue 로 다음 사이클(인터미션)로.
        if not taggerPlaced then
            warn("[배치] 태거 텔레포트 실패 → 라운드 무효:", tagger and tagger.Name or "?")
            if tagger and tagger.Parent then tagger:SetAttribute("Role", nil) end
            endRound(nil, nil, true)
            continue
        end
        
        -- 러너 머리 위 프로필 + 빛기둥 마커는 클라이언트(PlayerMarkerClient)가
        -- "태거 시점에만" 생성한다. (서버 생성 시 모두에게 보이므로 여기선 만들지 않음)

        -- 🌾 AI 러너(농민 봇) 동적 스폰: 유저 러너 수에 따라 부족분 보충(최소 군중 보장)
        -- AI는 승패 카운트에서 분리(세션1). RunnerBotDriveController가 이동·회피·근접 구동.
        roundUserRunnerCount = #currentRunners  -- 리더보드 자격 게이트용 스냅샷 (AI 제외 실인원)
        spawnAIRunners(#currentRunners, selectedMap.playerSpawn, selectedMap.playerSpawns)

        -- AI 러너 사망 훅: 유저 러너가 0명인 판(솔로 태거 모드)에서는 AI 가 유일한 승패 대상이므로
        -- 마지막 AI 가 죽는 순간 종료 판정이 필요하다. 훅이 없으면 아무도 checkRunners 를 호출하지
        -- 않아 농민봇을 전멸시켜도 라운드가 끝나지 않는다.
        -- (spawnAIRunner 정의부는 checkRunners 보다 위라 그 안에서 연결할 수 없어 여기서 건다)
        if #currentRunners == 0 then
            for model in pairs(aiRunners) do
                local aHum = model and model:FindFirstChildOfClass("Humanoid")
                if aHum then
                    local conn
                    conn = aHum.Died:Connect(function()
                        if conn then conn:Disconnect() conn = nil end
                        if not roundActive then return end
                        local alive = checkRunners()
                        print("AI Runner died! Alive runners:", alive)
                        if alive == 0 then
                            print("All runners eliminated! (AI)")
                            registerDownedAsKills()
                            task.wait(2)
                            if roundActive then endRound("Tagger") end
                        end
                    end)
                end
            end
        end

        -- [NEWBIE-TIER] 누적 라운드 수 증가 + 속성 노출.
        --   ⚠️ 반드시 킹 소환(아래)보다 앞이어야 한다.
        --      TaggerBotSystem.pickTier 가 이 속성을 읽어 신규 유저에게 hard 를 배제하는데,
        --      뒤에 두면 항상 nil 을 읽어 모든 유저가 영구 신규 취급된다.
        --   ⚠️ _G.DataService.get 은 프로필이 아니라 Data 를 직접 반환한다(DataService:65).
        for _, player in ipairs(Players:GetPlayers()) do
            local d = _G.DataService and _G.DataService.get(player)
            if d then
                d.RoundsPlayed = (d.RoundsPlayed or 0) + 1
                player:SetAttribute("RoundsPlayed", d.RoundsPlayed)
            end
        end

        -- 🤖 봇 태거(KING) 스폰: 1인 서버 봇 모드일 때만. 사망 → 러너 승리.
        if botMode and _G.TaggerBot then
            -- [SOLO-HP] botMode 를 명시적으로 넘긴다. TaggerBotSystem 이 이걸 보고
            --   솔로 전용 킹 HP(150)를 쓴다. runnerCount==1 로 추론하면
            --   "다인인데 혼자 남은 경우"와 구분이 안 되어 잘못 적용된다.
            -- 👑 [2026-08-29] 봇 킹 HP 는 유저 태거와 같은 공식(150 × 환산)을 쓴다.
            --   ⚠️ #currentRunners 는 '유저' 러너만 센다. AI 러너는 별도로 스폰되므로
            --     그대로 넘기면 솔로 판에서 항상 1 이 되어 HP 150 이 나온다
            --     (실측 13:47 판: AI 10체가 있는데 "러너 1 × 0.55 → 환산 1.0").
            --   → 실제 전투 인원 = 유저 러너 + AI 러너를 세어 넘긴다.
            local aiRunnerCount = 0
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m:GetAttribute("AIRunner") then
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then aiRunnerCount += 1 end
                end
            end
            local totalRunners = #currentRunners + aiRunnerCount
            local bot = _G.TaggerBot.startForRound(selectedMap.folder, totalRunners, true)
            if bot then
                local bHum = bot:FindFirstChildOfClass("Humanoid")
                if bHum then
                    -- 💀 [버그수정 2026-09-01] Died 가 아니라 HP<=0 시점에 즉시 판정한다.
                    --   [증상] 12:52 판 — 러너가 킹을 죽였는데 'TIME UP → 태거 승리' 로 끝났다.
                    --     41.242  킹 피격 -14 → -2/892      (HP 이미 0 이하)
                    --     41.269  Punch 킬 이펙트 발동
                    --     43.207  === TIME UP → 태거 승리 ===   ← 1.9초 뒤 시간 초과가 먼저
                    --     45.042  [Punch] -> death: KING        ← 3.8초 뒤에야 Died 발생
                    --   [원인] 처형형 킬이펙트는 연출을 위해 task.delay 뒤에 killCharacter 를
                    --     부른다(ItemDamageSystem:316, Punch 는 3.8초). Died 는 그때 발생하므로
                    --     'HP 0' 과 '사망 선언' 사이에 창이 생기고, 그 사이 다른 종료 조건
                    --     (시간 초과·점령)이 끼어들면 승패가 뒤집힌다. 코핀은 연출이 18초라 더 넓다.
                    --   [해결] 승패 판정이 연출을 기다리지 않게 분리한다. HP<=0 즉시 확정하고
                    --     킬이펙트는 그대로 재생되게 둔다(연출 자체는 건드리지 않는다).
                    --   ⚠️ Died 연결도 남긴다. HP 를 거치지 않고 죽는 경로가 있을 수 있어서다.
                    --     kingDeathHandled 로 중복 실행만 막는다.
                    local kingDeathHandled = false
                    local function onKingDown()
                        if kingDeathHandled then return end
                        kingDeathHandled = true
                        if roundActive then
                            -- 👑 [2026-08-30] 막타를 넣은 러너 이름을 찾아 넘긴다.
                            --   [증상] 봇 킹을 잡아도 결과창에 "👑 Kingslayer!" 배지가 안 떴다.
                            --   [원인] endRound 의 killerName 자리에 nil 을 넘기고 있었다.
                            --     배지 조건이 `killerName == player.Name` 이라 절대 참이 안 된다.
                            --     ⚠️ 60코인 보상은 별도 경로(creator 태그)로 정상 지급되고 있었다 —
                            --       "보상은 주는데 표시가 없어" 유저가 인지하지 못하는 상태였다.
                            --   ⚠️ 유저 태거 사망 경로와 같은 방식(creator 태그)을 쓴다.
                            --     한쪽만 고치면 봇전과 실전의 표시가 달라진다.
                            local kName = nil
                            local creator = bHum:FindFirstChild("creator")
                            if creator and creator.Value then kName = creator.Value.Name end

                            -- 🏅 [2026-09-01] creator 가 없으면 '마지막 실제 가해자'로 폴백한다.
                            --   [왜] 물벽(FirePressureSystem)은 creator 태그 없이 TakeDamage 를
                            --     직접 부른다 — 환경 압박이 내구도에 막히면 안 되므로 의도된 동작이다.
                            --     그런데 그 한 방이 막타가 되면 여기서 kName 이 nil 이 되고,
                            --     킬로그·퀘스트·리더보드·승리 화면이 전부 비어버린다.
                            --   [실측 12:14 판] 러너가 892 → 31 (96%)까지 깎았는데 마지막 31 을
                            --     물벽이 가져갔다. 실제로 킹을 잡은 건 러너인데 아무도 인정받지 못했다.
                            --   ⚠️ 순서가 중요하다. creator 가 있으면 그쪽이 항상 우선이다 —
                            --     이건 '진짜 막타가 없을 때'만 쓰는 폴백이다.
                            --   ⚠️ 유효 시간(CREDIT_WINDOW)·생존 여부는 TaggerBot 쪽에서 검사한다.
                            --     여기서는 결과만 받는다.
                            local viaFallback = false
                            if not kName and _G.TaggerBot and _G.TaggerBot.getLastAttackerName then
                                local ok, nm = pcall(_G.TaggerBot.getLastAttackerName)
                                if ok and nm then kName = nm ; viaFallback = true end
                            end

                            -- ⛓️ [2026-09-06] 사슬 먼저 뗀다. 킬이펙트(코핀 등)도 사슬을
                            --   쓰므로 겹치면 분간이 안 되고, 저주는 '살아 있는 왕'을
                            --   묶는 것이라 죽은 뒤엔 의미가 없다.
                            --   ⚠️ ThroneFallReset 은 다음 라운드 시작에 불려서 너무 늦다.
                            if _G.ThroneChainsDetach then
                                pcall(_G.ThroneChainsDetach, bot)
                            end

                            -- ⚠️ [2026-09-12] 로그 문구는 아래 aiFinisher 판정 뒤에 확정한다.
                            --   여기서 바로 찍으면 AI 막타도 "환경 막타"로 남아 로그가 거짓말을 한다.
                            local killerLine = kName
                                and (" (막타: " .. kName .. ")")
                                or " (막타 불명)"

                            -- 🌊 [2026-09-01] 환경(hazard) 막타면 사유를 갈라 보낸다.
                            --   [왜] 결과창 부제가 "You brought down the King" 으로 뜨는데,
                            --     실제로는 러너가 아니라 밀려오는 벽이 마지막을 가져간 경우가 있다.
                            --     실측(12:14 판): 러너 96% / 벽 4% 인데 화면엔 아무 단서도 없어
                            --     "이게 내 승리가 맞나?" 라는 애매함만 남았다.
                            --   [왜 'hazard' 인가] map1 은 물벽, map2 는 불꽃벽이고 맵이 늘면 또 는다.
                            --     요소별로 사유를 만들면 맵마다 문구를 추가해야 하므로 하나로 묶는다.
                            --     tox_box·낙사 등 다른 환경 요소가 붙어도 이 사유를 재사용한다.
                            --   ⚠️ endReason 을 새 값으로 바꾸지 않는다. 'bot_slain' 을 정확히 비교하는 곳이
                            --     4군데 있어(RoundSystem 보상 차등 +55, RoundResultClient 부제,
                            --     VictoryScreenClient 연출), 새 값을 넣으면 전부 조건을 놓친다.
                            --     특히 보상은 +55 → +35 로 조용히 깎인다.
                            --     그래서 사유는 그대로 두고 '별도 플래그'로만 알린다.
                            --   ⚠️ 승패도 바꾸지 않는다. 러너 승리 그대로고 '어떻게 이겼는지'만 알린다.
                            --
                            -- 🤖 [2026-09-12] AI 막타를 환경 막타와 분리한다.
                            --   [왜] 히어로봇이 무기를 들기 전에는 "creator 없는 피해 = 환경"이 참이었다.
                            --     지금은 히어로가 파이어 블레이드로 막타를 낼 수 있어 제3의 경우가 생겼다.
                            --     실측 12:24 판 — 히어로봇이 킹을 잡았는데 결과창이 "환경 막타"로 떴다.
                            --   [구분] creator 자체가 없으면 환경(물벽·불기둥),
                            --     creator 는 있는데 Player 가 아니면 AI(히어로봇·농민봇).
                            --   ⚠️ 킬 이펙트는 두 경우 다 안 나온다(_G.GetKiller 가 AI 를 nil 로 돌린다).
                            --     그건 의도된 설계다 — "봇이 잡았는데 유저 이펙트가 나오는" 건 거짓말이다.
                            --     여기서 가르는 건 '결과창 문구'뿐이다.
                            local aiFinisher = false
                            do
                                local bh = bot and bot:FindFirstChildOfClass("Humanoid")
                                local cr = bh and bh:FindFirstChild("creator")
                                if cr and cr.Value and not cr.Value:IsA("Player") then
                                    aiFinisher = true
                                end
                            end
                            _G.LastKillWasHazard = viaFallback and not aiFinisher

                            -- 🤖 이제 세 경우가 갈렸으므로 로그를 확정한다.
                            if kName and viaFallback then
                                killerLine = " (막타: " .. kName ..
                                    (aiFinisher and " / AI 막타 → 직전 가해자 인정"
                                                or " / 환경 막타 → 직전 가해자 인정") .. ")"
                            end
                            print("🤖 KING 처치됨 → 러너 승리" .. killerLine)

                            -- ⚠️ 승패를 '먼저' 잠근 뒤 연출 대기에 들어간다.
                            --   [왜] 아래 task.wait(2)는 결과창 전 호흡용인데, 그 2초 동안
                            --     roundActive 가 true 로 남아 있으면 시간 초과 감시가
                            --     그 사이에 끼어들어 태거 승리로 끝낼 수 있다.
                            --     HP<=0 즉시 판정으로 창을 3.8초 → 2초로 줄였을 뿐,
                            --     구조적 구멍은 그대로 남는다.
                            --   [해결] roundActive 를 지금 내려 다른 종료 경로를 봉쇄한다.
                            --     endRound 도 첫 줄에서 같은 일을 하므로 중복 대입은 무해하다.
                            roundActive = false

                            task.wait(2)
                            endRound("Runner", kName, nil, "bot_slain")
                        end
                    end

                    -- ⚠️ 두 경로 모두 연결한다. HealthChanged 가 정상 경로이고,
                    --   Died 는 HP 를 거치지 않는 예외 경로용 안전망이다.
                    bHum.HealthChanged:Connect(function(h)
                        if h <= 0 then task.spawn(onKingDown) end
                    end)
                    bHum.Died:Connect(function() task.spawn(onKingDown) end)
                    -- 연결 시점에 이미 죽어 있을 가능성(경합)도 막는다.
                    if bHum.Health <= 0 then task.spawn(onKingDown) end
                end
            else
                warn("[TaggerBot] 봇 스폰 실패 — 라운드는 계속 (태거 없음)")
            end
        end

        -- Noob NPC 러너 참여
        npcRunners = {}
        -- 🤖 봇 모드(솔로 러너)에서는 테스트 Noob 자동 편입 스킵 (checkRunners 승패 오염 방지: Studio에서 _TestRigBoot이 Noob 복원함)
        local noob = (not botMode) and workspace:FindFirstChild('Noob') or nil
        if noob and noob:FindFirstChild('Humanoid') then
            noob.Humanoid.MaxHealth = 100
            noob.Humanoid.Health = 100
            -- ⚠️ npcRunners 등록 제거 (2026-08): Noob 은 Studio 전용 테스트 더미인데
            --    승패 카운트에 들어가서, 농민봇(AI 러너)을 전멸시켜도 이 더미가 살아있으면
            --    라운드가 끝나지 않았다. AI 러너 시스템 도입 전의 잔재.
            --    더미는 히트박스/이펙트 테스트용으로 그대로 두되 승패에는 관여하지 않는다.
            --    (라이브에서는 _TestRigBoot 의 IsStudio 게이트로 애초에 존재하지 않음)
            -- ✅ Runners 콜리전 그룹 적용
            for _, part in ipairs(noob:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CollisionGroup = "RunnerCharacter"
                end
            end
            
            -- Noob 프로필 + 광선 기둥
            local npcHead = noob:FindFirstChild('Head')
            if npcHead then
                local existing = npcHead:FindFirstChild('RunnerProfile')
                if existing then existing:Destroy() end
                local existingBeam = npcHead:FindFirstChild('RunnerBeam')
                if existingBeam then existingBeam:Destroy() end
                -- 프로필
                local billboard = Instance.new('BillboardGui')
                billboard.Name = 'RunnerProfile'
                billboard.Size = UDim2.new(10, 0, 10, 0)
                billboard.StudsOffset = Vector3.new(0, 52, 0)
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = 2000
                local frame = Instance.new('Frame')
                frame.Size = UDim2.new(1, 0, 1, 0)
                frame.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
                frame.Parent = billboard
                local corner = Instance.new('UICorner')
                corner.CornerRadius = UDim.new(1, 0)
                corner.Parent = frame
                local stroke = Instance.new('UIStroke')
                stroke.Color = Color3.fromRGB(0, 0, 0)
                stroke.Thickness = 2
                stroke.Parent = frame
                local label = Instance.new('TextLabel')
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Text = 'NPC'
                label.TextColor3 = Color3.fromRGB(0, 0, 0)
                label.TextScaled = true
                label.Font = Enum.Font.GothamBold
                label.Parent = frame
                billboard.Parent = npcHead
                -- 광선 기둥
                local beamPart = Instance.new('Part')
                beamPart.Name = 'RunnerBeam'
                beamPart.Anchored = false
                beamPart.CanCollide = false
                beamPart.Transparency = 1
                beamPart.Size = Vector3.new(0.1, 0.1, 0.1)
                beamPart.CFrame = npcHead.CFrame
                beamPart.Parent = npcHead
                local weld = Instance.new('WeldConstraint')
                weld.Part0 = npcHead
                weld.Part1 = beamPart
                weld.Parent = beamPart
                local att0 = Instance.new('Attachment')
                att0.Position = Vector3.new(0, 0, 0)
                att0.Parent = beamPart
                local att1 = Instance.new('Attachment')
                att1.Position = Vector3.new(0, 50, 0)
                att1.Parent = beamPart
                local beam = Instance.new('Beam')
                beam.Attachment0 = att0
                beam.Attachment1 = att1
                beam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 0))
                beam.LightEmission = 1
                beam.LightInfluence = 0
                beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.8)})
                beam.Width0 = 3
                beam.Width1 = 0.5
                beam.FaceCamera = true
                beam.Parent = beamPart
            end
            
            -- Noob 사망 감지
            local npcHumanoid = noob.Humanoid
            local deathConn
            deathConn = npcHumanoid.Died:Connect(function()
                if roundActive then
                    print('Noob NPC died!')
                    local aliveRunners = checkRunners()
                    if aliveRunners == 0 then
                        task.wait(2)
                        endRound('Tagger')
                    end
                end
                deathConn:Disconnect()
            end)
            
            print('🤖 Noob NPC 러너 참여!')
        end

        -- Noob2 NPC 러너 참여
        local noob2 = (not botMode) and workspace:FindFirstChild('Noob2') or nil
        if noob2 and noob2:FindFirstChild('Humanoid') then
            noob2.Humanoid.MaxHealth = 100
            noob2.Humanoid.Health = 100
            -- npcRunners 등록 제거 (위 Noob 과 동일 사유 — 테스트 더미는 승패 무관)
            -- ✅ Runners 콜리전 그룹 적용
            do
                for _, part in ipairs(noob2:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CollisionGroup = "RunnerCharacter"
                    end
                end
            end
            -- Noob2 프로필
            local npcHead2 = noob2:FindFirstChild('Head')
            if npcHead2 then
                local existing2 = npcHead2:FindFirstChild('RunnerProfile')
                if existing2 then existing2:Destroy() end
                local existingBeam2 = npcHead2:FindFirstChild('RunnerBeam')
                if existingBeam2 then existingBeam2:Destroy() end
                local billboard2 = Instance.new('BillboardGui')
                billboard2.Name = 'RunnerProfile'
                billboard2.Size = UDim2.new(10, 0, 10, 0)
                billboard2.StudsOffset = Vector3.new(0, 52, 0)
                billboard2.AlwaysOnTop = true
                billboard2.MaxDistance = 2000
                local frame2 = Instance.new('Frame')
                frame2.Size = UDim2.new(1, 0, 1, 0)
                frame2.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
                frame2.Parent = billboard2
                local corner2 = Instance.new('UICorner')
                corner2.CornerRadius = UDim.new(1, 0)
                corner2.Parent = frame2
                local stroke2 = Instance.new('UIStroke')
                stroke2.Color = Color3.fromRGB(0, 0, 0)
                stroke2.Thickness = 2
                stroke2.Parent = frame2
                local label2 = Instance.new('TextLabel')
                label2.Size = UDim2.new(1, 0, 1, 0)
                label2.BackgroundTransparency = 1
                label2.Text = 'NPC'
                label2.TextColor3 = Color3.fromRGB(0, 0, 0)
                label2.TextScaled = true
                label2.Font = Enum.Font.GothamBold
                label2.Parent = frame2
                billboard2.Parent = npcHead2
                -- 광선 기둥
                local beamPart2 = Instance.new('Part')
                beamPart2.Name = 'RunnerBeam'
                beamPart2.Anchored = false
                beamPart2.CanCollide = false
                beamPart2.Transparency = 1
                beamPart2.Size = Vector3.new(0.1, 0.1, 0.1)
                beamPart2.CFrame = npcHead2.CFrame
                beamPart2.Parent = npcHead2
                local weld2 = Instance.new('WeldConstraint')
                weld2.Part0 = npcHead2
                weld2.Part1 = beamPart2
                weld2.Parent = beamPart2
                local att0_2 = Instance.new('Attachment')
                att0_2.Position = Vector3.new(0, 0, 0)
                att0_2.Parent = beamPart2
                local att1_2 = Instance.new('Attachment')
                att1_2.Position = Vector3.new(0, 50, 0)
                att1_2.Parent = beamPart2
                local beam2 = Instance.new('Beam')
                beam2.Attachment0 = att0_2
                beam2.Attachment1 = att1_2
                beam2.Color = ColorSequence.new(Color3.fromRGB(255, 220, 0))
                beam2.LightEmission = 1
                beam2.LightInfluence = 0
                beam2.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.8)})
                beam2.Width0 = 3
                beam2.Width1 = 0.5
                beam2.FaceCamera = true
                beam2.Parent = beamPart2
            end
            -- Noob2 사망 감지
            local npcHumanoid2 = noob2.Humanoid
            local deathConn2
            deathConn2 = npcHumanoid2.Died:Connect(function()
                if roundActive then
                    print('Noob2 NPC died!')
                    local aliveRunners = checkRunners()
                    if aliveRunners == 0 then
                        task.wait(2)
                        endRound('Tagger')
                    end
                end
                deathConn2:Disconnect()
            end)
            print('🤖 Noob2 NPC 러너 참여!')
        end

        -- Noob3 NPC 러너 참여
        local noob3 = (not botMode) and workspace:FindFirstChild('Noob3') or nil
        if noob3 and noob3:FindFirstChild('Humanoid') then
            noob3.Humanoid.MaxHealth = 100
            noob3.Humanoid.Health = 100
            -- npcRunners 등록 제거 (위 Noob 과 동일 사유 — 테스트 더미는 승패 무관)
            -- ✅ Runners 콜리전 그룹 적용
            do
                for _, part in ipairs(noob3:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CollisionGroup = "RunnerCharacter"
                    end
                end
            end
            -- Noob3 프로필
            local npcHead3 = noob3:FindFirstChild('Head')
            if npcHead3 then
                local existing3 = npcHead3:FindFirstChild('RunnerProfile')
                if existing3 then existing3:Destroy() end
                local existingBeam3 = npcHead3:FindFirstChild('RunnerBeam')
                if existingBeam3 then existingBeam3:Destroy() end
                local billboard3 = Instance.new('BillboardGui')
                billboard3.Name = 'RunnerProfile'
                billboard3.Size = UDim2.new(10, 0, 10, 0)
                billboard3.StudsOffset = Vector3.new(0, 52, 0)
                billboard3.AlwaysOnTop = true
                billboard3.MaxDistance = 2000
                local frame3 = Instance.new('Frame')
                frame3.Size = UDim2.new(1, 0, 1, 0)
                frame3.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
                frame3.Parent = billboard3
                local corner3 = Instance.new('UICorner')
                corner3.CornerRadius = UDim.new(1, 0)
                corner3.Parent = frame3
                local stroke3 = Instance.new('UIStroke')
                stroke3.Color = Color3.fromRGB(0, 0, 0)
                stroke3.Thickness = 2
                stroke3.Parent = frame3
                local label3 = Instance.new('TextLabel')
                label3.Size = UDim2.new(1, 0, 1, 0)
                label3.BackgroundTransparency = 1
                label3.Text = 'NPC'
                label3.TextColor3 = Color3.fromRGB(0, 0, 0)
                label3.TextScaled = true
                label3.Font = Enum.Font.GothamBold
                label3.Parent = frame3
                billboard3.Parent = npcHead3
                -- 광선 기둥
                local beamPart3 = Instance.new('Part')
                beamPart3.Name = 'RunnerBeam'
                beamPart3.Anchored = false
                beamPart3.CanCollide = false
                beamPart3.Transparency = 1
                beamPart3.Size = Vector3.new(0.1, 0.1, 0.1)
                beamPart3.CFrame = npcHead3.CFrame
                beamPart3.Parent = npcHead3
                local weld3 = Instance.new('WeldConstraint')
                weld3.Part0 = npcHead3
                weld3.Part1 = beamPart3
                weld3.Parent = beamPart3
                local att0_3 = Instance.new('Attachment')
                att0_3.Position = Vector3.new(0, 0, 0)
                att0_3.Parent = beamPart3
                local att1_3 = Instance.new('Attachment')
                att1_3.Position = Vector3.new(0, 50, 0)
                att1_3.Parent = beamPart3
                local beam3 = Instance.new('Beam')
                beam3.Attachment0 = att0_3
                beam3.Attachment1 = att1_3
                beam3.Color = ColorSequence.new(Color3.fromRGB(255, 220, 0))
                beam3.LightEmission = 1
                beam3.LightInfluence = 0
                beam3.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.8)})
                beam3.Width0 = 3
                beam3.Width1 = 0.5
                beam3.FaceCamera = true
                beam3.Parent = beamPart3
            end
            -- Noob3 사망 감지
            local npcHumanoid3 = noob3.Humanoid
            local deathConn3
            deathConn3 = npcHumanoid3.Died:Connect(function()
                if roundActive then
                    print('Noob3 NPC died!')
                    local aliveRunners = checkRunners()
                    if aliveRunners == 0 then
                        task.wait(2)
                        endRound('Tagger')
                    end
                end
                deathConn3:Disconnect()
            end)
            print('🤖 Noob3 NPC 러너 참여!')
        end
        
        roundActive = true
roundEnded = false   -- 🔒 [2026-09-04] 새 라운드 = 종료 가드 해제. 이 줄이 빠지면 라운드가 안 끝난다.
pendingResult = nil  -- 🔒 승패 예약도 함께 해제. 안 지우면 다음 라운드가 즉시 끝난 것으로 취급된다.
        roundCleanupDone = false

        -- 온보딩 퍼널: 라운드 시작 (신규 유저 이탈 지점 측정)
        if _G.OnboardingFunnel then _G.OnboardingFunnel.roundStarted() end

        -- ── 라운드 킬 카운터 + 참여 코인 초기화 (지급은 라운드 종료 시) ──
        for _, player in ipairs(Players:GetPlayers()) do
            local role = player:GetAttribute("Role")
            player:SetAttribute("RoundKills", 0)
            player:SetAttribute("RoundAIKills", 0)
            -- ⚠️ 차징 강화 단계도 초기화. 안 하면 지난 라운드의 빨간 손으로 시작한다.
            -- ⚠️ 디버그로 고정한 단계는 유지한다(_ChargeStageLocked).
            --    테스트 중 /stage2 를 눌러도 라운드 시작에 1로 돌아가면
            --    확인이 불가능하다.
            if not player:GetAttribute("_ChargeStageLocked") then
                player:SetAttribute("PushChargeStage", 1)
                if player.Character then
                    player.Character:SetAttribute("PushChargeStage", 1)
                end
            end  -- AI 러너 처치 수 (결과창 병기용, 리더보드 미반영)

            -- 👑 [2026-09-15] 몸집 강화 원복.
            --   [증상] 라운드가 끝나도 킹이 커진 채로 남았다(실측 09-15).
            --   [원인] normalizeAllPlayers 는 **R15 스케일 Value 만** 1 로 되돌린다.
            --     R6 는 파트 Size 와 상대 위치를 직접 곱했으므로 되돌리는 주체가 없었다.
            --     그리고 KingScale / _KingScaleApplied 속성도 그대로 남아,
            --     다음 라운드 무기 확대(Stage2TriggerSystem)가 잘못된 배율로 걸린다.
            --   ⚠️ 속성만 지우면 R6 의 커진 파트는 그대로다. 리스폰으로 캐릭터가
            --     새로 생기면 크기는 초기화되지만, 라운드 사이에 리스폰이 없는 경로도 있다.
            --     그래서 **속성을 지우고, 살아 있는 R6 캐릭터는 직접 되돌린다.**
            do
                local ch = player.Character
                if ch then
                    local applied = ch:GetAttribute("_KingScaleApplied")
                    local hum = ch:FindFirstChildOfClass("Humanoid")
                    if applied and applied > 1.001 and hum
                       and hum.RigType ~= Enum.HumanoidRigType.R15 then
                        local root = ch:FindFirstChild("HumanoidRootPart")
                        if root then
                            local step = 1 / applied
                            local origin = root.Position
                            local snap = {}
                            for _, p in ipairs(ch:GetDescendants()) do
                                if p:IsA("BasePart") then snap[#snap + 1] = { p, p.CFrame } end
                            end
                            for _, e in ipairs(snap) do
                                local p, cf = e[1], e[2]
                                p.Size = p.Size * step
                                local rel = cf.Position - origin
                                p.CFrame = CFrame.new(origin + rel * step) * (cf - cf.Position)
                            end
                            -- ⚠️ 여기가 찍히면 RoundStateResetServer 가 못 받았다는 뜻이다
                            --   (사망 상태로 라운드 종료 등). 이중 그물의 바깥쪽이 작동한 것.
                            print(string.format("👑 [KingScale] 라운드시작 원복 ×%.2f (%s)",
                                applied, player.Name))
                        end
                    end
                    ch:SetAttribute("_KingScaleApplied", nil)
                    ch:SetAttribute("KingScale", nil)
                end
            end
            player:SetAttribute("RoundRevives", 0)  -- 부활 카운트 초기화
            player:SetAttribute("ReachedStage2", nil)  -- 퀘스트용 2단계 도달 플래그 초기화
            -- 참여 보상: 태거 30 고정 / 러너는 기본 15 + 진행도 비례 최대 35 (결산 시 가산).
            -- 💰 [2026-08-29] 라운드 보상 상향 세트. 하루 코인의 14% 뿐이던 라운드 비중을
            --   26% 로 올려 "잘한 판과 못한 판의 차이"가 체감되게 한다.
            --   잘한 판 115→205 / 못한 판 40→55 (격차 2.9배→3.7배).
            -- ⚠️ 러너를 시간이 아니라 "전진 거리"로 재는 이유:
            --    시간 비례는 숨어서 버티는 소극적 플레이가 최적이 되어 언덕 돌파 동기를 해친다.
            --    거리 비례는 게임 목표(전진)와 보상이 일치하고, 2단계 직전에 죽은 러너도
            --    거의 만점을 받는 반면 잠수·즉사 어뷰징은 0에 수렴한다.
            player:SetAttribute("RoundCoins", role == "Runner" and 15 or 30)   -- 💰 [2026-08-29] 러너 5→15 (태거 30 대비 6배 격차 완화)
            player:SetAttribute("RunnerProgress", 0)  -- 도달 진행률 0~1 (러너만 사용)
            player:SetAttribute("Eliminated", nil)   -- 관전 시스템용: 탈락 표시 초기화
            -- [NEWBIE-TIER] 누적 라운드 수 증가 + 속성 노출.
            --   TaggerBotSystem.pickTier 가 이 값을 보고 신규 유저에게 hard 를 배제한다.
            --   ⚠️ 프로필이 아직 로드 전이면 조용히 건너뛴다(킥 대신). 그 라운드는
            --      카운트가 안 올라가지만, 데이터 유실보다 낫고 다음 라운드에 복구된다.
            -- [NEWBIE-TIER] 실제 증가는 킹 소환 앞(2148행 부근)으로 옮겼다.
            --   여기서 또 올리면 라운드당 2씩 증가해 신규 보호가 절반 기간만 적용된다.
            print("📋 참여 기록:", player.Name, role, "기본코인:", role == "Runner" and 15 or 30)
        end

        -- ── 러너 전진 진행도 추적 ────────────────────────────────
        -- 스폰 X → 2단계 진입 지점(ItemSpawnPlate) X 구간을 0~1 로 정규화해 최고 도달치를 갱신한다.
        -- 최고치만 기록하므로 뒤로 밀려나거나 죽어도 이미 번 진행도는 남는다.
        -- 1초 주기: 라운드가 3분 안팎이라 충분한 해상도이고 서버 부하도 거의 없다.
        do
            local startX = selectedMap.playerSpawn and selectedMap.playerSpawn.Position.X
            local plate = selectedMap.folder and (selectedMap.folder:FindFirstChild("ItemSpawnPlate")
                          or selectedMap.folder:FindFirstChild("ItemSpawnPlate2"))
            local goalX = plate and (plate:IsA("Model") and select(1, plate:GetBoundingBox()).Position.X or plate.Position.X)
            if startX and goalX and math.abs(goalX - startX) > 1 then
                task.spawn(function()
                    while roundActive do
                        for _, runner in ipairs(currentRunners) do
                            if runner.Parent and runner:GetAttribute("Role") == "Runner" then
                                local char = runner.Character
                                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                local hum = char and char:FindFirstChildOfClass("Humanoid")
                                if hrp and hum and hum.Health > 0 and not runner:GetAttribute("Eliminated") then
                                    local p = math.clamp((hrp.Position.X - startX) / (goalX - startX), 0, 1)
                                    if p > (runner:GetAttribute("RunnerProgress") or 0) then
                                        runner:SetAttribute("RunnerProgress", p)
                                    end
                                end
                            end
                        end
                        task.wait(1)
                    end
                end)
            else
                warn("[진행도] 기준 좌표 확보 실패 — 러너 진행도 보상 생략")
            end
        end

        -- 불꽃 압박 시작 신호
        local startFireEvent = ReplicatedStorage:FindFirstChild('StartFirePressure')
        if startFireEvent then startFireEvent:Fire() end

        -- 부활 카운트 리셋 (라운드별 1회 한정)
        local ReviveSystem = require(game.ServerScriptService:WaitForChild("ReviveSystem"))
        ReviveSystem.resetAllRevives()
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then
                p.Character:SetAttribute("UsedRevive", nil)
                p.Character:SetAttribute("ReviveInvul", nil)
            end
        end

        -- 라운드 진행
        print("\n=== ROUND START ===")
        broadcastPhase("stage1")  -- 음악: 1단계 BGM으로
        -- 📡 [2026-09-06] 라이브 텔레메트리 시작. 생존/관전 시간의 기준점이다.
        --   ⚠️ 여기여야 한다 — 스폰·역할배정이 끝난 뒤라야 '라운드가 실제로 시작된' 시점이다.
        if _G.Telemetry_RoundStart then _G.Telemetry_RoundStart() end

        -- 📋 라운드 요약용 관측 초기화.
        -- ⚠️ 여기서 세는 이유: AI 스폰이 끝난 뒤라야 총원이 확정된다.
        --   (라운드 시작 HP 계산은 스폰보다 22ms 앞서 돌아 봇을 0으로 세는
        --    알려진 함정이 있다 — 같은 실수를 반복하지 않으려고 여기에 둔다)
        do
            roundObs.startAt     = os.clock()
            roundObs.stage2At    = 0
            roundObs.stage2Alive = 0
            roundObs.s2Downs     = {}   -- 🔬 [K측정] 2단계 다운 기록 초기화
            roundObs.s2Deaths    = 0    -- 🔬 [K측정] 2단계 사망 수 초기화
            roundObs.s2KingDmg   = 0    -- 🔬 [K측정] 킹이 2단계에서 받은 총 피해
            roundObs.s2KingHits  = 0    -- 🔬 [K측정] 그 피격 횟수
            roundObs.s2KingBleed = 0    -- 🩸 [K측정] 저주검 출혈 누적(분리 집계)
            -- 🎯 [계측 2026-09-20] 1단계 명중률 분리. 두 스크립트가 채운다.
            roundObs.s1Spawns    = 0    -- 1단계 아이템 사용 횟수(쿨을 실제로 소모한 것만)
            roundObs.s1Hits      = 0    -- 1단계 유효 히트(⚠️ 내구도 흡수분 포함)
            local n = 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p:GetAttribute("Role") == "Runner" then
                    local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then n += 1 end
                end
            end
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m:GetAttribute("AIRunner") then
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then n += 1 end
                end
            end
            roundObs.runnersTotal = n
        end

        for i = ROUND_TIME, 1, -1 do
            if not roundActive then break end
            -- 일시정지 중이면 타이머 멈춤
            while roundPaused do
                updateAllTimers("⏸️ PAUSED")
                wait(0.5)
            end
            
            -- ── 러너 전멸 감시 (안전망) ──────────────────────────────
            -- ⚠️ Humanoid.Died 훅만으로는 전멸을 놓치는 경로가 있다.
            --    얼음 킬 이펙트처럼 연출이 캐릭터를 Destroy 하면 Died 가 아예 발생하지 않아,
            --    사망 이벤트에 의존하는 종료 판정과 킬 카운트가 통째로 건너뛰어진다.
            --    (2026-08 실측: AI 러너 5체가 빙결 처형으로 전부 소멸했는데 타임아웃까지 진행)
            --    연출이 늘수록 이런 경로도 늘어나므로, 원인과 무관하게 "지금 살아있는가"를
            --    매초 확인해 확실히 종료시킨다. Died 훅은 즉각 반응용으로 그대로 둔다.
            if roundActive and checkRunners() == 0 then
                print("⏱️ [감시] 러너 전멸 감지 → 라운드 종료")
                registerDownedAsKills()
                task.wait(2)
                if roundActive then endRound("Tagger") end
                break
            end

            local minutes = math.floor(i / 60)
            local seconds = i % 60
            updateAllTimers(string.format("🎮 Round: %d:%02d", minutes, seconds))
            wait(1)
        end
        
        -- ⏱️ 시간 초과 — 태거 승리
        -- ⚠️ [밸런스 2026-08-25] 러너 승리 → 태거 승리로 변경.
        --    [왜] 시간 초과가 러너 승리면 "성문을 안 부수고 버티는 것"이
        --    최선의 전략이 된다. 실제로 그런 판이 나왔고, 압박선을 성문
        --    앞까지 미는 것도 그 대응이었다.
        --    뒤집으면 러너가 반드시 밀어붙여야 하고, 태거의 "버티기"가
        --    지연이 아니라 승리 조건이 된다.
        --    ⚠️ 태거는 2단계에 불리한 역할이므로, 시간이 그 보상이 된다.
        if roundActive then
            print("\n=== TIME UP → 태거 승리 ===")
            endRound("Tagger", nil, nil, "timeout")
        end
        
        wait(3)
    end
end)

print("Round System with Victory Conditions initialized!")
