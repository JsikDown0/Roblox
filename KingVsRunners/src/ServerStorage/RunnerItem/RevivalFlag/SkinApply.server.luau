-- SkinApply: when this potion is given to a player, apply their equipped "Speed Potion" skin.
-- Self-contained so the RoundSystem / LoadoutManager give paths stay untouched.
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local tool = script.Parent

local applied = false

local function getOwner()
	local p = tool.Parent
	if not p then return nil end
	local plr = Players:GetPlayerFromCharacter(p)  -- equipped in character
	if plr then return plr end
	if p:IsA("Backpack") then return p.Parent end  -- in backpack
	return nil
end

local function applySkin()
	if applied then return end
	local player = getOwner()
	if not player then return end
	if not (_G.getEquippedSkin and _G.getSwordSkinData) then return end

	local itemName = tool.Name
	local skinName = _G.getEquippedSkin(player, itemName)
	if not skinName then applied = true; return end          -- default look
	local skinData = _G.getSwordSkinData(itemName, skinName)
	if not skinData then applied = true; return end
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end

	-- particle color + drink sound (read by SpeedPotionClient)
	if skinData.potionFxColor then
		local c = skinData.potionFxColor
		tool:SetAttribute("PotionFxColor", Color3.fromRGB(c[1], c[2], c[3]))
	end
	if skinData.potionSoundId then
		tool:SetAttribute("PotionSoundId", skinData.potionSoundId)
	end

	-- form swap: coconut model welded to handle + bottle hidden (via the template's WeldOn)
	if skinData.vfxAttachment then
		local vfx = ServerStorage:FindFirstChild(skinData.vfxAttachment)
		if vfx then
			local oldv = handle:FindFirstChild(skinData.vfxAttachment)
			if oldv then oldv:Destroy() end
			vfx:Clone().Parent = handle
		end
	end

	applied = true
end

task.defer(applySkin)
tool.AncestryChanged:Connect(applySkin)
