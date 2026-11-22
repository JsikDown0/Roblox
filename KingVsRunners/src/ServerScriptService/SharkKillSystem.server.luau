-- ════════════════════════════════════════════════════════════
-- SharkKillSystem — 러너가 물(SharkKillZone)에 빠지면 Shark가 솟아 즉사
-- ────────────────────────────────────────────────────────────
-- 판정: SharkKillZone 영역(물 표면보다 낮게 설정 — 충분히 잠겨야 발동)에
--        Role=="Runner" 캐릭터의 HumanoidRootPart가 들어오면 발동.
-- 연출: Shark 템플릿(ServerStorage) 복제 → 물 밑에서 솟아오름 + 사운드 → 러너 즉사 → 제거.
-- 안정성: 0.2초 주기 영역 검사(Touched 터널링 방지) + 캐릭터별 디바운스.
-- ════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local SHARK_SOUND = "rbxassetid://139323583518651"
local CHECK_INTERVAL = 0.2
local RISE_HEIGHT = 14       -- 상어가 솟아오르는 높이
local RISE_TIME = 0.35       -- 솟는 데 걸리는 시간
local SHARK_LIFETIME = 2.5   -- 연출 후 상어 제거까지
local FLOOR_SINK = 8         -- 러너가 수면 아래로 잠기는 깊이(존 상단 기준). 클수록 더 잠김

-- ⚠️ SharkKillZone은 맵(map1) 안에 있고 라운드마다 로드/스왑됨. 구버전은 workspace 최상위에서
--    WaitForChild → 영영 못 찾고 여기서 멈췄음(스크립트 전체 사망). 동적 조회로 수정.
local cachedZones = nil
-- 베이스플레이트 제거로 물 밑이 void → 러너가 그대로 추락해 상어 연출이 안 보임.
-- 존 밑에 안 보이는 충돌 바닥을 만들어 러너가 수면 아래 살짝 잠긴 채 멈추게 함. 존의 자식이라 맵과 함께 이동.
local function ensureFloor(zone)
    local floor = zone:FindFirstChild("_SharkFloor")
    if floor then return floor end
    floor = Instance.new("Part")
    floor.Name = "_SharkFloor"
    floor.Anchored = true
    floor.CanCollide = true
    floor.Transparency = 1
    floor.Size = Vector3.new(zone.Size.X, 2, zone.Size.Z)
    local topY = (zone.Position.Y + zone.Size.Y / 2) - FLOOR_SINK  -- 존 상단에서 FLOOR_SINK만큼 내려온 높이
    floor.Position = Vector3.new(zone.Position.X, topY - 1, zone.Position.Z)  -- 두께 2 → 윗면 = topY
    floor.Parent = zone
    return floor
end
-- 복수 존 지원: 이름이 "SharkKillZone"으로 시작하는 모든 파트 (map2는 언덕 양옆 2개 등)
-- 존 파트 속성 KillStyle: nil/"shark"=상어 솟구침(기본) / "quicksand"=개미지옥(가라앉음+모래분출)
local function getZones()
    if cachedZones then
        local alive = true
        for _, z in ipairs(cachedZones) do
            if not z:IsDescendantOf(workspace) then alive = false break end
        end
        if alive and #cachedZones > 0 then return cachedZones end
    end
    cachedZones = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and d.Name:sub(1, 13) == "SharkKillZone" then
            cachedZones[#cachedZones + 1] = d
            if d:GetAttribute("KillStyle") ~= "quicksand" then
                ensureFloor(d)  -- 상어 스타일만 (잠김 연출용 바닥). 개미지옥은 지면이 이미 있음
            end
        end
    end
    return cachedZones
end
local sharkTemplate = ServerStorage:WaitForChild("Shark")

local debounce = {}  -- [character] = true (중복 발동 방지)
-- 모래지옥(quicksand) 유예: 존에 들어와도 GRACE_QUICKSAND초 이상 머물러야 발동.
-- 지나가다 스치는 경우 방지. 물(shark) 스타일은 유예 없이 즉시 발동.
local GRACE_QUICKSAND = 1.0   -- 유예 시간(초)
local graceTimers = {}        -- [character] = { zone = zone, since = os.clock() }

-- 영역 안에 점이 있는지 (회전 없는 박스 가정)
local function inZone(zone, pos)
    local half = zone.Size / 2
    local c = zone.Position
    return math.abs(pos.X - c.X) <= half.X
       and math.abs(pos.Y - c.Y) <= half.Y
       and math.abs(pos.Z - c.Z) <= half.Z
end

local function playSharkSound(atPart)
    local s = Instance.new("Sound")
    s.SoundId = SHARK_SOUND
    s.Volume = 1
    s.RollOffMaxDistance = 200
    s.Parent = atPart
    s:Play()
    Debris:AddItem(s, 5)
end

-- 상어 솟아오르는 연출
local function spawnSharkAt(pos)
    local clone = sharkTemplate:Clone()
    -- 물 아래에서 시작 (90도 회전 적용 — 상어가 세워진 자세로 솟음)
    local ROT = CFrame.Angles(math.rad(90), 0, 0)
    local startPos = Vector3.new(pos.X, pos.Y - RISE_HEIGHT, pos.Z)
    clone:PivotTo(CFrame.new(startPos) * ROT)
    clone.Parent = workspace

    -- 사운드 (몸통 파트에서)
    local body = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
    if body then playSharkSound(body) end

    -- 솟아오르기 (Tween 대신 수동 보간 — PivotTo로 모델 전체 이동)
    task.spawn(function()
        local t0 = os.clock()
        while os.clock() - t0 < RISE_TIME do
            local a = (os.clock() - t0) / RISE_TIME
            local y = startPos.Y + RISE_HEIGHT * a
            clone:PivotTo(CFrame.new(pos.X, y, pos.Z) * ROT)
            RunService.Heartbeat:Wait()
        end
        clone:PivotTo(CFrame.new(pos.X, pos.Y, pos.Z) * ROT)
    end)

    Debris:AddItem(clone, SHARK_LIFETIME)
end

-- 개미지옥(quicksand) 연출: 빙글 돌며 서서히 가라앉음 + 모래 분출 → 완전히 잠기면 사망
local QS_SINK_TIME  = 2.0   -- 가라앉는 시간
local QS_SINK_DEPTH = 7     -- 가라앉는 깊이(stud)
local QS_SOUND      = "rbxassetid://137858693327824"  -- 모래에 빨려드는 SFX (ElevenLabs)
local function quicksandKill(player, char, hum)
    debounce[char] = true
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then if hum and hum.Parent then hum.Health = 0 end return end
    -- 서버가 몸을 제어 (네트워크 소유권 회수 + 물리 무력화 — 클라 스냅백 방지)
    pcall(function() root:SetNetworkOwner(nil) end)
    hum.PlatformStand = true
    root.AssemblyLinearVelocity = Vector3.zero
    local startCF = root.CFrame

    -- 모래 분출 이펙트 (발밑에서 소용돌이치듯)
    local fx = Instance.new("Part")
    fx.Anchored = true fx.CanCollide = false fx.CanQuery = false fx.CanTouch = false
    fx.Transparency = 1
    fx.Size = Vector3.new(6, 1, 6)
    fx.CFrame = CFrame.new(root.Position.X, root.Position.Y - 2.5, root.Position.Z)
    fx.Parent = workspace
    local e = Instance.new("ParticleEmitter")
    e.Texture = "rbxasset://textures/particles/smoke_main.dds"
    e.Color = ColorSequence.new(Color3.fromRGB(216, 196, 156))
    e.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.7, 0.7),
        NumberSequenceKeypoint.new(1, 1),
    })
    e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) })
    e.Lifetime = NumberRange.new(0.8, 1.4)
    e.Speed = NumberRange.new(6, 11)
    e.SpreadAngle = Vector2.new(35, 35)
    e.Rotation = NumberRange.new(-180, 180)
    e.RotSpeed = NumberRange.new(-90, 90)
    e.Rate = 45
    e.Parent = fx
    local snd = Instance.new("Sound")
    snd.SoundId = QS_SOUND
    snd.Volume = 1.6
    snd.PlaybackSpeed = 1.12   -- 클라이맥스를 잠김 시점(2s)에 맞춰 살짝 당김
    snd.RollOffMaxDistance = 180
    snd.Parent = fx
    snd:Play()
    Debris:AddItem(fx, QS_SINK_TIME + 2)

    -- 가라앉기: ease-in(점점 빨라짐) + 빙글 회전 + 살짝 기울어짐
    task.spawn(function()
        local t0 = os.clock()
        while os.clock() - t0 < QS_SINK_TIME do
            if not (root.Parent and hum.Parent) then return end
            local a = (os.clock() - t0) / QS_SINK_TIME
            local ease = a * a
            root.CFrame = startCF
                * CFrame.new(0, -QS_SINK_DEPTH * ease, 0)
                * CFrame.Angles(math.rad(10 * a), math.rad(200 * a), 0)
            RunService.Heartbeat:Wait()
        end
        e.Rate = 0  -- 분출 종료 (잔여 파티클은 자연 소멸)
        if hum and hum.Parent then hum.Health = 0 end
    end)
end

local function killRunner(player, char, hum, zone)
    -- 존 스타일 분기: quicksand(개미지옥) / 기본(상어)
    if zone and zone:GetAttribute("KillStyle") == "quicksand" then
        quicksandKill(player, char, hum)
        return
    end
    debounce[char] = true
    local root = char:FindFirstChild("HumanoidRootPart")
    spawnSharkAt(root and root.Position or char:GetPivot().Position)
    -- 살짝 지연 후 즉사 (상어가 솟는 순간과 맞춤)
    task.delay(0.15, function()
        if hum and hum.Parent then
            hum.Health = 0
        end
    end)
end

-- 메인 감시 루프: Role=="Runner" 캐릭터가 판정 영역에 들어오면 발동
while true do
    local zones = getZones()   -- 맵 안 SharkKillZone* 전부 (없으면 빈 목록)
    for _, player in ipairs(Players:GetPlayers()) do
        if #zones > 0 and player:GetAttribute("Role") == "Runner" then
            local char = player.Character
            if char and not debounce[char] then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and root then
                    -- 캐릭터가 들어와 있는 존 하나 찾기 (여러 존은 겹치지 않음)
                    local insideZone = nil
                    for _, zone in ipairs(zones) do
                        if inZone(zone, root.Position) then
                            insideZone = zone
                            break
                        end
                    end
                    if insideZone then
                        if insideZone:GetAttribute("KillStyle") == "quicksand" then
                            -- 모래지옥: 같은 존에 GRACE_QUICKSAND초 이상 머물러야 발동
                            local t = graceTimers[char]
                            if not t or t.zone ~= insideZone then
                                graceTimers[char] = { zone = insideZone, since = os.clock() }
                            elseif os.clock() - t.since >= GRACE_QUICKSAND then
                                graceTimers[char] = nil
                                killRunner(player, char, hum, insideZone)
                            end
                        else
                            -- 물(shark): 유예 없이 즉시 발동
                            killRunner(player, char, hum, insideZone)
                        end
                    else
                        graceTimers[char] = nil  -- 존 밖으로 나감 → 유예 타이머 리셋
                    end
                end
            end
        end
    end
    -- 죽은 캐릭터 디바운스 정리
    for char in pairs(debounce) do
        if not char.Parent then debounce[char] = nil end
    end
    for char in pairs(graceTimers) do
        if not char.Parent then graceTimers[char] = nil end
    end
    task.wait(CHECK_INTERVAL)
end
