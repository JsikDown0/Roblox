-- HammerHigh (고급 망치) 서버 스크립트
-- 차지-도약 슬램. 홀드 차지 → 도약 거리 증가 + 착지 예고 원(서버가 workspace에 Part 소환 → 전원에게 복제)
-- → 릴리스로 도약 + 슬램. 명중 시 태거 데미지 + 공중 부양 시각 스턴. 빗나가면 러너 자가 스턴(하이리스크).
-- 일반 공격은 느리고 강한 단타. 저급 망치(HammerLow)의 hit-detection/상태관리/세션ID/쿨다운 패턴 재사용.
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Tool   = script.Parent
local Handle = Tool:WaitForChild("Handle")
local SlashSound = Handle:WaitForChild("SlashSound")
local HitSound   = Handle:WaitForChild("HitSound")
local ChargeSound = Handle:WaitForChild("SpinSound")   -- 차지/슬램 사운드로 재활용
local AttackSound  = Handle:WaitForChild("AttackSound")   -- 일반 공격
local LeapSound    = Handle:WaitForChild("LeapSound")     -- 슬램 출발(날아가기 시작)
local LandSound    = Handle:WaitForChild("LandSound")     -- 예고원 도착(착지)
local SlamHitSound = Handle:WaitForChild("SlamHitSound")  -- 슬램 적중
local ChargeLoopA  = Handle:WaitForChild("ChargeLoopA")   -- 차징 루프 사운드 A
local ChargeLoopB  = Handle:WaitForChild("ChargeLoopB")   -- 차징 루프 사운드 B
local SlamRemote = Tool:WaitForChild("SlamRemote")
local ShakeEvent = game:GetService("ReplicatedStorage"):WaitForChild("HammerShakeEvent")

-- ── flame tail 제어 (필살기 차징 임팩트 — 평소 OFF, 슬램 선딜~착지에만 ON) ──
local flameTail = Tool:FindFirstChild("flame tail")
-- flame tail 하위 이펙트(Beam/ParticleEmitter)를 수집. 각자의 원래 Enabled 기억.
local flameEmitters = {}
if flameTail then
	for _, e in ipairs(flameTail:GetDescendants()) do
		if e:IsA("Beam") or e:IsA("ParticleEmitter") then
			table.insert(flameEmitters, e)
			e.Enabled = false   -- 평소엔 꺼둠
		end
	end
end
local function setFlameTail(on)
	for _, e in ipairs(flameEmitters) do
		if e and e.Parent then
			e.Enabled = on
			-- 켤 때: 꼬리를 만드는 긴 수명 파티클(Specs)은 Rate로 천천히 차오르면 1~2초 늦게
			-- 완성됨. 켜는 순간 한 사이클치(Rate×최대수명)를 Emit해 즉시 꼬리를 채움.
			-- Specs는 Speed가 높아(최대 53) Emit해도 바로 퍼져 꼬리 형성 → 지연 제거.
			if on and e:IsA("ParticleEmitter") and e.Lifetime.Max >= 1 and e.Speed.Max >= 1 then
				local n = math.clamp(math.ceil(e.Rate * e.Lifetime.Max), 1, 40)
				e:Emit(n)
			end
		end
	end
end
setFlameTail(false)   -- 시작 시 OFF 보장

-- ── 색 스킨 (무지개 순환 + 단색 11종) ──────────────────────────
-- 무지개: 시간에 따라 hue가 도는 루프. 단색: 고정 색 한 번 칠하고 끝.
-- 둘 다 같은 대상 파트(머리+포인트들)와 flame tail 불꽃을 칠함.
local RAINBOW_TEST = false         -- false면 RainbowSkin 속성 장착 시에만 무지개 (정식 스킨)
local RAINBOW_CYCLE = 3.0          -- 한 바퀴(빨~보~빨) 도는 시간(초)

-- 색을 입힐 망치 본체 파트들 (머리 + 금색 포인트 + 손잡이)
local SKIN_PART_NAMES = { "Cube.004", "Cylinder.004", "Handle" }
local skinParts = {}               -- { part = 인스턴스, origColor, origMaterial }
for _, nm in ipairs(SKIN_PART_NAMES) do
	local p = Tool:FindFirstChild(nm)
	if p then
		table.insert(skinParts, { part = p, origColor = p.Color, origMaterial = p.Material })
	end
end

-- flame tail 이펙트별 "기준 명도·채도"를 미리 추출 (hue만 바꾸고 명도 관계 유지 → 불꽃 질감 보존)
-- 원래 Color/Transparency도 백업 (검정 스킨 등에서 변경 후 원복용)
local flameBaseHSV = {}
for _, e in ipairs(flameEmitters) do
	local c = e.Color.Keypoints[1].Value
	local _, s, v = Color3.toHSV(c)
	flameBaseHSV[e] = { s = s, v = v, origColor = e.Color, origTransparency = e.Transparency }
end

-- 본체 파트들을 특정 hue로 칠함 (Neon으로 선명하게)
local function paintBodyHue(hue)
	for _, sp in ipairs(skinParts) do
		if sp.part and sp.part.Parent then
			sp.part.Material = Enum.Material.Neon
			sp.part.Color = Color3.fromHSV(hue, 1, 1)
		end
	end
end
-- flame tail을 특정 hue로 칠함 (각 이펙트 원래 S·V 유지)
local function paintFlameHue(hue)
	for _, e in ipairs(flameEmitters) do
		if e and e.Parent then
			local base = flameBaseHSV[e]
			e.Color = ColorSequence.new(Color3.fromHSV(hue, base.s, base.v))
		end
	end
end
-- 본체 파트 원래 색·재질로 복원
local function restoreBody()
	for _, sp in ipairs(skinParts) do
		if sp.part and sp.part.Parent then
			sp.part.Color = sp.origColor
			sp.part.Material = sp.origMaterial
		end
	end
end

local colorRunning = false

-- 무지개: 매 프레임 hue를 굴리는 루프
local function startRainbow()
	if colorRunning then return end
	if not RAINBOW_TEST and not Tool:GetAttribute("RainbowSkin") then return end
	colorRunning = true
	task.spawn(function()
		while colorRunning do
			local hue = (tick() % RAINBOW_CYCLE) / RAINBOW_CYCLE
			paintBodyHue(hue)
			paintFlameHue(hue)
			task.wait()
		end
	end)
end

-- 단색: 고정 색 한 번 칠하고 끝 (루프 없음). SkinHue 속성(0~1)로 색 지정.
local function applySolidSkin()
	local hueAttr = Tool:GetAttribute("SkinHue")        -- 0~1 (색상환 위치)
	local satAttr = Tool:GetAttribute("SkinSat")        -- 채도 (검정/흰색은 0)
	local valAttr = Tool:GetAttribute("SkinVal")        -- 명도 (검정은 낮게)
	if hueAttr == nil then return end
	colorRunning = false   -- 무지개와 동시 적용 방지
	local h = hueAttr
	local s = (satAttr ~= nil) and satAttr or 1
	local v = (valAttr ~= nil) and valAttr or 1
	local col = Color3.fromHSV(h, s, v)

	-- 검정 스킨 판별: 채도≈0 + 명도 낮음 → 발광 없는 진짜 검정 + 검은 연기 불꽃
	local isBlack = (s <= 0.02) and (v <= 0.15)

	-- 본체 색칠
	for _, sp in ipairs(skinParts) do
		if sp.part and sp.part.Parent then
			if isBlack then
				-- 검정: Neon(발광) 대신 무광 → 진짜 검정으로 보임
				sp.part.Material = Enum.Material.SmoothPlastic
				sp.part.Color = Color3.fromRGB(15, 15, 15)
			else
				sp.part.Material = Enum.Material.Neon
				sp.part.Color = col
			end
		end
	end

	-- flame tail 색칠
	for _, e in ipairs(flameEmitters) do
		if e and e.Parent then
			local base = flameBaseHSV[e]
			if isBlack then
				-- 검정 불꽃: 색을 진한 검정으로. 투명도는 원래 그라데이션(여러 키포인트)을 유지하며
				-- 각 키포인트에 가산. Beam4(중심 코어)는 가산 0으로 가장 진하게.
				e.Color = ColorSequence.new(Color3.fromRGB(20, 20, 20))
				local addT = (e.Name == "Beam4") and 0 or 0.12
				local newKps = {}
				for _, kp in ipairs(base.origTransparency.Keypoints) do
					table.insert(newKps, NumberSequenceKeypoint.new(kp.Time, math.clamp(kp.Value + addT, 0, 1)))
				end
				e.Transparency = NumberSequence.new(newKps)
			else
				-- 일반 단색: 지정 hue + 각 이펙트 원래 S·V (질감 보존). 흰색(채도0)은 무채색.
				local fs = (s <= 0.02) and 0 or base.s
				e.Color = ColorSequence.new(Color3.fromHSV(h, fs, base.v))
				e.Transparency = base.origTransparency   -- 원래 투명도 복원
			end
		end
	end
end

local function startColorSkin()
	if Tool:GetAttribute("RainbowSkin") then
		startRainbow()
	elseif Tool:GetAttribute("SkinHue") ~= nil then
		applySolidSkin()
	else
		-- 노스킨 프라이밍: 스킨 적용 시엔 Equipped에서 색을 써주는 동작이 flame tail을 미리
		-- 워밍업시켜 첫 슬램에 즉시 나타남. 노스킨은 그 동작이 없어 첫 슬램이 1~2초 지연됨.
		-- → 동일하게 이펙트 속성을 자기 값으로 한 번 써줘서 워밍업 유발.
		for _, e in ipairs(flameEmitters) do
			if e and e.Parent then
				local base = flameBaseHSV[e]
				if base then
					e.Color = base.origColor
					e.Transparency = base.origTransparency
				end
			end
		end
	end
end
local function stopColorSkin()
	colorRunning = false
	restoreBody()
	-- flame tail 색·투명도도 원래대로 복원 (검정 스킨의 그을음/색 잔존 방지)
	for _, e in ipairs(flameEmitters) do
		if e and e.Parent then
			local base = flameBaseHSV[e]
			if base then
				e.Color = base.origColor
				e.Transparency = base.origTransparency
			end
		end
	end
end

-- ── love_effect (핑크 플레임 망치 전용: 몸 부착 + 착지 출력) ──────────
-- 템플릿은 호출 시점에 동적으로 찾음: ServerStorage.LoveEffectTemplate 우선,
-- 없으면 workspace.love_effect 폴백 (저장 누락 등으로 템플릿이 없어도 작동).
local function getLoveTemplate()
	local ss = game:GetService("ServerStorage")
	return ss:FindFirstChild("LoveEffectTemplate") or workspace:FindFirstChild("love_effect")
end
local bodyLovePart = nil   -- 몸에 부착된 love_effect 인스턴스 (정리용)

-- 핑크 스킨일 때 캐릭터 몸(HRP)에 love_effect 상시 부착
-- Char는 이 함수보다 아래(344줄)에서 선언돼 upvalue로 안 잡힘 → 캐릭터를 인자로 받음.
local function attachBodyLove(char)
	if bodyLovePart then return end          -- 이미 붙음
	local LoveTemplate = getLoveTemplate()
	if not LoveTemplate or not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local p = LoveTemplate:Clone()
	p.Anchored = false
	p.CanCollide = false
	p.Transparency = 1
	p.CFrame = hrp.CFrame
	p.Parent = char
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = p
	weld.Parent = p
	bodyLovePart = p
end
local function detachBodyLove()
	if bodyLovePart then bodyLovePart:Destroy(); bodyLovePart = nil end
end

-- 슬램 착지 지점에 love_effect를 한 번에 우수수 터뜨림 (핑크 스킨 전용)
local function burstLoveAt(pos)
	local LoveTemplate = getLoveTemplate()
	if not LoveTemplate then return end
	local p = LoveTemplate:Clone()
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
	-- 착지 분출용 조정: 사방으로 넓게 퍼지며 빠르게 튐.
	-- ⚠️ 서버에서 Emit()은 클라로 복제 안 됨 → Rate를 높여 켜두고 잠깐 뒤 끄는 방식 사용.
	--    (Enabled 속성은 복제되므로 클라 화면에 보임)
	for _, e in ipairs(p:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			e.SpreadAngle = Vector2.new(180, 180)   -- 전방위로 흩뿌림
			e.Speed = NumberRange.new(20, 45)         -- 훨씬 멀리 튀게
			-- 하트(Love)는 크게, 점(Dots)은 약간 작게
			local sizeMul = (e.Name == "Dots") and 0.7 or 1
			e.Size = NumberSequence.new({            -- 피었다 작아지는 형태
				NumberSequenceKeypoint.new(0, 1.5 * sizeMul),
				NumberSequenceKeypoint.new(0.3, 2.5 * sizeMul),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.Rate = 400                              -- 짧은 시간에 우수수 쏟아지게 높임
			e.Enabled = true
		end
	end
	p.Parent = workspace
	-- 잠깐 방출 후 정지 (1회성 폭발 느낌). Enabled는 복제되어 클라에 보임.
	task.delay(0.25, function()
		if p and p.Parent then
			for _, e in ipairs(p:GetDescendants()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
		end
	end)
	game:GetService("Debris"):AddItem(p, 3)
end

-- 슬램 착지 지점에 눈송이를 우수수 (아이스 크러셔 전용). burstLoveAt과 동일 방식(Rate↑ 켰다 끔).
local function burstSnowAt(pos)
	local SnowTemplate = game:GetService("ServerStorage"):FindFirstChild("SnowEffectTemplate")
	if not SnowTemplate then return end
	local p = SnowTemplate:Clone()
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
	for _, e in ipairs(p:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			e.SpreadAngle = Vector2.new(180, 180)
			e.Speed = NumberRange.new(14, 34)
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.0),
				NumberSequenceKeypoint.new(0.3, 1.8),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.Rate = 350
			e.Enabled = true
		end
	end
	p.Parent = workspace
	task.delay(0.25, function()
		if p and p.Parent then
			for _, e in ipairs(p:GetDescendants()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
		end
	end)
	game:GetService("Debris"):AddItem(p, 3)
end
local function startChargeLoop()
	ChargeLoopA:Play()
	ChargeLoopB:Play()
end
local function stopChargeLoop()
	ChargeLoopA:Stop()
	ChargeLoopB:Stop()
end
stopChargeLoop()   -- 시작 시 정지 보장

-- ── 일반 공격 (느리고 강한 단타) ─────────────────────────────
local HIT_DAMAGE   = 33     -- 단발 데미지
-- ⚠️ [밸런스 2026-08-29] 25 → 33, 슬램 45 → 80 (세트). Epic 목표 26 DPS.
--   [계산] 실효 사이클 = 슬램 소요(선딜 0.4 + 비행 0.45) + SLAM_COOLDOWN 6 = 약 6.85초.
--     쿨이 '착지 후' 시작되므로 6초가 아니다(doLeapSlam 끝의 CdUntil 참조).
--     슬램 중에는 Tool.Enabled=false 라 평타가 잠긴다.
--       평타 33/2.0 × (6.0/6.85) = 14.5 DPS
--       슬램 80 / 6.85            = 11.7 DPS   → 합계 26.2
--   ⚠️ SLAM_COOLDOWN 은 올리지 않았다. 에어본 1.2초가 CC 라, 쿨을 내리거나
--     올리면 러너 인원수만큼 곱해지는 CC 총량이 흔들린다.
local ATTACK_CD    = 2.0    -- 공격 쿨다운(초) — 더 묵직
local SWING_TIME   = 0.5    -- 타격 윈도우 지속(초)

-- ── 타겟 조준 슬램 설정 ──────────────────────────────────────
-- 아이콘 클릭 → 화면 터치로 착지점 조준(청사진 경계원) → 떼면 그 지점으로 도약 슬램.
local AIM_RANGE      = 55     -- 조준 가능 최대 사거리(러너 중심 반경, 스터드)
local LEAP_HEIGHT    = 30     -- 도약 정점 높이(시각용 — 포물선 띄움)
local SLAM_RADIUS    = 16     -- 슬램 타격 반경(고정 — 위력 균일)
local WINDUP_TIME    = 1.0    -- 확정 후 도약 전 선딜(차지 모션 — 태거 회피 여지)
-- ⚠️ [밸런스 2026-09-17] 0.4 → 1.0. 회피가 산술적으로 불가능했다.
--   [증상] "해머하이는 사실상 못 피한다" (사용자 제보, 5판 연속).
--   [계산] 반응 창 = WINDUP + 비행 0.45. 킹은 2단계에 감속되어 WalkSpeed 14다
--     (실측 로그: 🐢 태거 2단계 감속 16 → 14).
--       구 0.4: 14 × 0.85 = 11.9 stud  vs  SLAM_RADIUS 16  → 4.1 부족. 반응 0초를 줘도 못 피한다
--       신 1.0: 14 × (1.45 − 0.3) = 16.1 ≥ 16            → 반응 0.3초를 빼고도 성립
--     손익분기는 반응 0.2초 기준 WINDUP 0.89. 1.0 은 0.3초까지 버티는 값이다.
--   [왜 이 값인가 — 다른 축을 기각한 이유]
--     · SLAM_RADIUS 축소: 부등식은 풀리지만 결과가 '킹의 회피'가 아니라 '러너의 빗맞힘'이 된다.
--       킹은 여전히 구경만 하고, 경고원 가독성도 같이 떨어진다.
--     · SLAM_DAMAGE 인하: 부등식에 안 들어간다. "못 피하는 60"이 될 뿐이다.
--     · SLAM_COOLDOWN: 위 주석이 이미 기각했다(인원수만큼 곱해지는 CC 총량이 흔들림).
--   [부작용 — 의도한 대가] 실효 사이클 6.85 → 7.45초.
--       평타 33/2.0 × (6.0/7.45) = 13.3 DPS
--       슬램 80 / 7.45            = 10.7 DPS   → 합계 24.0 (구 26.2, Epic 목표 26)
--     약 8% 하락. 게다가 이제 실제로 회피가 가능하므로 체감 DPS는 더 낮아진다.
--     ⚠️ 데미지로 되돌리지 말 것. 그건 방금 만든 회피 가능성을 도로 지우는 방향이다.
--   ⚠️ 시전자는 선딜 중 '이동이 잠기지 않는다'. 위의 "제자리에서 차지 모션만 재생"은
--     강제하는 코드가 없는 서술이다(WalkSpeed 0 은 맞은 태거에게만 걸린다).
--     착지점이 월드 고정이라 러너가 뛰어도 이득은 없지만, 1.0 초는 0.4 초와 달리
--     "망치 들고 뛰어다니다 갑자기 뒤로 도약"이 눈에 띌 수 있다.
--     연출이 어색하면 시전자 이동 잠금을 별도 변경으로 검토할 것 — 이번 판에 같이 넣지 않는다.
--   ⚠️ 미확인: 슬램 적중 판정이 HRP 거리 기준인지 파트 경계 기준인지 안 봤다.
--     후자라면 KingScale(최대 ×2.5)로 커진 킹은 더 멀리 나가야 해서 위 계산이 낙관적이다.
local SLAM_DAMAGE    = 80     -- 슬램 명중 데미지
-- ⚠️ [밸런스 2026-08-29] 45 → 80. 위 HIT_DAMAGE 25→33 과 한 세트.
--   빗맞힘 자가 스턴을 제거했으므로(아래 참조) 리스크는 '조준 실패 + 쿨 6초 소모'뿐이다.
--   대신 명중 보상을 키워 '한 방이 무겁다'는 정체성을 강화한다.
local SLAM_COOLDOWN  = 6      -- 슬램 후 재사용 쿨다운(초) (8→6)
local STUN_DURATION  = 1.2    -- 명중한 태거 부양 스턴 지속(초)
-- ⚠️ SELF_STUN 제거됨(2026-08-29). 빗맞힘 페널티는 SLAM_COOLDOWN 6초가 대신한다.
local STUN_LIFT      = 55     -- 명중 시 태거가 떠오르는 속도 (에어본 강화)
local SHAKE_TAGGER_INTENSITY = 2.2   -- 맞은 태거 화면 흔들림 강도
local SHAKE_TAGGER_DURATION  = 0.5
local SHAKE_RUNNER_INTENSITY = 1.0   -- 내려찍은 러너 화면 흔들림 강도 (약하게)
local SHAKE_RUNNER_DURATION  = 0.35

local slamming      = false  -- 현재 슬램(도약~착지) 진행 중인가
local slamId        = 0      -- 슬램 세션 ID (중단된 슬램 뒤처리가 새 슬램을 안 망치게)
local indicatorPart = nil    -- 현재 예고 원 Part (정리용)
local savedWalk     = nil

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

-- ── 진영 판정: 러너 무기는 태거만 (아군 러너/봇 오사 차단) ───
local function isTaggerTarget(model, plyr)
	if model == nil then return false end
	local oPlayer = Players:GetPlayerFromCharacter(model)
	if oPlayer then
		return oPlayer ~= plyr and oPlayer:GetAttribute("Role") == "Tagger"
	else
		-- NPC: 러너봇이 아니면 태거 더미로 간주
		if model:GetAttribute("AIRunner") or model:GetAttribute("RunnerBot") then return false end
		if model.Parent and (model.Parent:GetAttribute("AIRunner") or model.Parent:GetAttribute("RunnerBot")) then return false end
		return true
	end
end

-- ── 상태(장착 캐릭터) ────────────────────────────────────────
local Char, Hum, Plyr

-- ── 일반 공격 (타격 윈도우 방식, 저급과 동일) ────────────────
local canDamage    = false
local HIT_COOLDOWN = 0.6
local lastHitTime  = {}
-- 평타 범위 보정: Handle이 0.36×1.9×0.39 막대라 Touched만으로는 망치 머리로 때려도 안 맞음.
-- 스윙 윈도우 동안 캐릭터 앞 영역을 주기 검사해 보완(푸시툴과 동일 방식).
local HITBOX_FORWARD = 2.0                    -- 캐릭터 앞쪽 검사 박스 중심 거리(stud)
local HITBOX_SIZE    = Vector3.new(4, 6, 5)   -- 폭4(±2) 높이6 깊이5 → 정면 도달 4.5stud
local HITBOX_RATE    = 0.06                   -- 검사 간격(초)
local HITBOX_SHOW    = false                   -- [디버그] 히트박스 시각화. 값 확정 후 false로

local function Blow(hit)
	if not hit or not hit.Parent then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	if slamming then return end   -- 슬램 중엔 일반 타격 판정 안 씀(슬램이 따로 판정)
	if not canDamage then return end

	local character = hit.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health == 0 then return end
	if not isTaggerTarget(character, Plyr) then return end

	local now = os.clock()
	local last = lastHitTime[character]
	if last and (now - last) < HIT_COOLDOWN then return end
	lastHitTime[character] = now

	TagHumanoid(humanoid, Plyr or Char)   -- 🏷️ 봇이면 캐릭터 모델
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
	humanoid:TakeDamage(HIT_DAMAGE)
	-- 🔢 [2026-09-06] 데미지 표기 (무기 공용 _G.ShowDamage).
	if _G.ShowDamage and Plyr then
		local root = character:FindFirstChild("HumanoidRootPart")
		_G.ShowDamage(Plyr,
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, HIT_DAMAGE)) or HIT_DAMAGE,
			root and root.Position, false)
	end
	HitSound:Play()
end
-- 스윙 윈도우 동안 앞쪽 영역을 훑어 Blow 판정을 재사용(디바운스·진영체크 그대로 적용)
local function areaHitCheck()
	if not Char or slamming or not canDamage then return end
	local hrp = Char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local center = hrp.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {Char}
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(center, HITBOX_SIZE, params)
	end)
	if not ok or not parts then return end
	local seen = {}
	local half = HITBOX_SIZE * 0.5
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			if model:FindFirstChildOfClass("Humanoid") then
				local thrp = model:FindFirstChild("HumanoidRootPart")
				-- 몸통 중심이 박스 안에 있을 때만 타격.
				-- 파트 하나만 걸쳐도 맞던 문제 차단(상대가 든 무기·액세서리가 박스 끝에 닿는 경우)
				if thrp then
					local rel = center:PointToObjectSpace(thrp.Position)
					if math.abs(rel.X) <= half.X
						and math.abs(rel.Y) <= half.Y
						and math.abs(rel.Z) <= half.Z then
						Blow(thrp)
					end
				end
			end
		end
	end
end
-- [디버그] 히트박스 시각화 (HITBOX_SHOW=false면 생성 안 함)
local function makeHitboxVisual()
	if not HITBOX_SHOW then return nil end
	local p = Instance.new("Part")
	p.Name = "_HammerHitboxDebug"
	p.Size = HITBOX_SIZE
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 0.75
	p.Color = Color3.fromRGB(255, 70, 70)
	p.Material = Enum.Material.Neon
	p.Parent = workspace
	return p
end

-- 스킨별 평타(스윙) 애니: SwingAnim 속성 있으면 커스텀 애니 로드/재생, 없으면 기본 toolanim "Slash".
local swingAnimObj = Instance.new("Animation")
local swingTrack = nil
local swingTrackChar = nil
local function ensureSwingTrack(animId)
	if not Char or not Hum then return nil end
	if swingAnimObj.AnimationId ~= animId then
		swingAnimObj.AnimationId = animId
		swingTrack = nil
	end
	if swingTrack and swingTrackChar == Char then return swingTrack end
	local animator = Hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = Hum
	end
	local ok, track = pcall(function() return animator:LoadAnimation(swingAnimObj) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		swingTrack = track
		swingTrackChar = Char
		return track
	end
	return nil
end
local function playSwing()
	local swingId = Tool:GetAttribute("SwingAnim")
	if swingId and swingId ~= "" then
		local track = ensureSwingTrack(swingId)
		if track then
			track:Stop()
			track:Play(0.1)
			return
		end
	end
	-- 기본: 레거시 toolanim "Slash"
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = Tool
	Debris:AddItem(anim, 0.5)
end

-- ── 슬램 도약 애니메이션 (Hammer Attack) ─────────────────────
local SLAM_ANIM_ID = "rbxassetid://88857110836573"
local slamAnimObj = Instance.new("Animation")
slamAnimObj.AnimationId = SLAM_ANIM_ID
-- 전체 애니 중 이 구간(초)만 재생. 도약 시간에 맞춰 속도 압축됨.
local ANIM_CLIP_START = 4.0
local ANIM_CLIP_END   = 7.0

local slamTrack = nil       -- 미리 로드해 둔 트랙 (캐시)
local slamTrackChar = nil   -- 그 트랙이 어느 캐릭터 것인지 (캐릭터 바뀌면 재로드)

-- 트랙 확보(없거나 캐릭터가 바뀌었으면 로드). 첫 재생 지연 방지를 위해 Equipped에서 미리 호출.
local function ensureSlamTrack()
	if not Char or not Hum then return nil end
	if slamTrack and slamTrackChar == Char then return slamTrack end
	local animator = Hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = Hum
	end
	local ok, track = pcall(function() return animator:LoadAnimation(slamAnimObj) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		slamTrack = track
		slamTrackChar = Char
		return track
	end
	return nil
end

-- ── 무기 감상(inspect) 모션: idle일 때 InspectAnim 애니를 랜덤 재생 ──
local inspectGen = 0        -- 장착 세대 (Unequip 시 증가 → 루프 종료)
local lastActionAt = 0      -- 마지막 공격/차징/슬램 시각 (idle 판정용)
local inspectAnimObj = Instance.new("Animation")
local inspectTrack = nil
local inspectTrackChar = nil
local inspectConn = nil       -- 그립 스핀 Heartbeat
local inspectGrip = nil
local inspectGripBase = nil
local function markAction() lastActionAt = os.clock() end
local function stopGripSpin()
	if inspectConn then inspectConn:Disconnect(); inspectConn = nil end
	if inspectGrip and inspectGripBase and inspectGrip.Parent then
		pcall(function() inspectGrip.C1 = inspectGripBase end)
	end
	inspectGrip = nil; inspectGripBase = nil
end
local function cancelInspect()
	if inspectTrack and inspectTrack.IsPlaying then inspectTrack:Stop(0.15) end
	stopGripSpin()
end
local function ensureInspectTrack(animId)
	if not Char or not Hum then return nil end
	if inspectAnimObj.AnimationId ~= animId then
		inspectAnimObj.AnimationId = animId
		inspectTrack = nil
	end
	if inspectTrack and inspectTrackChar == Char then return inspectTrack end
	local animator = Hum:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = Hum end
	local ok, track = pcall(function() return animator:LoadAnimation(inspectAnimObj) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		inspectTrack = track
		inspectTrackChar = Char
		return track
	end
	return nil
end
-- 그립을 애니 길이 동안 물리적으로 회전 (감상 애니와 동시 재생 → 손목 애니 + 무기 스핀)
local function startGripSpin(duration)
	if not Char then return end
	local hand = Char:FindFirstChild("RightHand") or Char:FindFirstChild("Right Arm")
	local grip = hand and hand:FindFirstChild("RightGrip")
	if not grip or not (grip:IsA("Motor6D") or grip:IsA("Weld")) then return end
	stopGripSpin()
	inspectGrip = grip
	inspectGripBase = grip.C1
	local base = inspectGripBase
	local RunService = game:GetService("RunService")
	local T = duration and duration > 0.3 and duration or 2.6
	local t0 = os.clock()
	inspectConn = RunService.Heartbeat:Connect(function()
		if not grip.Parent or not Char or Tool.Parent ~= Char then stopGripSpin(); return end
		local a = (os.clock() - t0) / T
		if a >= 1 then grip.C1 = base; stopGripSpin(); return end
		local ease = math.sin(a * math.pi)
		local spin = a * math.pi * 2
		grip.C1 = base * CFrame.new(0, ease * -0.25, 0) * CFrame.Angles(math.rad(ease * 14), spin, 0)
	end)
end
local function doInspect()
	local animId = Tool:GetAttribute("InspectAnim")
	if not animId or animId == "" then return end
	local track = ensureInspectTrack(animId)
	if track then
		track:Stop(); track:Play(0.2)
		-- 감상 애니 길이만큼 그립도 함께 회전 (동시 재생)
		local len = track.Length
		if not len or len <= 0 then len = 2.6 end
		startGripSpin(len)
	end
end
-- idle 상태에서 랜덤 간격마다 감상 재생 (장착 중 루프). InspectAnim 있을 때만.
local function startInspectLoop()
	if not Tool:GetAttribute("InspectAnim") then return end
	inspectGen = inspectGen + 1
	local myGen = inspectGen
	task.spawn(function()
		while myGen == inspectGen and Char and Tool.Parent == Char do
			task.wait(math.random(90, 160) / 10)   -- 9~16초 랜덤 간격
			if myGen ~= inspectGen then break end
			if not Char or Tool.Parent ~= Char then break end
			-- idle 판정: 슬램 아니고, 최근 3초 내 액션 없고, 안 움직이고, 감상 중 아님
			local hum = Hum
			local moving = hum and (hum.MoveDirection.Magnitude > 0.1)
			if hum and hum.Health > 0 and not slamming and (os.clock() - lastActionAt > 3) and not moving and not (inspectTrack and inspectTrack.IsPlaying) then
				doInspect()
			end
		end
	end)
end

-- 에셋 강제 다운로드(preload): 무음으로 잠깐 재생했다 즉시 정지 → 캐시에 올림.
local function preloadSlamAnim()
	local track = ensureSlamTrack()
	if not track then return end
	-- 속도 0으로 재생 시작하면 움직임 없이 에셋만 로드됨. 0.05초 뒤 정지.
	track:Play(0)
	track:AdjustSpeed(0)
	task.delay(0.05, function()
		if track and track.IsPlaying then track:Stop(0) end
		if track then track.TimePosition = 0 end
	end)
end

local function playSlamAnim(flightTime)
	local track = ensureSlamTrack()
	if not track then return end
	local clipLen = ANIM_CLIP_END - ANIM_CLIP_START      -- 재생할 구간 길이(초)
	local dur = flightTime or 0.7
	-- 구간(clipLen)을 도약 시간(dur)에 맞춰 압축/확장 → 도약과 애니가 같이 끝남
	local speed = (dur > 0.05) and (clipLen / dur) or 1
	-- 이미 preload돼 있으면 즉시 시작 지점부터 재생 (첫 재생 지연 없음)
	track:Stop(0)
	track.TimePosition = ANIM_CLIP_START
	track:Play(0.05)
	track:AdjustSpeed(speed)
	track.TimePosition = ANIM_CLIP_START   -- Play 후 한 번 더 박아 시작점 보장
	-- 도약 시간만큼 재생 후 정지 (구간 끝 = 7초 지점에서 멈춤)
	task.delay(dur, function()
		if track and track.IsPlaying then track:Stop(0.15) end
	end)
end

local function Activated()
	if slamming then return end   -- 슬램 중 일반 공격 불가
	if not Tool.Enabled then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	markAction()   -- idle 판정용 액션 기록
	if inspectConn then cancelInspect() end   -- 감상 중이면 즉시 중단
	Tool.Enabled = false
	playSwing()
	AttackSound:Play()   -- 일반 공격 사운드
	canDamage = true
	task.delay(SWING_TIME, function() canDamage = false end)
	-- 스윙 윈도우 동안 영역 검사 반복 (Touched는 그대로 병행 — 디바운스가 중복 방지)
	task.spawn(function()
		local t0 = os.clock()
		local vis = makeHitboxVisual()
		while canDamage and (os.clock() - t0) < SWING_TIME do
			areaHitCheck()
			if vis then
				local h = Char and Char:FindFirstChild("HumanoidRootPart")
				if h then vis.CFrame = h.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD) end
			end
			task.wait(HITBOX_RATE)
		end
		if vis then vis:Destroy() end
	end)
	wait(ATTACK_CD)
	Tool.Enabled = true
end

-- ── 예고 원 소환/갱신 (서버 → workspace → 전원 복제) ─────────
-- 차지 비율(0~1)에 따라 착지 지점·반경 표시. 착지 지점 = 러너 정면 LEAP_DIST 만큼 앞.
-- 단, 정면에 성/벽/산(Mountains/Walls/ItemBarrier) 또는 castle 모델이 있으면 그 앞에서 착지점을 잘라냄(맵 이탈 차단).
local BLOCK_GROUPS = { Mountains = true, Walls = true, ItemBarrier = true, TaggerBarrier = true }

-- 🚧 [2026-09-13] 통과 불가 판정을 이름·맵 목록에서 표식으로 뒤집는다.
--   [사고] 성문(Barricades.Barricade)은 콜리전 그룹이 Default 라 BLOCK_GROUPS 넷
--     (Mountains/Walls/ItemBarrier/TaggerBarrier) 중 어디에도 안 걸렸다. 레이캐스트가
--     성문을 통과해서, 히어로봇이 성문 너머 킹을 조준하고 55스터드 도약으로 넘어왔다.
--     성문 붕괴 전이라 태거 HP 재산정이 아직 안 된 상태였고 슬램 80 두 방에 죽었다
--     (실측 2026-09-13 22:38:38 무기지급 → 22:38:49 스턴 → 22:38:51 사망, 성문은 멀쩡).
--   [또 하나] castleFolder 가 "map1 castle" 만 찾았다. map2 의 이름은
--     "map2 castle folder" 라 **map2 에서는 캐슬 판정이 통째로 죽어 있었다.**
--     이번에 문제가 난 판이 전부 map2 였다.
--   [형태] 막을 것에 LeapBlocker 속성을 켠다. 상위 컨테이너에 켜면 하위가 전부 덮이므로
--     라운드마다 재건되는 성문도 자동으로 잡힌다 — BarricadeSystem 을 안 고쳐도 된다.
--     "제외 목록보다 결과 보장" / "이름 목록보다 속성" 과 같은 형태다.
--   ⚠️ 표식이 켜진 곳(2026-09-13 기준): map1.Barricades · map2.Barricades ·
--     map1.map1 castle · map2.map2 castle folder. 새 구조물을 막으려면 속성만 켜면 된다.
--   ⚠️ 이 함수는 ChargeClient 의 같은 판정과 **짝**이다. 한쪽만 고치면 예고 원과
--     실제 착지가 어긋난다. 둘을 같은 편집에서 바꿀 것.
local function hasLeapBlockerTag(inst)
	local cur = inst
	while cur and cur ~= workspace do
		if cur:GetAttribute("LeapBlocker") then return true end
		cur = cur.Parent
	end
	return false
end

-- 맞은 파트가 통과 불가 장애물(벽 그룹 or LeapBlocker 표식)인지
local function isBlocker(inst)
	if not inst then return false end
	local cg = inst.CollisionGroup
	if cg and BLOCK_GROUPS[cg] then return true end
	if hasLeapBlockerTag(inst) then return true end
	return false
end

-- 시작점에서 방향으로 maxDist까지, 장애물에 막히는 첫 지점까지의 거리 반환(안 막히면 maxDist).
-- ⚠️ [미해결 2026-09-13] 성문이 멀쩡한데 봇 슬램이 킹에게 닿는 사고가 있었다.
--   유저·봇 모두 이 함수를 타는데(doLeapSlam → landingPosForTarget) 봇에게만 안 걸렸다.
--   원인 미확정. 봇 쪽은 RunnerBotDriveController 에서 국면 게이트로 막아둔 상태다.
--   [알아둘 것] 로블록스 레이캐스트는 **시작점이 파트 안이면 그 파트를 히트로 주지 않는다.**
--     실측(map2 성문 두께 27.7): 바깥 40 → 적중 / 벽면 앞 2 → 적중 / 안쪽 1 → 성문을 건너뜀.
--     조사를 재개하면 이걸 먼저 배제할 것.
local function clampDistByWalls(startPos, dir, maxDist)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Char }
	local traveled = 0
	local cur = startPos
	-- 장애물이 아닌 것(지형·언덕)에 맞으면 그 지점 살짝 뒤부터 다시 쏴서 장애물만 골라냄.
	for _ = 1, 8 do
		local remain = maxDist - traveled
		if remain <= 0 then break end
		local result = workspace:Raycast(cur, dir * remain, params)
		if not result then return maxDist end   -- 끝까지 막는 것 없음
		if isBlocker(result.Instance) then
			-- 장애물에 막힘 → 장애물 앞 1.5스터드 지점까지만 허용
			local hitDist = traveled + (result.Position - cur).Magnitude
			return math.max(0, hitDist - 1.5)
		end
		-- 장애물이 아닌 것(지형 등)은 통과 취급: 그 지점 0.5 뒤에서 계속
		local stepped = (result.Position - cur).Magnitude + 0.5
		traveled = traveled + stepped
		cur = cur + dir * stepped
	end
	return maxDist
end

-- 클라가 보낸 목표 좌표를 검증해 최종 착지점 반환 (사거리 클램프 + 벽/castle 차단 + 지면 보정).
-- 클라를 신뢰하지 않고 서버가 다시 검증 → 치트/관통 방지.
local function landingPosForTarget(targetPos)
	if not Char or not targetPos then return nil end
	local hrp = Char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- 1) 수평 방향·거리 추출 (러너 중심 기준)
	local flat = (targetPos - hrp.Position) * Vector3.new(1, 0, 1)
	local dist = flat.Magnitude
	local dir = (dist < 0.01) and (hrp.CFrame.LookVector * Vector3.new(1,0,1)).Unit or flat.Unit
	-- 2) 사거리 클램프
	dist = math.min(dist, AIM_RANGE)
	-- 3) 경로상 벽/산/castle에 막히면 그 앞까지로 제한 (맵 이탈 차단)
	dist = clampDistByWalls(hrp.Position, dir, dist)
	-- 4) 착지 후보 지점
	local origin = hrp.Position + dir * dist
	-- 5) 지면에 붙이기 (위에서 아래로 레이캐스트)
	local params = RaycastParams.new()
	-- 🔙 [되돌림 2026-09-19] 같은 날 넣은 "캐릭터 전부 제외"를 되돌렸다.
	--   [넣었던 이유] 경고원이 태거 머리 위에 떠 보였다. 레이가 착지 후보 지점 +50 에서
	--     아래로 쏘는데 그 자리에 태거가 서 있으면 머리에 먼저 맞아 groundY 가
	--     지면이 아니라 머리 높이(약 +5)가 됐다. 순수 표시 문제였다.
	--   [왜 되돌렸나] 같은 시점에 "스킬 맞으니 땅에 박힌다" 제보가 들어와,
	--     게임플레이 회귀를 의심해 안전한 상태로 복귀했다.
	--   🟡 [상태 2026-09-19 — 확정 아님] 되돌린 뒤 증상이 사라졌다(사용자 확인).
	--     ⚠️ 중간에 "되돌려도 여전히 박힌다"는 보고가 한 번 있었으나, 그 사이
	--       **게임플레이 로직은 하나도 바뀌지 않았다**(주석·진단·로비 더미뿐).
	--       그 테스트가 되돌림 적용 전이었을 가능성이 높다.
	--     ⚠️ 그래서 "이 수정이 원인이었다"도 "아니었다"도 단정하지 않는다.
	--   [제보 원문 — 이게 아는 전부다] "업뎃 이후로는 해머하이 스킬 맞으니 땅에 박혀버린다".
	--     상황(라운드인지 훈련장인지, 맞은 쪽이 누구인지)은 **언급되지 않았다.**
	--     ⚠️ 한때 이 자리에 "라운드 중 킹이 히어로봇 슬램에 맞음"이라고 적혀 있었는데
	--       그건 **추론을 사실처럼 적은 것**이었다. 제보에 없는 내용이다. 인용하지 말 것.
	--     [정황] 같은 시각 스크린샷이 로비 훈련장(모래밭·역할선택 UI)이었고,
	--       사라짐을 확인한 테스트도 훈련장이다 — 조건이 같았을 가능성이 있다.
	--   [다시 켜려면] 켠 뒤 훈련장에서 해머하이 슬램을 맞아보고,
	--     박히면 원인 확정 → 도약 목적지에만 HRP 오프셋을 더한다.
	--   [그래서 원인은 아직 모른다] 박히는 건 슬램 피격자 쪽 현상이다.
	--     볼 곳: PlatformStand 해제 경로(oHum.PlatformStand = true 를 누가 되돌리나),
	--     STUN_LIFT 로 띄운 뒤 착지 처리, WalkSpeedManager 의 platformStand 관리.
	--   ⚠️ 이 제외를 다시 켤지는 원인이 밝혀진 뒤에 판단한다. 표시 개선이라
	--     급하지 않고, 지금 켜면 진단에 변수가 하나 더 붙는다.
	params.FilterDescendantsInstances = { Char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- 🎯 [버그 수정 2026-09-18] 시전자만이 아니라 **살아있는 캐릭터 전부**를 제외한다.
	--   [증상] 경고원이 태거 머리 위에 둥둥 떠서 "범위가 실제와 다르다"로 보였다(사용자 제보).
	--   [원인] 예전엔 { Char } 만 제외했다. 레이는 착지 후보 지점 +50 에서 아래로 쏘는데,
	--     그 자리에 태거가 서 있으면 **태거 머리에 먼저 맞아** groundY 가 지면이 아니라
	--     머리 높이(약 지면+5)가 된다. 해머하이는 태거를 조준하는 스킬이라
	--     "착지점 위에 태거가 있다"가 정상 사용이다 — 거의 매번 걸리는 조건이었다.
	--     뭉쳐 있는 아군 봇·러너도 같은 이유로 원을 띄운다.
	--   ⚠️ [판정은 원래 멀쩡했다] doSlamHit 은 XZ 평면 거리만 본다(Y를 0으로 누른다).
	--     그래서 groundY 가 틀려도 '누가 맞는지'는 안 바뀌었다 — 순수 표시 버그다.
	--     ⚠️ 그러므로 여기 고친다고 명중 판정이 달라지지 않는다. 밸런스 변화 없음.
	--     ⚠️ 이 사실 때문에 doSlamHit 에 높이 제한을 **넣으면 안 된다**. 넣으면
	--       '떠 있는 원'을 기준으로 판정하게 되어 없던 불일치가 생긴다.
	--   [왜 콜리전 그룹을 안 쓰나 — 실측 2026-09-18]
	--     캐릭터 HRP/Head = Default, 맵 충돌파트도 Default 가 2682개(전체의 89%)다.
	--     그룹으로 캐릭터를 빼면 지면도 같이 빠져 레이가 허공을 지나고,
	--     아래 폴백(hrp.Y - 3)으로 떨어져 지금보다 나빠진다.
	--   [비용 — 실측] GetChildren() 은 **재귀가 아니다**(최상위 41개). 순회 1회 0.0217ms,
	--     슬램당 2회라 0.043ms = 프레임 예산의 0.26%. 바로 아래 doSlamHit 이 매번
	--     GetDescendants() 를 통째로 도는 것에 비하면 반올림 오차다.
	--   ⚠️ 이름 목록이 아니라 **Humanoid 존재**로 잡는다. 새 봇·NPC 가 추가돼도 자동으로
	--     덮인다 — TaggerSpawnedItem 과 같은 '속성으로 잡기' 형태다.
	local ignore = { Char }
	-- 🔙 [되돌림 2026-09-19] 아래 순회를 껐다. 근거는 위 params 블록 주석 참조.
	--   다시 켤 때는 **도약 목적지에만 HRP 오프셋(약 3)** 을 더한 뒤 켤 것.
	--[[
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			table.insert(ignore, m)
		end
	end
	--]]
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local rayOrigin = origin + Vector3.new(0, 50, 0)
	local result = workspace:Raycast(rayOrigin, Vector3.new(0, -300, 0), params)
	-- 슬램으로 올라가면 안 되는 지점(성 지붕/장식/드래곤/벽 등): 착지 금지 → 슬램으로 못 올라감
	if result and result.Instance then
		local hit = result.Instance
		local BLOCK = { centerpart = true, hammerhigh_safety = true, roof1 = true, roof2 = true, ["back wall_2"] = true }
		if BLOCK[hit.Name]
			or hit:FindFirstAncestor("sun symbol")
			or hit:FindFirstAncestor("skeleton dragon") then
			return nil
		end
	end
	local groundY = result and result.Position.Y or (hrp.Position.Y - 3)
	return Vector3.new(origin.X, groundY + 0.1, origin.Z), SLAM_RADIUS
end

-- 예고원은 이제 클라(ChargeClient)가 청사진 경계원으로 직접 그림 → 서버 예고원 제거.
-- clearIndicator는 도약 시작 시 호출되므로 빈 안전 함수로 유지.
local function clearIndicator()
	if indicatorPart then indicatorPart:Destroy(); indicatorPart = nil end
end

-- 🎯 [2026-09-12] 착지 경고원 — 서버 파트라 전원에게 보인다.
--   [왜] 기존 예고원은 ChargeClient 가 시전자 화면에만 그렸다. 킹은 착지 지점을
--     볼 수단이 아예 없어 "모션도 없이 에어본이 날아온다"가 됐다(사용자 제보).
--     어제 Q그랩에서 세운 원칙과 같다 — 예고·표식·판정은 같은 모양이어야 한다.
--   [반경] SLAM_RADIUS 를 그대로 쓴다. BombSystem 주석의 교훈:
--     "즉사 반경 75인데 경고가 70이라 원 밖 5스터드가 죽는 구간이 있었다 —
--      학습 불가능한 죽음이라 불만으로 직결된다". 경고와 판정은 같은 수여야 한다.
--   [공개 시점] doLeapSlam 이 착지점을 확정한 직후. 반응 창 = WINDUP_TIME + 도약 비행시간.
--   ⚠️ 선딜 뒤 착지점이 재계산되므로 그때 원도 옮긴다(아래 두 번째 호출).
local function showIndicator(pos, radius)
	clearIndicator()
	local p = Instance.new("Part")
	p.Name = "HammerSlamWarning"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.2, radius * 2, radius * 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false      -- 레이캐스트에 안 잡히게 (지면 판정 오염 방지)
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 120, 40)   -- 주황 — 불꽃 꼬리와 같은 계열
	p.Transparency = 0.55
	p.Parent = workspace
	-- 🧹 [2026-09-18] 수명 상한. **정리 경로가 아니라 결과 보장이다.**
	--   [증상] 조준 후 야드를 벗어나면 주황 경고원이 바닥에 영구 잔존(실측 09-18, 2회 재현).
	--   [원인] WeaponTrialSystem 이 d:Destroy() 로 툴을 지우면 **툴 안의 이 스크립트도 같이 죽는다.**
	--     그래서 Tool.Destroying → emergencyMobilityRestore → clearIndicator 가 실행을 못 한다.
	--     같은 실패가 이미 기록돼 있다 — WeaponTrialSystem:72
	--       "툴을 지우면 그 안의 스킬 스크립트도 함께 죽는다 … 실측: 스핀 중 야드 이탈 →
	--        회수 → 8 로 굳음. **복구 로그 없음**"
	--     즉 Destroying/Unequipped/AncestryChanged 어느 훅을 더 걸어도 같은 운명이다.
	--   [규칙] 훅을 늘리는 대신 "이 파트는 N초 뒤 반드시 사라진다"로 뒤집는다.
	--     Debris 는 서비스라 툴과 함께 죽지 않는다 — 스크립트가 어떻게 끝나든 보장된다.
	--   [값] 최대 수명 = 선딜 0.94 + 비행 1.20 = 2.14 에 여유. 정상 경로는 착지 시
	--     clearIndicator 가 먼저 지우므로 이 값이 보이는 일은 없다. 어디까지나 안전망이다.
	--   ⚠️ clearIndicator 를 지우지 말 것. 정상 착지에서 원을 '판정과 같은 순간'에
	--     끄는 건 그쪽이다. 이건 그 경로가 죽었을 때만 작동한다.
	--   ⚠️ 같은 구멍이 다른 무기에도 있다(Gauntlet pathPart 등). 월드에 파트를 만드는
	--     스킬은 전부 이 형태가 필요하다 — 훅이 아니라 수명으로.
	Debris:AddItem(p, 4)
	indicatorPart = p
	return p
end

local function moveIndicator(pos)
	if indicatorPart and indicatorPart.Parent then
		indicatorPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	end
end

-- ── 슬램 착지 파편 효과 (에너지볼 createScorch 기반, 흙색 / 보라 스파크 제외) ──
-- 솟아오른 흙판 + 바깥으로 튀는 물리 파편 + 흙먼지·충격 입자.
local function createSlamScorch(centerPos, parent)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	rp.FilterDescendantsInstances = ignore
	local r = workspace:Raycast(centerPos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rp)
	local sPos   = r and r.Position or centerPos
	local normal = r and r.Normal or Vector3.new(0, 1, 0)
	local groundMat = Enum.Material.Ground
	local groundColor = Color3.fromRGB(102, 72, 45)
	if Tool:GetAttribute("IceGround") then
		groundMat = Enum.Material.Ice
		groundColor = Color3.fromRGB(175, 220, 255)   -- 얼음 청백색
	end

	-- 표면 접평면 기저
	local up2 = math.abs(normal.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local tangent = normal:Cross(up2).Unit
	local bitangent = normal:Cross(tangent).Unit

	-- (A) 솟아오르는 큰 흙판들 (중심 둘러싸고 바깥으로 기울어 들림)
	local slabCount = math.random(7, 11)
	local baseA = math.random() * math.pi * 2
	for i = 1, slabCount do
		local ang = baseA + (i / slabCount) * math.pi * 2 + (math.random() - 0.5) * 0.4
		local dir2d = (tangent * math.cos(ang) + bitangent * math.sin(ang)).Unit
		local dist = math.random(20, 65) / 10
		local w = math.random(30, 70) / 10
		local l = math.random(45, 95) / 10
		local thick = math.random(4, 8) / 10

		local slab = Instance.new("Part")
		slab.Anchored = true; slab.CanCollide = false; slab.CanQuery = false; slab.CanTouch = false
		slab.Material = groundMat
		slab.Color = groundColor
		slab.Size = Vector3.new(w, thick, l)

		local tiltUp = math.rad(math.random(15, 45))
		local liftedY = normal * math.random(8, 22) / 10
		local pos = sPos + dir2d * dist + liftedY
		local faceCF = CFrame.lookAt(pos, pos + dir2d, normal)
		slab.CFrame = faceCF * CFrame.Angles(tiltUp, 0, 0)

		local finalCF = slab.CFrame
		slab.CFrame = finalCF - normal * 3
		slab.Transparency = 1
		local upTI = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(slab, upTI, { CFrame = finalCF, Transparency = 0 }):Play()
		slab.Parent = parent

		task.delay(1.4 + math.random() * 0.6, function()
			if slab.Parent then
				TweenService:Create(slab, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = finalCF - normal * 4, Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(slab, 2.8)
	end

	-- (B) 바깥으로 튀는 물리 파편 조각
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
		shard.Size = Vector3.new(w, math.random(3, 6) / 10, l)
		shard.CFrame = CFrame.new(sPos + dir2d * math.random(10, 30)/10 + normal * 1)
			* CFrame.Angles(math.random()*6, math.random()*6, math.random()*6)
		shard.Parent = parent
		local launch = normal * math.random(22, 40) + dir2d * math.random(8, 18)
		shard.AssemblyLinearVelocity = launch
		shard.AssemblyAngularVelocity = Vector3.new(math.random()*12-6, math.random()*12-6, math.random()*12-6)
		Debris:AddItem(shard, 1.8)
	end

	-- (C) 입자 분출 (흙먼지 + 충격 코어. 보라 에너지 스파크는 제외)
	local emitterPart = Instance.new("Part")
	emitterPart.Size = Vector3.new(0.1, 0.1, 0.1)
	emitterPart.CFrame = CFrame.new(sPos + normal * 0.5)
	emitterPart.Anchored = true; emitterPart.CanCollide = false; emitterPart.CanQuery = false; emitterPart.Transparency = 1
	emitterPart.Parent = parent

	-- 흙먼지: 무겁게 퍼지고 가라앉음 (에너지볼 createScorch 원본 설정)
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

	-- 충격 코어: 중심에서 위로 솟구치는 밝은 흙빛 입자 (보라 대신 흙·황토색)
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.25, 0.45)
	burst.Speed = NumberRange.new(18, 35)
	burst.SpreadAngle = Vector2.new(35, 35)
	burst.Acceleration = Vector3.new(0, 10, 0)
	burst.LightEmission = 0.4
	burst.LightInfluence = 0.5
	burst.Color = ColorSequence.new(Color3.fromRGB(190, 150, 100), Color3.fromRGB(120, 85, 50))
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.4, 4), NumberSequenceKeypoint.new(1, 0) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	burst.Parent = emitterPart
	burst:Emit(14)

	Debris:AddItem(emitterPart, 2)
end

-- ── 슬램 판정 (착지 지점 반경 내 태거) ───────────────────────
local function doSlamHit(landingPos, radius)
	local hitAny = false
	for _, other in ipairs(workspace:GetDescendants()) do
		if other:IsA("Model") and other ~= Char then
			local oHum = other:FindFirstChildOfClass("Humanoid")
			local oRoot = other:FindFirstChild("HumanoidRootPart")
			if oHum and oRoot and oHum.Health > 0 and isTaggerTarget(other, Plyr) then
				local d = (oRoot.Position - landingPos) * Vector3.new(1, 0, 1)
				if d.Magnitude <= radius then
					hitAny = true
					TagHumanoid(oHum, Plyr or Char)   -- 🏷️ 봇이면 캐릭터 모델
					if _G.IsDamageImmune and _G.IsDamageImmune(oHum.Parent) then continue end
					oHum:TakeDamage(SLAM_DAMAGE)
					-- 🔢 슬램은 crit=true (금색·큰 글씨). 스킬 한 방임을 평타와 구분한다.
					if _G.ShowDamage and Plyr then
						_G.ShowDamage(Plyr,
							(_G.DisplayDamage and _G.DisplayDamage(oHum.Parent, SLAM_DAMAGE)) or SLAM_DAMAGE,
							oRoot.Position, true)
					end

					-- 공중 부양(에어본): PlatformStand로 잠깐 물리 자유화 → 위로 강하게 띄움.
					-- 성벽 충돌은 단단하니 옆으로는 안 밀고 위로만(멀리 안 날아감).
					-- 🛡️ [2026-09-02] CC 면역 중이면 부양·스턴을 건너뛴다(TaggerCcGuard).
					--   데미지(SLAM_DAMAGE)는 위에서 이미 들어갔다 — 명중 보상은 남긴다.
					--   ⚠️ 여기서 막아야 한다. 속성만 걸러도 PlatformStand·부양은 그대로 실행된다.
					if not (_G.IsCcImmune and _G.IsCcImmune(other)) then
					-- prevPlatform 스냅샷 제거 — PlatformStand 소유권을 매니저로 넘겼다(아래).
					--   ⚠️ 아래 직접 대입은 남긴다. 부양 속도를 주기 '전에' 물리가 자유화돼야
					--     띄우기가 먹는다. 매니저 등록도 같은 값을 쓰므로 충돌하지 않는다.
					oHum.PlatformStand = true
					oRoot.AssemblyLinearVelocity = Vector3.new(0, STUN_LIFT, 0)
					-- 위 속도를 유지하는 보조 LinearVelocity (한순간만 — 확실히 띄움)
					local lv = Instance.new("LinearVelocity")
					local att = Instance.new("Attachment")
					att.Parent = oRoot
					lv.Attachment0 = att
					lv.MaxForce = math.max(oRoot.AssemblyMass, 1) * 10000   -- 무한 힘 금지(벽 밀착 시 솔버 발산 → 좌표 폭주)
					lv.VectorVelocity = Vector3.new(0, STUN_LIFT, 0)
					lv.Parent = oRoot
					Debris:AddItem(lv, 0.12)
					Debris:AddItem(att, 0.12)

					-- 행동 불가(부양 스턴): 떠 있는 동안 조작 차단
					-- 🏃 [2026-09-12] WalkSpeedManager 로 이관.
					--   [왜] 직접 대입 방식은 슬램이 겹치면 두 번째가 '이미 0 인 값'을
					--     prev 로 저장하고, 나중에 끝나는 쪽이 0 으로 덮어 영구 정지가 됐다
					--     (실측: 히어로 2명이 HammerHigh 를 뽑은 판 — "땅에 박혀 못 나온다").
					--     KatanaSword2 의 [COUNTER-SPEED-LEAK] 도 같은 계열이다.
					--   [해결] 절대값 대신 '배율'을 등록한다. 같은 source 는 갱신이라
					--     슬램이 몇 번 겹쳐도 0 하나이고, 해제하면 원래 값으로 돌아온다.
					--     원본을 누가 아는지 다툴 일이 없다 — 관리자만 안다.
					--   ⚠️ PlatformStand 는 아직 직접 관리한다. 토큰으로 마지막 슬램만
					--     복원하게 해뒀다(아래).
					-- 🏃 [2026-09-13] 이동·점프·PlatformStand·표식을 source 하나로 묶는다.
					--   [이전] WalkSpeed 만 매니저에 있었고 PlatformStand 는 prevPlatform 스냅샷,
					--     종료 시점은 _HammerStunToken 으로 따로 관리했다. 스냅샷은 겹치면 오염되고
					--     (B 슬램이 '이미 true 인 값'을 저장), 토큰은 같은 코드가 KatanaSword2·
					--     TaggerCcGuard 에도 복사돼 세 벌이었다.
					--   ⚠️ source 를 시전자별로 나눈다. 히어로 4체가 동시에 슬램할 수 있는데 키를
					--     합치면 먼저 예약된 만료가 아직 유효한 남의 스턴까지 풀어버린다
					--     (실측 2026-09-13, 카타나에서 0.08초 차 2발 → 둘째가 0.42초 손실).
					--   ⚠️ 만료는 매니저가 소유한다(duration 인자). 여기서 task.delay 를 걸면
					--     라운드 종료·무기 회수로 Tool 이 파괴될 때 콜백이 함께 회수돼
					--     — 실행이 안 되니 에러도 안 남고 — 태거가 누운 채 영구히 남는다.
					--   ⚠️ HammerStunned 를 Humanoid → Character 로 옮겼다. CC 표식 5종 중 이것만
					--     Humanoid 에 붙어 있어서 라운드 정리 그물에 한 번도 안 걸렸다(Stunned 는
					--     RoundSystem·RoundStateResetServer 두 곳이 지운다). 읽는 쪽은
					--     TaggerCcGuard 두 줄이 전부였고 같이 옮겼다.
					local slamSource = "HammerSlam:" .. ((Plyr and Plyr.Name) or (Char and Char.Name) or "?")

					-- 🔬 [진단 2026-09-19] "슬램 맞으면 하반신이 땅에 박힌다" 추적.
					--   ⚠️ 원인 확정 후 이 블록을 통째로 삭제할 것 (SLAM_DIAG 검색).
					--   [가설] 위 09-13 주석이 같은 증상을 기록해뒀다 —
					--     "히어로 2명이 HammerHigh 를 뽑은 판: 땅에 박혀 못 나온다".
					--     그때 원인은 **슬램 겹침** 이었고 WalkSpeedManager 로 옮겨 고쳤다.
					--     오늘 HUNT 기능(여유 히어로가 킹을 쫓음)이 히어로들을 킹에게
					--     모으므로, 겹침이 다시 자주 일어나게 됐을 수 있다.
					--     → 즉 내가 버그를 만든 게 아니라 **도달 가능하게** 만들었을 가능성.
					--   [재는 것] ① 이 피격자에게 동시에 걸린 슬램 수
					--     ② STUN_DURATION 이 끝난 뒤 PlatformStand 가 풀렸는가
					--     ③ 그 시점 HRP.Y 와 지면 Y 의 차 (정상 약 3, 0 이하면 파묻힘)
					--   [판정] 동시 2건 이상인 경우에만 PS 가 안 풀리면 → 겹침이 원인. 확정.
					--     동시 1건에서도 박히면 → 겹침이 아니다. 가설 기각하고 다른 데를 본다.
					local SLAM_DIAG = true
					if SLAM_DIAG then
						_G._SlamDiag = _G._SlamDiag or {}
						local n = (_G._SlamDiag[other] or 0) + 1
						_G._SlamDiag[other] = n
						local t0 = os.clock()
						print(string.format("🔬 [Slam] %s ← %s | 동시 %d건 | PS=%s WS=%.1f",
							other.Name, slamSource, n,
							tostring(oHum.PlatformStand), oHum.WalkSpeed))
						task.delay(STUN_DURATION + 0.6, function()
							_G._SlamDiag[other] = math.max(0, (_G._SlamDiag[other] or 1) - 1)
							if not (other.Parent and oHum.Parent and oRoot.Parent) then return end
							local rp = RaycastParams.new()
							rp.FilterType = Enum.RaycastFilterType.Exclude
							rp.FilterDescendantsInstances = { other }
							local r = workspace:Raycast(oRoot.Position + Vector3.new(0, 6, 0),
								Vector3.new(0, -300, 0), rp)
							local gy = r and r.Position.Y or -999
							local gap = oRoot.Position.Y - gy
							local verdict =
								(oHum.PlatformStand and "🔴 PS 안 풀림")
								or (gap < 2 and "🔴 파묻힘")
								or "정상"
							print(string.format(
								"🔬 [Slam] %s | %.1fs 후 | 동시 %d건 | PS=%s WS=%.1f | HRP.Y %.1f / 지면 %.1f / 차 %.1f | %s",
								other.Name, os.clock() - t0, _G._SlamDiag[other] or 0,
								tostring(oHum.PlatformStand), oHum.WalkSpeed,
								oRoot.Position.Y, gy, gap, verdict))
						end)
					end
					if _G.WalkSpeed then
						_G.WalkSpeed.set(other, slamSource, {
							walk          = 0,
							jump          = 0,
							platformStand = true,
							flags         = { "HammerStunned" },
						}, STUN_DURATION)
					else
						-- 폴백: 관리자가 없으면 기존 방식(겹침 보호 없음)
						oHum.WalkSpeed  = 0
						oHum.JumpHeight = 0
						other:SetAttribute("HammerStunned", true)
						task.delay(STUN_DURATION, function()
							if not (oHum and oHum.Parent) then return end
							oHum.PlatformStand = false
							oHum.WalkSpeed  = 16
							oHum.JumpHeight = 7.2
							other:SetAttribute("HammerStunned", nil)
						end)
					end
					end

					-- 화면 흔들림: 맞은 태거가 플레이어면 그 클라에 신호
					local hitPlayer = Players:GetPlayerFromCharacter(other)
					if hitPlayer then
						ShakeEvent:FireClient(hitPlayer, SHAKE_TAGGER_INTENSITY, SHAKE_TAGGER_DURATION)
					end
				end
			end
		end
	end
	return hitAny
end

-- ── 자가 스턴 (제거됨 2026-08-29) ────────────────────────────
-- 빗맞힘 페널티를 없애면서 selfStun() 함수와 SELF_STUN 상수를 함께 제거했다.
-- ⚠️ 호출부가 사라진 함수를 남겨두면 다음 사람이 "이게 왜 안 불리지" 하고 헤맨다.
--    되살리려면 이 자리에 함수를 복원하고 doLeapSlam 의 else 분기에서 호출할 것.

-- 🎞️ [2026-09-18] 도약 비행시간 — 애니와 도약이 같은 수식을 보게 한다.
--   [증상] 슬램 모션이 어색하다(사용자 제보 09-18).
--   [측정] playSlamAnim 은 받은 시간에 클립 구간을 압축한다(speed = clipLen / dur).
--     클립 구간 3.0초(ANIM_CLIP_START 4.0 → END 7.0).
--     옛 호출은 WINDUP_TIME + **0.6 상수** 였는데, 실제 비행은 0.45~0.80초 가변이다.
--     → 가까이 뛰면 애니가 0.15초 남고, 멀리 뛰면 0.2초 먼저 끝나 마지막 프레임에서 굳는다.
--     미결큐 [연출 시간과 애니 길이는 따로 논다] 와 같은 형태다.
--   [규칙] 수식을 한 곳에만 둔다. 예전엔 도약 블록에만 있어서 애니 쪽이 상수로 근사했고,
--     그게 곧 "같은 규칙이 두 곳에" 였다. 한쪽만 고치면 다시 어긋난다.
--   ⚠️ 이건 연출값이다. 밸런스 상수(WINDUP_TIME · SLAM_DAMAGE · SLAM_RADIUS)는
--     이 수정에서 한 칸도 건드리지 않는다 — 체감만 바꾸고 강약은 그대로 둔다.
local function flightTimeFor(dist)
	local r = math.clamp(dist / AIM_RANGE, 0.15, 1)
	-- ⏱️ [2026-09-18] 0.35 → 0.75. 아래 windupTimeFor 와 **한 짝**이다.
	--   [왜] "뛰기 전에 바닥에서 멈춰 있는 시간이 어색하다"(사용자 제보).
	--     정지 구간을 덜어 비행에 얹는다. 총 예고 시간은 유지한다 —
	--     킹의 반응 창은 '선딜 + 비행' 합계이고, 비행 중에도 경고원은 떠 있다.
	--   ⚠️ 근거리를 같이 늘리면 안 된다. 8 stud 를 0.9초에 가면 둥둥 뜬다.
	--     그래서 상수(0.45)는 그대로 두고 거리 비례항(r)만 키웠다 — 근거리 스냅 유지.
	return 0.45 + 0.75 * r
end

-- ⏱️ [2026-09-18] 선딜도 거리에 비례시킨다. flightTimeFor 와 **한 짝** — 둘이 총량을 나눠 갖는다.
--   [제약] 09-17 주석이 정한 하한을 깬다: "반응 창 = WINDUP + 비행, 킹 WalkSpeed 14,
--     반경 16, 반응 0.3초 공제" → 14 × (총량 − 0.3) ≥ 16 → **총량 ≥ 1.45**.
--     최악 조건은 비행이 가장 짧은 **근거리**다. 그래서 근거리 선딜은 못 줄인다.
--   [해법] 줄일 수 있는 건 원거리뿐이다. 비행이 길어 정지를 흡수할 여유가 거기 있다.
--       거리  8   선딜 0.94 + 비행 0.56 = 1.50   14×1.20 = 16.8 ≥ 16 ✅  (옛 1.50 → 동일)
--       거리 28   선딜 0.80 + 비행 0.83 = 1.63   14×1.33 = 18.6 ✅       (옛 1.63 → 동일)
--       거리 55   선딜 0.60 + 비행 1.20 = 1.80   14×1.50 = 21.0 ✅       (옛 1.80 → 동일)
--     총량은 세 구간 다 그대로고 **정지 시간만 최대 40% 줄었다.**
--   [연출] 멀리 뛸 땐 짧게 웅크려 길게 날고, 가까이는 꾹 눌렀다 짧게 튄다.
--   ⚠️ WINDUP_TIME 상수는 '근거리 최대값'의 뜻으로 남긴다. 그 값을 만지면
--     위 표가 통째로 움직이므로 09-17 계산(총량 ≥ 1.45)을 다시 검산할 것.
--   ⚠️ 반경(SLAM_RADIUS 16)이나 킹 이속(14)이 바뀌면 하한 1.45 도 바뀐다.
local function windupTimeFor(dist)
	local r = math.clamp(dist / AIM_RANGE, 0.15, 1)
	return WINDUP_TIME - 0.40 * r
end

-- 🔬 [진단 2026-09-18] 봇 슬램 이동 추적 — **검증 완료, 기본 OFF.**
--   [결과] 9건 전부 정상이었다. 실제이동 ≈ 거리(18.4/19, 43.1/44, 54.2/55),
--     PS유지 true, 도달 좌표가 목표와 1 stud 이내, 프레임 53~94.
--     "봇은 안 날아가고 스킬만 간다"는 제보는 재현되지 않았다 — 가설 기각.
--   [남겨두는 이유] 같은 의심이 또 오면 한 줄로 되살려 판정할 수 있다.
--     블록 자체는 SLAM_DIAG 가 false 면 비용이 사실상 0 이다(분기 두 개).
--   ⚠️ 다시 켤 일: 슬램이 '제자리에서 터진다'는 제보. 프레임/실제이동/PS유지 세 값이면 갈린다.
local SLAM_DIAG = false

-- ── 도약 + 착지 ──────────────────────────────────────────────
local function doLeapSlam(targetPos)
	if slamming then return end
	-- 쿨다운: 플레이어 속성으로 (무기 내렸다 들어도 우회 불가)
	-- 🤖 [2026-09-12] 봇은 Player 가 없으므로 캐릭터 속성에 같은 키로 박는다.
	--   ⚠️ Plyr 가드 안에만 두면 봇은 쿨다운이 없어 매 틱 슬램이 가능해진다.
	local cdHolder = Plyr or Char
	if cdHolder then
		local cdUntil = cdHolder:GetAttribute("HammerSlamCdUntil") or 0
		if os.clock() < cdUntil then
			-- 📣 [2026-09-18] 거부를 클라에 알린다. 예전엔 조용히 return 이었다.
			--   [증상] "첫 번째 누르면 안 되고 두 번째 눌러야 된다"(사용자 제보 09-18).
			--   [원인] 클라는 confirmAim 에서 onCooldown/isSlamming 을 켜고 slamEnded 를 기다린다.
			--     서버가 말없이 return 하면 그 신호가 영영 안 와서, 클라 자체 4초 안전장치가
			--     풀어줄 때까지 버튼이 죽는다. 그 4초가 지난 뒤 누른 게 "두 번째"다.
			--   [왜 쿨이 남아 있었나] 슬램 시작 시 now + SLAM_COOLDOWN + 2 를 **플레이어 속성**에
			--     선반영하는데, 도중에 툴이 파괴되면(회수·라운드 종료) 그 8초가 그대로 남는다.
			--     새 툴은 신품이어도 이 속성을 읽으므로 거부된다.
			--   ⚠️ 쿨다운 자체는 안 푼다. "무기 내렸다 들어서 쿨 스킵"을 막는 값이라
			--     여기서 0 으로 만들면 어뷰징이 열린다. 알리기만 한다.
			if Plyr then SlamRemote:FireClient(Plyr, "cancel") end
			return
		end
	end
	if not Char or not Hum or Hum.Health <= 0 then return end
	local hrp = Char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local landingPos, radius = landingPosForTarget(targetPos)
	-- ⚠️ 봇은 Plyr 가 nil 이다. FireClient 에 nil 을 넘기면 에러가 나고
	--   그 줄에서 스크립트가 죽어 아래가 통째로 안 돈다.
	if not landingPos then
		if Plyr then SlamRemote:FireClient(Plyr, "cancel") end
		return
	end

	slamming = true
	markAction()   -- idle 판정용 (슬램 후 바로 감상 안 뜨게)
	if inspectConn then cancelInspect() end
	slamId = slamId + 1
	local mySlamId = slamId
	-- 쿨다운 시각 선반영 (도약 도중 무기 내려도 유지)
	if cdHolder then
		cdHolder:SetAttribute("HammerSlamCdUntil", os.clock() + SLAM_COOLDOWN + 2)
	end
	Tool.Enabled = false
	-- 🎯 착지 경고원 공개. 여기가 착지점이 확정된 첫 시점이다.
	--   ⚠️ 예전엔 여기서 clearIndicator() 를 불렀다(클라 예고원 정리용).
	--     이제는 서버 원을 띄우는 자리로 바꾼다 — 정리는 착지/취소 시점에 한다.
	showIndicator(landingPos, radius)

	-- 🎞️ [2026-09-18] 선딜·비행 둘 다 거리에서 뽑는다(flightTimeFor / windupTimeFor 참조).
	--   ⚠️ 여기서는 선딜 '전'의 landingPos 를 쓴다. 선딜 뒤 재계산으로 비행이 조금
	--     달라질 수 있지만 애니는 이미 재생 중이라 되돌릴 수 없다. 요점은 정확한
	--     예측이 아니라 도약 블록과 **같은 수식**을 본다는 것이다 — 상수보다 항상 가깝다.
	--   ⚠️ 선딜은 추정이 아니라 확정이다. 아래 task.wait 와 띄움 지속이 같은 변수를 쓴다.
	--     여기서 WINDUP_TIME 을 직접 쓰면 셋이 서로 어긋난다 — 한 변수로 묶는다.
	local preDist   = ((landingPos - hrp.Position) * Vector3.new(1, 0, 1)).Magnitude
	local preWindup = windupTimeFor(preDist)
	local preFlight = flightTimeFor(preDist)

	-- ── 선딜(차지 모션): 도약 전 잠깐 정지 → 태거가 피할 여지 ──
	-- 제자리에서 차지 모션만 재생, 끝나면 도약 시작.
	-- (flame tail은 조준 시작 시 이미 ON 상태 유지)
	-- 🛬 [2026-09-18] 띄움을 선딜 내내 유지한다. 예전엔 0.12초 임펄스뿐이었다.
	--   [증상] 시전 첫 모션에서 하반신이 지면에 파묻혀 안 보인다(사용자 제보 09-18).
	--   [측정] 중력 196.2 기준 옛 임펄스의 총 체공은 0.36초다
	--     (강제속도 0.12s 로 1.92 상승 → 관성 정점 2.57 → 낙하 0.16s).
	--     그런데 선딜은 0.60~0.94초다 → **0.24~0.58초를 바닥에 붙은 채** 보낸다.
	--     그 구간에서 애니가 다리를 내리면 하반신이 지면 아래로 들어간다.
	--   [왜 이제 드러났나] 09-17 에 선딜을 0.4 → 1.0 으로 올리면서 생긴 격차다.
	--     0.4 일 땐 0.36초 띄움이 거의 다 덮었다. 밸런스 변경이 연출 구멍을 연 사례다.
	--   [해결] 상승은 그대로 두고(1.92 stud — 기존에 검증된 높이), 상승이 끝나면
	--     속도를 0 으로 바꿔 그 높이에 머문다. MaxForce Y 가 중력을 상쇄한다.
	--   ⚠️ 클램프가 아니라 물리라서 애니와 싸우지 않는다 — 원 주석의 "떨림 없음"을 유지한다.
	--   ⚠️ 지속을 preWindup 에 묶는다. 선딜 길이가 거리마다 다르므로 상수로 두면 또 어긋난다.
	--   ⚠️ 제거는 Debris 가 맡는다. 아래 task.delay 가 툴 파괴로 회수돼도
	--     Debris 는 서비스라 살아남아 반드시 지운다 — 영구 부양이 안 생긴다.
	do
		local LIFT_RISE, LIFT_RISE_TIME = 16, 0.12
		local lift = Instance.new("BodyVelocity")
		lift.MaxForce = Vector3.new(0, math.huge, 0)   -- 위쪽만
		lift.Velocity = Vector3.new(0, LIFT_RISE, 0)   -- 상승 구간
		lift.P = 3000
		lift.Parent = hrp
		task.delay(LIFT_RISE_TIME, function()
			if lift.Parent then lift.Velocity = Vector3.new(0, 0, 0) end   -- 그 높이에서 정지
		end)
		Debris:AddItem(lift, preWindup)   -- 선딜이 끝나면 도약 블록이 이어받는다
	end

	playSlamAnim(preWindup + preFlight)   -- 애니를 선딜~도약에 걸쳐 재생
	task.wait(preWindup)

	if mySlamId ~= slamId or not Char or not Hum or Hum.Health <= 0 then
		clearIndicator()
		setFlameTail(false); stopChargeLoop(); slamming = false; Tool.Enabled = true; return
	end
	-- 선딜 중 러너가 이동했을 수 있으니 착지점 재계산(현재 위치 기준)
	landingPos, radius = landingPosForTarget(targetPos)
	if not landingPos then
		clearIndicator()
		setFlameTail(false); stopChargeLoop(); slamming = false; Tool.Enabled = true
		if cdHolder then cdHolder:SetAttribute("HammerSlamCdUntil", 0) end   -- 미발동이므로 쿨다운 리셋
		if Plyr then SlamRemote:FireClient(Plyr, "cancel") end
		return
	end
	-- 🎯 재계산된 착지점으로 경고원을 옮긴다. 안 옮기면 원과 실제 착지가 어긋나
	--   "원 밖인데 맞았다"가 된다 — BombSystem 주석이 경고한 그 상황이다.
	moveIndicator(landingPos)

	stopChargeLoop()   -- 발사 순간 차징 루프 사운드 끊김
	LeapSound:Play()   -- 슬램 출발(날아가기 시작) 사운드

	-- ── 제어된 포물선 도약 ───────────────────────────────────
	-- 물리(LinearVelocity+중력)에 방치하면 지형/충돌로 튕기고 예고 지점에 못 감.
	-- 대신 비행 내내 CFrame을 직접 보간: 수평은 시작→착지 선형, 수직은 sin 포물선.
	-- 회전은 시작 시점의 바라보던 방향으로 고정 → 뱅뱅 도는 현상 제거.
	local hrp2 = Char:FindFirstChild("HumanoidRootPart")
	if not hrp2 then setFlameTail(false); stopChargeLoop(); slamming = false; Tool.Enabled = true; return end
	local startPos = hrp2.Position
	-- 착지 목표는 러너 발 기준(landingPos는 지면 높이) → HRP 중심 높이로 보정(+3)
	local endPos = Vector3.new(landingPos.X, landingPos.Y + 3, landingPos.Z)
	-- 이동 방향으로 회전 고정 (이동 방향 = 착지 방향)
	local faceDir = ((endPos - startPos) * Vector3.new(1, 0, 1))
	if faceDir.Magnitude < 0.01 then faceDir = hrp2.CFrame.LookVector * Vector3.new(1,0,1) end
	faceDir = (faceDir.Magnitude < 0.01) and Vector3.new(0,0,-1) or faceDir.Unit
	local lockedRot = CFrame.lookAt(Vector3.new(), faceDir)   -- 회전만 추출용

	-- 아치 높이: 실제 도약 수평거리에 비례(가까우면 아치도 낮춤 → 제자리 솟구침 방지)
	local actualDist = ((endPos - startPos) * Vector3.new(1, 0, 1)).Magnitude
	local distRatio = math.clamp(actualDist / AIM_RANGE, 0.15, 1)
	local arcHeight = LEAP_HEIGHT * distRatio
	local flightTime = flightTimeFor(actualDist)   -- ⚠️ 애니도 같은 함수를 본다(위 호출부)

	-- 물리 간섭 제거: PlatformStand로 휴머노이드 물리 정지, AutoRotate off
	local prevPlatform = Hum.PlatformStand
	local prevAutoRot = Hum.AutoRotate
	Hum.AutoRotate = false
	Hum.PlatformStand = true
	-- 네트워크 소유권을 서버로 (클라 물리가 서버 CFrame 제어를 덮어쓰지 않게)
	pcall(function() hrp:SetNetworkOwner(nil) end)
	hrp.AssemblyLinearVelocity = Vector3.new()
	hrp.AssemblyAngularVelocity = Vector3.new()

	-- 🔬 [진단 2026-09-18] "봇은 안 날아가고 스킬만 간다" 추적.
	--   [왜 계측부터인가] 가설 두 개가 이미 기각됐다 — RAGDOLL_MAX 3.0 > 비행 1.20 이라
	--     '비행 중 강제 기립'이 아니고, 봇 주행 루프도 PlatformStand 를 존중한다.
	--     코드만 봐선 안 보인다. 09-11 에 원인을 세 번 단정해 세 번 틀린 형태라 관측을 먼저 붙인다.
	--   [읽는 법]
	--     프레임 0            보간 루프가 한 번도 안 돌았다 (while 조건 / 조기 break)
	--     프레임>0 · 이동≈0   매 프레임 누가 되돌린다 (CFrame 경쟁)
	--     PS유지 false        비행 중 누가 PlatformStand 를 껐다
	--     이동≈거리           이동은 정상 — 증상은 '연출이 안 보인다' 쪽이 된다
	--   ⚠️ 착지 스냅(CFrame = endPos) **전에** 재야 한다. 스냅 뒤엔 항상 도착해 보인다.
	--   ⚠️ 유저도 같이 찍는다. 봇만 찍으면 "봇이 특이한가"를 비교할 기준이 없다.
	local diagFrames, diagPsHeld = 0, true
	task.spawn(function()
		local t0 = os.clock()
		while slamming and mySlamId == slamId do
			if not Char or not Hum or Hum.Health <= 0 then break end
			local rootNow = Char:FindFirstChild("HumanoidRootPart")
			if not rootNow then break end
			local a = (os.clock() - t0) / flightTime   -- 0~1 진행도
			if a >= 1 then break end
			-- 수평: 선형 보간 / 수직: 시작·끝 높이 선형 + sin 포물선 아치
			local flat = startPos:Lerp(endPos, a)
			local y = startPos.Y + (endPos.Y - startPos.Y) * a + math.sin(a * math.pi) * arcHeight
			local pos = Vector3.new(flat.X, y, flat.Z)
			-- 위치 + 고정 회전 (뱅뱅 안 돔). 매 프레임 속도도 0으로 눌러 물리 튕김 방지.
			rootNow.CFrame = CFrame.new(pos) * lockedRot
			rootNow.AssemblyLinearVelocity = Vector3.new()
			rootNow.AssemblyAngularVelocity = Vector3.new()
			if SLAM_DIAG then
				diagFrames = diagFrames + 1
				if not Hum.PlatformStand then diagPsHeld = false end
			end
			task.wait()
		end
		if mySlamId ~= slamId then return end   -- 중단된 슬램이면 정리 안 함

		-- 착지 확정: 정확히 예고 지점에 안착
		local rootNow = Char and Char:FindFirstChild("HumanoidRootPart")
		if SLAM_DIAG then
			local at = (rootNow and rootNow.Position) or startPos
			warn(string.format(
				"🔬 [Slam] %s | 거리 %.0f | 비행 %.2fs | 프레임 %d | PS유지 %s | 실제이동 %.1f | 시작(%.0f,%.0f) → 목표(%.0f,%.0f) 도달(%.0f,%.0f)",
				(Plyr and Plyr.Name) or (Char and Char.Name) or "?",
				actualDist, flightTime, diagFrames, tostring(diagPsHeld),
				((at - startPos) * Vector3.new(1, 0, 1)).Magnitude,
				startPos.X, startPos.Z, endPos.X, endPos.Z, at.X, at.Z))
		end
		if rootNow then
			rootNow.CFrame = CFrame.new(endPos) * lockedRot
			rootNow.AssemblyLinearVelocity = Vector3.new()
		end
		-- 물리 복원
		if Hum and Hum.Parent then
			Hum.PlatformStand = prevPlatform
			Hum.AutoRotate = prevAutoRot
		end
		-- 네트워크 소유권 클라(자동)로 복원
		if rootNow then
			pcall(function() rootNow:SetNetworkOwnershipAuto() end)
		end

		setFlameTail(false)   -- 착지 → 추진 종료, flame tail OFF
		clearIndicator()      -- 🎯 착지 = 예고 종료. 판정과 같은 순간에 지운다.
		LandSound:Play()   -- 예고원 도착(착지) 사운드 — 명중 여부 무관
		createSlamScorch(landingPos, workspace)   -- 착지 지점 파편/균열 효과
		if Tool:GetAttribute("LoveEffect") then
			burstLoveAt(landingPos)   -- 핑크 스킨: 착지 지점에 love_effect 출력
		end
		if Tool:GetAttribute("SnowEffect") then
			burstSnowAt(landingPos)   -- 아이스 크러셔: 착지 지점에 눈송이 출력
		end
		local hit = doSlamHit(landingPos, radius)   -- 예고 지점(지면) 기준 판정
		if hit then
			SlamHitSound:Play()   -- 슬램 적중 사운드
			-- 명중: 내려찍은 러너 본인 화면도 흔들림(약하게)
			if Plyr then
				ShakeEvent:FireClient(Plyr, SHAKE_RUNNER_INTENSITY, SHAKE_RUNNER_DURATION)
			end
		else
			-- 🔨 [밸런스 2026-08-29] 빗맞힘 자가 스턴(1.5초) 제거.
			--   [왜] 페널티의 목적은 '쿨만으로 남용을 못 막을 때' 억제하는 것인데,
			--     SLAM_COOLDOWN 6초면 2단계(20~40초) 동안 3~6회뿐이라 이미 충분히 억제된다.
			--   [실제 손실] 빗맞히면 쿨 6초 + 원하던 위치를 못 잡음 + 착지점 노출.
			--     실패 자체가 이미 벌이라 스턴은 이중 처벌이었다.
			--   ⚠️ 결정적 이유: 킹 평타 쿨이 1초라 러너는 이미 상시 넉백에 밀린다.
			--     거기에 1.5초 자가 스턴이 겹치면 그동안 1~2회 더 밀리고 무방비로 얻어맞는다.
			--     실제 손실이 1.5초가 아니라 '그 사이 받는 피해'까지였다.
			--   ⚠️ Gauntlet 의 WALL_STUN 은 남긴다 — 그건 실패 페널티가 아니라
			--     '벽 보너스를 노리다 자기가 박은' 물리적 결과이고, 보상과 위험이 같은 조건이다.
		end

		slamming = false
		Tool.Enabled = true
		if cdHolder then
			cdHolder:SetAttribute("HammerSlamCdUntil", os.clock() + SLAM_COOLDOWN)
		end
		if Plyr then
			SlamRemote:FireClient(Plyr, "slamEnded")  -- 클라 쿨다운 카운트 + 백팩 복원
		end
	end)
end

-- 🤖 [③ 2026-09-12] 봇 전용 진입점. 이름 규약은 "BotSkill".
--   [좌표] 유저는 마우스로 조준하지만 봇은 표적 위치를 직접 안다 —
--     오히려 더 쉽다. 가장 가까운 태거의 HumanoidRootPart 를 목표로 삼는다.
--   ⚠️ 사거리·벽·castle 검증은 landingPosForTarget 이 한다. 여기서 다시 안 본다.
--
-- 🔥 [예고 2026-09-12] 조준 단계를 흉내낸다.
--   [왜] 유저 경로는 aimStart(불꽃 꼬리 ON + 차징음) → 조준 → slam 이다.
--     봇이 doLeapSlam 을 즉시 부르면 예고가 통째로 빠져,
--     "모션도 없이 즉시 에어본이 날아온다"가 된다(사용자 제보).
--     WINDUP_TIME 0.4 는 도약 '직전' 선딜이라 그것만으로는 읽을 시간이 안 된다.
--   [값] BOT_AIM_TIME 0.8 — 유저가 아이콘을 누르고 지점을 고르는 데 걸리는 시간에 해당한다.
--     총 예고 = 0.8(조준) + 0.4(선딜) = 1.2초. 킹이 반응할 창이 생긴다.
--   ⚠️ 조준 중에 대상이 움직이면 doLeapSlam 이 착지점을 재계산한다 —
--     좌표를 지금 고정하지 않고 '대상'을 넘겨 그때 다시 읽는다.
local BOT_AIM_TIME = 0.8

local function botFindTaggerRoot()
	if not Char then return nil end
	local myRoot = Char:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end
	local best, bestD = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= Plyr and plr:GetAttribute("Role") == "Tagger" and plr.Character then
			local r = plr.Character:FindFirstChild("HumanoidRootPart")
			local h = plr.Character:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 then
				local d = (r.Position - myRoot.Position).Magnitude
				if d < bestD then best, bestD = r, d end
			end
		end
	end
	-- NPC 태거(봇 킹·훈련 더미): 플레이어가 아니고 러너봇도 아니면 태거로 간주.
	--   ⚠️ HammerLow:238 이 쓰는 규약을 그대로 따른다. "TaggerBot" 같은 속성은 없다 —
	--     확인 없이 새 속성 이름을 지어내면 영원히 false 인 죽은 코드가 된다.
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m ~= Char and not Players:GetPlayerFromCharacter(m)
			and not (m:GetAttribute("AIRunner") or m:GetAttribute("RunnerBot")) then
			local h = m:FindFirstChildOfClass("Humanoid")
			local r = m:FindFirstChild("HumanoidRootPart")
			if h and r and h.Health > 0 then
				local d = (r.Position - myRoot.Position).Magnitude
				if d < bestD then best, bestD = r, d end
			end
		end
	end
	return best
end

-- 🚪 [기각 2026-09-13] "공성 중(성문 붕괴 전) 러너 스킬 봉인" — 넣었다가 되돌렸다.
--   [왜 떠올랐나] 성문이 6칸 남은 상태에서 슬램이 킹에게 닿아 죽였다(실측 23:37:50~54).
--     태거 쪽에 같은 시기 봉인이 있어(Stage2TriggerSystem:325 / TaggerBotSystem:1331)
--     "서로 직접 때릴 수 없어야 한다"는 주석을 대칭 규칙으로 읽었다.
--   [왜 틀렸나] 두 쪽은 근거가 다르다. 태거는 **무기를 받는 시점 자체가 성문 붕괴**라
--     결투 수단이 아직 없는 국면이고, 봉인 이유도 "공성 전 슬랩으로 밀치는 이기적 플레이"
--     차단이었다. 러너는 2단계 진입에 이미 무기를 받는다 —
--     **무기는 줘놓고 스킬만 빼면 그게 더 이상한 상태**이고,
--     곡사포·마법책을 회피하는 응용이라는 용도도 있다.
--   ⚠️ 다시 제안하지 말 것. 성문 너머 명중은 국면 문제가 아니라 **조준·착지 검증 문제**다.
--     (clampDistByWalls 가 봇 경로에서 안 걸리는 것 — 그쪽을 고쳐야 한다)

local botAiming = false
local botSkill = Instance.new("BindableFunction")
botSkill.Name = "BotSkill"
botSkill.OnInvoke = function()
	if slamming or botAiming then return true end   -- 진행 중 = 스킬 사용 중
	if not Char or not Hum or Hum.Health <= 0 then return false end
	-- 쿨 확인을 조준 '전'에 한다. 예고만 내고 못 뛰면 그게 더 이상하다.
	local cdHolder = Plyr or Char
	if cdHolder and os.clock() < (cdHolder:GetAttribute("HammerSlamCdUntil") or 0) then
		return false
	end
	local tgtRoot = botFindTaggerRoot()
	if not tgtRoot then return false end

	botAiming = true
	-- 유저의 aimStart 와 같은 연출 — 불꽃 꼬리 + 차징 루프음
	setFlameTail(true)
	startChargeLoop()
	task.delay(BOT_AIM_TIME, function()
		botAiming = false
		if not (Char and Hum and Hum.Health > 0) then
			setFlameTail(false); stopChargeLoop(); return
		end
		-- ⚠️ 조준 중 대상이 죽거나 사라졌을 수 있다. 지금 다시 읽는다.
		if not (tgtRoot and tgtRoot.Parent) then
			setFlameTail(false); stopChargeLoop(); return
		end
		doLeapSlam(tgtRoot.Position)
	end)
	return true
end
botSkill.Parent = Tool

-- 🎯 [2026-09-12] 원거리 스킬 표식. RunnerBotDriveController 가 이 값을 읽어
--   접촉 사거리 밖에서도 BotSkill 을 부른다.
--   [값] AIM_RANGE 와 같게 둔다 — 유저가 조준 가능한 거리와 같아야 공평하다.
--   ⚠️ 속성이 없으면 접촉 사거리 안에서만 쓴다(제자리 스킬의 기본값).
--     스핀·카운터는 제자리 기술이라 일부러 안 둔다.
--   ⚠️ 실제 착지 가능 여부는 landingPosForTarget 이 판단한다. 여기는 '시도 조건'일 뿐이다.
Tool:SetAttribute("SkillRange", AIM_RANGE)

-- ── 클라 입력 수신 ───────────────────────────────────────────
-- 클라가 조준 확정 시 착지 목표 좌표를 보냄. 서버가 검증(사거리·벽·castle) 후 도약.
SlamRemote.OnServerEvent:Connect(function(player, action, payload)
	if player ~= Plyr then return end
	if action == "aimStart" then
		-- 슬램 버튼 누른 순간(조준 시작) → flame tail ON + 차징 루프 사운드 시작
		if slamming then return end
		setFlameTail(true)
		startChargeLoop()
	elseif action == "aimCancel" then
		-- 조준만 하고 취소 → flame tail OFF + 사운드 정지
		if slamming then return end
		setFlameTail(false)
		stopChargeLoop()
	elseif action == "slam" then
		if slamming then return end
		if typeof(payload) ~= "Vector3" then return end   -- 좌표만 허용
		doLeapSlam(payload)
	end
end)

-- ── 스킨 적용 (저급 망치와 동일 규칙, 슬램용으로 유지) ────────
local function applySkin()
	local auraName = Tool:GetAttribute("AuraParticle")
	if auraName and not Handle:FindFirstChild("_auraParticle") then
		local aTmpl = ServerStorage:FindFirstChild(auraName)
		if aTmpl and aTmpl:IsA("ParticleEmitter") then
			local p = aTmpl:Clone()
			p.Name = "_auraParticle"
			p.Parent = Handle
		end
	end
	if Tool:GetAttribute("RainbowSkin") then return end
	local skinColor = Tool:GetAttribute("SkinColor")
	if skinColor then
		local mesh = Handle:FindFirstChildOfClass("SpecialMesh")
		local matName = Tool:GetAttribute("SkinMaterial") or "Neon"
		Handle.Material = Enum.Material[matName] or Enum.Material.Neon
		if Tool:GetAttribute("KeepTexture") then
			if mesh then mesh.VertexColor = Vector3.new(skinColor.R, skinColor.G, skinColor.B) end
			Handle.Color = skinColor
		else
			if mesh then mesh.TextureId = "" end
			Handle.Color = skinColor
		end
	end
end

local function Equipped()
	Char = Tool.Parent
	Hum  = Char:FindFirstChildOfClass("Humanoid")
	Plyr = Players:GetPlayerFromCharacter(Char)
	-- ★ 재장착 시 이전 시전 상태 완전 초기화.
	-- 슬램 중 수동으로 무기를 내리면 Unequipped가 'if slamming then return'으로 조기 종료해
	-- slamming=true / Tool.Enabled=false 가 고착된다. 다시 장착하면 Activated의
	-- 'if slamming then return'에 막혀 스킬은커녕 공격 입력이 씹혀 평타만 나갔다.
	-- 새로 장착했다는 건 이전 슬램이 끝났다는 뜻이므로 여기서 무조건 리셋한다.
	if slamming then
		slamming = false
		slamId = (slamId or 0) + 1   -- 진행 중이던 슬램 시퀀스 무효화
		pcall(function() if Hum then Hum.WalkSpeed = 16; Hum.JumpPower = 50; Hum.PlatformStand = false end end)
	end
	Tool.Enabled = true
	canDamage = false
	applySkin()
	startColorSkin()   -- 색 스킨 시작 (무지개 순환 또는 단색)
	startInspectLoop()  -- 무기 감상 모션 랜덤 재생 루프 (InspectAnim 있을 때만)
	-- 핑크 스킨(LoveEffect 속성): 몸에 love_effect 상시 부착
	if Tool:GetAttribute("LoveEffect") then
		attachBodyLove(Char)
	end
	-- 슬램 애니 미리 로드(첫 재생 지연 방지). 캐릭터/Animator 준비 후.
	slamTrack = nil; slamTrackChar = nil   -- 새 장착 → 트랙 갱신
	task.spawn(function()
		task.wait(0.1)
		preloadSlamAnim()
	end)
end

local function Unequipped()
	canDamage = false
	inspectGen = inspectGen + 1   -- 감상 루프 종료
	cancelInspect()
	-- 슬램(도약~착지) 중이면 클라가 즉시 재장착하므로 서버는 상태 유지(저급 망치 패턴).
	if slamming then return end
	clearIndicator()
	ChargeSound:Stop()
	setFlameTail(false)   -- 안전: 무기 내리면 flame tail 항상 OFF
	stopChargeLoop()      -- 차징 루프 사운드도 정지
	stopColorSkin()       -- 색 스킨 정지 + 본체 색 원복
	detachBodyLove()      -- 몸 love_effect 제거
end

Tool.Activated:Connect(Activated)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)
Handle.Touched:Connect(Blow)

-- ═══ 비상 이동 복원 (라운드 종료 회수 대응) ═══
-- 스킬 시전 중(WalkSpeed 0 등) 툴 파괴/회수 시 복원 코드 미실행 → 영구 정지 방지.
local function emergencyMobilityRestore()
	-- 🎯 [2026-09-12] 경고원도 같이 지운다.
	--   ⚠️ "켜는 코드에는 끄는 코드를" — 툴 회수·사망 시 원이 월드에 영영 남는다.
	--     Anchored 라 사라질 이유가 없고, 다음 라운드까지 주황 원이 떠 있게 된다.
	clearIndicator()
	local ch = Tool.Parent
	if not (ch and ch:IsA("Model") and ch:FindFirstChildOfClass("Humanoid")) then
		local plr = Tool:FindFirstAncestorWhichIsA("Player")
		ch = plr and plr.Character
	end
	if not ch then return end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	if hum and hum.Parent then
		hum.WalkSpeed = ch:GetAttribute("Downed") and (16 * 0.25) or 16
		hum.JumpPower = 50
		hum.PlatformStand = false
	end
	if hrp then
		for _, bm in ipairs(hrp:GetChildren()) do
			if bm:IsA("BodyVelocity") or bm:IsA("BodyPosition") or bm:IsA("BodyGyro") or bm:IsA("LinearVelocity") then
				bm:Destroy()
			end
		end
	end
end
local function emergencyRestoreStaged()
	emergencyMobilityRestore()
	task.delay(0.6, emergencyMobilityRestore)
	task.delay(1.8, emergencyMobilityRestore)
end
Tool.Destroying:Connect(emergencyRestoreStaged)
Tool.Unequipped:Connect(emergencyRestoreStaged)
