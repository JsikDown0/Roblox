-- Second Wall 접촉 시 X축 부스트 (map1 + map2)
local workspace = game:GetService("Workspace")

local X_BOOST = -80  -- 언덕 방향으로 밀기

local function setupWallBoost(wall)
    wall.Touched:Connect(function(hit)
        if not hit:IsA("BasePart") then return end

        -- TaggerItems 그룹인지 확인
        local ok, groupName = pcall(function()
            return hit.CollisionGroup
        end)
        if not ok or groupName ~= "TaggerItems" then return end

        -- X축 부스트 적용 (기존 Y, Z 속도 유지)
        local vel = hit.AssemblyLinearVelocity
        if vel.X > X_BOOST then
            hit.AssemblyLinearVelocity = Vector3.new(X_BOOST, vel.Y, vel.Z)
        end
    end)
    print("✅ 벽 부스트 연결:", wall:GetFullName())
end

-- map1 + map2 의 "Second Wall" 전부 찾아 연결
for _, mapName in ipairs({"map1", "map2"}) do
    local mp = workspace:WaitForChild(mapName)
    for _, child in ipairs(mp:GetDescendants()) do
        if child:IsA("BasePart") and child.Name:find("Second Wall") then
            setupWallBoost(child)
        end
    end
end

print("✅ WallBoostSystem 활성화! (map1 + map2)")
