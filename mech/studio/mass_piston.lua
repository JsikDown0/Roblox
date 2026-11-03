--[[ mass_piston.lua — 양산형 정강이 피스톤 구동 (2026-11-03, 클라우드 작성 · Studio 미검증)

모델 쪽(mech/code/mass/mass_leg_r4.py):
  PistonCylL  부모 LowerLegL  위 고정점 T (무릎판 밑)
  PistonRodL  부모 FootL      아래 고정점 B (발 혀 위 귀)
  (R 도 같음)
Studio 템플릿에서 준비할 것:
  1) Motor6D "PistonCylJointL": Part0 = LowerLegL, Part1 = PistonCylL, C0/C1 = 고정점 T(회전 없음)
     Motor6D "PistonRodJointL": Part0 = FootL,     Part1 = PistonRodL, C0/C1 = 고정점 B(회전 없음)
     (모터 이름을 파트 이름과 다르게 — FindFirstChild(이름, true) 가 파트를 먼저 잡지 않게)
  2) Attachment "PistonTopL" 을 LowerLegL 의 T 에, "PistonBotL" 을 FootL 의 B 에 (R 도)
  3) 피스톤 파트: Massless = true, CanCollide = false, CanQuery = false
쓰는 법: 애니메이션이 관절 Transform 을 다 쓴 뒤(같은 RenderStepped 맨 끝, 또는 그보다 늦은 우선순위)에
  MassPiston.update(mech) 를 부른다. MechClient 의 JOINTS 목록에 피스톤 모터를 넣지 않는다(덮어쓰지 않게).
원리: 실린더는 B 를, 로드는 T 를 바라보도록 Motor6D.Transform 을 매 프레임 설정 → 발이 까딱이면 로드가 실린더에 들어갔다 나옴.
  쉬는 자세의 방향을 처음 한 번 기억해 두고, 지금 방향으로 돌리는 최소 회전만 쓴다(메시 축 방향과 무관).
]]

local MassPiston = {}
local rest = setmetatable({}, { __mode = "k" }) -- [Motor6D] = 쉬는 자세 방향(관절 좌표)

local function find(mech, name)
	return mech:FindFirstChild(name, true)
end

local function fromTo(a: Vector3, b: Vector3): CFrame
	local d = a:Dot(b)
	if d > 0.99999 then
		return CFrame.identity
	end
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then -- 정반대(일어나지 않아야 함)
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(d, -1, 1)))
end

-- motor: 돌릴 Motor6D · selfAtt: 이 모터 쪽 고정점 · targetAtt: 바라볼 고정점
local function aimMotor(motor: Motor6D, selfAtt: Attachment, targetAtt: Attachment)
	local joint = motor.Part0.CFrame * motor.C0 -- Transform 적용 전 관절 좌표
	local dir = joint:VectorToObjectSpace(targetAtt.WorldPosition - selfAtt.WorldPosition)
	if dir.Magnitude < 1e-4 then
		return
	end
	dir = dir.Unit
	local r = rest[motor]
	if not r then
		-- 처음 부를 때를 쉬는 자세로 본다(스폰 직후, 애니 시작 전에 MassPiston.init 을 부르는 게 가장 정확)
		rest[motor] = dir
		r = dir
	end
	motor.Transform = fromTo(r, dir)
end

function MassPiston.init(mech)
	-- 스폰 직후(모든 Transform 이 0 일 때) 한 번: 쉬는 자세 방향 기록
	for _, s in ipairs({ "L", "R" }) do
		local cyl, rod = find(mech, "PistonCylJoint" .. s), find(mech, "PistonRodJoint" .. s)
		local top, bot = find(mech, "PistonTop" .. s), find(mech, "PistonBot" .. s)
		if cyl and rod and top and bot then
			cyl.Transform = CFrame.identity
			rod.Transform = CFrame.identity
			rest[cyl] = nil
			rest[rod] = nil
			aimMotor(cyl, top, bot)
			aimMotor(rod, bot, top)
		end
	end
end

function MassPiston.update(mech)
	for _, s in ipairs({ "L", "R" }) do
		local cyl, rod = find(mech, "PistonCylJoint" .. s), find(mech, "PistonRodJoint" .. s)
		local top, bot = find(mech, "PistonTop" .. s), find(mech, "PistonBot" .. s)
		if cyl and rod and top and bot and cyl:IsA("Motor6D") and rod:IsA("Motor6D") then
			aimMotor(cyl, top, bot)
			aimMotor(rod, bot, top)
		end
	end
end

return MassPiston
