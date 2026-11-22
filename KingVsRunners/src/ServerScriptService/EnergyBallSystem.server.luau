-- EnergyBallSystem
-- 태거 아이템 'EnergyBall': 레일건 형태 직선 공격.
-- 사용 시 hill 표면을 따라가는 일직선 경고선 표시 → Red/Blue가 캐릭터 양옆에서 가슴으로 모임 →
-- 합쳐져 Purple 생성 → 경로 따라 고속 발사 → 닿는 러너 즉사.

local ServerStorage = game:GetService("ServerStorage")
local Debris        = game:GetService("Debris")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local SoundService  = game:GetService("SoundService")

local taggerItems = ServerStorage:WaitForChild("TaggerItem")
local TEMPLATE    = taggerItems:WaitForChild("EnergyBall")

-- ─── Tunables ─────────────────────────────────────────────────
local TOTAL_RANGE     = 1000   -- 전체 발사 거리 (stud)
local SEGMENT_COUNT   = 150    -- 경로 분할 수 (step 10 stud로 hill 표면 추적)
local STEP_LEN        = TOTAL_RANGE / SEGMENT_COUNT
local SURFACE_PROBE_UP   = 50  -- 표면 raycast 위쪽 시작 offset
local SURFACE_PROBE_DOWN = 100 -- 표면 raycast 아래쪽 길이
local HEIGHT_ABOVE_GROUND = 3  -- 발사체가 표면에서 떠 있는 높이

local WARNING_DURATION = 1.5   -- 경고선 표시 시간 (= 차징 시간)
local FLIGHT_DURATION  = 0.6   -- Purple이 경로 끝까지 가는 시간 (클수록 느림)
local HIT_RADIUS       = 10    -- Purple 충돌 반경 (stud)
local EB_STALL_TIME    = 0.8   -- 🛡️ 방패에 막혔을 때 그 자리에 멈추는 시간(초)
                               --   ⚠️ 쓰나미(1.2)보다 짧다 — 발사체라 오래 서 있으면 어색하다.

local WARNING_THICKNESS = HIT_RADIUS * 2  -- 경고선 폭 = 피해 지름(반경×2)에 맞춤
local WARNING_COLOR     = Color3.fromRGB(255, 60, 60)
local WARNING_TRANSPARENCY = 0.4

-- ─── 사운드 ───────────────────────────────────────────────────
local FIRE_SOUND_ID    = "rbxassetid://132604058441815"  -- Purple 발사음
local FIRE_SOUND_ID2   = "rbxassetid://123410783666130"  -- Purple 발사 추가음 (동시 재생)
local MERGE_SOUND_ID   = "rbxassetid://77598724569330"   -- Red/Blue 합체음
local MERGE_SOUND_SPEED = 1.1   -- 합체음 재생 속도
local MERGE_SOUND_START = 1     -- 합체음 시작 지점 (초)

-- 사운드 재생 헬퍼 (2D: SoundService 직속 → 위치 무관 동일 볼륨, 재생 후 자동 정리)
local function playSound(soundId, speed, startTime, volume)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.PlaybackSpeed = speed or 1
	s.Volume = volume or 1
	s.Parent = SoundService  -- 2D 재생 (거리 감쇠 없음)
	s:Play()
	if startTime and startTime > 0 then
		s.TimePosition = startTime  -- Play 직후 지정 위치로 점프
	end
	s.Ended:Connect(function() s:Destroy() end)
	Debris:AddItem(s, 20)  -- 안전장치
	return s
end
-- 🧱 바리케이드·성문 목록 (레이캐스트 제외용)
-- ⚠️ 판정 파트의 BarricadeGate 속성이 연결 구조물을 알려준다.
local _wallCache = nil
-- ⚠️ [2026-08-27] 캐시 무효화 필수.
--   [증상] 에너지볼 경로가 바리케이드 지형 '위' 에 그려졌다(2단계, 성문 파괴 후).
--   [원인] 캐시를 한 번 만들면 영영 갱신하지 않았다. 성문이 부서지면 BarricadeSystem 이
--     ServerStorage 원본을 복제해 새로 만드는데, 캐시는 파괴된 옛 인스턴스를 붙들고 있어
--     '새 성문' 이 제외 목록에서 빠진다 → 레이가 성문 윗면을 지면으로 착각.
--   ⚠️ 스폰 아이템 제외(2026-08-27)는 매번 workspace 를 훑으므로 문제가 없었다.
--     그래서 "아이템 위는 고쳐졌는데 바리케이드 위는 그대로" 인 증상이 나왔다.
--   ⚠️ 캐시 자체는 유지한다 — GetDescendants 를 매 발사마다 도는 건 비싸다.
--     대신 맵 전환·성문 변화 시 버린다.
local function invalidateWallCache() _wallCache = nil end
do
	local ev = game:GetService("ReplicatedStorage"):FindFirstChild("SetCurrentMap")
	if ev and ev:IsA("BindableEvent") then ev.Event:Connect(invalidateWallCache) end
	-- 성문 재생성/파괴 감지: Barricades 폴더의 자식 변화
	task.spawn(function()
		while true do
			task.wait(2)
			for _, mf in ipairs(workspace:GetChildren()) do
				if mf.Name == "map1" or mf.Name == "map2" then
					local bf = mf:FindFirstChild("Barricades")
					if bf and not bf:GetAttribute("_EBHooked") then
						bf:SetAttribute("_EBHooked", true)
						bf.ChildAdded:Connect(invalidateWallCache)
						bf.ChildRemoved:Connect(invalidateWallCache)
						invalidateWallCache()
					end
				end
			end
		end
	end)
end
local function getWallParts()
	-- 캐시에 죽은 인스턴스가 섞여 있으면 통째로 다시 만든다(무효화 신호를 놓친 경우 대비).
	if _wallCache then
		for _, d in ipairs(_wallCache) do
			if not d.Parent then _wallCache = nil break end
		end
	end
	if _wallCache then return _wallCache end
	_wallCache = {}
	for _, mf in ipairs(workspace:GetChildren()) do
		if mf.Name == "map1" or mf.Name == "map2" then
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
	end
	return _wallCache
end

-- 🛡️ 태거 베이스 안의 러너는 태거 아이템에 당하지 않는다.
-- ⚠️ [2026-08-28] 판정을 _G.IsCharInTaggerBase 로 일원화했다. 여기서 복사하지 말 것.
--   원본은 ItemSpawnHandler 에 있다(높이 밴드·캐시 무효화·showBaseImmune 포함).
local function isInTaggerBase(model)
	return _G.IsCharInTaggerBase(model)
end


-- ─── 표면 추적 raycast 헬퍼 ───────────────────────────────────
local function makeRayParams(player)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	-- 모든 캐릭터 + 시각 part 제외
	for _, plr in ipairs(game.Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	-- NPC 캐릭터들도 제외 (Noob, Noob2 등)
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			table.insert(ignore, m)
		end
	end
	-- ⚠️ [2026-08-25] 바리케이드·성문 제외.
	--    예전엔 경로가 성벽 '위'를 타고 지나가 벽을 넘는 것처럼 보였다.
	--    바닥을 따라 직진해야 한다.
	for _, w in ipairs(getWallParts()) do table.insert(ignore, w) end
	-- ⚠️ [2026-08-27] 스폰된 태거 아이템·얼음·웅덩이도 제외한다.
	--   [증상] 경로 표식과 파편 지형이 바리케이드·다른 아이템 위에 겹쳐 생겼다.
	--   [원인] 이 레이는 '지면 높이' 를 재는 용도인데, 통나무·배럴·얼음기둥에 맞으면
	--     그 윗면을 지면으로 착각해 표식이 공중에 뜨거나 물체를 파고든다.
	--   ⚠️ 스폰 아이템은 workspace 최상위에 붙는다(TaggerSpawnedItem 속성).
	--     프드 얼음(FrostIce_*)·배럴 웅덩이(_BarrelSpill)는 이름으로 잡는다.
	--
	-- 🕳️ [2026-09-01] 블랙홀·픽업 상자 추가. 경로가 그 위로 솟았다 내려와 연출이 어색했다.
	--   ⚠️ 이 제외 목록이 세 번째로 늘어난 것이다(08-25 벽 → 08-27 아이템 → 지금).
	--     이름을 하나씩 더 적는 방식은 다음에 또 깨진다. 그래서 GroundRayIgnore 속성을
	--     기준으로 바꿨다 — 앞으로 새 물체는 '생성할 때 속성만 켜면' 여기를 안 고쳐도 된다.
	--   ⚠️ TaggerSpawnedItem 을 재사용하지 않는다. 그 속성은 라운드 종료 '태거 아이템 정리'가
	--     삭제 대상으로 쓰므로, 픽업 상자에 붙이면 상자까지 같이 지워진다.
	for _, d in ipairs(workspace:GetChildren()) do
		if d:GetAttribute("TaggerSpawnedItem")
		   or d:GetAttribute("GroundRayIgnore")
		   or d.Name:sub(1, 9) == "FrostIce_"
		   or d.Name == "_BarrelSpill" then
			table.insert(ignore, d)
		end
	end
	-- 📦 픽업 상자는 전용 폴더에 모여 있다 — 폴더 하나만 제외하면 전부 커버된다.
	--   (PickupSystem 이 라운드마다 PickupContainer 를 재생성하므로 매번 새로 찾는다)
	local pickups = workspace:FindFirstChild("PickupContainer")
	if pickups then table.insert(ignore, pickups) end
	rp.FilterDescendantsInstances = ignore
	return rp
end

-- 주어진 (x,z)에서 위쪽으로 raycast하여 hill 표면 점 찾기
local function probeSurface(xz, params)
	local origin = Vector3.new(xz.X, xz.Y + SURFACE_PROBE_UP, xz.Z)
	local dir = Vector3.new(0, -(SURFACE_PROBE_UP + SURFACE_PROBE_DOWN), 0)
	local r = workspace:Raycast(origin, dir, params)
	if r then
		return r.Position + Vector3.new(0, HEIGHT_ABOVE_GROUND, 0), r.Normal
	end
	return nil
end

-- 경로 점들 생성 (hill 표면 따라)
local function buildPath(startPos, horizDir, params)
	local points = {}
	for i = 0, SEGMENT_COUNT do
		local xz = startPos + horizDir * (STEP_LEN * i)
		local pt = probeSurface(xz, params)
		if pt then
			table.insert(points, pt)
		else
			-- 표면 없으면 종료 (절벽 등)
			break
		end
	end
	return points
end

-- ─── 경고선 시각화 ─────────────────────────────────────────────
local function drawWarning(points, parent)
	local segments = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i+1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local part = Instance.new("Part")
		part.Name = "EnergyBallWarning"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Material = Enum.Material.Neon
		part.Color = WARNING_COLOR
		part.Transparency = WARNING_TRANSPARENCY
		part.Size = Vector3.new(WARNING_THICKNESS, 0.2, len)
		part.CFrame = CFrame.lookAt(mid, b)
		part.Parent = parent
		table.insert(segments, part)
	end
	return segments
end

-- ─── 차징 (Red, Blue → 중앙으로 모음) ────────────────────────
-- fireDir(발사 방향)에 수직인 "순수 수평축"으로 좌우 배치.
-- → 두 공의 Y좌표가 항상 동일 (위아래 분리 불가능). 카메라가 발사 방향을 볼 때 화면 좌우로 보임.
local function chargeBalls(char, duration, fireDir)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end

	local sideOffset = 5
	-- 발사 방향에 수직인 수평 좌우축 (Y=0 보장)
	local up = Vector3.new(0, 1, 0)
	local rightAxis = fireDir:Cross(up)
	if rightAxis.Magnitude < 0.01 then
		rightAxis = Vector3.new(1, 0, 0)
	else
		rightAxis = Vector3.new(rightAxis.X, 0, rightAxis.Z).Unit  -- 확실히 수평
	end

	local center   = hrp.Position
	local leftPos  = center - rightAxis * sideOffset
	local rightPos = center + rightAxis * sideOffset

	local red  = TEMPLATE.Red:Clone()
	local blue = TEMPLATE.Blue:Clone()
	red.Anchored = true
	blue.Anchored = true
	red.CanCollide = false
	blue.CanCollide = false

	-- 이펙트 꼬리는 Beam이 Part의 로컬 X축을 따라 뻗음 (꼬리 = 로컬 -X).
	-- fromMatrix로 로컬 X축을 좌우축에 직접 정렬 → 꼬리가 각자 바깥으로.
	--   Red(왼쪽):   로컬 +X = +rightAxis → 꼬리(-X)가 왼쪽 바깥
	--   Blue(오른쪽): 로컬 +X = -rightAxis → 꼬리(-X)가 오른쪽 바깥
	red.CFrame  = CFrame.fromMatrix(leftPos,   rightAxis, up)   -- Red 왼쪽
	blue.CFrame = CFrame.fromMatrix(rightPos, -rightAxis, up)   -- Blue 오른쪽
	red.Parent  = workspace
	blue.Parent = workspace

	-- 합체음 재생 (1.1배속, 1초 지점부터) — 2D, 발사 시점에 끊기 위해 객체 보관
	local mergeSound = playSound(MERGE_SOUND_ID, MERGE_SOUND_SPEED, MERGE_SOUND_START)

	-- 목표: 중앙으로 모이되 바깥 향하는 orientation 유지
	local redGoal  = CFrame.fromMatrix(center,  rightAxis, up)
	local blueGoal = CFrame.fromMatrix(center, -rightAxis, up)

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(red,  info, { CFrame = redGoal }):Play()
	TweenService:Create(blue, info, { CFrame = blueGoal }):Play()
	return red, blue, mergeSound
end

-- ─── 땅 갈라짐(균열 + 파편) 이펙트 ─────────────────────────
local SCORCH_EVERY = 3  -- 몇 segment마다 갈라짐 (3 = 30 stud 간격)

local function createScorch(centerPos, parent)
	-- ⚠️ [2026-08-27] 자체 필터 → makeRayParams 재사용.
	--   [증상] 파편 지형이 바리케이드·다른 태거 아이템 위에 겹쳐 생겼다.
	--   [원인] 여기서만 필터를 따로 만들었는데 '플레이어 캐릭터' 만 제외했다.
	--     경로를 그리는 쪽(makeRayParams)은 2026-08-25 에 바리케이드를 제외하도록
	--     고쳐졌는데, 파편 쪽은 그 수정을 따라가지 못했다 — 같은 로직이 두 벌 있으면
	--     한쪽만 고쳐지는 이 사고가 반복된다.
	--   ⚠️ 필터를 다시 복사하지 말 것. 새 제외 대상은 makeRayParams 한 곳에만 추가한다.
	local rp = makeRayParams(nil)
	local r = workspace:Raycast(centerPos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rp)
	local sPos   = r and r.Position or centerPos
	local normal = r and r.Normal or Vector3.new(0, 1, 0)
	local groundMat = Enum.Material.Ground            -- 파헤쳐진 흙 느낌
	local groundColor = Color3.fromRGB(102, 72, 45)   -- 흙 갈색 (hill 초록 속 흙)

	-- 표면 접평면 기저 (tangent, bitangent) — 균열을 표면 위에 눕히기 위함
	local up2 = math.abs(normal.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local tangent = normal:Cross(up2).Unit
	local bitangent = normal:Cross(tangent).Unit

	-- ── 깨진 지면: 크고 납작한 판자들이 솟아올라 겹침 (레퍼런스 연출) ──
	-- (A) 솟아오른 채 잠시 고정되는 큰 판들 — 중심을 둘러싸고 바깥으로 기울어 들림
	local slabCount = math.random(7, 11)
	local baseA = math.random() * math.pi * 2
	for i = 1, slabCount do
		local ang = baseA + (i / slabCount) * math.pi * 2 + (math.random() - 0.5) * 0.4
		local dir2d = (tangent * math.cos(ang) + bitangent * math.sin(ang)).Unit
		local dist = math.random(20, 65) / 10                 -- 중심에서 2~6.5 stud
		local w = math.random(30, 70) / 10                    -- 폭 3~7 stud (큼)
		local l = math.random(45, 95) / 10                    -- 길이 4.5~9.5 stud (큼)
		local thick = math.random(4, 8) / 10                  -- 두께 0.4~0.8

		local slab = Instance.new("Part")
		slab.Anchored = true; slab.CanCollide = false; slab.CanQuery = false; slab.CanTouch = false
		slab.Material = groundMat
		slab.Color = groundColor
		slab.Size = Vector3.new(w, thick, l)

		-- 바깥쪽으로 기울어 들린 판: dir2d를 향하고 normal 기준 바깥 가장자리가 위로
		local tiltUp = math.rad(math.random(15, 45))           -- 들림 각도
		local liftedY = normal * math.random(8, 22) / 10       -- 살짝 떠오른 높이
		local pos = sPos + dir2d * dist + liftedY
		local faceCF = CFrame.lookAt(pos, pos + dir2d, normal) -- 길이축이 바깥 방향
		slab.CFrame = faceCF * CFrame.Angles(tiltUp, 0, 0)     -- 바깥 가장자리 들어올림

		-- 솟아오르는 애니메이션: 땅속에서 올라옴
		local finalCF = slab.CFrame
		slab.CFrame = finalCF * CFrame.new(0, 0, 0) - normal * 3
		slab.Transparency = 1
		local upTI = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(slab, upTI, { CFrame = finalCF, Transparency = 0 }):Play()
		slab.Parent = parent

		-- 잠시 후 가라앉으며 사라짐
		task.delay(1.4 + math.random() * 0.6, function()
			if slab.Parent then
				TweenService:Create(slab, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = finalCF - normal * 4, Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(slab, 2.8)
	end

	-- (B) 바깥으로 튀어나가는 물리 파편 (작은~중간 조각)
	local shardCount = math.random(6, 10)
	for i = 1, shardCount do
		local ang = math.random() * math.pi * 2
		local dir2d = (tangent * math.cos(ang) + bitangent * math.sin(ang)).Unit
		local w = math.random(15, 35) / 10
		local l = math.random(25, 55) / 10
		local shard = Instance.new("Part")
		shard.Anchored = false
		shard.CanCollide = false
		shard.Material = groundMat
		shard.Color = groundColor
		shard.Size = Vector3.new(w, math.random(3, 6) / 10, l)  -- 납작한 판자형
		shard.CFrame = CFrame.new(sPos + dir2d * math.random(10, 30)/10 + normal * 1)
			* CFrame.Angles(math.random()*6, math.random()*6, math.random()*6)
		shard.Parent = parent
		local launch = normal * math.random(22, 40) + dir2d * math.random(8, 18)
		shard.AssemblyLinearVelocity = launch
		shard.AssemblyAngularVelocity = Vector3.new(math.random()*12-6, math.random()*12-6, math.random()*12-6)
		Debris:AddItem(shard, 1.8)
	end

	-- ── 4) 입자 분출 (Emit 기반 — 충격 순간 터지는 입자감) ──
	local emitterPart = Instance.new("Part")
	emitterPart.Size = Vector3.new(0.1, 0.1, 0.1)
	emitterPart.CFrame = CFrame.new(sPos + normal * 0.5)
	emitterPart.Anchored = true; emitterPart.CanCollide = false; emitterPart.CanQuery = false; emitterPart.Transparency = 1
	emitterPart.Parent = parent

	-- (a) 흙먼지: 무겁게 퍼지고 가라앉음
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.5, 1.1)
	dust.Speed = NumberRange.new(12, 26)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Acceleration = Vector3.new(0, -35, 0)
	dust.Color = ColorSequence.new(Color3.fromRGB(120, 88, 58), Color3.fromRGB(70, 50, 32))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-90, 90)
	dust.Parent = emitterPart
	dust:Emit(20)

	-- (b) 보라 스파크: 빠르게 사방으로 튀는 가는 입자 (전기/에너지 느낌)
	local spark = Instance.new("ParticleEmitter")
	spark.Rate = 0
	spark.Lifetime = NumberRange.new(0.2, 0.5)
	spark.Speed = NumberRange.new(40, 75)
	spark.SpreadAngle = Vector2.new(180, 180)
	spark.Acceleration = Vector3.new(0, -20, 0)
	spark.LightEmission = 1
	spark.LightInfluence = 0
	spark.Color = ColorSequence.new(Color3.fromRGB(220, 150, 255), Color3.fromRGB(130, 50, 230))
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	spark.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	spark.Drag = 4
	spark.Parent = emitterPart
	spark:Emit(28)

	-- (c) 충격 플래시 입자: 중심에서 위로 솟구치는 밝은 코어 입자
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.25, 0.45)
	burst.Speed = NumberRange.new(18, 35)
	burst.SpreadAngle = Vector2.new(35, 35)
	burst.Acceleration = Vector3.new(0, 10, 0)
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 230, 255), Color3.fromRGB(180, 90, 255))
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.4, 4), NumberSequenceKeypoint.new(1, 0) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	burst.Parent = emitterPart
	burst:Emit(14)

	Debris:AddItem(emitterPart, 2)
end



-- ─── Purple 발사체 비행 + 충돌 ───────────────────────────────
local function flyPurple(points, taggerPlayer, parent)
	local purple = TEMPLATE.Purple:Clone()
	purple.Anchored = true
	purple.CanCollide = false
	purple.CanQuery = false
	purple.CanTouch = false
	purple.Parent = parent

	purple.Transparency = 0  -- 기존 Purple 비주얼 사용

	-- 화려한 보라 트레일 (비행 궤적)
	local ta0 = Instance.new("Attachment"); ta0.Position = Vector3.new(0,  3, 0); ta0.Parent = purple
	local ta1 = Instance.new("Attachment"); ta1.Position = Vector3.new(0, -3, 0); ta1.Parent = purple
	local trail = Instance.new("Trail")
	trail.Attachment0 = ta0
	trail.Attachment1 = ta1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.fromRGB(190, 90, 255), Color3.fromRGB(80, 20, 160))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.LightEmission = 1
	trail.Parent = purple

	-- 발사음 재생 — 2D (위치 무관 동일 볼륨)
	playSound(FIRE_SOUND_ID, 1)
	playSound(FIRE_SOUND_ID2, 1)  -- 추가 발사음 동시 재생

	local taggerChar = taggerPlayer.Character

	-- 이미 처치된 victim 추적
	local killed = {}

	local totalSegments = #points - 1
	if totalSegments < 1 then
		purple:Destroy(); return
	end

	local segmentTime = FLIGHT_DURATION / totalSegments
	for i = 1, totalSegments do
		local a, b = points[i], points[i+1]
		-- 진행 방향. 꼬리(Beam = 로컬 -X)가 뒤를 향하도록 로컬 +X = 진행방향으로 정렬
		local dir = (b - a).Unit
		local up = (Vector3.new(0,1,0) - dir * Vector3.new(0,1,0):Dot(dir))
		up = up.Magnitude > 0.01 and up.Unit or Vector3.new(0,0,1)

		purple.CFrame = CFrame.fromMatrix(a, dir, up)

		-- 이 segment 따라 짧은 tween (방향 유지)
		local t = TweenService:Create(purple,
			TweenInfo.new(segmentTime, Enum.EasingStyle.Linear),
			{ CFrame = CFrame.fromMatrix(b, dir, up) })
		t:Play()
		t.Completed:Wait()

		-- 🛡️ [2026-08-30] 경로에서 방패 검사. 명중 판정이 아니라 '지나갈 때' 본다.
		--   [왜] 예전엔 피격자를 때리는 순간에 봤는데, 그때 볼은 이미 방패를 지나친 뒤였다
		--     (실측: 방패 X=632, 피격 X=610 → 방패 기준으로 공격이 등 뒤라 판정이 뒤집힘).
		--   ⚠️ 막히면 잠깐 멈췄다가 사라진다. 발사체(스피어·데몬스피어·에너지볼)는
		--     '방패에 꽂혀 소멸'이 자연스럽다 — 굴리기·쓰나미와 규칙이 다른 건 의도다.
		--     굴리기는 실물이 튕겨 나가고, 쓰나미는 광역이라 계속 흐른다.
		if _G.WoodShieldBlockAt and _G.WoodShieldBlockAt(b, dir) then
			print("⚡ EnergyBall → 방패에 막힘")
			task.wait(EB_STALL_TIME)
			local fade = TweenService:Create(purple, TweenInfo.new(0.3), { Transparency = 1 })
			fade:Play()
			Debris:AddItem(purple, 0.4)
			return
		end

		-- 땅 파임 크레이터 (일정 간격마다)
		if i % SCORCH_EVERY == 0 then
			createScorch(b, parent)
		end

		-- 도착 지점에서 충돌 검사 (반경 HIT_RADIUS 안 캐릭터들)
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { taggerChar }
		local hits = workspace:GetPartBoundsInRadius(b, HIT_RADIUS, op)
		for _, hp in ipairs(hits) do
			local model = hp:FindFirstAncestorOfClass("Model")
			-- ⚠️ 태거 베이스 안이면 면역
			if model and model:FindFirstChildOfClass("Humanoid")
			   and not isInTaggerBase(model) and not killed[model] then
				killed[model] = true
				-- ⚠️ [2026-08-30] 방패 차단은 여기가 아니라 위 '경로 검사'가 담당한다.
				--   여기서 보면 볼이 이미 방패를 지나친 뒤라 판정이 뒤집힌다.
				do
				-- 즉사 처리
				if _G.processHit then
					local dummy = Instance.new("Part")
					dummy.Name = "EnergyBallHitter"
					dummy.Anchored = true
					dummy.CanCollide = false
					dummy.Transparency = 1
					dummy.Position = purple.Position
					dummy.Parent = workspace
					Debris:AddItem(dummy, 1)
					-- ⚠️ [수정 2026-08-26] 결과를 확인하고 찍는다.
					--   [기존] pcall 뒤에 무조건 "즉사" 를 출력했다. 내구도가 막아도
					--     똑같이 찍혀, 로그만 보면 3명을 죽인 것처럼 읽혔다.
					--     (실측 13:11:50 — 내구도 소모 3건과 '즉사' 3건이 같은 시각에
					--      찍혔고, 셋 다 36초 뒤에야 실제로 다운됐다)
					--   [왜 중요] 로그가 실제와 다르게 말하면 밸런스 판단이 통째로 틀어진다.
					--     오늘 마법책 무음 문제와 같은 유형이다.
					local before = model:GetAttribute("Durability") or 0
					pcall(function() _G.processHit(model, dummy) end)
					local after = model:GetAttribute("Durability") or 0
					if after < before then
						print(string.format("⚡ [EnergyBall] 내구도로 막힘 → %s (남은 %d)",
							model.Name, after))
					else
						print(string.format("⚡ [EnergyBall] 명중 → %s", model.Name))
					end
				else
					-- fallback
					local hum = model:FindFirstChildOfClass("Humanoid")
					if hum then hum.Health = 0 end
				end
				end   -- 🛡️ WoodShieldBlocks else 닫기
			end
		end
	end

	-- 도착 후 Purple 페이드 + 제거
	local fade = TweenService:Create(purple, TweenInfo.new(0.3), { Transparency = 1 })
	fade:Play()
	Debris:AddItem(purple, 0.4)
end

-- ─── Public: 발사 트리거 ──────────────────────────────────────
-- ⚠️ [2026-08-27] 반환값 규약: 수락 true / 거부 false. 그리고 즉시 반환한다.
--   [증상] 에너지볼이 연속 2발 이상 나갔다. 12초 쿨이 통째로 무시됨.
--     (실측 23:31 — 38.558/40.757 두 요청이 모두 통과, 42.843/45.222 두 발 발사)
--   [원인] 이 함수가 차징(1.5s) + 비행(flyPurple)까지 인라인 yield 해서 약 4.3초
--     뒤에야 복귀했다. 호출부(ItemSpawnHandler)의 쿨 기록은 복귀 '뒤'라,
--     그 4.3초 동안 쿨 슬롯이 비어 있어 재요청이 검사를 그대로 통과했다.
--     아이템 쿨(12s)뿐 아니라 전역 쿨(2s)·클라 쿨 UI 도 같이 늦어 무방비였다.
--   [해결] 동기 검증까지만 하고 즉시 반환. 차징~비행은 task.spawn 으로 분리.
--     TsunamiSystem.fireTsunami 가 이미 같은 모양이다(예고를 task.spawn 하고 즉시 return).
--   ⚠️ 거부 경로는 반드시 yield 앞에 둘 것. 뒤로 내려가면 호출부가 거부를
--     4.3초 뒤에 알게 되어 "거부 시 쿨 미소모" 처리가 늦는다.
--   ⚠️ task.spawn 은 스레드를 즉시 실행한다(첫 yield 까지 그 자리에서 진행).
--     따라서 drawWarning·chargeBalls 의 실행 시점은 분리 전과 같은 프레임이다.
local function fireEnergyBall(player, clickPosition)
	if not player or not player.Character then return false end
	local char = player.Character
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	-- VFX 컨테이너 (정리 편의)
	local container = Instance.new("Folder")
	container.Name = "EnergyBall_" .. player.Name
	container.Parent = workspace

	-- 발사 방향: 캐릭터 → 클릭 위치 수평
	local startPos = hrp.Position - Vector3.new(0, hrp.Size.Y/2, 0)
	local toClick = clickPosition - startPos
	local horizVec = Vector3.new(toClick.X, 0, toClick.Z)
	local horizDir = horizVec.Magnitude > 0.1 and horizVec.Unit or hrp.CFrame.LookVector
	-- LookVector도 수평 정규화 (위쪽 안 보게)
	if math.abs(horizDir.Y) > 0.01 then
		horizDir = Vector3.new(horizDir.X, 0, horizDir.Z).Unit
	end

	-- 경로 점들 생성
	local params = makeRayParams(player)
	-- 시작점도 표면 위로 (캐릭터 발 위치)
	local startSurface = probeSurface(startPos, params) or (startPos + Vector3.new(0, HEIGHT_ABOVE_GROUND, 0))
	local points = { startSurface }
	-- 이후 segment들: 직전 표면 점 기준으로 누적 추적 (경사 하강도 따라감)
	local lastPt = startSurface
	for i = 1, SEGMENT_COUNT do
		local nextXZ = lastPt + horizDir * STEP_LEN  -- 직전 점에서 한 칸 전진 (Y는 직전 표면 높이)
		local pt = probeSurface(nextXZ, params)
		if pt then
			table.insert(points, pt)
			lastPt = pt
		else
			break
		end
	end

	if #points < 2 then
		container:Destroy()
		print("⚡ EnergyBall: 표면 추적 실패")
		return false
	end

	-- ⚠️ 여기부터는 비동기. 호출부가 쿨을 '요청 시점'에 기록할 수 있게 하기 위함이다.
	--   위쪽 동기 검증(캐릭터/HRP/표면추적)이 끝났으므로 이 지점 = 발사 확정이다.
	task.spawn(function()
		-- 경고선 표시
		local warningSegs = drawWarning(points, container)

		-- Red/Blue charging (발사 방향 수직 좌우로 모음)
		local red, blue, mergeSound = chargeBalls(char, WARNING_DURATION, horizDir)

		-- 차징 완료 대기
		task.wait(WARNING_DURATION)

		-- 경고선 페이드 + 제거
		for _, s in ipairs(warningSegs) do
			local t = TweenService:Create(s, TweenInfo.new(0.2), { Transparency = 1 })
			t:Play()
			Debris:AddItem(s, 0.3)
		end
		-- Red/Blue 제거
		if red then Debris:AddItem(red, 0.1) end
		if blue then Debris:AddItem(blue, 0.1) end

		-- 합체음 끊기 (발사 시점)
		if mergeSound then
			mergeSound:Stop()
			mergeSound:Destroy()
		end

		-- Purple 발사
		flyPurple(points, player, container)

		-- 컨테이너 정리
		Debris:AddItem(container, 2)
		print(string.format("⚡ %s EnergyBall 발사 → %d segments, %.0f stud", player.Name, #points-1, (#points-1)*STEP_LEN))
	end)

	return true
end
_G.fireEnergyBall = fireEnergyBall

print("✅ EnergyBallSystem ready (레일건 + hill 표면 추적)")
