-- SmokeWallFilter
-- Gas Grenade가 폭발하면 서버가 좌우폭 가득한 SmokeWall(Part) 을 workspace 에 생성함.
-- 모든 클라이언트에 복제되지만, 러너 클라이언트에서는 이 LocalScript 가 ParticleEmitter 의
-- Transparency 를 높여서 흐릿하게만 보이게 함. 태거 클라이언트는 원본 그대로 짙게 보임.
--
-- 핵심 원리: LocalScript 의 instance 변경은 로컬 한정 (네트워크 복제 안 됨).
-- 즉 같은 SmokeWall 이라도 러너 화면엔 흐릿 / 태거 화면엔 짙음.
--
-- 러너에게 완전히 안 보이면 본인 연막 위치/지속을 모르니까, 흐릿한 가이드 정도로 표시.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

-- 러너 시점 투명도 (0 = 불투명 / 1 = 완전 투명)
-- 0.85 = 흐릿한 윤곽 정도. 더 진하게 보이려면 낮춤, 더 흐리게 하려면 높임.
local RUNNER_TRANSPARENCY = 0.85

local function isRunner()
	if localPlayer:GetAttribute("Role") == "Runner" then return true end
	local character = localPlayer.Character
	if character and character:GetAttribute("Role") == "Runner" then return true end
	return false
end

local function dimEmitter(emitter)
	emitter.Transparency = NumberSequence.new(RUNNER_TRANSPARENCY)
end

local function dimEmittersOnWall(wall)
	for _, desc in ipairs(wall:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			dimEmitter(desc)
		end
	end
end

local function handleWall(wall)
	if not wall:IsA("BasePart") then return end
	if wall.Name ~= "SmokeWall" then return end

	-- 러너만 디밍 적용. 태거는 원본 그대로.
	if isRunner() then
		dimEmittersOnWall(wall)
		-- 후속 추가 에미터도 안전망
		wall.DescendantAdded:Connect(function(desc)
			if desc:IsA("ParticleEmitter") and isRunner() then
				dimEmitter(desc)
			end
		end)
	end
end

-- 이미 존재하는 SmokeWall 처리 (LocalScript 가 늦게 로드된 경우 대비)
for _, child in ipairs(Workspace:GetChildren()) do
	handleWall(child)
end

-- 신규 생성 감지
Workspace.ChildAdded:Connect(handleWall)

print("✅ SmokeWallFilter 활성화 (러너 Transparency =", RUNNER_TRANSPARENCY, ")")
