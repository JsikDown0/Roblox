-- TrapSystem
-- 'bear_trap' 태거 아이템: 클라이언트가 PlaceTrap 이벤트로 위치 보내면
-- 서버가 1.5초 경고(반투명 + 빨간 빛) 표시 후 실제 함정 활성화.
-- 러너 접촉 시 3초 스턴(다리/몸통 anchored) + Close 메시 + 사운드.

local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService    = game:GetService("PhysicsService")
local Players           = game:GetService("Players")
local Debris            = game:GetService("Debris")

local taggerItems   = ServerStorage:WaitForChild("TaggerItem")
local trapTemplate  = taggerItems:WaitForChild("bear_trap")

-- ────────────────────────────────────────────────────────────────
-- 트랩 히트박스 전용 콜리전 그룹
--   굴러오는 태거 아이템(TaggerItems)은 통과시키고, 그 외에는 TaggerItems 와 동일하게 둔다.
--   러너 감지는 HitBox.Touched 이벤트라 콜리전 설정과 무관하게 계속 동작한다.
-- ────────────────────────────────────────────────────────────────
local trapGroupReady = false
local function ensureTrapGroup()
	if trapGroupReady then return end
	trapGroupReady = true
	local PS = game:GetService("PhysicsService")
	pcall(function() PS:RegisterCollisionGroup("TrapHitbox") end)
	pcall(function()
		-- 기본값은 TaggerItems 의 설정을 그대로 복사
		for _, g in ipairs(PS:GetRegisteredCollisionGroups()) do
			local c = PS:CollisionGroupsAreCollidable("TaggerItems", g.name)
			PS:CollisionGroupSetCollidable("TrapHitbox", g.name, c)
		end
		-- 핵심: 굴러오는 아이템은 통과
		PS:CollisionGroupSetCollidable("TrapHitbox", "TaggerItems", false)
		-- 트랩끼리도 통과 (겹쳐 설치 가능)
		PS:CollisionGroupSetCollidable("TrapHitbox", "TrapHitbox", false)
	end)
end
local placeEvent    = ReplicatedStorage:WaitForChild("PlaceTrap")

-- ─── Tunables ──────────────────────────────────────────────
local WARNING_DURATION    = 1.0    -- 예고 시간 (1.5 → 1.0, 적중률 개선)
local LOCK_DURATION       = 4.5    -- 락 지속 (3 → 4.5, 블랙홀 6초 대비 균형)
local TRAP_LIFETIME       = 30     -- 함정 자동 소멸 시간 (밟지 않으면)
local MAX_RANGE           = 850    -- 설치 사거리

-- 🩸 [2026-09-19] 지속 피해(틱뎀). 락 지속 내내 초당 10.
--   [왜] 트랩이 순수 CC 라 "밟아도 손해가 없다" 였다. 실측으로 킹의 전환
--     마감이 3.0초(락 4.5 − 내구도 무적 1.5)라 반경 48 stud 안에 있을 때만
--     처치로 이어지는데, 설치 사거리는 850 이다. 대부분의 설치가 아무 손해도
--     못 만들었다. 배럴 웅덩이가 2026-09-01 에 같은 진단("순수 디버프라 밟아도
--     손해가 없다")으로 같은 답을 냈다 — BarrelSpillConfig:44 의 형태를 따른다.
--   [왜 2단계에 연계되나] Stage2TriggerSystem 은 2단계 전환 때 '태거' HP 만
--     재산정한다(:290 유저 킹 / :318 봇 킹). 러너 분기(:589)에는 HP 대입이
--     한 줄도 없어 1단계에서 깎은 HP 가 그대로 2단계 전투로 넘어간다.
--     = 단계를 넘는 유일한 수단이다.
--   [경로] hum:TakeDamage. processHit 을 타지 않으므로 내구도를 소모하지 않고
--     "1발사 1히트" 도 안 건드린다. HP 0 은 ItemDamageSystem.attachRunnerDownOnZero
--     가 다운으로 바꾼다(즉사 아님). 배럴·마법책·곡사포와 같은 경로다.
--   [수치] 초당 10 × 락 4.5초 = 45 전후(첫 틱이 즉시 들어가 실측 45~47).
--     배럴 웅덩이 통과(44)와 같은 값이지만 성질이 다르다 — 배럴은 돌아가거나
--     대시로 피할 수 있고, 이쪽은 hrp.Anchored 라 확정 수령이다. 그걸 알고 넣는다
--     ("맞아야 의미가 있다" — 배럴이 초당 4 → 10 으로 올린 것과 같은 판단).
--   🔴 [과하면 여기만 내린다] TICK_DAMAGE 를 1.25(초당 5)로. LOCK_DURATION 은
--     건드리지 말 것 — 블랙홀 6초 대비로 잡은 값이다(위 :42 주석).
--   🔴 [되돌리는 법] 이 상수 2개와 lockRunner 안의 task.spawn 틱 블록을 지운다.
local TICK_DAMAGE         = 2.5    -- 1틱당 피해
local TICK_INTERVAL       = 0.25   -- 틱 주기(초) → 초당 10

-- ═══════════════════════════════════════════════════════════
-- 🪤 설치 가능 구역
--
-- [의도] 모든 태거 아이템은 '계단까지'만 쓸 수 있다.
--   베어트랩도 예외가 아니다. 데미지가 없어도 러너 스폰 근처에 깔면
--   출발 자체를 막아 데미지보다 답답한 상황이 된다.
--
-- ⚠️ MAX_RANGE(반경) 만으로는 안 된다. 태거 스폰이 베이스 안에 있어
--   어떤 반경을 잡아도 베이스가 포함된다. 좌표 구간으로 판정한다.
--
-- ⚠️ [맵 추가 시] 아래 ZONE_BY_MAP 에 항목만 추가하면 된다.
--   maxX  : 이 X 이하에만 설치 가능 (보통 계단 끝)
--   minX  : 이 X 이상 (러너 스폰 뒤쪽 낙사 지역 방지)
--   기존 맵 좌표는 ItemSpawnPlate 의 앞/뒤 면에서 뽑았다.
--   자동 탐지도 가능하지만, 맵마다 파트 이름이 달라(ItemSpawnPlate /
--   ItemSpawnPlate2) 명시가 더 안전하다.
-- ═══════════════════════════════════════════════════════════
local ZONE_BY_MAP = {
	map1 = { minX = -260, maxX = 711 },   -- 계단 687~711
	map2 = { minX = -180, maxX = 711 },   -- 계단 688~711
	-- map3 = { minX = ?, maxX = ? },
}

-- ⚠️ 맵 이름을 못 찾으면 설치를 막지 않는다(새 맵에서 기능이 죽는 것보다
--    허용해두고 나중에 등록하는 편이 낫다). 대신 경고를 남긴다.
local _warnedMaps = {}
local function isPlaceAllowed(position)
	for mapName, zone in pairs(ZONE_BY_MAP) do
		local mf = workspace:FindFirstChild(mapName)
		if mf then
			-- 이 맵의 Z 범위 안인지 먼저 확인(맵이 여러 개 로드돼 있을 수 있다)
			local base = mf:FindFirstChild("taggerbase") or mf:FindFirstChild("taggerbase2")
			if base then
				local z1 = base.Position.Z - base.Size.Z / 2 - 200
				local z2 = base.Position.Z + base.Size.Z / 2 + 200
				if position.Z >= z1 and position.Z <= z2 then
					return position.X >= zone.minX and position.X <= zone.maxX, mapName
				end
			end
		end
	end
	if not _warnedMaps._once then
		_warnedMaps._once = true
		warn("[TrapSystem] 설치 구역이 등록되지 않은 맵입니다. ZONE_BY_MAP 에 추가하세요.")
	end
	return true, nil
end
-- ═══════════════════════════════════════════════════════════
-- 🪤 [밸런스 2026-08-26] 설치 쿨 5 → 1.5.
--
-- [왜] 베어트랩은 '설치형' 이라 투척형과 평가 축이 다르다.
--   투척형: 한 번 던져 한 번 위협 → 쿨이 위협 빈도를 정한다.
--   설치형: 깔아두고 러너가 밟기를 기다린다 → 가치는 '깔린 개수 × 수명' 이다.
--   쿨 5초는 이 성질과 정면으로 충돌했다. 상한이 5개인데 다 까는 데 20초가
--   걸려서, 1단계(40~48초)의 절반을 설치에만 쓰는 셈이었다.
--   → 쿨이 아니라 MAX_TRAPS_PER_OWNER 가 총량을 제한하게 한다.
--
-- ⚠️ 총 위협량은 상한 5개로 이미 묶여 있다. 쿨을 줄여도 동시에 존재하는
--   함정 수는 그대로다. 빨라지는 것은 '배치 속도' 뿐이다.
-- ⚠️ [2026-08-26] 2.0 → 1.0. 위에 있던 "값이 2.0 인 이유" 경고는 폐기됐다.
--   당시 전제: GLOBAL_COOLDOWN(2.0)이 모든 태거 아이템에 걸리므로 여기를
--   그보다 낮춰도 실제 간격은 2.0 이라 코드가 거짓말을 한다 — 맞는 지적이었다.
--   → 그래서 ItemSpawnHandler 에 GLOBAL_CD_EXEMPT 를 만들어 bear_trap 을
--     전역 쿨에서 양방향으로 빼냈다. 이제 1.0 이 실제 간격이다.
--   ⚠️ 실효 간격 = max(PLACE_COOLDOWN, ITEM_COOLDOWN["bear_trap"]) = max(1.0, 1) = 1.0.
--     ItemSpawnHandler 의 개별 쿨도 1 이어야 한다. 한쪽만 바꾸면 긴 쪽이 이긴다.
-- ⚠️ 락 지속 4.5초는 그대로. 여기를 건드리면 총 위협량이 실제로 늘어난다.
-- ═══════════════════════════════════════════════════════════
local PLACE_COOLDOWN      = 1.0    -- 설치 간격. 총량은 MAX_TRAPS_PER_OWNER 가 제한
local MAX_TRAPS_PER_OWNER = 5      -- 동시 설치 최대 개수
local HITBOX_SCALE        = 1.25   -- 히트박스 = 겉모습(Open) 크기 × 이 값

-- 사운드 ID
local SND_WARNING = "rbxassetid://16903690359"   -- 함정 설치 직후 경고
local SND_SNAP    = "rbxassetid://2019418800"    -- 러너 밟힘
local SND_SNAP_VOLUME = 0.5

local playerCooldowns   = {}      -- userId → 마지막 설치 시각

-- 🔔 [2026-08-26] 함정 발동을 "설치한 태거에게만" 알리는 신호.
--   [왜] 밟힘 사운드는 RollOffMaxDistance 80 인데 맵 X축이 약 870 stud 다.
--     맵의 9% 안에 있어야 들려서, 멀리 깔아둔 함정은 걸렸는지조차 알 수 없었다.
--     배지(4/5→3/5)는 trap:Destroy() 시점 = LOCK_DURATION(4.5초) 뒤라
--     "잡았다"가 아니라 "방금 풀려났다"를 알리고 있었다 — 타이밍이 반대였다.
--   [방식] 소유자 클라에 2D(비위치) 사운드를 울린다. 거리 개념이 없으므로
--     맵 어디에 깔았든 동일하게 들린다. 수신부는 TaggerUIScript.
--   ⚠️ 위치 정보는 여기서 보내지 않는다. 그건 PlayerMarkerClient 가
--     TrapHit/TrapHitUntil 속성을 읽어 마커로 표시한다(소리=시점, 마커=대상).
local trapCaughtEvent = ReplicatedStorage:FindFirstChild("TrapCaughtEvent")
if not trapCaughtEvent then
	trapCaughtEvent = Instance.new("RemoteEvent")
	trapCaughtEvent.Name = "TrapCaughtEvent"
	trapCaughtEvent.Parent = ReplicatedStorage
end
local playerActiveTraps = {}      -- userId → {trap, trap, ...} 활성 함정 추적

-- ─── 🪤 설치 개수 노출 ───────────────────────────────────────
-- [왜] 설치 개수는 서버 로그에만 (3/5) 로 찍혀서 태거는 몇 개 깔았는지 알 수 없었다.
--   쿨타임은 이미 리스트의 CdOverlay 로 보이는데 개수만 안 보여,
--   상한(5)에 걸렸을 때 "왜 안 나가지?" 가 반복됐다. (2026-08-26 실측: 5/5 거부 3회)
-- [방식] 플레이어 속성으로 올린다 — 속성은 클라에 자동 복제되므로 RemoteEvent 가 필요 없고,
--   TaggerUIScript 가 GetAttributeChangedSignal 로 바로 따라온다.
-- ⚠️ 태거 봇은 진짜 Player 인스턴스가 아닌 pseudoPlayer(Lua 테이블)다 → IsA 가드 필수.
--   가드가 없으면 봇이 함정을 깔 때마다 "attempt to index" 로 스폰이 통째로 죽는다.
local function syncTrapCount(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local active = playerActiveTraps[player.UserId]
	local n = 0
	if active then
		for i = #active, 1, -1 do
			if not active[i] or not active[i].Parent then table.remove(active, i) end
		end
		n = #active
	end
	player:SetAttribute("TrapCount", n)
	player:SetAttribute("TrapMax", MAX_TRAPS_PER_OWNER)
end
_G.syncTrapCount = syncTrapCount

-- ─── 표면 정렬 헬퍼 ──────────────────────────────────────────
-- 표면 normal 방향으로 회전된 CFrame 생성.
-- primaryAxis="Y" → UpVector가 normal (함정 모델용, 위쪽이 표면 normal과 일치)
-- primaryAxis="X" → RightVector가 normal (Cylinder Part의 길이축 = 두께축이 표면 normal)
local function buildSurfaceCFrame(position, normal, primaryAxis)
	normal = normal.Unit
	-- 보조 축: normal과 평행하지 않아야 함
	local tempAxis = Vector3.new(0, 0, -1)
	if math.abs(normal:Dot(tempAxis)) > 0.99 then
		tempAxis = Vector3.new(1, 0, 0)
	end

	if primaryAxis == "Y" then
		local right = tempAxis:Cross(normal).Unit
		if right.Magnitude < 0.001 then
			right = Vector3.new(1, 0, 0):Cross(normal).Unit
		end
		local back = right:Cross(normal).Unit
		return CFrame.fromMatrix(position, right, normal, back)
	else
		-- X primary (Cylinder Part: 길이축이 normal 방향)
		local up = tempAxis:Cross(normal).Unit
		if up.Magnitude < 0.001 then
			up = Vector3.new(1, 0, 0):Cross(normal).Unit
		end
		local back = normal:Cross(up).Unit
		return CFrame.fromMatrix(position, normal, up, back)
	end
end

-- ─── 표면 raycast: 정확한 위치와 normal 추출 ─────────────────
local function findSurface(position, ownerCharacter)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ownerCharacter and {ownerCharacter} or {}
	-- click position 약간 위에서 아래로 raycast
	local res = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rp)
	if res then
		return res.Position, res.Normal
	end
	-- 못 찾으면 그대로 사용 (안전망)
	return position, Vector3.new(0, 1, 0)
end

-- ─── 러너 자리 고정 ────────────────────────────────────────
-- ────────────────────────────────────────────────────────────────
-- 트랩 해제 시 이동속도 복원
--   ⚠️ '걸린 순간의 값을 저장해 되돌리는' 방식은 쓰지 않는다.
--   3초 락 동안 다른 시스템이 WalkSpeed 를 바꾸면 그 값이 영구히 굳는다.
--   실측 트리거(2026-08): 트랩에 고정된 상태에서 산데비스탄(RunnerDive)을 쓰면
--   두 시스템이 서로의 저장값을 밟아 영구히 느려졌다.
--   → RunnerDive.groundSpeed() 와 같은 방식으로 기준값을 계산해 복원한다.
--   그리고 남이 걸어둔 상태(다운·대시 탈진)는 존중해서 건드리지 않는다.
-- ────────────────────────────────────────────────────────────────
local BASE_WALKSPEED   = 16     -- DownSystem/RunnerDive 의 DEFAULT_WALKSPEED 와 같은 값
local DOWN_SPEED_MULT  = 0.25   -- DownSystem 의 다운 중 배율
local EXHAUST_MULT     = 0.25   -- RunnerDive 의 탈진 배율

local function restoreWalkSpeed(character, humanoid, oldJump)
	if not (humanoid and humanoid.Parent) then return end
	humanoid.JumpPower = oldJump

	local base = BASE_WALKSPEED + ((character and character:GetAttribute("SpeedBoost")) or 0)

	-- 다운 중이면 다운 속도를 유지한다 (DownSystem 이 관리하는 상태).
	if character and character:GetAttribute("Downed") then
		humanoid.WalkSpeed = base * DOWN_SPEED_MULT
		return
	end

	-- 대시 탈진 중이면 탈진 속도를 유지한다 (트랩이 대시 페널티를 지우면 안 된다).
	local plr = Players:GetPlayerFromCharacter(character)
	if plr and plr:GetAttribute("Exhausted") then
		humanoid.WalkSpeed = base * EXHAUST_MULT
		return
	end

	humanoid.WalkSpeed = base
end

local function lockRunner(runnerCharacter, trapModel, ownerPlayer)
	local humanoid = runnerCharacter:FindFirstChildOfClass("Humanoid")
	local hrp      = runnerCharacter:FindFirstChild("HumanoidRootPart")
	local leftFoot = runnerCharacter:FindFirstChild("LeftFoot")
	local rightFoot= runnerCharacter:FindFirstChild("RightFoot")
	if not humanoid or not hrp then return end

	-- 다운 상태 면역 (이중 처벌 방지)
	if humanoid.Health <= 0 then return end
	local plr = Players:GetPlayerFromCharacter(runnerCharacter)
	if (plr and plr:GetAttribute("Downed")) or runnerCharacter:GetAttribute("Downed") then return end

	-- 이미 잡힌 상태면 무시
	if runnerCharacter:GetAttribute("TrapHit") then return end
	runnerCharacter:SetAttribute("TrapHit", true)
	-- ⏳ 마커 카운트다운용 종료 시각. 속성이라 클라에 자동 복제된다.
	--   ⚠️ TrapHit 과 반드시 같이 세우고 같이 지운다(아래 해제 블록).
	--   ⚠️ GetServerTimeNow 기준이라 클라가 시계 보정 없이 그대로 뺄 수 있다.
	runnerCharacter:SetAttribute("TrapHitUntil", workspace:GetServerTimeNow() + LOCK_DURATION)

	-- ⭐ 자리 고정: 끌어오기 없이 그 자리에 그대로 anchored
	if leftFoot then leftFoot.Anchored = true end
	if rightFoot then rightFoot.Anchored = true end
	hrp.Anchored = true

	-- WalkSpeed/JumpPower 0 (이중 안전망)
	-- (oldWalk 저장은 제거됨 — restoreWalkSpeed 가 기준값을 직접 계산한다)
	local oldJump = humanoid.JumpPower
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	-- 함정 닫힘 애니메이션 + 사운드
	local trapHitBox = trapModel:FindFirstChild("HitBox")
	local openMesh  = trapModel:FindFirstChild("Open")
	local closeMesh = trapModel:FindFirstChild("Close")
	if openMesh  then openMesh.Transparency  = 1 end
	if closeMesh then closeMesh.Transparency = 0 end

	if trapHitBox then
		-- 원본 무료모델 사운드 (있으면)
		local bang = trapHitBox:FindFirstChild("Bang")
		local ow   = trapHitBox:FindFirstChild("Ow")
		if bang then bang:Play() end
		if ow   then ow:Play()   end

		-- ⭐ 새 밟힘 사운드 (rbxassetid://2019418800, 볼륨 0.5)
		local snap = Instance.new("Sound")
		snap.Name = "SnapSound"
		snap.SoundId = SND_SNAP
		snap.Volume = SND_SNAP_VOLUME
		snap.RollOffMode = Enum.RollOffMode.InverseTapered
		snap.RollOffMaxDistance = 80
		snap.Parent = trapHitBox
		snap:Play()
		Debris:AddItem(snap, 5)

		trapHitBox.CanCollide = false  -- 잡힌 후 다른 사람이 또 안 걸리게
	end

	print("🪤 Trap caught:", runnerCharacter.Name)

	-- 🔔 설치한 태거에게만 알린다 (거리 무관 2D 사운드).
	-- ⚠️ 태거 봇은 pseudoPlayer(Lua 테이블)라 FireClient 인자로 못 쓴다 → 가드.
	if typeof(ownerPlayer) == "Instance" and ownerPlayer:IsA("Player") then
		trapCaughtEvent:FireClient(ownerPlayer, runnerCharacter.Name, LOCK_DURATION)
	end
	-- 🩸 [2026-09-19] 지속 피해 틱. 상수·설계근거는 위 Tunables 주석 참조.
	-- ⚠️ 무적은 '면제'지 '초기화'가 아니다 — 틱은 건너뛰되 루프는 계속 돈다.
	--   앵커된 상태라 빠져나갈 수 없으므로 무적이 풀리는 즉시 다시 들어간다.
	--   BarrelSpillSystem:287 과 같은 규칙.
	-- ⚠️ 다운되면 중단한다. 다운은 이미 10초 사형 선고라 추가 피해가 무의미하고
	--   DownSystem 의 부활 후 HP 규칙과 충돌한다(배럴도 같은 이유로 제외한다).
	-- ⚠️ 종료 조건을 TrapHit 속성에 건다. 아래 해제 블록이 이 속성을 지우므로
	--   락 해제와 DoT 종료가 구조적으로 같이 끝난다 — 따로 타이머를 두지 않는다.
	-- 🔬 [계측] 판당 한 줄. 스피어 쿨 변경과 1단계 처치 기여분을 분리해 읽으려고 둔다.
	task.spawn(function()
		local dealt = 0
		while runnerCharacter.Parent and runnerCharacter:GetAttribute("TrapHit") do
			if humanoid.Parent == nil or humanoid.Health <= 0 then break end
			if runnerCharacter:GetAttribute("Downed") then break end
			if not (_G.isInvincible and _G.isInvincible(runnerCharacter)) then
				humanoid:TakeDamage(TICK_DAMAGE)
				dealt = dealt + TICK_DAMAGE
			end
			task.wait(TICK_INTERVAL)
		end
		if dealt > 0 then
			print(string.format("🩸 [Trap] %s 지속피해 %.1f → 남은 HP %.0f",
				runnerCharacter.Name, dealt, math.max(0, humanoid.Health)))
		end
	end)


	-- LOCK_DURATION 후 풀어줌
	task.delay(LOCK_DURATION, function()
		if humanoid and humanoid.Parent then
			restoreWalkSpeed(runnerCharacter, humanoid, oldJump)
		end
		if leftFoot  and leftFoot.Parent  then leftFoot.Anchored  = false end
		if rightFoot and rightFoot.Parent then rightFoot.Anchored = false end
		if hrp and hrp.Parent then hrp.Anchored = false end
		if runnerCharacter and runnerCharacter.Parent then
			runnerCharacter:SetAttribute("TrapHit", nil)
			-- ⚠️ 세운 것과 지우는 것은 같은 편집에. TrapHitUntil 만 남으면
			--   마커가 "묶여 있음" 상태로 굳는다.
			runnerCharacter:SetAttribute("TrapHitUntil", nil)
		end

		-- 함정 소멸 (1회용)
		if trapModel and trapModel.Parent then
			trapModel:Destroy()
		end
	end)
end

-- ─── 함정 활성화 (경고 시간 끝난 후) ───────────────────────
local function activateTrap(trap, ownerPlayer)
	-- 빨간 경고 디스크 제거
	local warnDisk = trap:FindFirstChild("WarnDisk")
	if warnDisk then warnDisk:Destroy() end

	-- 경고 라이트 제거
	local hitbox = trap:FindFirstChild("HitBox")
	if hitbox then
		local warnLight = hitbox:FindFirstChild("WarnLight")
		if warnLight then warnLight:Destroy() end

		-- 이제 충돌 감지 활성화
		hitbox.Touched:Connect(function(hit)
			local char = hit.Parent
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			if not hum then return end

			-- 태거 면역 (유저/봇 KING/NPC 모두): 캐릭터 Role 속성으로 일반화
			local plr = Players:GetPlayerFromCharacter(char)
			local roleAttr = (plr and plr:GetAttribute("Role")) or char:GetAttribute("Role")
			if roleAttr == "Tagger" then return end
			if char.Name == "Noob" or char.Name == "KING" then return end

			lockRunner(char, trap, ownerPlayer)
		end)
	end

	-- TRAP_LIFETIME 후 자동 소멸 (밟히지 않은 경우)
	Debris:AddItem(trap, TRAP_LIFETIME)
end

-- ─── 클라이언트 PlaceTrap 이벤트 핸들러 (또는 _G.placeTrap 직접 호출) ─────
local function placeTrap(player, position)
	-- 검증
	if not player or not position then return end
	if typeof(position) ~= "Vector3" then return end

	-- 태거만
	if player:GetAttribute("Role") ~= "Tagger" then
		print("❌ TrapSystem: 비태거 차단", player.Name)
		return
	end

	-- Frozen 차단 (Ice Bow 효과)
	if player:GetAttribute("Frozen") then
		print("❌ TrapSystem: Frozen 차단", player.Name)
		return
	end

	-- 사거리 검증
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (position - hrp.Position).Magnitude > MAX_RANGE then
		print("❌ TrapSystem: 사거리 초과", player.Name)
		return
	end

	-- 🪤 설치 구역 검사 (계단까지만)
	local allowed, mapName = isPlaceAllowed(position)
	if not allowed then
		print(string.format("🪤 TrapSystem: 설치 불가 구역 (%s, X %.0f) - %s",
			tostring(mapName), position.X, player.Name))
		local nv2 = game:GetService("ReplicatedStorage"):FindFirstChild("TaggerNoticeEvent")
		-- ⚠️ 봇은 pseudoPlayer(Lua 테이블)라 FireClient 인자로 못 쓴다 → 가드.
		if nv2 and typeof(player) == "Instance" and player:IsA("Player") then
			nv2:FireClient(player, "여기엔 설치할 수 없어요")
		end
		return false
	end

	-- 쿨다운
	local now = tick()
	local last = playerCooldowns[player.UserId] or 0
	if now - last < PLACE_COOLDOWN then
		print("❌ TrapSystem: 쿨다운", player.Name, string.format("%.1f초 남음", PLACE_COOLDOWN - (now - last)))
		return
	end

	-- 최대 동시 설치 개수 체크 (유효한 함정만 카운트)
	local active = playerActiveTraps[player.UserId]
	if not active then
		active = {}
		playerActiveTraps[player.UserId] = active
	end
	-- 사라진 함정 정리
	for i = #active, 1, -1 do
		if not active[i] or not active[i].Parent then
			table.remove(active, i)
		end
	end
	if #active >= MAX_TRAPS_PER_OWNER then
		-- 📢 화면에 알린다. 서버 로그만으로는 유저가 이유를 모른다.
		-- ⚠️ [2026-08-26] 같은 FireClient 가 두 번 있어 토스트가 2겹으로 떴다 → 하나로 정리.
		local nv = game:GetService("ReplicatedStorage"):FindFirstChild("TaggerNoticeEvent")
		if nv and typeof(player) == "Instance" and player:IsA("Player") then
			nv:FireClient(player, string.format("함정은 최대 %d개까지", MAX_TRAPS_PER_OWNER))
		end
		print("❌ TrapSystem: 최대 함정 개수", player.Name, string.format("(%d/%d)", #active, MAX_TRAPS_PER_OWNER))
		syncTrapCount(player)
		return false
	end

	playerCooldowns[player.UserId] = now

	-- 표면 정보 (정확한 표면 위치 + normal) 구하기
	local surfacePos, surfaceNormal = findSurface(position, char)

	-- 함정 클론 (장착 스킨 반영: 색 스킨은 베이스+Open색칠, 이펙트 스킨은 모델교체)
	local templateToUse = trapTemplate
	local trapSkinData = nil
	if _G.getEquippedSkin then
		local skin = _G.getEquippedSkin(player, "bear_trap")
		if skin and player:GetAttribute("Has_" .. skin) == true then
			local data = _G.getSwordSkinData and _G.getSwordSkinData("bear_trap", skin)
			if data and data.color then
				trapSkinData = data  -- 색 스킨: 베이스 유지 + Open 색칠(스폰 후)
				print("🎨 Bear Trap 색 스킨:", skin)
			else
				local skinTemplate = taggerItems:FindFirstChild(skin)
				if skinTemplate then
					templateToUse = skinTemplate  -- 이펙트 스킨(Rainbow): 모델교체
					print("🎨 Bear Trap 스킨 적용:", skin)
				end
			end
		end
	end
	-- _Custom: 색/이펙트 스킨 없으면 BTColor/BTMaterial 속성으로 Open 색칠
	if templateToUse == trapTemplate and not trapSkinData then
		local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
		local cfg = palette.getConfig("bear_trap")
		local colorName = player:GetAttribute("BTColor_Trap") or cfg.zoneDefault.Trap
		local defs = cfg.colors or palette.COLORS
		if colorName and defs[colorName] then
			local finishKey = player:GetAttribute("BTMaterial_Trap") or cfg.materialDefault
			local baseColor = defs[colorName]
			local f = palette.FINISHES[finishKey]
			if f then
				trapSkinData = { material = f.material, color = f.tint or baseColor }
			else
				trapSkinData = { material = "Metal", color = baseColor }
			end
		end
	end
	local trap = templateToUse:Clone()

	-- 색 스킨: Open 파트만 텍스처 제거 + material/color (기존 색 BearTrap과 동일 결과)
	if trapSkinData then
		local openPart = trap:FindFirstChild("Open")
		if openPart and openPart:IsA("BasePart") then
			openPart.TextureID = ""
			openPart.Material = Enum.Material[trapSkinData.material] or openPart.Material
			openPart.Color = trapSkinData.color
		end
	end

	-- ⭐ PrimaryPart 설정: PivotTo가 HitBox 기준으로 동작하게
	-- 히트박스를 겉모습에 맞추고 전반적으로 키운다.
	--   실측(2026-08): HitBox 2.27×2.27×3.18 은 겉모습(Open 4.54×1.36×4.09)의
	--   X 50% / Z 78% 뿐이라, 눈에 보이는 트랩을 밟아도 안 걸리는 구간이 있었다.
	--   템플릿이 16개(스킨별)라 모델을 개별 수정하면 어긋나므로 런타임에 맞춘다.
	--   HITBOX_SCALE 로 겉모습보다 조금 더 키워 적중률을 올린다.
	if trap.HitBox and trap:FindFirstChild("Open") then
		local o = trap.Open.Size
		trap.HitBox.Size = Vector3.new(
			o.X * HITBOX_SCALE,
			math.max(trap.HitBox.Size.Y, o.Y * HITBOX_SCALE),
			o.Z * HITBOX_SCALE)
	end
	trap.PrimaryPart = trap.HitBox

	-- 함정을 표면 경사에 맞게 정렬 (UpVector = surfaceNormal)
	-- HitBox 중심이 표면에서 normal 방향으로 1.2 stud 띄움
	trap:PivotTo(buildSurfaceCFrame(surfacePos + surfaceNormal * 1.2, surfaceNormal, "Y"))

	-- Close 메시는 시작부터 안 보이게 (Open만 보임)
	if trap:FindFirstChild("Close") then
		trap.Close.Transparency = 1
	end

	-- 메시 자체는 텍스처 그대로 (TextureID가 Color를 가리므로 색 변경 의미 없음)
	-- 대신 별도 빨간 경고 디스크로 시각화

	-- 🔴 빨간 경고 디스크 (Cylinder Part, 표면 경사에 따라 평평하게 깔림)
	local warnDisk = Instance.new("Part")
	warnDisk.Name = "WarnDisk"
	warnDisk.Shape = Enum.PartType.Cylinder
	warnDisk.Size = Vector3.new(0.3, 10, 10)   -- 두께 0.3 (X축 = 길이축), 직경 10 stud
	warnDisk.Anchored = true
	warnDisk.CanCollide = false
	warnDisk.Massless = true
	warnDisk.Transparency = 0.35
	warnDisk.Material = Enum.Material.Neon
	warnDisk.Color = Color3.fromRGB(255, 50, 50)
	-- Cylinder의 길이축(X)이 표면 normal과 일치하도록 정렬 → 디스크 면이 표면에 평평하게 깔림
	-- 표면 위로 살짝 띄워서 z-fighting 방지
	warnDisk.CFrame = buildSurfaceCFrame(surfacePos + surfaceNormal * 0.15, surfaceNormal, "X")
	warnDisk.Parent = trap

	-- 경고 라이트
	if trap.HitBox then
		local light = Instance.new("PointLight")
		light.Name = "WarnLight"
		light.Color = Color3.fromRGB(255, 50, 50)
		light.Range = 14
		light.Brightness = 3
		light.Parent = trap.HitBox
	end

	-- CollisionGroup (라운드 종료 시 자동 정리)
	ensureTrapGroup()
	for _, part in ipairs(trap:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				-- HitBox 만 전용 그룹으로 분리한다.
				--   트랩은 TaggerItems 였고 TaggerItems↔TaggerItems=true 라서,
				--   굴러오는 통나무·배럴이 트랩 HitBox 에 걸려 멈추거나 튀었다.
				--   TaggerItems 끼리의 충돌을 끄면 아이템들이 서로 겹쳐 굴러가므로
				--   트랩 히트박스만 따로 빼서 아이템만 통과시킨다.
				--   (러너 감지는 Touched 이벤트라 콜리전과 무관하게 계속 동작한다)
				if part.Name == "HitBox" then
					part.CollisionGroup = "TrapHitbox"
				else
					part.CollisionGroup = "TaggerItems"
				end
			part:SetAttribute("NoContactDown", true)  -- 접촉 다운 면제: 트랩은 경고 후 '맞물림'으로만 잡음
			end)
		end
	end

	trap.Parent = workspace

	-- 활성 함정 목록에 등록
	table.insert(playerActiveTraps[player.UserId], trap)
	syncTrapCount(player)
	-- 함정이 사라지면(밟힘·라운드 정리·수명) 개수 표시도 같이 내려간다.
	-- ⚠️ 켜는 코드와 끄는 코드는 한 편집에. insert 만 넣고 이걸 빼면 표시가 5/5 로 굳는다.
	trap.AncestryChanged:Connect(function(_, parent)
		if not parent then syncTrapCount(player) end
	end)

	-- ⭐ 경고 사운드 (rbxassetid://16903690359)
	if trap.HitBox then
		local warnSound = Instance.new("Sound")
		warnSound.Name = "WarnSound"
		warnSound.SoundId = SND_WARNING
		warnSound.Volume = 1
		warnSound.RollOffMode = Enum.RollOffMode.InverseTapered
		warnSound.RollOffMaxDistance = 100
		warnSound.Parent = trap.HitBox
		warnSound:Play()
		Debris:AddItem(warnSound, 5)
	end

	print("🪤 Trap placed by", player.Name, "at", surfacePos, "normal=", surfaceNormal,
		string.format("(%d/%d, 1.5s warning)", #playerActiveTraps[player.UserId], MAX_TRAPS_PER_OWNER))

	-- WARNING_DURATION 후 활성화
	task.delay(WARNING_DURATION, function()
		if trap and trap.Parent then
			activateTrap(trap, player)
		end
	end)

	-- ⚠️ [2026-08-26] 성공을 명시적으로 알린다.
	--   [증상] 로그에 "❌ 최대 함정 개수 (5/5)" 바로 뒤에 "🪤 Bear trap dispatched" 가 찍혔다.
	--   [원인] ItemSpawnHandler 가 _G.placeTrap 의 반환을 안 보고 무조건 성공 처리 →
	--     설치가 거부됐는데도 쿨타임(전역 2.0 + 개별)을 먹었다.
	--   실패 경로는 전부 nil/false 를 반환하므로 호출부에서 그대로 분기 가능.
	return true
end

-- RemoteEvent (TrapPlacementClient 사용 시) 와 _G (ItemSpawnHandler 사용 시) 둘 다 지원
placeEvent.OnServerEvent:Connect(placeTrap)
_G.placeTrap = placeTrap

print("✅ TrapSystem ready")
