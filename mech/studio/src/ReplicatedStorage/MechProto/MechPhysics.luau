-- MechPhysics: 기체 물리 안전장치(2026-10-25 13:26). 조종 클라(내 기체)와 MechEnemy(서버 적 기체)가 매 프레임 부른다.
-- 계기: 유저 영상 "부스트 → 빔사벨로 적에 부딪히면 공중으로 급상승".
-- 원인 [추측 — 플레이 재현은 못 함, MCP 가 플레이에 안 붙음]: 수평 속도 제약(LinearVelocity Plane, MaxForce = 무한 —
--   대시·지속 부스트 "BoostHold"·공중 관성 "AirCarry"·근접 내딛기 "MeleeLunge"·적 AI 의 push)이 상대 몸통(HRP 6×6×4 —
--   기체에서 유일한 충돌 파트)을 계속 밀면, 물리가 겹침을 풀 때 접촉면이 조금만 기울어도 무한한 힘의 위쪽 성분이 그대로 솟구치는 힘이 된다.
--   (같은 꼴: 로블록스 "fling" — 무한 힘으로 미는 몸이 다른 몸에 닿으면 날아감)
-- 두 겹(원인이 딴 데 있어도 결과를 보장하는 쪽 — "제외 목록보다 결과 보장"):
--   ① clipPush: 다른 기체 몸통에 닿을 만큼(CFG.BodyBlockDist) 가까우면 수평 속도 제약에서 그쪽으로 향하는 성분을 지우고(옆·뒤는 그대로),
--      그쪽으로 밀려던 동안은 힘도 유한(질량 × CFG.BodyBlockAccel, 중력보다 약함)으로(뒤·옆으로 빠지는 회피는 원래 힘) → 상대를 밀어붙이지도, 버티며 튕기지도 않는다
--   ② capRise: 위로 오르는 속도 상한(점프로 오르는 중 CFG.RiseCapJump, 아니면 CFG.RiseCap)
-- 속도 제약의 "원래 원하는 속도"는 속성 Want(Vector2). 매 프레임 속도를 바꾸는 쪽(setBoostLV)은 M.setWant 로 같이 넣고,
--   한 번 만들고 마는 쪽(대시·내딛기·적 push)은 여기서 처음 볼 때의 PlaneVelocity 를 Want 로 적어 둔다.
local CS = game:GetService("CollectionService")
local CFG = require(script.Parent:WaitForChild("MechConfig"))
local M = {}

function M.setWant(lv, v2)
	lv:SetAttribute("Want", v2)
	lv.PlaneVelocity = v2
end

-- model = 내 기체, root = 그 HRP
function M.clipPush(model, root)
	local normals = nil   -- 닿아 있는 기체 쪽 수평 방향들(필요할 때 한 번만 모음)
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("LinearVelocity") and c.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane then
			if not normals then
				normals = {}
				for _, o in ipairs(CS:GetTagged("Mech")) do
					if o ~= model and o.Parent then
						local r = o:FindFirstChild("HumanoidRootPart")
						if r then
							local d = r.Position - root.Position
							local flat = Vector3.new(d.X, 0, d.Z)
							local dist = flat.Magnitude
							if math.abs(d.Y) < (r.Size.Y + root.Size.Y) / 2 + 1 and dist < CFG.BodyBlockDist and dist > 0.01 then
								table.insert(normals, flat / dist)
							end
						end
					end
				end
			end
			local want = c:GetAttribute("Want")
			if typeof(want) ~= "Vector2" then want = c.PlaneVelocity; c:SetAttribute("Want", want) end
			local base = c:GetAttribute("BaseMaxForce")
			if base == nil then base = c.MaxForce; c:SetAttribute("BaseMaxForce", base) end
			local v = Vector3.new(want.X, 0, want.Y)   -- PrimaryTangentAxis = X, SecondaryTangentAxis = Z
			local pushing = false
			for _, n in ipairs(normals) do
				local along = v:Dot(n)
				if along > 0.5 then v -= n * along; pushing = true end
			end
			local out = Vector2.new(v.X, v.Z)
			if (c.PlaneVelocity - out).Magnitude > 1e-3 then c.PlaneVelocity = out end
			-- 힘을 줄이는 건 "상대 쪽으로 밀려던" 때만. 닿은 채 뒤·옆으로 빠지는 회피(대시)는 원래 힘 그대로 — 근접에서 못 빠져나가면 안 됨
			local f = pushing and math.min(base, root.AssemblyMass * CFG.BodyBlockAccel) or base
			if c.MaxForce ~= f then c.MaxForce = f end
		end
	end
end

function M.capRise(root, cap)
	local v = root.AssemblyLinearVelocity
	if v.Y > cap then root.AssemblyLinearVelocity = Vector3.new(v.X, cap, v.Z) end
end

return M
