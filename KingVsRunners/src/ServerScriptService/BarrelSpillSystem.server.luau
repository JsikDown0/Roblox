-- ═══════════════════════════════════════════════════════════════
-- 🛢️ BarrelSpillSystem — 배럴 액체 지대
--
-- [무엇] 배럴이 러너에게 닿는 순간 배럴은 그 자리에서 사라지고,
--   미끄러운 액체 웅덩이가 8초간 남는다.
--
-- [왜] 배럴이 통나무의 하위호환이었다. 커버 폭 25 vs 40 이고 속도도 같아
--   고를 이유가 없었다(실플레이 판단 2026-08-26).
--   역할을 이렇게 가른다:
--     · 통나무 : 맞힌다 (넓게 쓸고 지나감)
--     · 배럴   : 못 피하게 만든다 (한 번 맞히고 그 자리를 잠금)
--
-- [설계 결정]
--   · "멈추면 터진다" 가 아니라 "맞으면 터진다" 다. 멈추는 자리는 지형이 정하지만
--     맞는 자리는 태거가 정한다 → 조준에 의미가 생기고, 러너가 몰린 곳에서 터진다.
--   · 배럴이 사라지는 건 손해가 아니다. 관통을 포기하는 대신 지대를 남기는 교환이다.
--   · 데미지는 준다. 다만 지대 파트가 인스턴스 하나이므로 ItemDamageSystem 의
--     "1발사 = 1히트" 기록이 그대로 적용된다 → 러너당 딱 한 번만 맞는다.
--     이미 맞은 러너는 계속 미끄러지기만 한다. 별도 로직이 필요 없다.
--
-- ⚠️ 미끄러짐은 마찰 제거 방식이다. Humanoid 는 WalkSpeed 로 직접 움직여서
--   마찰 영향이 약할 수 있다 — 체감이 부족하면 관성 흉내로 바꿔야 한다.
-- ⚠️ 지대는 라운드 종료 시에만 정리한다. 2단계까지 남아도 무해하다 —
--   태거는 미끄러짐·피해 어느 쪽도 대상이 아니고, BASE-BLOCK 이 베이스 안 생성을
--   막으며, 수명 8초라 곧 사라진다.
--   (단계 경계에서 지우면 "1단계 막판에 뿌린 것만 손해" 라는 형평성 문제가 생긴다)
-- ═══════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ⚠️ 상수는 전부 공유 모듈에서 읽는다. 클라이언트(BarrelSlipClient)도 같은 모듈을
--   쓰므로 값이 어긋날 수 없다. 값 변경은 BarrelSpillConfig 에서만.
local CFG = require(ReplicatedStorage:WaitForChild("BarrelSpillConfig"))

local RADIUS        = CFG.RADIUS
local DURATION      = CFG.DURATION
local THICKNESS     = CFG.THICKNESS
local FADE_TIME     = CFG.FADE_TIME
local HEIGHT_SLACK  = CFG.HEIGHT_SLACK
local SLIP_RESPONSE = CFG.SLIP_RESPONSE
local TICK_DAMAGE   = CFG.TICK_DAMAGE
local TICK_INTERVAL = CFG.TICK_INTERVAL
local LIQUIDS       = CFG.LIQUIDS
local DEFAULT_LIQUID = LIQUIDS[CFG.DEFAULT_LIQUID_KEY]

local activeSpills = {}   -- [Part] = true. 단계 전환 시 정리용

-- ── 미끄러짐 적용 (봇 전용) ──────────────────────────────────
-- ⚠️ 플레이어는 여기서 처리하지 않는다. 플레이어 캐릭터는 클라이언트가 물리
--   소유권을 가져서 서버가 AssemblyLinearVelocity 를 써도 클라가 덮어쓴다
--   (서버가 이기려면 SetNetworkOwner(nil) 이 필요한데, 그러면 조작이 고무줄이 된다).
--   → 플레이어 미끄러짐은 BarrelSlipClient 가 클라이언트에서 처리한다.
--   여기 남은 로직은 서버가 소유한 AI 러너 전용이다.
local slipVel = {}   -- [Character] = 직전 수평 속도(Vector3)

local function applySlip(character, hrp)
	-- 🚫 [2026-08-27] AI 러너도 웅덩이 안에선 대시 봉인 대상으로 표시한다.
	--   지금 AI 러너가 대시를 쓰는지는 미확인이지만, 규칙은 러너 전체에 같아야
	--   나중에 AI 에 대시가 붙어도 자동으로 적용된다(빠뜨리기 쉬운 자리).
	if not character:GetAttribute("InBarrelSpill") then
		character:SetAttribute("InBarrelSpill", true)
	end
	local cur = hrp.AssemblyLinearVelocity
	local curH = Vector3.new(cur.X, 0, cur.Z)
	local prev = slipVel[character]
	if prev then
		-- 직전 속도 쪽으로 끌어당긴다 = 방향 전환이 둔해진다
		local blended = prev:Lerp(curH, SLIP_RESPONSE)
		-- ⚠️ Y 는 건드리지 않는다. 점프·낙하가 깨진다.
		hrp.AssemblyLinearVelocity = Vector3.new(blended.X, cur.Y, blended.Z)
		slipVel[character] = blended
	else
		slipVel[character] = curH
	end
end

local function clearSlip(character)
	slipVel[character] = nil
	-- 🚫 [2026-08-27] "켜는 코드에는 끄는 코드를 같이".
	--   AI 러너용. 유저는 BarrelSlipClient 가 자기 캐릭터에 직접 세운다.
	if character and character.Parent and character:GetAttribute("InBarrelSpill") then
		character:SetAttribute("InBarrelSpill", nil)
	end
end

-- ── 액체 웅덩이 생성 ─────────────────────────────────────────
-- ⚠️ [버그 수정 2026-08-26] 웅덩이가 공중에 생성됐다.
--   [원인] 지면을 찾는 레이가 '배럴 자기 자신' 을 맞았다. position 은 배럴 중심인데
--     배럴 지름이 18.5 라, 중심 +10 에서 아래로 쏘면 배럴 윗면에 바로 걸린다.
--     제외 목록에 workspace.Runners 폴더만 넣었는데 그건 존재하지도 않아
--     사실상 아무것도 제외되지 않았다.
--   [해결] ① 지면 기준을 러너 발밑으로 잡는다(러너는 땅에 서 있다).
--          ② 배럴·캐릭터·다른 아이템·기존 웅덩이를 전부 제외한다.
--          ③ 경사면 법선이 너무 누우면(벽에 맞음) 수직으로 폴백한다.
local function spawnSpill(position, itemName, barrelModel, character)

	-- 🚫 [BASE-BLOCK 2026-08-27] 태거 베이스 안에는 웅덩이를 만들지 않는다.
	--   [왜] 베이스(성 앞 평지)는 "푸시툴로만 대항하는 결투 구역" 이다. 즉사·투척
	--     아이템 반입이 금지된 이유와 같다 — 미끄러짐 지대가 들어가면 그 원칙이 깨지고,
	--     특히 2026-08-27 에 웅덩이가 '대시 봉인' 을 걸게 되면서 러너의 회피 수단을
	--     결투 구역에서 통째로 빼앗는 셈이 됐다.
	--   ⚠️ 판정은 _G.IsOnTaggerBase 를 쓴다. 복사하지 말 것 — 그 함수는 ItemSpawnPlate
	--     중첩과 부동소수점 오차(EDGE_EPS)까지 처리한다.
	--   ⚠️ 배럴 자체는 굴러 들어와도 된다. 막는 건 '파열 웅덩이' 뿐이다.
	if _G.IsOnTaggerBase then
		local checkPos = position
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then checkPos = hrp.Position end
		end
		if typeof(checkPos) == "Vector3" and _G.IsOnTaggerBase(checkPos) then
			print("🚫 [BarrelSpill] 태거 베이스 — 웅덩이 생성 안 함")
			return
		end
	end
	local liquid = LIQUIDS[itemName] or DEFAULT_LIQUID

	-- 레이 제외 목록: 지면이 아닌 것은 전부 뺀다.
	local exclude = {}
	if barrelModel then table.insert(exclude, barrelModel) end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	for _, d in ipairs(workspace:GetChildren()) do
		-- 봇 러너 + 스폰된 태거 아이템(Model/BasePart 양쪽) + 기존 웅덩이
		if d:GetAttribute("AIRunner") or d:GetAttribute("TaggerSpawnedItem")
		   or d.Name == "_BarrelSpill" then
			table.insert(exclude, d)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	-- ⚠️ 시작점은 러너 발밑 우선. 러너는 땅에 서 있으므로 가장 믿을 만한 기준이다.
	--   배럴 중심을 쓰면 지름의 절반만큼 떠 있어 오차가 생긴다.
	local origin = position
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then origin = hrp.Position end
	end

	local ray = workspace:Raycast(origin + Vector3.new(0, 5, 0), Vector3.new(0, -300, 0), params)
	local groundPos = ray and ray.Position or origin
	local normal = ray and ray.Normal or Vector3.new(0, 1, 0)
	-- 벽이나 급경사에 맞으면 웅덩이가 세로로 선다 → 수직으로 폴백
	if normal.Y < 0.5 then normal = Vector3.new(0, 1, 0) end

	local pool = Instance.new("Part")
	pool.Name = "_BarrelSpill"
	pool.Shape = Enum.PartType.Cylinder
	pool.Color = liquid.color
	pool.Material = liquid.material
	pool.Transparency = 0.25
	pool.Anchored = true
	pool.CanCollide = false
	-- ⚠️ [수정 2026-08-26] 접촉 판정(processHit) 없음.
	--   [왜] 처음엔 "1히트 1다운" 으로 만들었으나 실플레이에서 웅덩이만 밟아도
	--   다운돼 버렸다(17:27 실측). 배럴은 이미 굴러가며 한 번 때린다.
	--   웅덩이까지 때리면 한 발에 2히트라 "1발사 1히트" 원칙이 깨진다.
	--   [구현] CollisionGroup 을 TaggerItems 로 두지 않는다. ItemDamageSystem 은
	--   그 그룹의 Touched 만 processHit 에 연결하므로, 그룹만 안 주면 판정 자체가 없다.
	-- 🩸 [2026-09-01] 단, 지속 피해는 별도 축으로 추가됐다(applyTickDamage).
	--   Touched 가 아니라 거리 판정 루프에서 TakeDamage 로 직접 준다. 위 원칙과
	--   충돌하지 않는다 — processHit 을 안 타므로 히트 수에도 내구도에도 안 잡힌다.
	--   ⚠️ 그래서 이 파트의 CanTouch/CollisionGroup 설정은 그대로 둘 것. 여기를
	--     TaggerItems 로 바꾸면 2026-08-26 의 "1히트 1다운" 이 그대로 부활한다.
	pool.CanTouch = false
	pool.CanQuery = false     -- ⚠️ 태거 조준 레이를 막으면 안 된다
	pool.CastShadow = false

	-- 🤖 [2026-09-15] 농민봇 위험지대 등록 (프드 얼음과 같은 사유).
	--   [원인] RunnerBotDriveController 의 지대 목록이 '이름'이라 여기가 빠져 있었고,
	--     웅덩이는 Anchored(속도 0)라 위협 회피(minSpeed 8)에서도 걸러진다.
	--     두 경로 모두 누락 → 봇이 초당 10 지속딜 위를 그냥 걸어다녔다.
	-- ⚠️ 반경을 명시로 넘긴다. 기본 규약(Size.Y/2)을 쓰면 안 되는 이유 —
	--   아래 Size 는 (THICKNESS, 2, 2) 로 시작해 0.35초 트윈으로 RADIUS*2 까지 커지는데,
	--   지속딜·미끄러짐 판정은 처음부터 상수 RADIUS 다. Size 로 읽으면 그 0.35초 동안
	--   봇이 "아직 작다"고 판단해 이미 아픈 구역으로 걸어 들어간다.
	pool:SetAttribute("BotDangerZone", "circle")
	pool:SetAttribute("BotZoneRadius", RADIUS)

	-- Cylinder 는 원통축이 로컬 X 다. 지면 법선에 축을 맞춰 납작하게 눕힌다.
	-- ⚠️ 두께의 절반보다 살짝 더 띄운다. groundPos 는 지면 '표면' 이라
	--   중심을 거기 두면 절반이 땅에 파묻혀 안 보인다.
	local up = normal
	local right = up:Cross(Vector3.new(0, 0, 1))
	if right.Magnitude < 0.01 then right = up:Cross(Vector3.new(1, 0, 0)) end
	pool.CFrame = CFrame.fromMatrix(groundPos + normal * (THICKNESS * 0.5 + 0.1), up, right.Unit)

	-- 작게 시작해 반경까지 퍼지는 연출
	pool.Size = Vector3.new(THICKNESS, 2, 2)

	pool.Parent = workspace
	activeSpills[pool] = true

	TweenService:Create(pool, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(THICKNESS, RADIUS * 2, RADIUS * 2),
	}):Play()

	-- 소멸: 마지막 FADE_TIME 동안 옅어진다 → 러너가 "곧 사라진다"를 읽을 수 있다
	task.delay(DURATION - FADE_TIME, function()
		if not pool.Parent then return end
		TweenService:Create(pool, TweenInfo.new(FADE_TIME), { Transparency = 1 }):Play()
	end)
	task.delay(DURATION, function()
		activeSpills[pool] = nil
		if pool.Parent then pool:Destroy() end
	end)

	print(string.format("🛢️ [BarrelSpill] %s 웅덩이 생성 (반경 %d, %d초)",
		liquid.name, RADIUS, DURATION))
	return pool
end

-- ── 배럴 파열 진입점 ─────────────────────────────────────────
-- ItemDamageSystem 이 배럴 접촉을 감지하면 호출한다.
-- ⚠️ 중복 방지: 한 배럴은 한 번만 터진다. 여러 파트가 동시에 닿을 수 있다.
local burst = {}   -- [Model] = true
_G.BarrelBurst = function(barrelModel, itemName, position, character)
	if not barrelModel or burst[barrelModel] then return end
	burst[barrelModel] = true

	spawnSpill(position, itemName, barrelModel, character)

	-- 배럴 소멸. 파괴 연출은 웅덩이가 퍼지는 것으로 대신한다.
	task.defer(function()
		if barrelModel.Parent then barrelModel:Destroy() end
		burst[barrelModel] = nil
	end)
end

-- ── 웅덩이 안 판정 (공용) ────────────────────────────────────
-- ⚠️ 미끄러짐과 지속 피해가 같은 판정을 써야 한다. 복사해 두면 한쪽만 고쳤을 때
--   "미끄러지는데 안 아픈" 경계가 생긴다 — 이 모듈이 상수를 공유 모듈로 뺀 이유와 같다.
-- ⚠️ 높이도 본다 — 웅덩이 위 언덕·다리에 있는 러너까지 잡으면 안 된다.
--   HumanoidRootPart 는 발밑보다 약 3 stud 위다. 지면에 붙은 웅덩이 기준으로
--   여유 6(HEIGHT_SLACK) 이면 "밟고 있다" 를 커버하고 위층에 선 러너는 걸러진다.
local function insideSpill(hrp)
	for pool in pairs(activeSpills) do
		if pool.Parent then
			local d = Vector3.new(hrp.Position.X - pool.Position.X, 0,
				hrp.Position.Z - pool.Position.Z).Magnitude
			if d <= RADIUS and math.abs(hrp.Position.Y - pool.Position.Y) < HEIGHT_SLACK then
				return true
			end
		end
	end
	return false
end

-- ── 지속 피해 1틱 ────────────────────────────────────────────
-- ⚠️ processHit 을 타지 않는다. 내구도를 소모하지 않고 "1발사 1히트" 도 안 건드린다.
--   HP 0 은 ItemDamageSystem.attachRunnerDownOnZero 가 다운으로 바꾼다(즉사 아님).
-- ⚠️ 무적(Q대시 i-frame) 중이면 건너뛴다. 대시로 통과하는 판단이 무의미해진다.
-- ⚠️ 다운 상태는 제외. 다운은 이미 10초 사형 선고라 추가 피해가 의미 없고,
--   부활 후 HP 규칙(DownSystem 510행 주석)과 충돌한다.
--
-- ⏱️ [2026-09-01] 전역 누산기 → 캐릭터별 타이머.
--   [증상] "데미지가 늦게 들어온다"(유저 실측).
--   [원인] 0.5초 격자에 맞춰 전원을 한꺼번에 처리했다. 웅덩이에 들어간 시점과
--     격자가 어긋나면 첫 피해까지 최대 한 주기를 기다렸고, 그 사이 이미
--     지대를 통과해버리는 경우도 있었다. "밟았는데 아무 일도 없다" 로 읽힌다.
--   [해결] 캐릭터마다 다음 틱 시각을 들고 간다. 처음 들어오면 예약이 없으므로
--     그 프레임에 바로 1틱이 들어간다 — 진입과 피해가 같은 순간에 붙는다.
--   ⚠️ 지대를 벗어나면 예약을 지운다. 재진입 때 또 즉시 1틱이라, 들락날락으로
--     피해를 흘리는 우회가 오히려 손해가 된다.
--   ⚠️ 약한 키 테이블이다. 캐릭터가 사라지면 예약도 함께 회수된다.
local nextTickAt = setmetatable({}, { __mode = "k" })

local function applyTickDamage(character, now)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum and hum.Health > 0) then nextTickAt[character] = nil return end
	if character:GetAttribute("Downed") then nextTickAt[character] = nil return end
	if not insideSpill(hrp) then nextTickAt[character] = nil return end
	-- ⚠️ 무적은 '면제' 지 '초기화' 가 아니다. 예약을 지우지 않으므로 무적이 풀리는
	--   즉시 밀린 틱이 들어간다 — 대시로 지대를 지나가는 건 되지만 눌러앉지는 못한다.
	if _G.isInvincible and _G.isInvincible(character) then return end
	local due = nextTickAt[character]
	if due and now < due then return end
	nextTickAt[character] = now + TICK_INTERVAL
	hum:TakeDamage(TICK_DAMAGE)
end

-- ── 미끄러짐 판정 루프 (봇 전용) ─────────────────────────────
-- ⚠️ Touched 가 아니라 거리 판정이다. 웅덩이가 얇아서(0.4) Touched 가
--   프레임 사이에 새고, "밟고 있는 동안" 이라는 지속 상태를 표현할 수 없다.
-- ⚠️ 플레이어는 '미끄러짐'만 제외 — 클라이언트(BarrelSlipClient)가 담당한다.
--   '지속 피해'는 서버 권위라 유저도 여기서 함께 처리한다(아래 지속 피해 블록).
RunService.Heartbeat:Connect(function()
	if next(activeSpills) == nil then
		-- 지대가 없으면 남아 있는 미끄러짐만 정리
		for char in pairs(slipVel) do clearSlip(char) end
		return
	end

	local function check(character)
		local hrp = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum and hum.Health > 0) then
			clearSlip(character)
			return
		end
		-- ⚠️ [버그 수정 2026-08-26] 다운 상태면 건드리지 않는다.
		--   DownSystem 이 PlatformStand 와 AssemblyLinearVelocity 로 다운 연출을
		--   만드는데, 여기서 매 프레임 속도를 덮어쓰면 그 연출이 방해받는다.
		--   (RunnerBotDriveController 가 매 Heartbeat CFrame 을 써서
		--    PlatformStand 를 무력화했던 것과 같은 유형의 실수다)
		if character:GetAttribute("Downed") or hum.PlatformStand then
			clearSlip(character)
			return
		end
		local inside = insideSpill(hrp)
		if inside then applySlip(character, hrp) else clearSlip(character) end
	end

	-- ⚠️ AI 러너만. 서버가 물리 소유권을 가지므로 속도 조작이 그대로 먹는다.
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("AIRunner") then check(m) end
	end

	-- 🩸 [2026-09-01] 지속 피해 — 미끄러짐과 달리 유저·AI 둘 다 서버가 처리한다.
	--   [왜 여기는 유저도 포함인가] 미끄러짐은 물리라 클라 소유권 문제로 나눴지만,
	--     피해는 서버 권위여야 한다. 클라에 맡기면 조작 대상이 된다.
	--   ⚠️ 매 프레임 호출하되 간격 판단은 applyTickDamage 안의 캐릭터별 타이머가 한다.
	--     전역 누산기로 묶으면 진입 시점과 무관하게 격자에 맞춰 처리돼 첫 피해가 늦다.
	local now = os.clock()
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("AIRunner") then applyTickDamage(m, now) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		-- 태거는 대상이 아니다(미끄러짐 제외와 같은 원칙). Eliminated 는 로비에 있다.
		if plr:GetAttribute("Role") == "Runner" and not plr:GetAttribute("Eliminated")
		   and plr.Character then
			applyTickDamage(plr.Character, now)
		end
	end
end)

-- ── 라운드 종료 시 정리 ──────────────────────────────────────
--
-- ⚠️ [수정 2026-08-26] 2단계 진입 시 정리 → 라운드 종료 시 정리.
--   [기존] "2단계 결투장에 미끄러운 바닥이 남으면 푸시툴 밀어내기가 예측
--     불가능해진다" 는 이유로 stage2 진입에 지웠다.
--   [왜 틀렸나] 근거가 없었다. 태거는 미끄러짐·피해 양쪽 모두 대상이 아니고,
--     BASE-BLOCK(97행)이 베이스 안에 웅덩이 생성 자체를 막는다 — 2단계 결투장에는
--     애초에 웅덩이가 생기지 않는다. 게다가 수명이 8초라
--     2단계까지 넘어가도 곧 스스로 사라진다.
--     오히려 "1단계 막판에 뿌린 것만 손해" 라는 형평성 문제가 생긴다.
--   [지금] 라운드가 끝날 때만 치운다. 인터미션·로비까지 따라가는 것만 막으면 된다.
--
-- ⚠️ "상태를 켜는 코드와 끄는 코드는 같은 편집에" — 만들 때 지우는 것도 같이 둔다.
--   다만 지우는 시점은 '라운드 경계' 여야 하고 '단계 경계' 가 아니다.
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	local phase = ReplicatedStorage:GetAttribute("RoundPhase")
	-- stage1·stage2 동안은 유지. intermission(라운드 종료) 에만 정리한다.
	if phase == "stage1" or phase == "stage2" then return end
	local n = 0
	for pool in pairs(activeSpills) do
		if pool.Parent then pool:Destroy() end
		activeSpills[pool] = nil
		n = n + 1
	end
	for char in pairs(slipVel) do clearSlip(char) end
	if n > 0 then
		print(string.format("🛢️ [BarrelSpill] 라운드 종료(%s) — 웅덩이 %d개 정리",
			tostring(phase), n))
	end
end)

print("✅ BarrelSpillSystem 준비 (배럴 파열 → 액체 지대)")
