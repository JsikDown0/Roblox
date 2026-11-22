-- Gas Grenade — 던져진 발사체에서 실행되는 효과 스크립트
-- (Server.lua가 cloneAndEnable로 활성화)
--
-- 흐름:
--   1) 첫 지면/벽 충돌 시 즉시 고정 (구르기/튕김 제거)
--   2) 1초 후 본체 투명화
--   3) 다시 1초 후: SmokeWall 생성 + Fuse 사운드
--      - 에미터를 wall 본체에 직접 부착 (attachment 분산 X)
--      - Shape=Box + ShapeStyle=Volume 으로 벽 전체 볼륨에서 균일 spawn
--      - 모든 에미터 즉시 ON
--      - t=EMIT_DURATION 시점에 동시 OFF (균일 페이드)
--   4) FADE_TAIL 추가 대기 후 SmokeWall + 본체 destroy
--
-- 데미지 효과는 의도적으로 없음 (시야 차단 전용 도구).
-- SmokeWall은 서버에서 만들어지지만, 러너 클라이언트에서는 SmokeWallFilter LocalScript가
-- Transparency를 조정해 비대칭 가시성(러너=흐릿 / 태거=짙음) 구현.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PickupConfig      = require(ReplicatedStorage:WaitForChild("PickupConfig"))

local Object = script.Parent

-- ─ SmokeWall 파라미터 ──────────────────────────────────
local WALL_THICKNESS   = 6      -- X 두께 (런 방향, 얇게)
local WALL_HEIGHT      = 35     -- Y 높이 (트리 위로 솟아 시야 차단)
local EMIT_DURATION    = 10     -- 벽 활성 총 시간 (초)
local FADE_TAIL        = 5      -- 모든 에미터 OFF 후 잔여 입자 소멸 + destroy 대기
local RATE_MULTIPLIER  = 15     -- 원본 에미터 Rate 에 곱할 배수. 벽 볼륨이 크니 보상 필요.
                                -- 너무 sparse 하면 ↑, 너무 dense (성능 부담) 하면 ↓

-- ─ 충돌 시 고정 ────────────────────────────────────────
local landed = false
Object.Touched:Connect(function(hit)
	if landed then return end
	if not hit or not hit.Parent then return end
	local model = hit:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return end
	landed = true
	Object.AssemblyLinearVelocity = Vector3.zero
	Object.AssemblyAngularVelocity = Vector3.zero
	Object.Anchored = true
	Object.CanCollide = false
end)

-- ─ SmokeWall 생성 ─────────────────────────────────────
-- 벽 본체(BasePart)에 에미터를 직접 부착. Box+Volume 으로 균일 분포.
local function spawnSmokeWall()
	local landingPos = Object.Position
	local geo      = PickupConfig.GetGeometry()
	local width    = geo.zWidth
	local centerZ  = geo.zCenter

	-- 벽 본체 (보이지 않음, 입자 spawn 영역 정의용)
	local wall = Instance.new("Part")
	wall.Name         = "SmokeWall"
	wall.Size         = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, width)
	wall.Position     = Vector3.new(landingPos.X, landingPos.Y + WALL_HEIGHT / 2, centerZ)
	wall.Transparency = 1
	wall.Anchored     = true
	wall.CanCollide   = false
	wall.CastShadow   = false
	wall.Parent       = workspace

	-- 원본 Smoke1/2/3 에미터를 wall 에 직접 복제.
	-- Box+Volume 으로 벽 전체 볼륨에서 입자 무작위 spawn → 끝/가운데 밀도 격차 사라짐.
	local allEmitters = {}
	for _, emitterName in ipairs({"Smoke1", "Smoke2", "Smoke3"}) do
		local original = Object:FindFirstChild(emitterName)
		if original and original:IsA("ParticleEmitter") then
			local clone = original:Clone()

			-- 벽 볼륨 전체 균일 분포
			pcall(function()
				clone.Shape      = Enum.ParticleEmitterShape.Box
				clone.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			end)

			-- 큰 볼륨 보상: Rate 스케일업
			clone.Rate = clone.Rate * RATE_MULTIPLIER

			clone.Enabled = true
			clone.Parent  = wall
			table.insert(allEmitters, clone)
		end
	end

	-- SYNC OFF: 모든 에미터 t=EMIT_DURATION 시점에 일제히 OFF → 균일 페이드
	task.delay(EMIT_DURATION, function()
		if not wall.Parent then return end
		for _, em in ipairs(allEmitters) do
			em.Enabled = false
		end
	end)

	-- 잔여 입자 페이드 + destroy
	task.delay(EMIT_DURATION + FADE_TAIL, function()
		if wall and wall.Parent then wall:Destroy() end
	end)
end

local function Explode()
	wait(2)
	Object.Fuse:Play()
	spawnSmokeWall()
	wait(EMIT_DURATION)
	Object.Fuse:Stop()
	wait(FADE_TAIL)
	if Object and Object.Parent then Object:Destroy() end
end

local function boom()
	wait(1)
	Object.Transparency = 1
	Explode()
end

boom()
