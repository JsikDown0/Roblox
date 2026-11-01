-- PilotJetpackServer (Script, ServerScriptService) — 10-29 조종사 제트팩: 캐릭터마다 붙이고, 부스트 켬/끔을 받아 불꽃을 켠다(서버가 켜야 모두에게 보임)
-- 게이지·이속은 클라(PilotJetpackClient)가 셈 — 시험장 이동용. 서버는 불꽃·소리만
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Proto = RS:WaitForChild("MechProto")
local Remotes = Proto:WaitForChild("Remotes")
local SM = require(Proto:WaitForChild("SoundManager"))
local JP = require(script.Parent:WaitForChild("PilotJetpack"))

local jetOf = {}   -- player → 그 사람 몸의 제트팩(메카를 타서 몸이 보관돼도 끌 수 있게 Character 대신 이걸 씀)

local function onCharacter(player, char)
	-- 메카도 player.Character 가 된다(MechServer board) → 몸 제트팩 불꽃은 끄고 메카엔 안 붙임
	if char:GetAttribute("IsMech") then
		JP.setFlames(jetOf[player], false)
		return
	end
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		local name = (hum.RigType == Enum.HumanoidRigType.R15) and "UpperTorso" or "Torso"
		if not char:WaitForChild(name, 10) then return end
		if player.Character ~= char then return end   -- 기다리는 사이 다른 몸으로 바뀜
		local jp = JP.attach(char)
		if jp then
			JP.setFlames(jp, false)
			jetOf[player] = jp
		end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	if player.Character then onCharacter(player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerRemoving:Connect(function(p) jetOf[p] = nil end)

Remotes:WaitForChild("PilotJet").OnServerEvent:Connect(function(player, on)
	on = (on == true)
	local jp = jetOf[player]
	if not (jp and jp.Parent) then return end
	if on and jp.Parent ~= player.Character then return end   -- 켜는 건 걸어 다니는 몸일 때만(메카 탑승 중 X)
	if (jp:GetAttribute("On") == true) == on then return end
	JP.setFlames(jp, on)
	if on then SM.play("JetIgnite", jp.PrimaryPart) end
end)
