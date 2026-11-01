-- PilotJetpack (ModuleScript, ServerScriptService) — 10-29 조종사 제트팩: 붙이기 · 불꽃 켜고 끄기
-- 유저 10-29 23:55 "내 캐릭터에 제트팩 좀 달아줘. 나중에 비상 사출 같은 거랑 연계할 수도 있고 테스트할 때 이속이 빨라지면 좋겠어.
--   시프트 누르면 게이지 소모하면서 부스트 기능이 있어야 해"
-- ■ 견본 = ServerStorage.PilotJetpack (Model, PrimaryPart = JetBody, 속성 PilotJetpack = true). 불꽃 = JetBody 안 Attachment Exhaust* 의 ParticleEmitter "Flame"
-- ■ 붙이기 = "끌려오게" 말고 "직접 놓고" 묶는다(프로젝트 원칙): 먼저 PivotTo 로 등 뒤 자리에 놓고 → 파트끼리 WeldConstraint → 몸통과는 Weld(C0 고정)
--   Weld 의 C0 가 자리를 정하므로 붙인 뒤 몸이 움직여도 어긋나지 않는다
-- ■ 정체 판별은 속성(PilotJetpack)으로. 메카(속성 IsMech)에는 안 붙인다 — MechServer 가 탈 때 player.Character = 메카로 바꿔 CharacterAdded 가 메카로도 온다
-- ■ 비상 사출(나중): 사출된 몸에 이 모듈 attach + setFlames 를 그대로 쓰면 됨(게이지는 클라 PilotJetpackClient 가 셈)
local ServerStorage = game:GetService("ServerStorage")

local M = {}
M.TEMPLATE = "PilotJetpack"

function M.torsoOf(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then return char:FindFirstChild("UpperTorso") end
	return char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

function M.find(char)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("PilotJetpack") then return c end
	end
	return nil
end

-- 등 뒤 자리(몸통 틀): 몸통 뒷면에 JetBody 앞면이 0.02 띄워 닿게, 높이는 몸통 가운데
--   (0.1 위로 두면 기본 R15 에서 JetBody 위 앞 모서리가 머리와 겹침 [에디트 GetPartsInPart] → 0)
function M.offset(torso, body)
	return CFrame.new(0, 0, torso.Size.Z / 2 + body.Size.Z / 2 + 0.02)
end

function M.attach(char)
	if not char or char:GetAttribute("IsMech") then return nil end
	local have = M.find(char)
	if have then return have end   -- 메카에서 내리면 같은 몸이 다시 Character 가 됨 → 두 개 붙지 않게
	local torso = M.torsoOf(char)
	local tpl = ServerStorage:FindFirstChild(M.TEMPLATE)
	if not (torso and tpl) then return nil end
	local jp = tpl:Clone()
	local body = jp.PrimaryPart
	local off = M.offset(torso, body)
	jp:PivotTo(torso.CFrame * off)                 -- ① 먼저 그 자리에 놓고
	for _, p in ipairs(jp:GetDescendants()) do      -- ② 그 자리에서 묶는다
		if p:IsA("BasePart") and p ~= body then
			local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = p; w.Parent = p
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "JetWeld"; weld.Part0 = torso; weld.Part1 = body; weld.C0 = off; weld.C1 = CFrame.new()
	weld.Parent = body
	jp.Parent = char
	return jp
end

function M.setFlames(jp, on)
	if not jp then return end
	for _, e in ipairs(jp:GetDescendants()) do
		if e:IsA("ParticleEmitter") and e.Name == "Flame" then e.Enabled = on end
	end
	jp:SetAttribute("On", on or nil)
end

return M
