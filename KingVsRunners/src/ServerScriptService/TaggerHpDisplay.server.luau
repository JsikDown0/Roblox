-- TaggerHpDisplay
-- 태거 캐릭터 머리 위에 HP 바를 표시 (모든 클라이언트가 봄).
-- BillboardGui 를 서버에서 만들면 자동 복제되어 모든 클라가 봄.
-- HP 변화는 Humanoid.HealthChanged로 감지 → 바/텍스트 자동 업데이트.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── HP 표시 UI 생성 ──────────────────────────────────────
local function createDisplay(character)
    -- 🛡️ [2026-09-06] nil 방어. 라이브 오류 7건의 원인이다
    --   ("TaggerHpDisplay:10 attempt to index nil with 'WaitForChild'", V1184).
    --   [원인] 호출부가 task.wait(0.5) 뒤에 player.Character 를 넘기는데,
    --     그 0.5초 사이에 죽거나 나가면 nil 이 된다. 호출부 한 곳엔 검사가 있고
    --     다른 한 곳엔 없었다 — 같은 규칙이 두 곳에 있으면 한 곳만 고쳐진다는 그 패턴.
    --   ⚠️ 호출부가 아니라 여기서 막는다. 앞으로 호출부가 늘어나도 자동으로 덮인다.
    if not character or not character.Parent then return end
    local head = character:WaitForChild("Head", 5)
    if not head then return end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- 기존 정리 (재생성 시)
    local existing = head:FindFirstChild("TaggerHpDisplay")
    if existing then existing:Destroy() end

    -- BillboardGui (심플 + 두께감)
    -- VIP 태거: HP 바 금색 (기본은 초록)
    local plr = Players:GetPlayerFromCharacter(character)
    local isVIP = plr ~= nil and plr:GetAttribute("IsVIP") == true
    -- 🎨 [2026-09-11] 기본색을 초록 → 크림슨. 진영색 분리의 절반이다.
    --   [왜] 러너 바도 초록이라 둘이 같은 색이었고, 러너가 저체력이면 빨강으로
    --     변해서 오히려 더 헷갈렸다. 색상(hue)이 '누구냐'를 맡게 한다.
    --   ⚠️ RunnerHealthBar(BotHealthBarSystem)의 청색과 한 세트다.
    --     한쪽만 바꾸면 구분이 다시 무너진다.
    --   ⚠️ VIP 금색은 그대로 둔다. 그건 진영색이 아니라 과금 표식이라 축이 다르다.
    --     VIP 태거는 금색, 일반 태거는 크림슨 — 둘 다 청색(러너)과는 확실히 갈린다.
    --   ⚠️ 여기는 잔량 lerp 가 없다(고정색 + 그라디언트). 러너 쪽만 명도 lerp 를 쓴다 —
    --     킹은 한 명뿐이라 "누구냐"를 색으로 구분할 필요가 없어서다.
    local fillC   = isVIP and Color3.fromRGB(230, 180, 40)  or Color3.fromRGB(178, 34, 62)
    local gradTop = isVIP and Color3.fromRGB(255, 225, 120) or Color3.fromRGB(220, 70, 100)
    local gradBot = isVIP and Color3.fromRGB(190, 140, 20)  or Color3.fromRGB(110, 15, 38)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "TaggerHpDisplay"
    -- 스터드(scale) 단위 크기: 실제 3D 크기라 원근 적용 — 멀면 자연히 작아짐.
    -- (픽셀 고정은 거리 무관 동일 픽셀이라 원거리에서 주변 대비 거대해 보였음)
    billboard.Size = UDim2.new(5.5, 0, 0.85, 0)
    billboard.MaxDistance = 220                       -- 그보다 멀면 아예 숨김
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = false  -- 구조물 뒤에선 가려짐 (벽 너머 투시로 시야 가리던 것 방지)
    billboard.LightInfluence = 0
    billboard.Adornee = head
    billboard.MaxDistance = 1500
    billboard.Parent = head

    -- ⚠️ [2026-08-26] 1단계에서는 숨긴다.
    --   [왜] 1단계엔 러너가 태거를 때릴 수 없다(벽 뒤 + 불기둥은 러너만 태움).
    --   아무도 못 깎는 숫자를 40초 내내 띄우는 셈이다.
    --   게다가 라운드 시작 HP 는 '스폰 수' 기준이고, 2단계 진입 시
    --   '생존 러너' 로 재산정된다(Stage2TriggerSystem). 1단계에서 825 를
    --   보여주면 러너가 틀린 정보로 계획을 세운다.
    --   (실측 09:39 판: 1단계 38초 내내 825/825 노출)
    -- ⚠️ 삭제가 아니라 Enabled 토글이다. HealthChanged 연결과 갱신 로직을
    --   그대로 살려둬야 2단계 진입 순간 이미 최신값이 들어가 있다.
    -- ⚠️ 태거 더미(TaggerDummy)는 라운드 밖 테스트용이라 게이트하지 않는다.
    if Players:GetPlayerFromCharacter(character) then
        billboard:SetAttribute("PhaseGated", true)
        -- 🩸 [2026-08-29] 생성 시점 초기값도 refreshPhaseGate 와 같은 규칙을 쓴다.
        --   ⚠️ 캐릭터가 리스폰되면 이 GUI 가 새로 만들어진다. 여기 조건이 아래
        --     refreshPhaseGate 와 어긋나면 리스폰 직후에만 잘못 보인다.
        billboard.Enabled = (ReplicatedStorage:GetAttribute("RoundPhase") == "stage2")
                        and (ReplicatedStorage:GetAttribute("TaggerHpReady") == true)
    end

    -- HP 바 배경 (어두운 트랙)
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.Size = UDim2.new(1, 0, 1, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(15, 20, 15)
    barBg.BackgroundTransparency = 0.15
    barBg.BorderSizePixel = 0
    barBg.Parent = billboard

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 6)
    bgCorner.Parent = barBg

    -- 외곽선 (세련된 느낌)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    stroke.Parent = barBg

    -- HP 바 채움 (초록)
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, -4, 1, -4)              -- 안쪽 여백 (트랙 안에 떠있는 느낌)
    fill.Position = UDim2.new(0, 2, 0, 2)
    fill.BackgroundColor3 = fillC
    fill.BorderSizePixel = 0
    fill.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fill

    -- 그라디언트 (위는 밝게, 아래는 진하게 → 입체감)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, gradTop),
        ColorSequenceKeypoint.new(1, gradBot),
    }
    gradient.Rotation = 90  -- 위→아래
    gradient.Parent = fill

    -- HP 숫자 (간결, 바 위에 겹침)
    local hpText = Instance.new("TextLabel")
    hpText.Name = "HpText"
    hpText.Size = UDim2.new(1, 0, 1, 0)
    hpText.BackgroundTransparency = 1
    hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpText.TextScaled = true  -- 스터드 기반 바에 맞춰 텍스트도 원근 스케일
    hpText.Font = Enum.Font.GothamBold
    hpText.TextStrokeTransparency = 0
    hpText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    hpText.ZIndex = 2
    hpText.Parent = barBg

    -- 🛡️ [2026-09-02] CC 면역 표시 (라벨 + 몸을 감싸는 붉은 보호막).
    --   [왜] 면역은 '걸리나/안 걸리나' 두 상태뿐이라 예고가 가능하다. 러너가 던지기 전에
    --     보고 판단할 수 있어야 소모품을 헛되이 쓰지 않는다(마이크밤 150코인).
    --   [문구] "IMMUNE" 만 쓰면 데미지까지 막는 무적으로 읽힌다. CC 만 막는다고 명시한다.
    --   [색] 붉은 계열 — 러너 진영 UI(초록·파랑)와 구분되는 태거 색.
    --   ⚠️ [실패 이력] HP 바 BillboardGui 의 자식으로 넣었더니 Visible=true 인데도
    --     화면에 안 보였다(실측 15:56 — 로그는 정상, 화면은 무반응). 바 레이아웃에
    --     가려진 것으로 보인다. → 독립 BillboardGui 로 분리한다.
    --   ⚠️ 크기는 스터드(Scale) 단위다. 픽셀 고정은 원거리에서 거대해 보인다
    --     (TaggerHpDisplay:30 이 같은 이유로 이미 기각한 방식).
    local ccGui = Instance.new("BillboardGui")
    ccGui.Name = "CcImmuneGui"
    ccGui.Size = UDim2.new(4.4, 0, 0.8, 0)
    ccGui.StudsOffset = Vector3.new(0, 5.0, 0)   -- HP 바(3.5)보다 위
    ccGui.AlwaysOnTop = false
    ccGui.LightInfluence = 0
    ccGui.MaxDistance = 1500
    ccGui.Adornee = head
    ccGui.Enabled = false
    ccGui.Parent = head

    local ccLabel = Instance.new("TextLabel")
    ccLabel.Name = "CcImmuneLabel"
    ccLabel.Size = UDim2.new(1, 0, 1, 0)
    ccLabel.BackgroundColor3 = Color3.fromRGB(120, 20, 25)
    ccLabel.BackgroundTransparency = 0.1
    ccLabel.BorderSizePixel = 0
    ccLabel.Text = "CC IMMUNE"
    ccLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
    ccLabel.TextScaled = true
    ccLabel.Font = Enum.Font.GothamBold
    ccLabel.TextStrokeTransparency = 0
    ccLabel.TextStrokeColor3 = Color3.fromRGB(40, 0, 0)
    ccLabel.Parent = ccGui

    local ccCorner = Instance.new("UICorner")
    ccCorner.CornerRadius = UDim.new(0.3, 0)
    ccCorner.Parent = ccLabel

    local ccStroke = Instance.new("UIStroke")
    ccStroke.Color = Color3.fromRGB(255, 90, 90)
    ccStroke.Thickness = 2
    ccStroke.Parent = ccLabel

    -- 🔴 몸을 감싸는 보호막. Highlight 는 캐릭터 윤곽을 그대로 따라가 별도 메시가 필요 없다.
    --   ⚠️ DepthMode 를 AlwaysOnTop 으로 두면 벽 너머로도 비쳐 위치가 노출된다.
    --     Occluded 로 두어 시야에 있을 때만 보이게 한다.
    local ccShield = Instance.new("Highlight")
    ccShield.Name = "CcImmuneShield"
    ccShield.FillColor = Color3.fromRGB(255, 60, 60)
    ccShield.FillTransparency = 0.65
    ccShield.OutlineColor = Color3.fromRGB(255, 140, 140)
    ccShield.OutlineTransparency = 0.1
    ccShield.DepthMode = Enum.HighlightDepthMode.Occluded
    ccShield.Enabled = false
    ccShield.Adornee = character
    ccShield.Parent = character

    -- TaggerCcGuard 가 CcImmune 속성을 켜고 끈다. 여기선 그걸 따라가기만 한다.
    local function refreshCcImmune()
        local on = (character:GetAttribute("CcImmune") == true)
        ccGui.Enabled = on
        ccShield.Enabled = on
    end
    character:GetAttributeChangedSignal("CcImmune"):Connect(refreshCcImmune)
    refreshCcImmune()

    -- 🚫 [2026-09-11] 로블록스 기본 체력바를 끈다. 위 '손댈 수 없다' 주석의 정정.
    --   ⚠️ 이름표는 남는다 — HealthDisplayType 은 체력바만 끈다. 이름은 계속 필요하다.
    pcall(function()
        hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end)

    -- HP 업데이트 함수
    local function updateHp()
        local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        -- 안쪽 여백 4px 빼고 채움
        fill.Size = UDim2.new(ratio, ratio > 0 and -4 or 0, 1, -4)
        -- 🩸 [2026-08-30] floor → ceil.
        --   [증상] HP 바가 "0 / 907"인데 킹이 안 죽는다. 한 대 더 쳐야 죽는 것처럼 보였다.
        --   [원인] 분산 데미지가 소수(5.0/√N)라 잔량 0.6 같은 값이 남는데,
        --     floor 가 그걸 0 으로 깎아 보여줬다. Humanoid.Died 는 0 이하일 때만 발동하므로
        --     실제로는 정상 동작 — 판정이 아니라 표시가 거짓말을 하고 있었다.
        --   ⚠️ ceil 이면 0.01 도 1 로 표시된다. 즉 "0"은 진짜 죽었을 때만 나온다.
        --
        -- 🛡️ [2026-09-02] CC 배율을 되돌려 표시한다.
        --   [증상] 마이크밤·아이스보우로 킹을 묶으면 머리 위 숫자가 480/480 → 960/960 으로
        --     튀었다. 바 길이는 비율이라 안 움직이는데 숫자만 두 배가 되어, 러너 눈에는
        --     "얼렸더니 오히려 체력이 늘었다" 로 보인다.
        --   [원인] TaggerCcGuard 가 '피해 50% 감소'를 MaxHealth·Health ×2 로 구현한다.
        --     실제 값이 두 배인 게 맞고, 표시가 그걸 정직하게 보여준 것뿐이다.
        --   [해결] 표시에서만 배율로 나눈다. 판정은 건드리지 않는다 — 비율이 같으므로
        --     바 길이엔 영향이 없고 숫자만 제자리로 돌아온다. 피해도 체감대로 절반으로 보인다.
        --   ⚠️ CcHpScale 이 붙고 떨어지는 순간엔 Health 도 함께 바뀌므로(×2 / ÷2)
        --     HealthChanged 가 발동해 자동 갱신된다. 별도 신호를 걸 필요가 없다.
        --   ⚠️ [정정 2026-09-11] 아래 옛 주석은 틀렸다. 끌 수 있다 —
        --     Humanoid.HealthDisplayType = AlwaysOff 다. attachHp 진입부에서 끈다.
        --     단순히 '거슬리는' 문제가 아니었다. CcHpScale 이 붙으면 커스텀은 ÷배율로
        --     정직한 값을 내는데 기본 바는 원본(2배)을 그려서, 서로 다른 두 숫자가
        --     같은 머리 위에 동시에 떴다. 실측 18:21 판 스크린샷에서 확인.
        --   ⚠️ (폐기된 옛 주석) "유저 태거의 Roblox 기본 체력바는 손댈 수 없다"
        local scale = (hum.Parent and hum.Parent:GetAttribute("CcHpScale")) or 1
        hpText.Text = string.format("%d / %d",
            math.ceil(hum.Health / scale), math.ceil(hum.MaxHealth / scale))
    end

    -- 변화 감지
    local conn = hum.HealthChanged:Connect(updateHp)
    hum.Died:Connect(function() conn:Disconnect() end)

    -- 초기 표시
    updateHp()
end

-- ── 태거 역할 변경 감지 ─────────────────────────────────
local function watchPlayer(player)
    -- Role이 Tagger로 바뀌면 HP 표시
    player:GetAttributeChangedSignal("Role"):Connect(function()
        if player:GetAttribute("Role") == "Tagger" then
            task.wait(0.5)  -- 캐릭터 텔레포트 완료 대기
            if player.Character then
                createDisplay(player.Character)
            end
        else
            -- 태거 아님 → 기존 표시 제거
            local char = player.Character
            if char then
                local head = char:FindFirstChild("Head")
                if head then
                    local existing = head:FindFirstChild("TaggerHpDisplay")
                    if existing then existing:Destroy() end
                end
            end
        end
    end)

    -- 태거인 채로 캐릭터가 재생성되면 다시 표시
    player.CharacterAdded:Connect(function()
        if player:GetAttribute("Role") == "Tagger" then
            task.wait(0.5)
            -- ⚠️ wait 뒤에는 반드시 다시 확인한다. 위 Role 변경 핸들러엔 이 검사가
            --   있었는데 여기만 빠져 있었다.
            if player.Character then
                createDisplay(player.Character)
            end
        end
    end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    watchPlayer(player)
    -- 이미 태거인 경우 즉시 적용
    if player:GetAttribute("Role") == "Tagger" and player.Character then
        createDisplay(player.Character)
    end
end

-- ── 태거 더미(NPC) HP 표시 ──────────────────────────────
-- taggerdummy 등 TaggerDummy 속성을 가진 테스트 NPC는 플레이어가 아니라
-- watchPlayer 범위 밖이므로, 별도로 HP 바를 붙여준다.
local function tryApplyDummy(model)
    if not (model:IsA("Model") and model:GetAttribute("TaggerDummy")) then return end
    if not model:FindFirstChildOfClass("Humanoid") then return end
    task.spawn(function()
        createDisplay(model)
    end)
end

-- 이미 있는 더미들
for _, m in ipairs(workspace:GetChildren()) do
    tryApplyDummy(m)
end
-- 나중에 추가되는 더미
workspace.ChildAdded:Connect(function(m)
    task.wait(0.3)  -- 캐릭터 파츠 로드 대기
    tryApplyDummy(m)
end)

-- ── 단계 전환 시 HP 바 노출 토글 ────────────────────────
-- ⚠️ 이벤트가 아니라 Attribute 를 본다. 표시 대상이 서버 인스턴스라
--    이벤트 타이밍 경합이 없고, 라운드 중 재생성돼도 현재 값을 바로 읽는다.
-- ⚠️ PhaseGated 표식이 있는 것만 건드린다. 태거 더미는 항상 보인다.
--
-- 🩸 [2026-08-29] 조건이 둘이 됐다: 2단계 '그리고' HP 확정 완료.
--   [왜] HP 확정 시점이 '계단 진입' → '성문 붕괴' 로 옮겨졌다(Stage2TriggerSystem).
--     그래서 2단계 진입~붕괴 사이(실측 7~11초)에는 아직 확정 전이고,
--     그때 바를 띄우면 캐릭터 기본값 100 이 보이다가 붕괴 순간 825 로 튄다.
--     러너에겐 "때리지도 않았는데 HP 가 늘었다"로 읽혀 버그처럼 보인다.
--   ⚠️ 두 속성 모두를 감시해야 한다. 하나만 걸면 나중에 바뀌는 쪽을 놓친다.
local function isHpVisible()
    return ReplicatedStorage:GetAttribute("RoundPhase") == "stage2"
       and ReplicatedStorage:GetAttribute("TaggerHpReady") == true
end

local function refreshPhaseGate()
    local show = isHpVisible()
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        local head = char and char:FindFirstChild("Head")
        local gui = head and head:FindFirstChild("TaggerHpDisplay")
        if gui and gui:GetAttribute("PhaseGated") then
            gui.Enabled = show
        end
    end
end
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(refreshPhaseGate)
ReplicatedStorage:GetAttributeChangedSignal("TaggerHpReady"):Connect(refreshPhaseGate)

print("✅ TaggerHpDisplay 활성화 (태거 머리 위 HP 바 — 2단계에만 노출)")
