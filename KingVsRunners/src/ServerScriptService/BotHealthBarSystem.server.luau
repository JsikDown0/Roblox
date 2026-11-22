-- ═══════════════════════════════════════════════════════════
-- 🩸 러너 체력바 (AI + 유저 공용)
--
-- [왜] 봇은 이름표만 있고 HP 표시가 없어서 "얼마나 깎았는지" 알 수 없었다.
--   그러면 실제로는 거의 죽은 봇도 멀쩡해 보여, 유저보다 오히려
--   위압적으로 느껴진다. 때린 만큼 줄어드는 게 보여야 한다.
--
-- 🧑 [2026-09-11] 유저 러너까지 확대. 파일명은 Bot 이지만 대상은 러너 전체다.
--   [왜] 봇만 커스텀 체력바를 달고 유저는 로블록스 기본 바를 썼다.
--     같은 진영인데 둘이 다르게 생겨서, 태거 입장에서 "봇인지 사람인지"가
--     체력바 모양으로 드러났다. 정보 노출이자 완성도 격차다.
--   [왜 새 파일이 아닌가] 같은 규칙을 두 파일에 두면 한쪽만 고쳐지는 사고가 난다.
--     이 프로젝트가 반복해서 밟은 함정이라, 대상만 넓히고 로직은 하나로 둔다.
--   ⚠️ 로블록스 기본 HP바를 끄지 않으면 커스텀과 '둘 다' 뜬다.
--     attach 에서 HealthDisplayType = AlwaysOff 로 끈다 — 봇에게도 함께 적용된다.
--
-- ⚠️ 항상 띄우지 않는다. 맞았을 때만 나타나고 잠시 뒤 사라진다.
--   11마리가 늘 체력바를 달고 있으면 화면이 지저분해진다.
-- ⚠️ 서버에서 만든다. BillboardGui 는 복제되므로 전원에게 보인다.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 🎨 [2026-09-11] 진영색. 색상(hue)은 '누구냐', 명도는 '얼마 남았냐' 를 맡는다.
--   [왜 초록→빨강 lerp 를 버렸나] 저체력 러너가 빨강이 되어 킹 바와 같은 색이 됐다.
--     잔량 표시가 진영 표시를 덮어써서, 난전에서 순간적으로 오인할 수 있었다.
--   [지금] 두 정보가 다른 축을 쓰므로 서로를 안 덮는다. 정확한 값은 숫자가 맡는다.
--   ⚠️ 킹은 TaggerHpDisplay 가 크림슨 계열로 같은 규칙을 쓴다. 한 세트다 —
--     한쪽만 바꾸면 구분이 다시 무너진다.
local RUNNER_FULL = Color3.fromRGB(80, 170, 255)   -- 밝은 청
local RUNNER_LOW  = Color3.fromRGB(25, 60, 115)    -- 어두운 청

local SHOW_DURATION = 4.0     -- 마지막 피격 후 유지 시간
local BAR_STUD_W    = 4.2     -- 상세형 폭(스터드). 태거 5.5 보다 작게 — 위계 유지
local BAR_STUD_H    = 0.65    -- 상세형 높이(스터드)
local BOT_WIDTH     = 56      -- px — 간소형(바만)
local BOT_HEIGHT    = 6
-- ⚠️ [2026-09-11] VIP 이름표가 StudsOffset Y=2.5 에 있다(VIPNametag:63).
--   3.4 는 0.9 밖에 안 떨어져서 실측상 겹쳤다 → 3.8 로 올린다.
--   ⚠️ 비VIP 는 로블록스 기본 이름표라 높이를 알 수 없다. 눈으로 보고 조정할 것.
local Y_OFFSET      = 3.8     -- 머리 위 (이름표와 겹치지 않게)

local tracked = {}   -- [char] = { gui, fill, text, hideAt, lastHp }

-- 🔢 [2026-09-11] 숫자까지 보여줄 대상 = "웨폰을 든 러너".
--   [왜 봇/유저로 안 나누나] 오늘 정한 기준이 "웨폰을 들었는가" 한 줄이다.
--     여기만 '봇이냐'로 나누면 히어로봇이 들어올 때 기준이 셋으로 갈린다.
--   [왜 농민은 간소형인가] 농민은 한 방 다운이라 HP 가 사실상 이진값이다.
--     `86 / 100` 은 없는 정보를 만드는 것이고, 11개가 동시에 뜨면 전부 노이즈가 된다.
--     숫자 유무가 곧 "재야 할 상대 / 쓸어담을 대상" 이라는 우선순위 신호가 된다.
--   ⚠️ HeroRunner 는 아직 미구현이다. 히어로봇이 생기면 그 속성만 켜면 자동으로 붙는다.
--     지금은 봇 전원이 농민 역할이므로 전부 간소형이 되는 게 맞다.
local function isDetailed(char)
    if Players:GetPlayerFromCharacter(char) then return true end
    return char:GetAttribute("HeroRunner") == true
end

-- 🎨 [2026-09-11] 상세형은 태거(TaggerHpDisplay)와 같은 양식을 쓴다.
--   [왜] 같은 판에서 한쪽만 얇은 픽셀 바면 완성도 격차로 보인다. 유저 러너는
--     킹과 함께 2단계 결투의 주역이라 같은 무게로 그려야 한다.
--   [무엇이 같은가] 스터드(Scale) 단위 · 그라디언트 음영 · UIStroke 테두리 ·
--     숫자를 바 안에 중앙 배치. 크기만 킹보다 작게 둬서 위계를 남긴다(5.5 → 4.2).
--   ⚠️ 스터드 단위라 원근이 적용된다 — 멀면 자연히 작아진다. 픽셀 고정이 원거리에서
--     거대해 보이는 문제(TaggerHpDisplay:30)를 여기서도 피한다.
--   ⚠️ 간소형(농민)은 픽셀 소형을 유지한다. 11개가 스터드 크기로 뜨면 화면이 터진다.
--   ⚠️ 그라디언트는 음영 전용(흰→회색)이다. 색은 BackgroundColor3 의 명도 lerp 가 맡는다 —
--     그라디언트에 색을 넣으면 진영색 lerp 를 덮어써서 두 축이 다시 섞인다.
local function buildBar(char)
    local head = char:FindFirstChild("Head")
    if not head then return nil end

    local detailed = isDetailed(char)

    local bb = Instance.new("BillboardGui")
    bb.Name = "RunnerHpBar"
    bb.StudsOffsetWorldSpace = Vector3.new(0, Y_OFFSET, 0)
    bb.AlwaysOnTop = false
    bb.MaxDistance = 160
    bb.Adornee = head
    bb.Enabled = false
    bb.Parent = head

    if not detailed then
        -- ── 간소형: 바만, 픽셀 소형 ──
        bb.Size = UDim2.new(0, BOT_WIDTH, 0, BOT_HEIGHT)

        local back = Instance.new("Frame")
        back.Name = "Back"
        back.Size = UDim2.fromScale(1, 1)
        back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
        back.BackgroundTransparency = 0.25
        back.BorderSizePixel = 0
        back.Parent = bb
        Instance.new("UICorner", back).CornerRadius = UDim.new(0, 3)

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.fromScale(1, 1)
        fill.BackgroundColor3 = RUNNER_FULL
        fill.BorderSizePixel = 0
        fill.Parent = back
        Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

        return bb, fill, nil
    end

    -- ── 상세형: 태거 양식 (스터드 단위) ──
    bb.Size = UDim2.new(BAR_STUD_W, 0, BAR_STUD_H, 0)

    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.Size = UDim2.fromScale(1, 1)
    barBg.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    barBg.BackgroundTransparency = 0.15
    barBg.BorderSizePixel = 0
    barBg.Parent = bb

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 6)
    bgCorner.Parent = barBg

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 2
    stroke.Transparency = 0.4
    stroke.Parent = barBg

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, -4, 1, -4)        -- 안쪽 여백 (트랙 안에 떠있는 느낌)
    fill.Position = UDim2.new(0, 2, 0, 2)
    fill.BackgroundColor3 = RUNNER_FULL
    fill.BorderSizePixel = 0
    fill.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fill

    -- 음영 전용 그라디언트 (위 밝게 / 아래 진하게). 색은 안 건드린다 — 상단 주석 참조.
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 140, 140)),
    }
    gradient.Rotation = 90
    gradient.Parent = fill

    local text = Instance.new("TextLabel")
    text.Name = "HpText"
    text.Size = UDim2.fromScale(1, 1)
    text.BackgroundTransparency = 1
    text.Text = ""
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.TextScaled = true
    text.Font = Enum.Font.GothamBold
    text.TextStrokeTransparency = 0.2
    text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    text.ZIndex = 5            -- ⚠️ fill 위에 떠야 보인다
    text.Parent = barBg

    local tc = Instance.new("UITextSizeConstraint")
    tc.MaxTextSize = 22
    tc.MinTextSize = 10
    tc.Parent = text

    return bb, fill, text
end

-- 🧑 [2026-09-11] 추적 대상 = "러너 진영" 전체. 봇/유저를 가리지 않는다.
--   ⚠️ 태거(Role=="Tagger")는 제외한다 — TaggerHpDisplay 가 따로 담당하고,
--     그쪽은 2단계 전용 노출이라 규칙이 다르다. 여기서 같이 다루면 충돌한다.
--   ⚠️ 로비·인터미션에는 Role 이 없어 아무도 안 잡힌다. 의도한 동작이다.
--   ⚠️ 옛 isAIRunner 는 소비처가 사라져 삭제했다. 봇 판정은 아래 첫 줄에 흡수돼 있다.
local function isTrackedRunner(m)
    if not m:IsA("Model") then return false end
    if m:GetAttribute("AIRunner") == true then return true end
    local plr = Players:GetPlayerFromCharacter(m)
    return plr ~= nil and plr:GetAttribute("Role") == "Runner"
end

-- 🔢 [2026-09-11] 숫자 표기 추가. 바만으로는 "얼마 남았는지"가 안 읽힌다.
--   [왜] 태거는 TaggerHpDisplay 가 `960 / 975` 를 띄우는데 러너는 바뿐이었다.
--     같은 판에서 한쪽만 정보가 많으면 진영 간 완성도 격차로 보인다.
--   ⚠️ 형식을 태거와 맞춘다(`%d / %d`, ceil). floor 면 잔량 0.6 이 0 으로 보여
--     "0인데 안 죽는다"가 된다 — TaggerHpDisplay:194 가 같은 이유로 ceil 을 쓴다.
local function attach(char)
    if tracked[char] then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- 🚫 [2026-09-11] 로블록스 기본 HP바를 끈다. 안 끄면 커스텀과 둘 다 뜬다.
    --   ⚠️ 기본값은 DisplayWhenDamaged 라 '피격 시에만' 뜬다 — 커스텀과 조건이 같아서
    --     정확히 같은 순간에 겹친다. 평소엔 안 보이니 놓치기 쉬운 종류의 중복이다.
    pcall(function()
        hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end)

    local bb, fill, text = buildBar(char)
    if not bb then return end

    local info = { gui = bb, fill = fill, text = text, hideAt = 0, lastHp = hum.Health, conns = {} }
    tracked[char] = info

    -- 🔗 [2026-09-20] 연결을 info 에 보관한다. 회수할 때 반드시 끊어야 한다.
    --   [왜] 캐릭터는 라운드가 바뀌어도 유지된다(Stage2TriggerSystem:71). 아래 스윕이
    --     tracked 를 풀면 다음 라운드에 attach 가 다시 돌아, 안 끊으면 연결이 한 겹씩
    --     쌓이고 옛 연결이 이미 Destroy 된 바를 계속 만진다.
    --   ⚠️ 같은 함정을 Stage2TriggerSystem.watchKingDamage 가 세대 토큰으로 막고 있다.
    info.conns[#info.conns + 1] = hum.HealthChanged:Connect(function(hp)
        if not tracked[char] then return end
        -- ⚠️ 회복도 HealthChanged 를 부른다. 줄어들 때만 띄운다.
        if hp < info.lastHp then
            info.hideAt = os.clock() + SHOW_DURATION
            bb.Enabled = true
        end
        info.lastHp = hp

        local ratio = math.clamp(hp / math.max(hum.MaxHealth, 1), 0, 1)
        -- ⚠️ 상세형은 안쪽 여백 2px 를 쓴다(태거 양식). 간소형은 여백이 없다.
        --   같은 식을 쓰면 상세형 바가 트랙 밖으로 2px 삐져나온다.
        if text then
            fill.Size = UDim2.new(ratio, ratio > 0 and -4 or 0, 1, -4)
            text.Text = string.format("%d / %d", math.ceil(hp), math.ceil(hum.MaxHealth))
        else
            fill.Size = UDim2.fromScale(ratio, 1)
        end
        -- 🎨 밝은 청 → 어두운 청. 색상은 고정(진영), 명도만 잔량 — 상단 주석 참조.
        fill.BackgroundColor3 = RUNNER_FULL:Lerp(RUNNER_LOW, 1 - ratio)

        if hp <= 0 then
            bb.Enabled = false
        end
    end)

    info.conns[#info.conns + 1] = hum.Died:Connect(function()
        if bb and bb.Parent then bb.Enabled = false end
        tracked[char] = nil
    end)
end

-- ⚠️ 봇은 라운드마다 새로 스폰되므로 주기적으로 훑는다.
--    ChildAdded 만 쓰면 시스템 시작 전에 이미 있던 봇을 놓친다.
-- 🧑 [2026-09-11] 유저 러너의 리스폰도 이 스윕이 받는다. tracked 키가 캐릭터라
--    새 몸이 오면 자동으로 미등록 상태가 되고 다음 바퀴에 붙는다 (최대 1초 지연).
--    라운드 시작 직후엔 피격이 없으므로 그 지연이 문제되지 않는다.
task.spawn(function()
    while true do
        task.wait(1.0)
        for _, m in ipairs(workspace:GetChildren()) do
            if isTrackedRunner(m) then attach(m) end
        end
        -- 사라진 대상 정리 + 🔴 [버그수정 2026-09-20] 러너가 아니게 된 대상의 바 회수.
        --   [증상] 태거 머리 위에 HP바가 둘 떴다 — 크림슨(태거)과 청색(러너).
        --     청색이라 진영색이 거짓말을 했다("색상 = 누구냐" 원칙 위반).
        --   [원인] isTrackedRunner 는 '붙일 때'만 본다. 해제 경로가 둘뿐인데
        --     둘 다 이 상황에 도달하지 못한다:
        --       ① hum.Died        — 살아서 라운드를 끝내면 안 뜬다
        --       ② char.Parent 소멸 — 로비 복귀는 캐릭터를 유지한다(Stage2TriggerSystem:71)
        --     러너로 살아남은 사람이 다음 판 태거가 되면 청색 바가 그대로 따라온다.
        --     ItemDamageSystem:1010 에 글자 그대로 같은 사고가 적혀 있다(그때는 훅).
        --   [해결] 붙일 때와 뗄 때가 같은 함수(isTrackedRunner)를 보게 한다.
        --     기준이 하나뿐이라 한쪽만 갱신되어 갈라질 수가 없다.
        --   ⚠️ HealthDisplayType 은 되돌리지 않는다. 되돌리면 로블록스 기본 바가 살아나
        --     attach 의 194행이 없애려던 중복이 그대로 돌아온다.
        --   ⚠️ 인터미션에는 Role 이 없어 전원이 여기서 회수된다. 의도한 동작이다 —
        --     다음 라운드 시작 때 스윕이 다시 붙인다(최대 1초, 그 사이 피격 없음).
        for char, info in pairs(tracked) do
            if not char.Parent then
                tracked[char] = nil
            elseif not isTrackedRunner(char) then
                if info.conns then
                    for _, c in ipairs(info.conns) do pcall(function() c:Disconnect() end) end
                end
                if info.gui then info.gui:Destroy() end
                tracked[char] = nil
            end
        end
    end
end)

workspace.ChildAdded:Connect(function(m)
    task.wait(0.3)   -- Humanoid·Head 가 붙을 때까지
    if isTrackedRunner(m) then
        attach(m)
    end
end)

-- 시간이 지나면 숨긴다
-- ⏱️ [2026-09-11] 2단계에는 상시 노출한다.
--   [왜] 2단계는 HP 소모전이라 "얼마 남았나"가 매 순간 판단에 들어간다.
--     피격 시 4초만 보이면 정작 볼 때 안 보인다.
--   [왜 1단계는 그대로인가] 1단계는 한 방 다운이라 HP 가 사실상 이진값이고,
--     봇 10마리가 몰려오는 구간이라 상시로 띄우면 화면이 바로 지저분해진다.
--   [왜 이 규칙인가] TaggerHpDisplay 가 이미 "2단계에만 노출" 이다. 새 기준이 아니라
--     기존 규칙의 재사용이라, 히어로봇이 들어와도 갈리지 않는다.
--   ⚠️ RoundPhase 는 ReplicatedStorage 속성이다(_WalkSpeedProbe:27 과 같은 출처).
--     여기서만 쓰는 별도 플래그를 만들지 말 것.
task.spawn(function()
    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        local stage2 = (ReplicatedStorage:GetAttribute("RoundPhase") == "stage2")
        local now = os.clock()
        for char, info in pairs(tracked) do
            local gui = info.gui
            if gui and gui.Parent then
                if stage2 then
                    -- 살아 있으면 계속 보인다. 사망 시엔 HealthChanged 가 이미 껐다.
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then gui.Enabled = true end
                elseif gui.Enabled and now > info.hideAt then
                    gui.Enabled = false
                end
            end
        end
    end)
end)

print("🩸 RunnerHealthBar 준비 (AI + 유저 공용, 기본 HP바 OFF)")
