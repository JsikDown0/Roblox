-- Katana Sword 2 (서버) — 게임 구조 기반: 진영 체크(태거만) + canDamage 윈도우 + 서버 애니 재생.
-- 휘두를 때마다 SwingAnim(직접 제작 R15 애니 139331963882133) 재생.
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local Tool   = script.Parent
local Handle = Tool:WaitForChild("Handle")
local SwingAnim = Tool:WaitForChild("SwingAnim")
local CounterAnim = Tool:WaitForChild("CounterAnim")
-- 🎭 [2026-09-14] R6 판 애니. 리그에 따라 골라 쓴다.
--   [왜] 로블록스 애니는 R6/R15 사이에 자동 변환되지 않는다. 관절 이름이 다르다
--     (R6 Torso/Right Arm ↔ R15 UpperTorso/RightUpperArm). 맞지 않는 리그에서는
--     로드는 되는데 화면에 아무것도 안 나온다 — 에러도 없다.
--   [현황] AI 러너 템플릿(ServerStorage.Famer2)은 R6 다. 유저 캐릭터는 게임 설정에 따라
--     R6 일 수도 R15 일 수도 있어, 어느 쪽이든 나오도록 양쪽을 둔다.
--   [선례] 같은 방식이 이 게임에 이미 있다 — 어떤 무기가 Fire/Hold/Idle 와
--     R15Fire/R15Hold/R15Idle 를 짝으로 갖고 있다.
--   ⚠️ R6 판이 없으면 기존(R15) 것으로 떨어진다. 없는 것보단 낫고, 안 나오면
--     "R6 판을 안 넣었다"가 원인이라는 뜻이다.
local SwingAnimR6 = Tool:FindFirstChild("SwingAnimR6")
local CounterAnimR6 = Tool:FindFirstChild("CounterAnimR6")
-- ⚠️ 리그 선택 헬퍼(animFor)는 `local Char, Hum, Plyr` 선언 **아래**에 있다.
--   여기 두면 Hum 을 상위값으로 못 잡고 전역 nil 을 보게 되어, R6 판을 영영 안 고른다.
--   에러도 안 나서 "R6 애니를 넣었는데 그대로다"로만 보인다.
local CounterRemote = Tool:WaitForChild("CounterRemote")
local SlashSound = Handle:WaitForChild("SlashSound")

-- ── 데미지 값 ────────────────────────────────────────────────
local SLASH_DAMAGE = 13   -- 카타나: 36DPS 아웃라이어 정리 → 26DPS(2타/초)로 수렴대 편입

-- ── 카운터(발도 반격) 설정 ──────────────────────────────────
-- 강제 지속형: 한 번 누르면 HOLD_TIME 동안 자세 강제 유지(취소 불가).
-- 그 안에 밀치기가 오면 성공, 안 오면 불발 → 쿨다운.
local COUNTER_DAMAGE    = 50     -- 카운터 성공 시 태거에게 주는 데미지
local COUNTER_STUN      = 0.5    -- 태거 스턴 시간(초)
local COUNTER_HOLD_TIME = 1.5    -- 자세 강제 지속 시간(초)
local COUNTER_COOLDOWN  = 6      -- 자세 종료 후 재사용 쿨다운(초) — 성공/불발 동일
local COUNTER_SLOW      = 0.5    -- 자세 중 이동속도 배율(50%)

local counterReady   = false    -- 현재 카운터 자세 중인가
local counterCooling = false    -- 쿨다운 중인가
local counterSession = 0         -- 자세 세션 ID (지속 타이머 식별용)
local savedWalkSpeed = nil       -- 자세 진입 전 원래 속도
local counterTrack   = nil       -- 카운터 자세 애니 트랙

-- ── 타격 윈도우 + 중복 방지 ──────────────────────────────────
local canDamage    = false
local windowDamage = 0
local HIT_COOLDOWN = 0.5
local lastHitTime  = {}

local Char, Hum, Plyr

-- 🎭 이 캐릭터 리그에 맞는 애니를 고른다. (선언부의 R6 판 주석 참조)
--   ⚠️ 반드시 `Hum` 선언 아래에 둘 것. 위에 두면 전역 nil 을 잡아 R6 분기가 통째로 죽고,
--     에러도 안 나서 "R6 애니를 넣었는데 그대로다"로만 보인다.
local function animFor(r15Anim, r6Anim)
	if r6Anim and Hum and Hum.RigType == Enum.HumanoidRigType.R6 then
		return r6Anim
	end
	return r15Anim
end

-- 🔊 [2026-08-25] 연타 시 소리 씹힘 방지.
-- ⚠️ 같은 Sound 에 Play() 를 다시 호출하면 재생 중이던 소리가 되감긴다.
--    평타 쿨이 음원보다 짧으면 소리가 계속 잘린다.
--    → 복제해 재생하고 Debris 로 정리한다.
-- 🐛 [버그수정 2026-09-05] 이 블록이 UntagHumanoid 함수 '안'에 삽입돼 있었다.
--    [증상] 카타나로 한 번 치면 모션만 나오고 데미지가 0, 이후 평타도 안 나감.
--    [원인] playOneShot 이 UntagHumanoid 의 지역 함수라 Activated 에서는 nil.
--      실측: playSwingAnim=function / playOneShot=nil / __Debris=nil
--      → 148행에서 에러 → 그 아래 canDamage=true 가 실행되지 않아 데미지 창이 안 열린다.
--      (135행에서 Tool.Enabled=false 로 잠근 뒤였으므로 툴도 영구 잠김이었다)
--    [교훈] 삽입 위치 앞에 어떤 블록이 열려 있는지 확인할 것 — 함수 본문 안에
--      들여쓰기 없이 붙으면 눈으로는 최상위처럼 보이지만 스코프는 그 함수다.
local __Debris = game:GetService("Debris")
local function playOneShot(template, parent)
	if not template then return end
	local s = template:Clone()
	s.Parent = parent or template.Parent
	s:Play()
	__Debris:AddItem(s, 4)
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

	-- 같은 대상 중복 타격 방지
	local now = os.clock()
	local last = lastHitTime[character]
	if last and (now - last) < HIT_COOLDOWN then return end
	lastHitTime[character] = now

	TagHumanoid(humanoid, Plyr or Char)   -- 🏷️ 봇이면 캐릭터 모델(다른 무기와 같은 처리)
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then return end
	humanoid:TakeDamage(windowDamage)
	-- 🔢 [2026-09-06] 데미지 표기 (무기 공용 _G.ShowDamage).
	--   ⚠️ _G.DisplayDamage 를 통과시켜 CC 중 실효값으로 환산한다 — 다른 무기와 같은 규약.
	if _G.ShowDamage and Plyr then
		local root = character:FindFirstChild("HumanoidRootPart")
		_G.ShowDamage(Plyr,
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, windowDamage)) or windowDamage,
			root and root.Position, false)
	end
end

-- 휘두름 애니 재생 헬퍼 (일반 공격 + 카운터 공용)
local function playSwingAnim(speed)
	if not Hum then return end
	local animator = Hum:FindFirstChildOfClass("Animator")
	local track
	local src = animFor(SwingAnim, SwingAnimR6)
	if animator then
		track = animator:LoadAnimation(src)
	else
		track = Hum:LoadAnimation(src)
	end
	-- 🎬 [2026-09-14] Action → Action3. 카운터 자세(Action2)보다 위에 둔다.
	--   [왜] 같은 우선순위면 나중에 Play 한 쪽이 이긴다. 자세를 Action2 로 올렸으므로
	--     참격이 Action 그대로면 성공 순간에 참격이 자세에 눌려 안 보인다.
	--   [의도] 자세는 유지되는 동안 보이고, 반격이 터지는 순간만 참격이 덮는다.
	track.Priority = Enum.AnimationPriority.Action3
	track:Play(0.05, 1, speed or 0.8)  -- 기본 0.8배속(일반 공격). 카운터는 더 빠르게 인자 전달.
	return track
end

-- ── 공격 ─────────────────────────────────────────────────────
Tool.Enabled = true
local function Activated()
	if not Tool.Enabled then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	-- ⚠️ 카운터 자세 중에는 평타를 못 쓴다.
	--    자세는 "반격을 노리며 대기"하는 상태이므로 그 중에 베기가 나가면
	--    이동 둔화(COUNTER_SLOW)라는 대가만 지고 공격은 그대로 하는 셈이 되어
	--    자세의 리스크가 사라진다(공짜 버프화).
	if counterReady then return end
	Tool.Enabled = false

	-- 휘두름 애니메이션 — 서버에서 직접 재생(모든 클라에 자동 복제).
	playSwingAnim()
	playOneShot(SlashSound)  -- 베기 사운드

	-- 타격 윈도우 열기 (휘두르는 동안만 데미지)
	windowDamage = SLASH_DAMAGE
	canDamage = true
	task.delay(0.35, function() canDamage = false end)

	wait(0.5)   -- 공격 쿨다운
	Tool.Enabled = true
end

-- 🛡️ [안전망 2026-09-05] Activated 안에서 무슨 에러가 나든 잠금은 반드시 풀린다.
--   [왜] 135행에서 Tool.Enabled=false 로 잠근 뒤 본문에서 에러가 나면 156행의
--     복구에 영영 도달하지 못한다. 실측: SwordScript:139 nil 호출 한 번으로
--     그 라운드 내내 평타가 안 나갔다(카운터만 작동해 원인이 가려졌다).
--   [규칙] "상태를 끄는 코드에는 켜는 코드를 같은 편집에 함께 넣을 것"(09-01) —
--     여기서는 '어떤 경로로 빠져나가도 켜진다'로 보장을 한 단계 올린다.
--   ⚠️ 에러를 삼키지 않는다. warn 으로 남겨야 원인이 계속 보인다.
local function ActivatedSafe()
	local ok, err = pcall(Activated)
	if not ok then
		warn("[KatanaSword2] Activated 에러 → 툴 잠금 해제:", err)
		Tool.Enabled = true
	end
end

-- ── 카운터(발도 반격) ───────────────────────────────────────
-- 칼날 발광 헬퍼: 카운터 자세 동안 칼의 모든 메시를 빛나게.
-- (칼은 Handle + Blade + 메시 조각들로 구성된 복합 구조라 전부 처리)
local glowParts = {}        -- 발광 대상 파트들
local glowOriginals = {}    -- 원래 Material/Color 저장
do
	for _, p in ipairs(Tool:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(glowParts, p)
			glowOriginals[p] = { Material = p.Material, Color = p.Color }
		end
	end
end

local function setGlow(on)
	-- 무지개 스킨은 칼이 이미 Hue 순환 중 → 발광색 강제하지 않음(순환 유지)
	local isRainbow = Tool:GetAttribute("RainbowSkin") == true
	if isRainbow then return end

	-- 발광색 = 스킨 색(참격 색과 동일). 없으면(원본) 검정 검광.
	local glowColor = Tool:GetAttribute("SkinColor") or Color3.fromRGB(15, 15, 15)
	for _, p in ipairs(glowParts) do
		if on then
			p.Material = Enum.Material.Neon
			p.Color = glowColor
		else
			local orig = glowOriginals[p]
			if orig then
				p.Material = orig.Material
				p.Color = orig.Color
			end
		end
	end
end

-- 카운터 자세 애니 정지 헬퍼
local function stopCounterAnim()
	if counterTrack then
		counterTrack:Stop(0.1)
		counterTrack = nil
	end
end

-- 자세 정리(공통): 발광/애니/이동속도 원복. 쿨다운은 건드리지 않음.
local function clearStance()
	setGlow(false)
	stopCounterAnim()
	-- 🏃 [2026-09-12] WalkSpeedManager 로 이관.
	--   [왜] 이 주석 아래 [COUNTER-SPEED-LEAK] 이력이 정확히 이 문제였다 —
	--     복원이 한 번 새면 다음 진입이 '이미 절반인 값'을 기준으로 또 절반을 만들어
	--     16 → 8 → 4 → 2 로 원래 값이 영영 사라졌다.
	--     배율로 등록하면 기준값을 이 스크립트가 알 필요가 없어 그 실패가 불가능해진다.
	--   ⚠️ 다운 클램프는 관리자가 base 를 그대로 두므로 DownSystem 이 알아서 한다.
	if _G.WalkSpeed and Char then
		_G.WalkSpeed.clear(Char, "KatanaCounter")
		savedWalkSpeed = nil
		return
	end
	-- 폴백: 관리자가 없으면 기존 방식
	if Hum and savedWalkSpeed then
		Hum.WalkSpeed = savedWalkSpeed
		if Hum.Parent and Hum.Parent:GetAttribute("Downed") then Hum.WalkSpeed = 16 * 0.25 end
		savedWalkSpeed = nil
	elseif Hum and Hum.WalkSpeed > 0 and Hum.WalkSpeed < 16 then
		if not (Hum.Parent and Hum.Parent:GetAttribute("Downed")) then
			Hum.WalkSpeed = 16
		end
	end
end

-- 카운터 자세 발동 (한 번 누르면 강제 지속, 취소 불가)
local function enterCounter()
	if counterReady or counterCooling then return end
	if not Char or not Hum or Hum.Health <= 0 then return end
	counterReady = true
	counterSession = counterSession + 1
	local mySession = counterSession

	-- 이동 둔화 (자세 중 노출 리스크)
	-- 🏃 [2026-09-12] WalkSpeedManager 로 이관 — 위 clearStance 주석 참조.
	--   절대값 대신 배율을 등록하므로 "원래 값이 뭐였나"를 이 스크립트가 몰라도 된다.
	if _G.WalkSpeed and Char then
	-- 🏷️ [2026-09-14] 자세 중임을 캐릭터 속성으로 복제한다 — 킹 화면의 표식이 이걸 읽는다.
	--   [왜 flags 인가] 이미 이 자세가 WalkSpeedManager 에 "KatanaCounter" 로 등록된다.
	--     같은 source 에 표식을 얹으면 **해제가 한 곳으로 묶인다** — clearStance 의 clear()
	--     하나가 감속과 표식을 같이 내린다. 속성을 따로 관리하면 해제 경로가 둘이 되고,
	--     오늘 내내 본 "끄는 코드에 도달을 못 해 상태가 고착"이 재발할 자리가 생긴다.
	--   ⚠️ 세 번째 인자 COUNTER_HOLD_TIME 은 매니저 소유 만료다. clearStance 가 어떤
	--     이유로든 도달 못 해도 자세 지속 뒤에는 반드시 풀린다(이중 안전망).
		_G.WalkSpeed.set(Char, "KatanaCounter", {
			walk  = COUNTER_SLOW,
			flags = { "KatanaCounter" },
		}, COUNTER_HOLD_TIME)
	else
		-- 폴백: 관리자가 없으면 기존 방식(savedWalkSpeed 덮어쓰기 금지 가드 포함)
		if savedWalkSpeed == nil then
			savedWalkSpeed = Hum.WalkSpeed
		end
		Hum.WalkSpeed = savedWalkSpeed * COUNTER_SLOW
	end
	setGlow(true)
	-- 카운터 사용(자세 진입) 사운드
	local readySound = Handle:FindFirstChild("CounterReadySound")
	if readySound then readySound:Play() end
	-- 카운터 자세 애니 루프 재생
	local animator = Hum:FindFirstChildOfClass("Animator")
	if animator then
		stopCounterAnim()
		counterTrack = animator:LoadAnimation(animFor(CounterAnim, CounterAnimR6))
		-- 🎬 [2026-09-14] Action → Action2. 봇 공격 애니에 눌리던 것을 고친다.
		--   [증상] 봇 카운터 시 칼날 발광·효과음만 나오고 자세가 안 보였다(실측 09-14).
		--   [원인] RunnerBotDriveController:500 의 공격 애니가 **같은 Action** 이고
		--     봇은 성문·킹을 계속 때린다. 같은 우선순위는 나중에 Play 한 쪽이 이기므로
		--     자세가 켜지자마자 다음 타격에 덮였다. 걷기(Movement)는 원인이 아니다.
		--   ⚠️ 캐시 지연(AnimPrewarm)도 후보였지만 예열을 넣은 뒤에도 안 보여 배제됐다.
		--   [짝] playSwingAnim 은 Action3 로 올렸다. 한쪽만 바꾸면 참격이 자세에 눌린다.
		counterTrack.Priority = Enum.AnimationPriority.Action2
		counterTrack.Looped = true
		counterTrack:Play(0.15)
	end

	-- HOLD_TIME 후에도 여전히 이 세션의 자세가 유지 중이면 = 불발.
	-- 자세 해제 + 쿨다운(헛치면 크게 손해).
	task.delay(COUNTER_HOLD_TIME, function()
		if not counterReady or counterSession ~= mySession then return end  -- 이미 성공/교체됨
		counterReady = false
		counterCooling = true
		clearStance()
		task.delay(COUNTER_COOLDOWN, function()
			counterCooling = false
		end)
	end)
end

-- 카운터 발동: 푸시툴이 이 캐릭터를 밀치려 할 때 PushTool이 호출.
-- 성공 시 true 반환 → 푸시툴은 이 대상 밀치기를 건너뜀.
-- ⚔️ [2026-09-12] 봇용 서버 참격. 유저는 기존 클라 경로(CounterClient)를 그대로 쓴다.
--   [왜] 참격은 CounterRemote:FireAllClients 로 보내지만, 받는 CounterClient 는
--     무기 안 LocalScript 다. 봇 툴의 LocalScript 는 실행되지 않고, 킹은 카타나를
--     안 들었으니 CounterClient 자체가 아무 데서도 안 돈다 → 신호만 나가고 아무도 안 그림.
--     (실측 2026-09-12: 봇 카운터는 막혔는데 참격 이펙트가 안 보임)
--   [해결] 서버가 직접 그린다. 월드 오브젝트라 전원에게 복제된다.
--   [값] CounterClient 와 동일 — SLASH_LIFE 0.4, 같은 페이드 곡선, 같은 배치 공식.
--     ⚠️ 둘이 달라지면 "유저가 쓸 때와 봇이 쓸 때 참격이 다르다"가 된다.
--     수정할 일이 생기면 양쪽을 같이 고칠 것.
--   ⚠️ 스킨 분기는 안 태운다. 봇은 스킨이 없어 원본 초승달(KatanaSlashTemplate)만 쓴다.
local SLASH_LIFE = 0.4
-- ⚠️ 이 스크립트엔 ReplicatedStorage 선언이 없었다. 참격 템플릿을 여기서 찾으므로 추가.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function slashFadeServer(a)
	if a < 0.6 then return a * 0.15 end
	local t = (a - 0.6) / 0.4
	return 0.09 + t * 0.91
end

local function drawServerSlash(fromPos, toPos)
	local template = ReplicatedStorage:FindFirstChild("KatanaSlashTemplate")
	if not template then
		warn("⚔️ [Katana] ReplicatedStorage.KatanaSlashTemplate 없음 — 봇 참격 미표시")
		return
	end
	local dir = toPos - fromPos
	if dir.Magnitude < 0.1 then return end
	local mid = fromPos:Lerp(toPos, 0.35) + Vector3.new(0, 2.5, 0)

	local fx = template:Clone()
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.01 then flatDir = Vector3.new(0, 0, -1) end
	flatDir = flatDir.Unit
	local yawCF = CFrame.lookAt(mid, mid + flatDir)
	local cf = yawCF * CFrame.Angles(math.rad(0), -90, -10)   -- CounterClient:448 과 동일
	if fx:IsA("BasePart") then
		fx.CFrame = cf; fx.Anchored = true; fx.CanCollide = false
	else
		fx:PivotTo(cf)
	end
	-- ⚠️ 판정에 끼지 않게. 지면 레이캐스트·Touched 오염 방지.
	for _, d in ipairs(fx:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		end
	end
	if fx:IsA("BasePart") then
		fx.CanQuery = false; fx.CanTouch = false
	end
	fx.Parent = workspace

	local fades = {}
	local function collect(inst)
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			table.insert(fades, { obj = inst, base = inst.Transparency })
		end
	end
	collect(fx)
	for _, d in ipairs(fx:GetDescendants()) do collect(d) end

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < SLASH_LIFE and fx.Parent do
			local a = (os.clock() - t0) / SLASH_LIFE
			local f = slashFadeServer(a)
			for _, rec in ipairs(fades) do
				rec.obj.Transparency = rec.base + (1 - rec.base) * f
			end
			task.wait()
		end
		if fx and fx.Parent then fx:Destroy() end
	end)
	-- ⚠️ 안전망: 루프가 끊겨도 월드에 남지 않게.
	Debris:AddItem(fx, SLASH_LIFE + 2)
end

local function doCounter(taggerChar)
	if not counterReady then return false end
	if not Char or not Hum or Hum.Health <= 0 then return false end
	if not taggerChar then return false end
	local tHum = taggerChar:FindFirstChildOfClass("Humanoid")
	if not tHum or tHum.Health <= 0 then return false end

	-- 자세 종료 + 쿨다운 진입 (성공)
	counterReady = false
	counterSession = counterSession + 1  -- 불발 타이머 무효화
	counterCooling = true
	clearStance()

	-- 휘두름 동작 재생 (참격 비주얼과 함께, 순간 반격이라 빠르게)
	playSwingAnim(1.6)

	-- 태거에게 데미지 + 크레딧
	TagHumanoid(tHum, Plyr or Char)   -- 🏷️ 봇이면 캐릭터 모델
	if _G.IsDamageImmune and _G.IsDamageImmune(tHum.Parent) then return end
	tHum:TakeDamage(COUNTER_DAMAGE)
	-- 🔢 카운터는 crit=true (금색·큰 글씨). 성공 보상이 눈에 띄어야 한다.
	if _G.ShowDamage and Plyr then
		local tRoot = taggerChar:FindFirstChild("HumanoidRootPart")
		_G.ShowDamage(Plyr,
			(_G.DisplayDamage and _G.DisplayDamage(tHum.Parent, COUNTER_DAMAGE)) or COUNTER_DAMAGE,
			tRoot and tRoot.Position, true)
	end

	-- 태거 스턴: 이동/점프 봉쇄 + Stunned 속성(푸시툴 발사 차단용)
	-- 🛡️ [2026-09-02] CC 면역 중이면 스턴은 건너뛴다(TaggerCcGuard). 데미지는 그대로 들어간다 —
	--   카운터 성공의 보상을 통째로 지우지 않기 위해서다.
	if not (_G.IsCcImmune and _G.IsCcImmune(taggerChar)) then
	-- 🏃 [2026-09-13] 이동·점프·표식을 source 하나로 묶는다 (WalkSpeedManager).
	--   [이전 사고] tSpeed = tHum.WalkSpeed 스냅샷 방식이었다. 히어로봇 카운터 2발이
	--     0.08초 차로 들어가자 ②가 '이미 0 인 값'을 저장했고, ①이 14 로 되돌린 뒤
	--     ②가 0 으로 덮어 킹이 13초간 정지했다(실측 04.207/04.289 → 04.724/04.806).
	--   [왜 토큰이 아니라 매니저인가] 처음엔 만료 토큰을 붙였는데, 그러면 같은 토큰 코드가
	--     HammerHigh · TaggerCcGuard 와 함께 세 벌이 된다. "같은 source 는 갱신"이라는
	--     매니저 규칙이 토큰이 하던 일("마지막 것만 이긴다")을 그대로 해준다.
	--   ⚠️ Stunned 는 소유자가 셋이다(여기 · PushTool.Server · ThroneExhaustSystem).
	--     매니저에 맡겨야 '먼저 끝난 쪽이 남의 표식을 끄는' 경로가 사라진다. 표식이
	--     일찍 꺼지면 TaggerCcGuard 가 CC 지속을 짧게 재서 면역과 HP 피해감소(1.43×)가
	--     같이 일찍 풀린다 — 킹은 아직 묶여 있는데 보호만 먼저 꺼진다.
	--   ⚠️ 점프 봉쇄는 JumpHeight 다. 예전 `tHum.JumpPower = 0` 은 죽은 줄이었다 —
	--     UseJumpPower = false 라 JumpPower 대입은 점프에 아무 영향이 없다(실측).
	--     즉 이 스턴은 그동안 이동만 막고 점프는 못 막았다. 이제 실제로 막힌다.
	--   ⚠️ source 를 시전자별로 나눈다. 히어로봇 4체가 전부 카타나를 들 수 있으므로
	--     키를 합치면 먼저 예약된 만료가 아직 유효한 남의 스턴까지 풀어버린다
	--     (실측 2026-09-13: 0.08초 차 2발에서 둘째가 0.42초 손실).
	--   ⚠️ 만료를 매니저에 맡긴다. 여기서 task.delay 를 걸면 라운드 종료·무기 회수로
	--     Tool 이 파괴될 때 콜백이 함께 회수돼 킹이 0 인 채로 남는다.
	local stunSource = "KatanaStun:" .. ((Plyr and Plyr.Name) or (Char and Char.Name) or "?")
	if _G.WalkSpeed then
		_G.WalkSpeed.set(taggerChar, stunSource, {
			walk  = 0,
			jump  = 0,
			flags = { "Stunned" },
		}, COUNTER_STUN)
	else
		-- 폴백: 관리자가 없으면 기존 방식(겹침 보호 없음)
		taggerChar:SetAttribute("Stunned", true)
		tHum.WalkSpeed  = 0
		tHum.JumpHeight = 0
		task.delay(COUNTER_STUN, function()
			if not (tHum and tHum.Parent) then return end
			tHum.WalkSpeed  = 16
			tHum.JumpHeight = 7.2
			if taggerChar then taggerChar:SetAttribute("Stunned", nil) end
		end)
	end
	end

	-- 카운터 성공 사운드 (서버 재생 → 전원에게 들림)
	local hitSound = Handle:FindFirstChild("CounterHitSound")
	if hitSound then hitSound:Play() end

	-- 카운터 성공 연출: 클라에 참격 이펙트 신호 + 러너/태거 위치 전달.
	-- 참격은 러너(Char)와 태거(taggerChar) 사이에 그림 → 모든 클라가 봄.
	local runnerRoot = Char:FindFirstChild("HumanoidRootPart")
	local taggerRoot = taggerChar:FindFirstChild("HumanoidRootPart")
	if runnerRoot and taggerRoot then
		-- 스킨 색(있으면)을 함께 전송 → 참격을 그 색으로 칠함
		local skinColor = Tool:GetAttribute("SkinColor")
		local isRainbow = Tool:GetAttribute("RainbowSkin") == true
		CounterRemote:FireAllClients("CounterSlash", runnerRoot.Position, taggerRoot.Position, skinColor, isRainbow)
		-- 🤖 봇이면 위 신호를 받을 CounterClient 가 없다 → 서버가 직접 그린다.
		--   ⚠️ 유저일 때는 부르지 않는다. 두 번 그려져 겹친다.
		if not Plyr then
			drawServerSlash(runnerRoot.Position, taggerRoot.Position)
		end
	end
	-- 본인 버튼 번쩍용 신호
	if Plyr then
		CounterRemote:FireClient(Plyr, "CounterSuccess")
	end

	-- 쿨다운
	task.delay(COUNTER_COOLDOWN, function()
		counterCooling = false
	end)

	return true
end

-- 클라 입력 수신: 카운터 자세 발동 (한 번 누름, 강제 지속이라 취소 없음)
CounterRemote.OnServerEvent:Connect(function(player, action)
	if player ~= Plyr then return end
	if action == "Activate" then
		enterCounter()
	end
end)

-- 🤖 [③ 2026-09-12] 봇 전용 진입점. 이름 규약은 "BotSkill".
--   [연출] enterCounter 가 자세 애니·칼날 발광·진입음을 전부 서버에서 재생하고,
--     성공 시 doCounter 가 발도 애니(playSwingAnim 1.6배)와 참격 VFX를 낸다.
--     셋 다 Plyr 를 안 쓴다 — 유저와 똑같은 동작이 그대로 나온다.
--     ⚠️ 참격 VFX 는 FireAllClients 라 모두에게 보인다. 봇이라고 빠지지 않는다.
--
--   [왜 "쓸 수 있으면 쓴다" 로 충분한가]
--     카운터는 '밀치기'에 반응한다 — 강타만이 아니라 평타도 막는다(PushTool 이 doCounter 를 부른다).
--     봇은 접촉 사거리 안에서만 이 함수를 부르는데, 그 거리면 킹이 평타 쿨(1초)로
--     계속 때리는 중이다. 자세 1.5초 안에 밀치기가 올 확률이 충분히 높다.
--   ⚠️ 헛치면 쿨 6초 + 자세 중 이동 50% 라 손해가 크다. 실전에서 헛치는 비율이 높으면
--     "킹이 차징 중일 때만"(PushCharging 속성 감시)으로 좁힐 것 — 그 신호는 이미 있다.
--   ⚠️ 자세 중에는 평타가 막힌다(Activated 의 counterReady 가드). 그것도 유저와 같다.
local botSkill = Instance.new("BindableFunction")
botSkill.Name = "BotSkill"
botSkill.OnInvoke = function()
	if counterReady then return true end    -- 자세 유지 중 = 스킬 사용 중
	if counterCooling then return false end -- 쿨 → 평타로 넘긴다
	if not Char or not Hum or Hum.Health <= 0 then return false end
	enterCounter()
	return true
end
botSkill.Parent = Tool

-- 푸시툴이 호출할 전역 연동 헬퍼 (per-character).
-- 캐릭터에 함수를 매달아 PushTool이 찾도록.
local function registerGlobal()
	if not Char then return end
	_G.katanaCounters = _G.katanaCounters or setmetatable({}, {__mode = "k"})
	_G.katanaCounters[Char] = doCounter
end

local function unregisterGlobal()
	if Char and _G.katanaCounters then
		_G.katanaCounters[Char] = nil
	end
end

local function Equipped()
	Char = Tool.Parent
	Hum  = Char:FindFirstChildOfClass("Humanoid")
	Plyr = Players:GetPlayerFromCharacter(Char)
	registerGlobal()
end

local function Unequipped()
	canDamage = false
	-- 무기 내려놓으면 자세 강제 정리 (쿨다운 타이머는 그대로 흐름)
	if counterReady then
		counterReady = false
		counterSession = counterSession + 1
		clearStance()
	end
	unregisterGlobal()
end

Tool.Activated:Connect(ActivatedSafe)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)
Handle.Touched:Connect(Blow)

-- ═══ 비상 이동 복원 (라운드 종료 회수 대응) ═══
-- 스킬 시전 중(WalkSpeed 0 등) 툴 파괴/회수 시 복원 코드 미실행 → 영구 정지 방지.
local function emergencyMobilityRestore()
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
