-- Stage2NotifyClient
-- 2단계 진입 시 화면에 큰 알림을 띄움.
-- 모든 플레이어가 봄 — "이제 Duel Phase가 시작됐다"는 명확한 시그널.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local Stage2Started = ReplicatedStorage:WaitForChild("Stage2Started")

-- 👑 [2026-09-20] 역할별 문구. **새 배너를 만들지 않고 이 배너를 가른다.**
--   [증상] 라이브 관전 — 킹이 존을 지켜야 한다는 규칙 자체를 모른다.
--     멀뚱히 서 있다가 존을 뺏기고 디버프에 걸려 진다.
--   [원인] 이 파일에도 Role 검사가 없었다(CaptureHudClient 와 같은 병).
--     킹이 보는 문구가 "A runner reached the altar" — 정보일 뿐 **지시가 없다.**
--     2단계는 킹의 할 일이 완전히 바뀌는 순간인데 그걸 알려주는 곳이 아무 데도 없었다.
--   [왜 새 UI 를 안 만드나] 이 배너가 이미 480×90 중앙 + Back 이징으로 충분히 눈에 띈다.
--     하나 더 띄우면 같은 순간에 두 개가 겹친다.
--   [짝] 이 배너가 '도입', CaptureHudClient 의 상단 라벨이 '지속'이다.
--     배너로 한 번 알리고, 그 뒤엔 라벨이 계속 상태를 말해준다.
--   ⚠️ RoundsPlayed 게이트를 안 건다. DiveSlotClient 의 Q대시 힌트는 신규 3판 한정인데,
--     킹은 희귀 역할이라(10명 중 1명) 3번 킹을 하려면 30판이 필요하다 —
--     그 게이트를 쓰면 이 힌트는 사실상 영원히 안 뜬다. 2단계 진입은 라운드당 1회뿐이고
--     대상도 한 명이라 매번 띄워도 잔소리가 되지 않는다.
--   ⚠️ Role 은 호출 시점에 읽는다. 캐싱하면 역할이 바뀐 다음 라운드에 틀린 문구가 나간다.
local KING_CRIMSON = Color3.fromRGB(178, 34, 62)   -- 진영색 규칙(킹 크림슨)

local function showNotice(reachedName)
    local isKing = localPlayer:GetAttribute("Role") == "Tagger"
    -- 킹은 읽을 게 더 많다(지시 2줄). 1초 더 준다.
    local HOLD = isKing and 4 or 3

    -- 기존 알림 정리 (중복 트리거 안전)
    local pgui = localPlayer:WaitForChild("PlayerGui")
    local existing = pgui:FindFirstChild("Stage2NoticeGui")
    if existing then existing:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "Stage2NoticeGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9
    gui.Parent = pgui

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.4, 0)
    frame.Size = UDim2.new(0, 480, 0, 90)
    -- 킹에게만 진영색(크림슨). "이건 너에 대한 얘기다" 를 색으로 먼저 말한다.
    frame.BackgroundColor3 = isKing and KING_CRIMSON or Color3.fromRGB(180, 40, 40)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 3
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 8)
    title.Size = UDim2.new(1, -20, 0, 36)
    title.BackgroundTransparency = 1
    -- ⚠️ 킹에게는 페이즈 이름보다 지시가 먼저다. 3초 안에 읽을 수 있는 건 한 줄뿐이고,
    --   그 한 줄은 "뭘 해야 하나" 여야 한다. 페이즈 전환은 음악·연출이 이미 알린다.
    title.Text = isKing and "DEFEND THE THRONE" or "DUEL PHASE!"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 28
    title.Font = Enum.Font.GothamBold
    title.TextStrokeTransparency = 0.3
    title.Parent = frame

    local sub = Instance.new("TextLabel")
    sub.AnchorPoint = Vector2.new(0.5, 1)
    sub.Position = UDim2.new(0.5, 0, 1, -8)
    sub.Size = UDim2.new(1, -20, 0, 32)
    sub.BackgroundTransparency = 1
    sub.Text = isKing
        and "Runners capture the zone to win — stand on it to stop them"
        or  string.format("%s reached the altar", reachedName or "A runner")
    sub.TextColor3 = Color3.fromRGB(255, 220, 220)
    sub.TextSize = 18
    sub.Font = Enum.Font.Gotham
    sub.TextStrokeTransparency = 0.5
    sub.Parent = frame

    -- 등장 애니메이션 (위에서 떨어지듯)
    frame.Position = UDim2.new(0.5, 0, 0.3, 0)
    frame.BackgroundTransparency = 1
    title.TextTransparency = 1
    sub.TextTransparency = 1
    stroke.Transparency = 1

    local enterInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    TweenService:Create(frame, enterInfo, {
        Position = UDim2.new(0.5, 0, 0.4, 0),
        BackgroundTransparency = 0.1,
    }):Play()
    TweenService:Create(title, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()
    TweenService:Create(sub, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()
    TweenService:Create(stroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Transparency = 0}):Play()

    -- 3초 후 페이드 아웃
    task.delay(HOLD, function()
        if not frame.Parent then return end
        local exitInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(frame, exitInfo, {
            Position = UDim2.new(0.5, 0, 0.5, 0),
            BackgroundTransparency = 1,
        }):Play()
        TweenService:Create(title, exitInfo, {TextTransparency = 1}):Play()
        TweenService:Create(sub, exitInfo, {TextTransparency = 1}):Play()
        TweenService:Create(stroke, exitInfo, {Transparency = 1}):Play()
        task.wait(0.6)
        if gui then gui:Destroy() end
    end)
end

Stage2Started.OnClientEvent:Connect(showNotice)

print("✅ Stage2NotifyClient 활성화")
