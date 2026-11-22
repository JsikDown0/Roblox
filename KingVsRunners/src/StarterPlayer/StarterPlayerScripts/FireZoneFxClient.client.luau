-- ═══════════════════════════════════════════════════════════════
-- 🔥 압박선 지대 연출 + 저체력 경고
--
-- [왜 지대 연출] 불기둥이 즉사에서 지속 데미지로 바뀌면서 "지금 내가 타는 중"을
--   알려줄 신호가 필요해졌다. 즉사는 결과가 즉시 보이지만 지속 데미지는
--   알려주지 않으면 "왜 HP가 깎이지?"가 된다.
--
-- [왜 저체력 경고를 따로] 지대 표시만 있으면 강도가 늘 같아서 "지대에 있다"만
--   전달되고 "위험하다"는 안 전달된다. HP 가 낮을수록 강해지는 별도 층을 쌓는다.
--   · 지대 비네트  = 어디에 있는가 (테마색, 은은함)
--   · 저체력 경고  = 얼마나 위험한가 (빨강, 점멸, HP 낮을수록 빠르고 진하게)
--   두 신호가 겹치면 "위험지대에서 죽어간다"가 한눈에 읽힌다.
--
-- ⚠️ 서버가 InFireZone 속성을 켜고 끈다(FirePressureSystem.applyZoneDamage).
--    클라는 그 속성만 보고 그린다 — 판정을 클라에서 다시 하지 않는다.
-- ⚠️ [테마] map1=water(쓰나미) / map2=lava(용암). 무조건 불을 붙이면
--    물에 잠겼는데 몸에 불이 붙는 그림이 된다(실측 2026-08-23).
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- 현재 맵 테마. 서버 브로드캐스트로 갱신된다.
local currentTheme = "water"
do
    local ev = ReplicatedStorage:FindFirstChild("FirePressureCountdown")
    if ev then
        ev.OnClientEvent:Connect(function(kind, _, themeName)
            if themeName then currentTheme = themeName end
        end)
    end
end

local THEME = {
    lava = {
        fire = true,
        colorA = Color3.fromRGB(255, 170, 40),
        colorB = Color3.fromRGB(255, 60, 10),
        vignette = Color3.fromRGB(255, 40, 0),
    },
    water = {
        fire = false,
        colorA = Color3.fromRGB(150, 220, 255),
        colorB = Color3.fromRGB(40, 120, 220),
        vignette = Color3.fromRGB(30, 110, 220),
    },
}
local function theme() return THEME[currentTheme] or THEME.water end

-- 저체력 경고 임계. 이 아래부터 빨간 점멸이 시작된다.
-- ⚠️ [2026-08-27] 0.5 → 0.35.
--   [왜] 불기둥·쓰나미 지대가 초당 15 데미지다. 태거 HP 150 기준 0.5 는 5초 만에 닿아,
--     지대에 들어가기만 하면 경고가 상시 켜져 있는 상태가 된다. 늘 켜져 있는 경고는
--     경고가 아니라 배경이 된다.
--   ⚠️ 비네트로 형태를 바꾼 것과 같은 세션에 조정했다. 둘 중 어느 쪽이 체감을 바꿨는지
--     구분하려면 이 값을 0.5 로 되돌려 한 판 비교할 것.
local LOW_HP_RATIO = 0.35
local GLOW_TEX = "rbxassetid://8451174579"

-- ── 캐릭터 이펙트 ──────────────────────────────────────────────
-- ⚠️ Destroy 하지 않고 Enabled 만 토글한다. 지대를 들락날락할 때마다
--    만들고 지우면 파티클이 매번 새로 준비되어 끊긴다.
local function setBurning(char, on)
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local t = theme()
    local fx = hrp:FindFirstChild("_FireZoneFx")

    -- 테마가 바뀌면 종류가 달라 재사용할 수 없다(Fire vs ParticleEmitter)
    if fx and fx:GetAttribute("Theme") ~= currentTheme then
        fx:Destroy() ; fx = nil
    end

    if on then
        if not fx then
            if t.fire then
                fx = Instance.new("Fire")
                fx.Heat = 12
                fx.Size = 7
                fx.Color = t.colorA
                fx.SecondaryColor = t.colorB
            else
                fx = Instance.new("ParticleEmitter")
                fx.Texture = GLOW_TEX
                fx.Color = ColorSequence.new(t.colorA, t.colorB)
                fx.Size = NumberSequence.new(1.6)
                fx.Transparency = NumberSequence.new(0.25)
                fx.Lifetime = NumberRange.new(0.4, 0.8)
                fx.Rate = 34
                fx.Speed = NumberRange.new(7, 13)
                fx.SpreadAngle = Vector2.new(40, 40)
                fx.Acceleration = Vector3.new(0, -26, 0)
                fx.LightEmission = 0.35
            end
            fx.Name = "_FireZoneFx"
            fx:SetAttribute("Theme", currentTheme)
            fx.Parent = hrp
        end
        fx.Enabled = true
    elseif fx then
        fx.Enabled = false
    end
end

-- ── 화면 오버레이 (2층) ────────────────────────────────────────
-- ⚠️ [2026-08-27] ImageLabel + GLOW_TEX → 가장자리 4줄 그라디언트로 교체.
--   [증상] 화면 정중앙이 제일 진해서 시야를 가리고 조잡해 보였다.
--   [원인] 주석엔 "비네트"라 적혀 있는데 물린 에셋(rbxassetid://8451174579)은 GLOW 였다.
--     글로우는 가운데가 밝고 가장자리로 갈수록 투명하다 — 비네트의 정반대다.
--     3인칭이라 조준점뿐 아니라 자기 캐릭터까지 덮었다.
--   [해결] 위/아래/좌/우 4줄 Frame + UIGradient 로 테두리만 물들인다.
--     · 텍스처 에셋에 의존하지 않는다(쓸 만한 비네트 ID 를 찾아 헤맬 필요가 없다)
--     · 모서리에서 두 줄이 겹쳐 자연히 더 진해진다 — 실제 비네트가 그렇게 보인다
--     · 화면 중앙은 아예 건드리지 않아 조준·캐릭터가 가려지지 않는다
--   ⚠️ 4모서리에 덩어리를 나눠 찍는 방식은 검토 후 폐기했다. 사이에 빈 구간이 생겨
--     "UI 장식 4개"로 읽히고, FPS 에서 모서리 분할은 '피격 방향'이라는 다른 신호다.
--     여기서 알리려는 건 '저체력 상태'(지속)이므로 끊김 없는 테두리가 맞다.
-- ⚠️ UIGradient.Transparency 는 Frame 의 BackgroundTransparency 와 함께 적용된다.
--   → 프레임 투명도만 올리면 그라디언트 모양 그대로 전체가 흐려진다(마스터 페이드).
local EDGE_THICK_X = 0.16   -- 좌우 줄 두께(화면 폭 대비)
local EDGE_THICK_Y = 0.22   -- 상하 줄 두께(화면 높이 대비). 와이드스크린이라 세로를 더 두껍게
local FADE_IN  = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
local FADE_OUT = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
-- rot 90 = 위→아래 진행, rot 0 = 왼→오른 진행
local EDGES = {
    { n = "Top",    size = UDim2.new(1, 0, EDGE_THICK_Y, 0), pos = UDim2.new(0, 0, 0, 0),
      rot = 90, seq = FADE_IN },
    { n = "Bottom", size = UDim2.new(1, 0, EDGE_THICK_Y, 0), pos = UDim2.new(0, 0, 1 - EDGE_THICK_Y, 0),
      rot = 90, seq = FADE_OUT },
    { n = "Left",   size = UDim2.new(EDGE_THICK_X, 0, 1, 0), pos = UDim2.new(0, 0, 0, 0),
      rot = 0,  seq = FADE_IN },
    { n = "Right",  size = UDim2.new(EDGE_THICK_X, 0, 1, 0), pos = UDim2.new(1 - EDGE_THICK_X, 0, 0, 0),
      rot = 0,  seq = FADE_OUT },
}

local function makeVignette(name, zIndex, color)
    local holder = Instance.new("Frame")
    holder.Name = name
    holder.Size = UDim2.fromScale(1, 1)
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel = 0
    holder.ZIndex = zIndex
    for _, e in ipairs(EDGES) do
        local f = Instance.new("Frame")
        f.Name = e.n
        f.Size = e.size
        f.Position = e.pos
        f.BackgroundColor3 = color
        f.BackgroundTransparency = 1   -- 시작은 완전 투명
        f.BorderSizePixel = 0
        f.ZIndex = zIndex
        local g = Instance.new("UIGradient")
        g.Rotation = e.rot
        g.Transparency = e.seq
        g.Parent = f
        f.Parent = holder
    end
    return holder
end

-- 4줄에 한꺼번에 적용. color 가 nil 이면 색은 유지한다.
-- ⚠️ 예전 ImageTransparency 대입 자리를 전부 이 함수로 바꿨다.
--   한 곳이라도 남겨두면 그 층만 안 꺼진다.
local function setVignette(holder, transparency, color)
    if not (holder and holder.Parent) then return end
    for _, f in ipairs(holder:GetChildren()) do
        if f:IsA("Frame") then
            f.BackgroundTransparency = transparency
            if color then f.BackgroundColor3 = color end
        end
    end
end

local gui, zoneLayer, dangerLayer

local function ensureGui()
    if gui and gui.Parent then return end
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local prev = pg:FindFirstChild("FireZoneOverlay")
    if prev then prev:Destroy() end

    gui = Instance.new("ScreenGui")
    gui.Name = "FireZoneOverlay"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 80
    gui.Parent = pg

    -- [1층] 지대 비네트 — 테마색, 은은하게. "여기가 위험지대다"
    zoneLayer = makeVignette("Zone", 1, theme().vignette)
    zoneLayer.Parent = gui

    -- [2층] 저체력 경고 — 빨강, 점멸. "죽기 직전이다"
    -- ⚠️ 지대와 분리한다. HP 가 낮으면 지대 밖에서도 떠야 한다(칼에 맞아 깎였을 때도).
    dangerLayer = makeVignette("Danger", 2, Color3.fromRGB(255, 25, 15))
    dangerLayer.Parent = gui
end

-- ── 감시 ───────────────────────────────────────────────────────
local watching = {}

local function watch(char)
    if not char or watching[char] then return end
    watching[char] = true

    local function update()
        setBurning(char, char:GetAttribute("InFireZone") == true)
    end
    char:GetAttributeChangedSignal("InFireZone"):Connect(update)
    update()

    char.AncestryChanged:Connect(function(_, parent)
        if not parent then watching[char] = nil end
    end)
end

local function hookPlayer(plr)
    if plr.Character then watch(plr.Character) end
    plr.CharacterAdded:Connect(watch)
end
for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
Players.PlayerAdded:Connect(hookPlayer)

-- AI 러너도 감시. 서버가 봇에게도 InFireZone 을 켜므로 안 그리면 봇만 멀쩡해 보인다.
local function hookModel(m)
    if m:IsA("Model") and m.Name:match("^AIRunner") then watch(m) end
end
for _, m in ipairs(workspace:GetChildren()) do hookModel(m) end
workspace.ChildAdded:Connect(hookModel)

-- ── 매 프레임 갱신 ─────────────────────────────────────────────
-- ⚠️ [성능] 예전엔 매 프레임 ensureGui() 를 불렀는데, 그 안의 FindFirstChildOfClass /
--    FindFirstChild 가 프레임마다 돌아 다른 작업(그랩 등)과 겹칠 때 버벅였다.
--    → GUI 는 한 번만 만들고, 캐릭터가 바뀔 때만 다시 확인한다.
-- ⚠️ 오버레이는 '변할 때만' 대입한다. 같은 값을 매 프레임 써넣으면
--    렌더 파이프라인이 매번 갱신 대상으로 잡는다.
ensureGui()
player.CharacterAdded:Connect(function()
    task.wait(0.3)
    ensureGui()
end)

local lastZoneT, lastDangerT = -1, -1
-- ⚠️ local 선언 필수. 없으면 전역이 되어 다른 스크립트와 충돌할 수 있다.
local lastFxUpdate = 0

RunService.RenderStepped:Connect(function()
    if not gui or not gui.Parent then return end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        if lastZoneT ~= 1 then setVignette(zoneLayer, 1) ; lastZoneT = 1 end
        if lastDangerT ~= 1 then setVignette(dangerLayer, 1) ; lastDangerT = 1 end
        return
    end

    local t = os.clock()

    -- [1층] 지대: 있으면 은은하게 맥동
    local inZone = char:GetAttribute("InFireZone") == true
    local zt
    if inZone then
        zt = 0.52 + math.sin(t * 3) * 0.1
    else
        zt = 1
    end
    if math.abs(zt - lastZoneT) > 0.008 then
        -- 테마색은 여기서 같이 넘긴다(map1 water / map2 lava 전환 대응).
        setVignette(zoneLayer, zt, inZone and theme().vignette or nil)
        lastZoneT = zt
    end

    -- [2층] 저체력: HP 가 낮을수록 빠르고 진하게 점멸
    -- ⚠️ 지대 여부와 무관하다. 칼에 맞아 깎였을 때도 위험은 위험이다.
    local ratio = hum.Health / math.max(hum.MaxHealth, 1)
    local dt2
    if ratio < LOW_HP_RATIO then
        local sev = math.clamp((LOW_HP_RATIO - ratio) / LOW_HP_RATIO, 0, 1)
        local speed = 4 + sev * 8
        local peak = 0.62 - sev * 0.34
        local pulse = (math.sin(t * speed) + 1) * 0.5
        dt2 = peak + (1 - peak) * (1 - pulse) * 0.55
    else
        dt2 = 1
    end
    if math.abs(dt2 - lastDangerT) > 0.008 then
        setVignette(dangerLayer, dt2)
        lastDangerT = dt2
    end

    -- [3층] 캐릭터 이펙트 강도.
    -- ⚠️ 매 프레임 할 필요가 없다. 0.2초마다만 갱신한다.
    if t - (lastFxUpdate or 0) < 0.2 then return end
    lastFxUpdate = t

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local fx = hrp and hrp:FindFirstChild("_FireZoneFx")
    if fx and inZone then
        local sev = math.clamp((LOW_HP_RATIO - ratio) / LOW_HP_RATIO, 0, 1)
        if fx:IsA("Fire") then
            fx.Size = 7 + sev * 8
            fx.Heat = 12 + sev * 10
        elseif fx:IsA("ParticleEmitter") then
            fx.Rate = 34 + sev * 60
            fx.Speed = NumberRange.new(7 + sev * 6, 13 + sev * 10)
        end
    elseif fx then
        -- ⚠️ 지대를 벗어나면 기본값으로 되돌린다. 안 그러면 키워둔 값이 남아
        --    다음에 들어갈 때 처음부터 격하게 시작한다.
        if fx:IsA("Fire") then
            fx.Size = 7 ; fx.Heat = 12
        elseif fx:IsA("ParticleEmitter") then
            fx.Rate = 34 ; fx.Speed = NumberRange.new(7, 13)
        end
    end
end)
