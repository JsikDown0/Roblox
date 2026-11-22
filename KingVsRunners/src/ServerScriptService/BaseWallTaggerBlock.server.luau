-- Base Wall 태거 차단 (움직임만 막기)
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

-- Base Wall 찾기
local map1 = workspace:WaitForChild("map1")
local baseWall = map1:FindFirstChild("Base Wall", true)

if not baseWall then
    warn("Base Wall을 찾을 수 없습니다!")
    return
end

print("✅ Base Wall 태거 차단 시스템 시작")

-- Base Wall에 닿으면
baseWall.Touched:Connect(function(hit)
    -- 플레이어인지 확인
    local humanoid = hit.Parent:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local player = Players:GetPlayerFromCharacter(hit.Parent)
    if not player then return end
    
    -- 태거인지 확인
    local role = player:GetAttribute("Role")
    if role == "Tagger" then
        -- HumanoidRootPart 찾기
        local rootPart = hit.Parent:FindFirstChild("HumanoidRootPart")
        if rootPart then
            -- 현재 속도 가져오기
            local velocity = rootPart.AssemblyLinearVelocity
            
            -- Base Wall 반대 방향으로 밀어내기
            local pushDirection = (rootPart.Position - baseWall.Position).Unit
            rootPart.AssemblyLinearVelocity = pushDirection * 20
            
            print("🚫 태거", player.Name, "Base Wall 통과 차단!")
        end
    end
end)

print("✅ Base Wall 태거 차단 활성화!")
