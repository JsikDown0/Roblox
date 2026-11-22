-- HammerLow (저급 망치) 서버 스크립트
-- 일반 공격: 느린 공속 + 강한 단발. (스핀 슬래시 스킬은 이후 추가)
-- 게임 구조: 러너 무기 → 태거만 공격(아군 오사 차단), canDamage 윈도우 + creator 태그.
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local Tool   = script.Parent
local Handle = Tool:WaitForChild("Handle")
local SlashSound = Handle:WaitForChild("SlashSound")
local HitSound   = Handle:WaitForChild("HitSound")
local SpinSound  = Handle:WaitForChild("SpinSound")   -- 스킬(스핀) 전용 사운드
local SpinRemote = Tool:WaitForChild("SpinRemote")   -- 클라 스핀 발동 입력

-- ── 데미지/공속 (망치: 강한 단발 + 느린 공속) ────────────────
local HIT_DAMAGE   = 29     -- 단발 데미지
-- 🔺 [밸런스 2026-09-08] 24 → 29 (스핀 틱 9 → 11 과 한 세트, 약 1.2배).
--   [왜] 1대1 통제 실험(킹 HP 975 고정, 8종 20판)에서 6.7 DPS 로 최하위였다.
--     전체 중앙값 8.5 · 목표 8.0 에 맞춘다.
--   ⚠️ 아래 [계산] 주석의 20.0 DPS 는 '스핀 10틱 전부 명중' 가정이라 실측과 어긋난다.
--     실측(09-08 원본 로그 10회): 스핀 명중이 3~8틱, 중앙값 4.5/10 이었다.
--       23:26:30 4틱 / 23:26:42 4틱 / 23:26:51 5틱 / 23:27:00 6틱
--       23:27:10 3틱 / 23:27:20 8틱 / 23:27:29 3틱 / 23:28:37 8틱 …
--     SPIN_KNOCK 45 가 킹을 SPIN_RADIUS 15 밖으로 밀어내 자기 딜을 깎는다.
--     → 스핀 실효는 90 이 아니라 약 40. 이론 계산을 근거로 쓰지 말 것.
--   ⚠️ 넉백·반경·쿨은 건드리지 않는다. 이 무기의 강점은 DPS 가 아니라 생존이다 —
--     실측에서 148초를 버티며 킹을 98% 까지 깎았고(타임아웃 패), 유일하게
--     "거리를 두고 스킬만 반복"이 성립하는 무기다. 딜만 올려 그 구조를 유지한다.
--   ⚠️ 되돌릴 값: HIT_DAMAGE 24 / SPIN_TICK_DMG 9
-- ⚠️ [밸런스 2026-08-29] 20 → 24. Normal 목표 20 DPS 에 맞춤.
--   [계산] 실효 사이클은 SPIN_DURATION(2.5) + SPIN_COOLDOWN(6) = 8.5초다.
--     쿨이 '회전이 끝난 뒤' 시작되므로 6초가 아니다(startSpin 의 CdUntil 참조).
--     스핀 2.5초 동안은 평타가 잠기므로(Tool.Enabled=false) 평타 가동은 6.0/8.5.
--       평타 24/1.8 × (6.0/8.5) = 9.4 DPS
--       스핀 9×10틱 = 90 / 8.5   = 10.6 DPS   → 합계 20.0
--   ⚠️ 쿨·공속·지속은 건드리지 않았다. Q대시로 벽에 붙여 풀틱을 넣는 연계가
--     이 무기의 숙련 보상이라, 쿨을 올리면 그 설계가 죽는다.
local ATTACK_CD    = 1.8    -- 공격 쿨다운(초) — 느린 공속 (더 묵직하게)
local SWING_TIME   = 0.5    -- 타격 윈도우 지속(초)

-- ── 스핀 슬래시 설정 (가렌 E식 회전 넉백) ───────────────────
-- 평지에선 넉백이 태거를 밀어내 손해지만, 벽·언덕 근처에선 막혀서 지속 넉백 = 사실상 스턴.
local SPIN_DURATION = 2.5    -- 회전 지속(초)
local SPIN_TICK     = 0.25   -- 타격/넉백 판정 간격(초)
local SPIN_RADIUS   = 15     -- 타격 반경(스터드) — spin_effect 시각 링 크기에 맞춤
local SPIN_TICK_DMG = 11     -- 틱당 데미지 (9 → 11, 2026-09-08 · HIT_DAMAGE 주석 참조)
local SPIN_KNOCK    = 45     -- 넉백 속도(물리 — 벽이 막아줌)
local SPIN_SLOW     = 0.5    -- 회전 중 이속 배율(50%, 즉사엔 그대로 취약)
local SPIN_COOLDOWN = 6      -- 종료 후 재사용 쿨다운(초) (8→6)

-- 🔬 [진단 2026-09-03] 스핀이 태거를 실제로 얼마나 밀어내는지 측정.
--   [왜] 09-03 로그에 해머 관련 서버 기록이 '지급' 한 줄뿐이었다. 그래서 30초 내내
--     킹을 밀어내 존 진입을 막고 있었다는 사실이 로그만으로는 보이지 않았고,
--     "로그에 없으니 안 일어났다"로 오독했다. 밀림이 점령의 원인인지 판단하려면
--     "몇 틱 맞췄고 몇 stud 밀렸나"가 로그에 남아야 한다.
--   ⚠️ 확인 끝나면 DBG_SPIN = false. 끄는 스위치를 같은 편집에 넣어둔다.
--   ✅ [2026-09-13] 확인 종료 — false 로 되돌린다. 밀림이 점령의 원인인지는
--     09-11 에 "점령 = 디버프"로 정리됐고, 그 뒤 로그 판독에 이 줄이 더 필요하지 않았다.
--     ⚠️ 다시 켤 일이 생기면 DBG_KB(TaggerBotSystem:311)와 짝으로 볼 것 —
--       이쪽은 '몇 stud 밀렸나', 저쪽은 '넉백 감쇠가 먹었나'로 묻는 게 다르다.
local DBG_SPIN      = false
local dbgSpinTgt    = nil    -- 이번 스핀에서 맞춘 태거 (첫 명중 대상으로 고정)
local dbgSpinPos    = nil    -- 첫 명중 시점의 태거 좌표
local dbgSpinTicks  = 0      -- 명중한 틱 수
-- ⚠️ [측정 결함 수정 2026-09-03] 순변위만으로는 밀림을 기각하게 된다.
--   첫 명중 → 스핀 종료 0.3초 뒤만 재면, 30 밀렸다가 27 걸어 돌아온 경우가 '3' 으로 찍힌다.
--   "밀렸다가 복귀했다"와 "안 밀렸다"가 같은 숫자가 되므로 최고 변위를 따로 남긴다.
local dbgSpinPeak   = 0      -- 첫 명중 좌표로부터의 최대 이탈 거리

local spinning      = false  -- 현재 회전 중인가
local spinSavedWalk = nil    -- 회전 진입 전 원래 속도
local currentEffect = nil    -- 현재 소환된 스핀 이펙트 (정리용)
local spinId        = 0      -- 회전 세션 ID (중단된 회전의 뒤처리가 새 회전을 망치지 않게 구분)
local ServerStorage = game:GetService("ServerStorage")
local spinEffectTemplate = ServerStorage:FindFirstChild("SpinEffectTemplate")
local SPIN_VISUAL_SCALE = 1.0   -- 이펙트 크기 배율 (범위 SPIN_RADIUS에 맞춰 조정)

-- ── 번개 타격 이펙트 (LightningHammer 스킨: 태거 타격 시마다 번개 소환) ──
local thunderStrikeTemplate = ServerStorage:FindFirstChild("ThunderStrikeTemplate")
local lastThunderTime = 0
local THUNDER_MIN_INTERVAL = 0.15   -- 번개 연출 최소 간격(연타 시 과도한 소환 방지)
local function spawnThunderStrike(targetRoot)
	if not Tool:GetAttribute("ThunderStrike") then return end   -- 번개 스킨일 때만
	if not thunderStrikeTemplate or not targetRoot then return end
	local now = os.clock()
	if now - lastThunderTime < THUNDER_MIN_INTERVAL then return end
	lastThunderTime = now

	local strike = thunderStrikeTemplate:Clone()
	-- 번개 기둥(lighting 파트)을 타격 대상의 수평 위치에 정확히 맞춤.
	-- 수평(XZ)은 대상 정중앙에, 높이(Y)는 lighting 오프셋만 보정해 대상 발치 기준으로.
	local pivot = strike:GetPivot()
	local lightingPart = strike:FindFirstChild("lighting")
	local lp = lightingPart and lightingPart.Position or pivot.Position
	-- pivot을 옮길 목표: lighting이 대상의 (X, 발높이, Z)에 오도록
	local targetPos = targetRoot.Position
	-- 대상 발 높이 (HumanoidRootPart 중심에서 약 3스터드 아래 = 발바닥)
	local footY = targetPos.Y - 3
	-- 번개가 쏠려 보여서 Z축으로 살짝 보정
	local desiredLightingPos = Vector3.new(targetPos.X, footY, targetPos.Z + 3)
	local offset = lp - pivot.Position           -- pivot→lighting 상대 위치
	strike:PivotTo(CFrame.new(desiredLightingPos - offset))
	strike.Parent = workspace
	-- 사운드 명시 재생 (복제본은 Playing 상태가 꼬일 수 있어 직접 Stop→Play)
	for _, s in ipairs(strike:GetDescendants()) do
		if s:IsA("Sound") then
			s:Stop()
			s:Play()
		end
	end
	-- 파티클은 잠깐만 터지고 사라지게 (Rate는 그대로 두되, 짧게 산 뒤 제거)
	Debris:AddItem(strike, 1.5)
	-- 0.4초 뒤 파티클 방출 정지 (남은 입자는 수명대로 사라짐)
	task.delay(0.4, function()
		if strike and strike.Parent then
			for _, pe in ipairs(strike:GetDescendants()) do
				if pe:IsA("ParticleEmitter") then pe.Enabled = false end
			end
		end
	end)
end

-- ── 타격 윈도우 + 중복 방지 ──────────────────────────────────
local canDamage    = false
local windowDamage = 0
local HIT_COOLDOWN = 0.6    -- 같은 대상 중복 타격 방지
local lastHitTime  = {}

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

-- ── 타격 판정 ────────────────────────────────────────────────
local function Blow(hit)
	if not hit or not hit.Parent then return end
	if not Char or not Hum or Hum.Health <= 0 then return end

	local character = hit.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health == 0 then return end

	-- 진영 체크: 러너 무기는 태거만 공격. 아군(러너/AI 러너봇) 오사 차단.
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		if player == Plyr or player:GetAttribute("Role") ~= "Tagger" then return end
	else
		if character:GetAttribute("AIRunner") or character:GetAttribute("RunnerBot")
			or (character.Parent and (character.Parent:GetAttribute("AIRunner") or character.Parent:GetAttribute("RunnerBot"))) then
			return
		end
	end

	-- 휘두르는 중이 아니면 데미지 없음
	if not canDamage then return end

	-- 같은 대상 중복 타격 방지
	local now = os.clock()
	local last = lastHitTime[character]
	if last and (now - last) < HIT_COOLDOWN then return end
	lastHitTime[character] = now

	-- 🏷️ 봇이면 캐릭터 모델로 태그한다(DragonFireSword 와 같은 처리).
	--   Plyr 가 nil 이면 TagHumanoid 가 기존 태그를 지우고 nil 을 넣어,
	--   유저가 남긴 creator 까지 함께 날아간다. creator 는 킬 크레딧·어그로가 읽는다.
	TagHumanoid(humanoid, Plyr or Char)
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
	humanoid:TakeDamage(windowDamage)
	-- 🔢 [2026-09-06] 데미지 표기. 해머는 숫자가 없어 "때린 건지 모르겠다"는 문제가 있었다.
	--   ⚠️ _G.DisplayDamage 를 먼저 통과시킨다. CC 중이면 판정값과 체감값이 다르다
	--     (아이스보우 ×1/1.43 등) — 다른 무기들이 쓰는 규약과 같게 맞춘다.
	if _G.ShowDamage and Plyr then
		local root = character:FindFirstChild("HumanoidRootPart")
		_G.ShowDamage(Plyr,
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, windowDamage)) or windowDamage,
			root and root.Position or (Handle and Handle.Position), false)
	end
	HitSound:Play()
	spawnThunderStrike(character:FindFirstChild("HumanoidRootPart"))   -- 번개 스킨이면 타격 지점에 번개
end

-- ── 휘두름 애니 (R6 toolanim + R15 기본) ─────────────────────
local function playSwing()
	-- R6: toolanim StringValue
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = Tool
	Debris:AddItem(anim, 0.5)
end

-- ── 일반 공격 ────────────────────────────────────────────────
local function Activated()
	if spinning then return end   -- 회전 중엔 일반 공격 불가
	if not Tool.Enabled then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	Tool.Enabled = false

	playSwing()
	SlashSound:Play()

	-- 타격 윈도우 열기 (휘두르는 동안만 데미지)
	windowDamage = HIT_DAMAGE
	canDamage = true
	task.delay(SWING_TIME, function() canDamage = false end)

	wait(ATTACK_CD)   -- 느린 공속
	Tool.Enabled = true
end

-- ── 스핀 슬래시 (회전 넉백) ──────────────────────────────────
-- 한 틱: 반경 내 태거에게 데미지 + 물리 넉백(러너 중심에서 바깥으로 밀기).
local function spinTick()
	if not Char then return end
	local hrp = Char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for _, other in ipairs(workspace:GetDescendants()) do
		if other:IsA("Model") and other ~= Char then
			local oHum = other:FindFirstChildOfClass("Humanoid")
			local oRoot = other:FindFirstChild("HumanoidRootPart")
			if oHum and oRoot and oHum.Health > 0 then
				-- 진영 체크: 태거만 (아군 러너/봇 제외)
				local oPlayer = Players:GetPlayerFromCharacter(other)
				local isTagger = false
				if oPlayer then
					isTagger = (oPlayer ~= Plyr and oPlayer:GetAttribute("Role") == "Tagger")
				else
					-- NPC 태거 더미 등: 러너봇이 아니면 태거로 간주
					isTagger = not (other:GetAttribute("AIRunner") or other:GetAttribute("RunnerBot"))
				end
				if isTagger then
					local delta = oRoot.Position - hrp.Position
					local dist = delta.Magnitude
					if dist <= SPIN_RADIUS and dist > 0.1 then
						-- 데미지 + 크레딧
						TagHumanoid(oHum, Plyr or Char)   -- 🏷️ 봇이면 캐릭터 모델
						if _G.IsDamageImmune and _G.IsDamageImmune(oHum.Parent) then continue end
						oHum:TakeDamage(SPIN_TICK_DMG)
						-- 🔢 스핀 타격도 표기. crit=true 로 금색 — 스킬임을 평타와 구분한다.
						if _G.ShowDamage and Plyr then
							_G.ShowDamage(Plyr,
								(_G.DisplayDamage and _G.DisplayDamage(oHum.Parent, SPIN_TICK_DMG)) or SPIN_TICK_DMG,
								oRoot.Position, true)
						end
						HitSound:Play()
						spawnThunderStrike(oRoot)   -- 번개 스킨이면 타격 지점에 번개
						-- 물리 넉백: 러너 중심에서 바깥 방향으로 속도 부여.
						-- 순간이동이 아니라 속도라, 벽·지형이 막으면 자연히 안 밀림 = 지속 넉백.
						local dir = (delta * Vector3.new(1, 0, 1)).Unit  -- 수평만
						local lv = Instance.new("LinearVelocity")
						local att = Instance.new("Attachment")
						att.Parent = oRoot
						lv.Attachment0 = att
						lv.MaxForce = math.max(oRoot.AssemblyMass, 1) * 10000   -- 무한 힘 금지(벽 밀착 시 솔버 발산 → 좌표 폭주)
						lv.VectorVelocity = dir * SPIN_KNOCK + Vector3.new(0, 12, 0)  -- 바깥 + 살짝 띄움
						lv.Parent = oRoot
						Debris:AddItem(lv, 0.15)
						Debris:AddItem(att, 0.15)
						-- 🔬 [진단] 명중 틱 누적 + 첫 명중 좌표 기록 (스핀 종료 시 거리 계산)
						if DBG_SPIN then
							dbgSpinTicks += 1
							if not dbgSpinTgt then
								dbgSpinTgt, dbgSpinPos = other, oRoot.Position
							end
							-- 이 틱 시점의 좌표는 '직전 틱들이 밀어낸 결과'다. 최고점만 남긴다.
							if dbgSpinPos then
								local dd = (oRoot.Position - dbgSpinPos).Magnitude
								if dd > dbgSpinPeak then dbgSpinPeak = dd end
							end
						end
					end
				end
			end
		end
	end
end

local function startSpin()
	if spinning then return end
	-- 쿨다운은 플레이어 속성(다음 사용 가능 시각)으로 관리 → 무기 내렸다 다시 들어도 우회 불가.
	-- 🤖 [2026-09-12] 봇은 Player 가 없으므로 캐릭터 속성에 같은 키로 박는다.
	--   [왜] Plyr 가드 안에만 두면 봇은 쿨다운이 없어 매 틱 스핀이 가능해진다.
	--   ⚠️ 키 이름을 같게 둔다 — "어디에 저장되나"를 두 번 찾지 않게.
	local cdHolder = Plyr or Char
	if cdHolder then
		local cdUntil = cdHolder:GetAttribute("HammerSpinCdUntil") or 0
		if os.clock() < cdUntil then return end   -- 아직 쿨다운 중
	end
	if not Char or not Hum or Hum.Health <= 0 then return end
	spinning = true
	if DBG_SPIN then dbgSpinTgt, dbgSpinPos, dbgSpinTicks, dbgSpinPeak = nil, nil, 0, 0 end   -- 🔬 진단 초기화
	spinId = spinId + 1          -- 이번 회전 세션 ID
	local mySpinId = spinId      -- 이 회전이 자기 것인지 식별
	-- 회전 시작과 동시에 쿨다운 시각을 미리 박아둠 (회전 시간 + 쿨다운).
	-- 회전 도중 무기를 내려도 이 시각이 플레이어에 남아 무한 사용 차단.
	if cdHolder then
		cdHolder:SetAttribute("HammerSpinCdUntil", os.clock() + SPIN_DURATION + SPIN_COOLDOWN)
	end
	Tool.Enabled = false   -- 회전 중 일반 공격 잠금

	-- 이속 둔화 (즉사엔 그대로 취약 = 하이리스크)
	spinSavedWalk = Hum.WalkSpeed
	Hum.WalkSpeed = spinSavedWalk * SPIN_SLOW

	SpinSound:Play()   -- 스킬 전용 사운드

	-- 스핀 이펙트 소환 (러너 몸 주위, 빠르게 자체 회전)
	local hrp = Char:FindFirstChild("HumanoidRootPart")
	if currentEffect then currentEffect:Destroy(); currentEffect = nil end
	-- 스킨이 별도 이펙트 모델을 지정하면 그걸 쓰고(예: 흰/검 단색 회오리), 아니면 기본 템플릿.
	local modelName = Tool:GetAttribute("EffectModel")
	local chosenTemplate = spinEffectTemplate
	if modelName then
		local custom = ServerStorage:FindFirstChild(modelName)
		if custom then chosenTemplate = custom end
	end
	if chosenTemplate and hrp then
		local effect = chosenTemplate:Clone()
		currentEffect = effect
		effect.CFrame = hrp.CFrame
		effect.Parent = workspace
		-- DruidHammer 스킨이면 세계수 Billboard + 나뭇잎 파티클 신호 (클라 처리)
		if Tool:GetAttribute("MeshSwap") == "DruidHammer" and Plyr then
			local fxEv = game:GetService("ReplicatedStorage"):FindFirstChild("HammerSpinFx")
			-- 🤖 [2026-09-12] Plyr → (Plyr or Char). 봇은 Player 가 없어 수신부 가드에서 걸렸다.
	--   HammerSpinFxClient 가 Player·Character 둘 다 받게 고쳤다.
	if fxEv then fxEv:FireAllClients(Plyr or Char, "start") end
		end
		-- 스킨 이펙트 색: 별도 모델(EffectModel)을 쓰면 색 칠하기 건너뜀(모델 색 그대로 사용).
		local effectColor = (not modelName) and Tool:GetAttribute("EffectColor") or nil
		local skinSeq = nil
		if effectColor then
			-- 어두운쪽 → 스킨색 → 밝은쪽 그라데이션 (흑백 방지: 명도 폭 유지)
			local function dk(c,f) return Color3.new(math.max(0,c.R-f),math.max(0,c.G-f),math.max(0,c.B-f)) end
			local function lt(c,f) return Color3.new(math.min(1,c.R+f),math.min(1,c.G+f),math.min(1,c.B+f)) end
			skinSeq = ColorSequence.new({
				ColorSequenceKeypoint.new(0, dk(effectColor, 0.25)),
				ColorSequenceKeypoint.new(0.5, lt(effectColor, 0.2)),
				ColorSequenceKeypoint.new(1, dk(effectColor, 0.25)),
			})
		end
		-- 상하 높이만 압축 (수평 범위는 유지 → 판정과 계속 일치). Attachment Y만 축소.
		for _, a in ipairs(effect:GetDescendants()) do
			if a:IsA("Attachment") then
				local lp = a.Position
				a.Position = Vector3.new(lp.X, lp.Y * 0.5, lp.Z)
			end
			if skinSeq and a:IsA("Beam") then
				a.Color = skinSeq
			end
		end
		-- 번개 이펙트: ThunderLight PointLight를 1초마다 번쩍이게 (번개 깜빡임)
		local thunderLight = effect:FindFirstChild("ThunderLight")
		if thunderLight then
			task.spawn(function()
				while spinning and effect and effect.Parent and thunderLight.Parent do
					thunderLight.Enabled = true
					task.wait(0.1)            -- 짧게 번쩍
					if not (effect and effect.Parent) then break end
					thunderLight.Enabled = false
					task.wait(0.9)            -- 1초 주기 (0.1 켜짐 + 0.9 꺼짐)
				end
			end)
		end
		-- 용접 없이 매 프레임 위치+회전 직접 갱신 → 러너 따라다니며 빠르게 돎.
		local isRainbow = Tool:GetAttribute("RainbowSkin") == true
		-- 무지개면 미리 Beam 목록 수집 (매 프레임 색 갱신용)
		local rainbowBeams = nil
		if isRainbow then
			rainbowBeams = {}
			for _, b in ipairs(effect:GetDescendants()) do
				if b:IsA("Beam") then table.insert(rainbowBeams, b) end
			end
		end
		task.spawn(function()
			local angle = 0
			while spinning and effect and effect.Parent do
				local root = Char and Char:FindFirstChild("HumanoidRootPart")
				if not root then break end
				angle = angle + math.rad(28)   -- 프레임당 28도 → 적당히 빠른 회전
				effect.CFrame = root.CFrame * CFrame.Angles(0, angle, 0)
				-- 무지개: 망치 순환과 같은 Hue로 Beam 색 갱신 (CYCLE_TIME 3초 = 순환 스크립트와 동일)
				if rainbowBeams then
					local hue = (tick() % 3) / 3
					local col = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
					for _, b in ipairs(rainbowBeams) do
						if b.Parent then b.Color = col end
					end
				end
				task.wait()
			end
		end)
	end

	-- 회전 루프
	local elapsed = 0
	task.spawn(function()
		while spinning and elapsed < SPIN_DURATION do
			if not Hum or Hum.Health <= 0 then break end
			spinTick()
			task.wait(SPIN_TICK)
			elapsed = elapsed + SPIN_TICK
		end
		-- 종료 정리: 내가 시작한 회전이 여전히 최신일 때만 (중단 후 새 회전이 시작됐으면 건너뜀).
		if mySpinId ~= spinId then return end
		spinning = false
		SpinSound:Stop()   -- 스킬 끝나면 사운드도 종료
		if currentEffect then currentEffect:Destroy(); currentEffect = nil end   -- 이펙트 제거
		-- DruidHammer 세계수/나뭇잎 FX 종료 신호 (세계수는 클라에서 서서히 페이드)
		if Tool:GetAttribute("MeshSwap") == "DruidHammer" and Plyr then
			local fxEv = game:GetService("ReplicatedStorage"):FindFirstChild("HammerSpinFx")
			if fxEv then fxEv:FireAllClients(Plyr or Char, "stop") end   -- 🤖 봇 지원
		end
		if Hum and spinSavedWalk then
			Hum.WalkSpeed = spinSavedWalk
			-- 다운 인지: 다운 중이면 패널티 속도로 눌러씀 (스킬로 다운 이속 초기화 방지)
			local _c = Hum.Parent
			if _c and _c:GetAttribute("Downed") then Hum.WalkSpeed = 16 * 0.25 end
		end
		spinSavedWalk = nil
		Tool.Enabled = true
		-- 쿨다운: 회전이 정상으로 다 끝난 시점부터 SPIN_COOLDOWN.
		--   ⚠️ 봇은 캐릭터 속성에 박는다(위 startSpin 의 cdHolder 와 같은 규약).
		local holder = Plyr or Char
		if holder then
			holder:SetAttribute("HammerSpinCdUntil", os.clock() + SPIN_COOLDOWN)
		end
		if Plyr then
			SpinRemote:FireClient(Plyr, "spinEnded")  -- 클라 쿨다운 카운트다운 시작
		end
		-- 🔬 [진단] 이번 스핀이 태거를 실제로 몇 stud 밀어냈나.
		--   ⚠️ 물리가 정착하기 전에 재면 옛 좌표가 나온다(ODM 진단과 같은 함정) → 0.3초 지연.
		if DBG_SPIN and dbgSpinTgt and dbgSpinPos then
			local tgt, p0, n, pk = dbgSpinTgt, dbgSpinPos, dbgSpinTicks, dbgSpinPeak
			task.delay(0.3, function()
				local r = tgt:FindFirstChild("HumanoidRootPart")
				if not r then return end
				local d  = (r.Position - p0).Magnitude
				local mx = math.max(pk, d)
				-- 최고 ≫ 순 이면 "밀렸다가 걸어 돌아왔다" = 그 시간을 통째로 복귀에 쓴 것.
				-- 최고 ≈ 순 이면 "밀린 채로 끝났다". 둘은 대응이 다르다.
				print(string.format("🔬 [Spin] %s 명중 %d/%d틱 | 최고 %.0f / 순 %.0f stud | 복귀 %.0f",
					tgt.Name, n, math.floor(SPIN_DURATION / SPIN_TICK + 0.5), mx, d, mx - d))
			end)
		end
	end)
end

-- 클라 입력 수신: 스핀 발동
SpinRemote.OnServerEvent:Connect(function(player)
	if player ~= Plyr then return end
	startSpin()
end)

-- 🤖 [③ 2026-09-12] 봇 전용 진입점. 리모트를 우회해 서버가 직접 부른다.
--   [왜] Tool.Activated 는 Player 클릭으로만 발동하고, 리모트는 firingPlayer 가드가 막는다.
--     봇은 Player 가 없으므로 서버가 그 자리를 대신 채운다 —
--     봇 킹이 PushTool 을 구동하는 방식(PushTool.Server 의 botChargeTrack 분기)과 같은 형태다.
--   [규약] Tool 속성에 함수를 걸어 무기 인스턴스마다 자기 것을 갖게 한다.
--     _G 로 노출하면 히어로가 여럿일 때 마지막 하나가 나머지를 덮는다.
--   ⚠️ 쿨다운·회전·데미지는 전부 startSpin 안에 있다. 여기서 따로 세지 않는다.
local botSpin = Instance.new("BindableFunction")
botSpin.Name = "BotSkill"   -- ⚠️ 이름 규약. 무기마다 다르게 두면 봇 쪽에 분기가 쌓인다.
botSpin.OnInvoke = function()
	if spinning then return false end
	startSpin()
	return true
end
botSpin.Parent = Tool

-- 스킨 색 적용: Tool에 SkinColor 속성이 있으면 망치 Handle을 단색으로.
-- (무지개 스킨은 순환 스크립트가 Handle 색을 관리하므로 여기선 건드리지 않음)
local function applySkin()
	-- meshSwap 스킨: 원본 Handle 메시를 숨기고 스킨 모델을 Handle에 부착 (색놀이와 별개)
	local swapName = Tool:GetAttribute("MeshSwap")
	if swapName and not Handle:FindFirstChild("_skinMesh") then
		local wsFolder = ServerStorage:FindFirstChild("WeaponSkins")
		local swapModel = wsFolder and wsFolder:FindFirstChild(swapName)
		if swapModel then
			local swapScale = Tool:GetAttribute("SwapScale") or 1
			local swapOffset = Tool:GetAttribute("SwapOffset") or Vector3.new(0,0,0)
			local swapRot = Tool:GetAttribute("SwapRot") or Vector3.new(0,0,0)
			-- 원본 메시/텍스처 숨김
			-- 원본 메시 숨김: Handle 투명 + SpecialMesh는 Scale 0으로 축소(Transparency 없음)
			local origMesh = Handle:FindFirstChildOfClass("SpecialMesh")
			if origMesh then origMesh.Scale = Vector3.new(0, 0, 0) end
			Handle.Transparency = 1
			-- 스킨 메시 파트 복제해서 Handle에 부착
			local src = swapModel.PrimaryPart or swapModel:FindFirstChildWhichIsA("BasePart")
			if src then
				local skinPart = src:Clone()
				skinPart.Name = "_skinMesh"
				skinPart.Anchored = false
				skinPart.CanCollide = false
				skinPart.CanQuery = false
				skinPart.CanTouch = false
				skinPart.Massless = true
				if skinPart:IsA("MeshPart") and swapScale ~= 1 then
					skinPart.Size = skinPart.Size * swapScale
				end
				-- Handle 기준 정렬: offset(위치) + rot(회전)
				skinPart.CFrame = Handle.CFrame
					* CFrame.new(swapOffset)
					* CFrame.Angles(math.rad(swapRot.X), math.rad(swapRot.Y), math.rad(swapRot.Z))
				skinPart.Parent = Handle
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = Handle
				wc.Part1 = skinPart
				wc.Parent = skinPart
			end
		end
		return  -- meshSwap 스킨은 색놀이 분기 스킵
	end

	-- 오라 파티클(번개 등): Handle을 감싸는 상시 파티클 부착
	local auraName = Tool:GetAttribute("AuraParticle")
	if auraName and not Handle:FindFirstChild("_auraParticle") then
		local aTmpl = ServerStorage:FindFirstChild(auraName)
		if aTmpl and aTmpl:IsA("ParticleEmitter") then
			local p = aTmpl:Clone()
			p.Name = "_auraParticle"
			p.Parent = Handle
		end
	end

	if Tool:GetAttribute("RainbowSkin") then return end   -- 무지개는 순환 스크립트가 처리
	local skinColor = Tool:GetAttribute("SkinColor")
	if skinColor then
		local mesh = Handle:FindFirstChildOfClass("SpecialMesh")
		local matName = Tool:GetAttribute("SkinMaterial") or "Neon"
		Handle.Material = Enum.Material[matName] or Enum.Material.Neon
		if Tool:GetAttribute("KeepTexture") then
			-- 텍스처 유지(원본 디테일) + VertexColor로 색조 입힘 (예: 번개 망치 ForceField)
			if mesh then mesh.VertexColor = Vector3.new(skinColor.R, skinColor.G, skinColor.B) end
			Handle.Color = skinColor
		else
			-- 텍스처 비우고 단색 (Neon 색놀이 스킨)
			if mesh then mesh.TextureId = "" end
			Handle.Color = skinColor
		end
	end
end

local function Equipped()
	Char = Tool.Parent
	Hum  = Char:FindFirstChildOfClass("Humanoid")
	Plyr = Players:GetPlayerFromCharacter(Char)
	-- ★ 재장착 시 이전 시전 상태 리셋 (스핀 중 수동 재장착으로 spinning 고착 → 스킬 먹통 방지)
	if spinning then
		spinning = false
		if spinId then spinId = spinId + 1 end
		pcall(function() if Hum then Hum.WalkSpeed = 16; Hum.JumpPower = 50; Hum.PlatformStand = false end end)
	end
	Tool.Enabled = true
	applySkin()
end

local function Unequipped()
	canDamage = false
	-- 회전 중이면 클라가 즉시 재장착하므로(무기 전환 금지), 서버는 회전 상태를 건드리지 않고 유지.
	if spinning then return end
	-- 회전 중이 아닐 때(정상 해제)만 정리.
	if currentEffect then currentEffect:Destroy(); currentEffect = nil end
	SpinSound:Stop()
end

-- 🏁 [2026-09-06] 라운드가 끝나면 회전 상태를 강제로 종료한다.
--   [증상] 스핀 도중 라운드가 끝나면 이속이 8 로 굳은 채 로비로 나갔다.
--     걷기 애니가 그 속도에 맞춰 느리게 재생돼 "포즈가 굳었다"처럼 보였다.
--   [실측] 스핀 중 종료 WS=8.0 / 스핀 후 종료 WS=16.0. PlatformStand·Anchored·
--     Action 트랙은 전부 정상이었다 — 애니 문제가 아니라 WalkSpeed 문제다.
--   [원인] Unequipped 의 `if spinning then return end`. "클라가 즉시 재장착한다"는
--     전제로 정리를 건너뛰는데, 라운드 종료에는 재장착이 없다.
--   [왜 여기서도 고치나] RoundSystem 에 안전망을 뒀지만, 그것만으로는 spinning
--     플래그가 true 로 남는다. 다음 라운드에 startSpin 이 첫 줄에서 return 해
--     스킬이 통째로 먹통이 된다 — 이속만 고쳐서는 절반만 고치는 것이다.
--   ⚠️ RoundPhase 는 ReplicatedStorage 속성이다(AnimGuardClient 와 같은 규약).
--     stage1/stage2 가 아니면 라운드 밖이다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function forceEndSpin(reason)
	if not spinning then return end
	spinning = false
	spinId = spinId + 1          -- 진행 중이던 회전 루프를 무효화한다
	if currentEffect then currentEffect:Destroy(); currentEffect = nil end
	pcall(function() SpinSound:Stop() end)
	if Hum and Hum.Parent then
		-- 저장해둔 값이 있으면 그걸로, 없으면 기본값으로. 감속된 값이 남지 않게 한다.
		Hum.WalkSpeed = (spinSavedWalk and spinSavedWalk > 0) and spinSavedWalk or 16
		Hum.JumpPower = 50
		Hum.PlatformStand = false
	end
	-- ⚠️ 반드시 비운다. 안 비우면 다음 스핀의 startSpin 이 이 값을 '원래 속도'로
	--   덮어쓸 여지가 남는다 — 정상 종료 경로(위쪽)도 같은 이유로 nil 을 넣는다.
	spinSavedWalk = nil
	Tool.Enabled = true
	warn("[Hammer] 회전 강제 종료 (" .. tostring(reason) .. ") → WalkSpeed 복구")
end

ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	local ph = ReplicatedStorage:GetAttribute("RoundPhase")
	if ph == "stage1" or ph == "stage2" then return end
	forceEndSpin("phase=" .. tostring(ph))
end)

Tool.Activated:Connect(Activated)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)
Handle.Touched:Connect(Blow)
