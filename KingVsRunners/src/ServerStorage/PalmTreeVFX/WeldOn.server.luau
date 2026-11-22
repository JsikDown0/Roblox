-- WeldOn: scales the palm tree, stands it on the flag Handle, welds it, and hides the flag.
-- Runs when this template is cloned onto a RevivalFlag Handle (skin apply path).
local model = script.Parent
local handle = model.Parent
if not (handle and handle:IsA("BasePart")) then return end

-- body = trunk (tagged at build time)
local body
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") and p:GetAttribute("IsBody") then
		body = p
		break
	end
end
if not body then return end

local S = model:GetAttribute("Scale") or 1
local off = model:GetAttribute("LocalOffset") or Vector3.new(0, 0, 0)
local rot = model:GetAttribute("LocalRot") or Vector3.new(0, 0, 0)
local rotCF = CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
local target = handle.CFrame * CFrame.new(off) * rotCF

-- pass 1: record offsets relative to trunk
local rels = {}
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		rels[p] = body.CFrame:ToObjectSpace(p.CFrame)
	end
end

-- pass 2: scale, reposition, weld
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
		wc.Part0 = handle
		wc.Part1 = p
		wc.Parent = p
	end
end

-- hide the flag (pole handle + cloth = BasePart children of the tool)
local tool = handle.Parent
if tool then
	for _, c in ipairs(tool:GetChildren()) do
		if c:IsA("BasePart") then
			c.Transparency = 1
		end
	end
end
