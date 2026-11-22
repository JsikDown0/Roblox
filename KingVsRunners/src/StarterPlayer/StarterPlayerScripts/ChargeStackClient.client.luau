-- ═══════════════════════════════════════════════════════════
-- 👑 푸시툴 강화 스택 UI
--
-- [왜] 지금은 1단계에서 킬을 쌓아도 그 사실이 화면에 안 드러난다.
--   태거가 "내가 잘하고 있다 → 2단계가 강해진다"를 느껴야
--   1단계 플레이에 목적이 생긴다.
--
-- [흐름]
--   1단계  킬을 쌓으면 게이지가 차오른다 (0~5~9점)
--   2단계  진입 시 게이지가 푸시툴 쪽으로 빨려들며 사라진다
--          = "1단계에 모은 힘이 무기로 들어갔다"
--
-- ⚠️ 태거에게만 보인다. 러너에게는 손목 오라로 전달된다.
-- ⚠️ 점수 공식은 KillEffectSystem.updateChargeStage 와 같아야 한다.
--    (유저 킬 + 봇 킬 × 0.5)
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local BOT_W = 0.5
local T2, T3 = 5, 9          -- 단계 문턱
local STAGE_COLOR = {
    [1] = Color3.fromRGB(235, 235, 235),
    [2] = Color3.fromRGB(255, 210, 60),
    [3] = Color3.fromRGB(230, 45, 30),
}

local gui = Instance.new("ScreenGui")
gui.Name = "ChargeStackGui"
gui.ResetOnSpawn = false     -- ⚠️ 리스폰마다 사라지지 않게
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- 📍 [SLAM-POS 2026-08-27] 화면 상단 중앙(0.5, -105 / 96) → 좌측 하단 'REVIVE' 자리.
--   [왜] 조준 방향 정면을 가려서 1단계 조준 중 시야를 먹었다(실측 스크린샷).
--   [왜 이 자리] 부활 기회는 러너 전용 개념인데 태거에게도 "REVIVE 1" 이 붙박이로
--     떠 있었다. ReviveClient 에 태거 가드를 넣어 숨기고 그 슬롯을 여기가 쓴다.
--
--   ⚠️ 위치를 세 군데에서 쓴다 — 여기(초기) + pulse() 의 확대/복귀 2곳.
--     예전에 이 중 하나만 고치면 단계 상승 연출이 돌 때마다 옛 좌표로 되돌아갔다.
--     → 좌표를 변수로 묶어 한 곳에서만 정한다. 새 위치 쓰는 곳이 생기면 이 변수를 쓸 것.
--   ⚠️ 고정 좌표로 두지 않는다. 이 슬롯은 ReviveClient 가 세 번 고쳐 잡은 자리다
--     (EmoteBar 크기 변동 56↔164 / 모바일·PC 배치 분기 / UIScale 차이).
--     계산을 복제하지 말고 ChanceFrame 의 좌표를 그대로 받아온다.
local POS_NORM = UDim2.new(0.5, -105, 0, 96)   -- 폴백(구 위치). attach 성공 시 슬롯 좌표로 교체
local POS_BIG  = UDim2.new(0.5, -119, 0, 92)   -- 단계 상승 확대 연출용

-- 본체
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromOffset(210, 54)
root.Position = POS_NORM
root.BackgroundColor3 = Color3.fromRGB(18, 16, 24)
root.BackgroundTransparency = 0.25
root.BorderSizePixel = 0
root.Parent = gui

-- [SLAM-POS] ReviveClient 의 ChanceFrame 을 슬롯 삼아 좌표를 받아온다.
--   ⚠️ syncToBar 계산을 여기로 복사하지 말 것 — ReviveClient 가 세 번 재발시킨 계산이다.
--     ChanceFrame 은 태거에게도 생성된다(Visible=false). 좌표만 빌린다.
--   ⚠️ 부모를 EmotionBarGui 로 옮겨야 같은 좌표계·같은 UIScale 을 쓴다.
--     ChargeStackGui 는 폴백 경로에서만 부모 역할을 한다(표시 제어는 아래 setShown).
do
    local function attachToChanceSlot()
        local pg   = player:FindFirstChild("PlayerGui")
        local ebg  = pg and pg:FindFirstChild("EmotionBarGui")
        local slot = ebg and ebg:FindFirstChild("ChanceFrame")
        if not (slot and slot:IsA("GuiObject")) then return false end
        root.Parent = ebg
        local function sync()
            if not (slot.Parent and root.Parent) then return end
            root.AnchorPoint = slot.AnchorPoint
            POS_NORM = slot.Position
            -- 확대 연출은 '슬롯 기준 상대 오프셋'으로 잡는다(구 코드의 -14/-4 차이 유지).
            POS_BIG = UDim2.new(
                slot.Position.X.Scale, slot.Position.X.Offset - 14,
                slot.Position.Y.Scale, slot.Position.Y.Offset - 4)
            root.Position = POS_NORM
        end
        sync()
        slot:GetPropertyChangedSignal("Position"):Connect(sync)
        slot:GetPropertyChangedSignal("AnchorPoint"):Connect(sync)
        return true
    end
    if not attachToChanceSlot() then
        task.spawn(function()
            for _ = 1, 60 do
                task.wait(0.25)
                if attachToChanceSlot() then return end
            end
            warn("[ChargeStack] ChanceFrame 슬롯을 못 찾아 폴백 위치 사용")
        end)
    end
end

-- 👁️ [SLAM-POS 2026-08-27] 표시 제어는 반드시 이 함수를 통한다.
--   [증상] 위치를 옮긴 뒤 로비·맵투표 화면에서도 SLAM POWER 가 계속 떠 있었다.
--   [원인] 원래 gui.Enabled 하나로 껐는데, root 를 EmotionBarGui 로 옮기면서
--     ChargeStackGui 밑을 벗어났다 → gui.Enabled 가 root 에 아무 영향이 없다.
--     (ReviveClient 가 같은 이동을 하며 "gui.Enabled 로는 못 끈다"고 주석까지 남겼는데
--      같은 함정을 그대로 밟았다)
--   [해결] 두 곳을 함께 끈다:
--     · root.Visible  — attach 성공 시(부모=EmotionBarGui) 실제로 먹히는 스위치
--     · gui.Enabled   — attach 실패 폴백 시(부모=ChargeStackGui) 먹히는 스위치
--   ⚠️ 어느 경로로 붙었는지에 따라 유효한 스위치가 다르므로 둘 다 세팅한다.
--     새로 켜고 끄는 코드를 추가할 땐 gui.Enabled 를 직접 쓰지 말고 이 함수를 쓸 것.
local function setShown(v)
    -- 🚫 [비활성 2026-09-02] 강화 스택 UI 를 숨긴다.
    --   [왜] 강화 시스템의 실효가 래그돌 0.4→0.8초뿐이고(데미지·넉백은 고정),
    --     문턱이 유저 5명/봇 10마리라 실전에서 거의 도달하지 않는다. 도달도 안 하는
    --     게이지가 화면을 차지하면 "이게 뭐지"만 남는다. 필요성 자체를 재검토 중이라
    --     표시부터 내린다.
    --   ⚠️ 계산(KillEffectSystem.updateChargeStage)과 손 이펙트(PushChargeFxViewer)는
    --     그대로 살아 있다. PushChargeStage 속성도 계속 갱신된다 — 되살릴 때
    --     이 한 줄만 지우면 원상복구된다.
    --   ⚠️ 스크립트를 Disabled 하지 않은 이유: 이 파일은 흡수 연출·상태 훅을 함께
    --     들고 있어 통째로 끄면 나중에 어디까지 살아 있었는지 알기 어렵다.
    if true then v = false end

    root.Visible = v
    gui.Enabled  = v
end
local function isShown()
    return root.Visible
end
setShown(false)
local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0, 10)
rc.Parent = root
local rs = Instance.new("UIStroke")
rs.Color = STAGE_COLOR[1]
rs.Thickness = 1.6
rs.Transparency = 0.35
rs.Parent = root

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 16)
title.Position = UDim2.fromOffset(8, 5)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "KING FIST"
title.TextColor3 = Color3.fromRGB(210, 205, 225)
title.Parent = root

local stageLbl = Instance.new("TextLabel")
stageLbl.Size = UDim2.new(0, 70, 0, 16)
stageLbl.Position = UDim2.new(1, -78, 0, 5)
stageLbl.BackgroundTransparency = 1
stageLbl.Font = Enum.Font.GothamBlack
stageLbl.TextScaled = true
stageLbl.TextXAlignment = Enum.TextXAlignment.Right
stageLbl.Text = "I"
stageLbl.TextColor3 = STAGE_COLOR[1]
stageLbl.Parent = root

-- 게이지
local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -16, 0, 12)
barBg.Position = UDim2.fromOffset(8, 28)
barBg.BackgroundColor3 = Color3.fromRGB(38, 34, 48)
barBg.BorderSizePixel = 0
barBg.Parent = root
local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(0, 6)
bc.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = STAGE_COLOR[1]
barFill.BorderSizePixel = 0
barFill.Parent = barBg
local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0, 6)
fc.Parent = barFill

-- 문턱 표시선 (2단계 지점)
local tick = Instance.new("Frame")
tick.Size = UDim2.new(0, 2, 1, 0)
tick.Position = UDim2.fromScale(T2 / T3, 0)
tick.BackgroundColor3 = Color3.fromRGB(120, 115, 140)
tick.BorderSizePixel = 0
tick.ZIndex = 2
tick.Parent = barBg

local scoreLbl = Instance.new("TextLabel")
scoreLbl.Size = UDim2.new(1, -16, 0, 12)
scoreLbl.Position = UDim2.fromOffset(8, 41)
scoreLbl.BackgroundTransparency = 1
scoreLbl.Font = Enum.Font.Gotham
scoreLbl.TextScaled = true
scoreLbl.TextXAlignment = Enum.TextXAlignment.Right
scoreLbl.Text = ""
scoreLbl.TextColor3 = Color3.fromRGB(160, 155, 175)
scoreLbl.Parent = root

-- ── 상태 ──
local lastStage = 1
local absorbed = false

local function scoreOf()
    local u = player:GetAttribute("RoundKills") or 0
    local b = player:GetAttribute("RoundAIKills") or 0
    return u + b * BOT_W
end

local function stageOf(sc)
    if sc >= T3 then return 3 elseif sc >= T2 then return 2 end
    return 1
end

-- ✨ 단계 상승 연출
local function pulse(stage)
    local col = STAGE_COLOR[stage]
    rs.Color = col
    barFill.BackgroundColor3 = col
    stageLbl.TextColor3 = col
    stageLbl.Text = (stage == 3) and "III" or (stage == 2) and "II" or "I"

    -- 확 커졌다 돌아온다
    local big = UDim2.fromOffset(238, 62)
    local norm = UDim2.fromOffset(210, 54)
    root.Size = big
    root.Position = POS_BIG
    TweenService:Create(root, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = norm, Position = POS_NORM }):Play()
    rs.Transparency = 0
    TweenService:Create(rs, TweenInfo.new(0.6), { Transparency = 0.35 }):Play()
end

-- 🌀 2단계 진입: 푸시툴로 흡수되며 사라진다
local function absorb()
    if absorbed then return end
    absorbed = true

    -- 푸시툴 버튼 위치를 목표로 삼는다(없으면 화면 우하단)
    local targetPos = UDim2.new(1, -120, 1, -160)
    local pg = player:FindFirstChild("PlayerGui")
    local pushGui = pg and pg:FindFirstChild("PushGrabGui")
    if pushGui then
        local btn = pushGui:FindFirstChild("GrabButton", true)
            or pushGui:FindFirstChildWhichIsA("ImageButton", true)
        if btn and btn.AbsolutePosition then
            targetPos = UDim2.fromOffset(
                btn.AbsolutePosition.X + btn.AbsoluteSize.X / 2 - 20,
                btn.AbsolutePosition.Y + btn.AbsoluteSize.Y / 2 - 20)
        end
    end

    -- 빨려들어가며 축소·소멸
    local info = TweenInfo.new(0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    TweenService:Create(root, info, {
        Position = targetPos,
        Size = UDim2.fromOffset(40, 12),
        BackgroundTransparency = 1,
    }):Play()
    TweenService:Create(rs, info, { Transparency = 1 }):Play()
    for _, d in ipairs({ title, stageLbl, scoreLbl }) do
        TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
    end
    TweenService:Create(barBg, info, { BackgroundTransparency = 1 }):Play()
    TweenService:Create(barFill, info, { BackgroundTransparency = 1 }):Play()
    TweenService:Create(tick, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()

    task.delay(0.85, function() setShown(false) end)
end

local function refresh()
    if absorbed then return end
    local sc = scoreOf()
    local st = stageOf(sc)
    local ratio = math.clamp(sc / T3, 0, 1)
    TweenService:Create(barFill, TweenInfo.new(0.25), { Size = UDim2.fromScale(ratio, 1) }):Play()
    scoreLbl.Text = (st >= 3) and "MAX" or string.format("%.1f / %d", sc, (st >= 2) and T3 or T2)
    if st ~= lastStage then
        lastStage = st
        pulse(st)
    end
end

-- ── 표시 조건 ──
local function onPhase()
    local ph = ReplicatedStorage:GetAttribute("RoundPhase")
    local isTagger = player:GetAttribute("Role") == "Tagger"

    if ph == "stage1" and isTagger then
        absorbed = false
        lastStage = 1
        rs.Color = STAGE_COLOR[1]
        barFill.BackgroundColor3 = STAGE_COLOR[1]
        stageLbl.TextColor3 = STAGE_COLOR[1]
        stageLbl.Text = "I"
        -- 트윈으로 바뀐 값들을 되돌린다
        root.Size = UDim2.fromOffset(210, 54)
        -- ⚠️ [SLAM-POS] 여기가 세 번째 위치 지정이다(초기·pulse·여기).
        --    absorb 트윈이 root 를 우하단으로 끌고 갔다 오므로 반드시 되돌려야 하는데,
        --    옛 좌표를 하드코딩하면 라운드가 바뀔 때마다 화면 상단으로 되돌아간다.
        root.Position = POS_NORM
        root.BackgroundTransparency = 0.25
        rs.Transparency = 0.35
        barBg.BackgroundTransparency = 0
        barFill.BackgroundTransparency = 0
        barFill.Size = UDim2.fromScale(0, 1)
        tick.BackgroundTransparency = 0
        for _, d in ipairs({ title, stageLbl, scoreLbl }) do d.TextTransparency = 0 end
        setShown(true)
        refresh()
    elseif ph == "stage2" and isTagger and isShown() then
        -- 🌀 힘이 무기로 흡수된다
        absorb()
    elseif not isTagger or ph == nil or ph == "intermission" then
        setShown(false)
        absorbed = false
    end
end

ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(onPhase)
player:GetAttributeChangedSignal("Role"):Connect(onPhase)
player:GetAttributeChangedSignal("RoundKills"):Connect(refresh)
player:GetAttributeChangedSignal("RoundAIKills"):Connect(refresh)
onPhase()

print("👑 ChargeStackClient 준비")
