--[[
	Based on the bear trap created by TheDrakCarlos. I removed the need to click it to reset. 
	Instead it autoresets so it can be used as an automated trap
--]]	
	
debounce = true
local trap = script.Parent.Parent

function onTouched(part)
	local player = part.Parent:findFirstChild("Humanoid")
	if (player ~= nil and debounce == true) then --If the part is a player then
		if script.Parent.Captured.Value == false then
			debounce = false
			player.Health = player.Health - player.Health/10 --Take 10% of the player's health away
			part.Parent["LeftFoot"].Anchored = true --Anchor their legs
			part.Parent["RightFoot"].Anchored = true
			trap.Open.Transparency = 1 --Close the trap
			trap.Close.Transparency = 0
			script.Parent.Bang:Play() --Play audios
			script.Parent.Ow:Play()
			wait(0.5)
			part.Parent.HumanoidRootPart.Anchored = true --Anchor their torso so they don't flail around
			script.Parent.Captured.Value = true
			wait(3) --Wait 3 seconds
			script.Parent.Parent.Open.Transparency = 0 --Open the trap
			script.Parent.Parent.Close.Transparency = 1
			part.Parent["RightFoot"].Anchored = false --Free the player
			part.Parent["LeftFoot"].Anchored = false
			player.Jump = true --Make sure the player isn't glitched
			part.Parent.HumanoidRootPart.Anchored = false
			debounce = true
			wait(2) --Wait 2 seconds
			script.Parent.Captured.Value = false
		end
	end
end

script.Parent.Touched:connect(onTouched)	
