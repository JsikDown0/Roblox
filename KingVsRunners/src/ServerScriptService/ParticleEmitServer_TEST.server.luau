local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local emitEvent = ReplicatedStorage:WaitForChild("EmitParticlesEvent")

-- 플레이어 입장 후 3초 뒤 clock effect_test에 Emit 발사
Players.PlayerAdded:Connect(function(player)
    task.wait(3)
    local target = workspace:FindFirstChild("clock effect_test")
    if target then
        emitEvent:FireClient(player, target)
        print("✅ [Server] EmitParticlesEvent 발사 →", player.Name)
    else
        warn("clock effect_test 없음")
    end
end)
