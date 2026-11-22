-- 👑 ThroneBeaconClient — 2단계 점령지 유도 화살표 (킹 전용, 텍스트 없음)
--
-- [왜] 라이브 관전에서 킹이 존을 지켜야 한다는 걸 모르고 멀뚱히 서 있었다.
--   배너·상단 라벨로 글자를 두 층 넣었지만 저연령층은 텍스트를 안 읽는다.
--
-- [왜 화살표인가 — 2026-09-20 1차 시도 기각]
--   처음엔 존 바닥을 크림슨 원판으로 맥동시켰다. 실패했다:
--   "채워진 영역 + 붉은 계열"은 이 게임에서 이미 **폭격 예고**의 문법이다
--   (해머하이 슬램 / 곡사포 / TNT). 존이 폭격 지점으로 읽혔다.
--   → 축을 두 개 바꾼다:
--     · 모양 : 채워진 영역(경고) → 이산 화살표(안내)
--     · 움직임: 제자리 확대(경고) → 존 쪽으로 흘러 들어감(안내)
--     모양과 움직임이 둘 다 다르면 같은 색이어도 안 헷갈린다.
--
-- [왜 흰색인가] 빨강·주황·노랑 = 위험 축(경고원), 금색 = VIP·과금 축이라 둘 다 막혔다.
--   청색은 러너 진영색이다. 킹만 보는 마커라 진영색을 선언할 이유가 없으므로
--   2단계 바닥(진빨강) 대비가 가장 센 흰색을 쓴다. 한 줄로 바꿀 수 있게 상수로 뺐다.
--
-- [축 분리] 배너=도입(한 번) / 상단 라벨=상태(글자) / 이 화살표=위치(공간).

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local capEvent = ReplicatedStorage:WaitForChild("CaptureState")

local ARROW_COLOR  = Color3.fromRGB(255, 255, 255)
local ARM_LEN      = 5.0     -- 화살표 한 팔 길이
local ARM_THICK    = 1.1     -- 팔 두께
local ARM_HEIGHT   = 0.35    -- 바닥에서 띄우는 높이(두께)
local Y_LIFT       = 0.3     -- 존 표면 위로 살짝
local TRAVEL_FAR   = 13      -- 존 가장자리 기준 바깥 시작 거리
local TRAVEL_NEAR  = 1.5     -- 존 가장자리 기준 도착 거리(= 존 바로 앞)
local CYCLE        = 1.25    -- 한 번 흘러 들어가는 데 걸리는 시간(초)
local PEAK_ALPHA   = 0.15    -- 가장 진할 때 투명도
local INSIDE_PAD   = 3       -- "존 안" 판정 여유(stud). 가장자리 깜빡임 방지

-- 상하좌우 4방향(월드 축). 존 바깥 이 방향에서 안쪽으로 들어온다.
local DIRS = {
    Vector3.new( 1, 0,  0),
    Vector3.new(-1, 0,  0),
    Vector3.new( 0, 0,  1),
    Vector3.new( 0, 0, -1),
}

local zones = {}     -- { part, center, radius, arrows = { {a1, a2, out} } }
local loopConn = nil

local function isKing()
    return player:GetAttribute("Role") == "Tagger"
end

-- Y축 회전. 화살촉 두 팔의 방향을 구하는 데만 쓴다.
local function rotY(v, deg)
    local a = math.rad(deg)
    return Vector3.new(v.X * math.cos(a) - v.Z * math.sin(a), 0,
                       v.X * math.sin(a) + v.Z * math.cos(a))
end

-- 활성 맵의 존만 고른다.
-- ⚠️ 맵 이름으로 가르지 않는다. 비활성 맵도 workspace 에 남아 있어 이름으로 찾으면
--   항상 map1 이 잡히는 사고가 이미 두 번 있었다(CaptureSystem:435 / BarricadeSystem:1168).
-- ⚠️ 런타임 신호를 쓴다 — setZoneVisible 이 비활성 맵 존을 Transparency 1 로 두므로
--   "보이는 CapturePoint" 가 곧 활성 존이다. 맵이 늘어도 코드를 안 고쳐도 된다.
-- ⚠️ map2 도 존이 2개다(CapturePointA/B). CaptureSystem:449 주석의 "map2 = 1개" 는 낡았다 —
--   대표 존 하나만 가리키면 다른 존에서 뺏기면서 UI 가 거짓말을 한다. 전부 표시한다.
local function activeZoneParts()
    local out = {}
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Folder") or m:IsA("Model") then
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") and d.Name:sub(1, 12) == "CapturePoint"
                   and d.Transparency < 1 then
                    out[#out + 1] = d
                end
            end
        end
    end
    return out
end

local function makeArm()
    local p = Instance.new("Part")
    p.Name = "_ThroneArrow"
    p.Material = Enum.Material.Neon
    p.Color = ARROW_COLOR
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false    -- ⚠️ 조준 레이캐스트에 잡히면 청사진이 이 위에 뜬다
    p.CanTouch = false    -- ⚠️ 존 판정(GetPartBoundsInBox)에 섞이면 안 된다
    p.CastShadow = false
    p.Size = Vector3.new(ARM_THICK, ARM_HEIGHT, ARM_LEN)
    p.Transparency = 1
    -- ⚠️ 클라에서 workspace 에 직접 붙인다 = 이 화면에만 존재한다. 서버·타 유저와 무관.
    p.Parent = workspace
    return p
end

local function clearArrows()
    for _, z in ipairs(zones) do
        for _, a in ipairs(z.arrows) do
            pcall(function() a.a1:Destroy() end)
            pcall(function() a.a2:Destroy() end)
        end
    end
    table.clear(zones)
    if loopConn then loopConn:Disconnect() ; loopConn = nil end
end

local function setAlpha(z, v)
    for _, a in ipairs(z.arrows) do
        a.a1.Transparency = v
        a.a2.Transparency = v
    end
end

local function buildArrows()
    clearArrows()
    -- ⚠️ 킹이 아니면 아무것도 만들지 않는다. 러너 화면은 지금이 맞다
    --   (밟으면 네온벽이 솟는 게 러너의 신호다 — setCaptureFx).
    if not isKing() then return end

    for _, part in ipairs(activeZoneParts()) do
        local z = {
            part   = part,
            center = part.Position,
            radius = math.max(part.Size.X, part.Size.Z) / 2,
            arrows = {},
        }
        for _, outDir in ipairs(DIRS) do
            z.arrows[#z.arrows + 1] = { a1 = makeArm(), a2 = makeArm(), out = outDir }
        end
        zones[#zones + 1] = z
    end
    if #zones == 0 then return end

    loopConn = RunService.Heartbeat:Connect(function()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root or not isKing() then
            for _, z in ipairs(zones) do setAlpha(z, 1) end
            return
        end

        -- 킹이 어느 존에든 올라와 있으면 전부 끈다 = "잘 서 있다"
        local inside = false
        for _, z in ipairs(zones) do
            local off = root.Position - z.center
            if Vector3.new(off.X, 0, off.Z).Magnitude <= (z.radius + INSIDE_PAD) then
                inside = true
                break
            end
        end
        if inside then
            for _, z in ipairs(zones) do setAlpha(z, 1) end
            return
        end

        -- 바깥으로 갈수록 옅고, 존에 가까워질수록 진하다가 도착 직전에 사라진다.
        -- ⚠️ 시작·끝을 완전 투명으로 둔다. 안 그러면 리셋 순간에 툭 튀어 '점멸'로 읽힌다.
        local t = (os.clock() % CYCLE) / CYCLE
        local alpha = 1 - math.sin(t * math.pi) * (1 - PEAK_ALPHA)

        for _, z in ipairs(zones) do
            local dist = z.radius + TRAVEL_FAR + (TRAVEL_NEAR - TRAVEL_FAR) * t
            local y = z.center.Y + Y_LIFT
            for _, a in ipairs(z.arrows) do
                local tip = Vector3.new(
                    z.center.X + a.out.X * dist, y,
                    z.center.Z + a.out.Z * dist)
                local inward = -a.out
                -- 화살촉 두 팔: 진행 방향에서 ±135° 로 뒤로 벌린다
                local d1 = rotY(inward,  135)
                local d2 = rotY(inward, -135)
                local c1 = tip + d1 * (ARM_LEN / 2)
                local c2 = tip + d2 * (ARM_LEN / 2)
                a.a1.CFrame = CFrame.lookAt(c1, c1 + d1)
                a.a2.CFrame = CFrame.lookAt(c2, c2 + d2)
                a.a1.Transparency = alpha
                a.a2.Transparency = alpha
            end
        end
    end)
end

capEvent.OnClientEvent:Connect(function(kind)
    if kind == "start" then
        -- ⚠️ 존 가시화(setZoneVisible)와 이 이벤트가 같은 프레임이라 Transparency 가
        --   아직 안 왔을 수 있다. 한 박자 뒤에 훑는다.
        task.delay(0.35, buildArrows)
    elseif kind == "stop" then
        clearArrows()
    end
end)

-- 역할이 늦게 확정되는 경우 대비(킹 배정이 2단계 신호보다 늦게 올 수 있다)
player:GetAttributeChangedSignal("Role"):Connect(function()
    if #zones > 0 or isKing() then buildArrows() end
end)

-- 🔄 안전망. "이벤트만 믿으면 안 된다" — stop 을 놓치면 로비에서도 화살표가 남는다.
--   ⚠️ 켜는 코드에 끄는 코드를 같이.
task.spawn(function()
    while true do
        task.wait(1)
        local ph = ReplicatedStorage:GetAttribute("RoundPhase")
        if ph ~= "stage1" and ph ~= "stage2" and #zones > 0 then
            clearArrows()
        end
    end
end)

print("✅ ThroneBeaconClient 활성화 (유도 화살표)")
