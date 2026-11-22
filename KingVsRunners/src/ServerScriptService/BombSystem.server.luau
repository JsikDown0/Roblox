-- BombSystem: TNT 폭탄 태거 아이템
-- 흐름: 클라이언트가 탑뷰에서 타겟 클릭 → 빨강 경사 원 5초 → AC-130 등장 → TNT 투하 → 폭발 + 사운드 + 화재 잔류

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

-- ─── Tunables ────────────────────────────────────────────────
local WARNING_DURATION   = 5     -- 빨강 원형 경고 표시 시간 (초)
-- ⚠️ 경고 원 "공개 시점" — 연출 시간과 정보 공개를 분리하기 위한 값.
-- 이전에는 시전 즉시(t=0) 원이 뜨고 폭발이 t=12.75 라, 러너가 반경 70을 빠져나올 시간이
-- 3배 넘게 남았다(중심에서 탈출에 3.5~4.4초). 실질적으로 아무도 안 맞는 상태였다.
-- → AC-130 비행 연출은 그대로 두고, 원은 투하 직전에만 띄운다.
--   반응 창 = WARNING_LEAD_TIME + BOMB_FALL_DURATION (기본 0.5 + 1.5 = 2.0초)
--   중심 부근(70스터드 필요)은 못 빠져나가고, 가장자리는 살아남는 구배가 생긴다.
--   더 강하게 하려면 0으로(=1.5초), 더 약하게 하려면 값을 키운다.
local WARNING_LEAD_TIME  = 0.5   -- 투하 몇 초 전에 경고 원을 띄울지
local WARNING_RADIUS     = 75    -- 폭격 시각 반경 (stud) = 즉사 반경과 일치시킴
-- ⚠️ 이전 70 → 75. 즉사 반경이 75인데 경고가 70이라 "원 밖 5스터드가 죽는" 구간이 있었다.
-- 경고 창이 12.75초일 땐 아무도 체감 못 했지만, 반응 창을 2초로 줄이면
-- "간신히 원을 벗어났는데 죽었다"가 잦아진다 — 학습 불가능한 죽음이라 불만으로 직결된다.
-- 봇 회피도 경고 원 기준으로 판단하므로(RunnerBotDriveController), 봇/사람 판단 근거가 같아진다.
local KILL_RADIUS        = 75    -- 실제 즉사 반경
local BOMB_DROP_HEIGHT   = 250   -- AC-130 / TNT 시작 고도
local BOMB_FALL_DURATION = 1.5   -- TNT 낙하 시간 (초)
local AC130_FLYBY_SPEED  = 80    -- AC-130 비행 속도 (stud/sec)
local AC130_FLYBY_OFFSET = 500   -- AC-130 등장/퇴장 거리
local POST_EXPLOSION_DELAY = 2   -- 폭발 후 2차 사운드 + random explosion 등장 지연 (초)
local FIRE_AFTERMATH_DURATION = 10  -- 화재 잔류 효과 지속 시간 (초)
local FIRE_AFTERMATH_INTERVAL_MIN = 0.35  -- 화재 이펙트 spawn 최소 간격
local FIRE_AFTERMATH_INTERVAL_MAX = 0.7   -- 화재 이펙트 spawn 최대 간격
local FIRE_AFTERMATH_LIFETIME_MIN = 0.8   -- 각 화재 이펙트 수명 최소
local FIRE_AFTERMATH_LIFETIME_MAX = 1.5   -- 각 화재 이펙트 수명 최대
local FIRE_AFTERMATH_Y_TOLERANCE = 12  -- ground hit Y가 폭격 Y에서 이만큼 떨어지면 skip (바위 위 방지)
-- 잔불 화상 데미지 (영역 안에 있는 Runner에게 지속 데미지)
local BURN_TICK_INTERVAL  = 0.5   -- 데미지 tick 간격 (초)
local BURN_DAMAGE_PER_TICK = 8    -- tick당 데미지량

-- 🛡️ 태거 베이스 안의 러너는 태거 아이템에 당하지 않는다.
-- ⚠️ [2026-08-28] 판정을 _G.IsCharInTaggerBase 로 일원화했다. 여기서 복사하지 말 것.
--   원본은 ItemSpawnHandler 에 있다(높이 밴드·캐시 무효화·showBaseImmune 포함).
local function isInTaggerBase(model)
	return _G.IsCharInTaggerBase(model)
end
local BURN_RADIUS_USES_WARNING = true  -- true면 WARNING_RADIUS 사용 (사용자 요청: 기존 경고 영역 재활용)

-- Sound asset IDs
local SOUND_EXPLODE         = "rbxassetid://73247208240625"   -- 1차 폭발 (TNT 착탄)
local SOUND_POST_EXPLODE    = "rbxassetid://110947043486538"  -- 2차 (+2초)
local SOUND_TNT_FALL        = "rbxassetid://127858554543866"  -- TNT 낙하 중 looping
local SOUND_AC130_ENGINE    = "rbxassetid://89508159592753"   -- AC-130 비행 중 looping

-- ─── 템플릿 참조 ─────────────────────────────────────────────
local taggerItems   = ServerStorage:WaitForChild("TaggerItem")
local tntFolder     = taggerItems:WaitForChild("tnt")
local tntTemplate   = tntFolder:WaitForChild("Tsar bombar")
local ac130Folder   = ServerStorage:WaitForChild("AC-130")
local ac130Template = ac130Folder.Model:WaitForChild("AC130")
local explosionsFolder    = ServerStorage:WaitForChild("Explosions")
local randomExplosionTpl  = explosionsFolder:WaitForChild("random explosion ")  -- 이름 끝 공백 주의
local explosion2Template  = explosionsFolder:WaitForChild("Explosion effect2")
local firstBombVfxTemplate = explosionsFolder:WaitForChild("first bomb vfx")

-- ─── RemoteEvents ────────────────────────────────────────────
local bombEnterEvent   = ReplicatedStorage:WaitForChild("BombEnterTargeting")
local bombTargetEvent  = ReplicatedStorage:WaitForChild("BombTargetConfirmed")
local bombCancelEvent  = ReplicatedStorage:WaitForChild("BombCancelTargeting")

-- 진행 중인 폭격 추적 (플레이어별 중복 방지)
local activeBombs = {}

-- ─────────────────────────────────────────────────────────────
-- 헬퍼: 위치에서 ground normal 얻기 (raycast)
-- ─────────────────────────────────────────────────────────────
local function getGroundInfo(pos, ignoreList)
	local rayOrigin = pos + Vector3.new(0, 50, 0)
	local rayDir = Vector3.new(0, -200, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	local result = workspace:Raycast(rayOrigin, rayDir, params)
	if result then
		return result.Position, result.Normal
	end
	return pos, Vector3.yAxis
end

-- ─────────────────────────────────────────────────────────────
-- 헬퍼: ground normal에 맞춘 CFrame 생성 (Cylinder 평면을 slope에 정렬)
-- Cylinder는 local +X 축으로 높이가 뻗으므로, local +X = normal 방향이 되도록 한다.
-- ─────────────────────────────────────────────────────────────
local function cframeFromNormal(centerPos, normal)
	local up = normal.Unit
	local arbitrary = math.abs(up.Y) < 0.99 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	local right = up:Cross(arbitrary).Unit
	local fwd = up:Cross(right).Unit
	-- CFrame.fromMatrix(pos, vX, vY, vZ) — vX = local +X, vY = local +Y, vZ = local +Z
	return CFrame.fromMatrix(centerPos, up, right, fwd)
end

-- ─────────────────────────────────────────────────────────────
-- 헬퍼: 3D 위치 사운드 재생 (Part에 Sound 부착 → 자동 정리)
-- sessionSounds 배열이 주어지면 트래킹 (aftermath 종료 시 강제 정리용)
-- ─────────────────────────────────────────────────────────────
local function playPositional(soundId, pos, volume, rollOffMax, sessionSounds)
	local soundPart = Instance.new("Part")
	soundPart.Name = "_BombSound"
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Transparency = 1
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.Position = pos
	soundPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 50
	sound.RollOffMaxDistance = rollOffMax or 600
	sound.Parent = soundPart
	sound:Play()

	sound.Ended:Connect(function()
		soundPart:Destroy()
	end)
	Debris:AddItem(soundPart, 30)  -- 안전망

	if sessionSounds then
		table.insert(sessionSounds, soundPart)
	end
	return soundPart
end

-- ─────────────────────────────────────────────────────────────
-- 헬퍼: looping sound를 part에 직접 부착 (engine / fall 효과음)
-- 부모 part가 destroy되면 자동으로 사라짐
-- ─────────────────────────────────────────────────────────────
local function attachLoopingSound(part, soundId, volume, rollOffMax, sessionSounds)
	if not part then return nil end
	local sound = Instance.new("Sound")
	sound.Name = "_BombLoopSound"
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 50
	sound.RollOffMaxDistance = rollOffMax or 600
	sound.Parent = part
	sound:Play()
	if sessionSounds then
		table.insert(sessionSounds, sound)
	end
	return sound
end

-- ─────────────────────────────────────────────────────────────
-- 빨강 원형 경고 (slope에 맞춰 기울어짐)
-- ─────────────────────────────────────────────────────────────
local function createWarningCircle(targetPos)
	local groundPos, normal = getGroundInfo(targetPos)

	local circle = Instance.new("Part")
	circle.Name = "_BombWarning"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.5, WARNING_RADIUS * 2, WARNING_RADIUS * 2)
	circle.CFrame = cframeFromNormal(groundPos + normal * 0.3, normal)
	circle.Anchored = true
	circle.CanCollide = false
	circle.Material = Enum.Material.Neon
	circle.Color = Color3.fromRGB(255, 30, 30)
	circle.Transparency = 0.3
	circle.Parent = workspace
	-- 안전망: 폭발이 어떤 이유로 일어나지 않아도 30초 후 강제 제거
	Debris:AddItem(circle, 30)

	-- 깜빡임 효과 (외부에서 destroy할 때까지 계속)
	task.spawn(function()
		local t = 0
		while circle.Parent do
			local intensity = (math.sin(t * 8) + 1) / 2
			circle.Transparency = 0.2 + intensity * 0.4
			t = t + RunService.Heartbeat:Wait()
		end
	end)

	return circle
end

-- ─────────────────────────────────────────────────────────────
-- 화재 잔류 효과: Explosion effect2를 영역 내 무작위 위치에 반복 spawn
-- ─────────────────────────────────────────────────────────────
local function spawnFireAftermath(centerPos, radius, duration)
	task.spawn(function()
		local endTime = tick() + duration
		while tick() < endTime do
			-- 무작위 offset (반경의 80% 내)
			local angle = math.random() * math.pi * 2
			local r = math.random() * radius * 0.85
			local pos = centerPos + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)

			-- 해당 위치 ground raycast
			-- 위에서 시작해서 아래로 충분히 길게 (바위/나무를 통과해서 진짜 ground까지)
			local rayOrigin = pos + Vector3.new(0, 80, 0)
			local rayDir = Vector3.new(0, -300, 0)
			local result = workspace:Raycast(rayOrigin, rayDir)

			-- ground hit Y가 폭격 Y와 너무 다르면 skip (바위/나무 위에 떠있는 거 방지)
			if result and math.abs(result.Position.Y - centerPos.Y) <= FIRE_AFTERMATH_Y_TOLERANCE then
				local groundPos = result.Position

				local fx = explosion2Template:Clone()
				fx.Anchored = true
				fx.CanCollide = false
				fx.Transparency = 1
				fx.Position = groundPos + Vector3.new(0, 1, 0)
				fx.Parent = workspace

				for _, d in ipairs(fx:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d.Enabled = true
					end
				end

				local lifetime = FIRE_AFTERMATH_LIFETIME_MIN + math.random() * (FIRE_AFTERMATH_LIFETIME_MAX - FIRE_AFTERMATH_LIFETIME_MIN)
				Debris:AddItem(fx, lifetime)
			end
			-- skip된 경우에도 interval은 동일하게 진행 (총 spawn 빈도 안정)

			local interval = FIRE_AFTERMATH_INTERVAL_MIN + math.random() * (FIRE_AFTERMATH_INTERVAL_MAX - FIRE_AFTERMATH_INTERVAL_MIN)
			task.wait(interval)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- 잔불 화상 데미지 루프 (영역 안에 있는 Runner에게 지속 데미지)
-- 시각 표시는 없고 (사용자 요청), 기존 경고 반경 재활용
-- ─────────────────────────────────────────────────────────────
local function applyBurnDamageLoop(centerPos, radius, duration)
	task.spawn(function()
		local endTime = tick() + duration
		while tick() < endTime do
			-- 플레이어 Runner 검사
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("Role") == "Runner" then
					local char = p.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if hum and root and hum.Health > 0 then
						local dist = (root.Position - centerPos).Magnitude
						-- Y는 비교 안 함 (수평 거리만 보고 싶지만 일단 3D 거리, 잔불은 작은 범위라 OK)
						-- ⚠️ 태거 베이스 안이면 면역
						if dist <= radius and not isInTaggerBase(char) then
							if not (_G.isInvincible and _G.isInvincible(char)) then  -- 산데비스탄 i-frame
								hum:TakeDamage(BURN_DAMAGE_PER_TICK)
							end
						end
					end
				end
			end
			-- NPC Runner도 동일 처리
			for _, char in ipairs(workspace:GetChildren()) do
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local isPlayerChar = Players:GetPlayerFromCharacter(char) ~= nil
					if not isPlayerChar then
						local root = char:FindFirstChild("HumanoidRootPart")
						if root and (root.Position - centerPos).Magnitude <= radius
						   and not isInTaggerBase(char) then
							hum:TakeDamage(BURN_DAMAGE_PER_TICK)
						end
					end
				end
			end
			task.wait(BURN_TICK_INTERVAL)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- one-shot VFX clone 헬퍼: ParticleEmitter 활성화 → 일정 시간 후 Debris 정리
-- ─────────────────────────────────────────────────────────────
local function spawnOneShotVFX(template, pos, lifetime)
	local clone = template:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.Transparency = 1
	clone.Position = pos
	clone.Parent = workspace
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ParticleEmitter") then d.Enabled = true end
	end
	Debris:AddItem(clone, lifetime)
	return clone
end

-- ─────────────────────────────────────────────────────────────
-- 폭발: 즉사 + 사운드 + Roblox Explosion + first bomb vfx + 2초 후 random explosion + 화재 잔류
-- warningCircle은 폭발과 동시에 정리 (TNT 착탄 직전까지 표시 유지)
-- sessionSounds: 전체 시퀀스에서 트래킹 중인 사운드 (cleanup용)
-- ─────────────────────────────────────────────────────────────
local function explodeAtPosition(pos, warningCircle, sessionSounds)
	-- 0. 경고 원 제거 (TNT가 착탄한 순간)
	if warningCircle and warningCircle.Parent then
		warningCircle:Destroy()
	end

	-- 1. 1차 폭발 사운드
	playPositional(SOUND_EXPLODE, pos, 1.5, 800, sessionSounds)

	-- 2. Roblox 내장 Explosion (시각 효과)
	local explosion = Instance.new("Explosion")
	explosion.Position = pos
	explosion.BlastRadius = WARNING_RADIUS
	explosion.BlastPressure = 0  -- 물리 안 밀리게 (이미 즉사)
	explosion.DestroyJointRadiusPercent = 0  -- 캐릭터 분해 방지
	explosion.Parent = workspace

	-- 2.5. first bomb vfx (낙하 직후 종합 폭발 이펙트: Explosion + Shockwave + Smoke + Sparks + Debris)
	spawnOneShotVFX(firstBombVfxTemplate, pos + Vector3.new(0, 2, 0), 2.5)

	-- 3. 즉사 처리: 반경 내 Runner/NPC
	local dummyPart = Instance.new("Part")
	dummyPart.Name = "_BombDamageSource"
	dummyPart.Anchored = true
	dummyPart.CanCollide = false
	dummyPart.Transparency = 1
	dummyPart.Position = pos
	dummyPart.Parent = workspace
	Debris:AddItem(dummyPart, 1)

	-- 플레이어 Runner
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Role") == "Runner" then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (root.Position - pos).Magnitude
				-- ⚠️ 태거 베이스 안이면 면역
				if dist <= KILL_RADIUS and not isInTaggerBase(char) then
					if _G.processHit then
						_G.processHit(char, dummyPart)
						print(string.format("💥 폭격 즉사: %s (거리 %.1f)", player.Name, dist))
					else
						local hum = char:FindFirstChildOfClass("Humanoid")
						if hum then hum.Health = 0 end
					end
				end
			end
		end
	end

	-- NPC Runner
	for _, char in ipairs(workspace:GetChildren()) do
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local isPlayerChar = Players:GetPlayerFromCharacter(char) ~= nil
			if not isPlayerChar then
				local root = char:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - pos).Magnitude <= KILL_RADIUS
				   and not isInTaggerBase(char) then
					if _G.processHit then
						_G.processHit(char, dummyPart)
						print(string.format("💥 NPC 즉사: %s", char.Name))
					else
						hum.Health = 0
					end
				end
			end
		end
	end

	-- 4. 2초 후: 2차 사운드 + random explosion (단일) + 화재 잔류 시작
	task.delay(POST_EXPLOSION_DELAY, function()
		playPositional(SOUND_POST_EXPLODE, pos, 1.5, 800, sessionSounds)

		-- random explosion (큰 크레이터 시각, 단일 spawn)
		local rayOrigin = pos + Vector3.new(0, 80, 0)
		local result = workspace:Raycast(rayOrigin, Vector3.new(0, -300, 0))
		local groundPos = (result and result.Position) or pos
		spawnOneShotVFX(randomExplosionTpl, groundPos + Vector3.new(0, 1, 0), 4)

		-- Explosion effect2 무작위 등장 (화재 잔류)
		spawnFireAftermath(pos, WARNING_RADIUS, FIRE_AFTERMATH_DURATION)
		-- 잔불 화상 데미지 (시각 표시 없음, 기존 경고 반경 재활용)
		local burnRadius = BURN_RADIUS_USES_WARNING and WARNING_RADIUS or KILL_RADIUS
		applyBurnDamageLoop(pos, burnRadius, FIRE_AFTERMATH_DURATION)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- TNT 투하: dropFromPos에서 targetPos까지 떨어진 후 폭발
-- TNT에 낙하 looping 사운드 부착 → 착탄 시 tnt:Destroy()로 사운드도 자동 종료
-- ─────────────────────────────────────────────────────────────
local function dropTNT(targetPos, dropFromPos, warningCircle, sessionSounds, owner)
	local tnt = tntTemplate:Clone()
	tnt.Name = "_DroppedTNT"
	tnt.Anchored = true
	tnt.CanCollide = false
	tnt.CFrame = CFrame.new(dropFromPos)
	tnt.Parent = workspace

	-- 🎨 스킨 색 적용: Rainbow(장착) 우선 → ITEM COLOR(BombColor_Body). 단일 메시 전체 한 색.
	-- Tsar Bomba는 SurfaceAppearance(PBR)라 색이 보이려면 제거 필요 (applyFinish가 자동 제거).
	do
		local skin = owner and _G.getEquippedSkin and _G.getEquippedSkin(owner, "tnt")
		if skin == "RainbowBomb" and owner:GetAttribute("Has_RainbowBomb") == true then
			local sa = tnt:FindFirstChildWhichIsA("SurfaceAppearance")
			if sa then sa:Destroy() end
			tnt.Material = Enum.Material.Neon
			local hue = 0
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not tnt.Parent then if conn then conn:Disconnect() end return end
				hue = (hue + dt * 0.5) % 1
				tnt.Color = Color3.fromHSV(hue, 1, 1)
			end)
		elseif owner then
			local colorName = owner:GetAttribute("BombColor_Body")
			if colorName then
				local ok, palette = pcall(function()
					return require(ReplicatedStorage:WaitForChild("NoobColorPalette"))
				end)
				if ok and palette and palette.COLORS[colorName] then
					local cfg = palette.getConfig("tnt")
					local finishKey = owner:GetAttribute("BombMaterial_Body") or (cfg and cfg.materialDefault)
					palette.applyFinish(tnt, finishKey, palette.COLORS[colorName])
				end
			end
		end
	end

	-- 낙하 사운드 부착 (looping, TNT가 destroy되면 자동 종료)
	attachLoopingSound(tnt, SOUND_TNT_FALL, 1.3, 600, sessionSounds)

	-- 낙하 회전: 시작은 투하 시점 각도(모델 기본, 수평) 유지 → 낙하하며 선두가 점차 아래로 회전 →
	-- 착탄 시 nose-down(수직). 선두 끝이 지면(targetPos)에 닿도록 중심을 길이 절반만큼 위로.
	-- EasingDirection.In: 처음엔 회전이 거의 없다가 후반에 가속.
	local noseHalf = tnt.Size.Z / 2  -- 길이축(Z) 절반 = 선두~중심 거리
	local fallTween = TweenService:Create(
		tnt,
		TweenInfo.new(BOMB_FALL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{CFrame = CFrame.new(targetPos + Vector3.new(0, noseHalf, 0)) * CFrame.Angles(math.rad(-90), 0, 0)}
	)
	fallTween:Play()

	fallTween.Completed:Connect(function()
		explodeAtPosition(targetPos, warningCircle, sessionSounds)
		tnt:Destroy()  -- 부착된 fall 사운드도 함께 종료됨
	end)
end

-- ─────────────────────────────────────────────────────────────
-- AC-130 폭격기 등장 + 비행 (target 좌측 → target 위 → 우측, nose-first)
-- 엔진 사운드 부착 → plane:Destroy() 시 자동 종료
-- ─────────────────────────────────────────────────────────────
local function spawnAC130AndDropBomb(targetPos, warningCircle, sessionSounds, owner)
	local plane = ac130Template:Clone()
	plane.Name = "_BombingAC130"
	plane.Parent = workspace

	-- 엔진 looping 사운드 부착 (PrimaryPart에) — plane 사라지면 함께 종료
	if plane.PrimaryPart then
		attachLoopingSound(plane.PrimaryPart, SOUND_AC130_ENGINE, 1.2, 1200, sessionSounds)
	end

	local flyAltitude = targetPos.Y + BOMB_DROP_HEIGHT
	local startPos = Vector3.new(targetPos.X - AC130_FLYBY_OFFSET, flyAltitude, targetPos.Z)
	local endPos   = Vector3.new(targetPos.X + AC130_FLYBY_OFFSET, flyAltitude, targetPos.Z)

	-- 모델 자체의 '정면'(nose)이 +Z 방향이라 LookAt만으로는 거꾸로 (tail-first) 됨.
	-- 180° Y 회전을 추가해서 nose-first로 비행하도록 보정.
	local function buildPlaneCFrame(atPos, lookDir)
		return CFrame.lookAt(atPos, atPos + lookDir) * CFrame.Angles(0, math.rad(180), 0)
	end

	-- 초기 CFrame: 시작 위치에서 +X 방향 바라보기
	plane:PivotTo(buildPlaneCFrame(startPos, Vector3.new(1, 0, 0)))

	-- 비행 트윈
	local totalDist = (endPos - startPos).Magnitude
	local flyDuration = totalDist / AC130_FLYBY_SPEED
	local halfDuration = flyDuration / 2

	task.spawn(function()
		local startTime = tick()
		local bombDropped = false
		local warningShown = false
		while plane.Parent do
			local elapsed = tick() - startTime
			if elapsed >= flyDuration then break end
			local alpha = elapsed / flyDuration
			local pos = startPos:Lerp(endPos, alpha)
			plane:PivotTo(buildPlaneCFrame(pos, Vector3.new(1, 0, 0)))

			-- 🔴 경고 원: 투하 WARNING_LEAD_TIME 초 전에 공개 (연출과 정보 분리)
			if not warningShown and elapsed >= (halfDuration - WARNING_LEAD_TIME) then
				warningShown = true
				warningCircle = createWarningCircle(targetPos)
			end

			-- 정점(target 위) 도달 시 TNT 투하
			if not bombDropped and elapsed >= halfDuration then
				bombDropped = true
				dropTNT(targetPos, pos, warningCircle, sessionSounds, owner)
			end

			RunService.Heartbeat:Wait()
		end
		plane:Destroy()  -- 부착된 엔진 사운드도 함께 종료
	end)
end

-- ─────────────────────────────────────────────────────────────
-- 메인 폭격 시퀀스 (target 받으면 실행)
-- ─────────────────────────────────────────────────────────────
local function executeBombing(player, targetPos)
	if activeBombs[player.UserId] then
		warn("⚠️ 이미 폭격 진행 중:", player.Name)
		return
	end
	activeBombs[player.UserId] = true

	print(string.format("💣 폭격 시작 by %s | target=(%.0f, %.0f, %.0f)",
		player.Name, targetPos.X, targetPos.Y, targetPos.Z))

	-- 이번 폭격 세션의 모든 사운드 트래킹 (aftermath 끝나면 강제 정리)
	local sessionSounds = {}

	-- 1. 경고 원은 여기서 만들지 않는다 — spawnAC130AndDropBomb 안에서
	--    투하 직전(WARNING_LEAD_TIME)에 생성한다. 시전 즉시 띄우면 반응 창이 12.75초가 된다.
	local warningCircle = nil

	-- 2. 5초 후 폭격
	task.delay(WARNING_DURATION, function()
		spawnAC130AndDropBomb(targetPos, warningCircle, sessionSounds, player)

		-- 총 시퀀스 종료 시점 계산:
		-- AC-130 정점(반)까지 + TNT 낙하 + post 사운드 지연 + aftermath 지속
		local totalDuration = (AC130_FLYBY_OFFSET * 2 / AC130_FLYBY_SPEED) / 2
			+ BOMB_FALL_DURATION + POST_EXPLOSION_DELAY + FIRE_AFTERMATH_DURATION

		-- aftermath 종료 시점에 모든 잔존 사운드 강제 정리 (안전망 + 보장)
		task.delay(totalDuration + 0.5, function()
			for _, obj in ipairs(sessionSounds) do
				if obj and obj.Parent then
					obj:Destroy()
				end
			end
			activeBombs[player.UserId] = nil
	-- 🔓 [2026-08-27] UI 잠금 해제(세우는 쪽: ItemSpawnHandler tnt 분기).
	--   ⚠️ activeBombs 가 nil 이 되는 지점이 셋(투하 완료 / 취소 / 이탈)이라 전부에 붙인다.
	--     하나라도 빠지면 그 경로로 끝났을 때 TNT 가 영영 잠긴다.
	if _G.SetItemLock then _G.SetItemLock(player, "tnt", false) end
			print("🧹 폭격 시퀀스 정리 완료:", player.Name)
		end)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- 클라이언트 target 확정 이벤트
-- ─────────────────────────────────────────────────────────────
bombTargetEvent.OnServerEvent:Connect(function(player, targetPos)
	if player:GetAttribute("Role") ~= "Tagger" then
		warn("❌ 비태거가 폭격 시도:", player.Name)
		return
	end
	if typeof(targetPos) ~= "Vector3" then
		warn("❌ 잘못된 target 데이터:", player.Name)
		return
	end
	-- Hill 영역 내인지 서버 측 검증 (변조된 클라이언트 방지)
	-- map1/map2가 동시에 workspace에 존재 → target에서 가장 가까운 맵의 Hill 사용
	-- (활성 맵 = target이 찍힌 맵, 맵끼리 수천 stud 떨어짐). 이름 다름(Hill/hill2) → "hill" 포함으로 폴백.
	local hill
	do
		local bestDist = math.huge
		for _, mapFolder in ipairs(workspace:GetChildren()) do
			if mapFolder.Name:lower():find("map") then
				for _, d in ipairs(mapFolder:GetChildren()) do
					if d:IsA("BasePart") and d.Name:lower():find("hill") then
						local dist = (d.Position - targetPos).Magnitude
						if dist < bestDist then bestDist = dist; hill = d end
					end
				end
			end
		end
	end
	if not hill then
		warn("❌ Hill 객체 없음 — 폭격 거부")
		return
	end
	-- targetPos가 Hill의 OBB(Oriented Bounding Box) 내부에 있는지 확인
	local localPos = hill.CFrame:PointToObjectSpace(targetPos)
	local halfSize = hill.Size * 0.5
	local TOLERANCE = 10  -- 가장자리 약간 허용
	if math.abs(localPos.X) > halfSize.X + TOLERANCE
		or math.abs(localPos.Y) > halfSize.Y + TOLERANCE
		or math.abs(localPos.Z) > halfSize.Z + TOLERANCE then
		warn(string.format("❌ Hill 영역 밖 타겟 거부 by %s | pos=(%.0f, %.0f, %.0f)",
			player.Name, targetPos.X, targetPos.Y, targetPos.Z))
		return
	end
	-- 청사진 제거
	local blueprintName = "Blueprint_" .. player.Name
	local blueprint = workspace:FindFirstChild(blueprintName)
	if blueprint then blueprint:Destroy() end

	executeBombing(player, targetPos)
end)

-- 취소 이벤트 (필요시 청사진 정리)
bombCancelEvent.OnServerEvent:Connect(function(player)
	local blueprintName = "Blueprint_" .. player.Name
	local blueprint = workspace:FindFirstChild(blueprintName)
	if blueprint then blueprint:Destroy() end
	activeBombs[player.UserId] = nil
	-- 🔓 [2026-08-27] UI 잠금 해제(세우는 쪽: ItemSpawnHandler tnt 분기).
	--   ⚠️ activeBombs 가 nil 이 되는 지점이 셋(투하 완료 / 취소 / 이탈)이라 전부에 붙인다.
	--     하나라도 빠지면 그 경로로 끝났을 때 TNT 가 영영 잠긴다.
	if _G.SetItemLock then _G.SetItemLock(player, "tnt", false) end
end)

-- 외부 호출용
-- 💣 [2026-08-27] 반환값 도입: 성공 true / 거부 false.
--   [증상] 이전 폭격이 진행 중이면 거부되는데 ItemSpawnHandler 가 쿨(7초)을 소모했다.
--     로그 실측: "💣 TNT targeting mode triggered" 만 찍히고 "📡 진입 신호" 는 없는데
--     그 뒤 "⏱️ tnt 쿨타임 3.3초 남음" — 아무 일도 안 일어났는데 쿨만 나갔다.
--   ⚠️ tox_box 가 같은 이유로 오늘 고쳐졌다(spawnToxBox 반환값 도입).
--     "별도 시스템에 위임" 패턴은 전부 이 함정을 갖는다 — 새 위임 아이템은
--     반환값을 먼저 정할 것.
_G.startBombTargeting = function(player)
	if player:GetAttribute("Role") ~= "Tagger" then return false end
	if activeBombs[player.UserId] then return false end
	bombEnterEvent:FireClient(player)
	print("📡 폭격 타겟팅 모드 진입 신호 전송:", player.Name)
	return true
end

-- 테스트용: 위치 직접 지정으로 폭격 즉시 실행 (role 체크 없음)
_G.fireBombAt = function(player, targetPos)
	if typeof(targetPos) ~= "Vector3" then return end
	executeBombing(player, targetPos)
end

Players.PlayerRemoving:Connect(function(player)
	activeBombs[player.UserId] = nil
	-- 🔓 [2026-08-27] UI 잠금 해제(세우는 쪽: ItemSpawnHandler tnt 분기).
	--   ⚠️ activeBombs 가 nil 이 되는 지점이 셋(투하 완료 / 취소 / 이탈)이라 전부에 붙인다.
	--     하나라도 빠지면 그 경로로 끝났을 때 TNT 가 영영 잠긴다.
	if _G.SetItemLock then _G.SetItemLock(player, "tnt", false) end
end)

print(string.format("✅ BombSystem v2 활성화! (반경: warning=%d, kill=%d / 사운드 + 잔류화재 포함)",
	WARNING_RADIUS, KILL_RADIUS))
