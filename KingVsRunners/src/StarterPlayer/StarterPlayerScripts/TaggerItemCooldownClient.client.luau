-- TaggerItemCooldownClient
-- 태거 아이템 "전역 최소 간격"을 화면에 표시한다.
--
-- 배경: 아이템별 쿨다운이 서로 독립이라 아이템을 바꿔가며 연사가 가능했다(난사).
--   서버(ItemSpawnHandler)가 종류와 무관한 최소 간격 GLOBAL_COOLDOWN 을 강제하는데,
--   화면에 표시가 없으면 "왜 안 나가지?"가 된다. PushTool 쿨다운 바와 같은 형태로 보여준다.
--
-- 시간 동기화: 서버가 workspace:GetServerTimeNow() 기준 "끝나는 시각"을 속성으로 준다.
--   tick()/os.clock() 은 기기마다 기준이 달라 못 쓰고, GetServerTimeNow 는 동기화돼 있어
--   클라가 그대로 비교하면 남은 시간이 정확히 나온다.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui, frame, fill, label

local function build()
    if gui and gui.Parent then return end
    gui = Instance.new("ScreenGui")
    gui.Name = "TaggerItemCooldownGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 8
    gui.Parent = player:WaitForChild("PlayerGui")

    frame = Instance.new("Frame")
    frame.Name = "Bar"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    -- PushTool 바가 Y 0.8 이므로 겹치지 않게 위로 띄운다(2단계에선 둘 다 뜰 수 있음)
    frame.Position = UDim2.new(0.5, 0, 0.73, 0)
    frame.Size = UDim2.new(0, 200, 0, 22)
    frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    stroke.Parent = frame

    fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.AnchorPoint = Vector2.new(0, 0.5)
    fill.Position = UDim2.new(0, 0, 0.5, 0)
    fill.Size = UDim2.new(1, 0, 1, 0)
    -- 금색 계열 — 태거(왕) 색 언어에 맞춤. PushTool 은 붉은색이라 구분도 된다.
    fill.BackgroundColor3 = Color3.fromRGB(224, 170, 40)
    fill.BorderSizePixel = 0
    fill.Parent = frame

    local fcorner = Instance.new("UICorner")
    fcorner.CornerRadius = UDim.new(0, 6)
    fcorner.Parent = fill

    label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = ""
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 0.4
    label.ZIndex = 2
    label.Parent = frame
end

build()

RunService.RenderStepped:Connect(function()
    if not frame then return end
    -- 태거가 아니면 숨김
    if player:GetAttribute("Role") ~= "Tagger" then
        frame.Visible = false
        return
    end
    local until_ = player:GetAttribute("TaggerGlobalCDUntil")
    local length = player:GetAttribute("TaggerGlobalCDLength") or 1
    if not until_ then frame.Visible = false return end

    local remain = until_ - workspace:GetServerTimeNow()
    if remain <= 0 then
        frame.Visible = false
        return
    end
    frame.Visible = true
    fill.Size = UDim2.new(math.clamp(remain / length, 0, 1), 0, 1, 0)
    label.Text = string.format("ITEM  %.1fs", remain)
end)

print("✅ TaggerItemCooldownClient 활성화 (아이템 전역 쿨다운 표시)")
