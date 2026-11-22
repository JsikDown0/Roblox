-- PickupSystem — Hill 위 아이템 픽업 스폰 시스템
-- 라운드 시작 N초 후 불벽 앞 안전 띠에 무작위 아이템 픽업이 떨어짐.
-- 러너가 E키 0.5초 차징으로 줍는다. 차징 중 무방비 (산데비스탄 i-frame 같은 보호 없음).
-- 불벽이 따라잡은 픽업은 자동 디스폰.

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("PickupConfig"))

-- 라운드 라이프사이클: FirePressureSystem과 동일한 BindableEvent를 공유
local startEvent = ReplicatedStorage:WaitForChild("StartFirePressure")
local stopEvent  = ReplicatedStorage:WaitForChild("StopFirePressure")
local roundEndedEvent = ReplicatedStorage:WaitForChild("RoundEnded")
local rareSkinRewardEvent = ReplicatedStorage:WaitForChild("RareSkinReward")

-- 불벽 시작 X (불벽이 아직 안 만들어졌을 때 fallback)
local FIRE_START_X = -228

-- ════════════ 상태 ════════════
local activePickups = {}  -- { [model] = true }
local pickupFolder  = nil -- Workspace.PickupContainer
local active        = false
local spawnLoopId   = 0   -- 라운드 끝나면 increment해서 이전 루프 무효화

-- ════════════ 불벽 X 위치 추적 ════════════
local function getFireWallX()
	local folder = Workspace:FindFirstChild("FirePressurePillars")
	if folder then
		local pillar = folder:FindFirstChild("FirePillar_1")
		if pillar and pillar:IsA("BasePart") then
			return pillar.Position.X
		end
	end
	return FIRE_START_X
end

-- ════════════ 픽업 모델 생성 ════════════
-- ServerStorage 의 Item Chest 템플릿을 클론해서 사용. 흰 트레일 구체 2개가 시각 중심 주변을 직교 궤도로 돔.
local function createPickupModel(itemName, position)
	-- 템플릿 검증
	local template = ServerStorage:FindFirstChild(Config.CHEST_TEMPLATE_NAME)
	if not template then
		warn("[PickupSystem] ServerStorage." .. Config.CHEST_TEMPLATE_NAME .. " 템플릿 없음")
		return nil, nil, nil
	end

	local model = template:Clone()
	model.Name  = "Pickup_" .. itemName

	local root       = model:FindFirstChild("HumanoidRootPart")
	local woodTop    = model:FindFirstChild("WoodTop")
	local woodBottom = model:FindFirstChild("WoodBottom")
	if not (root and woodTop and woodBottom) then
		warn("[PickupSystem] 체스트 구조 불완전 (HumanoidRootPart/WoodTop/WoodBottom 누락)")
		model:Destroy()
		return nil, nil, nil
	end

	-- 앵커링: 전부 anchored 유지 (Motor6D 무시) + 충돌 끔
	-- root 기준 delta 이동으로 모델 전체를 한꺼번에 옮김 (조립체 유지)
	local oldRootPos = root.Position
	local delta = position - oldRootPos
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored   = true
			desc.CanCollide = false
			desc.CFrame     = desc.CFrame + delta
		end
	end
	root.CastShadow   = false  -- root는 안 보이는 파트
	root.Transparency = 1

	model.PrimaryPart = root

	-- 뚜껑 힌지 정보 사전 계산 (Triggered 핸들러에서 CFrame 트윈으로 사용)
	-- WoodTop 안에 MetalTop, KeyHole 같은 별도 anchored Part들이 있어서, 전부 같이 회전시켜야 함
	local lidParts = { woodTop }
	for _, desc in ipairs(woodTop:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(lidParts, desc)
		end
	end

	-- 각 lid part 초기 CFrame 기록 (회전 계산 기준)
	local lidInitialCFrames = {}
	for _, p in ipairs(lidParts) do
		lidInitialCFrames[p] = p.CFrame
	end

	local hingeInfo = {
		pivotCFrame       = woodBottom.CFrame * CFrame.new(0, woodBottom.Size.Y / 2, woodBottom.Size.Z / 2),
		lidParts          = lidParts,
		lidInitialCFrames = lidInitialCFrames,
	}

	-- 체스트 시각 중심 (root는 캐릭터 가슴 높이쯤에 있어서 시각 중심 아님)
	local visualCenter = (woodBottom.Position + woodTop.Position) / 2

	-- ════════════ 체스트 내부 오브 (전리품 placeholder) ════════════
	-- 뚜껑 열렸을 때 안에 뭔가 들어있는 것처럼 보이게 흰 발광 구 1개
	local innerOrb = Instance.new("Part")
	innerOrb.Name       = "InnerOrb"
	innerOrb.Shape      = Enum.PartType.Ball
	innerOrb.Size       = Vector3.new(Config.INNER_ORB_SIZE, Config.INNER_ORB_SIZE, Config.INNER_ORB_SIZE)
	innerOrb.Anchored   = true
	innerOrb.CanCollide = false
	innerOrb.CastShadow = false
	innerOrb.Material   = Enum.Material.Neon
	innerOrb.Color      = Config.INNER_ORB_COLOR
	innerOrb.Position   = woodBottom.Position + Vector3.new(0, woodBottom.Size.Y * Config.INNER_ORB_Y_RATIO, 0)
	innerOrb.Parent     = model

	-- 작은 라이트 추가 (오브 안쪽 빛남)
	local innerLight = Instance.new("PointLight")
	innerLight.Brightness = 1.5
	innerLight.Color      = Color3.fromRGB(255, 255, 255)
	innerLight.Range      = 8
	innerLight.Parent     = innerOrb

	-- 포인트 라이트 (체스트 주변 발광, 범위 좁게 — 빛기둥 없는 대신 근접 빛으로 위치 식별)
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Color      = Color3.fromRGB(255, 255, 255)
	light.Range      = 12
	light.Parent     = root

	-- ProximityPrompt — E키 0.5초 차징
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "픽업"
	prompt.ObjectText            = "아이템"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = Config.PICKUP_HOLD_DURATION
	prompt.MaxActivationDistance = Config.MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = root

	-- ════════════ 궤도 트레일 구체 ════════════
	-- 작은 흰 구체 2개가 체스트 시각 중심 주변을 직교 궤도로 빙빙 돌며 흰 트레일을 그림
	local function createOrbiter(name)
		local part = Instance.new("Part")
		part.Name              = name
		part.Shape             = Enum.PartType.Ball
		part.Size              = Vector3.new(Config.ORBITER_SIZE, Config.ORBITER_SIZE, Config.ORBITER_SIZE)
		part.Position          = position  -- 첫 프레임에 Heartbeat가 잡아줌
		part.Anchored          = true
		part.CanCollide        = false
		part.CastShadow        = false
		part.Material          = Enum.Material.Neon
		part.Color             = Config.ORBITER_COLOR
		part.Parent            = model

		local a0 = Instance.new("Attachment")
		a0.Name     = "TrailStart"
		a0.Position = Vector3.new(0, Config.ORBITER_SIZE * 0.4, 0)
		a0.Parent   = part

		local a1 = Instance.new("Attachment")
		a1.Name     = "TrailEnd"
		a1.Position = Vector3.new(0, -Config.ORBITER_SIZE * 0.4, 0)
		a1.Parent   = part

		local trail = Instance.new("Trail")
		trail.Attachment0    = a0
		trail.Attachment1    = a1
		trail.Color          = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		trail.Transparency   = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Lifetime       = Config.TRAIL_LIFETIME
		trail.LightEmission  = 1
		trail.LightInfluence = 0
		trail.MinLength      = 0
		trail.FaceCamera     = true
		trail.Parent         = part

		return part
	end

	local orbiterA = createOrbiter("OrbiterA")
	local orbiterB = createOrbiter("OrbiterB")

	-- 궤도 애니메이션 (체스트 실제 시각 중심 = WoodBottom과 WoodTop의 중점)
	-- 체스트는 정적이라 중심 한 번만 계산
	local angle = 0
	local R = Config.ORBIT_RADIUS
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent or not root.Parent then
			conn:Disconnect()
			return
		end
		angle = angle + dt * Config.ORBIT_SPEED
		local c = visualCenter
		-- OrbiterA: XZ 평면 (수평 링)
		orbiterA.Position = c + Vector3.new(math.cos(angle) * R, 0, math.sin(angle) * R)
		-- OrbiterB: YZ 평면 (수직 링, A와 직교) + 위상 90° 어긋남
		orbiterB.Position = c + Vector3.new(0, math.cos(angle + math.pi/2) * R, math.sin(angle + math.pi/2) * R)
	end)

	return model, prompt, hingeInfo
end

-- ════════════ 고급 상자(Rare Chest) 모델 생성 ════════════
-- 구조가 Item Chest와 완전히 다름(본체/뚜껑/코인 메시) → 별도 생성.
-- 반환 형식은 동일(model, prompt, hingeInfo)이라 spawnOne의 뚜껑 트윈 코드를 그대로 재사용.
local function createRarePickupModel(position)
	local template = ServerStorage:FindFirstChild(Config.RARE_CHEST_TEMPLATE_NAME)
	if not template then
		warn("[PickupSystem] ServerStorage." .. Config.RARE_CHEST_TEMPLATE_NAME .. " 템플릿 없음")
		return nil, nil, nil
	end

	local model = template:Clone()
	model.Name = "RarePickup"
	local body = model.PrimaryPart  -- Chinese Chest_Chest (템플릿에서 지정됨)
	if not body then
		warn("[PickupSystem] Rare Chest PrimaryPart 없음")
		model:Destroy()
		return nil, nil, nil
	end

	-- 위치 배치 (본체 기준). 템플릿은 이미 Anchored=true, CanCollide=false
	-- 앞면(-Z, 경첩 반대편)이 항상 불벽(쓰나미 발생) 쪽을 바라보도록 lookAt 정렬.
	-- 불벽은 상자보다 X가 작은 쪽 → 그 방향을 향하게.
	local wallX = getFireWallX()
	local faceDir = Vector3.new(wallX - position.X, 0, 0)
	if faceDir.Magnitude < 0.01 then faceDir = Vector3.new(-1, 0, 0) end
	model:PivotTo(CFrame.lookAt(position, position + faceDir.Unit))

	-- 뚜껑(Lid) 찾기 → 힌지 정보 (Item Chest와 같은 트윈 코드 재사용)
	-- 축/각도는 4단계 인게임 확인 후 미세조정. 일단 본체 위+뒤 모서리 기준.
	local lid
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:find("Lid") then lid = d break end
	end
	local hingeInfo = nil
	if lid then
		hingeInfo = {
			-- 경첩 축 = 본체 로컬 X축, 위치 = point1/point2로 측정한 중점 (body 기준 로컬)
			pivotCFrame       = body.CFrame * CFrame.new(0, 1.751, 1.365),
			lidParts          = { lid },
			lidInitialCFrames = { [lid] = lid.CFrame },
		}
	end

	-- 포인트 라이트 (금색 — rare 강조, 일반 흰색과 구분)
	local light = Instance.new("PointLight")
	light.Brightness = 3
	light.Color      = Color3.fromRGB(255, 215, 0)
	light.Range      = 16
	light.Parent     = body

	-- ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "고급 픽업"
	prompt.ObjectText            = "Rare Chest"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = Config.PICKUP_HOLD_DURATION
	prompt.MaxActivationDistance = Config.MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = body

	-- ════════════ 궤도 트레일 구체 (금색 — rare 강조, 일반 흰색과 구분) ════════════
	local RARE_ORBIT_COLOR = Color3.fromRGB(255, 215, 0)
	local orbitCenter = body.Position + Vector3.new(0, body.Size.Y * 0.3, 0)
	local orbitR = Config.ORBIT_RADIUS + 1  -- rare 상자가 커서 약간 넓게

	local function createRareOrbiter(oname)
		local part = Instance.new("Part")
		part.Name       = oname
		part.Shape      = Enum.PartType.Ball
		part.Size       = Vector3.new(Config.ORBITER_SIZE, Config.ORBITER_SIZE, Config.ORBITER_SIZE)
		part.Position   = orbitCenter
		part.Anchored   = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material   = Enum.Material.Neon
		part.Color      = RARE_ORBIT_COLOR
		part.Parent     = model

		local a0 = Instance.new("Attachment")
		a0.Name = "TrailStart"
		a0.Position = Vector3.new(0, Config.ORBITER_SIZE * 0.4, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailEnd"
		a1.Position = Vector3.new(0, -Config.ORBITER_SIZE * 0.4, 0)
		a1.Parent = part

		local trail = Instance.new("Trail")
		trail.Attachment0    = a0
		trail.Attachment1    = a1
		trail.Color          = ColorSequence.new(RARE_ORBIT_COLOR)
		trail.Transparency   = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Lifetime       = Config.TRAIL_LIFETIME
		trail.LightEmission  = 1
		trail.LightInfluence = 0
		trail.MinLength      = 0
		trail.FaceCamera     = true
		trail.Parent         = part
		return part
	end

	local orbiterA = createRareOrbiter("OrbiterA")
	local orbiterB = createRareOrbiter("OrbiterB")

	local angle = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent or not body.Parent then
			conn:Disconnect()
			return
		end
		angle = angle + dt * Config.ORBIT_SPEED
		orbiterA.Position = orbitCenter + Vector3.new(math.cos(angle) * orbitR, 0, math.sin(angle) * orbitR)
		orbiterB.Position = orbitCenter + Vector3.new(0, math.cos(angle + math.pi/2) * orbitR, math.sin(angle + math.pi/2) * orbitR)
	end)

	model:SetAttribute("IsRare", true)

	return model, prompt, hingeInfo
end

-- ════════════ 코인 보상 부유 텍스트 (서버 생성, 모든 클라가 봄) ════════════
-- 코인 박스 트리거 시 체스트 위에 "+N Coins" 텍스트가 떠올라 페이드됨.
local function spawnFloatingCoinText(worldPosition, amount)
	-- anchor part (보이지 않는 트윈 타겟)
	local anchor = Instance.new("Part")
	anchor.Name           = "CoinFloatAnchor"
	anchor.Size           = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position       = worldPosition
	anchor.Anchored       = true
	anchor.CanCollide     = false
	anchor.Transparency   = 1
	anchor.CastShadow     = false
	anchor.Parent         = Workspace

	-- BillboardGui + TextLabel (크게, 잘 보이게)
	local bb = Instance.new("BillboardGui")
	bb.Size         = UDim2.new(10, 0, 3, 0)        -- 더 큼 (6,2 → 10,3)
	bb.StudsOffset  = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop  = true
	bb.MaxDistance  = 300                            -- 멀리서도 보임
	bb.LightInfluence = 0                            -- 환경광 영향 없음 (항상 밝게)
	bb.Parent       = anchor

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                   = string.format("+%d Coins", amount)  -- 영어
	label.TextColor3             = Color3.fromRGB(255, 215, 0)         -- 황금
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBlack
	label.Parent                 = bb

	-- UIStroke 로 두꺼운 외곽선 (TextStroke 보다 진함)
	local stroke = Instance.new("UIStroke")
	stroke.Color        = Color3.fromRGB(0, 0, 0)
	stroke.Thickness    = 3
	stroke.Transparency = 0
	stroke.Parent       = label

	-- 위로 부유 + 페이드 트윈
	local DURATION     = 2.0      -- 좀 더 길게 (1.5 → 2.0)
	local FLOAT_HEIGHT = 10        -- 더 높이 (8 → 10)
	local info = TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, {
		Position = worldPosition + Vector3.new(0, FLOAT_HEIGHT, 0),
	}):Play()
	TweenService:Create(label, info, {
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, info, {
		Transparency = 1,
	}):Play()

	-- 트윈 완료 후 destroy
	task.delay(DURATION + 0.1, function()
		if anchor.Parent then anchor:Destroy() end
	end)
end

-- ════════════ 아이템 지급 (Backpack에 Tool 클론) ════════════
local function grantItem(player, itemName)
	local runnerItems = ServerStorage:FindFirstChild("RunnerItem")
	if not runnerItems then return false end
	local template = runnerItems:FindFirstChild(itemName)
	if not template or not template:IsA("Tool") then return false end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return false end

	local clone = template:Clone()
	clone.Parent = backpack
	return true
end

-- ════════════ 픽업 디스폰 ════════════
local function despawnPickup(model)
	if not model then return end
	activePickups[model] = nil
	if model.Parent then model:Destroy() end
end

-- ════════════ 픽업 1개 스폰 ════════════
local function spawnOne()
	if not active or not pickupFolder then return end

	-- 동시 존재 캡 체크 (캡 도달 시 이번 틱 스킵, 다음 틱에서 재시도)
	local count = 0
	for _ in pairs(activePickups) do count = count + 1 end
	if count >= Config.MAX_ACTIVE_PICKUPS then return end

	local wallX = getFireWallX()
	local geo = Config.GetGeometry()
	local zMin = geo.zCenter - geo.zWidth / 2
	local zMax = geo.zCenter + geo.zWidth / 2

	-- X: 불벽 앞 안전 띠, 단 맵 종착지(endX) 넘지 않게
	local xMin = wallX + Config.AHEAD_MIN
	local xMax = math.min(wallX + Config.AHEAD_MAX, geo.endX)
	if xMin >= geo.endX then return end  -- 불벽이 종착지 근접 → 스폰 그만

	-- 기존 픽업들과 최소 거리 만큼 떨어진 위치 찾기 (재시도 최대 MAX_SPAWN_RETRIES 번)
	local position
	local minDistSq = Config.MIN_PICKUP_DISTANCE * Config.MIN_PICKUP_DISTANCE
	for attempt = 1, Config.MAX_SPAWN_RETRIES do
		local x = xMin + math.random() * (xMax - xMin)
		local z = zMin + math.random() * (zMax - zMin)
		local y = Config.GetHillSurfaceY(x) + Config.PICKUP_Y_OFFSET
		local candidate = Vector3.new(x, y, z)

		-- 기존 활성 픽업들과의 거리 검사 (Y 무시, XZ 수평 거리만)
		local tooClose = false
		for activeModel in pairs(activePickups) do
			local pp = activeModel.PrimaryPart
			if pp then
				local dx = pp.Position.X - x
				local dz = pp.Position.Z - z
				if (dx * dx + dz * dz) < minDistSq then
					tooClose = true
					break
				end
			end
		end

		if not tooClose then
			position = candidate
			break
		end
	end

	if not position then return end  -- 모든 재시도 실패 → 이번 틱 스킵, 다음 보충 때 다시 시도

	local itemName  = Config.PickRandomItem()

	-- rare 추첨: 당첨 시 Item Chest 대신 Rare Chest (아이템 칸은 그대로 itemName 사용)
	local isRare = math.random() < Config.RARE_SPAWN_CHANCE
	local model, prompt, hingeInfo
	if isRare then
		model, prompt, hingeInfo = createRarePickupModel(position)
	else
		model, prompt, hingeInfo = createPickupModel(itemName, position)
	end
	if not model then return end  -- 템플릿/구조 문제로 생성 실패

	if not isRare then
		-- 일반 박스: 사전 코인 보상 결정 (오브 색도 사전 결정)
		local isCoinReward = math.random() < Config.COIN_DROP_CHANCE
		model:SetAttribute("IsCoinReward", isCoinReward)
		-- 코인 박스면 내부 오브를 황금색으로
		if isCoinReward then
			local orb = model:FindFirstChild("InnerOrb")
			if orb then
				orb.Color = Config.COIN_ORB_COLOR
			end
		end
	end
	-- (rare는 createRarePickupModel에서 IsRare 속성 설정 완료)

	model.Parent = pickupFolder
	activePickups[model] = true

	-- 차징 완료 시 처리 (E 0.5초 → 뚜껑 열림 1초 → 소멸)
	prompt.Triggered:Connect(function(player)
		if not activePickups[model] then return end  -- 이미 누군가 가져감 / 정리됨
		if player:GetAttribute("Role") ~= "Runner" then return end  -- 러너 전용

		-- 즉시 가져감 표시 (재트리거 방지)
		activePickups[model] = nil
		prompt.Enabled = false

		-- 스폰 시점에 결정된 보상 분기 읽기
		local isRare       = model:GetAttribute("IsRare") or false
		local isCoinReward = model:GetAttribute("IsCoinReward") or false

		if isRare then
			-- 고급 상자: 스킨 1개(영구) + 아이템 1개(즉시 인벤)
			-- 스킨 칸: 안 가진 스킨/건틀릿색 균등 추첨. 전부 보유면 코인 폴백.
			local skinResult = _G.grantRandomSkin and _G.grantRandomSkin(player) or nil
			if skinResult then
				print(string.format("✨ %s 고급상자 스킨: %s (%s)", player.Name, skinResult.display, skinResult.kind))
				rareSkinRewardEvent:FireClient(player, skinResult)  -- 클라에 보상 카드 표시
			elseif _G.CoinSystem and _G.CoinSystem.addCoins then
				_G.CoinSystem.addCoins(player, Config.RARE_FALLBACK_COIN)
				spawnFloatingCoinText(model:GetPivot().Position, Config.RARE_FALLBACK_COIN)
				print(string.format("✨ %s 고급상자: 스킨 전부 보유 → 코인 +%d 폴백", player.Name, Config.RARE_FALLBACK_COIN))
			end
			-- 아이템 칸: 항상 지급 (스킨은 이미 줬으니 아이템 실패해도 계속 진행)
			if grantItem(player, itemName) then
				print(string.format("✨ %s 고급상자 아이템: %s", player.Name, itemName))
			end

		elseif isCoinReward then
			-- 📦 [항상 둘 다] 코인과 아이템을 함께 지급한다.
			--   [변경 2026-08-23] 예전엔 COIN_DROP_CHANCE(40%) 로 '코인 아니면 아이템'
			--   둘 중 하나만 줬다. 이제 코인 박스든 아이템 박스든 아이템은 항상 나가고,
			--   코인 박스는 거기에 코인이 얹힌다.
			--   ⚠️ IsCoinReward 속성과 황금색 오브는 그대로 유지한다. 그게 "이 상자엔
			--      코인도 들었다"는 예고 역할을 하므로, 없애면 상자 간 구분이 사라진다.
			--   ⚠️ 아이템을 먼저 지급한다. 코인부터 주면 아이템 지급이 실패했을 때
			--      코인만 받은 채 상자가 사라져 보상이 어긋난다.
			local gotItem = grantItem(player, itemName)

			local amount = Config.COIN_REWARD_AMOUNT
			if _G.CoinSystem and _G.CoinSystem.addCoins then
				_G.CoinSystem.addCoins(player, amount)
				-- 부유 텍스트 (체스트 위에 "+10 🪙")
				local chestPos = model:GetPivot().Position
				spawnFloatingCoinText(chestPos, amount)
				print(string.format("🪙 %s 코인 보상 +%d (+ 아이템 %s)",
					player.Name, amount, gotItem and itemName or "실패"))
			else
				warn("⚠️ _G.CoinSystem 미로드 — 코인 지급 실패 (아이템은 이미 지급됨)")
			end

			-- 아이템도 코인도 못 준 경우에만 상자를 되돌린다.
			if not gotItem and not (_G.CoinSystem and _G.CoinSystem.addCoins) then
				despawnPickup(model)
				return
			end
		else
			-- 아이템 즉시 지급 (애니메이션은 비주얼만)
			if not grantItem(player, itemName) then
				despawnPickup(model)
				return
			end
			print(string.format("📦 %s가 %s 픽업", player.Name, itemName))
		end

		-- 픽업 상자 열림 사운드 (rare는 전용 소리, 일반은 일반 소리 — 각각 하나만)
		local soundParent = model.PrimaryPart or model
		local function playOpenSound(soundId, volume)
			local s = Instance.new("Sound")
			s.SoundId = soundId
			s.Volume  = volume
			s.Parent  = soundParent
			s:Play()
			game:GetService("Debris"):AddItem(s, 5)
		end
		if isRare then
			playOpenSound(Config.SOUND_OPEN_RARE, 3)
		else
			playOpenSound(Config.SOUND_OPEN_NORMAL, 0.7)
		end

		-- 뚜껑 열림 트윈 (뚜껑 안의 모든 anchored 파트를 같은 회전으로 동기 트윈)
		if hingeInfo then
			local rotation = CFrame.Angles(math.rad(Config.CHEST_OPEN_ANGLE_DEG), 0, 0)
			local pivot    = hingeInfo.pivotCFrame
			local info     = TweenInfo.new(Config.CHEST_OPEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			for _, part in ipairs(hingeInfo.lidParts) do
				if part.Parent then
					local initialCF  = hingeInfo.lidInitialCFrames[part]
					local openCFrame = pivot * rotation * pivot:Inverse() * initialCF
					TweenService:Create(part, info, { CFrame = openCFrame }):Play()
				end
			end
		end

		-- 애니메이션 시간만큼 보여준 후 소멸
		task.wait(Config.CHEST_OPEN_DURATION)
		despawnPickup(model)
	end)
end

-- ════════════ 불벽 추월 픽업 정리 ════════════
local function cullPassedPickups()
	local wallX = getFireWallX()
	for model in pairs(activePickups) do
		if model.Parent and model.PrimaryPart then
			if model.PrimaryPart.Position.X < wallX then
				despawnPickup(model)
			end
		end
	end
end

-- ════════════ 메인 스폰 루프 ════════════
-- 1) 첫 스폰: INITIAL_BURST_COUNT 개를 한꺼번에 깔아줌 (캡 안에서)
-- 2) 이후: REPLENISH_INTERVAL 마다 1개씩 보충 (캡 도달 시 스킵)
local function spawnLoop(myId)
	-- 라운드 시작 후 첫 스폰까지 대기
	task.wait(Config.SPAWN_START_DELAY)
	if myId ~= spawnLoopId or not active then return end

	-- ─ 1단계: 초기 버스트 ─
	for i = 1, Config.INITIAL_BURST_COUNT do
		spawnOne()  -- 캡 체크는 spawnOne 내부에서
	end

	-- ─ 2단계: 보충 사이클 ─
	while active and myId == spawnLoopId do
		local elapsed = 0
		while elapsed < Config.REPLENISH_INTERVAL and active and myId == spawnLoopId do
			task.wait(0.5)
			elapsed = elapsed + 0.5
			cullPassedPickups()
		end
		spawnOne()
	end
end

-- ════════════ 라운드 시작/끝 ════════════
local function onRoundStart()
	if active then return end
	active = true
	spawnLoopId = spawnLoopId + 1
	local myId = spawnLoopId

	-- 픽업 컨테이너 폴더 재생성
	local existing = Workspace:FindFirstChild("PickupContainer")
	if existing then existing:Destroy() end
	pickupFolder = Instance.new("Folder")
	pickupFolder.Name = "PickupContainer"
	pickupFolder.Parent = Workspace

	print("📦 PickupSystem 시작 (대기:", Config.SPAWN_START_DELAY, "초)")
	task.spawn(spawnLoop, myId)
end

-- 스폰만 중단 (Stage 2 / 라운드 종료 공통): 기존 픽업은 그대로 유지
-- StopFirePressure 이벤트가 Stage 2 트리거 + 라운드 종료 모두에서 발사되므로 이 핸들러 하나로 처리.
-- 기존 픽업 정리는 다음 onRoundStart 시 PickupContainer 폴더가 destroy 되며 자동 처리됨.
local function stopSpawning()
	if not active then return end
	active = false
	spawnLoopId = spawnLoopId + 1  -- 루프 무효화
	print("📦 PickupSystem 스폰 중단 (기존 픽업은 유지)")
end

-- 전체 정리 (수동 호출/테스트용): 스폰 중단 + 모든 활성 픽업 즉시 제거
local function onRoundEnd()
	active = false
	spawnLoopId = spawnLoopId + 1  -- 루프 무효화

	for model in pairs(activePickups) do
		if model and model.Parent then model:Destroy() end
	end
	activePickups = {}
	if pickupFolder then pickupFolder:Destroy(); pickupFolder = nil end
	print("📦 PickupSystem 전체 정리")
end

startEvent.Event:Connect(onRoundStart)
stopEvent.Event:Connect(stopSpawning)        -- StopFirePressure → 스폰만 중단 (Stage 2 + 라운드 종료 공통)
roundEndedEvent.Event:Connect(onRoundEnd)    -- RoundEnded → 전체 정리 (라운드 진짜 끝났을 때만)

-- ════════════ 테스트 인터페이스 ════════════
-- 1) 채팅 명령 /pickup → 켜고끄기 토글 (정상 라운드 흐름과 독립)
-- 2) _G.startPickupSpawning() / _G.stopPickupSpawning() → 다른 테스트 시스템에서 호출용
_G.startPickupSpawning = onRoundStart
_G.stopPickupSpawning  = onRoundEnd

local isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev

local function hookChat(player)
	player.Chatted:Connect(function(msg)
		if not isDev(player) then return end   -- 🔒 개발자 전용
		if msg == "/pickup" then
			if active then
				onRoundEnd()
				print("📦 /pickup → OFF")
			else
				onRoundStart()
				print("📦 /pickup → ON (불벽 X 추적: 없으면 -228 가정)")
			end
		end
	end)
end
Players.PlayerAdded:Connect(hookChat)
for _, p in ipairs(Players:GetPlayers()) do hookChat(p) end

print("📦 PickupSystem 활성화 (첫 스폰:", Config.INITIAL_BURST_COUNT, "개 / 보충:", Config.REPLENISH_INTERVAL, "초마다 1개 / 최대", Config.MAX_ACTIVE_PICKUPS, "개 / 테스트: /pickup)")
