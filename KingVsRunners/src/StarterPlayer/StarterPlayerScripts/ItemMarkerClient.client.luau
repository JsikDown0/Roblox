-- ItemMarkerClient (태거 아이템 빨강선 — 러너 시점 전용)
-- "내가 러너일 때만" TaggerItems 콜리전 그룹 아이템에 빨강 빛기둥 선을 붙인다.
-- 그래픽 낮아 본체가 원거리 컬링돼도 선은 보이므로, 날아오는 아이템에 미리 대응 가능.
-- 모든 태거 아이템 대상(멈춰있어도). 클라이언트 생성이라 러너 화면에만 보임.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local MARKED_ATTR = "_ItemMarker"   -- 중복 부착 방지 표식

-- 아이템의 마커 부착 대상 파트 1개 선정 (모델이면 대표 파트, 단일이면 자신)
local function pickAnchor(container)
    if container:IsA("BasePart") then return container end
    if container:IsA("Model") then
        if container.PrimaryPart then return container.PrimaryPart end
        for _, d in ipairs(container:GetDescendants()) do
            if d:IsA("BasePart") then return d end
        end
    end
    return nil
end

local function addLine(container)
    if container:GetAttribute(MARKED_ATTR) then return end
    local anchor = pickAnchor(container)
    if not anchor then return end
    container:SetAttribute(MARKED_ATTR, true)

    local PILLAR_HEIGHT = 45
    local PILLAR_WIDTH  = 1.0
    local beamGui = Instance.new("BillboardGui")
    beamGui.Name = "ItemBeam"
    beamGui.Adornee = anchor
    beamGui.AlwaysOnTop = true
    beamGui.MaxDistance = 2000
    beamGui.LightInfluence = 0
    beamGui.Size = UDim2.fromScale(PILLAR_WIDTH, PILLAR_HEIGHT)
    beamGui.StudsOffset = Vector3.new(0, PILLAR_HEIGHT / 2, 0)
    local pillar = Instance.new("Frame")
    pillar.Size = UDim2.fromScale(1, 1)
    pillar.BackgroundColor3 = Color3.fromRGB(255, 0, 220)  -- 마젠타 (빨강과 구분 + 얼음맵 등 밝은 배경에서도 잘 보임)
    pillar.BackgroundTransparency = 0.15
    pillar.BorderSizePixel = 0
    pillar.Parent = beamGui
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(1, 0.85),
    })
    grad.Parent = pillar
    local pstroke = Instance.new("UIStroke")
    pstroke.Color = Color3.fromRGB(120, 0, 100)  -- 어두운 마젠타 외곽선
    pstroke.Thickness = 1
    pstroke.Transparency = 0.4
    pstroke.Parent = pillar
    -- 아이템(또는 대표 파트)에 부모를 둬서, 아이템 소멸 시 마커도 함께 사라지게
    beamGui.Parent = anchor
end

-- TaggerItems 파트가 속한 최상위 컨테이너(모델 또는 단일 파트) 반환
local function topContainer(part)
    local top = part
    while top.Parent and top.Parent ~= workspace do top = top.Parent end
    return top
end

local function isRunner()
    return player:GetAttribute("Role") == "Runner"
end

-- 전체 스캔: 러너 시점 + 마커 토글 ON일 때만 모든 TaggerItems 아이템에 선 부착
local function scanItems()
    if not isRunner() then return end
    if _G.MarkersEnabled == false then return end  -- 토글 OFF면 부착 안 함
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("BasePart") and p.CollisionGroup == "TaggerItems" then
            addLine(topContainer(p))
        end
    end
end

-- 마커 토글 상태
local function markersEnabled()
    if _G.MarkersEnabled == nil then return true end
    return _G.MarkersEnabled
end

-- 마커를 보여야 하는 조건: 러너 시점 + 마커 토글 ON
local function shouldShow()
    return isRunner() and markersEnabled()
end

-- 마커 모두 제거 + 재부착 표식(_ItemMarker)도 해제 (다시 켤 때 재생성되도록)
local function clearAll()
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BillboardGui") and d.Name == "ItemBeam" then
            d:Destroy()
        end
    end
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("BasePart") and p.CollisionGroup == "TaggerItems" then
            topContainer(p):SetAttribute(MARKED_ATTR, nil)
        end
    end
end

-- ⚡ [2026-08-28] 새 아이템은 이벤트로 잡는다 — 폴링만으로 버티지 않는다.
--   [원인] scanItems 가 0.3초마다 workspace:GetDescendants() 전체를 돌았다.
--     map1 약 4,000 파트 기준 초당 13,000 순회 + 4,000짜리 테이블 3.3개 할당.
--     서버가 아니라 '클라이언트' 부하라 저사양·모바일에서 그대로 체감된다.
--   [왜 ChildAdded 로 충분한가] 태거 아이템은 workspace 직속 자식이다
--     (ItemSpawnHandler: newItem.Parent = workspace). topContainer 가 workspace
--     자식까지 거슬러 올라가는 것도 같은 전제다.
--   [왜 지연이 필요 없나] CollisionGroup 은 parent '보다 먼저' 설정된다
--     (ItemSpawnHandler 1269~1273행 → 1475행). ChildAdded 시점에 이미 판별 가능.
--   ⚠️ 그래도 아래 전체 재스캔을 지우지 말 것. 폴더 안에 들어가는 경로
--     (프드 얼음 등)는 ChildAdded 가 못 잡는다. 주기를 늦춰 안전망으로 남긴다.
local function scanOne(child)
    if not shouldShow() then return end
    if child:IsA("BasePart") then
        if child.CollisionGroup == "TaggerItems" then addLine(child) end
        return
    end
    for _, p in ipairs(child:GetDescendants()) do
        if p:IsA("BasePart") and p.CollisionGroup == "TaggerItems" then
            addLine(child)   -- child 가 곧 최상위 컨테이너다
            return
        end
    end
end
workspace.ChildAdded:Connect(scanOne)

-- 역할/토글 변경 대응
player:GetAttributeChangedSignal("Role"):Connect(function()
    if shouldShow() then scanItems() else clearAll() end
end)

-- 안전망 재스캔: ChildAdded 가 놓치는 경로(폴더 중첩 등)를 뒤늦게라도 잡는다.
-- ⚠️ 주기를 다시 줄이지 말 것 — 이 루프가 원래 부하의 원인이었다. 새 아이템은
--    위 ChildAdded 가 즉시 처리하므로 여기서 빨리 돌 이유가 없다.
local RESCAN_DT = 2.0
task.spawn(function()
    local lastShow = shouldShow()
    while true do
        local nowShow = shouldShow()
        if nowShow ~= lastShow then
            lastShow = nowShow
            if nowShow then scanItems() else clearAll() end
        end
        if nowShow then scanItems() end
        task.wait(RESCAN_DT)
    end
end)

if shouldShow() then scanItems() end
print("✅ ItemMarkerClient 활성화 (태거 아이템 마커 — 러너 시점)")
