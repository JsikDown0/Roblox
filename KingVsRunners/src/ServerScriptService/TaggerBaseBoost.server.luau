-- taggerbase 위 태거 아이템에 약한 지속 가속 (map1 + map2)
local workspace = game:GetService("Workspace")

local X_BOOST = -15  -- 약한 지속 가속 (안전장치용)

local function onTouch(hit)
    if not hit:IsA("BasePart") then return end

    local ok, groupName = pcall(function()
        return hit.CollisionGroup
    end)
    if not ok or groupName ~= "TaggerItems" then return end

    local vel = hit.AssemblyLinearVelocity
    if vel.X > X_BOOST then
        hit.AssemblyLinearVelocity = Vector3.new(X_BOOST, vel.Y, vel.Z)
    end
end

local function connectBase(base)
    if base and base:IsA("BasePart") then
        base.Touched:Connect(onTouch)
        print("✅ TaggerBaseBoost 연결:", base:GetFullName(), "(X:", X_BOOST, ")")
    end
end

local map1 = workspace:WaitForChild("map1")
local map2 = workspace:WaitForChild("map2")
connectBase(map1:FindFirstChild("taggerbase"))    -- map1
connectBase(map2:FindFirstChild("taggerbase2"))   -- map2

print("✅ TaggerBaseBoost 활성화! (map1 + map2)")
