-- ToxBoxSystem
-- 'tox_box' 태거 아이템: 큐브가 굴러가는 위협체.
-- 패턴: 전진 3 + 좌/우 4 + 전진 3 + 좌/우 4 ... (계단형, hill 중앙 쪽)
-- 본체 면 접촉 → 다운(10초 블리드아웃). 빈 면(-Y local) 쪽 접촉 → 안전 통과.
-- 러너 베이스(playerbase) 도달 시 destroy + 새 박스 생성 가능.
-- 다른 태거 아이템과 충돌 X (전용 CollisionGroup).
-- ★ Hill 경계 강제 + 매 step 표면 Y 정렬.

local ServerStorage = game:GetService("ServerStorage")
local Players       = game:GetService("Players")
local DownSystem    = require(game:GetService("ServerScriptService"):WaitForChild("DownSystem"))
local PhysicsService= game:GetService("PhysicsService")
local RunService    = game:GetService("RunService")

local taggerItems    = ServerStorage:WaitForChild("TaggerItem")
local toxBoxTemplate = taggerItems:WaitForChild("tox_box")

-- 📏 [2026-08-31] pivot → 기하중심 로컬 오프셋.
--   [왜] tox_box 의 pivot 은 모델 중심과 일치하지 않는다(실측 로컬 (0, 3.46, 0)).
--     히트박스를 pivot 에 그대로 얹으면 실제 박스보다 3.46 stud 어긋난 자리에 뜬다.
--     Touched 는 실제 파트가 잡으니 티가 안 났는데, 폴링 범위를 조이자마자 드러났다
--     (실측 16:10 — 러너가 박스 옆 24 stud 인데 판정이 한 번도 안 걸림).
--   ⚠️ 템플릿에서 한 번만 잰다. 모델을 갈아끼우면 자동으로 따라간다 — 값을 박지 말 것.
local BOX_CENTER_OFFSET = (function()
	local pv   = toxBoxTemplate:GetPivot()
	local bbCF = toxBoxTemplate:GetBoundingBox()
	return pv:PointToObjectSpace(bbCF.Position)
end)()

-- ─── Tunables ─────────────────────────────────────
local CUBE_SIZE       = 30      -- 박스 한 변 길이 (Y BBox)
local STEP_ROLL       = 0.85    -- 한 step 회전 시간 (초)
local STEP_PAUSE      = 0.15    -- step 사이 정지 (초)
-- 🛡️ 방패에 막혔을 때 멈춰 있는 시간(초).
--   ⚠️ 쓰나미(1.2)와 비슷하게 잡는다. 한 step 굴림이 0.85초라 그보다 길어야
--     "멈췄다"가 눈에 보인다.
local TOXBOX_STALL_TIME = 1.5
local FORWARD_COUNT   = 3       -- 전진 횟수
local SIDE_COUNT      = 4       -- 좌/우 횟수
local BASE_HIT_RADIUS = 40      -- 베이스 도달 인식 반경
local EDGE_MARGIN     = 2       -- hill 가장자리에서 박스가 떨어지지 않을 여유 (stud)
-- 📏 [2026-08-31] 폴링 접촉 판정의 여유폭(stud). 박스 로컬 좌표 기준 half + 이 값.
--   ⚠️ GetPartBoundsInBox 는 파트 바운딩박스로 잡아 Touched 보다 관대하다.
--     실측 16:01 에 중심 거리 29 (박스 반폭 15) 에서 판정이 걸렸다 —
--     Y 차이만 26 이었는데도 통과했다. 그대로 두면 "안 닿았는데 다운"이 난다.
--   ⚠️ 키우면 관대해지고 줄이면 Touched 누락분을 놓친다.
--   ⚠️ [2026-08-31] 3 → 5. 3 으로 뒀더니 pivot 오프셋(3.46)이 마진을 통째로 먹어
--     러너가 박스 바로 옆에 있어도 안 걸렸다. 오프셋은 위에서 보정했고,
--     보정 뒤 기준으로 다시 잡은 값이다.
local POLL_MARGIN     = 5
-- ─── 굴림 사운드 ──
local ROLL_SOUND_ID     = "rbxassetid://138247332716810"
local ROLL_SOUND_VOLUME = 0.8   -- 기본 1.0에서 20% 감소
-- 빈 면 = 박스 로컬 -Y (자동 감지로 확정)
local EMPTY_FACE_LOCAL = Vector3.new(0, -1, 0)

-- ─── 박스 OBB 코너 캐싱 (정렬용) ─────────────────
-- ★ tox_box pivot이 모델 기하학적 중심과 일치하지 않으므로,
--   회전 시 실제 최저 world Y를 정확히 구하기 위해 pivot-local 8개 코너를 캐싱.
--   (이전 코드: pivot Y = surface + CUBE_SIZE/2 → 자세에 따라 박스가 뜨거나 잠김)
local function computeLocalOBBCorners(model)
	local pivotCF = model:GetPivot()
	local minP = Vector3.new(math.huge, math.huge, math.huge)
	local maxP = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local localCF = pivotCF:ToObjectSpace(p.CFrame)
			local h = p.Size * 0.5
			for _, sx in ipairs({-1, 1}) do
				for _, sy in ipairs({-1, 1}) do
					for _, sz in ipairs({-1, 1}) do
						local c = localCF * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						minP = Vector3.new(math.min(minP.X, c.X), math.min(minP.Y, c.Y), math.min(minP.Z, c.Z))
						maxP = Vector3.new(math.max(maxP.X, c.X), math.max(maxP.Y, c.Y), math.max(maxP.Z, c.Z))
					end
				end
			end
		end
	end
	local corners = {}
	for _, x in ipairs({minP.X, maxP.X}) do
		for _, y in ipairs({minP.Y, maxP.Y}) do
			for _, z in ipairs({minP.Z, maxP.Z}) do
				table.insert(corners, Vector3.new(x, y, z))
			end
		end
	end
	return corners
end
local LOCAL_OBB_CORNERS = computeLocalOBBCorners(toxBoxTemplate)

local function getLowestWorldY(box)
	local pivotCF = box:GetPivot()
	local minY = math.huge
	for _, corner in ipairs(LOCAL_OBB_CORNERS) do
		local w = pivotCF * corner
		if w.Y < minY then minY = w.Y end
	end
	return minY
end

-- ─── CollisionGroup ───────────────────────────────
-- ★ 새 API (IsCollisionGroupRegistered) 사용
-- ★ 다른 시스템보다 먼저 실행될 수 있으므로 의존 그룹을 모두 미리 등록
--   (이미 등록되어 있으면 RegisterCollisionGroup이 에러를 던지므로 IsCollisionGroupRegistered로 가드)
local function ensureGroup(name)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end
ensureGroup("ToxBox")
ensureGroup("TaggerItems")
ensureGroup("IceEffect")
ensureGroup("WoodShield")
ensureGroup("Mountains")
ensureGroup("Walls")

local function safeSetCollidable(a, b, c)
	local ok, err = pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, a, b, c)
	if not ok then warn("⚠️ CollisionGroupSetCollidable(" .. a .. ", " .. b .. ") 실패:", err) end
end
safeSetCollidable("ToxBox", "TaggerItems", false)
safeSetCollidable("ToxBox", "ToxBox",      false)
safeSetCollidable("ToxBox", "IceEffect",   false)
safeSetCollidable("ToxBox", "WoodShield",  false)
safeSetCollidable("ToxBox", "Mountains",   false)
safeSetCollidable("ToxBox", "Walls",       false)
print("✅ ToxBox 콜리전 그룹 설정")

-- ─── State ────────────────────────────────────────
local playerActiveBox = {}  -- userId → tox box

-- ─── 헬퍼: 러너 베이스 ───────────────────────────
-- [양 맵 공존 대응] 스폰 클릭 위치를 기준으로 가까운 맵의 것을 채택.
-- 각 map 폴더 안에서는 기존 이름 우선순위 체인을 그대로 유지한다.
local currentRefPos = nil  -- spawnToxBox에서 clickPosition으로 갱신

local function pickNearest(cands)
	if #cands == 0 then return nil end
	if #cands == 1 or not currentRefPos then return cands[1] end
	local best, bestD = nil, math.huge
	for _, c in ipairs(cands) do
		local p = c:IsA("BasePart") and c.Position
			or (c:IsA("Model") and c:GetPivot().Position)
		if p then
			local d = (p - currentRefPos).Magnitude
			if d < bestD then best, bestD = c, d end
		end
	end
	return best or cands[1]
end

local function findRunnerBase()
	-- 맵별 이름 폴백 체인: playerbase(map1) → playerspawn → playerspawn2 (map2엔 playerbase 없음)
	local cands = {}
	for _, mapFolder in ipairs(workspace:GetChildren()) do
		if mapFolder.Name:lower():find("map") then
			for _, name in ipairs({"playerbase", "playerspawn", "playerspawn2"}) do
				local pb = mapFolder:FindFirstChild(name, true)
				if pb and pb:IsA("BasePart") then
					table.insert(cands, pb)
					break  -- 폴더당 1개 (기존 우선순위 유지)
				end
			end
		end
	end
	return pickNearest(cands)
end

-- ─── 헬퍼: Hill 객체 / BBox ─────────────────────
local function findHill()
	-- 각 map 폴더에서 기존 체인("Hill" 재귀 → hill%d 폴백)으로 후보 1개씩 → 가까운 것 채택
	local cands = {}
	local h = workspace:FindFirstChild("Hill")
	if h then table.insert(cands, h) end
	for _, mapFolder in ipairs(workspace:GetChildren()) do
		if mapFolder.Name:lower():find("map") then
			-- [TOXHILL-DIRECT] 맵 폴더의 "직속 자식"에서 먼저 찾는다.
			--   기존에는 FindFirstChild("Hill", true) 재귀 검색이라
			--   map2."Desert scape" 안의 장식용 Hill(196×21×169, 14개)이 먼저 잡혔다.
			--   그 결과 클릭 (700,132,887) 이 장식물 OBB 로 클램프돼
			--   실제 스폰이 (-177,132,840) — 877 stud 어긋난 맵 밖에 생성됐다.
			--   실제 플레이 언덕은 map1.Hill(245×122×902) / map2.hill2(248×122×808) 로
			--   둘 다 맵 폴더 직속이고, 직속 검색이면 맵당 정확히 1개만 매치된다(실측).
			local h2 = nil
			for _, d in ipairs(mapFolder:GetChildren()) do
				if d.Name:lower():match("^hill%d*$") and (d:IsA("BasePart") or d:IsA("Model")) then
					h2 = d
					break
				end
			end
			-- 폴백: 직속에 없는 신규 맵 대비 (기존 경로 유지)
			if not h2 then h2 = mapFolder:FindFirstChild("Hill", true) end
			if not h2 then
				for _, d in ipairs(mapFolder:GetDescendants()) do
					if d.Name:lower():match("^hill%d*$") and (d:IsA("BasePart") or d:IsA("Model")) then
						h2 = d
						break
					end
				end
			end
			if h2 then table.insert(cands, h2) end
		end
	end
	return pickNearest(cands)
end

local function getHillBounds()
	local hill = findHill()
	if not hill then return nil end
	if hill:IsA("BasePart") then
		return hill.Position, hill.Size * 0.5, hill
	elseif hill:IsA("Model") then
		local cf, size = hill:GetBoundingBox()
		return cf.Position, size * 0.5, hill
	end
	return nil
end

-- Hill의 CFrame + 로컬 사이즈 반환 (회전 보존)
local function getHillCFrameAndSize()
	local hill = findHill()
	if not hill then return nil, nil, nil end
	if hill:IsA("BasePart") then
		return hill.CFrame, hill.Size, hill
	elseif hill:IsA("Model") then
		local cf, size = hill:GetBoundingBox()
		return cf, size, hill
	end
	return nil, nil, nil
end

-- 박스 중심이 hill OBB(회전 고려) 안인지
local function isInsideHillXZ(pos)
	local hillCF, hillSize = getHillCFrameAndSize()
	if not hillCF then return true end
	local edge = CUBE_SIZE * 0.5 + EDGE_MARGIN
	local localPos = hillCF:PointToObjectSpace(pos)
	return math.abs(localPos.X) <= (hillSize.X * 0.5 - edge)
	   and math.abs(localPos.Z) <= (hillSize.Z * 0.5 - edge)
end

-- 굴림 후 박스 중심 예상 위치 (수평 이동만)
local function predictNextPos(box, direction)
	return box:GetPivot().Position + direction * CUBE_SIZE
end

-- ─── 표면 Y 정렬 (raycast로 박스 아래 표면 찾기) ──
local function alignToSurface(box)
	if not box or not box.Parent then return end
	local cf = box:GetPivot()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {box}
	-- 박스 중심 위쪽에서 아래로 raycast
	local res = workspace:Raycast(
		cf.Position + Vector3.new(0, 50, 0),
		Vector3.new(0, -300, 0),
		rp
	)
	if not res then return end
	-- ★ 자세에 따라 박스 OBB 최저점이 표면에 닿도록 보정
	--   (pivot은 모델 중심과 일치하지 않으므로 코너 기반으로 계산)
	local currentLowest = getLowestWorldY(box)
	local delta = res.Position.Y - currentLowest
	if math.abs(delta) > 0.05 then
		box:PivotTo(cf + Vector3.new(0, delta, 0))
	end
end

-- ─── 1 step 굴림 ─────────────────────────────────
local function rollStep(box, direction)
	if not box or not box.Parent then return end

	-- 🛡️ 방패에 막혔으면 굴리기 전에 여기서 대기한다.
	--   ⚠️ 막힘 '판정'은 여기서 하지 않는다. 한때 여기서 다음 칸을 미리 조회했는데
	--     두 가지 이유로 못 잡았다:
	--       · step 이 CUBE_SIZE(30) 씩 건너뛰어 방패 반경(14)을 통째로 넘어간다.
	--       · 패턴이 '전진 3 + 좌우 4' 라 절반 이상이 측면 굴림이다. 그때 굴림 방향은
	--         방패 정면과 직각이라 방향 판정을 통과하지 못한다.
	--     판정은 실제 피해가 나는 hitbox.Touched 에서 한다(거기가 유일하게 정확하다).
	--   ⚠️ 굴린 뒤에 대기하면 막힌 걸 알고도 한 칸 더 전진한다 — 반드시 굴리기 앞에서.
	while box and box.Parent and box:GetAttribute("ShieldStallUntil")
	      and os.clock() < box:GetAttribute("ShieldStallUntil") do
		RunService.Heartbeat:Wait()
	end
	if not (box and box.Parent) then return end

	local startCF = box:GetPivot()

	-- ★ 굴림 사운드 재생
	local rollSound = box:FindFirstChild("RollSound", true)
	if rollSound then rollSound:Play() end

	local pivotOffset = direction * (CUBE_SIZE * 0.5) + Vector3.new(0, -CUBE_SIZE * 0.5, 0)
	local pivotWorld  = startCF.Position + pivotOffset

	local rotAxis = Vector3.new(0, 1, 0):Cross(direction)
	if rotAxis.Magnitude < 0.001 then return end
	rotAxis = rotAxis.Unit

	local startTime = tick()
	while box and box.Parent do
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / STEP_ROLL, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		local angle = math.rad(90 * eased)
		local rotation = CFrame.fromAxisAngle(rotAxis, angle)
		local newCF = CFrame.new(pivotWorld) * rotation * CFrame.new(-pivotWorld) * startCF
		box:PivotTo(newCF)
		if alpha >= 1 then break end
		RunService.Heartbeat:Wait()
	end

	-- ★ 굴림 끝 → 표면 Y로 보정 (hill 경사 따라 자연스럽게)
	alignToSurface(box)

	task.wait(STEP_PAUSE)
end

-- ─── 패턴 (hill 경계 + 베이스 방향이면 hill 밖도 허용) ───
-- ★ 박스가 hill 가장자리에서 멈추지 않고 베이스까지 굴러가려면,
--   "베이스 쪽"이고 "지면이 있는" 방향은 hill 밖이라도 허용해야 함.
local function canRollTo(box, pos, direction)
	-- hill 안이면 무조건 OK
	if isInsideHillXZ(pos) then return true end

	-- hill 밖이면 베이스 방향만 허용
	local base = findRunnerBase()
	if not base then return false end
	local currentPos = box:GetPivot().Position
	local toBase = base.Position - currentPos
	local toBaseH = Vector3.new(toBase.X, 0, toBase.Z)
	if toBaseH.Magnitude < 1 then return true end
	local dirH = Vector3.new(direction.X, 0, direction.Z)
	if dirH.Magnitude < 0.001 then return false end
	if dirH.Unit:Dot(toBaseH.Unit) < 0.5 then return false end

	-- 지면이 있고, 낭떠러지가 아니어야 함
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {box}
	local res = workspace:Raycast(pos + Vector3.new(0, 100, 0), Vector3.new(0, -400, 0), rp)
	if not res then return false end
	local drop = currentPos.Y - res.Position.Y
	if drop > CUBE_SIZE * 1.5 then return false end
	return true
end

local function tryRoll(box, primary, fallbacks)
	if not box or not box.Parent then return nil end
	-- 우선 방향 시도
	if canRollTo(box, predictNextPos(box, primary), primary) then
		rollStep(box, primary)
		return primary
	end
	-- 대체 방향 순차 시도
	for _, alt in ipairs(fallbacks) do
		if canRollTo(box, predictNextPos(box, alt), alt) then
			rollStep(box, alt)
			return alt
		end
	end
	return nil  -- 모두 막힘
end

local function cleanupBox(box, reason)
	if not box then return end
	local ownerId = box:GetAttribute("OwnerUserId")
	if ownerId and playerActiveBox[ownerId] == box then
		playerActiveBox[ownerId] = nil
		-- 🔓 [2026-08-27] UI 잠금 해제. 세우는 쪽은 ItemSpawnHandler 의 tox_box 분기.
		--   ⚠️ 여기가 모든 소멸 경로(베이스 도달·라운드 정리·수동 리셋)가 모이는 지점이라
		--     여기 한 곳만 붙이면 된다. 개별 경로에 흩어 놓으면 하나 빠뜨렸을 때 영구 잠김.
		do
			local plr = game:GetService("Players"):GetPlayerByUserId(ownerId)
			if plr and _G.SetItemLock then _G.SetItemLock(plr, "tox_box", false) end
		end
	end
	print(string.format("📦 Tox Box destroyed (%s)", reason or "?"))
	if box.Parent then box:Destroy() end
end

local function runPattern(box, forwardDir, sideDir)
	local currentSide = sideDir
	while box and box.Parent do
		-- 전진 페이즈
		for _ = 1, FORWARD_COUNT do
			if not box.Parent then return end
			-- forward 우선, 막히면 side → -side → -forward
			local used = tryRoll(box, forwardDir, {currentSide, -currentSide, -forwardDir})
			if not used then
				cleanupBox(box, "stuck (all directions blocked)")
				return
			end
		end
		-- 좌/우 페이즈
		for _ = 1, SIDE_COUNT do
			if not box.Parent then return end
			-- currentSide 우선, 막히면 반대 side로 영구 전환 → forward → -forward
			local used = tryRoll(box, currentSide, {-currentSide, forwardDir, -forwardDir})
			if not used then
				cleanupBox(box, "stuck (all directions blocked)")
				return
			end
			-- 반대 side로 갔으면 이후로도 그 방향 유지 (경계 부딪힘 영구 반영)
			if used == -currentSide then
				currentSide = -currentSide
			end
		end
	end
end

-- ─── 즉사 hitbox ────────────────────────────────
local function setupHitbox(box)
	-- 📏 [2026-08-31] 히트박스는 pivot 이 아니라 '기하중심'에 얹는다.
	--   pivot 을 그대로 쓰면 박스와 3.46 stud 어긋난 자리에 판정면이 생긴다.
	--   ⚠️ 아래 판정·진단이 전부 이 함수를 거치게 할 것. 한 곳만 pivot 을 쓰면
	--     그 경로만 조용히 어긋난다(이 시스템에서 이미 한 번 그랬다).
	local function centerCF()
		return box:GetPivot() * CFrame.new(BOX_CENTER_OFFSET)
	end

	local hitbox = Instance.new("Part")
	hitbox.Name         = "ToxHitbox"
	hitbox.Size         = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	hitbox.Transparency = 1
	hitbox.CanCollide   = false
	hitbox.Anchored     = true
	hitbox.Massless     = true
	hitbox.CFrame       = centerCF()
	hitbox.CollisionGroup = "ToxBox"
	hitbox.Parent = box

	-- 🔎 [진단 2026-08-31] 판정이 어디서 끊겼는지 한 줄로 남긴다.
	--   [증상] /atk tox 로 소환한 박스에 직접 부딪혀도 아무 일이 없었다.
	--     방패 판정 로그조차 0줄 — 아래 판정이 아예 안 불렸다는 뜻이다.
	--   ⚠️ 검증이 끝나면 diag / [ToxDiag] 만 걷어낸다. tryHit 분리와 폴링은 남길 것.
	local lastLog = {}
	local function diag(char, msg)
		local now = os.clock()
		if lastLog[char] and now - lastLog[char] < 1 then return end
		lastLog[char] = now
		warn(string.format("[ToxBox] 판정 중단 ← %s | %s", char and char.Name or "?", msg))
	end

	-- 📦 판정 본체. Touched 와 폴링이 함께 쓴다.
	--   ⚠️ 두 경로가 같은 프레임에 들어올 수 있어 캐릭터별로 짧게 묶어둔다.
	--     안 그러면 방패가 연달아 소모되고 로그도 스팸이 된다.
	local lastTry = {}
	local function tryHit(char, source)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end

		-- 🛡️ [2026-08-31] 방패에 막혀 멈춰 있는 동안은 아무도 못 때린다.
		--   [증상] 막은 지 0.3초 만에 그대로 다운됐다(실측 16:45 — 차단 28.467, 다운 28.783).
		--   [원인] ShieldStallUntil 은 rollStep 앞에서만 대기를 건다. 모델이 안 움직일 뿐
		--     히트박스는 러너와 겹친 채 남고, 폴링(0.1s)은 계속 돈다. tryHit throttle 이
		--     0.3초라 방패가 소모된 직후의 재판정이 통과했다.
		--   ⚠️ throttle 갱신보다 앞에 둔다. 여기서 lastTry 를 건드리면 stall 이 끝나는
		--     순간의 첫 판정이 밀린다.
		local stallUntil = box:GetAttribute("ShieldStallUntil")
		if stallUntil and os.clock() < stallUntil then return end

		local now = os.clock()
		if lastTry[char] and now - lastTry[char] < 0.3 then return end
		lastTry[char] = now

		local plr = Players:GetPlayerFromCharacter(char)
		if plr and plr:GetAttribute("Role") == "Tagger" then diag(char, "Role=Tagger — 태거는 대상 아님") return end
		if char.Name == "Noob" then return end
		if (plr and plr:GetAttribute("Downed")) or char:GetAttribute("Downed") then
			diag(char, "이미 다운 상태")
			return
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then diag(char, "HumanoidRootPart 없음") return end

		local boxCF     = centerCF()
		local boxCenter = boxCF.Position
		local toRunner  = (hrp.Position - boxCenter)
		if toRunner.Magnitude < 0.01 then return end
		toRunner = toRunner.Unit

		-- 📦 [2026-08-31 개정] 빈 면 판정을 '방향 dot' 에서 '접근한 면' 으로 바꿨다.
		--   [증상] 옆면으로 정면충돌했는데 빈 면으로 처리돼 그냥 통과했다
		--     (실측 16:28 — 로컬(-9, -13, 15), 지배 축은 Z 인데 dot 0.60 으로 안전 판정).
		--   [원인] 지면에 선 러너의 HRP 는 박스 중심보다 항상 13~18 아래다(반높이 15).
		--     빈 면이 아래를 향한 자세면 옆에서 와도 -Y 성분이 늘 커서 dot 이 0.4 를 넘는다.
		--     정작 그 면은 땅에 깔려 있어 러너가 닿을 수조차 없는 면이다.
		--   [해결] 로컬 방향에서 절대값이 가장 큰 축 = 러너가 실제로 접근한 면.
		--     그 면이 빈 면일 때만 통과시킨다. 박스 위에 올라탄 경우는 그대로 걸러진다.
		local ld = boxCF:VectorToObjectSpace(toRunner)
		local ax, ay, az = math.abs(ld.X), math.abs(ld.Y), math.abs(ld.Z)
		local faceNormal
		if ax >= ay and ax >= az then
			faceNormal = Vector3.new(ld.X > 0 and 1 or -1, 0, 0)
		elseif ay >= az then
			faceNormal = Vector3.new(0, ld.Y > 0 and 1 or -1, 0)
		else
			faceNormal = Vector3.new(0, 0, ld.Z > 0 and 1 or -1)
		end
		if faceNormal:Dot(EMPTY_FACE_LOCAL) > 0.9 then
			diag(char, string.format("빈 면으로 접근 (로컬방향 %.2f,%.2f,%.2f) — 설계상 안전 통과",
				ld.X, ld.Y, ld.Z))
			return
		end
		if _G.isInvincible and _G.isInvincible(char) then
			diag(char, "i-frame(산데비스탄) 중")
			return
		end

		print(string.format("📦 [ToxBox] 접촉 판정 진입 ← %s (경로: %s)", char.Name, source))

		-- 🛡️ [2026-08-30] 우든 실드 엄폐 판정. 피해가 들어가는 '이 지점'에서 본다.
		--   [왜 여기인가] 처음엔 굴리기 단계에서 막으려 했는데 안 됐다. 실제 피해는
		--     이 지점에서 나오므로, 거길 안 건드리면 방패가 개입할 자리가 없다
		--     (실측 15:16 — 박스가 방패를 지나 그대로 다운시켰다).
		--   [방향] toRunner = 박스 → 러너. 그게 곧 공격이 오는 방향이다.
		--     굴림 방향(direction)은 못 쓴다 — 톡스박스는 좌우로도 굴러서
		--     러너를 때리는 순간의 굴림 방향이 실제 가해 방향과 다를 수 있다.
		--   ⚠️ 엄폐형(반경 60)을 쓴다. 박스가 한 변 30 짜리라 러너가 방패에서
		--     꽤 떨어진 채로 맞을 수 있다 — 발사체용 반경 14 로는 안 걸린다.
		--   ⚠️ [2026-08-31] 세 번째 인자 true = 각도 조건 무시. 톡스박스 전용이다.
		--     방패 facing 은 +X 고정인데 박스는 측면 4 step 동안 ±Z 로 굴러온다.
		--     그 구간에서는 둘이 직각이라 각도 조건을 구조적으로 통과할 수 없다
		--     (실측 16:01 — 정면받나? 0.09, 공격방향 (-0.05, 1.00)).
		--     위치 조건은 그대로라 방패 뒤에 있어야 막히는 건 변함없다.
		if _G.WoodShieldBlocks and _G.WoodShieldBlocks(char, toRunner, true) then
			print("📦 Tox Box → 방패에 차단:", char.Name)
			-- 시각 피드백: 그 자리에 잠깐 멈춘다(쓰나미와 같은 규칙).
			box:SetAttribute("ShieldStallUntil", os.clock() + TOXBOX_STALL_TIME)
			return
		end
		-- 즉사가 아니라 다운(10초 블리드아웃) — 다른 접촉류 아이템과 동일 규칙.
		-- triggerDown 내부 가드(이미 다운/사망 시 무시)가 있어 이중 호출 안전.
		local triggered = DownSystem.triggerDown(char)
		if triggered then
			print("🩸 Tox Box → 다운:", char.Name)
		else
			diag(char, "triggerDown 이 false 를 반환")
		end
	end

	hitbox.Touched:Connect(function(hit)
		tryHit(hit.Parent, "Touched")
	end)

	-- 📦 [2026-08-31] 폴링 백업.
	--   [왜] Anchored 파트를 CFrame 으로 텔레포트시키면 Touched 가 누락될 수 있다.
	--     WoodShieldManager:125 에 "둘 다 Anchored 라 Touched 가 아예 발생하지 않는다"고
	--     이미 적혀 있었는데, 박스 ↔ 러너 쪽도 같은 함정을 갖고 있었던 셈이다.
	--   ⚠️ 진단 겸용이다. 로그에 "경로: 폴링" 이 찍히면 Touched 가 원인이었다는 증거고,
	--     "경로: Touched" 로 찍히면 접촉은 되고 있었다는 뜻이다.
	local hitAcc, diagAcc = 0, 0
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { box }
	op.CollisionGroup = "ToxBox"   -- 박스 관점에서 실제로 부딪히는 것만 (WoodShield 는 자동 제외)

	local followConn
	followConn = RunService.Heartbeat:Connect(function(dt)
		if not box.Parent or not hitbox.Parent then
			followConn:Disconnect()
			return
		end
		hitbox.CFrame = centerCF()

		hitAcc += dt
		if hitAcc >= 0.1 then
			hitAcc = 0
			local seen = {}
			-- ⚠️ [2026-08-31] 수집 범위를 POLL_MARGIN 만큼 넓혀서 던진다.
			--   [왜] 히트박스 실물 크기(half 15)로 수집하면 1차가 아래 2차(한계 20)보다
			--     빡빡해져서 2차가 아무 역할도 못 한다. 그 상태로 진단만 2차를 재현하니
			--     "✅범위안" 이 뜨는데 판정은 안 들어오는 모순이 났다(실측 16:19).
			--   ⚠️ 여기 크기와 아래 lim 은 반드시 같은 값에서 나와야 한다.
			local probeSize = hitbox.Size + Vector3.new(POLL_MARGIN, POLL_MARGIN, POLL_MARGIN) * 2
			for _, p in ipairs(workspace:GetPartBoundsInBox(hitbox.CFrame, probeSize, op)) do
				-- 액세서리 Handle 이면 한 단계 더 올라가야 캐릭터가 나온다.
				local ch = p.Parent
				if ch and not ch:FindFirstChildOfClass("Humanoid") then ch = ch.Parent end
				if ch and not seen[ch] and ch:FindFirstChildOfClass("Humanoid") then
					seen[ch] = true
					-- 📏 박스 로컬 좌표로 다시 잰다. GetPartBoundsInBox 결과를 그대로 믿으면
					--   박스 위/옆으로 한참 떨어진 러너까지 잡힌다(실측 16:01, 중심 거리 29).
					local phrp = ch:FindFirstChild("HumanoidRootPart")
					if phrp then
						local lp  = hitbox.CFrame:PointToObjectSpace(phrp.Position)
						local lim = CUBE_SIZE * 0.5 + POLL_MARGIN
						if math.abs(lp.X) <= lim and math.abs(lp.Y) <= lim and math.abs(lp.Z) <= lim then
							tryHit(ch, "폴링")
						end
					end
				end
			end
		end

		-- 🔎 [진단 2026-08-31] 박스가 나를 스치기는 하는지. 검증 후 삭제할 것.
		diagAcc += dt
		if diagAcc >= 0.5 then
			diagAcc = 0
			local bcf = hitbox.CFrame
			local c   = bcf.Position
			local lim = CUBE_SIZE * 0.5 + POLL_MARGIN
			for _, plr in ipairs(Players:GetPlayers()) do
				local h = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if h then
					local d = (h.Position - c).Magnitude
					if d <= 45 then
						-- ⚠️ 판정은 로컬 축별로 본다. 거리만 찍으면 어느 축이 넘쳤는지 모른다.
						local lp = bcf:PointToObjectSpace(h.Position)
						print(string.format("[ToxDiag] %s 거리 %.0f | 로컬(%.0f, %.0f, %.0f) 한계 %d%s | 박스(%.0f,%.0f,%.0f) 나(%.0f,%.0f,%.0f)",
							plr.Name, d, lp.X, lp.Y, lp.Z, lim,
							(math.abs(lp.X) <= lim and math.abs(lp.Y) <= lim and math.abs(lp.Z) <= lim) and " ✅범위안" or "",
							c.X, c.Y, c.Z, h.Position.X, h.Position.Y, h.Position.Z))
					end
				end
			end
		end
	end)
end

-- ─── 베이스 도달 감지 ────────────────────────────
local function setupBaseDetection(box, ownerId)
	local base = findRunnerBase()
	if not base then
		warn("⚠️ ToxBoxSystem: playerbase 못 찾음")
		return
	end
	task.spawn(function()
		while box and box.Parent do
			local dist = (box:GetPivot().Position - base.Position).Magnitude
			if dist < BASE_HIT_RADIUS then
				cleanupBox(box, "reached runner base")
				return
			end
			task.wait(0.25)
		end
	end)
end

-- ─── 헬퍼: spawn 위치를 hill 위로 보정 ────────────
local function findSpawnPos(clickPos, forwardDir)
	local hill = findHill()
	if not hill then return clickPos end

	-- 1) clickPos 아래 raycast → hill 전용 Include 필터로 정확히 hill 표면만 검색
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = {hill}

	local res = workspace:Raycast(
		clickPos + Vector3.new(0, 200, 0),
		Vector3.new(0, -500, 0),
		rp
	)
	if res then
		return res.Position  -- hill 표면
	end

	-- 2) clickPos가 hill 밖 → hill OBB 안쪽 가장자리로 클램프 (회전 고려)
	local hillCF, hillSize = getHillCFrameAndSize()
	if not hillCF then
		return clickPos
	end
	local edge = CUBE_SIZE * 0.5 + EDGE_MARGIN
	local localPos = hillCF:PointToObjectSpace(clickPos)
	local halfX = math.max(hillSize.X * 0.5 - edge, 0)
	local halfZ = math.max(hillSize.Z * 0.5 - edge, 0)
	local clampedLocal = Vector3.new(
		math.clamp(localPos.X, -halfX, halfX),
		localPos.Y,
		math.clamp(localPos.Z, -halfZ, halfZ)
	)
	local clampedWorld = hillCF:PointToWorldSpace(clampedLocal)

	-- 클램프된 점에서 hill 표면 Y 다시 raycast
	local res2 = workspace:Raycast(
		clampedWorld + Vector3.new(0, 200, 0),
		Vector3.new(0, -500, 0),
		rp
	)
	if res2 then
		return res2.Position
	end
	return clampedWorld
end

-- ─── 강제 정리 (디버그/관리용) ────────────────────
local function forceCleanupAllBoxes()
	for uid, box in pairs(playerActiveBox) do
		if box and box.Parent then
			print("🧹 forceCleanup: destroy box of userId", uid)
			box:Destroy()
		end
	end
	playerActiveBox = {}
	-- workspace에 떠있는 미관리 박스도 정리
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "tox_box" then
			print("🧹 forceCleanup: orphan tox_box destroy", child:GetFullName())
			child:Destroy()
		end
	end
	print("✅ ToxBox 전체 정리 완료")
end
_G.resetToxBox = forceCleanupAllBoxes

-- ─── spawn ──────────────────────────────────────
local -- 🧪 [2026-08-27] 반환값 도입: 성공 true / 거부 false.
--   [증상] 이전 박스가 살아 있어 거부됐는데도 ItemSpawnHandler 가 쿨(3초)을 소모했다.
--     로그 실측: "❌ 이전 박스 살아있음" 바로 뒤에 "📦 Tox Box dispatched".
--     태거는 아무 일도 안 일어난 채 쿨만 날린다.
--   [원인] 모든 거부 경로가 값 없는 return 이라 호출부가 성공/실패를 구분할 수 없었다.
--   ⚠️ bear_trap 이 2026-08-27 에 같은 버그로 고쳐졌다(placeTrap 반환값 도입).
--     "별도 시스템에 위임" 패턴은 전부 이 함정을 갖는다 — 새 위임 아이템을 만들 땐
--     반환값을 먼저 정할 것.
function spawnToxBox(player, clickPosition)
	print(string.format("📦 [ToxBox] spawn 요청: %s @ (%.0f, %.0f, %.0f)",
		player and player.Name or "?",
		clickPosition and clickPosition.X or 0,
		clickPosition and clickPosition.Y or 0,
		clickPosition and clickPosition.Z or 0))

	if not player or not clickPosition then
		warn("  ❌ player/clickPos nil"); return false
	end
	if typeof(clickPosition) ~= "Vector3" then
		warn("  ❌ clickPosition is not Vector3"); return false
	end
	currentRefPos = clickPosition  -- 양 맵 공존 시 hill/base를 이 위치 기준으로 선택
	if player:GetAttribute("Role") ~= "Tagger" then
		warn("  ❌ Role != Tagger:", tostring(player:GetAttribute("Role"))); return false
	end
	if player:GetAttribute("Frozen") then
		warn("  ❌ Frozen"); return false
	end

	-- 이전 박스 체크 (자세히)
	local existing = playerActiveBox[player.UserId]
	if existing then
		if existing.Parent then
			local pos = existing:GetPivot().Position
			warn(string.format(
				"  ❌ 이전 박스 살아있음: %s @ (%.0f, %.0f, %.0f). 정리하려면 _G.resetToxBox() 또는 박스 베이스 도달 대기.",
				existing:GetFullName(), pos.X, pos.Y, pos.Z))
			return false
		else
			print("  ⚠️ 이전 박스 reference만 남음 (Parent nil) → 정리하고 진행")
			playerActiveBox[player.UserId] = nil
		end
	end

	local box = toxBoxTemplate:Clone()
	for _, p in ipairs(box:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "ToxBox"
		end
	end
	print("  ✓ 클론 + CollisionGroup 적용")

	-- 굴림 사운드 부착 (3D 사운드 → 첫 BasePart 자식에 부착)
	local soundHost
	for _, p in ipairs(box:GetDescendants()) do
		if p:IsA("BasePart") then soundHost = p; break end
	end
	if soundHost then
		local rollSound = Instance.new("Sound")
		rollSound.Name = "RollSound"
		rollSound.SoundId = ROLL_SOUND_ID
		rollSound.Volume = ROLL_SOUND_VOLUME
		rollSound.RollOffMode = Enum.RollOffMode.InverseTapered
		rollSound.Parent = soundHost
	end

	-- 방향 결정
	local base = findRunnerBase()
	if not base then
		warn("  ⚠️ playerbase 못 찾음 → forward fallback (-X)")
	end
	local hill = findHill()
	if not hill then
		warn("  ⚠️ Hill 못 찾음 → hill 경계 체크 비활성화됨")
	else
		print("  ✓ Hill 발견:", hill:GetFullName())
	end
	local hillCenter = getHillBounds() or Vector3.new(0, 0, 0)

	local forwardDir = Vector3.new(-1, 0, 0)
	if base then
		local toBase = base.Position - clickPosition
		local horizontal = Vector3.new(toBase.X, 0, toBase.Z)
		if horizontal.Magnitude > 0.1 then
			forwardDir = horizontal.Unit
		end
	end

	local rightOfForward = Vector3.new(0, 1, 0):Cross(forwardDir).Unit
	local toHillCenter = Vector3.new(
		hillCenter.X - clickPosition.X, 0,
		hillCenter.Z - clickPosition.Z
	)
	local sideDir
	if toHillCenter:Dot(rightOfForward) > 0 then
		sideDir = rightOfForward
	else
		sideDir = -rightOfForward
	end

	-- ★ spawn 위치를 hill 표면 위로 보정
	local surfacePos = findSpawnPos(clickPosition, forwardDir)
	local spawnPos = surfacePos + Vector3.new(0, CUBE_SIZE * 0.5, 0)
	print(string.format("  ✓ findSpawnPos → surface=(%.1f, %.1f, %.1f), final box center=(%.1f, %.1f, %.1f)",
		surfacePos.X, surfacePos.Y, surfacePos.Z,
		spawnPos.X, spawnPos.Y, spawnPos.Z))

	local boxCF = CFrame.lookAt(spawnPos, spawnPos + forwardDir, Vector3.new(0, 1, 0))
	box:PivotTo(boxCF)

	box:SetAttribute("OwnerUserId", player.UserId)
	-- 🔥 [버그수정 2026-09-20] 불벽 청소 대상에 포함시킨다.
	--   [증상] 박스가 불꽃벽을 지나쳐도 안 사라지고 계속 굴러갔다(제보).
	--   [원인] FirePressureSystem.cleanupItemsBehindFire 의 그물 셋에 전부 안 걸렸다:
	--     ① 표식(TaggerSpawnedItem) — 여기서 안 붙였다
	--     ② CollisionGroup=="TaggerItems" — 박스는 전용 "ToxBox" 그룹이다
	--     ③ 이름 "Wooden Barrel"/"Wood Log" — 박스 이름은 tox_box
	--     그래서 종료 사유가 '베이스 도달'과 '완전 차단' 둘뿐이었다(cleanupBox 호출 3곳).
	--   [왜 표식인가] 이름·콜리전 그룹은 이미 두 번 깨진 기준이다
	--     (RoundSystem 2026-09-02 / FirePressureSystem 2026-09-19 주석 — 같은 버그 두 번).
	--     "이름 목록보다 속성"이 이 게임의 정답 형태다.
	--   ⚠️ 이 표식은 조준 레이캐스트 제외에도 쓰인다(TaggerUIScript · EnergyBall · DemonSpear).
	--     이제 박스 위가 아니라 그 아래 지면에 조준된다 — 다른 스폰 아이템과 같은 취급이 된다.
	box:SetAttribute("TaggerSpawnedItem", true)
	box.Parent = workspace
	playerActiveBox[player.UserId] = box

	-- ⚠️ [2026-09-20] 외부 Destroy 안전망. **위 표식과 한 짝이다.**
	--   표식을 붙이는 순간 cleanupBox 를 거치지 않는 소멸 경로가 생긴다 —
	--   불벽 청소와 RoundSystem 표식 그물이 obj:Destroy() 를 직접 부른다.
	--   그 경로로 사라지면 playerActiveBox 와 UI 잠금이 남아 그 라운드 내내 "IN USE" 로 굳는다.
	--   위 cleanupBox 주석이 경고하는 바로 그 영구 잠김이다.
	--   [해결] 인스턴스 자신의 Destroying 에 건다. 어느 경로로 죽든 반드시 지나간다.
	--   ⚠️ 잠금 해제는 조건 없이 한다. 중복 해제는 무해하지만(FireClient false),
	--     테이블 비교를 조건으로 걸면 forceCleanupAllBoxes 처럼 테이블을 통째로
	--     교체하는 경로에서 해제가 통째로 누락된다.
	--   ⚠️ 새 박스가 먼저 생겨 옛 박스 해제가 그걸 덮을 일은 없다 — 게이트(spawnToxBox 상단)가
	--     옛 박스의 Parent 가 살아 있는 동안 새 스폰을 막으므로 순서가 보장된다.
	do
		local uid = player.UserId
		local thisBox = box
		box.Destroying:Connect(function()
			if playerActiveBox[uid] == thisBox then
				playerActiveBox[uid] = nil
				print("📦 Tox Box destroyed (외부 정리 — 불벽/라운드 그물)")
			end
			local plr = game:GetService("Players"):GetPlayerByUserId(uid)
			if plr and _G.SetItemLock then _G.SetItemLock(plr, "tox_box", false) end
		end)
	end

	-- 🎨 스킨 색 적용: Rainbow(장착) 우선 → ITEM COLOR(ToxColor_Steel). 대상=SkinPaintPart 속성 파트(청회/적갈)만
	do
		local targets = {}
		for _, p in ipairs(box:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("SkinPaintPart") then
				targets[#targets + 1] = p
			end
		end
		local skin = _G.getEquippedSkin and _G.getEquippedSkin(player, "tox_box")
		if skin == "RainbowToxBox" and player:GetAttribute("Has_RainbowToxBox") == true then
			-- Rainbow: 대상 파트 Neon + Heartbeat hue 순환 (box 소멸 시 자동 해제)
			for _, p in ipairs(targets) do p.Material = Enum.Material.Neon end
			local hue = 0
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not (box and box.Parent) then if conn then conn:Disconnect() end return end
				hue = (hue + dt * 0.25) % 1
				local col = Color3.fromHSV(hue, 1, 1)
				for _, p in ipairs(targets) do if p.Parent then p.Color = col end end
			end)
			print("📦 ToxBox: Rainbow 순환 (" .. #targets .. " 파트)")
		else
			-- ITEM COLOR: ToxColor_Steel 속성 있을 때만 색칠(없으면 원본 청회/적갈 유지)
			local colorName = player:GetAttribute("ToxColor_Steel")
			if colorName then
				local ok, palette = pcall(function()
					return require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
				end)
				if ok and palette and palette.COLORS[colorName] then
					local cfg = palette.getConfig("tox_box")
					local finishKey = player:GetAttribute("ToxMaterial_Steel") or (cfg and cfg.materialDefault)
					for _, p in ipairs(targets) do
						palette.applyFinish(p, finishKey, palette.COLORS[colorName])
					end
					print("📦 ToxBox 색:", colorName, finishKey, "(" .. #targets .. " 파트)")
				end
			end
		end
	end

	-- ★ spawn 직후 즉시 표면 정렬 (코너 기반)
	alignToSurface(box)

	print(string.format(
		"  📦 spawned | fwd=(%.2f, %.2f, %.2f) side=(%.2f, %.2f, %.2f)",
		forwardDir.X, forwardDir.Y, forwardDir.Z,
		sideDir.X, sideDir.Y, sideDir.Z
	))

	setupHitbox(box)
	setupBaseDetection(box, player.UserId)
	task.spawn(runPattern, box, forwardDir, sideDir)
	print("  ✓ hitbox + base detection + pattern 시작")
	return true   -- ✅ 여기까지 왔으면 실제로 스폰됐다. 호출부가 쿨을 소모해도 된다.
end

_G.spawnToxBox = spawnToxBox
print("✅ ToxBoxSystem ready (hill-bounded + surface aligned + debug v2)")
