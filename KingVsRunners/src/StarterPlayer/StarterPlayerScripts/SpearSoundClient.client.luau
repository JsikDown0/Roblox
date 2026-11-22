-- SpearSoundClient: 스피어 투척 사운드
-- 투척자(태거)는 2D로 반드시 들리게, 그 외(러너/관전자)는 큰 범위 3D로(긴박감).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("SpearSound")

local SOUND_ID     = "rbxassetid://109290309233384"
local SOUND_VOL    = 1.5
local ROLLOFF_MIN  = 40
local ROLLOFF_MAX  = 700   -- 러너가 멀리서도 듣도록 (긴박감)

remote.OnClientEvent:Connect(function(position, throwerUserId)
	if player.UserId == throwerUserId then
		-- 태거(투척자): 2D 비위치 사운드 → 거리·감쇠 무관하게 반드시 들림
		local snd = Instance.new("Sound")
		snd.SoundId = SOUND_ID
		snd.Volume = SOUND_VOL
		snd.Parent = SoundService
		snd:Play()
		Debris:AddItem(snd, 5)
	elseif typeof(position) == "Vector3" then
		-- 러너/관전자: 발사 지점에서 3D 위치 사운드 (큰 범위)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.CFrame = CFrame.new(position)
		part.Parent = workspace
		local snd = Instance.new("Sound")
		snd.SoundId = SOUND_ID
		snd.Volume = SOUND_VOL
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = ROLLOFF_MIN
		snd.RollOffMaxDistance = ROLLOFF_MAX
		snd.Parent = part
		snd:Play()
		Debris:AddItem(part, 5)
	end
end)
