-- 🆓 무료 로테이션 만료 알림
--
-- [왜] 로테 아이템을 로드아웃에 넣어둔 채 날짜가 넘어가면 그 아이템은 잠긴다.
--      서버가 로드아웃에서 빼주는데, 알리지 않으면 유저는 "내가 안 건드렸는데
--      왜 빠졌지"가 되고, 더 나쁘게는 빠진 줄도 모르고 라운드에 나간다.
--
-- ⚠️ 기본 아이템으로 자동 치환하지 않기로 한 설계라(무엇으로 채울지는 유저가
--    정할 문제), 이 알림이 유일한 안내 수단이다. 빠뜨리면 안 된다.
-- ⚠️ Stage2 알림과 달리 화면 중앙에 띄우지 않는다. 급한 경고가 아니라
--    로비에서 읽고 인벤을 열게 하는 안내라 상단이 적절하다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("RotationExpired")

local HOLD_TIME = 5   -- 로비에서 읽을 시간. 짧으면 놓친다.

local function show(removedNames, filledDefault)
    if type(removedNames) ~= "table" or #removedNames == 0 then return end

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end

    -- 이전 알림이 떠 있으면 교체(중첩 방지)
    local prev = pg:FindFirstChild("RotationExpiredNotice")
    if prev then prev:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "RotationExpiredNotice"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 150
    gui.Parent = pg

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0, 70)
    frame.Size = UDim2.new(0, 460, 0, 74)
    frame.BackgroundColor3 = Color3.fromRGB(38, 34, 22)
    frame.BackgroundTransparency = 0.05
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(255, 200, 70)
    stroke.Thickness = 2

    local title = Instance.new("TextLabel")
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 8)
    title.Size = UDim2.new(1, -20, 0, 28)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.fromRGB(255, 210, 90)
    title.Text = "Free rotation ended"
    title.Parent = frame

    local sub = Instance.new("TextLabel")
    sub.AnchorPoint = Vector2.new(0.5, 1)
    sub.Position = UDim2.new(0.5, 0, 1, -8)
    sub.Size = UDim2.new(1, -20, 0, 30)
    sub.BackgroundTransparency = 1
    sub.Font = Enum.Font.GothamMedium
    sub.TextScaled = true
    sub.TextColor3 = Color3.fromRGB(235, 235, 235)
    -- ⚠️ displayName 을 서버가 보내므로 그대로 쓴다(내부 name 을 노출하지 않기 위해).
    -- ⚠️ 로드아웃이 전부 비어 기본값으로 보충된 경우는 문구가 달라야 한다.
    --    "확인해 달라"가 아니라 "이미 채워뒀다"가 정확한 안내다.
    sub.Text = filledDefault
        and (table.concat(removedNames, ", ") .. " expired — basic items equipped")
        or  (table.concat(removedNames, ", ") .. " removed — check your loadout")
    sub.Parent = frame

    -- 등장/퇴장
    frame.Position = UDim2.new(0.5, 0, 0, 40)
    frame.BackgroundTransparency = 1
    title.TextTransparency = 1
    sub.TextTransparency = 1
    stroke.Transparency = 1

    local inInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(frame, inInfo, {
        Position = UDim2.new(0.5, 0, 0, 70),
        BackgroundTransparency = 0.05,
    }):Play()
    TweenService:Create(title, inInfo, {TextTransparency = 0}):Play()
    TweenService:Create(sub, inInfo, {TextTransparency = 0}):Play()
    TweenService:Create(stroke, inInfo, {Transparency = 0}):Play()

    task.delay(HOLD_TIME, function()
        if not frame.Parent then return end
        local outInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(frame, outInfo, {
            Position = UDim2.new(0.5, 0, 0, 40),
            BackgroundTransparency = 1,
        }):Play()
        TweenService:Create(title, outInfo, {TextTransparency = 1}):Play()
        TweenService:Create(sub, outInfo, {TextTransparency = 1}):Play()
        TweenService:Create(stroke, outInfo, {Transparency = 1}):Play()
    end)

    Debris:AddItem(gui, HOLD_TIME + 1)
end

remote.OnClientEvent:Connect(show)
