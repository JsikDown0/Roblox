-- RainbowNoob: 모든 신체 파트 색을 무지개로 순환 (RainbowStone/Spear와 동일 방식)
local RunService = game:GetService("RunService")

local model = script.Parent
local SPEED = 0.222  -- 약 4.5초/바퀴 (다른 무지개 스킨과 동일)
local SAT   = 0.7

-- 색을 바꿀 신체 파트 수집 (투명 코어/투명 파트 제외)
local parts = {}
for _, d in ipairs(model:GetDescendants()) do
    if d:IsA("BasePart") and d.Name ~= "_CollisionCore" and d.Transparency < 1 then
        table.insert(parts, d)
    end
end

RunService.Heartbeat:Connect(function()
    local hue = (tick() * SPEED) % 1
    local col = Color3.fromHSV(hue, SAT, 1)
    for _, p in ipairs(parts) do
        p.Color = col
    end
end)
