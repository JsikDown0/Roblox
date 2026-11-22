local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local gui = script.Parent
local container = gui:WaitForChild("KillLogContainer")
local killLogEvent = ReplicatedStorage:WaitForChild("KillLogEvent")

-- 모바일 노치/펀치홀 자동 회피
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- ── 모바일 대응 UIScale ────────────────────────────────────────
local camera = workspace.CurrentCamera
local uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", gui)
local BASE_W, BASE_H = 1280, 720
local function updateUIScale()
	local vp = camera.ViewportSize
	local s = math.min((vp.X * 0.85) / BASE_W, (vp.Y * 0.85) / BASE_H, 1)
	uiScale.Scale = math.max(s, 0.55)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
updateUIScale()

local logCount = 0
local MAX_LOGS = 4

local function createKillLog(victimName, coinAmount)
    logCount = logCount + 1

    -- 최대 개수 초과 시 오래된 것 제거
    local cards = {}
    for _, c in ipairs(container:GetChildren()) do
        if c:IsA("Frame") then table.insert(cards, c) end
    end
    if #cards >= MAX_LOGS then
        table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
        cards[1]:Destroy()
    end

    local card = Instance.new("Frame")
    card.Name = "KillLog_" .. logCount
    card.Size = UDim2.new(1, 0, 0, 72)
    card.BackgroundColor3 = Color3.fromRGB(15, 8, 3)
    card.BackgroundTransparency = 1
    card.BorderSizePixel = 0
    card.LayoutOrder = logCount
    card.ClipsDescendants = true
    card.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 100, 20)
    stroke.Thickness = 2
    stroke.Transparency = 1
    stroke.Parent = card

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 35, 5)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(22, 10, 3)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 5, 2))
    })
    grad.Parent = card

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 6, 1, 0)
    accent.BackgroundColor3 = Color3.fromRGB(255, 80, 0)
    accent.BorderSizePixel = 0
    accent.BackgroundTransparency = 1
    accent.Parent = card
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 6)

    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 64, 1, 0)
    icon.Position = UDim2.new(0, 12, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = "\xF0\x9F\x94\xA5"  -- 🔥
    icon.TextColor3 = Color3.fromRGB(255, 120, 0)
    icon.TextSize = 36
    icon.TextScaled = false
    icon.TextTransparency = 1
    icon.Parent = card

    local killText = Instance.new("TextLabel")
    killText.Size = UDim2.new(1, -200, 0, 28)
    killText.Position = UDim2.new(0, 80, 0, 4)
    killText.BackgroundTransparency = 1
    killText.Text = victimName .. " eliminated!"
    killText.TextColor3 = Color3.fromRGB(255, 255, 255)
    killText.TextSize = 16
    killText.Font = Enum.Font.GothamBold
    killText.TextXAlignment = Enum.TextXAlignment.Left
    killText.TextTransparency = 1
    killText.Parent = card

    local coinText = Instance.new("TextLabel")
    coinText.Size = UDim2.new(1, -200, 0, 22)
    coinText.Position = UDim2.new(0, 80, 0, 30)
    coinText.BackgroundTransparency = 1
    coinText.Text = "+" .. coinAmount .. " Coins"
    coinText.TextColor3 = Color3.fromRGB(255, 210, 60)
    coinText.TextSize = 14
    coinText.Font = Enum.Font.Gotham
    coinText.TextXAlignment = Enum.TextXAlignment.Left
    coinText.TextTransparency = 1
    coinText.Parent = card

    local badge = Instance.new("Frame")
    badge.Size = UDim2.new(0, 105, 0, 48)
    badge.Position = UDim2.new(1, -117, 0.5, -24)
    badge.BackgroundColor3 = Color3.fromRGB(210, 90, 0)
    badge.BorderSizePixel = 0
    badge.BackgroundTransparency = 1
    badge.Parent = card
    Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 8)

    local badgeGrad = Instance.new("UIGradient")
    badgeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 145, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 55, 0))
    })
    badgeGrad.Rotation = 90
    badgeGrad.Parent = badge

    local badgeText = Instance.new("TextLabel")
    badgeText.Size = UDim2.new(1, 0, 1, 0)
    badgeText.BackgroundTransparency = 1
    badgeText.Text = "+" .. coinAmount .. " COIN"
    badgeText.TextColor3 = Color3.fromRGB(255, 255, 220)
    badgeText.TextSize = 18
    badgeText.Font = Enum.Font.GothamBold
    badgeText.TextTransparency = 1
    badgeText.Parent = badge

    -- 페이드 인
    task.wait(0.03)
    local tweenIn = TweenInfo.new(0.3, Enum.EasingStyle.Quad)
    TweenService:Create(card,      tweenIn, {BackgroundTransparency = 0.1}):Play()
    TweenService:Create(stroke,    tweenIn, {Transparency = 0}):Play()
    TweenService:Create(accent,    tweenIn, {BackgroundTransparency = 0}):Play()
    TweenService:Create(icon,      tweenIn, {TextTransparency = 0}):Play()
    TweenService:Create(killText,  tweenIn, {TextTransparency = 0}):Play()
    TweenService:Create(coinText,  tweenIn, {TextTransparency = 0}):Play()
    TweenService:Create(badge,     tweenIn, {BackgroundTransparency = 0}):Play()
    TweenService:Create(badgeText, tweenIn, {TextTransparency = 0}):Play()

    -- 3.5초 후 페이드 아웃
    task.delay(3.5, function()
        if not card.Parent then return end
        local tweenOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
        TweenService:Create(card,      tweenOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(stroke,    tweenOut, {Transparency = 1}):Play()
        TweenService:Create(accent,    tweenOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(icon,      tweenOut, {TextTransparency = 1}):Play()
        TweenService:Create(killText,  tweenOut, {TextTransparency = 1}):Play()
        TweenService:Create(coinText,  tweenOut, {TextTransparency = 1}):Play()
        TweenService:Create(badge,     tweenOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(badgeText, tweenOut, {TextTransparency = 1}):Play()
        task.delay(0.5, function()
            if card.Parent then card:Destroy() end
        end)
    end)
end

killLogEvent.OnClientEvent:Connect(function(victimName, coinAmount)
    createKillLog(victimName, coinAmount)
end)

print("KillLogClient v2 준비!")
