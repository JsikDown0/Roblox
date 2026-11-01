-- VictoryPadsServer (Script, ServerScriptService) — 승리포즈 컷씬 확인용 발판 (2026-10-29)
-- MechTestRange.VictoryPadA / VictoryPadB 위에 서면(사람 몸이든 탄 기체든) 그 플레이어 화면에서만 컷씬 A / B 재생.
-- 컷씬용 기체 = ReplicatedStorage.VictoryRig(부팅 때 MechProto.AeroTemplate 복제) — 화면이 복제해서 씀(서버 기체·판정과 무관).
-- 10-29 Studio 반영 때 초안에서 바꾼 것:
--   · 템플릿 경로 = MechProto.AeroTemplate 하나로 고정. ServerStorage 의 AeroTemplate 들은 백업(_…_before_…)이라 잡히면 옛 기체가 나옴
--   · 감지 = MechServer 피해 발판(DamagePad)과 같은 0.5초 박스 검사(Touched 아님)
--   · 플레이어 찾기 = 조상을 올라가며 GetPlayerFromCharacter. FindFirstAncestorOfClass("Model") 은 Workspace(Model 하위 클래스)에서도 참이라 안 씀
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Range = workspace:WaitForChild("MechTestRange")
local COOLDOWN = 7                                            -- 클립 4.6초 + 끝 유지 0.8초보다 길게
local PADS = { { "VictoryPadA", "A" }, { "VictoryPadB", "B" } }

local ev = RS:FindFirstChild("VictoryCutscene") or Instance.new("RemoteEvent")
ev.Name = "VictoryCutscene"; ev.Parent = RS

if not RS:FindFirstChild("VictoryRig") then
	local src = RS:WaitForChild("MechProto"):WaitForChild("AeroTemplate")
	local rig = src:Clone()
	rig.Name = "VictoryRig"
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("Humanoid") then d:Destroy() end
	end
	for _, tag in ipairs(CollectionService:GetTags(rig)) do CollectionService:RemoveTag(rig, tag) end
	rig:SetAttribute("VictoryRig", true)
	rig:SetAttribute("Note", "승리포즈 컷씬 전용 복제본(VictoryPadsServer 가 부팅 때 만듦). 화면이 복제해서 재생 — 게임 기체 아님")
	rig.Parent = RS
end

local function playerOf(part)
	local a = part.Parent
	while a and a ~= workspace do
		local plr = Players:GetPlayerFromCharacter(a)
		if plr then return plr end
		a = a.Parent
	end
	return nil
end

local last = {}
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, pr in ipairs(PADS) do
			local pad = Range:FindFirstChild(pr[1])
			if pad then
				local seen = {}
				for _, part in ipairs(workspace:GetPartBoundsInBox(pad.CFrame + Vector3.new(0, 4, 0), Vector3.new(pad.Size.X, 8, pad.Size.Z))) do
					local plr = playerOf(part)
					if plr and not seen[plr] then
						seen[plr] = true
						local now = os.clock()
						if not last[plr] or now - last[plr] >= COOLDOWN then
							last[plr] = now
							ev:FireClient(plr, pr[2])
						end
					end
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
