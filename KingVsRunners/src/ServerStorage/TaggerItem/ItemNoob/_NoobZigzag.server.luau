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
-- 🎯 [2026-09-01] 진폭 제한. 스폰 Z 기준 ±이 값에서 방향을 반전한다.
--   [왜] 원래는 산/벽에 닿을 때만 반전해서, 언덕 폭(245)을 통째로 왕복했다.
--     봇은 표적 러너의 Z 에 맞춰 스폰하는데(오차 ±12), SIDE_SPEED 80 이면
--     0.15초 만에 그 오차 범위를 벗어난다 — 939 stud 주행 중 조준이 유효한 건 7 stud, 0.7%다.
--     결국 "조준한 굴리기"가 아니라 "맵을 순찰하는 무작위 오브젝트"였다.
--     실측: normal 2판 연속 스폰 12회 / 9회 모두 명중 0.
--   [값 선정] 16 → 28 → 70 (2026-09-01, 2차 상향).
--     ⚠️ ±16 은 반전 주기 0.4초라 "지그재그"가 아니라 좌우로 떠는 것처럼 보였다.
--       ±28 로 0.7초, ±70 이면 1.75초 — 궤도가 확실히 읽힌다.
--     ±70 이면 커버 폭 140 + 히트박스 60 = 실효 200. 언덕 폭 245 의 약 82% 다.
--   ⚠️ 이 값은 이제 "회피 가능한 위협"의 상한 근처다. ±100 을 넘으면 언덕을 통째로
--     덮어 회피 판단 자체가 사라진다(= 굴리기가 아니라 전체 판정기가 된다).
--   ⚠️ 진폭은 양날이다. 넓힐수록 '아무나' 맞을 확률은 오르지만, 봇이 조준한
--     표적(오차 ±12)에서 멀어지는 시간이 길어져 '노린 대상'을 맞출 확률은 떨어진다.
--     ±70 은 조준 오차의 6배라 사실상 조준이 무의미해졌다 — 지대 장악형 무기가 됐다.
--   ⚠️ SIDE_SPEED 는 그대로 둔다. 진폭이 묶여 있으면 빠른 좌우 이동이
--     "궤도를 읽기 어렵다"는 이 아이템의 정체성으로 남는다.
local ZIGZAG_AMPLITUDE = 70

-- ── 시작 상태 ──────────────────────────────────
local startPos = core.Position
local curX = startPos.X
local curZ = startPos.Z
local zDir = (math.random() < 0.5) and 1 or -1   -- 시작 좌우 방향 랜덤
local lastY = startPos.Y

-- 피벗(코어 중심)에서 모델 바닥까지 거리 → 이만큼 띄워야 땅에 안 박히고 선다
-- ⚠️ [버그수정 2026-09-01] bbSize.Y/2 는 '바운딩박스 중심→바닥'이지 '코어→바닥'이 아니다.
--   코어(HumanoidRootPart)는 몸 중앙이 아니라 위쪽에 있어 둘이 다르다.
--   실측: 코어→바닥 44.3 vs bbSize.Y/2 36.9 → 7.4 stud 만큼 땅에 파묻혔다.
--   원래 크기(24.6)일 땐 오차가 2.5 라 눈에 안 띄었는데, 3배 스케일에서 드러났다.
--   ⚠️ 스케일에 비례해 커지는 오차다. 모델 크기를 바꿔도 안 깨지도록 실측값으로 바꾼다.
local bbCF, bbSize = model:GetBoundingBox()
local BOTTOM_OFFSET = core.Position.Y - (bbCF.Position.Y - bbSize.Y / 2)

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

-- 🛡️ [2026-09-02] 우든 실드에 막히면 잠시 멈춘다.
--   [증상] 뉴비가 방패를 완전히 무시하고 지나갔다(실측 12:19 판 — 방패 설치 상태로
--     내구도가 그대로 깎였다). 굴리기·쓰나미는 막히는데 뉴비만 예외였다.
--   [원인] 방패의 Touched 경로는 '닿은 파트의 CollisionGroup == TaggerItems' 를 본다.
--     그런데 뉴비는 벽·산과 충돌해야 해서 의도적으로 Default 그룹이다
--     (ItemSpawnHandler:1714). 게다가 이 스크립트는 매 프레임 CFrame 을 직접 쓰므로
--     방패 디텍터와 마찬가지로 사실상 Anchored 다 — Touched 가 아예 발생하지 않는다
--     (톡스박스가 같은 이유로 이 경로를 못 쓴다: WoodShieldManager:125 주석).
--   [해결] 표준 형태를 따른다 — 이동하면서 매 프레임 _G.WoodShieldBlockAt 을 직접 부른다.
--     쓰나미·에너지볼·창·톡스박스와 같은 방식이다.
--   ⚠️ 막혀도 '소멸'이 아니라 '정지'다. 굴리기류는 튕겨나가지만 뉴비는 CFrame 주행이라
--     속도를 되돌릴 대상이 없다. 대신 멈췄다 재개하는 쪽이 요청된 동작이다.
--   ⚠️ 방패는 한 번 막으면 소모된다(s.blocked). 그래서 같은 방패에 두 번 걸리지 않고,
--     스턴이 끝난 뒤 다시 전진하면 그 자리를 통과한다.
local SHIELD_STUN = 1.5     -- 방패에 막혔을 때 멈추는 시간(초)
local stunUntil = 0

local conn
conn = RunService.Heartbeat:Connect(function(dt)
    if not core.Parent or not model.Parent then
        conn:Disconnect()
        return
    end

    -- 🛡️ 정지 중이면 이동을 건너뛴다. 위치는 그대로 유지된다(CFrame 을 안 건드리므로).
    if os.clock() < stunUntil then return end

    -- 🛡️ 방패 검사. travelDir 은 전진 방향(-X) — 방패 정면으로 들어올 때만 막힌다.
    if _G.WoodShieldBlockAt then
        local hit = _G.WoodShieldBlockAt(core.Position, Vector3.new(-1, 0, 0))
        if hit then
            stunUntil = os.clock() + SHIELD_STUN
            return
        end
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

    -- 🎯 진폭 제한: 스폰 Z 에서 ±ZIGZAG_AMPLITUDE 를 넘으면 되돌린다.
    --   ⚠️ 벽 반전(위)보다 뒤에 둔다. 벽이 진폭보다 가까우면 벽 쪽이 먼저 이겨야
    --     산을 뚫지 않는다 — 두 반전이 같은 프레임에 겹쳐도 결과가 안전한 순서다.
    local zOff = curZ - startPos.Z
    if math.abs(zOff) > ZIGZAG_AMPLITUDE then
        curZ = startPos.Z + (zOff > 0 and ZIGZAG_AMPLITUDE or -ZIGZAG_AMPLITUDE)
        zDir = -zDir
    end

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
