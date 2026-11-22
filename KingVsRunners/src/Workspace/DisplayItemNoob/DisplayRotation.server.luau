local RunService = game:GetService("RunService")
local model = script.Parent

RunService.Heartbeat:Connect(function(dt)
    if model.PrimaryPart then
        model:SetPrimaryPartCFrame(
            model.PrimaryPart.CFrame * CFrame.Angles(0, math.rad(60) * dt, 0)
        )
    end
end)
