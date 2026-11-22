-- 🎯 곡사포 상태 표시 (전원에게 보임)
--
-- ⚠️ RemoteEvent 로 태거에게만 보내면 러너는 대포 상태를 모른다.
--    서버가 대포에 속성(CannonReadyAt / CannonCharging)을 남기고,
--    클라는 그걸 읽어 그린다 — HP 바와 같은 방식이다.
-- [왜 공개하나] 러너가 "지금 대포가 식었다"를 읽고 붙는 전술이 생긴다.
--    이 게임은 태거 HP 도 공개하므로 정보를 여는 방향이 일관된다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
-- ⚠️ RoundPhase 를 읽어 2단계 여부를 판단한다. 선언 없이 쓰면 런타임에 터진다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BAR_W, BAR_H = 110, 16
local ICON_W = 20

local gauges = {}   -- [cannonModel] = { gui, fill, label }

local function buildGauge(cannon)
    local barrel = cannon.PrimaryPart or cannon:FindFirstChild("Barrel")
    if not barrel then return nil end

    local prev = barrel:FindFirstChild("CannonGauge")
    if prev then prev:Destroy() end

    local gui = Instance.new("BillboardGui")
    gui.Name = "CannonGauge"
    gui.Size = UDim2.new(0, BAR_W + ICON_W, 0, BAR_H)
    gui.StudsOffset = Vector3.new(0, 6.5, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 200
    gui.Parent = barrel

    -- 🎯 아이콘. 내구도 게이지가 HP 바와 헷갈렸던 전례가 있어,
    --    형태로 "이건 대포다"를 먼저 알린다.
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, ICON_W, 1, 0)
    icon.BackgroundTransparency = 1
    icon.Font = Enum.Font.GothamBold
    icon.TextScaled = true
    -- ⚠️ 형태로 구분한다. 대포와 마법책이 같은 아이콘이면 맵이 바뀐 걸 못 느낀다.
    icon.Text = (cannon.Name == "MagicBook") and "📖" or "🎯"
    icon.TextStrokeTransparency = 0.4
    icon.Parent = gui

    local back = Instance.new("Frame")
    back.Name = "Back"
    back.Size = UDim2.new(1, -ICON_W, 1, 0)
    back.Position = UDim2.new(0, ICON_W, 0, 0)
    back.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
    back.BackgroundTransparency = 0.2
    back.BorderSizePixel = 0
    back.Parent = gui
    Instance.new("UICorner", back).CornerRadius = UDim.new(0.4, 0)

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 190, 60)
    fill.BorderSizePixel = 0
    fill.Parent = back
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0.4, 0)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.3
    label.Text = "READY"
    label.ZIndex = 2
    label.Parent = back

    return { gui = gui, fill = fill, label = label, back = back }
end

local function findCannons()
    local list = {}
    for _, mapFolder in ipairs(workspace:GetChildren()) do
        if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
            for _, d in ipairs(mapFolder:GetChildren()) do
                -- ⚠️ map1 은 Cannon, map2 는 MagicBook. 둘 다 같은 게이지를 쓴다.
                if d:IsA("Model") and (d.Name == "Cannon" or d.Name == "MagicBook") then
                    list[#list + 1] = d
                end
            end
        end
    end
    return list
end

-- ⚠️ 매 프레임 대포를 탐색하지 않는다. 주기적으로만 갱신한다.
local lastScan = 0
local cachedCannons = {}

RunService.Heartbeat:Connect(function()
    local now = os.clock()

    -- ⚠️ 곡사포는 2단계 전용이다. 그 전에는 서버가 대포를 숨기므로
    --    게이지도 뜨지 않아야 한다. RoundPhase 로 판단한다.
    -- ⚠️ 여기서 만들지 않으면 서버가 켜준 g.Enabled 를 덮어쓰지 않는다.
    local inStage2 = ReplicatedStorage:GetAttribute("RoundPhase") == "stage2"
    if not inStage2 then
        for _, g in pairs(gauges) do
            if g and g.gui and g.gui.Parent then g.gui.Enabled = false end
        end
        return
    end

    if now - lastScan > 2 then
        lastScan = now
        cachedCannons = findCannons()
        for _, c in ipairs(cachedCannons) do
            if not gauges[c] or not gauges[c].gui.Parent then
                gauges[c] = buildGauge(c)
            end
            if gauges[c] and gauges[c].gui then gauges[c].gui.Enabled = true end
        end
    end

    for _, c in ipairs(cachedCannons) do
        local g = gauges[c]
        if g and g.gui.Parent then
            local readyAt = c:GetAttribute("CannonReadyAt")
            local charging = c:GetAttribute("CannonCharging")

            if readyAt then
                local left = readyAt - os.time()
                if left > 0 then
                    -- 재장전 중: 게이지가 차오른다
                    local total = 6.0
                    local p = math.clamp(1 - (left / total), 0, 1)
                    g.fill.Size = UDim2.new(p, 0, 1, 0)
                    g.fill.BackgroundColor3 = Color3.fromRGB(150, 90, 60)
                    g.label.Text = string.format("%.0fs", left)
                else
                    g.fill.Size = UDim2.new(1, 0, 1, 0)
                    g.fill.BackgroundColor3 = Color3.fromRGB(255, 190, 60)
                    g.label.Text = "READY"
                end
            elseif charging then
                -- 장전 중: 맥동
                g.fill.Size = UDim2.new(1, 0, 1, 0)
                g.fill.BackgroundColor3 = Color3.fromRGB(255, 120, 50)
                g.label.Text = "AIMING"
                g.back.BackgroundTransparency = 0.2 + math.sin(now * 8) * 0.12
            else
                g.fill.Size = UDim2.new(1, 0, 1, 0)
                g.fill.BackgroundColor3 = Color3.fromRGB(255, 190, 60)
                g.label.Text = "READY"
                g.back.BackgroundTransparency = 0.2
            end
        end
    end
end)
