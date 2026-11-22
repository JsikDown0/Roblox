-- NOOB 지그재그 주행 (범용: 모든 뉴비 스킨 공용)
-- CFrame 직접 제어 + 지형/산 레이캐스트 + 시작 방향 랜덤 + 벽 반사(reflect).
-- → 스폰 위치마다 튕기는 지점/타이밍이 달라 경로가 전부 다름(트릭키함) + 산 절대 안 뚫음.
-- 스폰 시 ItemSpawnHandler가 활성화. 모든 파트를 앵커링하고 경로를 코드가 100% 결정.

local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local model = script.Parent
local core  = model:IsA("Model") and model.PrimaryPart or model
if not core then return end

-- ── 튜닝 파라미터 ──────────────────────────────
local FORWARD_SPEED = 48     -- 전진 속도 (-x 방향, stud/s)
local SIDE_SPEED    = 80     -- 좌우 이동 속도 (stud/s) — 클수록 지그재그 가파름
local WALL_MARGIN   = 3      -- 산/벽이 이 거리 안에 들면 튕김 (stud) — 작을수록 끝까지 붙음
local HOVER_HEIGHT  = 0.5    -- 바닥에서 살짝 띄움 (BOTTOM_OFFSET에 더해짐)
local RAY_UP        = 60     -- 높이 레이캐스트 시작점을 위로
local RAY_DOWN      = 400    -- 아래로 쏘는 거리
local SIDE_RAY_LEN  = 60     -- 옆 산 감지 레이 길이
local END_X         = -240   -- 이 x 이하로 가면 주행 종료

-- ── 시작 상태 ──────────────────────────────────
local startPos = core.Position
local curX = startPos.X
local curZ = startPos.Z
local zDir = (math.random() < 0.5) and 1 or -1   -- 시작 좌우 방향 랜덤
local lastY = startPos.Y

-- 피벗(코어 중심)에서 모델 바닥까지 거리 → 이만큼 띄워야 땅에 안 박히고 선다
local _, bbSize = model:GetBoundingBox()
local BOTTOM_OFFSET = bbSize.Y / 2

-- 모든 파트를 앵커링 (R6 Motor6D 출렁임 방지 + _CollisionCore 구조 모두 안정)
-- 코어 기준 상대 오프셋을 저장해, 코어 CFrame을 옮길 때 함께 따라오게 한다.
local parts = {}   -- { part = BasePart, offset = CFrame(코어→파트) }
if model:IsA("Model") then
    local coreCF = core.CFrame
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            parts[#parts+1] = { part = d, offset = coreCF:ToObjectSpace(d.CFrame) }
            d.Anchored = true
            d.CanCollide = false   -- 앵커 중 러너가 막히지 않게(즉사 판정은 Touch로 처리)
        end
    end
else
    core.Anchored = true
    parts[#parts+1] = { part = core, offset = CFrame.new() }
end

-- 산/벽 레이캐스트(Mountains, Walls 그룹만 감지)
local sideParams = RaycastParams.new()
sideParams.FilterType = Enum.RaycastFilterType.Include
local barriers = {}
for _, d in ipairs(Workspace:GetDescendants()) do
    if d:IsA("BasePart") and (d.CollisionGroup == "Mountains" or d.CollisionGroup == "Walls") then
        barriers[#barriers+1] = d
    end
end
sideParams.FilterDescendantsInstances = barriers

-- 높이 레이캐스트(자기 자신만 무시)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { model }
groundParams.IgnoreWater = true

local function sideDistance(x, y, z, zSign)
    local origin = Vector3.new(x, y, z)
    local hit = Workspace:Raycast(origin, Vector3.new(0, 0, zSign * SIDE_RAY_LEN), sideParams)
    if hit then
        return (hit.Position - origin).Magnitude
    end
    return math.huge
end

local function groundHit(x, z)
    local origin = Vector3.new(x, lastY + RAY_UP, z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -RAY_DOWN, 0), groundParams)
    if result then
        return result.Position.Y, result.Normal
    end
    return lastY, Vector3.new(0, 1, 0)
end

-- 코어를 새 CFrame으로 옮기고, 저장한 오프셋대로 나머지 파트도 함께 이동
local function moveTo(coreCF)
    core.CFrame = coreCF
    for _, info in ipairs(parts) do
        if info.part ~= core then
            info.part.CFrame = coreCF * info.offset
        end
    end
end

local conn
conn = RunService.Heartbeat:Connect(function(dt)
    if not core.Parent or not model.Parent then
        conn:Disconnect()
        return
    end

    -- 전진
    curX = curX - FORWARD_SPEED * dt

    -- 진행 방향(현재 zDir)으로 산이 가까운지 검사 → 가까우면 끝까지 붙인 뒤 방향 반전(튕김)
    local distAhead = sideDistance(curX, lastY + 2, curZ, zDir)
    if distAhead <= WALL_MARGIN then
        curZ = curZ + zDir * math.max(0, distAhead - 1)
        zDir = -zDir
    end

    -- 좌우 이동
    curZ = curZ + zDir * SIDE_SPEED * dt

    -- 높이 + 표면 법선: 지형 추적 (y 튐 방지)
    local gy, normal = groundHit(curX, curZ)
    local maxStep = 4
    if gy > lastY + maxStep then gy = lastY + maxStep end
    if gy < lastY - maxStep then gy = lastY - maxStep end
    lastY = gy

    local targetY = gy + BOTTOM_OFFSET + HOVER_HEIGHT
    local pos = Vector3.new(curX, targetY, curZ)

    -- 진행 방향을 표면 법선(up)에 맞춰 세움 → Hill 경사에 직립
    local up = normal
    local forward = Vector3.new(-1, 0, zDir * 0.4)
    local right = forward:Cross(up)
    if right.Magnitude < 1e-4 then right = Vector3.new(0, 0, 1) end
    right = right.Unit
    local trueForward = up:Cross(right).Unit
    moveTo(CFrame.fromMatrix(pos, right, up, -trueForward))

    if curX <= END_X then
        conn:Disconnect()
    end
end)
