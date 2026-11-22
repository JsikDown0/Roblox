-- PlayerMarkerClient (통합 마커 — 적 진영 위치 표시)
-- 내 Role에 따라 "상대 진영"에게만 초상화 + 빨강 빛기둥 선을 그린다.
--   내가 Tagger → 모든 러너(실제 Role=Runner 플레이어 + RunnerBot 봇)에 마커
--   내가 Runner → 모든 태거(실제 Role=Tagger 플레이어 + TaggerDummy 더미)에 마커
-- 클라이언트 생성이라 내 화면에만 보임 → 적에게 내 위치가 새지 않음.
-- 실제 플레이어 러너는 아바타 headshot, 그 외(봇/더미)는 노란 원+NPC.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- 🛡️ [2026-08-26] 마커 테두리로 내구도(방패) 상태를 알린다.
--
-- [왜] 마커가 '누구인지' 만 알려줬다. 태거에게 정작 필요한 정보는
--   "저 러너가 방패를 갖고 있나" 다 — 그게 아이템을 쓸지 말지를 정하기 때문이다.
--   방패가 있으면 한 방은 흡수되므로, 스피어 같은 단일 표적 정밀 무기는
--   낭비가 된다(실측: 스피어 7명중 → 다운 2명, 5회가 서로 다른 러너의 방패에 먹힘).
--   방패가 없는 대상을 골라 치면 명중이 곧 다운이 된다.
--
-- ⚠️ 얼굴을 없애지 않고 테두리에 정보를 얹는다. 초상화는 여전히
--   "누구인지" 를 알려주고(멀티에서 필요), 색이 "지금 칠 대상인지" 를 알려준다.
-- ⚠️ 태거 화면에만 그려진다(이 스크립트가 클라이언트 생성). 러너에게는 안 보인다.
-- ⚠️ 러너가 태거를 볼 때도 이 마커를 쓴다. 그때는 태거에게 내구도가 없으므로
--   기본색으로 남는다 — applyShieldTint 가 속성 없음을 그대로 처리한다.
local SHIELD_COLOR   = Color3.fromRGB(255, 210, 60)   -- DurabilitySystem.COL_FILL 과 동일
local NOSHIELD_COLOR = Color3.fromRGB(255, 70, 70)    -- 방패 없음 = 지금 치면 다운
local NEUTRAL_COLOR  = Color3.fromRGB(0, 0, 0)        -- 내구도 개념이 없는 대상

-- 테두리 색·굵기를 현재 내구도에 맞춘다.
local function applyShieldTint(model, stroke)
    if not (model and stroke and stroke.Parent) then return end
    local dur = model:GetAttribute("Durability")
    if dur == nil then
        -- 내구도 시스템 대상이 아님(태거 등) → 기본 검정 테두리
        stroke.Color = NEUTRAL_COLOR
        stroke.Thickness = 2
        return
    end
    if dur > 0 then
        stroke.Color = SHIELD_COLOR
        stroke.Thickness = 4        -- 두껍게 = "한 겹 더 있다" 는 인상
    else
        stroke.Color = NOSHIELD_COLOR
        stroke.Thickness = 2
    end
end

-- 🪤 [2026-08-26] 함정에 묶인 대상을 마커로 지목한다.
--
-- [왜] 태거는 함정이 걸렸는지 알 방법이 사실상 없었다. 밟힘 사운드는 80 stud
--   반경이고 맵은 약 870 stud 다. 배지(4/5→3/5)는 함정이 파괴되는 시점,
--   즉 러너가 풀려나는 순간에야 내려가서 "잡았다"가 아니라 "놓쳤다"를 알렸다.
--
-- [방식] 마커는 이미 모든 러너 머리 위에 있다. 새 시스템을 만드는 대신
--   기존 빛기둥의 색과 초상화 위 배지만 바꾼다 — 태거가 이미 보고 있는 자리다.
--
-- ⚠️ 테두리(UIStroke)는 건드리지 않는다. 그건 방패 상태 전용이다.
--   두 정보를 같은 채널에 실으면 둘 다 못 읽는다. 기둥=묶임 / 테두리=방패로 분리.
-- ⚠️ TrapHit / TrapHitUntil 은 TrapSystem 이 한 짝으로 세우고 지운다.
--   둘 중 하나만 보면 해제 후에도 상태가 굳는다.
-- ⚠️ [색 선택 근거 — 2026-08-26 전수 조사] 처음엔 연두(120,255,140)를 썼다가 폐기했다.
--   [왜 폐기] 이 게임에서 초록은 이미 "체력이 높다"는 뜻이다:
--     BotHealthBarSystem(90,200,90) / TaggerHpDisplay(60,200,90),(120,230,140).
--     묶인 러너에 초록을 씌우면 "쟤 멀쩡함"으로 읽혀 의미가 정반대가 된다.
--     게다가 TaggerHpDisplay(120,230,140)과 RGB가 거의 같아 화면에서 구분도 안 된다.
--   [왜 청록] 태거 HUD 전체에서 파랑/청록 계열 사용처가 0건이다(빨강·노랑·주황·초록은 전부 선점).
--     빨강→청록은 '파랑 채널' 차이라 적록색약에서도 구분이 살아남는다.
--     (빨강→초록은 적록색약에게 가장 안 보이는 조합이다)
--     주황(용암)·초록(잔디)·갈색 지형의 보색이라 배경 대비도 최대다.
--   ⚠️ 메타 UI 의 Runner 탭이 파랑이지만 그건 로비 화면이고 인게임 HUD 와 같이 뜨지 않는다.
--   ⚠️ 새 상태 색을 추가할 땐 이 조사부터 다시 할 것 — 남은 빈 칸이 거의 없다.
local TRAP_PILLAR_COLOR = Color3.fromRGB(0, 225, 255)    -- 묶임 = "지금 가면 잡는다"
local TRAP_STROKE_COLOR = Color3.fromRGB(0, 70, 105)     -- 청록 기둥의 어두운 짝
local BASE_PILLAR_COLOR = Color3.fromRGB(255, 40, 40)    -- 평상시(기존 값)
local BASE_STROKE_COLOR = Color3.fromRGB(120, 0, 0)      -- 평상시(기존 값)
local BASE_PILLAR_TRANS = 0.15                           -- 평상시(기존 값)

-- 초상화 위 🪤 + 남은 초. 묶여 있는 동안만 보인다.
-- ⚠️ 색만으로 알리지 않는다. 기존 코드가 방패를 색+두께로 이중 인코딩하는 것과 같은 원칙 —
--   여기서는 색 + 맥동(아래 startCountdown)을 쓴다. 움직임은 아직 아무도 안 쓰는 채널이라
--   색이 안 보이는 사람에게도, 화면 구석에 있어도 눈에 걸린다.
local function applyTrapState(model, pillar, badge)
    if not (model and pillar and pillar.Parent and badge and badge.Parent) then return end
    local stroke = pillar:FindFirstChildOfClass("UIStroke")
    if model:GetAttribute("TrapHit") then
        pillar.BackgroundColor3 = TRAP_PILLAR_COLOR
        if stroke then stroke.Color = TRAP_STROKE_COLOR end
        badge.Visible = true
    else
        pillar.BackgroundColor3 = BASE_PILLAR_COLOR
        pillar.BackgroundTransparency = BASE_PILLAR_TRANS   -- 맥동 원복 (짝)
        if stroke then stroke.Color = BASE_STROKE_COLOR end
        badge.Visible = false
    end
end

-- ── 마커 생성 ────────────────────────────────────────────
-- avatarUserId: 숫자면 그 유저의 headshot 사용, nil이면 노란 원+NPC
local function buildMarker(model, avatarUserId)
    local head = model:FindFirstChild("Head")
    if not head then return end
    if head:FindFirstChild("RunnerProfile") then return end  -- 이미 있음

    -- 초상화
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RunnerProfile"
    billboard.Size = UDim2.new(10, 0, 10, 0)
    billboard.StudsOffset = Vector3.new(0, 52, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 2000
    billboard.LightInfluence = 0
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = avatarUserId and Color3.fromRGB(255,255,255) or Color3.fromRGB(255, 255, 100)
    frame.Parent = billboard
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 2
    stroke.Parent = frame

    -- 🛡️ 내구도 상태를 테두리에 반영하고, 변화를 추적한다.
    -- ⚠️ 연결은 billboard 가 사라질 때 함께 끊어야 한다. 마커는 라운드마다
    --   다시 만들어지므로, 안 끊으면 연결이 계속 쌓인다.
    applyShieldTint(model, stroke)
    local durConn = model:GetAttributeChangedSignal("Durability"):Connect(function()
        applyShieldTint(model, stroke)
    end)
    billboard.Destroying:Connect(function()
        if durConn then durConn:Disconnect(); durConn = nil end
    end)
    if avatarUserId then
        -- 실제 플레이어 아바타 headshot
        local avatar = Instance.new("ImageLabel")
        avatar.Size = UDim2.new(0.9, 0, 0.9, 0)
        avatar.Position = UDim2.new(0.05, 0, 0.05, 0)
        avatar.BackgroundTransparency = 1
        avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. avatarUserId .. "&width=150&height=150&format=png"
        avatar.Parent = frame
        local ac = Instance.new("UICorner")
        ac.CornerRadius = UDim.new(1, 0)
        ac.Parent = avatar
    else
        -- 봇/더미: NPC 라벨
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "NPC"
        label.TextColor3 = Color3.fromRGB(0, 0, 0)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = frame
    end
    billboard.Parent = head

    -- 빨강 빛기둥 선
    local PILLAR_HEIGHT = 50
    local PILLAR_WIDTH  = 1.2
    local beamGui = Instance.new("BillboardGui")
    beamGui.Name = "RunnerBeam"
    beamGui.Adornee = head
    beamGui.AlwaysOnTop = true
    beamGui.MaxDistance = 2000
    beamGui.LightInfluence = 0
    beamGui.Size = UDim2.fromScale(PILLAR_WIDTH, PILLAR_HEIGHT)
    beamGui.StudsOffset = Vector3.new(0, PILLAR_HEIGHT / 2, 0)
    local pillar = Instance.new("Frame")
    pillar.Size = UDim2.fromScale(1, 1)
    pillar.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
    pillar.BackgroundTransparency = 0.15
    pillar.BorderSizePixel = 0
    pillar.Parent = beamGui
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
    beamGui.Parent = head

    -- 🪤 묶임 배지 (초상화 위). 기본은 숨김.
    local trapBadge = Instance.new("TextLabel")
    trapBadge.Name = "TrapBadge"
    trapBadge.AnchorPoint = Vector2.new(0.5, 1)
    trapBadge.Position = UDim2.new(0.5, 0, 0, -2)
    trapBadge.Size = UDim2.new(1.1, 0, 0.34, 0)
    trapBadge.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    trapBadge.BackgroundTransparency = 0.15
    trapBadge.Font = Enum.Font.GothamBold
    trapBadge.TextScaled = true
    trapBadge.TextColor3 = TRAP_PILLAR_COLOR
    trapBadge.Text = "🪤"
    trapBadge.Visible = false
    trapBadge.Parent = frame
    local tbc = Instance.new("UICorner")
    tbc.CornerRadius = UDim.new(0, 6)
    tbc.Parent = trapBadge

    -- ⏳ 남은 초 갱신.
    -- ⚠️ 폴링이 아니라 '묶여 있는 동안만' 도는 루프다. 평상시엔 아무것도 안 돈다
    --   (러너 10명 × 매프레임 속성 읽기를 피한다).
    -- ⚠️ 종료 조건 3개를 모두 본다: 배지 소멸 / 속성 해제 / 시간 만료.
    --   하나라도 빠지면 라운드가 끝나도 루프가 남는다.
    local function startCountdown()
        task.spawn(function()
            local t = 0
            while trapBadge.Parent and model:GetAttribute("TrapHit") do
                local until_ = model:GetAttribute("TrapHitUntil")
                if not until_ then break end
                local remain = until_ - workspace:GetServerTimeNow()
                if remain <= 0 then break end
                trapBadge.Text = string.format("🪤 %.1f", remain)
                -- 💓 맥동: 이 루프가 이미 돌고 있으므로 추가 비용이 없다.
                --   색이 안 보이는 사람에게도, 시야 구석에 있어도 걸리게 하는 두 번째 채널.
                t += 0.1
                if pillar.Parent then
                    pillar.BackgroundTransparency = BASE_PILLAR_TRANS
                        + 0.34 * (0.5 + 0.5 * math.sin(t * 9))
                end
                task.wait(0.1)
            end
            -- ⚠️ 켠 것은 반드시 되돌린다. 안 하면 해제 후에도 반투명하게 굳는다.
            --   (applyTrapState 도 같은 복원을 하지만, 속성 해제 없이 시간 만료로
            --    빠져나오는 경로가 있어 여기서도 한 번 더 원복한다)
            if pillar.Parent then pillar.BackgroundTransparency = BASE_PILLAR_TRANS end
            if trapBadge.Parent then trapBadge.Text = "🪤" end
        end)
    end

    -- 상태 반영 + 추적.
    -- ⚠️ 연결은 하나만 둔다. durConn 과 같은 규칙으로 billboard 소멸 시 끊는다.
    --   (한때 색 갱신용과 카운트다운용을 따로 걸었다가 후자가 해제 대상에서
    --    빠져 라운드마다 쌓였다 — 같은 신호는 한 연결에서 처리할 것)
    applyTrapState(model, pillar, trapBadge)
    if model:GetAttribute("TrapHit") then startCountdown() end
    local trapConn = model:GetAttributeChangedSignal("TrapHit"):Connect(function()
        applyTrapState(model, pillar, trapBadge)
        if model:GetAttribute("TrapHit") then startCountdown() end
    end)
    billboard.Destroying:Connect(function()
        if trapConn then trapConn:Disconnect(); trapConn = nil end
    end)
end

local function clearMarker(model)
    local head = model and model:FindFirstChild("Head")
    if not head then return end
    local p = head:FindFirstChild("RunnerProfile")
    if p then p:Destroy() end
    local b = head:FindFirstChild("RunnerBeam")
    if b then b:Destroy() end
end

-- 내 역할 기준, 마커를 붙일 "적 진영 대상" 목록 수집
-- 반환: { {model=Model, userId=숫자또는nil}, ... }
local function collectTargets()
    local myRole = player:GetAttribute("Role")
    local targets = {}
    if myRole == "Tagger" then
        -- 적 = 러너들: 실제 Role=Runner 플레이어 + RunnerBot 봇
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= player and pl:GetAttribute("Role") == "Runner" and pl.Character then
                table.insert(targets, {model = pl.Character, userId = pl.UserId})
            end
        end
        for _, m in ipairs(workspace:GetChildren()) do
            -- ⚠️ [2026-09-06] 분신(IsDecoy)도 포함한다.
            --   [왜] 태거는 마커로 러너를 찾는다. 분신만 마커가 없으면 "마커 없는 러너"가
            --     곧 가짜라는 표식이 되어, 아이템의 존재 이유가 사라진다.
            --   ⚠️ RunnerBot 속성을 대신 붙이는 방법도 있었지만 쓰지 않았다 —
            --     러너 무기의 아군 판정(HammerScript 등)이 RunnerBot 을 아군으로 걸러서,
            --     주인이 자기 분신을 못 때리는 것까지는 맞지만 다른 시스템에도 번진다.
            --     여기서 한 줄로 끝내는 편이 파급이 없다.
            if m:IsA("Model") and (m:GetAttribute("RunnerBot") or m:GetAttribute("IsDecoy")) then
                -- 분신은 주인의 UserId 를 물려받아 프로필 사진까지 같게 보인다.
                -- 봇(RunnerBot)은 원래 아바타가 없으므로 nil 그대로.
                table.insert(targets, {model = m, userId = m:GetAttribute("DecoyOwnerId")})
            end
        end
    elseif myRole == "Runner" then
        -- 적 = 태거들: 실제 Role=Tagger 플레이어 + TaggerDummy 더미
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= player and pl:GetAttribute("Role") == "Tagger" and pl.Character then
                table.insert(targets, {model = pl.Character, userId = pl.UserId})
            end
        end
        for _, m in ipairs(workspace:GetChildren()) do
            -- 🚫 [2026-09-19] 로비 훈련 더미는 제외한다.
            --   [증상] 러너로 라운드에 들어가면 로비 훈련장 더미 4체에도 빛기둥이 섰다.
            --   [원인] TaggerDummy 속성을 **봇 킹과 훈련 더미가 공유**한다.
            --     이 목록은 "적 진영 태거"를 찾는 용도인데, 훈련 더미는 적이 아니라
            --     로비 설치물이다. 같은 표식이 두 가지 뜻으로 쓰이고 있었다.
            --   [왜 LobbyDummy 로 거르나] 이미 더미에만 붙어 있는 표식이고
            --     PushTool 의 훈련장 예외·무피해 판정도 같은 속성을 쓴다.
            --     이름 목록을 새로 만들지 않는다.
            --   ⚠️ TaggerDummy 를 더미에서 떼는 방향은 쓰지 않았다 — 그 속성을 읽는 곳이
            --     여기 말고도 있어서(PushChargeFxViewer 등) 파급을 못 가늠한다.
            --     읽는 쪽에서 거르는 편이 안전하다.
            if m:IsA("Model") and m:GetAttribute("TaggerDummy")
               and not m:GetAttribute("LobbyDummy") then
                table.insert(targets, {model = m, userId = nil})
            end
        end
    end
    return targets
end

-- 전체 갱신: 대상엔 마커 부여, 그 외 마커는 정리
local function markersEnabled()
    if _G.MarkersEnabled == nil then return true end
    return _G.MarkersEnabled
end

local function refreshAll()
    -- 마커 토글이 꺼져 있으면 대상 없음 처리 → 아래 정리 로직이 전부 제거
    local targets = markersEnabled() and collectTargets() or {}
    local targetSet = {}
    for _, t in ipairs(targets) do
        targetSet[t.model] = true
        buildMarker(t.model, t.userId)
    end
    -- 더 이상 대상이 아닌 곳의 잔존 마커 제거 (역할 전환 시 등)
    -- 플레이어 캐릭터 + 봇/더미 모두 점검
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character and not targetSet[pl.Character] then
            clearMarker(pl.Character)
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and (m:GetAttribute("RunnerBot") or m:GetAttribute("TaggerDummy")) then
            if not targetSet[m] then clearMarker(m) end
        end
    end
end

-- 내 역할 변경 시 갱신
player:GetAttributeChangedSignal("Role"):Connect(refreshAll)

-- 다른 플레이어의 역할 변경/입장 감지
local function hookPlayer(pl)
    pl:GetAttributeChangedSignal("Role"):Connect(refreshAll)
    pl.CharacterAdded:Connect(function() task.wait(0.3); refreshAll() end)
end
for _, pl in ipairs(Players:GetPlayers()) do hookPlayer(pl) end
Players.PlayerAdded:Connect(hookPlayer)

-- 봇/더미 추가 감지
workspace.ChildAdded:Connect(function(m)
    if m:IsA("Model") and (m:GetAttribute("RunnerBot") or m:GetAttribute("TaggerDummy")) then
        task.wait(0.3); refreshAll()
    end
end)

-- 주기 점검: 캐릭터 리스폰/봇 리셋으로 마커가 사라지면 재부여.
-- 마커 토글(_G.MarkersEnabled) 변경도 여기서 감지(시그널 없으므로 폴링).
task.spawn(function()
    local lastEnabled = markersEnabled()
    while true do
        local nowEnabled = markersEnabled()
        if nowEnabled ~= lastEnabled then
            lastEnabled = nowEnabled
            refreshAll()  -- 토글 변경 시 즉시 부여/제거
        end
        if nowEnabled then
            local targets = collectTargets()
            for _, t in ipairs(targets) do
                local head = t.model:FindFirstChild("Head")
                if head and not head:FindFirstChild("RunnerBeam") then
                    buildMarker(t.model, t.userId)
                end
            end
        end
        task.wait(1)
    end
end)

refreshAll()
print("✅ PlayerMarkerClient 활성화 (적 진영 마커 — 내 화면에만)")
