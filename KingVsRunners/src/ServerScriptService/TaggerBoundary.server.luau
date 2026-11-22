-- TaggerBoundary
-- 태거의 이동 영역 제한.
-- 허용 영역: 현재 활성 맵의 taggerbase + ItemSpawnPlate.
--
-- Push back 정책:
--   - taggerbase + ItemSpawnPlate 둘 중 하나라도 inside면 OK
--   - 둘 다 outside일 때 push back 결정:
--     · 직전 inside가 ItemSpawnPlate였으면 → ItemSpawnPlate로 push (계단에서 떨어지는 것 방지)
--     · 직전 inside가 taggerbase였으면 → 자유 (성 가장자리에서 떨어지는 것은 허용)
--
-- 이유:
--   taggerbase는 큰 성/언덕 영역이라 자체적으로 위치적 우위가 분명하지만,
--   ItemSpawnPlate는 좁고 긴 계단 형태라 옆으로 떨어지기 쉬워 별도 보호 필요.
--   두 영역 경계의 미세한 좌표 갭에서 의도치 않은 push back 방지 효과도 있음.

local Players          = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── 상태 ────────────────────────────────────────────────
local currentMap = nil
local activeConnections = {}  -- player -> connection

-- ── 영역 수집 (taggerbase, ItemSpawnPlate 분리) ──────────
local function getZonesForMap(mapFolder)
    if not mapFolder then return nil, nil end
    local taggerbase, itemSpawnPlate = nil, nil
    for _, child in ipairs(mapFolder:GetChildren()) do
        if child:IsA("BasePart") then
            local cname = child.Name:lower()
            if cname:find("taggerbase") then
                taggerbase = child
            elseif cname:find("itemspawnplate") then
                itemSpawnPlate = child
            end
        end
    end
    return taggerbase, itemSpawnPlate
end

-- ── XZ 평면 영역 체크 ────────────────────────────────────
local function isInsideZoneXZ(pos, part)
    if not part then return false end
    local local_pos = part.CFrame:PointToObjectSpace(pos)
    local half = part.Size / 2
    return math.abs(local_pos.X) <= half.X and math.abs(local_pos.Z) <= half.Z
end

-- 점에서 Part의 가장 가까운 표면 점 (XZ만 클램프, Y 유지)
local function getClosestPointXZ(pos, part)
    local local_pos = part.CFrame:PointToObjectSpace(pos)
    local half = part.Size / 2
    local clamped = Vector3.new(
        math.clamp(local_pos.X, -half.X, half.X),
        local_pos.Y,
        math.clamp(local_pos.Z, -half.Z, half.Z)
    )
    return part.CFrame:PointToWorldSpace(clamped)
end

-- ── 모든 활성 boundary 정리 ─────────────────────────────
local function clearAllConnections()
    for _, conn in pairs(activeConnections) do
        if conn then conn:Disconnect() end
    end
    activeConnections = {}
end

-- ── 캐릭터 경계 감시 ──────────────────────────────────
local function setupBoundary(player)
    if activeConnections[player] then
        activeConnections[player]:Disconnect()
        activeConnections[player] = nil
    end

    if not currentMap then
        warn("[TaggerBoundary] currentMap 미설정 - boundary 미적용")
        return
    end

    local character = player.Character
    if not character then return end

    local taggerbase, itemSpawnPlate = getZonesForMap(currentMap)
    if not taggerbase and not itemSpawnPlate then
        warn("[TaggerBoundary] " .. currentMap.Name .. " 에 허용 영역 없음")
        return
    end

    print(string.format("[TaggerBoundary] %s 적용 (맵: %s, taggerbase=%s, itemSpawnPlate=%s)",
        player.Name, currentMap.Name,
        taggerbase and "✓" or "✗",
        itemSpawnPlate and "✓" or "✗"))

    -- 직전 inside 영역 추적: "taggerbase" / "itemspawnplate" / nil
    -- 시작 시 nil → 처음 inside가 될 때 갱신
    local lastInsideZone = nil

    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then conn:Disconnect() return end
        if player:GetAttribute("Role") ~= "Tagger" then conn:Disconnect() return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then conn:Disconnect() return end

        local pos = hrp.Position

        local insideTaggerbase = isInsideZoneXZ(pos, taggerbase)
        local insideItemSpawn  = isInsideZoneXZ(pos, itemSpawnPlate)

        -- 현재 inside면 lastInsideZone 갱신
        if insideTaggerbase then
            lastInsideZone = "taggerbase"
        elseif insideItemSpawn then
            lastInsideZone = "itemspawnplate"
        end

        -- 둘 다 outside일 때만 push back 결정
        if not insideTaggerbase and not insideItemSpawn then
            -- 직전이 ItemSpawnPlate였을 때만 push back 후보
            -- (taggerbase에서 나간 경우는 자유 — 사용자 의도)
            if lastInsideZone == "itemspawnplate" and itemSpawnPlate then
                -- 단, taggerbase에 진입하려는 중이면 통과 허용.
                -- 두 영역의 모양 차이로 둘 다 outside인 작은 영역에 빠질 수 있는데,
                -- taggerbase가 더 가까우면 그쪽으로 가려는 의도이므로 push back 안 함.
                local distToItemSpawn = nil
                local closestItemSpawnPoint = getClosestPointXZ(pos, itemSpawnPlate)
                do
                    local dx = closestItemSpawnPoint.X - pos.X
                    local dz = closestItemSpawnPoint.Z - pos.Z
                    distToItemSpawn = math.sqrt(dx * dx + dz * dz)
                end

                if taggerbase then
                    local closestTaggerbasePoint = getClosestPointXZ(pos, taggerbase)
                    local dx = closestTaggerbasePoint.X - pos.X
                    local dz = closestTaggerbasePoint.Z - pos.Z
                    local distToTaggerbase = math.sqrt(dx * dx + dz * dz)

                    if distToTaggerbase <= distToItemSpawn then
                        -- taggerbase에 더 가까움 → 진입 의도 → 자유
                        return
                    end
                end

                -- ItemSpawnPlate 옆으로 떨어지는 상황 → push back
                local safePoint = closestItemSpawnPoint
                local dx = safePoint.X - pos.X
                local dz = safePoint.Z - pos.Z
                local mag = math.sqrt(dx * dx + dz * dz)
                local pushVec
                if mag > 0.001 then
                    pushVec = Vector3.new(dx / mag * 1.5, 0, dz / mag * 1.5)
                else
                    pushVec = Vector3.zero
                end

                local rotationOnly = hrp.CFrame - hrp.CFrame.Position
                hrp.CFrame = CFrame.new(safePoint + pushVec) * rotationOnly
                local vel = hrp.AssemblyLinearVelocity
                hrp.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
            end
        end
    end)

    activeConnections[player] = conn
end

-- ── 맵 변경 이벤트 ─────────────────────────────────────
local setMapEvent = ReplicatedStorage:WaitForChild("SetCurrentMap", 5)
if setMapEvent and setMapEvent:IsA("BindableEvent") then
    setMapEvent.Event:Connect(function(mapFolder)
        currentMap = mapFolder
        print("[TaggerBoundary] 현재 맵:", mapFolder and mapFolder.Name or "(없음)")
        clearAllConnections()
        for _, player in ipairs(Players:GetPlayers()) do
            if player:GetAttribute("Role") == "Tagger" then
                setupBoundary(player)
            end
        end
    end)
else
    warn("[TaggerBoundary] SetCurrentMap BindableEvent 못 찾음")
end

-- ── 플레이어 Role 변경 감시 ──────────────────────────
local function watchPlayer(player)
    player:GetAttributeChangedSignal("Role"):Connect(function()
        if player:GetAttribute("Role") == "Tagger" then
            task.wait(0.5)
            setupBoundary(player)
        end
    end)
    player.CharacterAdded:Connect(function()
        if player:GetAttribute("Role") == "Tagger" then
            task.wait(0.5)
            setupBoundary(player)
        end
    end)
    player:GetPropertyChangedSignal("Parent"):Connect(function()
        if not player.Parent and activeConnections[player] then
            activeConnections[player]:Disconnect()
            activeConnections[player] = nil
        end
    end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    watchPlayer(player)
    if player:GetAttribute("Role") == "Tagger" then
        setupBoundary(player)
    end
end

print("✅ TaggerBoundary 활성화 (ItemSpawnPlate 진입 후 그 밖으로 떨어지는 것만 차단)")
