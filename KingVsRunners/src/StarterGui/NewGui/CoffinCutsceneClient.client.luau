-- ⚰️ CoffinCutsceneClient
-- 데스 코핀 킬이펙트 피해자 전용 컷씬 (카메라 + UI 연출)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")

local localPlayer  = Players.LocalPlayer
local camera       = workspace.CurrentCamera
local CoffinCutsceneEvent = ReplicatedStorage:WaitForChild("CoffinCutsceneEvent")

-- ── 이전 컷씬 잔재 정리 ───────────────────────────────────────────
-- respawn 시 NewGui가 reset되면서 컷씬 스크립트가 cleanup 도중에 죽으면
-- 카메라가 Scriptable로 잠겨있고 CoffinCutsceneGui도 PlayerGui에 고립됨
-- → 스크립트 시작 시 카메라 강제 리셋 + 잔재 GUI 정리 + CameraSubject 재바인딩
local existingGui = localPlayer.PlayerGui:FindFirstChild("CoffinCutsceneGui")
if existingGui then
    existingGui:Destroy()
end
if camera then
    camera.CameraType = Enum.CameraType.Custom
    local char = localPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            camera.CameraSubject = hum
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local pos = hrp.Position
            camera.CFrame = CFrame.new(pos + Vector3.new(0, 5, 12), pos)
        end
    end
end
-- ── UI 생성 ──────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name              = "CoffinCutsceneGui"
screenGui.ResetOnSpawn      = false
screenGui.IgnoreGuiInset    = true
screenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
screenGui.Enabled           = false
screenGui.Parent            = localPlayer.PlayerGui

-- 레터박스 상단
local topBar = Instance.new("Frame", screenGui)
topBar.BackgroundColor3  = Color3.fromRGB(0, 0, 0)
topBar.BorderSizePixel   = 0
topBar.Size              = UDim2.new(1, 0, 0, 0)
topBar.Position          = UDim2.new(0, 0, 0, 0)
topBar.ZIndex            = 10

-- 레터박스 하단
local bottomBar = Instance.new("Frame", screenGui)
bottomBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bottomBar.BorderSizePixel  = 0
bottomBar.Size             = UDim2.new(1, 0, 0, 0)
bottomBar.Position         = UDim2.new(0, 0, 1, 0)
bottomBar.ZIndex           = 10

-- 비네팅 오버레이 (어두운 테두리 효과)
local vignette = Instance.new("Frame", screenGui)
vignette.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
vignette.BackgroundTransparency = 1
vignette.BorderSizePixel      = 0
vignette.Size                 = UDim2.new(1, 0, 1, 0)
vignette.ZIndex               = 9
-- UIGradient로 가장자리 어둡게
local grad = Instance.new("UIGradient", vignette)
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)),
    ColorSequenceKeypoint.new(0.3, Color3.fromRGB(0,0,0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0))
})
grad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.3),
    NumberSequenceKeypoint.new(0.35, 1),
    NumberSequenceKeypoint.new(0.65, 1),
    NumberSequenceKeypoint.new(1, 0.3)
})
grad.Rotation = 0

-- 전체 블랙 페이드 (죽는 순간 블랙아웃)
local fadeFrame = Instance.new("Frame", screenGui)
fadeFrame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
fadeFrame.BackgroundTransparency = 1
fadeFrame.BorderSizePixel        = 0
fadeFrame.Size                   = UDim2.new(1, 0, 1, 0)
fadeFrame.ZIndex                 = 12

-- ── 컷씬 재생 함수 ───────────────────────────────────────────────
local function playCutscene(camPos, camLookAt, forceDuration)
    screenGui.Enabled = true

    -- 레터박스 등장 (0.4초)
    TweenService:Create(topBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(1, 0, 0.075, 0)}):Play()
    TweenService:Create(bottomBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(1, 0, 0.075, 0), Position = UDim2.new(0, 0, 0.925, 0)}):Play()

    -- 비네팅 등장
    TweenService:Create(vignette, TweenInfo.new(0.5),
        {BackgroundTransparency = 0.0}):Play()

    -- 카메라 잠금 → 관 정면으로 트윈
    camera.CameraType = Enum.CameraType.Scriptable
    local targetCF = CFrame.lookAt(camPos, camLookAt)
    TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {CFrame = targetCF}):Play()

    -- 카메라를 약간 앞으로 천천히 당김 (임장감) — 2초 후 시작, 6초에 걸쳐 줌
    task.delay(2.0, function()
        local zoomCF = CFrame.lookAt(camPos + (camLookAt - camPos).Unit * 3, camLookAt)
        TweenService:Create(camera, TweenInfo.new(6.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            {CFrame = zoomCF}):Play()
    end)

    -- ── 컷씬 종료 공통 처리 (중복 실행 방지) ──────────────────────────
    local cutsceneEnded = false
    local conn

    local function endCutscene()
        if cutsceneEnded then return end
        cutsceneEnded = true
        if conn then conn:Disconnect() end

        task.wait(0.2)

        -- 블랙아웃
        TweenService:Create(fadeFrame, TweenInfo.new(0.6, Enum.EasingStyle.Quad),
            {BackgroundTransparency = 0}):Play()

        task.wait(0.8)

        -- 카메라 복구
        camera.CameraType = Enum.CameraType.Custom

        -- UI 페이드 아웃
        TweenService:Create(topBar,    TweenInfo.new(0.5), {Size = UDim2.new(1, 0, 0, 0)}):Play()
        TweenService:Create(bottomBar, TweenInfo.new(0.5),
            {Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 1, 0)}):Play()
        TweenService:Create(vignette,  TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
        TweenService:Create(fadeFrame, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()

        task.wait(0.6)
        screenGui.Enabled = false
    end

    -- 캐릭터 사망 감지 → 즉시 종료
    local character = localPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    conn = humanoid.Died:Connect(endCutscene)

    -- 강제 종료 타이머 (서버에서 넘겨준 시간, 없으면 기본 14초)
    task.delay(forceDuration or 14, endCutscene)
end


-- ── 파티클 Emit 루프 (관이 올라온 후 클라이언트에서 반복 방출) ─────────
local activeEmitLoops = {}  -- coffin → active 플래그

local function startEmitLoop(coffin)
    if not coffin or not coffin.Parent then return end

    -- 이미 실행 중이면 중지
    if activeEmitLoops[coffin] then
        activeEmitLoops[coffin] = false
    end
    activeEmitLoops[coffin] = true

    for _, d in ipairs(coffin:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            local fillCount = math.ceil(d.Rate * d.Lifetime.Max)
            fillCount = math.min(fillCount, 10)
            fillCount = math.max(fillCount, 1)
            local interval = d.Lifetime.Max

            task.spawn(function()
                while activeEmitLoops[coffin] and coffin.Parent and d.Parent do
                    d:Emit(fillCount)
                    task.wait(interval)
                end
            end)
        end
    end
end

-- ── 이벤트 수신 ──────────────────────────────────────────────────
CoffinCutsceneEvent.OnClientEvent:Connect(function(camPos, camLookAt, forceDuration, coffin)
    local character = localPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    playCutscene(camPos, camLookAt, forceDuration)

    -- 관이 올라오는 시간(~2초) + 여유 후 Emit 루프 시작
    if coffin then
        task.delay(2.5, function()
            startEmitLoop(coffin)
        end)

        -- 컷씬 종료 후 루프 중단
        task.delay(forceDuration or 14, function()
            if activeEmitLoops[coffin] then
                activeEmitLoops[coffin] = false
            end
        end)
    end
end)
