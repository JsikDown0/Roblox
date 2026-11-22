-- Dragon Fire Sword (서버) — 원작 Stickmasterluke SFOTH 베이스를 샌드웨이퍼 게임 구조로 개조.
-- ⚠️ [2026-09-12] 화면 표기는 "Fire Blade" 다(WeaponData.name). 내부 id·폴더명·주석은
--   "DragonFireSword" 그대로 — 저장 데이터가 이 문자열을 쓰므로 바꾸면 장착이 깨진다.
--   다른 무기 주석에도 "Dragon Fire" 로 적힌 상호 참조가 있다(DiamondBlade·SakuraBlade).
-- 단일 스윙 공격 + 진영 체크(태거만) + canDamage 윈도우 + HIT_COOLDOWN + creator 태그.
-- 화상 도트(컨셉)는 다음 단계에서 추가 예정.

local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local Tool   = script.Parent
local Handle = Tool:WaitForChild("Handle")
local Fire   = Handle:WaitForChild("Fire")
local FXRemote = Tool:WaitForChild("FXRemote")  -- 데미지/스택 표시용 (클라 UI로 신호)

-- ── 데미지 값 ────────────────────────────────────────────────
-- 직접 타격은 아주 낮게(4) — 화염 표식을 쌓아 10단계에서 터뜨리는 게 주력.
local SLASH_DAMAGE = 11
-- ⚠️ [밸런스 2026-08-29] 4 → 11, 폭발 계수 0.40 → 0.06 (세트 조정).
--   [문제] 바닥 8 / 천장 58 로 격차가 7.3배였다. 조건(6연타)을 못 채우면
--     평타 4 뿐이라 무기가 무의미해지고, 채우면 최상위가 되는 도박이었다.
--     조건 충족 여부가 킹의 넉백에 달려 있어 러너가 통제할 수 없다는 게 더 문제였다.
--   [해결] 바닥을 올리고 천장을 낮춰 격차를 1.3배로 좁힌다.
--     평타 11/0.5 = 22 DPS (조건 실패해도 Rare 목표 23 에 근접)
--     6스택 사이클 (66 + 폭발) / 3.0초 → 약 29 DPS
--   ⚠️ '참았다 터뜨린다'는 정체성은 유지된다. 폭발이 여전히 사이클의 절반 이상이다.

-- ── 화상 도트(A 방식: 갱신형, 약한 보너스) ───────────────────
-- 타격 시 화상 부여 → 1초마다 BURN_TICK씩, BURN_DURATION 동안. 컨셉 연출 수준의 미세 도트.
-- 갱신형: 이미 화상 걸린 대상을 또 때리면 새로 쌓지 않고 남은 시간만 리셋.
local BURN_TICK     = 1      -- 초당 화상 데미지
local BURN_DURATION = 3      -- 화상 지속(초)
local BURN_INTERVAL = 1      -- 도트 적용 간격(초)
local burnUntil     = {}     -- [character] = 화상 만료 시각(os.clock 기준)
local burnActive    = {}     -- [character] = 화상 루프가 돌고 있는지

-- ── 화염 표식 스택 ───────────────────────────────────────────
-- 타격마다 스택 +1 (최대 10). 10스택 도달 시 폭발 데미지 + 스택 초기화.
-- 스택도 만료가 있어 일정 시간 안 때리면 풀림 → "공속으로 몰아쳐 빠르게 쌓는" 컨셉 유지.
local STACK_MAX        = 6
local STACK_EXPLODE_PCT = 0.06   -- 스택폭발: 태거 최대체력의 6%
-- ⚠️ [밸런스 2026-08-29] 0.40 → 0.06. 위 SLASH_DAMAGE 4→11 과 한 세트다.
--   [왜 이렇게 크게 낮추나] 0.40 은 태거 HP 375 부터 상한 150 에 걸려,
--     다인전(825)에서는 비율 설계가 사실상 죽고 고정 150 이 됐다.
--     0.06 이면 825 기준 50 으로, 전 구간에서 비율이 살아 있다.
--   ⚠️ 둘 중 하나만 바꾸면 안 된다. 평타를 안 올린 채 폭발만 낮추면 무기가 죽고,
--     폭발을 안 낮춘 채 평타만 올리면 최상위가 된다.
local STACK_EXPLODE_CAP = 150    -- 폭발 데미지 상한 (다인전 고HP 폭주 방지)
local STACK_DURATION   = 6     -- 마지막 타격 후 이 시간 안 때리면 스택 리셋(초)
local fireStacks       = {}    -- [character] = 현재 스택 수
local stackUntil       = {}    -- [character] = 스택 만료 시각
local stackWatcher     = {}    -- [character] = 만료 감시 루프 진행 중 여부

-- ── 스택 폭발 불꽃 X 연출 (fire vfx 재활용, 얇은 바 2개 ±45° 교차) ──
local FX_ServerStorage = game:GetService("ServerStorage")
local FX_Debris = game:GetService("Debris")
local FLAME_Y_OFFSET = -2.8   -- 태거 발쪽에서 불꽃 시작 (root=토르소 기준 아래로)
local FLAME_SFX = "rbxassetid://126383299163284"          -- 점화 사운드 rbxassetid (ID 넣으면 재생, 비우면 무음)
local function spawnFlameX(character, attacker)
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or character:FindFirstChild("Torso")
	if not root then return end
	local src = FX_ServerStorage:FindFirstChild("df_vfx")
	if not src then warn("[DragonFire] ServerStorage.df_vfx 없음"); return end
	local clone = src:Clone()
	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		end
	end
	clone.Parent = workspace
	-- 원본 df_vfx 회전(위로 뿜게 튜닝된 각도) 유지, 위치만 태거로 이동 (태거 회전 안 따라감)
	local origCF = src:IsA("Model") and src:GetPivot() or src.CFrame
	local placeCF = CFrame.new(root.Position + Vector3.new(0, FLAME_Y_OFFSET, 0)) * origCF.Rotation
	if clone:IsA("Model") then
		clone:PivotTo(placeCF)
	elseif clone:IsA("BasePart") then
		clone.CFrame = placeCF
	end
	-- 점화 사운드 (FLAME_SFX에 ID 넣으면 재생)
	if FLAME_SFX ~= "" then
		local sp = Instance.new("Part")
		sp.Transparency = 1; sp.Anchored = true; sp.CanCollide = false; sp.CanQuery = false
		sp.Size = Vector3.new(1, 1, 1); sp.CFrame = CFrame.new(placeCF.Position); sp.Parent = workspace
		local snd = Instance.new("Sound")
		snd.SoundId = FLAME_SFX; snd.Volume = 2.0
		snd.RollOffMaxDistance = 90; snd.RollOffMinDistance = 6
		snd.Parent = sp; snd:Play()
		FX_Debris:AddItem(sp, 3)
	end
	-- 즉발 버스트 + 지속 방출 후 자연 페이드 (요소 다 보이게)
	local emitters = {}
	for _, pe in ipairs(clone:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then
			pe:Emit(25)
			emitters[#emitters + 1] = pe
		end
	end
	local EMIT_TIME = 1.5   -- 지속 방출 시간 (요소 다 뜰 때까지)
	task.delay(EMIT_TIME, function()
		for _, pe in ipairs(emitters) do pe.Enabled = false end
	end)
	FX_Debris:AddItem(clone, EMIT_TIME + 1.5)   -- 방출 후 파티클 수명만큼 더 유지 후 정리
end

-- ── 타격 윈도우 + 중복 방지 (클래식/다이아와 동일 패턴) ──────
local canDamage    = false
local windowDamage = 0
local HIT_COOLDOWN = 0.5
local lastHitTime  = {}

-- 스윙 애니메이션(랜덤 — 드래곤 검 특유의 다채로운 스윙 손맛 유지)
-- 좌베기(LeftSlash) + 우베기(RightSlash) 두 동작만 랜덤 사용. (특수 동작=정적 포즈라 제외)
local anims = {"LeftSlash","RightSlash"}

local Char, Hum, Plyr

-- ── creator 태그 (킬 크레딧 → RoundSystem이 읽음) ────────────
local function UntagHumanoid(humanoid)
	for _, v in ipairs(humanoid:GetChildren()) do
		if v.Name == "creator" then v:Destroy() end
	end
end

local function TagHumanoid(humanoid, player)
	UntagHumanoid(humanoid)
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = player
	tag.Parent = humanoid
	Debris:AddItem(tag, 2)
end

-- ── 화상 도트 적용 (갱신형) ──────────────────────────────────
-- 만료 시각을 갱신하고, 루프가 안 돌고 있으면 새로 시작. 이미 돌고 있으면 시각만 연장.
local function applyBurn(character, humanoid, attacker)
	burnUntil[character] = os.clock() + BURN_DURATION

	if burnActive[character] then return end   -- 이미 화상 루프 진행 중 → 시각만 갱신됨
	burnActive[character] = true

	task.spawn(function()
		while burnActive[character] do
			task.wait(BURN_INTERVAL)
			-- 만료 / 사망 / 대상 소멸 체크
			if not humanoid or humanoid.Health <= 0 or not character.Parent then break end
			if os.clock() >= (burnUntil[character] or 0) then break end
			-- 킬 크레딧을 화상 시전자에게 유지 (도트로 죽어도 처치 인정)
			if attacker and attacker.Parent then
				TagHumanoid(humanoid, attacker)
			end
			if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
			humanoid:TakeDamage(BURN_TICK)
		end
		burnActive[character] = nil
		burnUntil[character] = nil
	end)
end

-- ── 화염 표식 스택 적용 ──────────────────────────────────────
-- 타격마다 +1, 만료 시각 갱신. 10스택 도달 시 폭발 데미지 + 초기화.
-- 반환: 현재 스택 수(표시용), 폭발 여부.
local function addFireStack(character, humanoid, attacker)
	stackUntil[character] = os.clock() + STACK_DURATION
	local cur = (fireStacks[character] or 0) + 1

	if cur >= STACK_MAX then
		-- 10스택 폭발: 큰 데미지 + 초기화
		fireStacks[character] = 0
		if attacker and attacker.Parent then
			TagHumanoid(humanoid, attacker)
		end
		if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return STACK_MAX, false end
		humanoid:TakeDamage(math.min(STACK_EXPLODE_CAP, humanoid.MaxHealth * STACK_EXPLODE_PCT))
		spawnFlameX(character, attacker)   -- 스택 폭발 불꽃 X 연출
		return STACK_MAX, true   -- 표시용으로 10(폭발) 알림
	else
		fireStacks[character] = cur
		-- 스택 만료 감시 루프(없으면 시작). 마지막 타격 후 STACK_DURATION 지나면 리셋.
		if not stackWatcher[character] then
			stackWatcher[character] = true
			task.spawn(function()
				while stackWatcher[character] do
					task.wait(0.25)
					if not character.Parent or not humanoid or humanoid.Health <= 0 then break end
					if os.clock() >= (stackUntil[character] or 0) then break end
				end
				fireStacks[character] = nil
				stackUntil[character] = nil
				stackWatcher[character] = nil
			end)
		end
		return cur, false
	end
end

-- ── 타격 판정 ────────────────────────────────────────────────
local function Blow(hit)
	if not hit or not hit.Parent then return end
	if not Char or not Hum or Hum.Health <= 0 then return end

	-- 칼날이 실제로 내 손에 쥐어져 있는지 (다른 도구 오작동 방지)
	local rightArm = Char:FindFirstChild("Right Arm") or Char:FindFirstChild("RightHand")
	if not rightArm then return end
	local grip = rightArm:FindFirstChild("RightGrip")
	if not grip or (grip.Part0 ~= Handle and grip.Part1 ~= Handle) then return end

	local character = hit.Parent
	if character == Char then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health == 0 then return end

	-- 진영 체크: 러너 무기는 태거만 공격. 아군(러너 플레이어/AI 러너봇) 오사 차단.
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		if player == Plyr or player:GetAttribute("Role") ~= "Tagger" then return end
	else
		if character:GetAttribute("AIRunner") or character:GetAttribute("RunnerBot")
			or (character.Parent and (character.Parent:GetAttribute("AIRunner") or character.Parent:GetAttribute("RunnerBot"))) then
			return
		end
	end

	-- 휘두르는 중이 아니면 데미지 없음(그냥 닿기만 한 경우 무시)
	if not canDamage then return end

	-- 같은 대상 중복 타격 방지
	local now = os.clock()
	local last = lastHitTime[character]
	if last and (now - last) < HIT_COOLDOWN then return end
	lastHitTime[character] = now

	-- 🏷️ [2026-09-12] 봇이면 캐릭터 모델로 태그한다.
	--   [증상] 히어로봇이 막타를 내면 킬 이펙트가 안 나왔다
	--     (실측: "[KillFxGate] 처형 스킵 → KING | 사유=킬러 없음 | creator=없음").
	--   [원인] Plyr 는 봇에서 nil 이다. TagHumanoid 가 기존 태그를 먼저 지우고
	--     nil 을 넣으므로, 유저가 남긴 creator 까지 함께 날아간다.
	--     화상 도트(applyBurn)도 매 틱 같은 일을 한다 — 피해가 누적된다.
	--   ⚠️ creator 는 킬 이펙트뿐 아니라 어그로·킬 크레딧·처형 판정이 모두 읽는다.
	--   [형태] RunnerBotDriveController 가 같은 상황에서 `creator.Value = bot` 으로
	--     봇 모델을 넣는다. 그 형태를 따른다 — RoundSystem 사망 핸들러가 이미 읽을 줄 안다.
	TagHumanoid(humanoid, Plyr or Char)
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
	humanoid:TakeDamage(windowDamage)

	-- 화상 도트 부여(갱신형, 미세 도트).
	--   ⚠️ attacker 도 `Plyr or Char` 다 — 위 TagHumanoid 주석 참조.
	--     봇이면 nil 이 들어가 화상 틱마다 creator 를 지운다.
	applyBurn(character, humanoid, Plyr or Char)

	-- 화염 표식 스택 +1 (6스택 시 폭발).
	local stacks, exploded = addFireStack(character, humanoid, Plyr or Char)

	-- 데미지/스택 표시: 공격자(파이어 소드 러너) 본인 클라로만 전송.
	-- 다른 러너와 공유 안 됨(검마다 스크립트·스택이 독립). 태거에겐 표시 안 함.
	if Plyr then
		-- 🔢 CC 중이면 화면 숫자를 실효값으로 환산한다(판정은 원본 그대로).
		FXRemote:FireClient(Plyr, "hitFX",
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, windowDamage)) or windowDamage,
			hit.Position, stacks, exploded)
	else
		-- 🤖 [진단 2026-09-12] 히어로봇 경로. Plyr 가 nil 이라 위 FireClient 를 건너뛰므로
		--   서버에 아무 흔적도 안 남았다 — "스택이 도는지 알 수가 없다"의 원인.
		--   ⚠️ 원인 확정 후 삭제하거나 조건부로 낮출 것. 히어로 3~4마리 × 매 타격이라
		--     로그가 빠르게 쌓인다.
		if _G.HeroWeaponDiag then
			print(string.format("🔥 [DF/Bot] %s → %s | %d뎀 | 스택 %d/%d%s",
				Char and Char.Name or "?", character.Name, windowDamage,
				stacks, STACK_MAX, exploded and "  💥폭발" or ""))
		end
	end

	-- 화염 강조: 타격 순간 확 키웠다가 0.3초 후 평소의 은은한 불로 복귀.
	-- 폭발 시엔 더 크게.
	Fire.Size = exploded and 5 or 2.5
	Fire.Heat = exploded and 30 or 25
	task.delay(0.3, function()
		Fire.Size = 0.7   -- 평소 은은한 불
		Fire.Heat = 8
	end)
end

-- ── 공격 ─────────────────────────────────────────────────────
Tool.Enabled = true
local lastAnimName = ""
local function Activated()
	if not Tool.Enabled then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	Tool.Enabled = false

	-- 좌/우 베기 랜덤 — 서버에서 직접 재생(모든 클라에 자동 복제).
	local newName = anims[math.random(1, #anims)]
	while newName == lastAnimName do
		newName = anims[math.random(1, #anims)]
	end
	lastAnimName = newName

	local animObj = Tool:FindFirstChild(newName)
	if animObj then
		local animator = Hum:FindFirstChildOfClass("Animator")
		local track
		if animator then
			track = animator:LoadAnimation(animObj)
		else
			track = Hum:LoadAnimation(animObj)
		end
		track.Priority = Enum.AnimationPriority.Action  -- 걷기/서기 위에 덮어쓰기
		track:Play(0.1, 1, 1)

		-- 🔬 [진단 2026-09-12] 봇에서 스윙 모션이 안 보인다는 제보.
		--   [주의] 로드 성공은 재생 가능을 뜻하지 않는다 — Length 0 이면 리그 불일치다
		--     (RunnerBotDriveController:58 주석이 같은 함정을 이미 기록했다).
		--   ⚠️ Length 는 로드 직후 0 으로 나올 수 있어 0.3초 뒤에 잰다.
		if _G.HeroWeaponDiag and not Plyr then
			task.delay(0.3, function()
				print(string.format("🎬 [DF/Anim] %s | %s | 길이=%.2fs | 재생=%s | 위치=%.2f%s",
					Char and Char.Name or "?", newName, track.Length,
					tostring(track.IsPlaying), track.TimePosition,
					track.Length <= 0 and "  ← ⚠️ 0초! 리그 불일치" or ""))
			end)
		end
	end

	-- 휘두름 사운드: 두 사운드 동시 출력 (볼륨은 인스턴스에 0.35로 설정 = 기본 대비 30% 낮춤)
	local sA = Handle:FindFirstChild("SwingSoundA")
	local sB = Handle:FindFirstChild("SwingSoundB")
	if sA then sA:Play() end
	if sB then sB:Play() end

	-- 타격 윈도우 열기 (휘두르는 동안만 데미지)
	windowDamage = SLASH_DAMAGE
	canDamage = true
	task.delay(0.35, function() canDamage = false end)

	wait(0.5)   -- 공격 쿨다운
	Tool.Enabled = true
end

local function Equipped()
	Char = Tool.Parent
	Hum  = Char:FindFirstChildOfClass("Humanoid")
	Plyr = Players:GetPlayerFromCharacter(Char)
	-- 평소에도 은은한 불꽃 유지 (불의 검 컨셉). 타격 시 잠깐 강해짐.
	Fire.Enabled = true
	Fire.Size = 0.7
	Fire.Heat = 8
end

local function Unequipped()
	canDamage = false
end

Tool.Activated:Connect(Activated)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)
Handle.Touched:Connect(Blow)
