-- ════════════════════════════════════════════════════════════════
-- DailyRewardClient  (StarterGui/NewGui/Rewards / LocalScript)
-- ────────────────────────────────────────────────────────────────
-- 일일 출석 보상 UI 바인딩.
--  · 창(Canvas.Main) 열릴 때 DailyRewardData로 스냅샷 요청
--  · Day1~6 = 3x2 그리드 (왼쪽), Day7 = 큰 박스 (오른쪽)
--  · 각 박스: 보상 아이콘 + 수량 + 상태(claimable/claimed/locked)
--  · claimable 박스 클릭 → DailyRewardClaim 발신
--  · DailyRewardUpdate 구독 → 실시간 갱신
-- ════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfettiEffect    = require(ReplicatedStorage:WaitForChild("ConfettiEffect"))

local player = Players.LocalPlayer

local screenGui = script.Parent
local main      = screenGui:WaitForChild("Canvas"):WaitForChild("Main")
local list      = main:WaitForChild("List")
local dayTemplate = list:WaitForChild("DayTemplate")
local resetTimer = main:WaitForChild("ResetTimer")

local dataEvent   = ReplicatedStorage:WaitForChild("DailyRewardData")    -- RemoteFunction
local updateEvent = ReplicatedStorage:WaitForChild("DailyRewardUpdate")  -- RemoteEvent
local claimEvent  = ReplicatedStorage:WaitForChild("DailyRewardClaim")   -- RemoteEvent

local currentSnapshot = nil

-- ── 색상 ─────────────────────────────────────────────────────────
local COLOR_CLAIMABLE = Color3.fromRGB(95, 190, 70)   -- 받을 수 있음(초록)
local COLOR_LOCKED    = Color3.fromRGB(30, 30, 36)     -- 잠김(어두움)
local COLOR_CLAIMED   = Color3.fromRGB(30, 30, 36)     -- 받음(어두움 + Dim)

-- 레이아웃 상수는 buildBoxes() 내부에서 직접 계산함

-- 생성된 박스 보관
local dayBoxes = {}  -- [dayNumber] = frame

-- ── 박스 하나의 내용 갱신 ────────────────────────────────────────
local function applyDayData(box, dayData)
    local inner = box:FindFirstChild("Main")
    if not inner then return end

    local dayLabel = inner:FindFirstChild("DayLabel")
    local icon     = inner:FindFirstChild("RewardIcon")
    local amount   = inner:FindFirstChild("AmountLabel")
    local check    = inner:FindFirstChild("Check")
    local dim      = inner:FindFirstChild("ClaimedDim")

    if dayLabel then dayLabel.Text = "Day " .. dayData.day end
    if icon then icon.Image = dayData.icon or "" end
    if amount then amount.Text = dayData.amount or "" end

    -- 상태별 표시
    if dayData.state == "claimed" then
        inner.BackgroundColor3 = COLOR_CLAIMED
        if dim then dim.Visible = true end
        if check then check.Visible = true end
    elseif dayData.state == "claimable" then
        inner.BackgroundColor3 = COLOR_CLAIMABLE
        if dim then dim.Visible = false end
        if check then check.Visible = false end
    else -- locked
        inner.BackgroundColor3 = COLOR_LOCKED
        if dim then dim.Visible = false end
        if check then check.Visible = false end
    end
end

-- ── 박스 클릭 핸들러 (claimable일 때만 수령) ─────────────────────
local function hookClaim(box, dayNumber)
    -- 박스(Frame)를 클릭 감지하려면 자식 버튼이 필요 → inner에 투명 TextButton 오버레이
    local inner = box:FindFirstChild("Main")
    if not inner then return end
    local hit = inner:FindFirstChild("_ClickHit")
    if not hit then
        hit = Instance.new("TextButton")
        hit.Name = "_ClickHit"
        hit.Size = UDim2.fromScale(1, 1)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.ZIndex = 10
        hit.Parent = inner
    end
    hit.MouseButton1Click:Connect(function()
        if not currentSnapshot then return end
        -- 이 박스가 현재 claimable인 Day일 때만
        if currentSnapshot.canClaim and currentSnapshot.currentDay == dayNumber then
            claimEvent:FireServer()
            ConfettiEffect.play()   -- 보상 수령 축하 컨페티
        end
    end)
end

-- ── 박스 배치 생성 (최초 1회) ────────────────────────────────────
-- 레이아웃:
--   첫째 줄(위): Day 1~5 작은 박스 5개 가로
--   둘째 줄(아래): Day 6 작은 박스 1개(왼쪽) + Day 7 큰 가로 박스(나머지)
local function buildBoxes()
    if next(dayBoxes) ~= nil then return end

    local ROW_PAD   = 0.04   -- 두 줄 사이 세로 여백
    local COL_PAD   = 0.02   -- 칸 사이 가로 여백
    local rowH = (1 - ROW_PAD) / 2  -- 한 줄 높이

    -- ── 첫째 줄: Day 1~5 (가로 5등분) ──
    local topCols = 5
    local topCellW = (1 - COL_PAD * (topCols - 1)) / topCols
    for day = 1, 5 do
        local col = day - 1
        local box = dayTemplate:Clone()
        box.Name = "DayBox_" .. day
        box.Visible = true
        box.AnchorPoint = Vector2.new(0, 0)
        box.Size = UDim2.fromScale(topCellW, rowH)
        box.Position = UDim2.fromScale(col * (topCellW + COL_PAD), 0)
        box.Parent = list
        dayBoxes[day] = box
        hookClaim(box, day)
    end

    -- ── 둘째 줄: Day 6 작은 박스 + Day 7 큰 박스 ──
    local bottomY = rowH + ROW_PAD
    -- Day 6: 첫째 줄 칸과 같은 너비
    local box6 = dayTemplate:Clone()
    box6.Name = "DayBox_6"
    box6.Visible = true
    box6.AnchorPoint = Vector2.new(0, 0)
    box6.Size = UDim2.fromScale(topCellW, rowH)
    box6.Position = UDim2.fromScale(0, bottomY)
    box6.Parent = list
    dayBoxes[6] = box6
    hookClaim(box6, 6)

    -- Day 7: Day6 오른쪽부터 끝까지 가로로 크게
    local day7X = topCellW + COL_PAD
    local day7W = 1 - day7X
    local box7 = dayTemplate:Clone()
    box7.Name = "DayBox_7"
    box7.Visible = true
    box7.AnchorPoint = Vector2.new(0, 0)
    box7.Size = UDim2.fromScale(day7W, rowH)
    box7.Position = UDim2.fromScale(day7X, bottomY)
    box7.Parent = list
    dayBoxes[7] = box7
    hookClaim(box7, 7)

    -- Day7 강조: 파란 테두리 + glow (원본 파란 Claim 상자 느낌)
    local inner7 = box7:FindFirstChild("Main")
    if inner7 then
        local icon = inner7:FindFirstChild("RewardIcon")
        if icon then
            -- 가로로 넓으니 아이콘을 왼쪽에, 수량/라벨을 오른쪽에 둘 수도 있지만
            -- 우선 중앙 큰 아이콘 유지
            icon.Size = UDim2.fromScale(0.32, 0.7)
            icon.Position = UDim2.fromScale(0.28, 0.5)
        end
        local amount = inner7:FindFirstChild("AmountLabel")
        if amount then
            amount.Position = UDim2.fromScale(0.62, 0.5)
            amount.Size = UDim2.fromScale(0.45, 0.3)
            amount.AnchorPoint = Vector2.new(0.5, 0.5)
        end
        local dayLabel = inner7:FindFirstChild("DayLabel")
        if dayLabel then
            dayLabel.Position = UDim2.fromScale(0.5, 0.12)
        end
        -- 파란 테두리
        if not inner7:FindFirstChild("_Day7Stroke") then
            local st = Instance.new("UIStroke")
            st.Name = "_Day7Stroke"
            st.Color = Color3.fromRGB(60, 170, 255)
            st.Thickness = 3
            st.Parent = inner7
        end
    end
end

-- ── 전체 렌더 ────────────────────────────────────────────────────
local function render()
    if not currentSnapshot then return end
    buildBoxes()
    for _, dayData in ipairs(currentSnapshot.days) do
        local box = dayBoxes[dayData.day]
        if box then applyDayData(box, dayData) end
    end
end

-- ── 데이터 요청 ──────────────────────────────────────────────────
local function requestData()
    local ok, snap = pcall(function()
        return dataEvent:InvokeServer()
    end)
    if ok and snap then
        currentSnapshot = snap
        render()
    end
end

updateEvent.OnClientEvent:Connect(function(snap)
    if snap then
        currentSnapshot = snap
        render()  -- 창이 닫혀 있어도 미리 갱신해 둠 (첫 열기 시 즉시 표시)
    end
end)

main:GetPropertyChangedSignal("Visible"):Connect(function()
    if main.Visible then requestData() end
end)

-- X(닫기) 버튼
local closeButton = main:FindFirstChild("Close")
if closeButton then
    closeButton.MouseButton1Click:Connect(function()
        main.Visible = false
    end)
end

-- 시작 시 미리 데이터를 받아 박스까지 빌드해 둠
-- (첫 클릭 시 빈 화면처럼 보이는 문제 방지)
task.spawn(function()
    for attempt = 1, 10 do
        local ok, snap = pcall(function()
            return dataEvent:InvokeServer()
        end)
        if ok and snap then
            currentSnapshot = snap
            render()
            break
        end
        task.wait(0.5)
    end
end)

-- ── 리셋 타이머 카운트다운 ───────────────────────────────────────
-- 서버 스냅샷의 secondsLeft를 기준으로 매초 표시.
-- 0이 되면 데이터를 다시 받아 수령 가능 상태로 전환.
local function formatHMS(sec)
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

task.spawn(function()
    local lastRefresh = 0
    while true do
        if currentSnapshot then
            if currentSnapshot.canClaim then
                resetTimer.Text = "Reward ready!"
            else
                -- 서버 시각 기준 경과분을 빼서 남은 시간 계산
                local baseLeft = currentSnapshot.secondsLeft or 0
                local elapsed = os.time() - (currentSnapshot.serverNow or os.time())
                local remaining = baseLeft - elapsed
                if remaining <= 0 then
                    resetTimer.Text = "Reward ready!"
                    -- 리셋됐으니 서버에서 새 데이터 받기 (10초에 한 번만 시도)
                    if os.time() - lastRefresh > 10 then
                        lastRefresh = os.time()
                        task.spawn(function()
                            local ok, snap = pcall(function() return dataEvent:InvokeServer() end)
                            if ok and snap then currentSnapshot = snap; render() end
                        end)
                    end
                else
                    resetTimer.Text = "Next reward in: " .. formatHMS(remaining)
                end
            end
        end
        task.wait(1)
    end
end)

print("✅ DailyRewardClient 활성화")
