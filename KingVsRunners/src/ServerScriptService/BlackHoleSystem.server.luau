-- BlackHoleSystem
-- 태거 트랩 아이템. 클릭한 곳으로 어둠의 구체를 포물선 던지기 →
-- 땅에 닿으면 즉시 블랙홀 활성화 → 5초간 주변 캐릭터 흡인.
-- VectorForce 기반 → NetworkOwnership과 무관하게 Player/NPC 모두 흡인.
-- 중심 도달 캐릭터는 영구 고정 (파리 끈끈이, 블랙홀 소멸 시까지).

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService    = game:GetService("RunService")
local Debris        = game:GetService("Debris")
local TweenService  = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spawnWarningEvent = ReplicatedStorage:WaitForChild("SpawnWarning")

-- ─── Tunables ─────────────────────────────────────
local PROJECTILE_SPEED  = 70
local PROJECTILE_LIFE   = 8
local SELF_HIT_GRACE    = 0.4
local PROJECTILE_SIZE = 2.8   -- 투척체 크기 (구 1.5 — 궤적 가시성 위해 상향, 트레일 폭도 비례)
local MAX_THROW_RANGE   = 600     -- 사거리 제한. 초과 시 같은 방향으로 클램프
local ARC_HEIGHT_MAX    = 80      -- 포물선 최대 호 높이 (시작점 기준)

-- 🕳️ [너프 2026-09-02] 흡인 반경 70 → 60, 이속 배수 0.4 → 0.5.
--   [왜] 중심 7 stud 에 닿으면 소멸까지 완전 무력이었다. 실측 7판에서
--     '유저가 블랙홀에 잡힌 판'과 패배가 정확히 일치했다(잡힌 5판 전패 / 안 잡힌 2판 전승).
--     데미지 0 인 제어기가 통나무의 명중률을 100% 로 만드는 통로였다.
--   ⚠️ ACTIVE_DURATION 은 6 → 5 (2026-09-02). 한때 4 로 내렸다가 6 으로 되돌린 뒤 중간값.
--     이 값은 블랙홀 수명이자 '중심 고정' 시간이다(고정은 소멸 시 일괄 해제되는 구조라
--     별도 상수가 없다). 고정만 따로 끊는 안도 검토했으나 기각했다 —
--     블랙홀은 돌고 있는데 사람만 걸어 나오는 그림이 되고, 흡인 가속도가 살아 있어
--     곧바로 재포획된다. 연출만 어긋나고 실질 자유 시간은 거의 없다.
--   ⚠️ 이 값을 더 줄이면 봇의 블랙홀→에너지볼 콤보가 깨진다. 실측 타이밍은
--     활성화 → 포획 1.7s → 콤보 발사 4.6s → 착탄 7.5s 다. 5초도 이미 빠듯하다.
local ACTIVE_DURATION   = 5
local PULL_RADIUS       = 60       -- 보라색 = 흡인 시작 반경 (약하게 끌림, 너프 전 70)
local STRONG_RADIUS     = 50       -- 풀 가속도 영역 반경 (확 끌림)
local ACCRETION_SCALE   = 1.3      -- Accretion Disk 시각 확대. 1.56이면 너무 광활 → 1.3 (직경 ~83)
_G.BLACKHOLE_PULL_RADIUS = PULL_RADIUS  -- 외부 노출 (테스트 명령어용)
local PULL_ACCEL        = 500    -- 흡인 가속도 (stud/s²). F = mass * 이 값
local PULL_WALK_FACTOR  = 0.5    -- 영향권 안 캐릭터 WalkSpeed 배수 (0.5 = 50% 감소)
local CENTER_RADIUS     = 7

local EXPAND_DURATION   = 1
local LIFT_HEIGHT       = 8
local ZONE_OFFSET       = 0.15

-- ─── State ────────────────────────────────────────
local activeHoles = {}
local affectedForces = {}    -- char → VectorForce 인스턴스
local affectedWalks = {}     -- char → original WalkSpeed (영향권 진입 시 백업)
local stuckChars = {}        -- char → { hole, origWS, origJP } (중심 도달 시 영구 고정)
local blackHoleActive = false  -- 맵에 블랙홀 1개 제한 (투척~소멸 동안 true)
-- 💸 착탄 거부 시 쿨을 환불할 대상. 맵에 하나뿐이라 단일 변수로 충분하다.
--   ⚠️ rejectLanding.deny 가 읽으므로 그보다 먼저 선언해야 한다.
local lastThrower = nil

-- 🔒 [2026-08-28] 플래그와 UI 잠금을 '한 함수'에서 같이 움직인다.
--   [증상] 쿨 표시는 끝났는데 실제로는 못 썼다. 사용자 입장에선 거짓 정보다.
--     (실측 15:20:44 / 15:20:54 / 15:22:58 — 전부 '중복 시도 거부' 직후 0.2~0.9초 뒤
--      블랙홀이 소멸했다. 즉 쿨은 진작 끝났고 홀 수명만 남아 있던 구간이다)
--   [원인] 표 쿨 7초 < 실제 점유(비행 ~2초 + 홀 수명 6초 ≈ 8초). 그 차이만큼
--     "쿨은 다 돌았는데 막히는" 2중막이 생긴다.
--   [해결] 알림 대신 UI 를 잠근다. Frost Dragon / tox_box / tnt 가 이미 쓰는 방식이다
--     (ItemSpawnHandler.LOCK_STATE_ITEMS + _G.SetItemLock).
--   ⚠️ blackHoleActive 를 직접 대입하지 말 것. 대입 지점이 4곳이라 반드시 한 곳이
--     빠지고, 잠금만 걸린 채 남으면 그 라운드 내내 블랙홀을 못 쓴다.
local function setActive(v)
	blackHoleActive = v
	if _G.SetItemLock and lastThrower then
		_G.SetItemLock(lastThrower, "BlackHole", v, v and "IN USE" or nil)
	end
end

-- ─── 템플릿 ───────────────────────────────────────
local function getTemplate()
	local tagger = ServerStorage:FindFirstChild("TaggerItem")
	return tagger and tagger:FindFirstChild("BlackHole")
end

-- ─── 표면 정렬 ────────────────────────────────────
local function alignToSurface(position, normal)
	local right = normal:Cross(Vector3.new(0, 1, 0))
	if right.Magnitude < 0.001 then
		right = normal:Cross(Vector3.new(1, 0, 0))
	end
	right = right.Unit
	local forward = right:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal, -forward)
end

-- Cylinder primitive 정렬용: local +X 축이 normal 방향이 되게
local function cframeForCylinder(centerPos, normal)
	local up = normal.Unit
	local arbitrary = math.abs(up.Y) < 0.99 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	local right = up:Cross(arbitrary).Unit
	local fwd = up:Cross(right).Unit
	return CFrame.fromMatrix(centerPos, up, right, fwd)
end

-- ─── VectorForce 관리 ─────────────────────────────
local function ensureForce(char, hrp)
	local existing = affectedForces[char]
	if existing and existing.Parent then return existing end

	local attach = hrp:FindFirstChild("BlackHolePullAttachment")
		or hrp:FindFirstChild("RootAttachment")
	if not attach then
		attach = Instance.new("Attachment")
		attach.Name = "BlackHolePullAttachment"
		attach.Parent = hrp
	end

	local force = Instance.new("VectorForce")
	force.Name = "BlackHolePullForce"
	force.Attachment0 = attach
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.zero
	force.Parent = hrp
	affectedForces[char] = force
	return force
end

local function clearForce(char)
	local f = affectedForces[char]
	if f and f.Parent then f:Destroy() end
	affectedForces[char] = nil
end

-- 🩸 [버그수정 2026-09-04] 이동 상태 복원은 반드시 이 함수를 통한다.
--   [증상] 블랙홀에 잡힌 채로 다운됐다가 홀이 소멸하면, 다운인데도 이동 속도가
--     다운 감속(25%)이 아니라 원래 속도(16)로 돌아왔다(실측 15:17:46 판).
--   [원인] origWS 는 '블랙홀에 잡히기 전' 값이다. 잡혀 있는 동안 DownSystem 이
--     WalkSpeed 를 4 로 낮췄는데, 해제할 때 그걸 모르고 16 으로 덮어썼다.
--   [규칙] 다운 중이면 아무것도 되돌리지 않는다. DownSystem 이 자기 복원을
--     완전히 책임진다(DownSystem:581 — WalkSpeed·JumpPower·AutoRotate 전부).
--     남의 시스템이 세운 상태를 지우지 않는 게 원칙이다.
--   ⚠️ 복원 지점이 세 곳이라(releaseStuck / 홀 0개 정리 / 영향권 이탈) 한 곳만
--     고치면 나머지가 살아남는다. 09-01 문서의 "같은 규칙이 두 곳에" 함정이라
--     헬퍼로 묶어 세 곳이 같은 규칙을 쓰게 한다.
local function restoreMovement(hum, origWS, origJP)
	if not (hum and hum.Parent) then return end
	local ch = hum.Parent
	if ch and ch:GetAttribute("Downed") then return end   -- DownSystem 소관
	hum.WalkSpeed = origWS
	if origJP then hum.JumpPower = origJP end
end

-- ─── Stuck 캐릭터 해제 ────────────────────────────
local function releaseStuck(char)
	local info = stuckChars[char]
	if not info then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = hum and hum.RootPart
	restoreMovement(hum, info.origWS, info.origJP)
	if hrp then
		hrp.Anchored = false
		-- 안전망: 소멸 시점 위치가 지형 아래(관통 흡입 잔재)면 표면 위로 끌어올려 추락사 방지
		if hrp.Position.Y < -10 then
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { char }
			local r = workspace:Raycast(hrp.Position + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), rp)
			if r then
				hrp.CFrame = CFrame.new(r.Position + Vector3.new(0, 4, 0))
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
	stuckChars[char] = nil
end

-- ─── 발사체 던지기 ────────────────────────────────
-- 🕳️ [2026-08-28] "이 파트는 관통한다" 공용 판정 — Touched / 레이 두 경로가 같이 쓴다.
--   [왜 함수로 뽑나] 두 경로가 관통 조건 3개(CanCollide / TaggerItems / Transparency)를
--     각자 복사해 갖고 있었다. 조건이 늘 때마다 한쪽만 고쳐진다.
--   ⚠️ 앞으로 관통 조건은 전부 여기에만 추가할 것.
local function passThrough(inst)
	if typeof(inst) ~= "Instance" then return true end
	-- 비물리 파트(파도·픽업·이펙트·고스트)
	if not inst.CanCollide then return true end
	-- 다른 태거 아이템(돌·통나무 등) — 자기 아이템 오폭 방지
	if inst.CollisionGroup == "TaggerItems" then return true end
	-- 투명 경계벽(TaggerWall 등) — 허공 폭발 방지
	if inst.Transparency >= 0.9 then return true end
	-- 🧱 성문·바리케이드는 '태거 자기 벽'이다. 넘어서 던지는 게 정상 플레이다.
	--   [증상] 1단계 내내 블랙홀이 전부 씹혔다. 실측 13:49:41~13:50:22 투척 13발이
	--     비행 0.5~1.0초 만에 거부됐고(멀리 던졌으면 나올 수 없는 시간),
	--     13:50:24.9 바리케이드 파괴 직후 첫 투척(13:50:26)이 바로 성공했다.
	--   [예전엔] 거부(소멸) 처리였다. 그래서 아이템이 1단계에 무용지물이었다.
	--   [지금] 관통시킨다. "성문 위 공중에 블랙홀이 열린다"는 원래 문제도
	--     같이 해결된다 — 거기서 멈추질 않으므로.
	if _G.IsGateStructure and _G.IsGateStructure(inst) then return true end
	return false
end

-- 🚫 [2026-08-28] 착탄 거부 규칙 — Touched / 레이캐스트 두 경로가 '같은 함수'를 쓴다.
--   [왜 함수로 뽑나] 두 경로가 규칙을 각자 들고 있었다. 레이 경로 주석엔
--     "Touched와 동일 규칙"이라 적혀 있었지만 실제로는 관통 조건 3개만 복사돼 있어,
--     베이스 가드가 한쪽에만 걸렸다. 새 조건을 넣을 때마다 같은 실수가 반복된다.
--   ⚠️ 앞으로 착탄 거부 조건은 전부 여기에만 추가할 것.
--   ⚠️ blackHoleActive 를 반드시 풀어야 한다. 안 풀면 '중복 시도 거부'가 걸린 채
--     남아 그 라운드 내내 블랙홀을 못 쓴다.
-- 반환: true = 거부됨(호출부는 즉시 return)
local function rejectLanding(hitPos, hitInstance, proj)
	local function deny(reason, notice)
		print("🚫 [BlackHole] " .. reason .. " — 활성화 안 함")
		if proj and proj.Parent then proj:Destroy() end
		setActive(false)
		-- 💸 [2026-08-28] 착탄 거부는 '쿨을 소모할 이유가 없다'.
		--   [증상] map1 에서 성문 거부 3연발이 각각 7초 쿨을 먹어 21초를 날렸다
		--     (실측 12:53:41 / 49.5 / 56.9 — 전부 성문 착탄).
		--   [왜 반환값으로 못 하나] 이 거부는 '비행 후 착탄' 시점이라
		--     spawnBlackHole 은 이미 true 를 돌려주고 쿨이 시작된 뒤다.
		--     던지기 전 거부(중복 시도)는 반환값 규약이 담당한다 — 그건 별개다.
		if _G.RefundItemCooldown and lastThrower then
			_G.RefundItemCooldown(lastThrower, "BlackHole")
		end
		-- 📢 거부 사유를 화면에 알린다. 피드백이 없으면 "던졌는데 아무 일도 안 남" =
		--    버그로 읽힌다(①을 처음 되돌린 이유가 정확히 이것이었다).
		if notice and lastThrower then
			pcall(function() spawnWarningEvent:FireClient(lastThrower, notice) end)
		end
		return true
	end

	-- ① 태거 베이스 착탄 — 거부한다.
	--   [원칙] 베이스는 "푸시툴로만 대항하는 결투 구역"이라 태거 아이템 반입 금지다.
	--     ItemSpawnHandler 는 '클릭 좌표'로 이미 막지만(🚫 태거 베이스 구역 소환 금지),
	--     블랙홀은 포물선이라 클릭이 통과해도 착탄이 베이스에 떨어질 수 있다.
	--     (실측 13:31:18 목표 X 709.9(플레이트 경계) → 착탄 taggerbase 721,
	--      13:31:50 목표 X 870.9(성 너머) → 착탄 taggerbase 828)
	--   [이력] 2026-08-28 오전에 한 번 되돌렸었다. 그때 되돌린 이유는 두 가지였고
	--     지금은 둘 다 해소됐다:
	--       · 쿨을 그대로 먹었다      → deny 가 RefundItemCooldown 으로 환불한다
	--       · 사용자 피드백이 없었다  → deny 가 notice 를 띄운다
	--   ⚠️ 그래도 '정상 투척 대량 거부' 위험은 남아 있다. 태거는 베이스 위(X≈780)에서
	--     던지므로, 짧게 던지면 발밑 베이스에 떨어져 거부가 기본 동작이 될 수 있다.
	--     한 판 돌려 거부 빈도를 확인할 것. 과하면 관통 거리(자폭 방지)를 늘리는 쪽으로
	--     조정한다 — 조건을 다시 지우지 말고.
	if _G.IsOnTaggerBase and _G.IsOnTaggerBase(hitPos) then
		return deny("태거 베이스 착탄", "Can't summon inside the castle")
	end
	--   ⚠️ 흡인 면제(러너 위치 기준)는 이 거부와 별개로 계속 유지한다.
	--     밖에서 열린 블랙홀이 베이스 안 러너를 끌어당기는 걸 막는 장치다.
	--     activateBlackHole 아래 stuck 루프의 IsOnTaggerBase 참조.

	-- ② 성문·바리케이드 구조물
	--   [증상] 성문 위에 붙어 공중(Y 214)에 블랙홀이 열렸다
	--     (실측 09:46~09:47 map1 — Gatehouse 착탄 4회).
	--   [왜 ①로 안 걸렸나] 성문은 taggerbase 파트 밖에 서 있는 별도 구조물이라
	--     좌표 판정을 통과한다. 맞은 '인스턴스'로 봐야 한다.
	--   ⚠️ [2026-08-28] 판정을 _G.IsGateStructure 로 일원화했다. 여기서 복사하지 말 것 —
	--     원본은 BarricadeSystem 에 있고, 프드 얼음 생성도 같은 함수를 쓴다.
	-- ② 성문·바리케이드 — ⚠️ 여기서 거부하지 않는다. passThrough 가 관통시킨다.
	--   [이력] 거부 처리였다가 2026-08-28 관통으로 바꿨다. 거부하면 바리케이드가
	--     서 있는 1단계 내내 블랙홀이 통째로 막힌다(실측 투척 13발 전멸).
	--   ⚠️ 되돌리지 말 것. "성문 위 공중에 열림" 문제는 관통으로 이미 해결된다.
	return false
end

local function throwProjectile(player, targetPos)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local startPos = hrp.Position + Vector3.new(0, 2, 0)
	local toTarget = targetPos - startPos
	local horizDist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
	local horizDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	if horizDir.Magnitude > 0.1 then horizDir = horizDir.Unit else horizDir = hrp.CFrame.LookVector end

	-- 사거리 제한: MAX_THROW_RANGE 초과 시 같은 방향으로 클램프
	if horizDist > MAX_THROW_RANGE then
		local clampedHoriz = horizDir * MAX_THROW_RANGE
		targetPos = startPos + clampedHoriz + Vector3.new(0, toTarget.Y * (MAX_THROW_RANGE/horizDist), 0)
		toTarget = targetPos - startPos
		horizDist = MAX_THROW_RANGE
	end

	-- 평탄한 포물선: apex 높이를 거리에 비례하되 ARC_HEIGHT_MAX로 cap
	-- vY = sqrt(2*g*apex). 너무 솟구치지 않게 cap.
	local arcHeight = math.clamp(horizDist * 0.25, 8, ARC_HEIGHT_MAX)
	local g = workspace.Gravity
	local vY = math.sqrt(2 * g * arcHeight)

	-- 도달 시간: y(t) = vY*t - 0.5*g*t² = toTarget.Y
	-- → 0.5*g*t² - vY*t + toTarget.Y = 0 → t = (vY + sqrt(vY² - 2g*Δy)) / g
	local disc = vY * vY - 2 * g * toTarget.Y
	local travelTime
	if disc >= 0 then
		travelTime = (vY + math.sqrt(disc)) / g
	else
		-- 목표가 너무 높음: arc 키워 재계산
		arcHeight = math.max(arcHeight, toTarget.Y + 10)
		vY = math.sqrt(2 * g * arcHeight)
		travelTime = (vY + math.sqrt(math.max(0, vY*vY - 2*g*toTarget.Y))) / g
	end
	travelTime = math.max(0.3, travelTime)
	local horizSpeed = horizDist / travelTime

	local proj = Instance.new("Part")
	proj.Name = "BlackHoleProjectile"
	-- 🕳️ [2026-09-01] 지면 높이 측정 레이에서 제외시킨다(EnergyBallSystem.makeRayParams).
	--   안 하면 에너지볼 경로가 블랙홀 위로 솟았다 내려온다.
	proj:SetAttribute("GroundRayIgnore", true)
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(PROJECTILE_SIZE, PROJECTILE_SIZE, PROJECTILE_SIZE)
	proj.Material = Enum.Material.Neon
	proj.Color = Color3.fromRGB(20, 0, 40)
	proj.CanCollide = false
	proj.Anchored = false
	proj.Massless = true
	-- 🤖 [2026-08-26] 농민봇 위협 인지 태그.
	--   [문제] 전수조사 결과 태거 아이템 중 블랙홀만 위협 등록이 없어
	--   봇이 날아오는 발사체에 전혀 반응하지 않았다.
	--   (다른 아이템은 CollisionGroup "TaggerItems" 또는 BotThreat 로 등록됨)
	-- ⚠️ CG 를 바꾸지 않고 속성으로 옵트인한다. CG 를 "TaggerItems" 로 하면
	--   ItemMarkerClient 가 러너 화면에 빨강 빛기둥을 붙여 게임플레이가 바뀐다
	--   (SpearSystem 155행이 같은 이유로 속성을 쓴다).
	proj:SetAttribute("BotThreat", true)
	proj.CFrame = CFrame.new(startPos)
	-- 궤적 가시화: 발광 강화 + 소용돌이 트레일 (더 크고 명확한 비행 경로)
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(170, 90, 255)
	pl.Brightness = 3
	pl.Range = 16
	pl.Parent = proj
	local a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, PROJECTILE_SIZE/2, 0) a0.Parent = proj
	local a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -PROJECTILE_SIZE/2, 0) a1.Parent = proj
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(160, 70, 255), Color3.fromRGB(40, 0, 80))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.55
	trail.WidthScale = NumberSequence.new(1)
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Parent = proj
	proj.Parent = workspace
	proj.AssemblyLinearVelocity = horizDir * horizSpeed + Vector3.new(0, vY, 0)
	proj.AssemblyAngularVelocity = Vector3.new(0, 5, 0)

	local throwTime = tick()
	local activated = false

	-- 관통 방지 백업: 매 프레임 이전위치→현재위치 사이를 레이로 검사.
	-- 빠른 투척체가 얇은 경사면을 Touched로 놓쳐 지하로 빠지는 터널링을 잡아
	-- 정확한 표면 교차점에서 착탄시킨다. (Touched와 병행 — 먼저 걸리는 쪽이 발동)
	do
		local lastPos = proj.Position
		local conn
		conn = game:GetService("RunService").Heartbeat:Connect(function()
			if activated or not proj.Parent then
				if conn then conn:Disconnect() end
				return
			end
			if (tick() - throwTime) < SELF_HIT_GRACE then lastPos = proj.Position return end
			local cur = proj.Position
			local delta = cur - lastPos
			if delta.Magnitude > 0.1 then
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { proj, char }
				local r = workspace:Raycast(lastPos, delta, rp)
				-- 관통 판정은 passThrough 공용 함수. 발사점 35 이내는 자폭 방지로 관통.
				if r and not passThrough(r.Instance)
					and (r.Position - startPos).Magnitude >= 35 then
					activated = true
					if conn then conn:Disconnect() end
					local hitPos = r.Position
					-- 🚫 착탄 거부 규칙은 Touched 경로와 '같은 함수'를 쓴다.
					--   ⚠️ [2026-08-28] 예전엔 이 레이 경로에 규칙이 없었다.
					--     주석엔 "Touched와 동일 규칙"이라 적혀 있었지만 실제로는
					--     관통 조건 3개만 복사돼 있었고 베이스/성문 가드는 빠져 있었다.
					--     그 결과 성문 위에 블랙홀이 붙어 공중(Y 214)에 열렸다
					--     (실측 09:46~09:47 map1, Gatehouse 착탄 4회).
					--   ⚠️ 새 거부 조건은 반드시 rejectLanding 안에 넣을 것. 여기에
					--     직접 쓰면 두 경로가 또 갈라진다.
					if rejectLanding(hitPos, r.Instance, proj) then return end
					print(string.format("🕳️ 블랙홀 착탄(레이): %s @ (%.0f,%.0f,%.0f)", r.Instance.GetFullName and r.Instance:GetFullName():sub(1,40) or "?", hitPos.X, hitPos.Y, hitPos.Z))
					proj:Destroy()
					_G.activateBlackHole(player, hitPos)
					return
				end
			end
			lastPos = cur
		end)
	end

	proj.Touched:Connect(function(otherPart)
		if activated then return end
		if (tick() - throwTime) < SELF_HIT_GRACE then return end
		if otherPart and otherPart.Parent == char then return end
		-- 관통 판정은 passThrough 공용 함수 (레이 경로와 같은 규칙).
		if passThrough(otherPart) then return end
		-- 발사점 근접 관통: 시전자 코앞 구조물(성벽·게이트 등)에 막혀 자폭하는 것 방지.
		-- 봇이 성 안에서 던질 때 벽 꼭대기 높이에서 "공중 활성화"처럼 보이던 문제의 해결책.
		if (proj.Position - startPos).Magnitude < 35 then return end
		activated = true
		local hitPos = proj.Position
		-- 🚫 [2026-08-28] 태거 베이스 착탄 차단.
		--   [증상] 소환 위치 검사(ItemSpawnHandler:501)는 통과했는데 베이스 위에서 활성화됐다.
		--     (실측 09:37:20 — 착탄 Workspace.map2.taggerbase2 @ (734,142,812))
		--   [원인] 블랙홀은 '던져지는' 아이템이라 클릭 지점과 착탄 지점이 다르다.
		--     소환 게이트는 클릭 지점만 본다.
		--   [왜 막나] 베이스는 "푸시툴로만 대항하는 결투 구역" 이다. 이동 봉인기가
		--     들어가면 러너의 회피 수단이 결투 구역에서 통째로 사라진다.
		--     (BarrelSpillSystem:98 이 같은 이유로 웅덩이를 막는다 — 같은 원칙이다)
		--   ⚠️ 판정은 _G.IsOnTaggerBase 를 쓴다. 복사하지 말 것 —
		--     그 함수가 ItemSpawnPlate 중첩과 부동소수점 오차(EDGE_EPS)까지 처리한다.
		--   ⚠️ 여기서 blackHoleActive 를 반드시 풀어야 한다. 안 풀면 '중복 시도 거부'가
		--     걸린 채로 남아 이번 라운드 내내 블랙홀을 못 쓴다.
		if rejectLanding(hitPos, otherPart, proj) then return end
		print(string.format("🕳️ 블랙홀 착탄: %s @ (%.0f,%.0f,%.0f)", otherPart:GetFullName():sub(1, 40), hitPos.X, hitPos.Y, hitPos.Z))
		proj:Destroy()
		_G.activateBlackHole(player, hitPos)
	end)
	Debris:AddItem(proj, PROJECTILE_LIFE)
	-- 빗나가서 활성화 안 되면 플래그 해제 (재설치 허용)
	task.delay(PROJECTILE_LIFE, function()
		if not activated then
			setActive(false)
			print("🕳️ 블랙홀 투척 빗나감 → 재설치 가능")
		end
	end)
	print(string.format("🕳️ %s 블랙홀 투척 → 목표 (%.0f, %.0f, %.0f)",
		player.Name, targetPos.X, targetPos.Y, targetPos.Z))
end

-- ─── 블랙홀 활성화 ────────────────────────────────
local function activateBlackHole(player, position)
	local template = getTemplate()
	if not template then warn("⚠️ 템플릿 없음"); return end

	local model = template:Clone()
	local body = model:FindFirstChild("Body")
	local accDisk = model:FindFirstChild("Accretion Disk")
	if not body then warn("⚠️ Body 없음"); model:Destroy(); return end

	local originalSizes = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			-- Accretion Disk만 ACCRETION_SCALE만큼 확대 (주황색 행성 테두리)
			-- Body, Event Horizon은 원본 크기 유지 (블랙홀 본체)
			local targetSize = p.Size
			if p.Name == "Accretion Disk" then
				targetSize = p.Size * ACCRETION_SCALE
			end
			originalSizes[p] = targetSize
			p.Anchored = true
			p.CanCollide = false
			p.Size = Vector3.new(0.1, 0.1, 0.1)
		end
	end

	-- 표면 raycast
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {model}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	-- 착탄점이 언덕 밑면/내부일 수 있으므로, 충분히 높은 곳(+80)에서 아래로 쏴
	-- 지형의 '윗면'을 잡는다. 단, 그 순간 상공에 있던 임시 물체(굴러가는 아이템·파도·
	-- 투명 벽 등)를 표면으로 오인하지 않도록, 착탄과 동일한 자격 규칙(비투명·CanCollide·
	-- 非TaggerItems)을 통과할 때까지 부적격 히트를 제외하며 반복 캐스트한다.
	local groundPos, normal
	do
		local excl = { }
		for _, inst in ipairs(rayParams.FilterDescendantsInstances) do excl[#excl + 1] = inst end
		for _ = 1, 6 do
			local rp2 = RaycastParams.new()
			rp2.FilterType = Enum.RaycastFilterType.Exclude
			rp2.FilterDescendantsInstances = excl
			local r = workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), rp2)
			if not r then break end
			local inst = r.Instance
			if inst.CanCollide and inst.Transparency < 0.9 and inst.CollisionGroup ~= "TaggerItems" then
				groundPos = r.Position
				normal = r.Normal
				break
			end
			excl[#excl + 1] = inst  -- 부적격(임시 물체) 제외 후 재시도
		end
	end
	if not groundPos then
		groundPos = position
		normal = Vector3.new(0, 1, 0)
	end
	-- (구 안전 클램프 삭제: "레이 결과가 착탄보다 낮으면 착탄 유지" 규칙이,
	--  Touched의 부정확한 공중 착탄 Y를 고수해 공중 스폰을 유발했음.
	--  지하 방지는 위→아래 레이가 항상 윗면을 잡으므로 이미 보장됨.)

	local blackHolePos = groundPos + normal * LIFT_HEIGHT
	-- Event Horizon (회전 0)을 PrimaryPart로 사용 → Body의 5도 기울기 안 섞임
	-- → Accretion Disk가 표면에 정확히 평행하게 정렬됨
	local horizon = model:FindFirstChild("Event Horizon")
	model.PrimaryPart = horizon or body
	model:PivotTo(alignToSurface(blackHolePos, normal))
	model:SetAttribute("GroundRayIgnore", true)   -- 🕳️ 지면 레이 제외 (proj 쪽 주석 참조)
	model.Parent = workspace

	for p, origSize in pairs(originalSizes) do
		TweenService:Create(p, TweenInfo.new(EXPAND_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = origSize,
		}):Play()
	end

	-- 흡인 범위 표시 (TNT bomb 방식: 단일 Cylinder, 한 점 normal 정렬)
	-- 범위가 엄청 정확할 필요는 없음. hill에선 가장자리가 살짝 떠 있거나 박힐 수 있음.
	local zone = Instance.new("Part")
	zone.Name = "BlackHolePullZone"
	zone:SetAttribute("GroundRayIgnore", true)   -- 🕳️ 지면 레이 제외 (proj 쪽 주석 참조)
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(0.5, 0.5, 0.5)  -- 시작 작게 → tween으로 확장
	zone.Material = Enum.Material.Neon
	zone.Color = Color3.fromRGB(80, 20, 120)
	zone.Transparency = 0.6
	zone.CanCollide = false
	zone.Anchored = true
	zone.CastShadow = false
	zone.CFrame = cframeForCylinder(groundPos + normal * ZONE_OFFSET, normal)
	zone.Parent = workspace
	TweenService:Create(zone, TweenInfo.new(EXPAND_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, PULL_RADIUS * 2, PULL_RADIUS * 2),
	}):Play()

	-- Accretion Disk 자전
	local spinConn
	if accDisk then
		spinConn = RunService.Heartbeat:Connect(function(dt)
			if not accDisk.Parent then spinConn:Disconnect(); return end
			accDisk.CFrame = accDisk.CFrame * CFrame.Angles(0, dt * 2, 0)
		end)
	end

	-- 사운드 (BlackHoleSound 명시적 재생)
	local bhSound = body:FindFirstChild("BlackHoleSound")
	if bhSound then
		bhSound.Looped = true
		bhSound:Play()
	end

	local holeData = {
		model      = model,
		body       = body,
		zone       = zone,
		position   = blackHolePos,
		ownerId    = player and player.UserId or 0,
		expireTime = tick() + ACTIVE_DURATION,
		spinConn   = spinConn,
	}
	table.insert(activeHoles, holeData)

	print(string.format("🕳️ %s 블랙홀 활성화 at (%.0f, %.0f, %.0f)",
		player and player.Name or "?", blackHolePos.X, blackHolePos.Y, blackHolePos.Z))

	task.delay(ACTIVE_DURATION, function()
		-- 이 hole에 갇혀있던 캐릭터 모두 해제 (페이드 시작 시점)
		for char, info in pairs(stuckChars) do
			if info.hole == holeData then
				releaseStuck(char)
			end
		end

		-- 모델 페이드
		for p, _ in pairs(originalSizes) do
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.5), {
					Size = Vector3.new(0.1, 0.1, 0.1),
					Transparency = 1,
				}):Play()
			end
		end
		if zone.Parent then
			TweenService:Create(zone, TweenInfo.new(0.5), {
				Size = Vector3.new(0.5, 0.5, 0.5),
				Transparency = 1,
			}):Play()
		end
		if bhSound then bhSound:Stop() end
		task.wait(0.5)
		if spinConn then spinConn:Disconnect() end
		if model and model.Parent then model:Destroy() end
		if zone and zone.Parent then zone:Destroy() end
		for i, h in ipairs(activeHoles) do
			if h == holeData then table.remove(activeHoles, i); break end
		end
		setActive(false)  -- 소멸 → 재설치 허용 (UI 잠금도 함께 해제)
		print("🕳️ 블랙홀 소멸")
	end)
end
_G.activateBlackHole = activateBlackHole

-- ─── 외부 진입점 ─────────────────────────────────
-- ⚠️ [2026-08-28] 반환값 규약: true = 발사됨(쿨 소모), false = 거부됨(쿨 미소모).
--   [증상] 거부된 캐스트가 쿨을 그대로 먹었다(실측 11:01:25.58 — '중복 시도 거부'
--     직후 ItemSpawnHandler 가 'dispatched' 를 찍고 7초 쿨을 시작).
--   [원인] 이 함수가 아무것도 안 돌려줘서 호출부가 성공/거부를 구분할 수 없었다.
--   ⚠️ tnt·EnergyBall·bear_trap·tox_box 가 이미 같은 규약을 쓴다.
--     위임 아이템 5종이 한 모양이어야 한다(ItemSpawnHandler:940 주석).
local function spawnBlackHole(player, clickPosition)
	if not player or not player.Character then return false end
	-- 맵에 블랙홀 1개만 허용 (투척 중이거나 활성 상태면 거부 + 경고)
	if blackHoleActive then
		print("🕳️ 블랙홀 중복 시도 거부:", player.Name)
		return false
	end
	lastThrower = player   -- 착탄 거부 시 쿨 환불 + UI 잠금 대상 (setActive 보다 먼저)
	setActive(true)
	throwProjectile(player, clickPosition)
	return true
end
_G.spawnBlackHole = spawnBlackHole

-- 🤖 [2026-08-31] 태거봇 콤보용: 지금 활성인 블랙홀의 좌표·종료시각·포획인원.
--   [왜] 봇이 '블랙홀에 묶인 무리'를 후속타로 덮으려면 세 가지가 다 필요하다.
--     · position   — 투척 목표가 아니라 '실제 활성화 좌표'다. 실측상 15~30 stud 어긋난다
--                     (목표 (512,98,-728) → 활성화 (534,107,-723)). 목표를 쓰면 빗나간다.
--     · expireTime — 언제까지 유효한지. 봇이 별도 타이머를 들지 않아도 된다.
--     · caught     — 실제로 잡힌 인원. 이게 없으면 빈 자리에 후속타를 버린다.
--                     실측: 콤보 7회 중 5회가 포획 0이었다. 조건 없이 쏘면 두 개를 버린다.
--   ⚠️ caught 는 stuckChars(중심 도달 = 영구 고정) 기준이다. 흡인 중이지만 아직
--     중심에 닿지 않은 캐릭터는 세지 않는다 — 그들은 빠져나갈 수 있어서 후속타
--     시점에 없을 수 있다. '확실히 묶인 수'만 센다.
--   ⚠️ 활성화에 실패한 경우(태거 베이스 착탄 등)는 activeHoles 에 안 들어가므로
--     자연히 nil 이 반환된다. 봇이 예외를 따로 처리할 필요가 없다.
--   ⚠️ 여러 개가 동시에 살아 있으면 포획이 가장 많은 것을 준다(후속타 가치가 가장 큼).
_G.GetActiveBlackHole = function()
	local best, bestCaught = nil, -1
	local now = tick()
	for _, hole in ipairs(activeHoles) do
		if hole.expireTime and now < hole.expireTime then
			local caught = 0
			for _, info in pairs(stuckChars) do
				if info.hole == hole then caught = caught + 1 end
			end
			if caught > bestCaught then best, bestCaught = hole, caught end
		end
	end
	if not best then return nil end
	return { pos = best.position, expireTime = best.expireTime, caught = bestCaught }
end

-- ─── 캐릭터 수집 (Player + NPC, R6/R15 호환) ──────
-- ⚡ [2026-08-28] 후보 목록을 캐시한다.
--   [원인] 이 함수는 흡인 루프에서 '매 프레임' 불린다. workspace 전체를 훑고
--     자식마다 FindFirstChildOfClass 를 돌리며 테이블도 새로 할당했다.
--   [무엇을 캐시하나] 비싼 쪽(workspace 스캔 + Humanoid 탐색 + 역할 판정)만.
--     ⚠️ hum.Health 는 캐시하지 말 것 — 죽어도 갱신 신호가 없어 즉시 낡는다.
--       그건 값싼 검사라 사용 시점에 매번 본다.
--   ⚠️ 캐릭터가 들고나면 workspace 자식이 바뀌므로 그 신호로 무효화한다.
local _charCache = nil
workspace.ChildAdded:Connect(function() _charCache = nil end)
workspace.ChildRemoved:Connect(function() _charCache = nil end)

local function collectAllCharacters()
	if not _charCache then
		_charCache = {}
		for _, child in ipairs(workspace:GetChildren()) do
			local hum = child:FindFirstChildOfClass("Humanoid")
			local hrp = hum and hum.RootPart
			if hum and hrp then
				-- 태거 면역: 시전자(태거/봇 KING)는 자기 블랙홀에 끌려가지 않음
				local plr = Players:GetPlayerFromCharacter(child)
				local roleAttr = (plr and plr:GetAttribute("Role")) or child:GetAttribute("Role")
				if roleAttr ~= "Tagger" then
					_charCache[#_charCache + 1] = { char = child, hum = hum, hrp = hrp }
				end
			end
		end
	end
	-- 살아있는 것만 걸러 반환 (체력은 캐시하지 않는다)
	local list = {}
	for _, c in ipairs(_charCache) do
		if c.char.Parent and c.hum.Health > 0 then
			list[#list + 1] = c
		end
	end
	return list
end

-- ─── 흡인 메커닉 (VectorForce + WalkSpeed 감소 + 중심 영구 고정) ──
RunService.Heartbeat:Connect(function(dt)
	-- 활성 hole 없으면 모든 상태 정리
	if #activeHoles == 0 then
		for char in pairs(affectedForces) do clearForce(char) end
		for char, origWS in pairs(affectedWalks) do
			local hum = char:FindFirstChildOfClass("Humanoid")
			restoreMovement(hum, origWS)   -- 🩸 다운 중이면 건드리지 않는다
		end
		table.clear(affectedWalks)
		for char in pairs(stuckChars) do
			releaseStuck(char)
		end
		return
	end

	local characters = collectAllCharacters()
	local accumulatedForce = {}
	local affectedThisFrame = {}

	for _, hole in ipairs(activeHoles) do
		local holePos = hole.position
		for _, c in ipairs(characters) do
			local char, hum, hrp = c.char, c.hum, c.hrp

			-- stuck 캐릭터는 흡인 처리 X (이미 영구 고정)
			if stuckChars[char] then continue end

			-- 태거 자신 면역
			local plr = Players:GetPlayerFromCharacter(char)
			if plr and plr.UserId == hole.ownerId then continue end

			local relPos = holePos - hrp.Position
			-- 수평 거리만 사용 (시각 디스크 = 평면이므로 시각과 판정 일치)
			-- 블랙홀이 표면에서 8 stud 떠 있어 3D 거리 쓰면 수직 차이로 어긋남
			local horizDist = Vector3.new(relPos.X, 0, relPos.Z).Magnitude
			if horizDist > PULL_RADIUS then continue end

			-- 🛡️ [2026-08-28] 태거 베이스 안의 러너는 흡인 면제.
			--   [왜] 착탄 차단(위)만으로는 부족하다. 계단과 베이스 경계에 걸쳐
			--     착탄하면 홀은 베이스 밖인데 흡인 반경이 베이스를 덮는다.
			--     그러면 결투 구역 안의 러너가 이동을 봉인당한다.
			--   ⚠️ 홀 위치가 아니라 '러너 위치' 로 판정한다. 걸친 착탄을 다루려는 것이므로
			--     홀 기준으로 보면 통과해버린다.
			--   ⚠️ 이미 stuck 된 캐릭터는 위에서 걸러진다. 여기 판정은
			--     '새로 잡히는' 것만 막으므로, 밖에서 잡혀 끌려온 러너는 유지된다.
			--   ⚡ [성능] 반드시 거리 검사 '뒤'에 둘 것. 앞에 두면 반경 밖 캐릭터까지
			--     매 프레임 베이스 판정을 돌아 서버가 버벅인다(실측: 블랙홀 사용 중 렉).
			if _G.IsOnTaggerBase and _G.IsOnTaggerBase(hrp.Position) then continue end

			-- 🩸 [버그수정 2026-09-04] 다운된 러너는 흡인 면제.
			--   [증상] 블랙홀에 빨려가던 중 통나무에 맞아 다운됐는데, 다운 상태인데도
			--     이동 속도가 다운 감속(25%)이 아니라 훨씬 빨랐다(실측 15:17:46 판).
			--   [원인] 다운은 WalkSpeed 를 낮추는 방식인데, 흡인은 VectorForce 로 민다.
			--     둘이 다른 채널이라 WalkSpeed 를 아무리 낮춰도 흡인은 그대로 끌어당긴다.
			--     로그상 다운(46.4s) 뒤에도 포획(48.7s)이 계속 찍혔다.
			--   ⚠️ 같은 유형의 수정이 BarrelSpillSystem:301 에 이미 있다
			--     ("다운 상태면 건드리지 않는다 — DownSystem 의 다운 연출이 방해받는다").
			--     같은 규칙이 두 곳에 필요한데 여기만 빠져 있었다.
			--   ⚠️ 이미 stuck 된 캐릭터는 697행에서 걸러진다. 여기 판정은 '새로 잡히는' 것과
			--     '끌려가는 중'을 막는다 — 잡힌 뒤 다운되면 stuck 해제는 별도 경로다.
			--   ⚡ 베이스 판정과 같은 이유로 거리 검사 뒤에 둔다(반경 밖까지 매 프레임 돌면 렉).
			if char:GetAttribute("Downed") then continue end

			affectedThisFrame[char] = hum

			-- 중심 도달 → 영구 고정 (파리 끈끈이)
			-- 블랙홀 소멸 시까지 풀리지 X
			if horizDist < CENTER_RADIUS then
				-- 🚧 [진단 2026-08-26] 포획 로그.
				--   [왜] 블랙홀은 processHit 을 부르지 않는다 = 데미지가 0이 설계다.
				--   그런데 로그가 전혀 없어서, 실측 시 "안 맞은 건지 원래 딜이
				--   없는 건지" 구분할 수 없었다(13:12 판: 3회 활성화, 명중 기록 0).
				--   제어기의 성과는 '몇 명을 몇 초 묶었나' 이므로 그걸 남긴다.
				print(string.format("🕳️ [BlackHole] 포획 → %s", char.Name))
				stuckChars[char] = {
					hole = hole,
					origWS = affectedWalks[char] or hum.WalkSpeed,
					origJP = hum.JumpPower,
				}
				-- affectedWalks/affectedForces에서 제거 (stuck 상태로 전환)
				affectedWalks[char] = nil
				clearForce(char)
				-- 입력 무력화
				hum.WalkSpeed = 0
				hum.JumpPower = 0
				-- HRP를 블랙홀 중심으로 텔레포트 + anchor → 본체 안에 박힘
				-- 본체가 검은 구라 캐릭터들이 겹쳐도 본체에 가려져 시각적으로 자연스러움
				hrp.CFrame = CFrame.new(holePos)
				hrp.Anchored = true
				continue
			end

			-- 흡인 방향 (수평만)
			local horizDir = Vector3.new(relPos.X, 0, relPos.Z)
			if horizDir.Magnitude < 0.1 then continue end
			horizDir = horizDir.Unit

			-- 거리별 가속도 계산
			-- STRONG_RADIUS 안 (주황색 영역): 풀 가속도 (확 끌림)
			-- STRONG_RADIUS ~ PULL_RADIUS (보라색 외곽): 제곱 falloff (약하게 끌림)
			local accel
			if horizDist < STRONG_RADIUS then
				accel = PULL_ACCEL
			else
				local t = 1 - (horizDist - STRONG_RADIUS) / (PULL_RADIUS - STRONG_RADIUS)
				accel = PULL_ACCEL * t * t
			end
			local mass = hrp.AssemblyMass
			local forceMag = mass * accel

			accumulatedForce[char] = (accumulatedForce[char] or Vector3.zero) + horizDir * forceMag
		end
	end

	-- 영향권 벗어난 캐릭터 force/walkspeed 정리
	for char in pairs(affectedForces) do
		if not affectedThisFrame[char] then clearForce(char) end
	end
	for char, origWS in pairs(affectedWalks) do
		if not affectedThisFrame[char] then
			local hum = char:FindFirstChildOfClass("Humanoid")
			restoreMovement(hum, origWS)   -- 🩸 다운 중이면 건드리지 않는다
			affectedWalks[char] = nil
		end
	end

	-- 영향권 들어온 캐릭터 walkspeed 감소 (한 번만, stuck는 제외)
	for char, hum in pairs(affectedThisFrame) do
		if not affectedWalks[char] and not stuckChars[char] then
			affectedWalks[char] = hum.WalkSpeed
			hum.WalkSpeed = hum.WalkSpeed * PULL_WALK_FACTOR
		end
	end

	-- 영향권 안 캐릭터 force 적용
	for char, totalForce in pairs(accumulatedForce) do
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = hum and hum.RootPart
		if hum and hrp then
			local force = ensureForce(char, hrp)
			force.Force = totalForce
		end
	end
end)

print("✅ BlackHoleSystem ready (VectorForce + 중심 영구 고정)")
