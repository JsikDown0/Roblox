-- WeldOn: aligns the noodle's Handle to the weapon grip point, scales it,
-- welds it to the weapon Handle, and hides the original weapon visual.
-- Runs when this template is cloned onto a weapon Handle (skin apply path).
local model = script.Parent
local weaponHandle = model.Parent
if not (weaponHandle and weaponHandle:IsA("BasePart")) then return end

local tool = weaponHandle.Parent
local grip = (tool and tool:IsA("Tool")) and tool.Grip or CFrame.new()

-- the noodle's own Handle part = grip anchor
local wHandle
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") and p.Name == "Handle" then
		wHandle = p
		break
	end
end
if not wHandle then return end

local S = model:GetAttribute("Scale") or 1
local off = model:GetAttribute("LocalOffset") or Vector3.new(0, 0, 0)
local rot = model:GetAttribute("LocalRot") or Vector3.new(0, 0, 0)
local rotCF = CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
local target = weaponHandle.CFrame * grip * CFrame.new(off) * rotCF

local rels = {}
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		rels[p] = wHandle.CFrame:ToObjectSpace(p.CFrame)
	end
end

for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		local rel = rels[p]
		local scaledRel = CFrame.new(rel.Position * S) * (rel - rel.Position)
		p.CFrame = target * scaledRel
		p.Size = p.Size * S
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = weaponHandle
		wc.Part1 = p
		wc.Parent = p
	end
end

-- hide the original weapon (Handle mesh + its child meshes)
weaponHandle.Transparency = 1
for _, c in ipairs(weaponHandle:GetChildren()) do
	if c:IsA("BasePart") then
		c.Transparency = 1
	end
end
