-- 맵 투표 클라이언트
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = script.Parent
local voteFrame = gui:WaitForChild("VoteFrame")
local mapContainer = voteFrame:WaitForChild("MapContainer")

-- 모바일 노치/펀치홀 자동 회피
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- ── 반응형 스케일 (디바이스별, 공통 모듈) ────────────────────
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))
Scaler.applyPanel(voteFrame, {
    baseW = 900, baseH = 280,
    Mobile = { frac = 0.7, minScale = 0.45 },  -- 현재 값 (동결)
    PC     = { frac = 0.7, minScale = 0.45 },  -- ← PC용. 자유 조정
})

-- 모바일: 패널 아래로 (X 닫기 버튼이 우상단 Settings에 가리지 않게)
local FINAL_Y = Scaler.isMobile() and 0.55 or 0.42

-- RemoteEvent
local voteEvent   = ReplicatedStorage:WaitForChild("MapVoteEvent")
local updateEvent = ReplicatedStorage:WaitForChild("MapVoteUpdate")
local startEvent  = ReplicatedStorage:WaitForChild("MapVoteStart")
local resultEvent = ReplicatedStorage:WaitForChild("MapVoteResult")

local mapButtons = {}
local currentVote = nil
local isVoting = false

-- 맵 정보
local maps = {
    {name = "map1", displayName = "MAP 1", color = Color3.fromRGB(100, 200, 255)},
    {name = "map2", displayName = "MAP 2", color = Color3.fromRGB(255, 100, 200)}
}

-- ── 닫기 버튼 생성 ────────────────────────────────────────────
local closeBtn = voteFrame:FindFirstChild("_CloseBtn")
if not closeBtn then
    closeBtn = Instance.new("TextButton")
    closeBtn.Name = "_CloseBtn"
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
    closeBtn.Parent = voteFrame
end
closeBtn.Size = UDim2.new(0, 48, 0, 48)
closeBtn.Position = UDim2.new(1, 20, 0, -24)  -- 오른쪽으로 살짝 이동
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 20
closeBtn.Font = Enum.Font.GothamBold
closeBtn.ZIndex = 10

closeBtn.MouseButton1Click:Connect(function()
    isVoting = false
    voteFrame.Visible = false
end)

-- GameUI TimerLabel 가져오기
local function getTimerLabel()
    local gameUI = playerGui:WaitForChild("GameUI", 10)
    if gameUI then
        local timerFrame = gameUI:WaitForChild("TimerFrame", 5)
        if timerFrame then
            return timerFrame:WaitForChild("TimerLabel", 5)
        end
    end
    return nil
end

-- ── 투표 UI 초기화 (라운드마다 깨끗하게) ──────────────────────
local function resetVoteUI()
    currentVote = nil
    for _, btn in pairs(mapButtons) do
        -- 투표 수 초기화
        local vc = btn:FindFirstChild("VoteCount")
        if vc then vc.Text = "0 Votes" end
        -- 아이콘 초기화
        local ic = btn:FindFirstChild("IconContainer")
        if ic then
            ic:ClearAllChildren()
            local grid = Instance.new("UIGridLayout")
            grid.CellSize = UDim2.new(0, 50, 0, 50)
            grid.CellPadding = UDim2.new(0, 5, 0, 5)
            grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
            grid.VerticalAlignment = Enum.VerticalAlignment.Top
            grid.Parent = ic
        end
        -- 선택 테두리 초기화
        local stroke = btn:FindFirstChild("UIStroke")
        if stroke then stroke.Thickness = 0 end
        -- 버튼 활성화
        btn.Active = true
    end
end

-- 맵 버튼 생성
local function createMapButton(mapData)
    local button = Instance.new("TextButton")
    button.Name = mapData.name
    button.Size = UDim2.new(0, 280, 1, 0)
    button.BackgroundColor3 = mapData.color
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = false
    button.Parent = mapContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 0
    stroke.Transparency = 0.5
    stroke.Parent = button

    -- 맵 이름
    local mapName = Instance.new("TextLabel")
    mapName.Size = UDim2.new(1, 0, 0, 50)
    mapName.Position = UDim2.new(0, 0, 0, 10)
    mapName.BackgroundTransparency = 1
    mapName.TextColor3 = Color3.fromRGB(255, 255, 255)
    mapName.TextSize = 24
    mapName.Font = Enum.Font.GothamBold
    mapName.Text = mapData.displayName
    mapName.TextStrokeTransparency = 0.5
    mapName.Parent = button

    -- 투표 수
    local voteCount = Instance.new("TextLabel")
    voteCount.Name = "VoteCount"
    voteCount.Size = UDim2.new(1, 0, 0, 60)
    voteCount.Position = UDim2.new(0, 0, 1, -70)
    voteCount.BackgroundTransparency = 1
    voteCount.TextColor3 = Color3.fromRGB(255, 255, 255)
    voteCount.TextSize = 36
    voteCount.Font = Enum.Font.GothamBold
    voteCount.Text = "0 Votes"
    voteCount.TextStrokeTransparency = 0.5
    voteCount.Parent = button

    -- 프로필 아이콘 컨테이너
    local iconContainer = Instance.new("Frame")
    iconContainer.Name = "IconContainer"
    iconContainer.Size = UDim2.new(1, -20, 1, -130)
    iconContainer.Position = UDim2.new(0, 10, 0, 65)
    iconContainer.BackgroundTransparency = 1
    iconContainer.Parent = button

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, 50, 0, 50)
    gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    gridLayout.Parent = iconContainer

    -- 클릭 이벤트
    button.MouseButton1Click:Connect(function()
        if not isVoting then return end
        voteEvent:FireServer(mapData.name)
        currentVote = mapData.name
        for _, btn in pairs(mapButtons) do
            btn:FindFirstChild("UIStroke").Thickness = 0
        end
        stroke.Thickness = 5
    end)

    mapButtons[mapData.name] = button
    return button
end

-- 모든 맵 버튼 생성
for _, mapData in ipairs(maps) do
    createMapButton(mapData)
end

-- 투표 업데이트
updateEvent.OnClientEvent:Connect(function(votes, weighted)
    for mapName, voters in pairs(votes) do
        local button = mapButtons[mapName]
        if button then
            local voteCount = button:FindFirstChild("VoteCount")
            voteCount.Text = ((weighted and weighted[mapName]) or #voters) .. " Votes"

            local iconContainer = button:FindFirstChild("IconContainer")
            iconContainer:ClearAllChildren()

            local gridLayout = Instance.new("UIGridLayout")
            gridLayout.CellSize = UDim2.new(0, 50, 0, 50)
            gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
            gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
            gridLayout.Parent = iconContainer

            for _, userId in ipairs(voters) do
                local icon = Instance.new("ImageLabel")
                icon.Size = UDim2.new(1, 0, 1, 0)
                icon.BackgroundTransparency = 1
                icon.BorderSizePixel = 0
                icon.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. userId .. "&width=150&height=150&format=png"
                Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)
                -- VIP 투표자면 금색 링 (2표 행사 표시)
                local voter = Players:GetPlayerByUserId(userId)
                if voter and voter:GetAttribute("IsVIP") then
                    local ring = Instance.new("UIStroke")
                    ring.Color = Color3.fromRGB(255, 215, 0)
                    ring.Thickness = 3
                    ring.Parent = icon
                end
                icon.Parent = iconContainer
            end
        end
    end
end)

local waitingForResult = false

-- 투표 시작
startEvent.OnClientEvent:Connect(function(duration)
    -- ✅ 매 라운드 시작 시 이전 투표 기록 초기화
    resetVoteUI()

    isVoting = true
    waitingForResult = true
    voteFrame.Visible = true
    voteFrame.BackgroundTransparency = 0.2

    for _, child in ipairs(voteFrame:GetDescendants()) do
        if child:IsA("GuiObject") then child.Visible = true end
        if child:IsA("Frame") and child.Name ~= "MapContainer" and child.Name ~= "IconContainer" then
            child.BackgroundTransparency = 0
        elseif child:IsA("TextButton") then
            child.BackgroundTransparency = 0
        end
    end

    voteFrame.Position = UDim2.new(0.5, 0, 0, -300)
    TweenService:Create(voteFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
        Position = UDim2.new(0.5, 0, FINAL_Y, 0)
    }):Play()

    local timerLabel = getTimerLabel()
    local endTime = tick() + duration

    while tick() < endTime and isVoting do
        local remaining = math.ceil(endTime - tick())
        if timerLabel then
            timerLabel.Text = "🗳️ Vote: " .. remaining .. "s"
            timerLabel.TextColor3 = remaining <= 5
                and Color3.fromRGB(255, 80, 80)
                or  Color3.fromRGB(255, 255, 255)
        end
        task.wait(0.1)
    end

    isVoting = false
    for _, btn in pairs(mapButtons) do btn.Active = false end

    if waitingForResult and timerLabel then
        timerLabel.Text = "🗳️ Counting..."
        timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    end
end)

-- 결과 발표
resultEvent.OnClientEvent:Connect(function(winner)
    waitingForResult = false
    local timerLabel = getTimerLabel()

    local displayName = winner
    for _, mapData in ipairs(maps) do
        if mapData.name == winner then
            displayName = mapData.displayName
            break
        end
    end

    if timerLabel then
        timerLabel.Text = "🗺️ Selected: " .. displayName
        timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    end

    task.wait(3.5)

    voteFrame.Visible = false
    voteFrame.Position = UDim2.new(0.5, 0, 0, -1000)

    -- TimerLabel 복원: 색 + 텍스트("Selected: ..." 잔존 방지 — 라운드 타이머가 덮기 전 과도기 문구)
    if timerLabel then
        timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        timerLabel.Text = "⚔️ Get Ready..."
    end

    -- 결과 후 초기화
    resetVoteUI()
end)

print("✅ MapVoteClient 준비! (닫기 버튼 + 라운드별 초기화)")
