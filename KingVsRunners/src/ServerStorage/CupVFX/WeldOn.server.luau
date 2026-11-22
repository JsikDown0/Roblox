-- WeldOn: welds the coconut parts onto the speed potion Handle and hides the bottle.
-- Runs when this template is cloned onto a potion Handle (skin apply path).
local model = script.Parent
local handle = model.Parent
if not (handle and handle:IsA("BasePart")) then return end

-- body part (largest, tagged at build time)
local body
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") and p:GetAttribute("IsBody") then
		body = p
		break
	end
end
if not body then return end

local off = model:GetAttribute("LocalOffset") or Vector3.new(0, 0.6, 0)
local lr = model:GetAttribute("LocalRot") or Vector3.new(0, 0, 0)
local target = handle.CFrame * CFrame.new(off) * CFrame.Angles(math.rad(lr.X), math.rad(lr.Y), math.rad(lr.Z))

-- pass 1: record offsets relative to body
local rels = {}
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		rels[p] = body.CFrame:ToObjectSpace(p.CFrame)
	end
end

-- pass 2: reposition onto the handle and weld
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		p.CFrame = target * rels[p]
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

-- hide the bottle (potion Handle + its welded children)
handle.Transparency = 1
for _, c in ipairs(handle:GetChildren()) do
	if c:IsA("BasePart") then
		c.Transparency = 1
	end
end
