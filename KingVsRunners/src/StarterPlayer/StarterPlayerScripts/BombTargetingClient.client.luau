-- BombTargetingClient: TNT 폭탄용 탑뷰 카메라 + 타겟 클릭 처리
-- 흐름: 서버에서 BombEnterTargeting 받으면 → 카메라 탑뷰로 → 클릭 시 raycast → target 전송 → 카메라 복귀

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- ─── Tunables ────────────────────────────────────────────────
-- Tactical view: 사용자가 캡처한 Studio 카메라 시점 적용
-- 플레이어 베이스 쪽에서 +X 방향(태거 베이스)을 비스듬히 내려보는 시야
-- map1 실측 시점. 다른 맵은 태거 기준점(taggerspawn) 오프셋만큼 평행이동 (맵 구조 동일: 태거=고X / 러너=저X)
local TACTICAL_VIEW_POS_M1 = Vector3.new(738.1, 234.9, -671.4)   -- map1 실측 카메라 위치
local TACTICAL_REF_M1      = Vector3.new(767.5, 137.5, -679.5)   -- map1 taggerspawn = 오프셋 기준점
local TACTICAL_VIEW_LOOK   = Vector3.new(-0.797, -0.604, -0.001)
local CAMERA_TWEEN_TIME    = 1.0    -- 카메라 전환 시간 (초)
local CROSSHAIR_SIZE       = 60     -- 화면 십자선 크기 (픽셀)
-- 🔴 착탄 반경 미리보기 — 서버 BombSystem.WARNING_RADIUS 와 반드시 일치시킬 것.
-- (불일치하면 "보이는 범위와 실제 범위가 다른" 상태가 되어 조준이 거짓말을 한다)
local PREVIEW_RADIUS       = 75
local PREVIEW_COLOR        = Color3.fromRGB(255, 45, 45)
local PREVIEW_TRANSPARENCY = 0.72

-- ─── RemoteEvents ────────────────────────────────────────────
local bombEnterEvent  = ReplicatedStorage:WaitForChild("BombEnterTargeting")
local bombTargetEvent = ReplicatedStorage:WaitForChild("BombTargetConfirmed")
local bombCancelEvent = ReplicatedStorage:WaitForChild("BombCancelTargeting")

-- ─── 상태 ────────────────────────────────────────────────────
local isTargeting = false
local originalCameraType = nil
local originalCameraCF = nil
local crosshairGui = nil
local clickConn = nil
local cancelConn = nil
local fireWallSavedState = nil  -- 불꽃벽 UI 원본 위치/AnchorPoint 백업
local previewCircle = nil       -- 🔴 착탄 반경 미리보기 (탑뷰 청사진)
local previewConn = nil

-- ─────────────────────────────────────────────────────────────
-- 착탄 반경 미리보기: 마우스가 가리키는 지면에 실제 폭발 반경 원을 그린다.
-- tnt 모델 청사진은 "얼마나 넓게 터지는지"를 전혀 알려주지 않아 조준 정보로 쓸모가 없다.
-- 지면 법선에 맞춰 눕히므로 경사면에서도 실제 피해 범위와 같은 모양으로 보인다.
-- ─────────────────────────────────────────────────────────────
local function cframeForCylinder(centerPos, normal)
	local up = normal.Unit
	local arb = math.abs(up.Y) < 0.99 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	local right = up:Cross(arb).Unit
	local fwd = up:Cross(right).Unit
	return CFrame.fromMatrix(centerPos, up, right, fwd)
end

-- 🧱 바리케이드·성문은 1단계 조준을 막지 않는다.
-- ⚠️ [2026-08-25] 바리케이드 판정 파트는 Transparency 1 인데 CanQuery=true 라
--    보이지 않으면서 레이를 막았다. 성문(Gatehouse 585파트)도 마찬가지.
--    태거가 언덕을 조준하려는데 벽에 걸려 소환 위치가 성문 앞에 찍혔다.
-- ⚠️ 원칙: 바리케이드는 1단계 플레이에 아무 영향도 주면 안 된다.
local _wallCache = nil
local function getWallParts()
	if _wallCache then return _wallCache end
	_wallCache = {}
	for _, mf in ipairs(workspace:GetChildren()) do
		local bf = mf:FindFirstChild("Barricades")
		if bf then
			_wallCache[#_wallCache + 1] = bf
			for _, seg in ipairs(bf:GetChildren()) do
				local g = seg:GetAttribute("BarricadeGate")
				if g then
					for _, nm in ipairs(string.split(g, ",")) do
						nm = nm:gsub("^%s+", ""):gsub("%s+$", "")
						for _, d in ipairs(mf:GetDescendants()) do
							if d.Name == nm then _wallCache[#_wallCache + 1] = d end
						end
					end
				end
			end
		end
	end
	return _wallCache
end

-- 🎯 태거베이스 위를 관통해 그 너머 지형을 찾는다.
--
-- [왜] 태거가 성 안에서 언덕을 조준하면 레이가 성 내부 구조물
--   (바닥·카펫·map2 castle 파트 등)에 먼저 맞는다.
--   ItemSpawnHandler.isOnTaggerBase 는 X/Z 만 보므로(높이 무시)
--   그 지점은 '소환 금지'로 판정돼 tnt 가 나가지 않았다.
--
-- [왜 제외가 답이 아닌가] 해당 파트들을 Exclude 에 넣으면 바닥이
--   사라져 레이가 그대로 관통하고, result 가 nil 이 되어 역시 실패한다.
--   성 내부 구조물은 맵마다 달라 목록으로 관리하기도 어렵다.
--
-- [해결] 맞은 지점이 베이스 X/Z 범위 안이면, 그 지점 바로 뒤에서
--   레이를 다시 쏜다. 범위 밖 지형이 나올 때까지 반복한다.
local function getBaseParts()
	local list = {}
	for _, mf in ipairs(workspace:GetChildren()) do
		if mf.Name:lower():find("map") then
			for _, d in ipairs(mf:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:lower():match("^taggerbase") then
					list[#list + 1] = d
				end
			end
		end
	end
	return list
end

local function isInBaseXZ(pos)
	for _, bp in ipairs(getBaseParts()) do
		if bp.Parent then
			local lp = bp.CFrame:PointToObjectSpace(pos)
			if math.abs(lp.X) <= bp.Size.X / 2 and math.abs(lp.Z) <= bp.Size.Z / 2 then
				return true
			end
		end
	end
	return false
end

-- ⚠️ 최대 8회까지만 이어 쏜다. 무한 루프 방지.
local function castThroughBase(origin, direction, params)
	local o, remain = origin, direction.Magnitude
	local dir = direction.Unit
	for _ = 1, 8 do
		local r = workspace:Raycast(o, dir * remain, params)
		if not r then return nil end
		if not isInBaseXZ(r.Position) then return r end
		local adv = (r.Position - o).Magnitude + 0.5
		remain = remain - adv
		if remain <= 0 then return nil end
		o = r.Position + dir * 0.5
	end
	return nil
end

local function groundRayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { player.Character }
	if previewCircle then table.insert(list, previewCircle) end
	local bpLocal = workspace:FindFirstChild("Blueprint_local")
	if bpLocal then table.insert(list, bpLocal) end
	local bpServer = workspace:FindFirstChild("Blueprint_" .. player.Name)
	if bpServer then table.insert(list, bpServer) end
	-- 🧱 바리케이드·성문 제외
	for _, w in ipairs(getWallParts()) do table.insert(list, w) end
	-- 🧱 태거 장벽 + 태거베이스 바닥 제외
	-- ⚠️ TaggerWall_* : Transparency 1 + CanQuery true 라 보이지 않으면서 막는다.
	--    map 폴더 직속이 아니라 하위에 있으므로 GetDescendants 로 찾아야 한다.
	-- ⚠️ taggerbase : 성 바닥이 언덕보다 높아, 성 안에서 밖을 조준하면
	--    바닥 가장자리에 레이가 걸린다. 성 안은 어차피 소환 금지 구역이라
	--    (ItemSpawnHandler.isOnTaggerBase) 제외해도 오작동이 없다.
	for _, mf in ipairs(workspace:GetChildren()) do
		if mf.Name:lower():find("map") then
			for _, d in ipairs(mf:GetDescendants()) do
				if d:IsA("BasePart") then
					local nm = d.Name:lower()
					-- ⚠️ taggerbase/taggerspawn 은 제외하지 않는다.
					--    제외하면 바닥이 사라져 레이가 관통하고,
					--    result 가 nil 이 되어 소환 자체가 안 된다.
					--    대신 castThroughBase 가 그 너머를 찾는다.
					if d.CollisionGroup == "TaggerBarrier"
					   or nm:find("taggerwall") then
						table.insert(list, d)
					end
				end
			end
		end
	end
	params.FilterDescendantsInstances = list
	return params
end

local function startPreview()
	if previewCircle then return end
	previewCircle = Instance.new("Part")
	previewCircle.Name = "_BombAimPreview"
	previewCircle.Shape = Enum.PartType.Cylinder
	previewCircle.Size = Vector3.new(0.5, PREVIEW_RADIUS * 2, PREVIEW_RADIUS * 2)
	previewCircle.Material = Enum.Material.Neon
	previewCircle.Color = PREVIEW_COLOR
	previewCircle.Transparency = PREVIEW_TRANSPARENCY
	previewCircle.Anchored = true
	previewCircle.CanCollide = false
	previewCircle.CanQuery = false   -- 자기 자신을 조준하지 않게
	previewCircle.CastShadow = false
	previewCircle.Parent = workspace

	previewConn = RunService.RenderStepped:Connect(function()
		if not isTargeting or not previewCircle then return end
		local camera = workspace.CurrentCamera
		local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local r = castThroughBase(ray.Origin, ray.Direction * 2000, groundRayParams())
		if r then
			previewCircle.Transparency = PREVIEW_TRANSPARENCY
			previewCircle.CFrame = cframeForCylinder(r.Position + r.Normal * 0.3, r.Normal)
		else
			previewCircle.Transparency = 1   -- 지면을 못 잡으면 숨김
		end
	end)
end

local function stopPreview()
	if previewConn then previewConn:Disconnect(); previewConn = nil end
	if previewCircle then previewCircle:Destroy(); previewCircle = nil end
end

-- ─────────────────────────────────────────────────────────────
-- 불꽃벽 카운트다운 UI를 임시로 하단으로 이동 (시야 가리지 않게)
-- 타겟팅 시작 시 호출 → 종료 시 복원
-- ─────────────────────────────────────────────────────────────
local function moveFireWallUIToBottom()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local gui = playerGui:FindFirstChild("FirePressureCountdownGui")
	if not gui then return end
	local frame = gui:FindFirstChildWhichIsA("Frame")
	if not frame then return end
	-- 원본 백업
	fireWallSavedState = {
		frame = frame,
		anchorPoint = frame.AnchorPoint,
		position = frame.Position,
	}
	-- 하단으로 이동
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -120)
end

local function restoreFireWallUI()
	if not fireWallSavedState then return end
	local frame = fireWallSavedState.frame
	if frame and frame.Parent then
		frame.AnchorPoint = fireWallSavedState.anchorPoint
		frame.Position = fireWallSavedState.position
	end
	fireWallSavedState = nil
end

-- 현재 맵(태거가 서 있는 맵) 기준으로 전술 카메라 위치 계산 → map2 등에서도 자기 맵을 비춘다.
-- map1/map2 동시 존재. 캐릭터에 가장 가까운 맵의 태거 기준점으로 오프셋(이름 다름 → 폴백 체인).
local function currentMapTacticalPos()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local anchor = hrp and hrp.Position
	if not anchor then return TACTICAL_VIEW_POS_M1 end
	local bestRef, bestDist
	for _, map in ipairs(workspace:GetChildren()) do
		if map.Name:lower():find("map") then
			local t = map:FindFirstChild("taggerspawn", true) or map:FindFirstChild("taggerspawn2", true)
				or map:FindFirstChild("taggerbase", true) or map:FindFirstChild("taggerbase2", true)
			if t and t:IsA("BasePart") then
				local d = (t.Position - anchor).Magnitude
				if not bestDist or d < bestDist then bestDist = d; bestRef = t.Position end
			end
		end
	end
	if not bestRef then return TACTICAL_VIEW_POS_M1 end
	return TACTICAL_VIEW_POS_M1 + (bestRef - TACTICAL_REF_M1)
end

-- ─────────────────────────────────────────────────────────────
-- Tactical 카메라 전환 (탑뷰 X, 비스듬히 내려보는 전술 시야)
-- ─────────────────────────────────────────────────────────────
local function enterTopView()
	local camera = workspace.CurrentCamera
	originalCameraType = camera.CameraType
	originalCameraCF = camera.CFrame

	-- 카메라를 Scriptable로 전환
	camera.CameraType = Enum.CameraType.Scriptable

	-- Tactical view: 현재 맵 기준 위치에서 정의된 방향으로 응시 (map2 등 대응)
	local tacticalPos = currentMapTacticalPos()
	local lookTarget = tacticalPos + TACTICAL_VIEW_LOOK * 100
	local newCF = CFrame.lookAt(tacticalPos, lookTarget)

	-- 부드러운 전환 트윈
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(CAMERA_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = newCF}
	)
	tween:Play()
end

-- ─────────────────────────────────────────────────────────────
-- 원래 카메라 복귀
-- ─────────────────────────────────────────────────────────────
local function exitTopView()
	local camera = workspace.CurrentCamera
	if originalCameraType then
		camera.CameraType = originalCameraType
	end
	-- CFrame은 안 돌려놓아도 됨 — Custom 모드면 자동으로 캐릭터 따라감
end

-- ─────────────────────────────────────────────────────────────
-- 화면 중앙 십자선 UI (탑뷰 중에만 표시)
-- ─────────────────────────────────────────────────────────────
local function createCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "_BombCrosshair"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player.PlayerGui

	-- 안내 텍스트
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 400, 0, 50)
	label.Position = UDim2.new(0.5, -200, 0, 30)
	label.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.Text = "TNT: click to set target | ESC Cancel"
	label.Parent = gui

	-- 십자선
	local v = Instance.new("Frame")
	v.Size = UDim2.new(0, 2, 0, CROSSHAIR_SIZE)
	v.Position = UDim2.new(0.5, -1, 0.5, -CROSSHAIR_SIZE / 2)
	v.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	v.BorderSizePixel = 0
	v.Parent = gui

	local h = Instance.new("Frame")
	h.Size = UDim2.new(0, CROSSHAIR_SIZE, 0, 2)
	h.Position = UDim2.new(0.5, -CROSSHAIR_SIZE / 2, 0.5, -1)
	h.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	h.BorderSizePixel = 0
	h.Parent = gui

	return gui
end

-- ─────────────────────────────────────────────────────────────
-- 타겟팅 시작
-- ─────────────────────────────────────────────────────────────
local function startTargeting()
	if isTargeting then return end
	isTargeting = true

	enterTopView()
	crosshairGui = createCrosshair()
	moveFireWallUIToBottom()  -- 불꽃벽 UI 임시 하단 이동 (시야 확보)
	-- 태거 청사진 억제 (tnt 청사진이 탑뷰에 재장전돼 조준을 방해하던 문제)
	if _G.TaggerBlueprintSuppress then _G.TaggerBlueprintSuppress(true) end
	startPreview()

	-- 클릭 핸들러
	clickConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if not isTargeting then return end

		-- 카메라가 transition 중일 수도 있음 — 짧은 시간 대기는 자동으로 됨
		local camera = workspace.CurrentCamera
		local mouseX = input.Position.X
		local mouseY = input.Position.Y
		local ray = camera:ScreenPointToRay(mouseX, mouseY)

		-- 청사진/미리보기 원은 반드시 제외 — 이걸 맞으면 착탄점이 엉뚱한 좌표가 된다.
		-- (실제 사고 로그: "🎯 폭격 타겟 확정: (237,46,903) | hit Blueprint_local")
		local params = groundRayParams()

		local result = castThroughBase(ray.Origin, ray.Direction * 2000, params)
		if not result then
			print("⚠️ raycast 미적중")
			return
		end

		-- 유효 바닥 어디든 폭격 가능 (맵 무관). 서버가 사거리/role 검증.

		-- 클릭 위치를 서버로 전송
		print(string.format("🎯 폭격 타겟 확정: (%.0f, %.0f, %.0f) | hit %s",
			result.Position.X, result.Position.Y, result.Position.Z,
			result.Instance and result.Instance.Name or "?"))
		bombTargetEvent:FireServer(result.Position)

		stopTargeting()
	end)

	-- ESC Cancel
	cancelConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape and isTargeting then
			print("❌ 폭격 타겟팅 Cancel")
			bombCancelEvent:FireServer()
			stopTargeting()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- 타겟팅 종료
-- ─────────────────────────────────────────────────────────────
function stopTargeting()
	if not isTargeting then return end
	isTargeting = false

	if clickConn then clickConn:Disconnect(); clickConn = nil end
	if cancelConn then cancelConn:Disconnect(); cancelConn = nil end
	if crosshairGui then crosshairGui:Destroy(); crosshairGui = nil end

	restoreFireWallUI()  -- 불꽃벽 UI 원본 위치 복원
	stopPreview()
	-- ⚠️ 같은 클릭이 TaggerUIScript의 mouse.Button1Down 에도 전달된다.
	--    억제를 즉시 풀면 그 핸들러가 새 스폰 요청을 보내 조준 모드가 다시 열린다(무한 재진입).
	--    → 해제 시각을 남겨 TaggerUIScript가 짧은 유예 동안 클릭을 무시하게 한다.
	_G.BombTargetingEndedAt = os.clock()
	if _G.TaggerBlueprintSuppress then _G.TaggerBlueprintSuppress(false) end
	exitTopView()
end

-- ─── 서버 신호 받기 ─────────────────────────────────────────
bombEnterEvent.OnClientEvent:Connect(function()
	startTargeting()
end)

-- 캐릭터 죽거나 라운드 종료 시 안전 정리
player.CharacterRemoving:Connect(function()
	if isTargeting then stopTargeting() end
end)

print("✅ BombTargetingClient 활성화 (탑뷰 폭격 타겟팅)")
