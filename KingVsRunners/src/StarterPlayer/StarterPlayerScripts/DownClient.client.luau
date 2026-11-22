-- DownClient
-- Downed의 클라이언트 측 처리:
--   - 기어가는 애니메이션 재생
--   - 카메라 높이 자연스럽게 낮춤 (Tween)
--   - 점프 입력 차단
--   - 다운 타이머 UI 표시
--
-- 서버의 DownSystem이 Downed와 이동 속도를 관리하고,
-- 이 스크립트는 시각/입력 측면만 담당함.

-- 다운 애니메이션 ID (DownSystem.DOWN_ANIM_IDS 와 동일해야 함).
-- 서버가 재생한 다운 트랙이 클라에 복제될 때, 에셋 자체에 저장된 우선순위가
-- Idle 로 읽히는 순간이 있어 아래 스윕 필터에 잘못 걸린다(실측: idle 트랙 소실 → T포즈).
-- 우선순위가 아니라 ID 로 제외해야 안전하다.
local DOWN_ANIM_KEEP = {
	["139314696142315"] = true,   -- R15 Idle
	["122123776991115"] = true,   -- R15 Walk
	["103837025248844"] = true,   -- R6  Idle
	["125507346849648"] = true,   -- R6  Walk
}

-- 다운 애니메이션 실제 ID (DownSystem.DOWN_ANIM_IDS 와 동일해야 함)
local DOWN_ANIM_IDS = {
	R15 = { Idle = "rbxassetid://139314696142315", Walk = "rbxassetid://122123776991115" },
	R6  = { Idle = "rbxassetid://103837025248844", Walk = "rbxassetid://125507346849648" },
}
local downBlendConn = nil   -- 다운 중 idle<->walk 가중치 블렌딩 연결

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local downStateEvent = ReplicatedStorage:WaitForChild("DownStateChanged")

-- ── 설정 ────────────────────────────────────────────────
-- 다운 시 사용할 애니메이션 (KeyframeSequence)
-- ReplicatedStorage.DownAnimations 폴더에서 RigType별로 골라 사용:
--   - R15.Idle / R15.Walk : R15 캐릭터용 (LowerTorso, UpperTorso 등 분할 본)
--   - R6.Idle / R6.Walk   : R6 캐릭터용 (Torso 단일 본)
-- 이동 시 Walk가 Idle을 덮어쓰고, 정지 시 Idle만 보임.
-- (워크스페이스의 Crouch Model에서 가져온 정식 R15/R6 호환 애니메이션)
local DOWN_ANIMS = ReplicatedStorage:WaitForChild("DownAnimations")

-- 카메라 높이 오프셋 (Y축 음수 = 카메라 낮아짐)
-- 기본 1인칭 시점 기준 약 1.5스터드 낮춤 (엎드린 자세 시점)
local DOWN_CAMERA_OFFSET = Vector3.new(0, -2.5, 0)
local CAMERA_TWEEN_TIME  = 0.4  -- 카메라 전환 부드럽게

-- 다운 중 이동 시 재생할 사운드 ID
-- HumanoidRootPart.Running 의 SoundId 를 이 값으로 교체.
-- Roblox 엔진이 캐릭터 이동 상태에 따라 자동으로 재생/정지함.
local CRAWL_SOUND_ID = "rbxassetid://140071470572800"

-- ── 상태 ────────────────────────────────────────────────
local idleTrack          = nil  -- 다운 시 정지 자세 (Idle)
local walkTrack          = nil  -- 다운 시 기어가기 (Walk)
local moveBlendConn      = nil  -- MoveDirection 기반 가중치 전환 connection
local jumpBlockConn      = nil
local savedClickToMove = nil   -- 다운 중 클릭이동 차단 여부(복구용)
local timerUpdateConn    = nil
local downStartTime      = 0
local downDuration       = 0
local timerUI            = nil
local originalRunningSoundId = nil  -- 다운 해제 시 복원용 (걷기 사운드 원본 ID)

-- ─────────────────────────────────────────────────────────────
-- 다운 타이머 UI 생성/업데이트/제거
-- ─────────────────────────────────────────────────────────────
local function createTimerUI()
    if timerUI then return timerUI end

    -- ⚠️ 모바일에서 다운 UI + SOS 버튼이 세로 136px(화면의 38%)를 먹어
--    3인칭 캐릭터를 가렸다(실측 772x360). 모바일만 압축하고 하단으로 밀착시킨다.
local Scaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))
local isMobile = Scaler.isMobile()
local BOX_W  = isMobile and 240 or 320
local BOX_H  = isMobile and 52  or 80
local BOX_Y  = isMobile and 0.97 or 0.90
local LBL_H  = isMobile and 18  or 24
local TMR_H  = isMobile and 22  or 28
local BAR_H  = isMobile and 5   or 6

local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DownTimerUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

    -- 중앙 하단 컨테이너
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.AnchorPoint = Vector2.new(0.5, 1)
    container.Position = UDim2.new(0.5, 0, BOX_Y, 0)
    container.Size = UDim2.new(0, BOX_W, 0, BOX_H)
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    container.BackgroundTransparency = 0.3
    container.BorderSizePixel = 0
    container.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(200, 50, 50)
    stroke.Thickness = 2
    stroke.Parent = container

    -- "다운" 라벨
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 0, LBL_H)
    label.Position = UDim2.new(0, 0, 0, isMobile and 4 or 8)
    label.BackgroundTransparency = 1
    label.Text = "DOWNED"
    label.TextColor3 = Color3.fromRGB(255, 100, 100)
    label.TextSize = 16
    label.Font = Enum.Font.GothamBold
    label.Parent = container

    -- 타이머 텍스트
    local timerText = Instance.new("TextLabel")
    timerText.Name = "TimerText"
    timerText.Size = UDim2.new(1, 0, 0, TMR_H)
    timerText.Position = UDim2.new(0, 0, 0, isMobile and 22 or 32)
    timerText.BackgroundTransparency = 1
    timerText.Text = "10.0"
    timerText.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerText.TextSize = 22
    timerText.Font = Enum.Font.GothamBold
    timerText.Parent = container

    -- 진행 바
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.AnchorPoint = Vector2.new(0.5, 1)
    barBg.Position = UDim2.new(0.5, 0, 1, isMobile and -5 or -8)
    barBg.Size = UDim2.new(1, isMobile and -12 or -16, 0, BAR_H)
    barBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    barBg.BorderSizePixel = 0
    barBg.Parent = container

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = barBg

    local barFill = Instance.new("Frame")
    barFill.Name = "BarFill"
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = barFill

    timerUI = {
        gui       = screenGui,
        timerText = timerText,
        barFill   = barFill,
    }
    return timerUI
end

local function showTimerUI(duration)
    local ui = createTimerUI()
    ui.gui.Enabled = true
    downStartTime = tick()
    downDuration  = duration

    -- 매 프레임 갱신
    if timerUpdateConn then timerUpdateConn:Disconnect() end
    timerUpdateConn = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - downStartTime
        local remaining = math.max(0, downDuration - elapsed)
        local progress = remaining / downDuration

        ui.timerText.Text = string.format("%.1f", remaining)
        ui.barFill.Size = UDim2.new(progress, 0, 1, 0)

        -- 마지막 3초 색깔 변화
        if remaining <= 3 then
            local pulse = math.abs(math.sin(tick() * 6))
            ui.barFill.BackgroundColor3 = Color3.fromRGB(255, 60 + pulse * 100, 60)
        else
            ui.barFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
        end
    end)
end

local function hideTimerUI()
    if timerUpdateConn then
        timerUpdateConn:Disconnect()
        timerUpdateConn = nil
    end
    if timerUI and timerUI.gui then
        timerUI.gui.Enabled = false
    end
end

-- ─────────────────────────────────────────────────────────────
-- 카메라 부드러운 전환 (CameraOffset Tween)
-- ─────────────────────────────────────────────────────────────
local function tweenCameraOffset(humanoid, targetOffset)
    if not humanoid or not humanoid.Parent then return end

    local startOffset = humanoid.CameraOffset
    local startTime   = tick()

    local conn
    conn = RunService.RenderStepped:Connect(function()
        local alpha = math.min((tick() - startTime) / CAMERA_TWEEN_TIME, 1)
        -- ease-out
        local eased = 1 - (1 - alpha) ^ 2
        if humanoid and humanoid.Parent then
            humanoid.CameraOffset = startOffset:Lerp(targetOffset, eased)
        end
        if alpha >= 1 then
            conn:Disconnect()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- 다운 시작 (로컬 플레이어 본인)
-- ─────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────
-- KeyframeSequence를 AnimationTrack으로 변환
-- KeyframeSequenceProvider가 임시 AnimationId를 발급해줘서, 별도 업로드 없이 사용 가능.
-- ─────────────────────────────────────────────────────────────
local function loadTrackFromKeyframeSequence(animator, keyframeSequence, name)
    local provider = game:GetService("KeyframeSequenceProvider")
    local ok, animId = pcall(function()
        return provider:RegisterKeyframeSequence(keyframeSequence)
    end)
    if not ok or not animId then
        warn("[DownClient]", name, "등록 실패:", animId)
        return nil
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = animId

    local loadOk, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not loadOk or not track then
        warn("[DownClient]", name, "LoadAnimation 실패:", track)
        return nil
    end
    return track
end

-- ─────────────────────────────────────────────────────────────
-- 다운 시작 (로컬 플레이어 본인)
-- ─────────────────────────────────────────────────────────────
local function startDown(duration)
    local character = localPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- ANIM-SWEEP: 기본 Animate 는 클라이언트 LocalScript 다.
    -- 서버(DownSystem)가 Disabled=true 를 걸어도 복제까지 지연(핑)이 있고,
    -- 그 사이 Animate 가 시작한 Core 트랙은 '클라가 소유한 재생'이라
    -- 서버에서 Stop 해도 화면에서는 안 멈춘다.
    -- 실측(2026-08): 913376220/913402848(기본 달리기/걷기)이 서버 정리 후에도 잔존.
    -- Action4 는 키를 잡은 관절만 이기므로 남은 Core 가 비쳐 나와 자세가 깨진다.
    -- 그래서 클라가 자기 몸은 자기가 즉시 정리한다.
    do
    	local an = character:FindFirstChild("Animate")
    	if an then an.Disabled = true end
    	local animator = humanoid:FindFirstChildOfClass("Animator")
    	if animator then
    		task.spawn(function()
    			-- 복제 지연 구간(약 1.5초)만 쓸어낸다. 다운 애니는 Action4 라 영향 없음.
    			for _ = 1, 30 do
    				for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
    					local rawId = (t.Animation and t.Animation.AnimationId) or ""
    					local numId = tostring(rawId):match("(%d+)")
    					if numId and DOWN_ANIM_KEEP[numId] then continue end
    					local p = t.Priority
    					if p == Enum.AnimationPriority.Core
    						or p == Enum.AnimationPriority.Idle
    						or p == Enum.AnimationPriority.Movement then
    						pcall(function() t:Stop(0) end)
    					end
    				end
    				task.wait(0.05)
    			end
    		end)
    	end
    end

    -- CLIENT-ANIM: 다운 애니메이션을 클라이언트가 직접 재생한다.
    -- 서버가 재생한 트랙은 '재생 시작'만 클라로 복제되고, 루프/가중치 같은 지속 제어는
    -- 서버 쪽에만 남는다. 플레이어 캐릭터의 네트워크 소유자가 클라이언트이기 때문이다.
    -- 실측(2026-08): 서버 트랙은 10초 내내 살아있는데 클라 복제본은 len(1.00s)에
    -- 도달하는 순간 소멸했다 → 남는 트랙이 없어 T포즈. 복제본에 Looped=true 를 걸어도 소용없었다.
    -- 그래서 클라가 자기 트랙을 직접 소유한다. (서버 트랙은 1초 뒤 자연 소멸하므로 충돌 없음)
    do
    	local am = humanoid:FindFirstChildOfClass("Animator")
    	if not am then
    		am = Instance.new("Animator")
    		am.Parent = humanoid
    	end
    	local set = (humanoid.RigType == Enum.HumanoidRigType.R15)
    		and DOWN_ANIM_IDS.R15 or DOWN_ANIM_IDS.R6
    	local function loadTrack(id)
    		local a = Instance.new("Animation")
    		a.AnimationId = id
    		local ok, tr = pcall(function() return am:LoadAnimation(a) end)
    		if not ok or not tr then
    			warn("[DownClient] 다운 애니 로드 실패: " .. tostring(id) .. " / " .. tostring(tr))
    			return nil
    		end
    		tr.Priority = Enum.AnimationPriority.Action4
    		tr.Looped = true
    		return tr
    	end
    	idleTrack = loadTrack(set.Idle)
    	walkTrack = loadTrack(set.Walk)
    	if idleTrack then idleTrack:Play(0.2, 1.0) end
    	if walkTrack then walkTrack:Play(0.2, 0.0) end
    	if downBlendConn then downBlendConn:Disconnect() end
    	downBlendConn = RunService.Heartbeat:Connect(function()
    		if not (humanoid and humanoid.Parent) then return end
    		local moving = humanoid.MoveDirection.Magnitude > 0.1
    		if walkTrack then walkTrack:AdjustWeight(moving and 1.0 or 0.0, 0.15) end
    		if idleTrack then idleTrack:AdjustWeight(moving and 0.0 or 1.0, 0.15) end
    	end)
    end

    -- ⚠️ 다운 자세 애니메이션은 서버(DownSystem)가 재생한다. 여기서 하지 않는다.
    --    이전에는 이 클라이언트가 KeyframeSequenceProvider 로 임시 애니메이션을 만들어
    --    재생했는데, 그 임시 에셋은 본인 클라이언트에만 존재해서 다른 플레이어에게는
    --    복제되지 않았다. 반면 Animate 비활성화는 인스턴스 속성이라 전파되어,
    --    "남의 화면에서만 T포즈"가 되는 버그가 있었다.
    --    → 서버 Animator 재생으로 이전(2026-08). Animate 제어도 서버가 담당한다.
    --    이 함수는 카메라 오프셋 / 기어가기 사운드 / 타이머 UI / 점프 차단만 처리한다.


    -- (Idle↔Walk 가중치 블렌딩은 서버 DownSystem 으로 이전됨)

    -- 걷기 사운드 교체 (Roblox 기본 Running 사운드 → 기어가는 소리)
    -- HumanoidRootPart.Running 은 엔진이 이동 상태에 따라 자동 재생/정지하므로
    -- SoundId 만 교체하면 다운 중에는 자동으로 새 사운드가 재생됨.
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local runningSound = hrp and hrp:FindFirstChild("Running")
    if runningSound then
        originalRunningSoundId = runningSound.SoundId
        runningSound.SoundId = CRAWL_SOUND_ID
    end

    -- 카메라 부드럽게 낮춤
    tweenCameraOffset(humanoid, DOWN_CAMERA_OFFSET)

    -- 점프 차단 (서버에서 JumpPower=0 설정해도 클라이언트에서 추가 차단)
    if jumpBlockConn then jumpBlockConn:Disconnect() end
    jumpBlockConn = UserInputService.JumpRequest:Connect(function()
        if humanoid and humanoid.Parent then
            humanoid.Jump = false
        end
    end)

    -- ⚠️ 모바일 클릭 이동(ClickToMove) 차단.
    --   모바일에서 다운 중 화면을 탭하면 Roblox 기본 컨트롤이 "그 지점으로 이동"으로 해석해
    --   Humanoid:MoveTo() 를 호출한다. 그러면 경로 이동이 시작되면서 다운 자세가 깨진다.
    --   (서버의 애니메이션 트랙 자체는 정상이라 서버 로그에는 이상이 안 잡혔다 — 실측 확인)
    --   조이스틱 이동은 그대로 두고(느린 기어가기는 의도된 동작), 탭 이동만 막는다.
    pcall(function()
        local pm = localPlayer.PlayerScripts:FindFirstChild("PlayerModule")
        if not pm then return end
        local controls = require(pm):GetControls()
        savedClickToMove = UserInputService.TouchEnabled
        -- ClickToMove 컨트롤러를 끄고 기본 터치 조작만 남긴다
        controls:SetComputerMovementMode(Enum.ComputerMovementMode.KeyboardMouse)
        -- [TOUCH-MODE] DynamicThumbstick 유지.
        --   여기 목적은 '탭 이동(ClickToMove) 차단'이다. DynamicThumbstick 도 탭 이동을 막는다.
        --   ⚠️ 한때 Thumbstick(고정 조이스틱)으로 바꿨다가 되돌렸다 — 오인식은 줄었지만
        --      "화면 아래 작은 지점에 계속 손을 가져가야 해서 불편"하다는 실사용 피드백.
        --      오인식은 아래 TouchMovementMode 대신 카메라 팬 영역 제한으로 완화한다.
        controls:SetTouchMovementMode(Enum.TouchMovementMode.DynamicThumbstick)
    end)
    -- ⚠️ humanoid:MoveTo(현재위치) 를 넣었다가 뺐다.
    --    자기 위치로 MoveTo 하면 휴머노이드가 "목표에 도달하려 계속 시도"하는 상태가 되어
    --    state 가 Running 으로 고정되고, 그 결과 다운 walk(기어가기) 트랙 가중치가 1.0 으로
    --    붙박이가 된다. 화면에서는 제자리에서 빠르게 허우적대는 모습으로 보였다(실측 제보).
    --    이동 모드 변경만으로 탭 이동은 이미 차단되므로 별도 취소가 필요 없다.

    -- UI 표시
    showTimerUI(duration)
end

-- ─────────────────────────────────────────────────────────────
-- 다운 종료 (사망 또는 부활)
-- ─────────────────────────────────────────────────────────────
-- ⚠️ [해결 2026-09-01] "다운 해제 후 자세가 굳는" 버그는 이 함수 밖의 문제였다.
--   진단 결과 endDown 은 정상 완주했고 Animate.Disabled=false, 다운 트랙도 전부 정리됐다.
--   남아 있던 건 Humanoid.PlatformStand=true 하나였다 — 강타 래그돌(PushTool.Server:555)이
--   `not Downed` 가드에 걸려 해제를 포기했는데, 다운이 끝날 때 대신 풀어주는 쪽이 없었다.
--   → DownSystem.clearDown 이 무조건 false 로 되돌리도록 수정. 여기는 손대지 않았다.
--   ⚠️ 비슷한 증상이 또 나오면 애니 계층부터 의심하지 말 것. PlatformStand 를 먼저 봐라.
local function endDown()
    -- ANIM-SWEEP 복구: 다운 시작 때 클라에서 직접 끈 Animate 를 되돌린다.
    -- Vishnu 오라 중이면 그쪽이 소유권을 가지므로 건드리지 않는다.
    do
    	local ch = localPlayer.Character
    	local an = ch and ch:FindFirstChild("Animate")
    	if an and not ch:GetAttribute("VishnuAura") then
    		an.Disabled = false
    	end
    end
    local character = localPlayer.Character

    -- ⚠️ 다운 중 껐던 클릭 이동을 복구한다.
    --   복구를 빠뜨리면 유저의 조작 방식이 영구히 바뀌어버린다.
    --   기본값(Default)으로 되돌리면 유저가 설정에서 고른 방식이 다시 적용된다.
    if savedClickToMove ~= nil then
        pcall(function()
            local pm = localPlayer.PlayerScripts:FindFirstChild("PlayerModule")
            if not pm then return end
            local controls = require(pm):GetControls()
            controls:SetComputerMovementMode(Enum.ComputerMovementMode.Default)
            -- ⚠️ [TOUCH-MODE] Default 로 되돌리면 안 된다.
            --    StarterPlayer.DevTouchMovementMode 를 DynamicThumbstick 으로 고정해 뒀는데
            --    Default 는 "유저 선택"으로 풀려서, 다운을 한 번 겪으면 설정이 되돌아간다.
            controls:SetTouchMovementMode(Enum.TouchMovementMode.DynamicThumbstick)
        end)
        savedClickToMove = nil
    end

    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            -- 카메라 복구
            tweenCameraOffset(humanoid, Vector3.new(0, 0, 0))
        end

        -- (Animate 활성화 복구는 서버 DownSystem.stopDownAnimation 이 담당)

        -- 걷기 사운드 원본 복원
        if originalRunningSoundId then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local runningSound = hrp and hrp:FindFirstChild("Running")
            if runningSound then
                runningSound.SoundId = originalRunningSoundId
            end
            originalRunningSoundId = nil
        end
    end

    -- MoveDirection 블렌딩 connection 해제
    if moveBlendConn then
        moveBlendConn:Disconnect()
        moveBlendConn = nil
    end

    -- 두 애니메이션 트랙 정지
    -- CLIENT-ANIM 정리: 가중치 블렌딩 연결 해제
    if downBlendConn then downBlendConn:Disconnect(); downBlendConn = nil end
    if idleTrack then
        idleTrack:Stop(0.2)
        idleTrack = nil
    end
    if walkTrack then
        walkTrack:Stop(0.2)
        walkTrack = nil
    end

    if jumpBlockConn then
        jumpBlockConn:Disconnect()
        jumpBlockConn = nil
    end

    hideTimerUI()
end

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 재생성 시 Downed 초기화
-- (다운 중 라운드 종료 등으로 캐릭터가 재생성되면 UI/입력 정리)
-- ─────────────────────────────────────────────────────────────
local function onCharacterAdded(_)
    endDown()
end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- ─────────────────────────────────────────────────────────────
-- 서버 이벤트 처리
-- ─────────────────────────────────────────────────────────────
downStateEvent.OnClientEvent:Connect(function(eventType, ...)
    if eventType == "downed" then
        local duration = ... or 10
        startDown(duration)

    elseif eventType == "died" or eventType == "revived" then
        endDown()

    -- 다른 캐릭터의 다운 시각화 (선택 — 추후 확장용)
    elseif eventType == "character_downed" then
        -- 다른 러너가 다운됨 (현재는 처리 없음, 부활 시스템 도입 시 활용)
    elseif eventType == "character_died" or eventType == "character_revived" then
        -- 다른 러너 상태 변경 (현재는 처리 없음)
    end
end)

print("✅ DownClient 활성화!")
