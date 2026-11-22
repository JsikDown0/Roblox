-- Wood Shield Client
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

local placeEvent = ReplicatedStorage:WaitForChild("WoodShieldPlace")
local clearEvent = ReplicatedStorage:WaitForChild("WoodShieldClear")

-- ⚠️ [범위 재조정 2026-08-23] 예전 값은 W 55 / L 28 로 좌우가 앞뒤의 2배였다.
--    러너는 앞으로 달리는데 설치 가능 거리가 28 뿐이라, 뛰면서 놓으면 그 안쪽은
--    이미 지나쳐버려 "지나온 길에 설치되는" 체감이 났다. 앞뒤를 대폭 늘리고
--    좌우는 오히려 줄여, 진행 방향으로 길게 뻗은 영역으로 성격을 바꾼다.
--    ⚠️ 실제 판정은 isInRect(RANGE_L/RANGE_W) 와 '서버의' MAX_PLACE_DIST 두 곳이다.
--       서버 값보다 RANGE_L 이 크면 클라 청사진은 초록인데 서버가 거부하는
--       불일치가 생긴다 → 서버 MAX_PLACE_DIST 도 반드시 같이 올릴 것.
local RANGE_W        = 44    -- 직사각형 가로 (55 → 34 → 44)
local RANGE_L        = 70    -- 직사각형 세로 (28 → 70, lookDir 방향 대폭 확대)

-- 🛡️ 방패 확대 배율.
--   [이유] 원본 방패는 좌우 4.27 인데 막아야 할 통나무가 20, 배럴이 26 이라
--          5~6배 작았다. 정면으로 굴러와도 방패 옆으로 지나가 버린다.
--   ⚠️ 이 값은 서버(use)의 SHIELD_SCALE 과 반드시 같아야 한다. 다르면 청사진으로 본
--      크기와 실제 설치된 방패 크기가 어긋난다.
local SHIELD_SCALE   = 1.5

-- 지면 위 띄움. ⚠️ 방패를 키우면 피벗(중심) 기준으로 아래로도 커져 지면에 묻힌다.
--   커진 높이의 절반만큼 더 올려야 밑변이 원래 자리에 온다.
--   원본 높이 4.84 → 1.5배 시 7.26, 증가분의 절반 ≈ 1.21
local Y_LIFT         = 3.5 + (4.84 * (SHIELD_SCALE - 1) * 0.5)
local BASE_ROT_Z = math.rad(30)   -- Z축 기울기 30°

local tool           = script.Parent
local blueprintModel = nil
local ringPart       = nil
local isActive       = false
local renderConn     = nil

local COLOR_OK  = Color3.fromRGB(100, 200, 255)
local COLOR_BAD = Color3.fromRGB(255, 80, 80)

-- ── 범위 직사각형 파트 생성 ───────────────────────────────────
local function createRing()
	local r = Instance.new("Part")
	r.Name         = "_ShieldRing"
	r.Size         = Vector3.new(RANGE_W, 0.12, RANGE_L)
	r.Color        = COLOR_OK
	r.Material     = Enum.Material.Neon
	r.Transparency = 0.58
	r.CanCollide   = false
	r.CanQuery     = false
	r.Anchored     = true
	r.CastShadow   = false
	r.Parent       = workspace.CurrentCamera
	return r
end

-- ── 청사진 모델 생성 (범위 원 제외) ─────────────────────────────
local function createBlueprint()
	local original = game:GetService("ReplicatedStorage")
		:WaitForChild("ItemTemplates"):WaitForChild("wood Shield", 10)
	if not original then warn("wood Shield 원본 없음") return nil end

	local bp = original:Clone()
	bp.Name = "_WoodShieldBlueprint"

	-- 🛡️ 청사진도 실제 설치물과 같은 배율로 키운다.
	-- ⚠️ ScaleTo 는 Model 전용이고 피벗 기준으로 확대한다. Parent 설정 전에 호출해도 된다.
	if bp:IsA("Model") then
		pcall(function() bp:ScaleTo(SHIELD_SCALE) end)
	end

	for _, part in ipairs(bp:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored       = true
			part.CanCollide     = false
			part.CanQuery       = false
			part.CastShadow     = false
			part.CollisionGroup = "Default"
			-- Union(방패 본체)만 파란색, 프레임 Parts는 원래 색 유지
			if part:IsA("UnionOperation") then
				part.Color        = COLOR_OK
				part.Transparency = 0.45
			else
				part.Transparency = 0.35  -- 프레임은 약간만 투명
			end
		end
	end

	bp.Parent = workspace
	return bp
end

local function destroyAll()
	if blueprintModel then blueprintModel:Destroy(); blueprintModel = nil end
	if ringPart       then ringPart:Destroy();       ringPart = nil       end
end

local function isInRect(groundPos)
	local lookDir  = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	local rightDir = Vector3.new(lookDir.Z, 0, -lookDir.X)  -- lookDir의 오른쪽 수직
	local toTarget = Vector3.new(groundPos.X - hrp.Position.X, 0, groundPos.Z - hrp.Position.Z)
	local fwd  = toTarget:Dot(lookDir)   -- 앞뒤 거리
	local side = toTarget:Dot(rightDir)  -- 좌우 거리
	-- 직사각형 범위: 앞 0~RANGE_L, 좌우 ±RANGE_W/2
	return fwd >= 0 and fwd <= RANGE_L and math.abs(side) <= RANGE_W * 0.5
end

-- 아이템이 굴러오는 방향(태거 스폰 → 플레이어)을 항상 사용
local function getItemFlowDir()
	-- 현재 맵의 taggerspawn 위치 탐색
	for _, mapFolder in ipairs(workspace:GetChildren()) do
		if mapFolder.Name:lower():find("map") then
			local ts = mapFolder:FindFirstChild("taggerspawn")
			if ts then
				local dir = Vector3.new(
					hrp.Position.X - ts.Position.X,
					0,
					hrp.Position.Z - ts.Position.Z
				)
				if dir.Magnitude > 0.1 then return dir.Unit end
			end
		end
	end
	-- fallback: 플레이어 LookVector
	return Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
end

local function calcPlaceCFrame(groundPos)
	local flowDir   = getItemFlowDir()   -- 항상 아이템 진행 방향으로 고정
	local liftedPos = groundPos + Vector3.new(0, Y_LIFT, 0)
	local yAngle    = math.atan2(-flowDir.X, -flowDir.Z)
	return CFrame.new(liftedPos) * CFrame.Angles(0, yAngle, 0) * CFrame.Angles(0, 0, BASE_ROT_Z)
end

-- ── 매 프레임 업데이트 ────────────────────────────────────────
local function updateBlueprint()
	if not isActive then return end

	local groundPos = mouse.Hit.Position
	local inRange   = isInRect(groundPos)
	local color    = inRange and COLOR_OK or COLOR_BAD

	-- 청사진 업데이트
	if blueprintModel then
		for _, part in ipairs(blueprintModel:GetDescendants()) do
			if part:IsA("BasePart") then part.Color = color end
		end
		pcall(function() blueprintModel:PivotTo(calcPlaceCFrame(groundPos)) end)
	end

	-- 범위 원: 플레이어 앞쪽으로 오프셋, 지형 Y + 0.15로 살짝 띄우기
		if ringPart then
			local lookDir = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
			local cx = hrp.Position.X + lookDir.X * (RANGE_L * 0.5)
			local cz = hrp.Position.Z + lookDir.Z * (RANGE_L * 0.5)

			-- 링 중심 독립 레이캐스트 → 항상 지형 높이
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = {character}
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local rayResult = workspace:Raycast(
				Vector3.new(cx, hrp.Position.Y + 80, cz),
				Vector3.new(0, -160, 0),
				rayParams
			)
			local groundY       = rayResult and (rayResult.Position.Y + 0.12) or (hrp.Position.Y - 3)
			local terrainNormal = rayResult and rayResult.Normal or Vector3.new(0, 1, 0)

			-- world Y → terrainNormal 기울기
			local worldY = Vector3.new(0, 1, 0)
			local cross  = worldY:Cross(terrainNormal)
			local tiltCF
			if cross.Magnitude > 0.001 then
				tiltCF = CFrame.fromAxisAngle(cross.Unit, math.acos(math.clamp(worldY:Dot(terrainNormal), -1, 1)))
			else
				tiltCF = CFrame.new()
			end

			-- lookDir 방향으로 직사각형 정렬
			local yAngle = math.atan2(lookDir.X, lookDir.Z)
			ringPart.CFrame = CFrame.new(cx, groundY, cz) * tiltCF * CFrame.Angles(0, yAngle, 0)
			ringPart.Color  = color
		end
end

-- ── Tool 이벤트 ───────────────────────────────────────────────
tool.Equipped:Connect(function()
	isActive       = true
	ringPart       = createRing()
	blueprintModel = createBlueprint()
	renderConn     = RunService.RenderStepped:Connect(updateBlueprint)
end)

tool.Unequipped:Connect(function()
	isActive = false
	destroyAll()
	if renderConn then renderConn:Disconnect(); renderConn = nil end
end)

tool.Activated:Connect(function()
	if not isActive then return end
	local groundPos = mouse.Hit.Position
	if not isInRect(groundPos) then return end

	placeEvent:FireServer(calcPlaceCFrame(groundPos))
	isActive = false
	destroyAll()
	if renderConn then renderConn:Disconnect(); renderConn = nil end
end)

clearEvent.OnClientEvent:Connect(function()
	destroyAll()
	isActive = false
end)
