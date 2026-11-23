-- VictoryPadsServer (Script, ServerScriptService) — 승리포즈 컷씬 확인용 발판 (2026-10-29 초안)
-- workspace.VictoryPadA / VictoryPadB 를 밟으면(사람 몸이든 탄 기체든) 그 플레이어 화면에서만 컷씬 A / B 재생.
-- 컷씬용 기체 = AeroTemplate 복제본(ReplicatedStorage.VictoryRig) — 화면이 복제해서 씀(서버 기체·판정과 무관).
-- ⚠️ 적용 전 확인: AeroTemplate 실제 위치(TEMPLATE_PATHS), 태그·스크립트가 복제본에 따라오는지.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local TEMPLATE_PATHS = {                                -- 확인 후 하나로 고정
	function() return RS:FindFirstChild("MechProto") and RS.MechProto:FindFirstChild("AeroTemplate") end,
	function() return game:GetService("ServerStorage"):FindFirstChild("AeroTemplate", true) end,
}
local COOLDOWN = 7

local ev = RS:FindFirstChild("VictoryCutscene") or Instance.new("RemoteEvent")
ev.Name = "VictoryCutscene"; ev.Parent = RS

if not RS:FindFirstChild("VictoryRig") then
	local src
	for _, f in ipairs(TEMPLATE_PATHS) do src = f(); if src then break end end
	assert(src, "[Victory] AeroTemplate 를 못 찾음")
	local rig = src:Clone()
	rig.Name = "VictoryRig"
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("Humanoid") then d:Destroy() end
	end
	for _, tag in ipairs(CollectionService:GetTags(rig)) do CollectionService:RemoveTag(rig, tag) end
	rig:SetAttribute("Note", "승리포즈 컷씬 전용 복제본(VictoryPadsServer 가 부팅 때 만듦). 화면이 복제해서 재생 — 게임 기체 아님")
	rig.Parent = RS
end

local last = {}
local function hook(pad, clip)
	pad.Touched:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		local plr = model and Players:GetPlayerFromCharacter(model)
		if not plr then return end
		local now = os.clock()
		if last[plr] and now - last[plr] < COOLDOWN then return end
		last[plr] = now
		ev:FireClient(plr, clip)
	end)
end

for _, pair in ipairs({ { "VictoryPadA", "A" }, { "VictoryPadB", "B" } }) do
	local pad = workspace:WaitForChild(pair[1], 10)
	if pad then hook(pad, pair[2]) else warn("[Victory] 발판 없음", pair[1]) end
end
Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
