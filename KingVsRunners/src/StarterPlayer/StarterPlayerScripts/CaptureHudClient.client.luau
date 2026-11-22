-- 👑 왕좌 점령 게이지 (2단계 목표 표시)
--
-- ⚠️ 이게 없으면 점령 시스템이 있어도 유저는 모른다. 2단계가 안 와닿는
--    원인이 "목표가 명시되지 않아서"였으므로, 표시가 기능의 절반이다.
-- ⚠️ 텍스트보다 게이지가 먼저다. 저연령·해외 유저에게 "저기 뭔가 차오른다"가
--    문장보다 빨리 읽힌다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("CaptureState")

-- ⚠️ [2026-09-02] barFill·ring 제거됨(상단 진행 바 삭제). 진행률은 각 점령지 위
--    게이지가 담당한다(CaptureSystem.ensureGauge). 여기는 상태 문구만 띄운다.
local gui, label
local BAR_W = 300

local function build()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local prev = pg:FindFirstChild("CaptureHud")
    if prev then prev:Destroy() end

    gui = Instance.new("ScreenGui")
    gui.Name = "CaptureHud"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 120
    gui.Parent = pg

    local holder = Instance.new("Frame")
    holder.Name = "Holder"
    holder.AnchorPoint = Vector2.new(0.5, 0)
    -- ⚠️ 상단 라운드 타이머(중앙 상단)와 겹치지 않게 그 아래로 내린다.
    holder.Position = UDim2.new(0.5, 0, 0, 62)
    holder.Size = UDim2.fromOffset(BAR_W, 24)
    holder.BackgroundTransparency = 1
    holder.Visible = false
    holder.Parent = gui

    -- 🏆 [2026-09-02] 상단 진행 바 제거. 텍스트(상태 문구)만 남긴다.
    --   [왜] 존별 게이지를 각 점령지 위에 띄우면서(CaptureSystem.ensureGauge) 진행률이
    --     두 곳에 표시돼 헷갈렸다. 존 위 게이지는 '어느 존이 얼마나' 를 위치와 함께
    --     보여주므로 정보량이 더 많다. 상단 바는 그 하위집합이라 지운다.
    --   ⚠️ 문구는 남긴다. "왜 안 차는지"(킹이 밟고 있음/아무도 없음)는 존 게이지가
    --     알려주지 못하는 정보다. 색도 문구에 그대로 옮겨 상태 구분을 유지한다.
    label = Instance.new("TextLabel")
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 0)
    label.Size = UDim2.new(1, 0, 0, 24)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 220, 90)
    label.TextStrokeTransparency = 0.4
    label.Text = "CAPTURE THE THRONE"
    label.Parent = holder
end

local function show(v) if gui then gui.Holder.Visible = v end end

remote.OnClientEvent:Connect(function(kind, ratio, runners, taggerInside)
    if not gui or not gui.Parent then build() end
    if not gui then return end

    -- 🚪 [버그수정 2026-09-20] 로비 대기자에게는 띄우지 않는다.
    --   [증상] 라이브 제보 — 로비에 있는데 점령지 현황이 공유된다.
    --   [원인] CaptureState 는 FireAllClients 라 라운드에 없는 사람에게도 간다.
    --     그리고 라이브에서 로비에 있는 사람은 대부분 라운드 중이다 —
    --     죽어서 관전 중이거나 라운드 도중 접속해 기다리는 중이다.
    --     그 전원이 "CAPTURE THE THRONE" 이라는 **자기 판이 아닌 지시**를 받고 있었다.
    --   [기준] 전역 페이즈가 아니라 **내 Role** 이다. 참가자에게만 세워진다
    --     (RoundSystem 이 라운드 시작에 세우고 :2224 에서 지운다).
    --     죽어서 관전 중인 참가자는 Role 이 남아 있어 계속 본다 — 자기 판이니 맞다.
    --   ⚠️ 서버(CaptureSystem)에서 거르지 않는 이유가 있다. stop 을 Role 로 거르면
    --     Role 이 먼저 지워지는 순간 해제 신호가 그 사람에게 영영 안 가서
    --     HUD 가 화면에 굳는다. **끄는 신호는 조건 없이 도착해야 한다**
    --     ("켜는 코드에 끄는 코드를 같이" 의 반대편 — 끄는 쪽에 조건을 달지 않는다).
    if player:GetAttribute("Role") == nil then
        show(false)
        return
    end

    -- 👑 [2026-09-20] 역할별 문구. ⚠️ 매번 읽는다 — Role 은 라운드 시작에 세워지므로
    --   캐싱하면 첫 라운드에 nil 로 굳는다(ReviveClient 가 같은 함정을 주석으로 남겼다).
    local isKing = player:GetAttribute("Role") == "Tagger"

    if kind == "start" then
        show(true)
        label.Text = isKing and "DEFEND THE THRONE" or "CAPTURE THE THRONE"
        label.TextColor3 = Color3.fromRGB(255, 210, 60)
        return
    elseif kind == "stop" then
        show(false)
        return
    end

    show(true)

    -- 상태별 색/문구. ⚠️ 왜 안 차는지를 알려주는 게 핵심이다.
    --    막혀 있는데 이유를 모르면 "버그인가?" 가 된다.
    -- ⚠️ [2026-09-02] 진행 바를 지우면서 색을 문구로 옮겼다. 진행률은 각 점령지 위
    --    게이지가 담당하고, 여기는 '상태'만 알린다.
    -- 👑 [버그수정 2026-09-20] 킹 전용 문구.
    --   [증상] 라이브 관전 — 태거가 존을 지켜야 한다는 규칙 자체를 모른다.
    --     멀뚱히 서 있다가 존을 뺏기고 디버프에 걸려 진다.
    --   [원인] 이 파일에 Role 검사가 **한 줄도 없었다.** 킹과 러너가 같은 문구를 보는데
    --     그 문구가 전부 러너 관점이다 — "CAPTURE THE THRONE"(점령하라),
    --     "DRIVE THE KING OUT"(킹을 몰아내라). 킹은 자기 화면에서
    --     **자기 자신을 몰아내라는 지시**를 받고 있었다.
    --     안 가르치는 게 아니라 틀린 걸 가르치고 있었던 것이다.
    --   [왜 여기서 고치나] 서버가 이미 taggerInside 를 보내준다. 킹 전용 문구에 필요한
    --     데이터가 전부 와 있는데 안 쓰고 있었다 — 새 신호를 만들 필요가 없다.
    --   ⚠️ 색도 같이 뒤집는다. 색은 '좋다/나쁘다'를 뜻하는데 그 판단이 진영마다 반대다.
    --     킹에게 taggerInside=true 는 초록(잘하고 있다), 러너에게는 빨강(막혔다)이다.
    --     문구만 뒤집고 색을 두면 "초록인데 위험" 같은 모순이 생긴다.
    --   ⚠️ 문구는 명령형으로 둔다. 상태 서술("THRONE IS SAFE")보다 지시가
    --     "지금 뭘 해야 하나"를 바로 준다 — 규칙을 모르는 사람이 대상이기 때문이다.
    if isKing then
        if taggerInside then
            label.TextColor3 = Color3.fromRGB(140, 245, 160)
            label.Text = "HOLDING THE THRONE"
        elseif (runners or 0) > 0 then
            label.TextColor3 = Color3.fromRGB(255, 120, 110)
            label.Text = "THRONE UNDER ATTACK — GET BACK!"
        else
            label.TextColor3 = Color3.fromRGB(255, 210, 60)
            label.Text = "DEFEND THE THRONE"
        end
    elseif taggerInside then
        label.TextColor3 = Color3.fromRGB(255, 120, 110)
        -- ⚠️ [2026-08-25] 완전 차단 → 감속으로 바뀌었다.
        --    "BLOCKED" 는 멈춘다는 뜻이라 오해를 준다.
        label.Text = "SLOWED — DRIVE THE KING OUT"
    elseif (runners or 0) > 0 then
        label.TextColor3 = Color3.fromRGB(140, 245, 160)
        label.Text = "CAPTURING..."
    else
        label.TextColor3 = Color3.fromRGB(255, 210, 60)
        label.Text = "CAPTURE THE THRONE"
    end
end)

-- 🔄 안전망. 라운드에서 빠지는 순간(종료·배치실패·제외) 즉시 숨긴다.
--   ⚠️ stop 이벤트를 놓쳐도 화면에 안 남게 하는 두 번째 경로다. 위 가드는 '다음 이벤트가
--     올 때' 판단하므로, 라운드가 끝나고 이벤트가 더 안 오면 그 가드는 영영 안 돈다.
player:GetAttributeChangedSignal("Role"):Connect(function()
    if player:GetAttribute("Role") == nil then show(false) end
end)

player.CharacterAdded:Connect(function()
    task.wait(0.5)
    if not gui or not gui.Parent then build() end
end)

build()
