-- PickupSoundPreload — 픽업 열림 사운드를 입장 시 미리 로드 (첫 재생 지연 방지)
local ContentProvider   = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("PickupConfig"))

task.spawn(function()
	local temp = {}
	for _, id in ipairs({ Config.SOUND_OPEN_NORMAL, Config.SOUND_OPEN_RARE }) do
		if id and id ~= "" then
			local s = Instance.new("Sound")
			s.SoundId = id
			temp[#temp+1] = s
		end
	end
	pcall(function() ContentProvider:PreloadAsync(temp) end)
	for _, s in ipairs(temp) do s:Destroy() end
end)
