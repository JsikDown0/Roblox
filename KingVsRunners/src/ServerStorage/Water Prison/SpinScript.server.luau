-- Water Prison 팽이 회전 스크립트 (MeshPart만 회전)
local RunService = game:GetService("RunService")

local model = script.Parent
local SPIN_SPEED = 1.2  -- rad/s (빠르게 하려면 올리기, 느리게 하려면 줄이기)

local sphere = model:FindFirstChild("main sphere")
if not sphere then
    warn("main sphere를 찾을 수 없습니다.")
    return
end

local center = sphere.Position  -- 회전 중심점

-- MeshPart만 수집
local meshParts = {}
local initialRel = {}
local centerCF = CFrame.new(center)

for _, part in ipairs(model:GetDescendants()) do
    if part:IsA("MeshPart") then
        part.Anchored = true
        table.insert(meshParts, part)
        initialRel[part] = centerCF:Inverse() * part.CFrame
    end
end

-- Heartbeat으로 MeshPart만 Y축 회전
local angle = 0
RunService.Heartbeat:Connect(function(dt)
    angle += SPIN_SPEED * dt
    local rotCF = CFrame.new(center) * CFrame.Angles(0, angle, 0)
    for _, part in ipairs(meshParts) do
        if part and part.Parent then
            part.CFrame = rotCF * initialRel[part]
        end
    end
end)
