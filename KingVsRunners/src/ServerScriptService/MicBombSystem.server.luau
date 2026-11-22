-- MicBombSystem
-- Mic Bomb 효과의 핵심 로직.
--   1. victim 자리 + 약간 위에 Mini Concert Stage 복제본 spawn
--   2. 무대와 victim 모두 playerbase 방향(앞쪽)을 바라보게 회전
--   3. 강제 댄스 + 이동/점프 freeze + Tool 비활성
--   4. 태거 아이템은 무대를 통과 (ConcertStage 콜리전 그룹)
--   5. 8초 후 무대 + 효과 모두 정리
-- _G.simulateMicBomb(character) 로 외부에서 호출 가능

local Players        = game:GetService("Players")
local ServerStorage  = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService     = game:GetService("RunService")

-- ─── Tunables ─────────────────────────────────────
local DANCE_DURATION  = 8       -- 강제 댄스 지속 시간 (초)
local SOUND_START     = 8       -- 사운드 재생 시작 지점 (초)
local LIFT_HEIGHT     = 5       -- 무대를 발 높이보다 얼마나 위로 띄울지 (stud)
-- 춤 애니메이션. R15/R6 는 리그가 달라 애니가 호환되지 않으므로 둘 다 둔다.
--   ⚠️ 예전 ID(122427143618198)는 CrazyCorrs 소유라 재생이 조용히 실패했다.
--      Roblox 는 게임 소유자/그룹이 소유한 애니만 재생하며, 남의 애셋은
--      KeyframeSequenceProvider 로 데이터 조회도 막는다(실측: 키프레임 0개).
--      애니가 안 나오면 제일 먼저 소유자를 확인할 것.
local ANIM_ID_R15     = "rbxassetid://134997183561832"  -- Rat Dance (131키프레임, 4.38s)
local ANIM_ID_R6      = "rbxassetid://72614198297450"   -- RickRoll  (301키프레임, 10.0s)
local STAGE_CG        = "ConcertStage"  -- 무대 콜리전 그룹

-- ─── 미리 만들어두는 Animation 인스턴스 ───────────
local danceAnimR15 = Instance.new("Animation")
danceAnimR15.AnimationId = ANIM_ID_R15
local danceAnimR6 = Instance.new("Animation")
danceAnimR6.AnimationId = ANIM_ID_R6

-- 피격자 리그에 맞는 애니를 고른다. RigType 이 없으면 R15 로 본다(현 캐릭터 기본값).
local function pickDanceAnim(hum)
    if hum and hum.RigType == Enum.HumanoidRigType.R6 then
        return danceAnimR6
    end
    return danceAnimR15
end

-- ─── State ────────────────────────────────────────
local activeShows = {}

-- ─── 루트 파트 (HRP 없는 R6 더미/봇은 Torso 폴백) ──
local function getRoot(char)
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return char:FindFirstChild("HumanoidRootPart")
		or (hum and hum.RootPart)
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("UpperTorso")
		or char.PrimaryPart
end

-- ─── 원본 무대 템플릿 ─────────────────────────────
local function getStageTemplate()
	return ServerStorage:FindFirstChild("Mini Concert Stage")
end

-- ─── 콜리전 그룹 초기화 (부팅 시 1회) ────────────
local function setupCollisionGroup()
	if not PhysicsService:IsCollisionGroupRegistered(STAGE_CG) then
		PhysicsService:RegisterCollisionGroup(STAGE_CG)
	end
	-- 태거 아이템은 무대를 통과 (태거 아이템이 무대 너머의 플레이어를 죽일 수 있도록)
	if PhysicsService:IsCollisionGroupRegistered("TaggerItems") then
		PhysicsService:CollisionGroupSetCollidable(STAGE_CG, "TaggerItems", false)
	end
	-- 캐릭터도 무대를 통과. 무대는 피격자 1명을 위한 연출물이라,
	-- 다른 플레이어가 여기 막히면 길이 끊기고 억울한 사망이 난다.
	--   ⚠️ 피격자 본인은 무대 바닥을 딛고 서는 게 아니라 hrp.CFrame 으로
	--      좌표를 강제 배치받는다(294~296행). 그래서 충돌을 다 꺼도 그대로 서 있다.
	for _, cg in ipairs({ "RunnerCharacter", "TaggerCharacter", "AIRunnerChar", "Runners" }) do
		if PhysicsService:IsCollisionGroupRegistered(cg) then
			PhysicsService:CollisionGroupSetCollidable(STAGE_CG, cg, false)
		end
	end
	-- 원본 무대의 모든 파트를 ConcertStage 그룹으로
	local template = getStageTemplate()
	if template then
		local cnt = 0
		for _, p in ipairs(template:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = STAGE_CG
				cnt = cnt + 1
			end
		end
		print(string.format("✅ MicBomb: %s 그룹 적용 %d개 파트 (TaggerItems 통과)", STAGE_CG, cnt))
	end
end
setupCollisionGroup()

-- ⚠️ AIRunnerChar 는 RoundSystem 이 라운드 시작마다 등록한다(RoundSystem:662).
--    이 스크립트의 부팅 시점에는 아직 없어서 위 루프가 건너뛴다(실측: 등록됨=false).
--    게다가 RoundSystem 은 등록 시 다른 그룹과의 관계를 자체 규칙으로 채우므로
--    ConcertStage 와의 통과 설정이 덮일 수 있다.
--    → 무대를 펼치기 직전에 한 번 더 건다. 이미 false 면 무해한 재설정.
local function ensureStagePassable()
	for _, cg in ipairs({ "RunnerCharacter", "TaggerCharacter", "AIRunnerChar", "Runners" }) do
		if PhysicsService:IsCollisionGroupRegistered(cg) then
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(STAGE_CG, cg, false)
			end)
		end
	end
end

-- ─── 가장 가까운 playerbase 또는 SpawnLocation 찾기 ──
local function findNearestBase(pos)
	local closest, minDist = nil, math.huge
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name:lower():find("playerbase") then
			local d = (inst.Position - pos).Magnitude
			if d < minDist then minDist = d; closest = inst end
		end
	end
	if closest then return closest end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			local d = (inst.Position - pos).Magnitude
			if d < minDist then minDist = d; closest = inst end
		end
	end
	return closest
end

-- ─── 모든 Tool 일시 비활성화 ──────────────────────
local function disableAllTools(player, victimChar)
	local frozen = {}
	if not victimChar then return frozen end

	-- ⚠️ 예전엔 여기서 `if not player then return end` 로 즉시 빠져나갔다.
	--    킹 봇은 pseudoPlayer(Lua 테이블)라 GetPlayerFromCharacter 가 nil 을 주는데,
	--    그 탓에 손에 든 Tool 검사조차 못 하고 "도구 0개 봉인"으로 통과했다
	--    (실측 2026-08-20: 콘서트 중 KING 이 PushTool 로 러너를 밀침).
	--    → 캐릭터 쪽은 player 유무와 무관하게 처리하고, 백팩만 player 가 있을 때 본다.

	-- 들고 있는 Tool (NPC·플레이어 공통)
	for _, t in ipairs(victimChar:GetChildren()) do
		if t:IsA("Tool") and t.Enabled then
			t.Enabled = false
			table.insert(frozen, t)
		end
	end
	-- Backpack 내 Tool (실제 Player 만 해당)
	local backpack = player and player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and t.Enabled then
				t.Enabled = false
				table.insert(frozen, t)
			end
		end
	end
	return frozen
end

local function restoreTools(frozen)
	for _, t in ipairs(frozen) do
		if t and t.Parent then t.Enabled = true end
	end
end

-- ─── 라이트쇼 (무대 조명에서 빛줄기 swing) ────────
-- 복제된 무대 안의 7개 PointLight 위치에서 SpotLight + Cylinder beam을 spawn.
-- 각 빔은 자기 조명 위치에서 시작해 victim 쪽으로 swing.
-- 색깔은 무대 조명 자체 색깔을 그대로 사용.
-- 반환: cleanup 함수
local BEAM_LENGTH       = 32      -- 빔 길이 (stud)
local BEAM_DIAMETER     = 1.3     -- 빔 두께 (stud)
local BEAM_TRANSPARENCY = 0.7     -- 빔 투명도

local function startLightShow(victimChar, stage)
	local hrp = getRoot(victimChar)
	if not hrp then return function() end end

	-- 무대 안 모든 PointLight 찾기 (조명 Part 위치 + 색깔)
	local sources = {}
	for _, inst in ipairs(stage:GetDescendants()) do
		if inst:IsA("PointLight") and inst.Parent and inst.Parent:IsA("BasePart") then
			table.insert(sources, {
				lightPart = inst.Parent,
				color     = inst.Color,
			})
		end
	end
	if #sources == 0 then
		warn("⚠️ MicBomb: 무대에 PointLight 없음, 라이트쇼 생략")
		return function() end
	end

	local lightParts = {}

	for i, src in ipairs(sources) do
		local spawnPos = src.lightPart.Position
		local color    = src.color

		-- SpotLight 부착할 invisible part (실제 빛, 표면 비춤)
		local part = Instance.new("Part")
		part.Name = "MicBombSpot_" .. i
		part.Size = Vector3.new(0.4, 0.4, 0.4)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.Massless = true
		part.CFrame = CFrame.new(spawnPos)
		part.Parent = workspace

		local spot = Instance.new("SpotLight")
		spot.Color      = color
		spot.Brightness = 7.5
		spot.Range      = 60
		spot.Angle      = 22
		spot.Face       = Enum.NormalId.Front
		spot.Shadows    = false
		spot.Parent     = part

		-- 시각화된 빛줄기 (Neon Cylinder)
		local beam = Instance.new("Part")
		beam.Name        = "MicBombBeam_" .. i
		beam.Shape       = Enum.PartType.Cylinder
		beam.Size        = Vector3.new(BEAM_LENGTH, BEAM_DIAMETER, BEAM_DIAMETER)
		beam.Material    = Enum.Material.Neon
		beam.Color       = color
		beam.Transparency = BEAM_TRANSPARENCY
		beam.Anchored    = true
		beam.CanCollide  = false
		beam.Massless    = true
		beam.CastShadow  = false
		beam.CollisionGroup = "ConcertStage"
		beam.Parent      = workspace

		-- 안전망: cleanup이 실패해도 빔/스팟이 반드시 사라지도록
		game:GetService("Debris"):AddItem(part, DANCE_DURATION + 2)
		game:GetService("Debris"):AddItem(beam, DANCE_DURATION + 2)

		table.insert(lightParts, {
			part    = part,
			beam    = beam,
			basePos = spawnPos,
			phase   = (i - 1) * (math.pi * 2 / #sources),  -- 조명 개수에 맞춰 phase 균등 분배
		})
	end

	-- Heartbeat swing
	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		if elapsed > DANCE_DURATION + 2 then
			connection:Disconnect()
			return
		end
		local vhrp = victimChar and getRoot(victimChar)
		if not vhrp then return end
		local victimTarget = vhrp.Position + Vector3.new(0, 1.5, 0)

		for _, lp in ipairs(lightParts) do
			if lp.part.Parent and lp.beam.Parent then
				local swingX = math.sin(elapsed * 2.5 + lp.phase) * 6
				local swingZ = math.cos(elapsed * 1.8 + lp.phase * 1.3) * 4
				local target = victimTarget + Vector3.new(swingX, 0, swingZ)
				local lookCF = CFrame.lookAt(lp.basePos, target)
				lp.part.CFrame = lookCF
				lp.beam.CFrame = lookCF * CFrame.new(0, 0, -BEAM_LENGTH / 2) * CFrame.Angles(0, math.pi / 2, 0)
			end
		end
	end)

	-- cleanup
	return function()
		if connection then connection:Disconnect() end
		for _, lp in ipairs(lightParts) do
			if lp.part and lp.part.Parent then lp.part:Destroy() end
			if lp.beam and lp.beam.Parent then lp.beam:Destroy() end
		end
	end
end

-- ─── 무대 spawn + 강제 댄스 시작 ──────────────────
local function spawnConcertOnVictim(victimChar)
	if not victimChar or not victimChar.Parent then return end
	-- 🛡️ [2026-09-02] CC 면역 중이면 발동하지 않는다(TaggerCcGuard).
	--   연속 CC 로 킹이 2단계 내내 묶이는 걸 막는다. 면역 시간은 직전 CC 지속 × 0.75.
	--   ⚠️ 여기서 막아야 한다. 속성만 봐서는 무대·댄스·Tool 봉인이 그대로 실행된다.
	if _G.IsCcImmune and _G.IsCcImmune(victimChar) then return end
	local hum = victimChar:FindFirstChildOfClass("Humanoid")
	local hrp = getRoot(victimChar)
	if not hum or hum.Health <= 0 or not hrp then return end

	local player = Players:GetPlayerFromCharacter(victimChar)
	local key = player and player.UserId or victimChar
	if activeShows[key] then return end
	activeShows[key] = true

	local victimName = player and player.Name or victimChar.Name

	-- 원본 무대 복제
	local template = getStageTemplate()
	if not template then
		warn("⚠️ MicBomb: Mini Concert Stage 템플릿 없음")
		activeShows[key] = nil
		return
	end
	local stage = template:Clone()
	ensureStagePassable()   -- AIRunnerChar 등 늦게 등록되는 그룹까지 통과 보장

	local protaspawn = stage:FindFirstChild("protaspawn", true)
	if not protaspawn then
		warn("⚠️ MicBomb: 복제된 무대에 protaspawn 없음")
		stage:Destroy()
		activeShows[key] = nil
		return
	end

	-- ─── 위치 계산 ────────────────────────────────
	local footY = hrp.Position.Y - (hrp.Size.Y * 0.5) - (hum.HipHeight or 0)
	local targetProtaTopY    = footY + LIFT_HEIGHT
	local targetProtaCenterY = targetProtaTopY - (protaspawn.Size.Y * 0.5)
	local targetProtaPos     = Vector3.new(hrp.Position.X, targetProtaCenterY, hrp.Position.Z)

	-- ─── 회전 방향 (playerbase 쪽) ───────────────
	local base = findNearestBase(hrp.Position)
	local lookTarget
	if base then
		lookTarget = Vector3.new(base.Position.X, targetProtaPos.Y, base.Position.Z)
	else
		lookTarget = targetProtaPos + Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		warn("⚠️ MicBomb: playerbase 못 찾음, victim LookVector fallback")
	end

	-- 무대 배치: protaspawn이 playerbase를 바라보되, 무대 모델의 진짜 정면이
	-- protaspawn LookVector와 90도 차이가 나서 yaw 보정
	local protaCFrame = CFrame.lookAt(targetProtaPos, lookTarget) * CFrame.Angles(0, -math.pi/2, 0)
	local origProtaCF = protaspawn.CFrame
	local origPivot   = stage:GetPivot()
	local relative    = origPivot:ToObjectSpace(origProtaCF)
	local newPivot    = protaCFrame * relative:Inverse()
	stage:PivotTo(newPivot)
	stage.Parent = workspace
	-- 안전망: cleanup이 어떤 이유로 실패해도 무대가 반드시 사라지도록
	game:GetService("Debris"):AddItem(stage, DANCE_DURATION + 2)

	-- ─── victim 위치 + 회전 (playerbase 향함) ────
	local newVictimY  = targetProtaTopY + (hum.HipHeight or 0) + (hrp.Size.Y * 0.5)
	local victimNewPos = Vector3.new(hrp.Position.X, newVictimY, hrp.Position.Z)
	local victimCF = CFrame.lookAt(victimNewPos, Vector3.new(lookTarget.X, newVictimY, lookTarget.Z))
	-- ⚠️ 킹 봇은 HumanoidRootPart 가 Anchored=true 다(King npc2 템플릿).
	--    앵커된 HRP 에 CFrame 을 대입하면 그 파트만 옮겨지고 나머지 몸통은
	--    물리 시뮬레이션을 안 타서 제자리에 남는다 → 무대에 안 올라간 것처럼 보였다.
	--    PivotTo 는 모델 전체를 함께 옮기므로 앵커 여부와 무관하게 동작한다.
	-- ⚠️ 단, King npc2 는 PrimaryPart 가 nil 이라 피벗이 HRP 와 0.43 stud 어긋난다.
	--    HRP 기준으로 계산한 목표를 그대로 PivotTo 하면 그만큼 파묻히거나 뜬다.
	--    → 현재 피벗과 HRP 의 상대 오프셋을 구해 보정한다.
	local pivotOffset = victimChar:GetPivot():ToObjectSpace(hrp.CFrame)
	victimChar:PivotTo(victimCF * pivotOffset:Inverse())
	-- 실측 2026-08-21: PivotTo 는 목표 Y 에 오차 0.00 으로 정확히 올렸다.
	--   낙하 원인은 이 계산이 아니라 무대 비충돌이었고, 아래 STAGE-ANCHOR 로 해결됨.

	-- ─── 사운드 ───────────────────────────────────
	local newProtaspawn = stage:FindFirstChild("protaspawn", true)
	local sound = newProtaspawn and newProtaspawn:FindFirstChild("ConcertSound")

	-- ─── 애니메이션 ───────────────────────────────
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local ok, track = pcall(function() return animator:LoadAnimation(pickDanceAnim(hum)) end)
	if not ok or not track then
		warn("⚠️ MicBomb: LoadAnimation 실패")
		stage:Destroy()
		activeShows[key] = nil
		return
	end

	-- ─── 이동/점프 freeze ─────────────────────────
	local origWS = hum.WalkSpeed
	local origJP = hum.JumpPower
	local origJH = hum.JumpHeight
	-- [STAGE-ANCHOR] HRP 를 앵커해 무대 위에 고정한다.
	--   ⚠️ 무대는 모든 캐릭터 콜리전 그룹과 비충돌이라(다른 플레이어가 막히지 않게)
	--      피격자 본인도 무대를 뚫고 떨어진다. WalkSpeed=0 은 중력을 막지 못한다.
	--      실측 2026-08-20: PivotTo 로 목표 Y=137.35 에 정확히 올렸으나
	--      0.3초 만에 131.05(무대 상판 135.15 아래)로 낙하.
	--   앵커하면 중력·충돌과 무관하게 고정되고, 사지는 Motor6D 로 매달려
	--   춤 애니는 그대로 재생된다(킹 템플릿이 원래 이 형태다).
	local origAnchored = hrp.Anchored
	hrp.Anchored = true
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0

	-- ─── Tool 봉인 ───────────────────────────────
	local frozenTools = disableAllTools(player, victimChar)

	-- [MICBOMB-SEAL] 킹 봇 전용 행동 정지.
	--   봇의 AI 루프는 hum.WalkSpeed 를 무시하고 MoveTo 로 직접 움직이며,
	--   PushTool 도 BindableEvent 로 발동해 Tool.Enabled 를 우회한다.
	--   TaggerBotSystem 의 루프가 이 속성을 보고 통째로 멈춘다.
	--   ⚠️ Frozen(IceBow용)을 재사용하면 그쪽 8초 안전망이 콘서트 8초와 겹쳐
	--      봉인한 Tool 을 자동 복구해버리므로 전용 속성을 쓴다.
	victimChar:SetAttribute("MicBombed", true)

	-- 🎤 [밸런스 2026-08-29] 공연 중 피해 면역 — 콜리전 그룹으로 격리한다.
	--   [왜] 마이크밤은 밈/개그 아이템인데(아군에게도 쓸 수 있다) 8초 완전 무력화가
	--     2단계(20~40초)의 1/4 을 지워버려 너무 강했다.
	--   [왜 지속을 안 줄이나] 댄스 애니와 노래가 8초에 맞춰져 있어 자르면 연출이 깨진다.
	--     → 지속은 두고 위력만 뺀다.
	--   [왜 TakeDamage 가드가 아니라 콜리전인가] 피해 호출 지점이 20곳이 넘는다
	--     (러너 무기 8종 15곳, 압박선, 곡사포, 마법책, 폭탄, 프드, 봇...).
	--     하나씩 가드를 넣으면 반드시 빠뜨리고, 새 무기를 추가할 때 또 빠진다.
	--     물리적으로 안 닿게 하면 근접 판정(Touched/GetPartsInPart)이 원천 차단된다.
	--   [효과] 태거에게 걸면 "8초간 서로 아무것도 못 함", 아군에게 걸면 "8초 무적".
	--     둘 다 밈 아이템다운 결과다.
	--   ⚠️ 지형(Default/Walls/Mountains)은 충돌을 유지한다. 안 그러면 무대에서 떨어진다.
	--     (실은 HRP 가 Anchored 라 안 떨어지지만, 앵커 해제 순간을 대비한 안전장치)
	--   ⚠️ 원래 그룹을 파트별로 기억했다가 복원해야 한다. 안 하면 공연이 끝난 뒤에도
	--     영영 무적으로 남는다 — 켜는 코드와 끄는 코드는 한 짝이다.
	local savedCG = {}
	for _, p in ipairs(victimChar:GetDescendants()) do
		if p:IsA("BasePart") then
			savedCG[p] = p.CollisionGroup
			pcall(function() p.CollisionGroup = "MicBombStage" end)
		end
	end

	-- ─── 라이트쇼 시작 ───────────────────────────
	local lightCleanup = startLightShow(victimChar, stage)

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	track:Play(0.2)

	if sound then
		sound.TimePosition = SOUND_START
		sound:Play()
	end

	print(string.format("🎤 %s 마이크 폭탄 피격 → 콘서트장 펼침 (%.1f초, 도구 %d개 봉인)",
		victimName, DANCE_DURATION, #frozenTools))

	-- ─── 종료 ────────────────────────────────────
	task.delay(DANCE_DURATION, function()
		-- 무대부터 확실히 제거 (이후 단계가 실패해도 콘서트는 사라짐)
		if stage and stage.Parent then stage:Destroy() end
		pcall(function() track:Stop(0.2) end)
		if sound then pcall(function() sound:Stop() end) end
		if hum and hum.Parent then
			pcall(function()
				hum.WalkSpeed = origWS
				hum.JumpPower = origJP
				hum.JumpHeight = origJH
			end)
		end
		-- [STAGE-ANCHOR] 앵커 해제. 안 풀면 피격자가 공중에 영구 고정된다.
		pcall(function()
			if hrp and hrp.Parent then hrp.Anchored = origAnchored end
		end)
		pcall(function() restoreTools(frozenTools) end)
		-- [MICBOMB-SEAL] 켠 것은 반드시 끈다. 안 지우면 킹 봇이 라운드 내내 멈춘다.
		pcall(function()
			if victimChar and victimChar.Parent then
				victimChar:SetAttribute("MicBombed", nil)
				-- 🎤 콜리전 그룹 복원. 위 savedCG 저장과 한 짝이다.
				--   ⚠️ 안 되돌리면 공연이 끝난 뒤에도 영영 무적으로 남는다.
				--   ⚠️ 파트별로 원래 그룹이 다르다(유저=RunnerCharacter, 봇=AIRunnerChar 등).
				--     일괄 "Default" 로 밀면 안 되고 저장해둔 값을 그대로 써야 한다.
				for p, cg in pairs(savedCG) do
					if p.Parent then pcall(function() p.CollisionGroup = cg end) end
				end
			end
		end)
		pcall(function() if lightCleanup then lightCleanup() end end)
		activeShows[key] = nil
		print(string.format("🎤 %s 콘서트 종료 (무대 철거 + 도구 복원)", victimName))
	end)
end

-- ═══ Mic Bomb 투척 발사 (영구 스크립트에서 처리 → Tool이 즉시 파괴돼도 비행 유지) ═══
local Debris = game:GetService("Debris")

local THROW_SPEED      = 90     -- 비행 속도 (stud/s)
local THROW_MAX_DIST   = 250    -- 최대 사거리
local THROW_DETONATE_R = 9      -- 착탄 폭발 반경 (이 안의 대상에게 콘서트)
local THROW_MIN_FLY    = 6      -- 너무 가까이 조준해도 최소 비행 거리
local THROW_AIM_RAISE  = 2.5    -- 조준점 몸통 높이 보정
local THROW_SCALE      = 4      -- 투척물 크기 배율 (대폭 확대)
local MIC_HOLD_TIME    = DANCE_DURATION  -- 손에 마이크 유지 시간
local HELD_SCALE       = 2      -- 손에 쥘 때 크기 (원본 대비)
-- 손에 쥘 때 Handle 기준 오프셋. 머리(Ball)=로컬 -Z → X축 회전으로 "위+앞" 향하게.
local HOLD_OFFSET_R6   = CFrame.new(0, -0.95, -0.5) * CFrame.Angles(math.rad(45), 0, 0)  -- Right Arm
local HOLD_OFFSET_R15  = CFrame.new(0, 0.15, -0.35) * CFrame.Angles(math.rad(45), 0, 0)  -- RightHand
local MIC_TEMPLATE     = ServerStorage:FindFirstChild("Mic2Proj")  -- Mic2 발사체 모델
if MIC_TEMPLATE then print("✅ [MicBomb] Mic2Proj 발사체 템플릿 로드") else warn("⚠️ [MicBomb] Mic2Proj 템플릿 없음") end

local function attachMicToHand(micModel, char)
	local r15hand = char:FindFirstChild("RightHand")
	local hand = r15hand or char:FindFirstChild("Right Arm")
	local prim = micModel.PrimaryPart
	if not hand or not prim then micModel:Destroy() return end
	pcall(function() micModel:ScaleTo(HELD_SCALE) end)  -- 손에 쥘 땐 2배
	for _, p in ipairs(micModel:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local offset = r15hand and HOLD_OFFSET_R15 or HOLD_OFFSET_R6
	micModel:PivotTo(hand.CFrame * offset)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = prim
	weld.Parent = prim
	Debris:AddItem(micModel, MIC_HOLD_TIME)
end

local function collectThrowTargets(throwerChar)
	local list, seen = {}, {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		if c and c ~= throwerChar then
			local hum = c:FindFirstChildOfClass("Humanoid")
			local r = getRoot(c)
			if hum and r and hum.Health > 0 then list[#list + 1] = { root = r, hum = hum, model = c }; seen[c] = true end
		end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m ~= throwerChar and not seen[m] then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local r = getRoot(m)
			if hum and r and hum.Health > 0 then list[#list + 1] = { root = r, hum = hum, model = m } end
		end
	end
	return list
end

local function doLaunch(thrower, throwerChar, targetPos)
	if not throwerChar then return end
	local hrp = getRoot(throwerChar)
	if not hrp then return end
	if not MIC_TEMPLATE then warn("⚠️ MicBomb 투척: Mic2Proj 템플릿 없음") return end

	-- 착탄점 반경에서 가장 가까운 대상
	-- 착탄 반경 안에서 대상 찾기
	--   우선순위: 태거 > 그 외. 같은 등급 안에서는 착탄점 최근접.
	--   ⚠️ 태거 판별은 두 경로가 필요하다.
	--      킹 봇   : 캐릭터 모델에 Role="Tagger" (TaggerBotSystem:174)
	--      플레이어: Player 객체에 Role="Tagger"
	--      한쪽만 보면 봇이나 사람 중 하나가 누락된다.
	local function isTaggerModel(m)
		if m:GetAttribute("Role") == "Tagger" then return true end
		local pl = Players:GetPlayerFromCharacter(m)
		return pl ~= nil and pl:GetAttribute("Role") == "Tagger"
	end

	local function findVictimNear(pos, micModel)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { throwerChar, micModel }
		local parts = workspace:GetPartBoundsInRadius(pos, THROW_DETONATE_R, params)
		local best, bestDist, seen = nil, math.huge, {}
		local bestTagger, bestTaggerDist = nil, math.huge
		for _, p in ipairs(parts) do
			local m = p:FindFirstAncestorOfClass("Model")
			if m and not seen[m] then
				seen[m] = true
				local hum = m:FindFirstChildOfClass("Humanoid")
				local r = getRoot(m)
				if hum and r and hum.Health > 0 and m ~= throwerChar then
					local d = (r.Position - pos).Magnitude
					if isTaggerModel(m) then
						if d < bestTaggerDist then bestTagger, bestTaggerDist = m, d end
					end
					if d < bestDist then best, bestDist = m, d end
				end
			end
		end
		-- 태거가 반경 안에 있으면 거리와 무관하게 태거를 우선한다.
		if bestTagger then return bestTagger end
		return best
	end

	local proj = MIC_TEMPLATE:Clone()
	proj.Name = "ThrownMic"
	for _, p in ipairs(proj:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end
	pcall(function() proj:ScaleTo(THROW_SCALE) end)
	proj.Parent = workspace
	proj:PivotTo(hrp.CFrame * CFrame.new(0, 1, -3))

	local origin = proj:GetPivot().Position
	local aim = targetPos + Vector3.new(0, THROW_AIM_RAISE, 0)
	local toAim = aim - origin
	local dist = toAim.Magnitude
	if dist > THROW_MAX_DIST then
		aim = origin + toAim.Unit * THROW_MAX_DIST
	elseif dist < THROW_MIN_FLY then
		local d = (dist > 0.01) and toAim.Unit or hrp.CFrame.LookVector
		aim = origin + d * THROW_MIN_FLY
	end
	toAim = aim - origin
	local total = toAim.Magnitude
	local dir = total > 0.01 and toAim.Unit or hrp.CFrame.LookVector

	local T = math.max(total / THROW_SPEED, 0.15)  -- 비행 시간(초)
	local arcH = math.clamp(total * 0.3, 12, 80)    -- 포물선 최고 높이
	local elapsed, spin, done = 0, 0, false
	local conn
	local function finish()
		if done then return end
		done = true
		if conn then conn:Disconnect() end
	end
	local function detonate(atPos)
		finish()
		local victim = findVictimNear(atPos, proj)
		if victim then
			attachMicToHand(proj, victim)
			spawnConcertOnVictim(victim)
		else
			if proj and proj.Parent then proj:Destroy() end
		end
	end

	-- 비행: 포물선(수평 lerp + 높이 4·H·t·(1-t)), 착탄점 도달 시 폭발 (비행 중 충돌 무시)
	conn = RunService.Heartbeat:Connect(function(dt)
		if done then return end
		elapsed = elapsed + dt
		spin = spin + dt * 10
		local t = elapsed / T
		if t >= 1 then
			proj:PivotTo(CFrame.new(aim) * CFrame.Angles(0, 0, spin))
			detonate(aim)
			return
		end
		local pos = origin:Lerp(aim, t) + Vector3.new(0, arcH * 4 * t * (1 - t), 0)
		local tangent = toAim + Vector3.new(0, arcH * 4 * (1 - 2 * t), 0)
		local look = tangent.Magnitude > 0.01 and tangent.Unit or dir
		proj:PivotTo(CFrame.lookAt(pos, pos + look) * CFrame.Angles(0, 0, spin))
	end)
	task.delay(T + 1, function()
		if not done then finish() if proj.Parent then proj:Destroy() end end
	end)

	if thrower then print(string.format("🎤 %s 마이크 폭탄 투척 (착탄 %.0f stud)", thrower.Name, total)) end
end

-- Tool에서 _G.launchMicBomb 호출 → BindableEvent로 넘겨 MicBombSystem 스레드에서 비행
-- (이렇게 해야 비행 연결/타이머의 소유권이 영구 스크립트에 있어 Tool 파괴와 무관해짐)
local launchBindable = Instance.new("BindableEvent")
launchBindable.Event:Connect(function(thrower, throwerChar, targetPos)
	doLaunch(thrower, throwerChar, targetPos)
end)
_G.launchMicBomb = function(thrower, throwerChar, targetPos)
	launchBindable:Fire(thrower, throwerChar, targetPos)
end

-- ─── 글로벌 노출 ─────────────────────────────────
_G.simulateMicBomb = spawnConcertOnVictim

print("✅ MicBombSystem ready (_G.simulateMicBomb, LIFT=" .. LIFT_HEIGHT .. ", CG=" .. STAGE_CG .. ")")
