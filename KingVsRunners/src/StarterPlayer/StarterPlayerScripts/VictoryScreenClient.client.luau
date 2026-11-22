-- ═══════════════════════════════════════════════════════════════
-- 🏆 승패 감상 화면 (사전 생성 방식 2026-08-23)
--
-- [핵심 변경] 매번 만들지 않는다. 부팅 때 한 번 짓고 숨겨뒀다가 켠다.
--   이전에는 승부가 날 때마다 ScreenGui 부터 14개 인스턴스를 새로 생성했고,
--   그 순간 텍스처 GPU 업로드 + 폰트 글리프 생성 + 인스턴스 할당이 겹쳐
--   "약간 로딩되는" 지연이 생겼다.
--   → 상용 게임의 정석대로 pre-build + toggle 로 바꾼다. 표시 비용이 0 에 수렴한다.
--
-- [추가] 부팅 직후 화면 밖에서 한 번 렌더해 폰트·텍스처를 예열한다
--   (AssetPreloadClient 의 워밍업과 같은 논리 — 다운로드가 아니라 '첫 그리기'가 비싸다).
--
-- ⚠️ 글자 수가 상황마다 다르다(WIN 3 / DEFEAT 6 / CANCELLED 9).
--    최대치인 9개를 미리 만들고 필요한 만큼만 보이게 한다.
-- ⚠️ 입자도 풀링한다. 매번 Instance.new 하면 사전 생성의 이점이 반감된다.
-- ═══════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local player = Players.LocalPlayer

local SFX_WIN  = "rbxassetid://122312432289909"
local SFX_LOSE = "rbxassetid://134829851656557"
local GLOW_TEX = "rbxassetid://8451174579"

local HOLD = 3.5   -- ⚠️ 서버 RoundSystem 의 이동 전 대기(4.5)와 한 쌍. 양쪽 같이 조정.

local MAX_CHARS = 9      -- CANCELLED
local PARTICLE_POOL = 12

local PALETTE = {
    win = {
        bg = Color3.fromRGB(38, 26, 4),   ray = Color3.fromRGB(255, 195, 60),
        text = Color3.fromRGB(255, 232, 150), text2 = Color3.fromRGB(255, 170, 40),
        stroke = Color3.fromRGB(92, 48, 0), spark = Color3.fromRGB(255, 218, 120),
        sub = Color3.fromRGB(255, 205, 110),
    },
    lose = {
        bg = Color3.fromRGB(8, 11, 20),   ray = Color3.fromRGB(58, 76, 112),
        text = Color3.fromRGB(178, 192, 214), text2 = Color3.fromRGB(96, 112, 142),
        stroke = Color3.fromRGB(14, 20, 34), spark = Color3.fromRGB(110, 130, 165),
        sub = Color3.fromRGB(130, 148, 178),
    },
}

-- ── 사전 생성 ──────────────────────────────────────────────────
local UI = nil   -- { gui, dim, ray, glow, lines, holder, chars, sub, particles }

local function build()
    local pg = player:WaitForChild("PlayerGui")
    local prev = pg:FindFirstChild("VictoryScreen")
    if prev then prev:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "VictoryScreen"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 200
    gui.Enabled = false          -- ⚠️ 숨겨두는 핵심. Destroy 하지 않는다.
    gui.Parent = pg

    local dim = Instance.new("Frame")
    dim.Name = "Dim"
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.ZIndex = 1
    dim.Parent = gui

    local ray = Instance.new("ImageLabel")
    ray.Name = "Ray"
    ray.AnchorPoint = Vector2.new(0.5, 0.5)
    ray.Position = UDim2.fromScale(0.5, 0.5)
    ray.Size = UDim2.fromOffset(620, 240)
    ray.BackgroundTransparency = 1
    ray.Image = GLOW_TEX
    ray.ImageTransparency = 1
    ray.ZIndex = 2
    ray.Parent = gui

    local glow = Instance.new("ImageLabel")
    glow.Name = "Glow"
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    glow.Position = UDim2.fromScale(0.5, 0.5)
    glow.Size = UDim2.fromOffset(620, 260)
    glow.BackgroundTransparency = 1
    glow.Image = GLOW_TEX
    glow.ImageTransparency = 1
    glow.ZIndex = 3
    glow.Parent = gui

    local lines = {}
    for i = 1, 2 do
        local ln = Instance.new("Frame")
        ln.Name = "Line" .. i
        ln.AnchorPoint = Vector2.new(0.5, 0.5)
        ln.Position = UDim2.new(0.5, 0, 0.5, (i == 1) and -78 or 78)
        ln.Size = UDim2.fromOffset(0, 3)
        ln.BackgroundTransparency = 1
        ln.BorderSizePixel = 0
        ln.ZIndex = 4
        ln.Parent = gui
        lines[i] = ln
    end

    local holder = Instance.new("Frame")
    holder.Name = "Word"
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Position = UDim2.fromScale(0.5, 0.5)
    holder.Size = UDim2.fromOffset(700, 170)
    holder.BackgroundTransparency = 1
    holder.ZIndex = 5
    holder.Parent = gui

    local layout = Instance.new("UIListLayout")
    -- ⚠️ SortOrder 기본값은 Name. LayoutOrder 를 쓰려면 명시해야 한다.
    --    (Cell1, Cell10, Cell2... 처럼 두 자리부터 순서가 뒤섞인다)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = holder

    -- ⚠️ 최대 글자 수만큼 미리 만든다. 매번 만들면 폰트 글리프 생성이 다시 일어난다.
    local chars = {}
    for i = 1, MAX_CHARS do
        local lbl = Instance.new("TextLabel")
        lbl.Name = "C" .. i
        lbl.LayoutOrder = i
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextTransparency = 1
        lbl.TextStrokeTransparency = 1
        lbl.Visible = false
        lbl.ZIndex = 5
        lbl.Parent = holder

        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Parent = lbl

        chars[i] = lbl
    end

    local sub = Instance.new("TextLabel")
    sub.Name = "Sub"
    sub.AnchorPoint = Vector2.new(0.5, 0.5)
    sub.Position = UDim2.new(0.5, 0, 0.5, 108)
    sub.Size = UDim2.fromOffset(560, 30)
    sub.BackgroundTransparency = 1
    sub.Font = Enum.Font.GothamMedium
    sub.TextSize = 19
    sub.TextTransparency = 1
    sub.TextStrokeTransparency = 1
    sub.ZIndex = 5
    sub.Parent = gui

    -- 입자 풀
    local particles = {}
    for i = 1, PARTICLE_POOL do
        local p = Instance.new("Frame")
        p.Name = "P" .. i
        p.BorderSizePixel = 0
        p.BackgroundTransparency = 1
        p.Visible = false
        p.ZIndex = 6
        p.Parent = gui
        particles[i] = p
    end

    UI = {
        gui = gui, dim = dim, ray = ray, glow = glow, lines = lines,
        holder = holder, chars = chars, sub = sub, particles = particles,
    }
    return UI
end

-- ── 예열 ───────────────────────────────────────────────────────
-- ⚠️ 다운로드는 AssetPreloadClient 가 끝냈지만, '첫 그리기'는 아직이다.
--    화면 밖에서 한 프레임 그려 폰트 글리프와 텍스처 GPU 업로드를 미리 끝낸다.
local function prewarm()
    if not UI then return end
    local g = UI.gui
    g.Enabled = true
    -- 완전 투명 + 화면 밖으로 밀어 사용자에게 보이지 않게
    UI.dim.BackgroundTransparency = 1
    UI.ray.ImageTransparency = 0.99
    UI.glow.ImageTransparency = 0.99
    UI.holder.Position = UDim2.fromScale(0.5, -3)
    for i, lbl in ipairs(UI.chars) do
        lbl.Visible = true
        lbl.TextSize = 130
        lbl.Size = UDim2.fromOffset(86, 170)
        lbl.Text = ("WINDEFEAT"):sub(i, i)   -- 두 단어의 글자를 모두 포함
        lbl.TextTransparency = 0.99
    end
    UI.sub.Text = "prewarm"
    UI.sub.TextTransparency = 0.99

    task.delay(0.15, function()
        if not UI then return end
        g.Enabled = false
        for _, lbl in ipairs(UI.chars) do
            lbl.Visible = false
            lbl.TextTransparency = 1
        end
        UI.holder.Position = UDim2.fromScale(0.5, 0.5)
        UI.sub.TextTransparency = 1
        print("[VictoryScreen] 예열 완료")
    end)
end

-- ── 재생 ───────────────────────────────────────────────────────
local activeConn = nil

local function play(myRole, iWon, voided, endReason)
    if not UI or not UI.gui.Parent then build() end
    if not UI then return end

    local win = iWon and not voided
    local pal = win and PALETTE.win or PALETTE.lose
    local word = voided and "CANCELLED" or (win and "WIN" or "DEFEAT")
    local sizePx = (#word <= 3) and 130 or 96

    if activeConn then activeConn:Disconnect() ; activeConn = nil end

    local g, dim, ray, glow = UI.gui, UI.dim, UI.ray, UI.glow
    local holder, chars, sub = UI.holder, UI.chars, UI.sub

    -- ── 값만 갱신 (인스턴스 생성 없음) ──
    dim.BackgroundColor3 = pal.bg
    dim.BackgroundTransparency = 1
    ray.ImageColor3 = pal.ray
    ray.ImageTransparency = 1
    ray.Rotation = 0
    glow.ImageColor3 = pal.ray
    glow.ImageTransparency = 1
    glow.Size = UDim2.fromOffset(620, 260)

    for i, ln in ipairs(UI.lines) do
        ln.BackgroundColor3 = pal.ray
        ln.BackgroundTransparency = 1
        ln.Size = UDim2.fromOffset(0, 3)
    end

    holder.Position = UDim2.fromScale(0.5, 0.5)
    local gradSeq = ColorSequence.new({
        ColorSequenceKeypoint.new(0, pal.text),
        ColorSequenceKeypoint.new(1, pal.text2),
    })
    for i = 1, MAX_CHARS do
        local lbl = chars[i]
        if i <= #word then
            lbl.Visible = true
            lbl.Text = word:sub(i, i)
            lbl.TextSize = sizePx
            lbl.Size = UDim2.fromOffset(sizePx * 0.66, sizePx * 1.3)
            lbl.TextColor3 = pal.text
            lbl.TextStrokeColor3 = pal.stroke
            lbl.TextTransparency = 1
            lbl.TextStrokeTransparency = 1
            lbl.Position = UDim2.fromOffset(0, win and -40 or 22)
            lbl.Rotation = win and -10 or 3
            local gr = lbl:FindFirstChildOfClass("UIGradient")
            if gr then gr.Color = gradSeq end
        else
            lbl.Visible = false
        end
    end

    -- 부제
    if voided then
        sub.Text = "No winner this round"
    elseif myRole == "Tagger" then
        sub.Text = win and "You defended the throne" or "The throne has fallen"
    elseif win then
        sub.Text = (endReason == "capture") and "The throne is yours"
            or ((endReason == "tagger_slain" or endReason == "bot_slain")
                and "You brought down the King" or "You outlasted the King")
    else
        sub.Text = "The King stood his ground"
    end
    sub.TextColor3 = pal.sub
    sub.TextStrokeColor3 = pal.stroke
    sub.TextTransparency = 1
    sub.TextStrokeTransparency = 1

    -- ── 표시 ──
    g.Enabled = true

    TweenService:Create(dim, TweenInfo.new(0.14), {BackgroundTransparency = 0.25}):Play()
    TweenService:Create(ray, TweenInfo.new(0.35),
        {ImageTransparency = win and 0.52 or 0.62}):Play()
    TweenService:Create(glow, TweenInfo.new(0.25),
        {ImageTransparency = win and 0.42 or 0.5}):Play()
    for _, ln in ipairs(UI.lines) do
        TweenService:Create(ln, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(win and 520 or 420, 3),
            BackgroundTransparency = win and 0.15 or 0.5,
        }):Play()
    end

    task.spawn(function()
        for i = 1, #word do
            local lbl = chars[i]
            if not lbl or not lbl.Parent then return end
            TweenService:Create(lbl,
                TweenInfo.new(win and 0.20 or 0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { TextTransparency = 0, TextStrokeTransparency = 0.1,
                  Position = UDim2.fromOffset(0, 0), Rotation = 0 }):Play()
            task.wait(win and 0.03 or 0.035)
        end
    end)

    task.delay(#word * 0.03 + 0.1, function()
        if g.Enabled then
            TweenService:Create(sub, TweenInfo.new(0.35),
                {TextTransparency = 0, TextStrokeTransparency = 0.5}):Play()
        end
    end)

    -- 입자 (풀 재사용)
    -- ⚠️ 승리는 아래→위, 패배는 위→아래. 방향으로 성격을 가른다.
    task.spawn(function()
        local count = win and 12 or 9
        for i = 1, count do
            if not g.Enabled then return end
            local p = UI.particles[i]
            if p then
                local sz = win and math.random(5, 11) or math.random(4, 8)
                p.Size = UDim2.fromOffset(sz, sz)
                p.Position = UDim2.new(math.random(18, 82) / 100, 0, win and 0.68 or 0.30, 0)
                p.BackgroundColor3 = pal.spark
                p.BackgroundTransparency = win and 0.2 or 0.45
                p.Rotation = math.random(0, 45)
                p.Visible = true

                local dur = win and (math.random(110, 180) / 100) or (math.random(160, 240) / 100)
                TweenService:Create(p,
                    TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Position = UDim2.new(p.Position.X.Scale, math.random(-40, 40), win and 0.14 or 0.82, 0),
                    BackgroundTransparency = 1,
                    Rotation = p.Rotation + math.random(-140, 140),
                }):Play()
            end
            task.wait(win and 0.25 or 0.32)
        end
    end)

    -- 상시 움직임
    local t0 = os.clock()
    local acc, lastPulse = 0, -1
    activeConn = RunService.Heartbeat:Connect(function(dt)
        if not g.Enabled then
            if activeConn then activeConn:Disconnect() ; activeConn = nil end
            return
        end
        acc = acc + dt
        if acc < 0.033 then return end
        local step = acc ; acc = 0
        local el = os.clock() - t0

        ray.Rotation = ray.Rotation + step * (win and 8 or -5)

        local pulse = 1 + math.sin(el * (win and 3.2 or 2.2)) * (win and 0.055 or 0.045)
        if math.abs(pulse - lastPulse) > 0.004 then
            lastPulse = pulse
            glow.Size = UDim2.fromOffset(620 * pulse, 260 * pulse)
        end

        local bob = win and (math.sin(el * 2.0) * 3)
                        or (math.sin(el * 1.3) * 2.5 + math.min(el * 1.6, 6))
        holder.Position = UDim2.new(0.5, 0, 0.5, bob)
    end)

    -- 소리
    if not voided then
        local snd = Instance.new("Sound")
        snd.SoundId = win and SFX_WIN or SFX_LOSE
        snd.Volume = win and 1.4 or 0.9
        snd.Parent = SoundService
        snd:Play()
        game:GetService("Debris"):AddItem(snd, 5)
    end

    -- 퇴장 (Destroy 하지 않고 숨기기만)
    task.delay(HOLD - 0.35, function()
        if not g.Enabled then return end
        local o = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(dim,  o, {BackgroundTransparency = 1}):Play()
        TweenService:Create(ray,  o, {ImageTransparency = 1}):Play()
        TweenService:Create(glow, o, {ImageTransparency = 1}):Play()
        TweenService:Create(sub,  o, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
        for _, ln in ipairs(UI.lines) do
            TweenService:Create(ln, o, {BackgroundTransparency = 1}):Play()
        end
        for i = 1, #word do
            local lbl = chars[i]
            if lbl then
                TweenService:Create(lbl, o, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
            end
        end
    end)

    task.delay(HOLD + 0.1, function()
        g.Enabled = false
        for _, p in ipairs(UI.particles) do p.Visible = false end
        if activeConn then activeConn:Disconnect() ; activeConn = nil end
    end)
end

-- ── 부팅 ───────────────────────────────────────────────────────
build()
task.delay(2, prewarm)   -- 로딩 화면이 걷힌 뒤 조용히 예열

-- 캐릭터가 리스폰돼도 UI 는 유지된다(ResetOnSpawn=false).
-- ⚠️ 다만 PlayerGui 가 통째로 갈리는 상황을 대비해 존재를 확인한다.
player.CharacterAdded:Connect(function()
    task.wait(1)
    if not UI or not UI.gui or not UI.gui.Parent then build() end
end)

local vsEvent = ReplicatedStorage:WaitForChild("VictoryScreenEvent")

vsEvent.OnClientEvent:Connect(function(winner, stats, voided, endReason)
    -- ⚠️ Role 속성은 서버가 이 직후 지운다. stats 에서 읽어야 한다.
    local myRole
    for _, s in ipairs(stats or {}) do
        if s.userId == player.UserId then myRole = s.role break end
    end
    if myRole == nil then return end

    local iWon = (not voided) and (
        (winner == "Tagger" and myRole == "Tagger") or
        (winner == "Runner" and myRole == "Runner")
    )
    play(myRole, iWon, voided, endReason)
end)
