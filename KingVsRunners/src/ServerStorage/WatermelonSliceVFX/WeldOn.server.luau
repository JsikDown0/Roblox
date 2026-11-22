-- WeldOn: aligns the watermelon's own Handle to the push tool grip point,
-- scales the slice, welds everything to the push Handle, and hides the glove.
-- Runs when this template is cloned onto a push tool Handle (vfxAttachment path).
local model = script.Parent
local pushHandle = model.Parent
if not (pushHandle and pushHandle:IsA("BasePart")) then return end

local tool = pushHandle.Parent
local grip = (tool and tool:IsA("Tool")) and tool.Grip or CFrame.new()

-- watermelon's own Handle part = grip anchor
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

-- target: place the watermelon Handle at the hand's grip point (+ tuning)
local target = pushHandle.CFrame * grip * CFrame.new(off) * rotCF

-- pass 1: record each part's offset relative to the watermelon Handle
local rels = {}
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		rels[p] = wHandle.CFrame:ToObjectSpace(p.CFrame)
	end
end

-- pass 2: scale, reposition onto the grip, and weld
for _, p in ipairs(model:GetChildren()) do
	if p:IsA("BasePart") then
		local rel = rels[p]
		local scaledRel = CFrame.new(rel.Position * S) * (rel - rel.Position)
		p.CFrame = target * scaledRel
		if p ~= wHandle then
			p.Size = p.Size * S
		end
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = pushHandle
		wc.Part1 = p
		wc.Parent = p
	end
end

-- hide the glove and the watermelon's grip anchor
pushHandle.Transparency = 1
for _, c in ipairs(pushHandle:GetChildren()) do
	if c:IsA("BasePart") then
		c.Transparency = 1
	end
end
wHandle.Transparency = 1
