local part = script.Parent
local RunService = game:GetService("RunService")
local SPEED = 0.222  -- 약 4.5초/바퀴
local SAT = 0.7      -- 채도
RunService.Heartbeat:Connect(function()
    local hue = (tick() * SPEED) % 1
    part.Color = Color3.fromHSV(hue, SAT, 1)
end)
