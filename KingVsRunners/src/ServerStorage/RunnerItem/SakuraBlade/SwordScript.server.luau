-- Sakura Blade (서버) — 진영 체크(태거만) + canDamage 윈도우 + 서버 애니 재생.
--   ⚠️ 헤더가 'Katana Sword 2' 로 되어 있었다(복붙 잔재). 이 파일은 사쿠라다 —
--     카타나를 고치려다 여기를 만지는 사고를 막으려고 바로잡았다.
-- 휘두를 때마다 SwingAnim(직접 제작 R15 애니 139331963882133) 재생.
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local Tool   = script.Parent
local Handle = Tool:WaitForChild("Handle")
local SwingAnim = Tool:WaitForChild("SwingAnim")
local SlashSound = Handle:WaitForChild("SlashSound")
local StackRemote = Tool:WaitForChild("StackRemote")   -- 스택 수 → 클라 UI

-- ── 데미지 값 ────────────────────────────────────────────────
local SLASH_DAMAGE = 5   -- 사쿠라: 타격당 5 (0스택 10 → 5스택 30 DPS). 0스택 약함 보정. 가속은 공속/이속만.

-- ── 가속 스택 시스템 (사쿠라 블레이드 핵심) ──────────────────
-- 공격할수록 스택이 쌓여(최대 5칸) 공속·이속이 빨라짐. 데미지는 SLASH_DAMAGE 고정.
--   ⚠️ 이 줄은 '6 고정'이라고 적혀 있었는데 실제 값은 5다. 숫자를 주석에 두 번 쓰면
--     한쪽만 바뀐다 — 상수 이름으로만 가리킨다.
-- 공격이 끊기면 일정 유예 후 천천히 감쇠 → 치고 빠지며 스택 유지하는 플레이.
local STACK_MAX        = 5      -- 최대 스택
local STACK_DECAY_DELAY = 4     -- 마지막 공격 후 이 시간(초) 동안은 감쇠 안 함 (유예)
-- ⚠️ [밸런스 2026-08-29] 2 → 4.
--   [문제] 킹 평타 쿨이 1초이고 넉백이 7.6 stud 다. 밀려나 복귀하는 데
--     0.5~1초가 걸리는데 유예가 2초뿐이라, 한 번만 삐끗해도 스택이 빠지기 시작했다.
--     한 번 떨어지면 공속도 같이 떨어져 다시 쌓기가 더 어려워지는 악순환이었다.
--   [기준] Dragon Fire 의 STACK_DURATION 이 6초다. 유독 이 무기만 빡빡했다.
--     4초면 넉백 사이클 2~3번을 버티되, 방심하면 여전히 잃는다.
local STACK_DECAY_INT  = 1      -- 유예 끝난 뒤, 이 시간(초)마다 1칸씩 감쇠
-- 스택별 데미지: 0칸=5 … 5칸=15 (칸당 +2)
-- 🔺 [밸런스 2026-09-08] 스택이 데미지에 연동된다. 이전엔 5 고정이었다.
--   [문제] 공속 ×3.0 이 실제 DPS 로 이어지지 않았다. 실측(14:34) —
--     5칸 쿨은 0.5/3.0 = 0.167초인데 실제 타격 간격이 0.396초로 고정.
--     Tool.Activated(마우스 클릭)가 병목이라 공속 3배의 2/3 가 입력 한계에 먹힌다.
--     → 이론 30 DPS 가 12.6 으로 떨어졌다.
--   [왜 데미지인가] 연타 축은 이미 상한(사람 손 ~0.4초)에 걸려 있어
--     쿨을 더 줄여도 DPS 가 안 오른다. 홀드 입력도 검토했지만
--     ① 광전사의 손맛(난타)을 오히려 죽이고 ② 다른 7종은 전부 클릭이라
--     조작이 갈리며 ③ 모바일 실기기 검증 비용이 크다.
--   [체감] 화면 데미지 숫자가 5→7→9→11→13→15 로 커진다.
--     이전엔 5칸을 채워도 숫자가 계속 5라 뭐가 좋아졌는지 보이지 않았다.
--   [수치] 입력 0.4초 기준 — 0칸 12.5 DPS / 5칸 37.5 DPS.
--     HammerHigh(66) 아래, Katana(26) 위. 5칸 유지 조건이 붙은 값이다.
--   ⚠️ 공속은 그대로 둔다. 1~3칸 구간에서는 여전히 DPS 에 기여하고,
--     애니가 빨라지는 시각 피드백도 값이 있다.
local function damageForStack(s)
	return SLASH_DAMAGE + s * 2   -- 0→5, 5→15
end
-- 스택별 공속 배수: 0칸=1.0 … 5칸=3.0 (칸당 +0.4배)
local function speedMultForStack(s)
	return 1 + (s / STACK_MAX) * 2   -- 0→1.0, 5→3.0
end
-- 스택별 이속 보너스: 5칸에서 +40% (칸당 +8%)
-- ⚠️ [밸런스 2026-08-29] 0.10 → 0.20.
--   [문제] +10% 는 WalkSpeed 16 → 17.6 으로, 넉백 복귀가 0.48→0.43초였다.
--     0.05초 차이는 체감되지 않아 5칸을 유지할 이유가 되지 못했다.
-- 🔺 [밸런스 2026-09-08] 0.20 → 0.40. 위 조정도 부족했다.
--   [문제] +20% 도 여전히 체감이 안 됐다(사용자 보고). 실측 비교 —
--     Speed Potion +75%(16→28) / 사쿠라 5칸 +20%(16→19.2).
--     포션이 3.75배 강한데다 조건도 없다. 존 이동(46 stud)으로 환산하면
--     사쿠라가 아끼는 건 0.5초, 포션은 1.2초다.
--   [왜 여기까지 올리나] 광전사 컨셉의 핵심이 "밀어내는 태거에게 붙는 것"이다.
--     킹 평타 넉백 7.6 을 복귀하는 시간이 곧 DPS 손실인데,
--     +40% 면 16 → 22.4 로 복귀가 0.48→0.34초. 때릴 시간이 0.14초 늘어난다.
--   [상한 근거] 포션(+75%)의 절반 남짓. 포션은 5초 한정이고 이건 상시라
--     같은 값을 줄 수는 없다. 러너 기본 16 · 태거 14 인 관계도 유지된다
--     (5칸 22.4 는 태거보다 빠르지만, 그게 '붙는다'의 의미다).
--   ⚠️ 1단계·점령 이동에도 적용된다(무기라 2단계 내내 들고 있다).
--     다만 5칸 유지가 전제라 언덕을 오르는 중에는 쌓을 대상이 없다.
-- 🔻 [밸런스 2026-09-08 #3] 0.46875 → 0.40 되돌림. 5칸 이속 23.5 → 22.4.
--   [왜] 23.5 로 F5 한 판 — "한 번도 안 맞았다"(사용자 보고). 계산상 반응 여유가
--     0.24초뿐이라 빠듯할 줄 알았는데 실제로는 여유롭게 피해졌다.
--     즉 실효 반응 지연이 내가 잡은 0.4초보다 훨씬 짧았다는 뜻이다 —
--     차징음·손 발광이 예고로 충분히 작동하고 있었던 것.
--   ⚠️ 계산으로 잡은 "회피 가능선"이 실측보다 보수적이었다. 다음에 같은 종류의
--     값을 정할 때 인지 지연 0.4초를 그대로 쓰지 말 것.
--   ⚠️ 되돌린 뒤에도 강타 도달은 12 다(CHARGED_FORWARD 5). 22.4 로 피해지는지가
--     이번 확인 대상 — 안 피해지면 이속이 아니라 도달 12 쪽을 되돌린다.
--   [이력] 0.10 → 0.20 → 0.40 → 0.46875 → 0.40
local function walkBonusForStack(s)
	return (s / STACK_MAX) * 0.40    -- 0→0, 5→0.40 (16 → 22.4)
end

local atkStacks    = 0      -- 현재 스택 수
local lastAtkTime  = 0      -- 마지막 공격 시각
local stackBaseWalk = nil   -- 스택 적용 전 원래 WalkSpeed (이속 보너스 복원용)
local decayRunning = false  -- 감쇠 루프 진행 중 여부
local nextDecayTime = 0     -- 다음 감쇠 예정 시각 (공격 시 now+유예로 리셋)
local STACK_DEBUG  = true   -- 🔬 [2026-09-08] 재활성. 스택이 실제로 몇 칸까지 오르는지 확인.
--   [왜] 이론상 5스택이면 DPS 30(HammerHigh 평타 33 급)인데 실측이 3.0 이었다.
--     훈련장에서 방해 없이 때렸을 때도 간격 0.39초 = 공속 배수 약 1.28 →
--     1~2스택밖에 안 유지된 것으로 계산된다. 수치가 약한 게 아니라
--     '스택이 안 쌓이는' 문제일 가능성이 높다.
--   [무엇을 보나] +1 / 감쇠 로그의 칸 수. 5칸에 도달하는지, 얼마나 유지되는지.
--   ⚠️ 확인 끝나면 false 로. 타격마다 찍혀서 스팸이 된다.
local updateAuraForStack    -- forward 선언 (아래에서 정의) — 스택 변할 때 오라 갱신

-- ── 타격 윈도우 + 중복 방지 ──────────────────────────────────
local canDamage    = false
local windowDamage = 0
local HIT_COOLDOWN = 0.5
local lastHitTime  = {}

local Char, Hum, Plyr

-- 다운 인지 이속 클램프: 스킬 이속을 세팅한 뒤 호출. 다운 중이면 다운 패널티 속도로 눌러써서
-- 다운 상태에서 스킬로 이속이 초기화되는 버그를 막는다. (DownSystem이 "Downed" 속성 + 16*0.25 적용)
local DOWN_WS_MULT = 0.25
local function clampDown()
	if not Hum then return end
	local char = Hum.Parent
	if char and char:GetAttribute("Downed") then
		Hum.WalkSpeed = 16 * DOWN_WS_MULT
	end
end

-- ── 가속 스택 관리 ──────────────────────────────────────────
-- 현재 스택을 이속(WalkSpeed)에 반영. 공속은 공격 시 speedMultForStack로 애니 속도에 반영.
local function applyStackWalk()
	if not Hum then return end
	if stackBaseWalk == nil then stackBaseWalk = Hum.WalkSpeed end
	Hum.WalkSpeed = stackBaseWalk * (1 + walkBonusForStack(atkStacks))
	clampDown()
end

-- 스택 감쇠 루프: 마지막 공격 후 STACK_DECAY_DELAY(유예) 뒤부터, STACK_DECAY_INT마다 1칸씩 감소.
local function startDecayLoop()
	if decayRunning then return end
	decayRunning = true
	task.spawn(function()
		while decayRunning and atkStacks > 0 do
			task.wait(0.1)
			if not Hum or Hum.Health <= 0 then break end
			-- nextDecayTime: 다음 감쇠 예정 시각. 공격 때마다 (공격시각 + 유예)로 리셋됨.
			if os.clock() >= nextDecayTime then
				atkStacks = math.max(0, atkStacks - 1)
				nextDecayTime = os.clock() + STACK_DECAY_INT   -- 다음 칸은 INT 간격
				applyStackWalk()
				if updateAuraForStack then updateAuraForStack() end
				if STACK_DEBUG then
					print(string.format("🌸 [스택] 감쇠 → %d칸 (공속 ×%.2f, 이속 +%.0f%%)",
						atkStacks, speedMultForStack(atkStacks), walkBonusForStack(atkStacks)*100))
				end
			end
		end
		decayRunning = false
		if Hum and stackBaseWalk then Hum.WalkSpeed = stackBaseWalk end
		clampDown()
	end)
end

-- 공격 적중 시 스택 +1 (최대치 한도).
local function addStack()
	atkStacks = math.min(STACK_MAX, atkStacks + 1)
	lastAtkTime = os.clock()
	nextDecayTime = os.clock() + STACK_DECAY_DELAY   -- 공격하면 유예 타이머 리셋
	applyStackWalk()
	startDecayLoop()
	if updateAuraForStack then updateAuraForStack() end
	if STACK_DEBUG then
		print(string.format("🌸 [스택] +1 → %d칸 (공속 ×%.2f, 이속 +%.0f%%)",
			atkStacks, speedMultForStack(atkStacks), walkBonusForStack(atkStacks)*100))
	end
end


-- ⚔️ [2026-09-08] 바리케이드 타격으로도 스택이 쌓이게 한다.
--   [증상] 성문을 부수는 약 15초 동안 사쿠라만 0칸으로 서 있었다.
--     그리고 성문이 무너지는 순간이 곧 킹과의 첫 교전인데,
--     하필 그때 가장 약한 상태다(실측 14:49 — 2단계 시작 후에야 첫 스택).
--   [왜 안 쌓였나] Blow 는 Humanoid 가 있는 대상만 처리한다.
--     바리케이드는 Humanoid 가 없고 BarricadeSystem 이 자체 판정하므로
--     무기의 타격 경로를 아예 타지 않는다.
--   [왜 이 방식인가] BarricadeSystem 이 이미 _G.playBotSwing 으로 외부에 알리는
--     패턴을 쓴다. 같은 형태로 훅을 하나 더 여는 것이라 새 구조가 아니다.
--   ⚠️ 캐릭터별로 등록한다. 여러 러너가 사쿠라를 들 수 있으므로
--     전역 하나로 두면 남의 스택이 오른다(katanaCounters 와 같은 형태).
--   ⚠️ 약참조(__mode="k")라 캐릭터가 사라지면 자동 정리된다.
local function registerBarricadeHook()
	if not Char then return end
	_G.sakuraStackers = _G.sakuraStackers or setmetatable({}, {__mode = "k"})
	_G.sakuraStackers[Char] = addStack
end
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

	-- 칼날이 실제로 내 손에 쥐어져 있는지
	local rightArm = Char:FindFirstChild("Right Arm") or Char:FindFirstChild("RightHand")
	if not rightArm then return end
	local grip = rightArm:FindFirstChild("RightGrip")
	if not grip or (grip.Part0 ~= Handle and grip.Part1 ~= Handle) then return end

	local character = hit.Parent
	if character == Char then return end
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

	-- 같은 대상 중복 타격 방지 (공속 스택만큼 쿨다운도 짧아짐 → 빠른 연타가 데미지로 이어짐)
	local now = os.clock()
	local last = lastHitTime[character]
	local hitCd = HIT_COOLDOWN / speedMultForStack(atkStacks)
	if last and (now - last) < hitCd then return end
	lastHitTime[character] = now

	TagHumanoid(humanoid, Plyr)
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
	humanoid:TakeDamage(windowDamage)
	-- 🔢 [2026-09-06] 데미지 표기 (무기 공용 _G.ShowDamage).
	--   ⚠️ 사쿠라는 5스택까지 공속이 오르므로 숫자가 빠르게 연속으로 뜬다.
	--     팝업이 같은 자리에 겹치지 않도록 클라가 좌표를 흩는다(DamagePopupClient).
	if _G.ShowDamage and Plyr then
		local root = character:FindFirstChild("HumanoidRootPart")
		_G.ShowDamage(Plyr,
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, windowDamage)) or windowDamage,
			root and root.Position, atkStacks and atkStacks >= STACK_MAX)
	end

	-- 적중 성공 시에만 스택 +1 (허공 휘두름으로는 안 쌓임)
	addStack()
end

-- 휘두름 애니 재생 헬퍼 (일반 공격 + 카운터 공용)
local function playSwingAnim(speed)
	if not Hum then return end
	local animator = Hum:FindFirstChildOfClass("Animator")
	local track
	if animator then
		track = animator:LoadAnimation(SwingAnim)
	else
		track = Hum:LoadAnimation(SwingAnim)
	end
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.05, 1, speed or 0.8)  -- 기본 0.8배속(일반 공격). 카운터는 더 빠르게 인자 전달.
	return track
end

-- ── 공격 ─────────────────────────────────────────────────────
Tool.Enabled = true
local function Activated()
	if not Tool.Enabled then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	Tool.Enabled = false

	-- 현재 스택 기준 공속 배수 (0칸 1.0 … 5칸 3.0)
	local mult = speedMultForStack(atkStacks)

	-- 휘두름 애니메이션 — 스택만큼 빠르게 재생
	playSwingAnim(0.8 * mult)
	SlashSound:Play()  -- 베기 사운드

	-- (스택은 적중 시에만 +1 — Blow에서 처리. 허공 휘두름으로는 안 쌓임)

	-- 타격 윈도우 열기 (휘두르는 동안만 데미지)
	-- ⚠️ [2026-09-08] 스윙 시작 시점의 스택으로 데미지를 정한다.
	--   스택은 '명중 후' 오르므로(addStack), 이 스윙은 직전 스택 기준이다.
	--   즉 첫 타는 5, 다음 타부터 7·9·11·13·15 로 오른다 — 의도한 순서다.
	windowDamage = damageForStack(atkStacks)
	canDamage = true
	task.delay(0.35 / mult, function() canDamage = false end)

	wait(0.5 / mult)   -- 공격 쿨다운도 스택만큼 짧아짐 → 실제 연타 속도 상승
	Tool.Enabled = true
end


-- ── 왼손 두 번째 칼(K2Blade) 부착 ───────────────────────────
-- Tool은 Handle(k1)만 오른손에 쥐여줌. k2는 LeftHand에 Motor6D로 직접 부착.
local K2Blade = Tool:FindFirstChild("K2Blade")
local leftMotor = nil

-- 왼손 칼 미세조정용 (오른손 Grip을 복사하므로 기본 0. 양손 위치는 Tool.Grip에서 통합 관리)
local K2_TUNE = CFrame.new(0, 0, 0)

local function attachK2()
	if not K2Blade or not Char then return end
	local leftHand = Char:FindFirstChild("LeftHand")          -- R15
		or Char:FindFirstChild("Left Arm")                    -- R6 폴백
	if not leftHand then return end
	local prim = K2Blade.PrimaryPart
	if not prim then return end

	-- 기존 모터 제거
	if leftMotor then leftMotor:Destroy(); leftMotor = nil end

	task.wait(0.15)
	if leftMotor or not (Char and Char.Parent) then return end

	-- 오른손이 칼을 어떻게 쥐는지 그대로 읽어옴.
	-- 오른손 칼 = RightHand(또는 RightGrip Weld)에 C1=Grip 으로 붙음.
	local rightHand = Char:FindFirstChild("RightHand") or Char:FindFirstChild("Right Arm")
	local handle = Tool:FindFirstChild("Handle")
	if not (rightHand and handle) then return end

	-- 오른손 칼이 쓰는 RightGrip의 C0/C1을 그대로 왼손에 복사 → 양손 동일하게 쥠.
	local rightGrip = rightHand:FindFirstChild("RightGrip")
	local motor = Instance.new("Motor6D")
	motor.Name = "K2Grip"
	motor.Part0 = leftHand
	motor.Part1 = prim
	if rightGrip and rightGrip:IsA("Weld") then
		motor.C0 = rightGrip.C0 * K2_TUNE   -- 오른손 손목 그립 회전 동일 적용 (+ 미세조정)
		motor.C1 = rightGrip.C1             -- 칼 기준점도 동일
	else
		motor.C0 = K2_TUNE
		motor.C1 = Tool.Grip
	end
	prim.CFrame = leftHand.CFrame * motor.C0 * motor.C1:Inverse()
	motor.Parent = leftHand
	leftMotor = motor
end

local function detachK2()
	if leftMotor then leftMotor:Destroy(); leftMotor = nil end
end

-- ── 벚꽃 오라 (스택 연동) ────────────────────────────────────
-- 발(exam2: dust+wave) 1군데 + 양팔·등(exam1) 3군데에 부착. 스택 오를수록 강화.
local ServerStorage = game:GetService("ServerStorage")
local armTemplate  = ServerStorage:FindFirstChild("SakuraArmAuraTemplate")
local footTemplate = ServerStorage:FindFirstChild("SakuraFootAuraTemplate")

-- ── 색놀이 스킨 (단색) ───────────────────────────────────────
-- 검날(Handle, Katana of Blossom)은 SpecialMesh+텍스처+VertexColor 구조 →
-- VertexColor에 색조를 곱해 색 변경(텍스처 질감 유지). 오라 파티clos은 Color로 변경.
-- SkinHue/SkinSat/SkinVal 속성(0~1)을 읽어 적용.
local function applyBladeColor()
	local hueAttr = Tool:GetAttribute("SkinHue")
	if hueAttr == nil then return end
	local h = hueAttr
	local s = Tool:GetAttribute("SkinSat") or 1
	local v = Tool:GetAttribute("SkinVal") or 1
	local col = Color3.fromHSV(h, s, v)
	-- 검날 VertexColor: 텍스처에 곱해지는 색조.
	-- ×3 균일 증폭은 채도 낮은 색(골드 등)의 RGB를 다 띄워 흰색으로 왜곡됨 →
	-- 색 비율(hue·채도)을 유지하며 밝기만 적당히(×1.8) 키워 선명하게.
	local mul = 1.8
	local vc = Vector3.new(col.R * mul, col.G * mul, col.B * mul)
	-- 재질: SkinMaterial 속성(로블록스 재질명). 기본 Metal. 텍스처는 유지(벚꽃 질감 살림).
	local matName = Tool:GetAttribute("SkinMaterial") or "Metal"
	local mat = Enum.Material[matName] or Enum.Material.Metal
	local refl = (matName == "Metal") and 0.5 or 0
	for _, p in ipairs(Tool:GetDescendants()) do
		local sm = p:IsA("BasePart") and p:FindFirstChildOfClass("SpecialMesh")
		if sm and sm.TextureId ~= "" then
			sm.VertexColor = vc
			p.Material = mat
			p.Reflectance = refl
		end
	end
end
-- 오라 파티clos을 스킨색으로 칠함 (칼날과 톤 일치 위해 스킨 HSV 그대로 적용)
local SILVER_PETAL_TEXTURE = "rbxassetid://133329036243942"  -- 무채색 벚꽃잎(실버 전용)
local function colorizeAuraEmitter(e)
	local hueAttr = Tool:GetAttribute("SkinHue")
	if hueAttr == nil then return end
	local h = hueAttr
	local s = Tool:GetAttribute("SkinSat") or 1
	local v = Tool:GetAttribute("SkinVal") or 1
	-- 원래 LightEmission/Texture 백업(최초 1회) — 스킨 해제 시 복원용
	if e:GetAttribute("OrigLightEmission") == nil then
		e:SetAttribute("OrigLightEmission", e.LightEmission)
	end
	if e:GetAttribute("OrigTexture") == nil then
		e:SetAttribute("OrigTexture", e.Texture)
	end
	-- 원래 Size 백업(최초 1회) — 실버 잎 텍스처가 기존보다 커서 줄였다 복원.
	-- 키포인트의 time·value를 모두 보존(SakuraArm은 t=0, 0.3, 1 형태).
	if e.Name == "SakuraArm" and e:GetAttribute("OrigSizeSaved") == nil then
		e:SetAttribute("OrigSizeSaved", true)
		e:SetAttribute("OrigT0", e.Size.Keypoints[1].Time); e:SetAttribute("OrigV0", e.Size.Keypoints[1].Value)
		e:SetAttribute("OrigT1", e.Size.Keypoints[2].Time); e:SetAttribute("OrigV1", e.Size.Keypoints[2].Value)
		e:SetAttribute("OrigT2", e.Size.Keypoints[3].Time); e:SetAttribute("OrigV2", e.Size.Keypoints[3].Value)
	end
	-- 벚꽃잎(SakuraArm) 텍스처: 실버 스킨일 때만 무채색 잎으로 교체(분홍기 제거),
	-- 그 외 색은 원래 분홍 벚꽃잎 텍스처 유지.
	if e.Name == "SakuraArm" then
		local t0,v0 = e:GetAttribute("OrigT0") or 0, e:GetAttribute("OrigV0") or 0.3
		local t1,v1 = e:GetAttribute("OrigT1") or 0.3, e:GetAttribute("OrigV1") or 0.7
		local t2,v2 = e:GetAttribute("OrigT2") or 1, e:GetAttribute("OrigV2") or 0.4
		if s <= 0.02 and v >= 0.85 then
			e.Texture = SILVER_PETAL_TEXTURE
			-- 실버 잎이 더 크게 보여서 0.5배로 축소 (time은 원래대로 유지)
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(t0, v0 * 0.5),
				NumberSequenceKeypoint.new(t1, v1 * 0.5),
				NumberSequenceKeypoint.new(t2, v2 * 0.5),
			})
			e.Squash = NumberSequence.new(0.3)   -- 세로를 눌러 납작하게(잎 모양 강조)
		else
			e.Texture = e:GetAttribute("OrigTexture")
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(t0, v0),
				NumberSequenceKeypoint.new(t1, v1),
				NumberSequenceKeypoint.new(t2, v2),
			})
			e.Squash = NumberSequence.new(0)     -- 원래대로(압축 없음)
		end
	end
	-- 실버 벚꽃잎(SakuraArm): 텍스처의 메탈릭 은색끼를 살리기 위해 발광을 낮추고
	-- 색은 거의 흰색(살짝 회색빛)을 곱해 음영·외곽선이 죽지 않게 함.
	if e.Name == "SakuraArm" and s <= 0.02 and v >= 0.85 then
		e.LightEmission = 0.05   -- 발광 거의 제거 → 텍스처 은색 그라데이션 보존
		e.Color = ColorSequence.new(Color3.fromRGB(235, 238, 242))  -- 살짝 차가운 은백색
		return
	end
	-- 검정 스킨(채도≈0 + 명도 낮음): 발광(LightEmission)이 높으면 검정 칠해도 환하게 떠서
	-- 안 검어짐 → LightEmission을 0으로 눌러 진짜 검정으로. 색도 진하게.
	if s <= 0.02 and v <= 0.15 then
		e.LightEmission = 0
		e.Color = ColorSequence.new(Color3.fromRGB(8, 8, 8))
		return
	end
	-- 비검정: 원래 발광 복원 + 스킨색 그대로 (칼날과 톤 일치)
	e.LightEmission = e:GetAttribute("OrigLightEmission") or e.LightEmission
	e.Color = ColorSequence.new(Color3.fromHSV(h, s, v))
end

-- ── 무지개 순환 ──────────────────────────────────────────────
-- RainbowSkin 속성이면 칼날 VertexColor + 모든 오라를 매 프레임 hue로 갱신.
local RAINBOW_CYCLE = 3.0   -- 한 바퀴(빨~보~빨) 도는 시간(초)
local rainbowRunning = false
local function paintRainbowHue(hue)
	-- 칼날 VertexColor (applyBladeColor와 동일하게 ×1.8 — 색 비율 유지하며 밝기만)
	local col = Color3.fromHSV(hue, 1, 1)
	local vc = Vector3.new(col.R * 1.8, col.G * 1.8, col.B * 1.8)
	-- 검(Tool)에 붙은 칼날·검 오라
	for _, p in ipairs(Tool:GetDescendants()) do
		local sm = p:IsA("BasePart") and p:FindFirstChildOfClass("SpecialMesh")
		if sm and sm.TextureId ~= "" then sm.VertexColor = vc end
		if p:IsA("ParticleEmitter") then
			p.Color = ColorSequence.new(col)
		end
	end
	-- 몸에 붙은 오라(SakuraArm/Foot 등)는 Tool이 아니라 캐릭터에 부착됨 → 직접 순회.
	if Char then
		for _, p in ipairs(Char:GetDescendants()) do
			if p:IsA("ParticleEmitter") then
				p.Color = ColorSequence.new(col)
			end
		end
	end
end
local function startRainbow()
	if rainbowRunning then return end
	if not Tool:GetAttribute("RainbowSkin") then return end
	rainbowRunning = true
	task.spawn(function()
		while rainbowRunning do
			paintRainbowHue((tick() % RAINBOW_CYCLE) / RAINBOW_CYCLE)
			task.wait()
		end
	end)
end
local function stopRainbow()
	rainbowRunning = false
end

local auraParts = {}        -- 부착한 holder 파트들 (정리용)
local auraEmitters = {}     -- {emitter, baseRate} 목록 (스택 연동용)
local footEmitters = {}     -- 발 파티클만 따로 추적 (0스택이면 완전히 끔)

-- 한 부위에 holder 복제 부착
local function attachOne(template, limbName, cframeOffset, isFoot)
	if not (template and Char) then return end
	local limb = Char:FindFirstChild(limbName)
	if not limb then return end
	local holder = template:Clone()
	-- ⚠️ [2026-09-08] 밖에서 찾을 수 있게 표식을 남긴다.
	--   [왜] 오라는 캐릭터 팔다리에 붙어 툴과 함께 사라지지 않는다.
	--     Tool.Destroying / AncestryChanged 로 자체 정리를 시도했지만,
	--     Destroy() 는 툴 안 스크립트를 즉시 정지시켜 그 핸들러가 실행되지 않는다.
	--     (오늘 관성·팔·스킬아이콘에서 반복 확인한 사실)
	--   [해결] 이름을 붙여 WeaponUICleanupClient 가 밖에서 걷어내게 한다.
	holder.Name = "_WeaponFx_SakuraAura"
	holder.CFrame = limb.CFrame * (cframeOffset or CFrame.new())
	holder.Parent = limb
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = holder
	weld.Parent = holder
	holder.Anchored = false
	table.insert(auraParts, holder)
	-- 이 holder 안의 모든 ParticleEmitter 등록 (기본 Rate 기억)
	for _, pe in ipairs(holder:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then
			colorizeAuraEmitter(pe)   -- 스킨 색이 있으면 파티clos을 그 색으로
			table.insert(auraEmitters, { emitter = pe, baseRate = pe.Rate })
			if isFoot then table.insert(footEmitters, pe) end   -- 발 파티클 별도 추적
		end
	end
end

local function attachAura()
	if not Char then return end
	auraParts = {}
	auraEmitters = {}
	footEmitters = {}
	-- 발: 한쪽 다리 (범위 넓어 양발 커버). 살짝 아래로 내려 바닥 파동이 발밑에 깔리게.
	attachOne(footTemplate, "RightLowerLeg", CFrame.new(0, -1, 0), true)   -- true = 발 파티클
	-- 양팔
	attachOne(armTemplate, "LeftUpperArm")
	attachOne(armTemplate, "RightUpperArm")
	-- 등 (UpperTorso 뒤쪽으로 살짝)
	attachOne(armTemplate, "UpperTorso", CFrame.new(0, 0, 0.6))
end

local function detachAura()
	for _, p in ipairs(auraParts) do
		if p then p:Destroy() end
	end
	auraParts = {}
	auraEmitters = {}
	footEmitters = {}
end

-- 스택(0~5)에 따라 오라 강도 보간. 0칸=은은, 5칸=만개.
function updateAuraForStack()
	local t = atkStacks / STACK_MAX        -- 0~1
	-- 0칸=기본 Rate의 8%(거의 안 보임) → 5칸=기본 Rate의 70%(차분한 만개)
	local mult = 0.08 + t * 0.62
	for _, info in ipairs(auraEmitters) do
		if info.emitter then
			info.emitter.Rate = info.baseRate * mult
		end
	end
	-- 발 파티클: 0스택이면 완전히 끄고(방출 중단), 1스택 이상이면 켬
	local footOn = atkStacks >= 1
	for _, pe in ipairs(footEmitters) do
		if pe then pe.Enabled = footOn end
	end
	-- 스택 UI 갱신 (본인 클라에게 현재 스택 전송)
	if Plyr then
		StackRemote:FireClient(Plyr, atkStacks)
	end
end

local function Equipped()
	Char = Tool.Parent
	Hum  = Char:FindFirstChildOfClass("Humanoid")
	Plyr = Players:GetPlayerFromCharacter(Char)
	attachK2()      -- 왼손에 두 번째 칼 부착
	attachAura()    -- 몸 주위 벚꽃 오라
	updateAuraForStack()
	applyBladeColor()   -- 스킨 색이 있으면 검날 VertexColor를 그 색조로
	registerBarricadeHook()   -- ⚔️ 바리케이드 타격으로도 스택이 쌓이게 등록
	-- 검 오라(KParticle) 프리필: Lifetime이 길어(10~30초) Rate로 천천히 차오르면
	-- 검을 처음 들 때 입자가 다 깔리기까지 수 초 걸려 어색함.
	-- 들 때 한 사이클치를 Emit으로 즉시 분출해 처음부터 꽉 찬 상태로 만듦.
	for _, kp in ipairs(Tool:GetDescendants()) do
		if kp:IsA("ParticleEmitter") and (kp.Parent.Name == "KParticle" or kp.Parent.Name == "KBeam") then
			colorizeAuraEmitter(kp)   -- 검 오라도 스킨 색으로
		end
		if kp:IsA("ParticleEmitter") and kp.Parent.Name == "KParticle" then
			kp:Emit(math.clamp(math.ceil(kp.Rate * kp.Lifetime.Min), 1, 80))
		end
	end
	startRainbow()   -- 무지개 스킨이면 순환 시작 (아니면 즉시 return)
end

local function Unequipped()
	canDamage = false
	stopRainbow() -- 무지개 순환 정지
	detachK2()   -- 왼손 칼 제거
	detachAura() -- 오라 제거
	-- ⚔️ 바리케이드 훅 해제. 안 지우면 무기를 바꿔도 남의 스택이 오른다.
	if Char and _G.sakuraStackers then
		_G.sakuraStackers[Char] = nil
	end
end

Tool.Activated:Connect(Activated)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)

-- ⚠️ [2026-09-08] 툴이 '파괴' 될 때도 오라를 걷는다.
--   [증상] 무기를 바꿔도 벚꽃 오라(꽃가루)가 캐릭터에 그대로 남았다.
--   [원인] detachAura 가 Unequipped 에만 걸려 있다(1010행). 훈련장 무기 교체나
--     라운드 회수처럼 툴이 Destroy 되는 경로에서는 그 이벤트가 오지 않는다.
--     오라 파트는 캐릭터(팔·다리·몸통)에 붙어 있어 툴과 함께 사라지지 않는다.
--   [왜 여기서 고치나] 오라 파트는 이름 없이 캐릭터에 붙어 밖에서 찾을 수 없다.
--     만든 쪽이 치우는 게 유일한 길이다. DiamondBladeSword 도 같은 처리를 했다.
--   ⚠️ AncestryChanged 를 함께 쓴다. Destroying 은 툴 내부 스크립트와 같은 운명이라
--     늦거나 아예 안 올 수 있다.
Tool.Destroying:Connect(function()
	pcall(detachAura)
end)
Tool.AncestryChanged:Connect(function(_, parent)
	if not parent then pcall(detachAura) end
end)
Handle.Touched:Connect(Blow)
