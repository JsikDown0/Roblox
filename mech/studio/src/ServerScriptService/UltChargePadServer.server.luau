-- UltChargePadServer (Script, ServerScriptService) — 10-30 궁극기 시험용 발판
-- 유저 10-30 18:16 "바닥에 궁극기 충전 패드 하나 깔아줘. 밟으면 궁극기가 99% 차는 패드야"
-- MechTestRange.UltChargePad 위에 선 기체(태그 Mech)의 UltGauge 를 CFG.Ult.Max 의 99% 로(이미 그 이상이면 그대로)
-- 감지 = MechServer 피해 발판(DamagePad)과 같은 0.5초 박스 검사(Touched 아님)
-- 기체 찾기 = 조상을 올라가며 태그 Mech 확인. FindFirstAncestorOfClass("Model") 은 Workspace(Model 하위 클래스)에서도 참이라 안 씀
-- 궁극기 쓰는 동안은 안 채움(MechDamage.addUlt 와 같은 조건 — 쓰자마자 다시 99% 가 되지 않게)
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local CFG = require(RS:WaitForChild("MechProto"):WaitForChild("MechConfig"))
local pad = workspace:WaitForChild("MechTestRange"):WaitForChild("UltChargePad")
local FILL = 0.99
local function mechOf(part)
	local p = part
	while p and p ~= workspace do
		if CollectionService:HasTag(p, "Mech") then return p end
		p = p.Parent
	end
	return nil
end
local op = OverlapParams.new()
while true do
	task.wait(0.5)
	local seen = {}
	for _, part in ipairs(workspace:GetPartBoundsInBox(pad.CFrame + Vector3.new(0, 4, 0), Vector3.new(pad.Size.X, 8, pad.Size.Z), op)) do
		local m = mechOf(part)
		if m and not seen[m] then
			seen[m] = true
			local h = m:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and not (CFG.ultPhase(m) or CFG.trapPhase(m) or CFG.leapPhase(m) or CFG.chargePhase(m)) then
				local want = math.floor(CFG.Ult.Max * FILL)
				if (m:GetAttribute("UltGauge") or 0) < want then m:SetAttribute("UltGauge", want) end
			end
		end
	end
end
