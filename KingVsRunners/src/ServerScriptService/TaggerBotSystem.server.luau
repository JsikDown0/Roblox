-- TaggerBotSystem — 1인 서버 태거 봇 "KING" (Phase 1: Stage 1 투척)
-- RoundSystem이 호출: _G.TaggerBot.startForRound(mapFolder, runnerCount) / _G.TaggerBot.stop()
-- 티어 랜덤(easy 50 / normal 35 / hard 15):
--   easy   : 오차 중간 | stone, Wooden Barrel, Wood Log
--   normal : 오차 중간 | Spear(오차1.5x·쿨9s), Wood Log, Wooden Barrel, bear_trap
--   hard   : 오차 작음 | Wooden Barrel, tsunami, BlackHole, tox_box + hard_face/붉은톤/king aura
-- Stage 2 진입(_G.Stage2TriggerSystem.isActive) 시 투척 중지 (Phase 2에서 PushTool 결투 예정)
-- 발동 경로: 기본 투척류=_G.BotSpawnItem(의사 player) / 나머지=_G.throwSpear 등 서버 인터페이스

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")


-- ── 어그로(위협) 시스템 ─────────────────────────────────
-- KING을 때린 대상에게 딜량 비례 위협 점수 적립(반감기 감쇠).
-- 타겟 스코어 = 거리 × AI가중 ÷ (1 + 위협 × 티어 민감도) — "때린 놈을 본다".
-- 숨어서 막타만 노리면 KING은 자길 때리는 농민을 정리하고,
-- 유저가 딜을 넣는 순간 큰 딜량이 농민의 잔딜을 압도해 시선이 유저에게 돌아간다.
local THREAT_HALF_LIFE = 4   -- 위협 반감기(초)
local THREAT_SENS = { easy = 0.04, normal = 0.08, hard = 0.12 }  -- 티어별 민감도
-- 🏅 [2026-09-01] 마지막 '실제 가해자' — 물벽 막타 시 크레딧을 넘겨줄 대상.
--   [왜 필요한가] 물벽은 creator 태그 없이 TakeDamage 를 부른다. 그 한 방이 막타면
--     "막타 불명"이 되어 킬로그·퀘스트·리더보드가 전부 비어버린다.
--     실측(12:14 판): 러너가 892 → 31 (96%)까지 깎았는데 마지막 31 을 물벽이 가져가
--     아무에게도 크레딧이 안 갔다. 그 판은 킹이 전멸승 직전이라 승패까지 뒤집혔다.
--   ⚠️ 유효 시간을 둔다. 오래 전에 때린 사람에게 크레딧이 가면 그게 더 이상하다.
--   ⚠️ Player 일 수도 Model(AI 러너) 일 수도 있다. 소비하는 쪽에서 분기할 것.
local lastAttacker, lastAttackerAt = nil, 0
local CREDIT_WINDOW = 8   -- 마지막 피격이 이 시간 안이어야 크레딧을 넘긴다(초)
local threatTable = {}       -- [characterModel] = { score, last }
-- 🎯 [2026-09-09] 사거리 밖 피격 대응 훅. 실체는 파일 아래(상수 선언 뒤)에서 채운다.
--   ⚠️ addThreat 는 이 파일 최상단에 있는데 SWING_RANGE·holdLineX 등은 800~900행대다.
--     forward 선언 없이 직접 쓰면 nil 참조로 죽는다.
local sallyOnDamage = nil

local function addThreat(char, amount)
	if not char or not amount or amount <= 0 then return end
	local now = os.clock()
	-- 🎯 [2026-09-09] 사거리 밖 피격 누적 → 출격 판단.
	--   ⚠️ 실제 판단은 sallyOnDamage 에 있다. 이 함수(52행)가 필요한 상수·상태보다
	--     훨씬 위에 있어서 여기서 직접 쓰면 nil 참조로 죽는다(실측으로 확인).
	--     forward 선언한 훅 변수를 통해 호출한다 — 아래에서 채워진다.
	if sallyOnDamage then sallyOnDamage(char, amount) end
	local e = threatTable[char]
	if e then
		e.score = e.score * 0.5 ^ ((now - e.last) / THREAT_HALF_LIFE) + amount
		e.last = now
	else
		threatTable[char] = { score = amount, last = now }
	end
end

local function getThreat(char)
	local e = threatTable[char]
	if not e then return 0 end
	return e.score * 0.5 ^ ((os.clock() - e.last) / THREAT_HALF_LIFE)
end

_G.BotAddThreat = addThreat  -- 외부 훅 (농민 딜 등 creator 태그 없는 경로용)


local TEMPLATE_FOLDER = "TaggerBot"
local MODEL_NAME = "King npc2"
local AURA_NAME = "king aura"
local GRACE_TIME = 8          -- (폴백) 라운드 시작 후 발사 유예(초)
-- 티어별 발사 유예. 이전에는 전 난이도 8초 고정이라 불기둥(10초)과 거의 동시에 시작해
-- 초반이 한가했다. easy/normal 을 앞당겨 압박이 일찍 걸리게 한다.
-- hard 는 원래도 충분히 위협적이라 그대로 둔다(더 당기면 스폰 직후 몰살 위험).
local GRACE_BY_TIER = {
	easy   = 4,   -- 8 → 4
	normal = 3,   -- 8 → 3
	hard   = 6,   -- 8 → 6 (오차 작음·쿨 짧음이라 과하게 당기면 스폰 직후 몰살)
}
local HARD_RED_TINT = 0.35    -- 하드 얼굴 붉은톤 강도(0~1)

local TIERS = {
	-- 🎯 [개편 2026-08-31] 티어별 아이템 재구성.
	--   [문제] 세 티어 모두 실제 처치 수단이 굴리기뿐인데, 상위 티어가 그걸 버리고
	--     미검증 아이템으로 갈아타는 '전면 교체식'이라 서열이 뒤집혀 있었다.
	--     실측 서열: hard ≲ easy > normal (설계 의도는 easy < normal < hard)
	--   [normal 이 easy 보다 약했던 이유] Spear 명중률 25%(8회 중 2), bear_trap 포획
	--     0~2/5개. 전역 쿨이 있으니 저효율 아이템이 굴리기의 발사 기회를 뺏는다.
	--   [hard 가 약했던 이유] 4종 중 tsunami·BlackHole 이 데미지 0(처치 기여 0 실측),
	--     tox_box 는 '이전 박스가 러너 베이스에 닿아야' 풀리는 비결정론적 잠금이라
	--     8회 요청 중 6회 거부(75%). 실질적으로 '배럴 하나 + 낭비 슬롯 3개'였다.
	--   ⚠️ cd 를 여기에 쓰지 않는다. ItemSpawnHandler.ITEM_COOLDOWN 을 그대로 읽는다
	--     (Demonspear 8 / EnergyBall 12 / tsunami 6 / BlackHole 7 / 나머지 3).
	--     비중은 cd 가 아니라 weight 로 조절한다 — 두 축을 분리했다.
	-- 🎯 [상향 2026-09-05] easy·normal 의 aimError 12 → 9 / 7. hard(4)는 그대로.
	--   [증상] 봇 킹의 1단계 처치가 0~2/11 이었다(유저 킹은 같은 조건에서 6/10).
	--   [원인] 발사 횟수는 정상이었다 — easy 기준 46초에 8회로 fireInterval(4.5)
	--     이론치와 거의 일치. 즉 던지긴 던지는데 안 맞았다. 병목은 빈도가 아니라 명중률.
	--   ⚠️ easy 와 normal 의 aimError 가 둘 다 12 로 '같았다'. 두 티어의 명중률 차이가
	--     0 이었고 발사 간격(4.5 vs 3.2)만 달랐다 — 서열이 흐릿했던 이유다.
	--     08-31 개편이 뒤집힌 서열(hard ≲ easy > normal)을 고친 자리라, 여기서도
	--     easy > normal > hard 순으로 오차가 줄도록 간격을 벌린다.
	--   ⚠️ fireInterval 은 건드리지 않는다. 08-31 주석의 "빈도(cd)와 비중(weight)을
	--     분리한다" 원칙대로 한 번에 한 축만 본다. 이 변경으로도 부족하면 그때 빈도를 본다.
	--   ⚠️ easy 는 뉴비가 만나는 50% 구간이다(NEWBIE-TIER 로 hard 를 배제하는 이유).
	--     hard 수준(4)으로 올리지 않고 9 에 둔 건 첫 판 이탈을 막기 위한 여유다.
	{ name = "easy",   weight = 50, aimError = 9, fireInterval = 4.5,
	  -- 뉴비 태거의 기본 로드아웃과 같은 구성. 굴리기 3종만 — 이 컨셉은 유지한다.
	  items = {
		{ item = "stone" },
		{ item = "Wooden Barrel" },
		{ item = "Wood Log" },
	  } },
	{ name = "normal", weight = 35, aimError = 7, fireInterval = 3.2,
	  -- 굴리기 우세(67%)를 유지해 easy 보다 약해지지 않게 하고, 위협 종류만 늘린다.
	  items = {
		{ item = "Wooden Barrel", weight = 3 },  -- 점프 봉인 + 반경 35 리워크 반영
		{ item = "ItemNoob",      weight = 3 },  -- 굴리기 계열(지그재그) — 명중률 별도 관찰 필요
		{ item = "Spear", errMul = 1.5, weight = 2 },  -- 즉사기 안전장치: 오차 1.5배
		{ item = "Demonspear",    weight = 1 },  -- 착탄 즉사 + 잔불. 잠금 최대 4.1초 < cd 8
	  } },
	{ name = "hard",   weight = 15, aimError = 4,  fireInterval = 2.5,
	  -- 살상기 75% / 제어기 25%. 제어기는 '판을 짜는' 역할이라 비중을 낮게 둔다.
	  -- ⚠️ tsunami·BlackHole 은 데미지가 0 이다. 지금은 후속타 연계 로직이 없어서
	  --   모아놓고 다음 아이템이 딴 게 나오면 그대로 흘러간다. 하드가 여전히 약하면
	  --   여기부터 볼 것 — weight 를 더 줄이거나 연계 로직을 붙여야 한다.
	  items = {
		{ item = "Wood Log",   weight = 3 },
		{ item = "EnergyBall", weight = 3 },  -- 즉발 장거리 관통, 유저 쿨 12로 가장 강한 제약
		{ item = "BlackHole",  weight = 1 },
		{ item = "tsunami",    weight = 1 },
	  } },
}

-- ── 상태 ─────────────────────────────────────────────
-- ── [FROZEN-SELFHEAL] Ice Bow 동결 안전망 ────────────────────
-- Ice Bow(FREEZE_DURATION=3s)의 해제는 Tool 스크립트의 task.delay 로 예약되는데,
-- 탄약 소진 0.3초 뒤 Tool:Destroy 가 돌면 그 스레드가 같이 죽어 해제가 영영 안 온다.
-- Frozen 을 지우는 곳이 Ice Bow / TestCommands 뿐이고 라운드 경계 정리도 없어서,
-- 한 번 새면 봇이 라운드 내내 무력화된다(실측 2026-08-20: 69초간 소환·이동·2단계 전무).
-- 근본 수정은 Ice Bow 쪽이고, 아래 값은 봇이 통째로 죽는 것만 막는 하한선이다.
-- MAX_HOLD 는 FREEZE_DURATION(3) 보다 넉넉히 크게 — 정상 동결을 끊지 않도록.
local FROZEN_WARN_AFTER = 4    -- 이 초를 넘겨 지속되면 1회 경고 (정상은 3초)
local FROZEN_MAX_HOLD   = 8    -- 이 초를 넘기면 해제 누락으로 보고 강제 해제

local activeBot = nil        -- 현재 봇 모델
local activeTier = nil       -- 현재 티어 설정
local botRunning = false     -- AI 루프 플래그
local itemLastFired = {}     -- [itemName] = tick (아이템별 쿨)
local pseudoPlayer = nil     -- 아이템 시스템에 넘길 의사 player

-- ── 티어 추첨 ────────────────────────────────────────
local forcedTier = nil   -- dev 강제 티어 (/kingtier 명령, nil=랜덤)

-- [NEWBIE-TIER] 신규 유저 보호: 누적 라운드가 이 값 미만이면 hard 를 배제한다.
--   근거: 티어는 easy50/normal35/hard15 랜덤이라 첫 판에 15% 확률로 hard 를 만난다.
--   hard 는 grabChance 0.5 + aimError 4 라, 기본 지급 무기(ClassicSword)만 든
--   신규 유저에게는 "뭘 잘못했는지도 모르는 채 계속 잡히는" 경험이 된다.
--   ⚠️ 리텐션 목적이므로 숙련자 판(5판 이상)은 전혀 건드리지 않는다.
local NEWBIE_ROUNDS = 5

-- 참여자 중 한 명이라도 신규면 보호를 적용한다.
--   여럿이 있을 때 신규 한 명 때문에 난이도가 내려가는 건 의도된 절충 —
--   신규가 첫 판에서 이탈하는 손실이 숙련자가 easy 를 만나는 손실보다 크다.
local function hasNewbie()
	for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
		local rp = pl:GetAttribute("RoundsPlayed")
		-- 속성이 없으면(데이터 로드 전) 신규로 간주 — 보수적으로 보호하는 쪽.
		if rp == nil or rp < NEWBIE_ROUNDS then return true end
	end
	return false
end

local function pickTier()
	if forcedTier then
		for _, t in ipairs(TIERS) do
			if t.name == forcedTier then return t end
		end
	end
	-- [NEWBIE-TIER] hard 제외 후 나머지 가중치로만 추첨.
	--   easy50/normal35 → 실질 59%/41%
	local newbie = hasNewbie()
	local pool = {}
	for _, t in ipairs(TIERS) do
		if not (newbie and t.name == "hard") then pool[#pool + 1] = t end
	end
	if #pool == 0 then pool = TIERS end   -- 안전망: 전부 걸러지면 원본 사용
	local total = 0
	for _, t in ipairs(pool) do total += t.weight end
	local roll = math.random() * total
	for _, t in ipairs(pool) do
		roll -= t.weight
		if roll <= 0 then
			if newbie then
				print("[TaggerBot] 신규 보호 적용 — hard 배제, 선정: " .. t.name)
			end
			return t
		end
	end
	return pool[1]
end

-- ── 얼굴/외형 적용 ───────────────────────────────────
local function applyLook(bot, tier)
	local head = bot:FindFirstChild("Head")
	if not head then return end
	local easyFace = head:FindFirstChild("easy_normal_face")
	local hardFace = head:FindFirstChild("hard_face")
	local isHard = (tier.name == "hard")
	if easyFace then easyFace.Transparency = isHard and 1 or 0 end
	if hardFace then hardFace.Transparency = isHard and 0 or 1 end
	if isHard then
		-- 약간 붉어진 얼굴
		head.Color = head.Color:Lerp(Color3.fromRGB(255, 60, 40), HARD_RED_TINT)
		-- king aura 이펙트만 부착: aura 파트 이름 = 봇 R15 파트 이름 대응
		local folder = ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
		local aura = folder and folder:FindFirstChild(AURA_NAME)
		if aura then
			for _, ap in ipairs(aura:GetChildren()) do
				local target = bot:FindFirstChild(ap.Name)
				if target and ap:IsA("BasePart") then
					for _, fx in ipairs(ap:GetChildren()) do
						if fx:IsA("ParticleEmitter") or fx:IsA("Beam") or fx:IsA("Trail")
							or fx:IsA("PointLight") or fx:IsA("Attachment") then
							fx:Clone().Parent = target
						end
					end
				end
			end
		end
	end
end

-- ── 봇 스폰 ──────────────────────────────────────────
-- 👑 [2026-08-29] 봇 킹 HP 는 유저 태거와 같은 공식을 쓴다: 150 × 환산, 상한 1600.
--   AI 러너는 유저보다 화력이 낮아 0.55 로 환산한다
--   (봇 DPS 10 / 유저 18.8 실측. Stage2TriggerSystem 의 aliveWeight 와 같은 계수).
--   ⚠️ 러너가 유저인 판에서는 이 가중치가 과소평가다. 봇 킹은 솔로/테스트 위주라
--     지금은 일괄 0.55 로 둔다. 유저 러너 + 봇 킹 조합이 흔해지면 분리할 것.
local BOT_RUNNER_WEIGHT = 0.55

local function spawnBot(mapFolder, runnerCount, tier, soloMode)
	local folder = ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
	local template = folder and folder:FindFirstChild(MODEL_NAME)
	if not template then
		warn("[TaggerBot] 템플릿 없음: ServerStorage." .. TEMPLATE_FOLDER .. "." .. MODEL_NAME)
		return nil
	end

	local bot = template:Clone()
	bot.Name = "KING"
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = (tier.name == "hard") and ("\240\159\148\165 KING") or "KING"  -- 🔥 KING (하드만 특별표시)
		-- 👑 [2026-08-29] HP 공식을 유저 태거와 통일했다.
		--   [문제] 공식이 셋으로 갈라져 있었다:
		--     솔로 봇  150 고정         ← 러너 수와 무관해 밸런스 측정이 불가능
		--     다인 봇  180 + 120×N (600)
		--     유저 태거 150 × 환산 (1600)  ← Stage2TriggerSystem
		--   봇 상대로 무기를 재도 그 값이 실전(유저 태거)에 그대로 안 옮겨졌다.
		--   [해결] 봇도 150 × 환산을 쓴다. 이제 봇 상대 측정 = 실전 측정이다.
		--   ⚠️ AI 러너는 0.55 로 환산한다(봇 DPS 10 / 유저 18.8 실측 비율).
		--     Stage2TriggerSystem 의 aliveWeight 와 같은 계수다. 한쪽만 고치지 말 것.
		--   ⚠️ 여기 값은 '스폰 시점' 기준이라 러너가 아직 다 안 왔을 수 있다.
		--     유저 태거는 성문 붕괴 때 재산정하지만(finalizeTaggerHp) 봇은 그 경로가 없다.
		--     측정 목적에는 스폰 시점 인원으로 충분하다 — 필요해지면 같은 훅을 붙일 것.
		local effN = math.max(1, (runnerCount or 1) * BOT_RUNNER_WEIGHT)
		local hp = math.floor(math.min(1600, 150 * effN))
		hum.MaxHealth = hp
		hum.Health = hp
		print(string.format("👑 [TaggerBot] KING HP: %d (러너 %d × %.2f → 환산 %.1f)%s",
			hp, runnerCount or 1, BOT_RUNNER_WEIGHT, effN,
			soloMode and " [솔로]" or ""))
		-- [COFFIN-POSE] 사망 시 관절을 끊지 않는다.
		--   킹은 Humanoid.Health 가 곧 결투 HP 라, 러너와 달리 킬 이펙트보다 먼저 Died 가 뜬다
		--   (실측 2026-08-20: Died 10:19:05.667 → Death Coffin 05.753, 86ms 차).
		--   기본값 true 면 그 사이 Motor6D 15개가 끊겨 리그가 흩어지고,
		--   코핀 연출에서 자세를 되돌릴 방법이 사라진다.
		--   이 게임의 다른 NPC(noobHum / dragonHum)도 같은 이유로 false 다.
		hum.BreakJointsOnDeath = false
	end
	-- 봇 캐릭터에 Role 속성 부여: ItemDamageSystem이 태거 아이템 면역을 이걸로 판별.
	bot:SetAttribute("Role", "Tagger")
	-- 유저 태거와 동일한 머리 위 HP 바("500 / 500" 수치 표시): TaggerHpDisplay의 NPC 훅이
	-- TaggerDummy 속성 모델에 자동 부착 (workspace.ChildAdded 감시, 0.3s 뒤 적용).
	bot:SetAttribute("TaggerDummy", true)
	-- ── 슈퍼아머 (연속 넉백 감쇠) ─────────────────────────
	-- 러너 여럿의 번갈아 넉백으로 KING이 구석에 몰려 무력화되는 스턴락 방지.
	-- 무기 코드 수정 없이 중앙 감시: HRP 수평 속도 급증(넉백)을 감지해
	-- 1.5초 창 내 2회째부터 속도 50% 감쇠, 3회째부터는 대폭 상쇄(보스 슈퍼아머 관례).
	do
		local hrp = bot:FindFirstChild("HumanoidRootPart")
		if hrp then
			local KB_THRESH  = 40    -- 이 수평 속도 초과 = 넉백 피격으로 간주 (자체 이동 16은 미달)
			local KB_DAMP_1  = 0.6   -- 1타 감쇠 (완전 면역은 아님 — 러너의 밀기 전략을 남겨둠)
			local KB_DAMP_2  = 0.3   -- 2타 감쇠
			local KB_DAMP_3  = 0.08  -- 3타 이상 = 거의 부동
			local KB_WINDOW  = 3.0   -- 연속 판정 창(초). 1.5 → 3.0: 여럿이 번갈아 밀어 창을 리셋하는 걸 막음
			local hits, lastHit = 0, 0
			local RunService = game:GetService("RunService")
			-- 🔬 [진단 2026-09-03] 이 감쇠가 물리 스텝을 넘어 살아남는지 측정한다.
			--   [의심] 여기는 AssemblyLinearVelocity 에 '값을 쓴다'. 그런데 HammerLow 는
			--     LinearVelocity 무버(MaxForce = 질량×10000, 수명 0.15초)로 민다.
			--     무버는 매 물리 스텝마다 목표 속도를 다시 강제하므로, 여기서 쓴 감쇠가
			--     다음 스텝에 그대로 덮어써질 수 있다. 그렇다면 KB_DAMP 값이 얼마든
			--     실제로는 아무 일도 일어나지 않는다 = 슈퍼아머가 해머에 무력.
			--   [읽는 법] '실제'가 '목표'에 가까우면 감쇠가 산 것,
			--     '실제'가 원래 속도로 돌아와 있으면 무버가 이긴 것이다.
			--   [덤] dbgHits 가 0.5초에 1씩만 오르면 문서의 두 번째 가설도 확인된다
			--     (SPIN_TICK 0.25 < 중복방지 0.35 라 카운트가 절반 속도로 오른다).
			--   ⚠️ 확인 끝나면 DBG_KB = false. 끄는 스위치를 같은 편집에 넣어둔다.
			-- ✅ [2026-09-03 결론] 무버 0개 → "감쇠 유지"(목표 26 → 실제 3),
			--   무버 1개 → 7건 전부 "감쇠 무효"(44~45 로 복귀). 대조군까지 나왔으므로 끈다.
			--   결론: AssemblyLinearVelocity 쓰기는 LinearVelocity 무버를 못 이긴다.
			--   ⚠️ 슈퍼아머를 고칠 때 다시 true 로 켜서 수정 전후를 비교할 것.
			-- 🔬 [2026-09-08] 수정 전후 비교를 위해 다시 켰다. 확인 끝나면 false 로.
			local DBG_KB = true
			local dbgPending, dbgTarget, dbgHits, dbgDamp, dbgLastLog = false, 0, 0, 0, 0
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if not (bot.Parent and hrp.Parent) then conn:Disconnect() return end
				local v = hrp.AssemblyLinearVelocity
				local hv = Vector3.new(v.X, 0, v.Z)
				-- 🔬 지난 프레임에 쓴 감쇠의 결과를 지금(물리 1스텝 뒤) 읽는다.
				if DBG_KB and dbgPending then
					dbgPending = false
					local now2 = os.clock()
					if now2 - dbgLastLog > 0.5 then
						dbgLastLog = now2
						local movers = 0
						for _, d in ipairs(hrp:GetChildren()) do
							if d:IsA("LinearVelocity") or d:IsA("BodyVelocity") or d:IsA("VectorForce") then
								movers += 1
							end
						end
						print(string.format(
							"🔬 [KB] %d타 감쇠 %.2f | 목표 %.0f → 실제 %.0f | 무버 %d개 → %s",
							dbgHits, dbgDamp, dbgTarget, hv.Magnitude, movers,
							(hv.Magnitude > dbgTarget * 1.5) and "감쇠 무효(되돌려짐)" or "감쇠 유지"))
					end
				end
				if hv.Magnitude > KB_THRESH then
					local now = os.clock()
					if now - lastHit > KB_WINDOW then hits = 0 end
					-- 같은 넉백을 매 프레임 중복 카운트하지 않게: 창 내 재감지는 카운트 유지
					if now - lastHit > 0.35 then
						hits += 1
						lastHit = now
					end
					if hits >= 1 then   -- 1타부터 저항 (예전엔 2타부터라 첫 넉백이 무방비였음)
						local damp = (hits >= 3) and KB_DAMP_3 or (hits == 2 and KB_DAMP_2 or KB_DAMP_1)
						-- 🔧 [2026-09-08] 무버를 직접 줄인다 (09-04 문서 1-1 수정안 적용).
						--   [왜] 아래 AssemblyLinearVelocity 쓰기는 LinearVelocity 무버가 매 물리
						--     스텝마다 목표 속도를 다시 강제해 덮어쓴다(위 2026-09-03 결론).
						--     그래서 KB_DAMP 값이 얼마든 해머에는 아무 일도 일어나지 않았다.
						--   [효과] VectorVelocity = dir*45 + (0,12,0) 이라 수평 넉백과 부양이
						--     같이 줄어든다. Freefall(걷기 봉인)도 같은 수정으로 완화된다.
						--   ⚠️ 무버당 정확히 1회만 적용한다. Heartbeat 는 매 프레임 도는데
						--     매번 곱하면 몇 프레임 만에 0 이 되어 '감쇠'가 아니라 '완전 면역'이
						--     된다. 속성 표식으로 재적용을 막는다.
						--   ⚠️ 아래 Assembly 쓰기는 지우지 말 것 — 무버 없이 속도를 직접 쓰는
						--     넉백(2026-09-03 대조군의 '무버 0개' 케이스)은 그 경로로만 잡힌다.
						for _, d in ipairs(hrp:GetChildren()) do
							if d:IsA("LinearVelocity") and not d:GetAttribute("KbDamped") then
								d:SetAttribute("KbDamped", true)
								d.VectorVelocity = d.VectorVelocity * damp
							end
						end
						hrp.AssemblyLinearVelocity = Vector3.new(hv.X * damp, v.Y, hv.Z * damp)
						if DBG_KB then
							dbgPending, dbgTarget, dbgHits, dbgDamp = true, hv.Magnitude * damp, hits, damp
						end
					end
				end
			end)
		end
	end

	-- 어그로: 피격 시 creator 태그(무기 표준)로 가해자 식별 → 딜량 비례 위협 적립
	threatTable = {}  -- 라운드 시작마다 리셋
	-- ⚠️ 안 지우면 이전 라운드 가해자가 새 판 막타 크레딧을 가져간다.
	lastAttacker, lastAttackerAt = nil, 0
	do
		local bHum = bot:FindFirstChildOfClass("Humanoid")
		if bHum then
			local lastHp  = bHum.Health
			local lastMax = bHum.MaxHealth
			bHum.HealthChanged:Connect(function(h)
				-- 🩹 [버그수정 2026-09-02] HealthChanged 는 '맞았다'가 아니라 'HP 값이 변했다'다.
				--   [증상] 성문 붕괴마다 "[Duel] 킹 피격 -97 → 810/810 (by ?)" 이 찍혔다.
				--     그 순간은 구조상 아무도 킹을 때릴 수 없다. (by ?) = 가해자 없음이
				--     그 증거였다 — 실제 피격에는 항상 creator 태그가 붙는다.
				--   [원인] Stage2TriggerSystem 의 HP 재산정(907 → 810)을 이 관찰자가 피해로
				--     읽었다. 실측 4건 모두 dmg = 907 − 새 MaxHealth 로 정확히 일치했다.
				--   [왜 MaxHealth 비교로는 못 잡았나] 대입이 이벤트를 두 번 만든다.
				--     ① MaxHealth 대입 → h=907(옛 값), MaxHealth=810 → 비교 가드가 여기서 소비된다
				--     ② Health 대입   → h=810, MaxHealth=810 → 이미 같아져 가드가 무력해진다
				--     HP 가 오른 판(907→975)에서 로그가 없던 것도 ②의 dmg 가 음수였기 때문이다.
				--   [해결] 'HP 가 꽉 찬 상태로 끝나는 변화'는 전투가 아니다 — 맞았는데 체력이
				--     최대치인 경우는 성립할 수 없다. 재산정·처형 풀피복구·라운드 원복이 전부
				--     여기 걸리므로, 앞으로 추가될 리셋류도 표식 없이 자동으로 커버된다.
				--   ⚠️ 부분값으로 끝나는 쓰기는 이걸로 못 잡는다(CC 배율 복원 800/960 → 400/480).
				--     그쪽은 TaggerCcGuard 가 HpRewrite 표식을 세워서 건너뛰게 한다.
				--   ⚠️ 로그만의 문제가 아니었다. creator 태그가 살아 있으면 아래 addThreat 이
				--     400~600 짜리 위협을 한 명에게 통째로 꽂는다(라운드 전체 어그로보다 크다).
				if bot:GetAttribute("HpRewrite") or h >= bHum.MaxHealth then
					lastMax = bHum.MaxHealth
					lastHp  = h
					return
				end
				local dmg = lastHp - h
				lastHp = h
				if dmg > 0 then
					-- [Duel] 교전 타임라인 진단
					-- ⚠️ [2026-09-06] OFF. 주석의 "확인 후 제거"를 이제 실행한다.
					--   [왜] warn 이라 Error report 에 경고로 집계됐다. 봇 킹 피격마다 찍혀
					--     28일간 97건. [Duel] 계열 전체(약 6,000건)의 일부이며, 진짜 에러가
					--     이 스팸에 묻혀 안 보였다.
					if false then
						local tag2 = bHum:FindFirstChild("creator")
						local who = "?"
						if tag2 and typeof(tag2.Value) == "Instance" then who = tag2.Value.Name end
						warn(string.format("[Duel] 킹 피격 -%.0f → %.0f/%.0f (by %s)",
							dmg, h, bHum.MaxHealth, who))
					end
					local tag = bHum:FindFirstChild("creator")
					local attacker = tag and tag.Value
					-- 🏅 [2026-09-01] 마지막 '실제 가해자'를 기억한다 (크레딧 이관용).
					--   [왜] 물벽(FirePressureSystem)은 creator 태그 없이 TakeDamage 를 직접 부른다.
					--     환경 압박이라 내구도에 막히면 안 되므로 그게 의도된 동작이다.
					--     그런데 그 한 방이 막타가 되면 creator 가 없어 "막타 불명"으로 끝난다.
					--     실측(12:14 판): 러너가 892 → 31 (96%)까지 깎았는데 마지막 31 을
					--     물벽이 가져가, 킬로그·퀘스트·리더보드에 아무도 안 잡혔다.
					--   ⚠️ '실제 가해자가 있는 피격'에서만 갱신한다. 물벽 피격으로 덮어쓰면
					--     기억이 즉시 지워져 의미가 없다.
					--   ⚠️ 라운드마다 threatTable 과 같이 초기화된다(아래 lastAttacker 선언 참조).
					if typeof(attacker) == "Instance" then
						lastAttacker = attacker
						lastAttackerAt = os.clock()
						if attacker:IsA("Player") and attacker.Character then
							addThreat(attacker.Character, dmg)      -- 유저 무기 (creator=Player)
						elseif attacker:IsA("Model") then
							addThreat(attacker, dmg)                -- 농민 등 NPC (creator=Model)
						end
					end
				end
			end)
		end
	end

	-- 파트 상태: 앵커 해제 + 태거 콜리전
	for _, p in ipairs(bot:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CollisionGroup = "TaggerCharacter"
		end
	end

	applyLook(bot, tier)

	-- 태거스폰 배치
	local spawnPart = mapFolder and (mapFolder:FindFirstChild("taggerspawn") or mapFolder:FindFirstChild("taggerspawn2"))
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	bot.Parent = workspace
	if hrp then
		if spawnPart then
			bot:PivotTo(CFrame.new(spawnPart.Position + Vector3.new(0, 4, 0)))
		end
		hrp:SetNetworkOwner(nil)  -- 물리 서버 소유 (스냅백 방지)
	end
	return bot
end

-- ── 앞당김(lead) 스폰 지점 계산 (bear_trap 전용) ──────
-- 타겟에서 성(봇) 방향으로 leadDist만큼 앞당긴 지점의 지형 표면. 성까지 남은 거리보다 길면 클램프.
-- 굴리는류(stone/Log/Barrel/tsunami): 유저 태거처럼 ItemSpawnPlate(언덕 꼭대기)에서 출발.
--   플레이트 X 고정 + 타겟 러너의 Z 라인에 정렬(오차 포함) → 위에서 굴러/밀려 내려오는 원래 그림.
-- bear_trap: 러너 진행 방향 앞 25 stud 설치 (발밑 즉착 방지, 보고 피할 수 있게).
-- Spear(시전자 원점 직선)/BlackHole(포물선 투척)는 시스템이 자체 처리.
local PLATE_ITEMS = {
	["stone"] = true, ["Wood Log"] = true, ["Wooden Barrel"] = true, ["tsunami"] = true,
	["tox_box"] = true,  -- 플레이트 위치를 넘기면 ToxBox의 hill 클램프가 그 근처 언덕 표면으로 정렬
	-- ⚠️ [버그수정 2026-09-01] ItemNoob 누락. 지그재그 주행(ItemSpawnHandler isAnyNoob)은
	--   멀쩡했는데 출발점이 조준점(=러너 발밑)이라 "갑자기 러너 옆에 튀어나오는" 그림이었다.
	--   실측 스폰 좌표가 X −108 / 196 / 416 처럼 매번 달랐다(배럴은 항상 X 698.9 고정).
	--   계단에서 출발해 지그재그로 내려가야 유저 태거가 쓰는 방식과 같아진다.
	["ItemNoob"] = true,
}
local TRAP_LEAD = 25
local ROLL_MIN_GAP = 15       -- (trap lead용) 봇과의 최소 이격
local activePlate = nil       -- 현재 라운드 맵의 ItemSpawnPlate (startForRound에서 캐싱)
-- 🚪 [2026-08-30] 성문 X. 봇이 이보다 안쪽(+X)으로 들어가지 않는 기준선.
--   ⚠️ startForRound 에서 캡처한다. 성문은 2단계 시작과 함께 파괴되므로 그때는 못 읽는다.
--   ⚠️ 여기서 선언해야 아래 computeApproachPos / retreatPos 가 볼 수 있다(선언 ≺ 사용).
local holdLineX = nil
-- 🌊 물벽 지대 경계에서 이만큼 위(+X)까지만 내려간다. clampToHoldLine 이 읽는다.
--   [6 인 근거] 불기둥 속도 10 stud/s, 지대 판정 틱 0.25초 → 한 틱 전진 2.5 stud.
--     그 두 배 이상이어야 프레임 밀림·지형 굴곡으로 경계를 넘지 않는다.
--   ⚠️ 키우면 킹이 계단에서 더 멀어져 밀기·아이템 사거리를 잃는다. 8 이상은 피할 것.
local FIRE_SAFE_MARGIN = 6


-- 🏆 [2026-08-30] 점령 방어(B선). 성문(A선)이 뚫린 뒤의 2차 수비.
--   [설계] 킹은 성문에서 막는 게 최선이지만(처치 수단이 거기서만 산다),
--     뚫렸으면 주도권은 러너에게 넘어간 것이고 킹은 골문 앞 수비로 전환한다.
--     축구에서 라인을 내리는 것과 같다 — 불리하지만 무력한 건 아니다.
--   ⚠️ [2026-08-31] 게이지 % 임계(50→30%)를 폐기하고 '존 침범 여부'로 바꿨다.
--     [왜] 위 설계는 "라인을 내린다"는 상태 전환인데, 구현은 게이지 비율이라
--       그라디언트였다 — 은유와 코드가 어긋나 있었다.
--     [실측] 30% 에 걸려도 실제 출발은 58% 였다(판3: 48.312 걸림 → 51.112 하강).
--       이별 일격이 강타 예열 2초를 기다렸기 때문. 이동은 별도로 4.7~6.0초 든다.
--       (역산: 하강~완료 구간의 평균 상승률을 감속 공식으로 되풀어 구함)
--     [왜 일찍 가야 하나] 늦게 가면 손해가 눈덩이로 커진다. 존 러너 2명 기준
--       도착 후 남은 시간 = (1-p) x 10 / (r/(r+4)) 이므로
--       10% 도착 27초 / 58% 도착 12.6초 — 두 배 차이다. 그리고 한 명 눕히면
--       r 이 줄어 게이지가 더 느려지고(2명 0.33 → 1명 0.20) 시간이 또 늘어난다.
--     ⚠️ 아래 "늦게 가도 회수가 된다"는 옛 판단은 폐기한다. 회수는 되지만
--       그 사이 킹이 싸울 시간을 잃는다 — 존에서도 소수면 충분히 죽일 수 있다.
--       (PushTool SPLIT_EXP=0.5 → 데미지 = 기본/√n. 선형 분산이 아니다.
--        유저1+봇1 기준 대상당 6.1 DPS = 16초에 한 명)
--   ⚠️ KING_POWER=4 라 킹이 존에 서 있기만 하면 진행이 사실상 멈춘다(1명 50초/2명 30초).
--     그래서 '일찍 가서 오래 버티기'가 최선이 된다.
--   ⚠️ 침범 신호는 CaptureSystem.getActiveZone() 을 그대로 쓴다 —
--     차오르는 중이면 존, 감쇠 중이면 nil 이라 "지금 누가 밟고 있나"와 같은 뜻이다.
--     별도 게터를 만들지 말 것(같은 판정이 두 곳에 생긴다).
local CAPTURE_RELEASE_AT = 0.05  -- 존이 빈 뒤 이 아래로 떨어지면 A선 복귀 (요요 방지 이력)
local zoneDefense = false        -- 현재 B선 상태인가. duel 루프가 매 틱 갱신한다
-- ⏱️ [회귀수정 2026-08-31] 하강 후 최소 체류. 게이지 기반 이력만으로는 부족하다.
--   [증상] 13초에 하강 3회·복귀 2회. 복귀→재하강 간격이 0.267초까지 나왔다.
--   [원인] 트리거를 '침범 즉시'로 바꾸면서 하강 시점 게이지가 3~8% 가 됐는데,
--     CAPTURE_RELEASE_AT 이 0.05 라 하강하는 순간 이미 복귀 조건이 참이다.
--     남은 조건이 not intruded 뿐이라 존 판정이 한 틱만 떨려도 즉시 복귀한다.
--     편도 이동이 4.7~6.0초인데 1초짜리 상태가 뒤집히니 도착조차 못 한다.
--   [8초 근거] 편도 이동 최대 6초 + 존에서 실제로 뭔가 할 2초.
--     이보다 짧으면 체류의 대부분이 이동이라 왕복만 하는 꼴이 된다.
--   ⚠️ 존 '전환'은 막지 않는다. 이건 zoneDefense(모드)만 붙잡고,
--     어느 존으로 갈지는 zoneTarget 이 getActiveZone() 으로 매 틱 따로 정한다.
--     러너가 반대 존으로 옮기면 그쪽으로 방향을 튼다.
--   ⚠️ CAPTURE_RELEASE_AT 과 한 세트다. 막는 게 서로 다르니 둘 다 남긴다 —
--     이건 '짧은 왕복', 그쪽은 '깊이 들어왔는데 잠깐 비었다고 떠나는 것'.
local ZONE_MIN_HOLD = 8          -- 하강 후 최소 체류(초)
-- 🏃 [2026-09-02] 존 복귀 이속. 봇 킹 전용.
--   [문제] 계단(홀드 라인)에서 존까지 4.7~6.0초가 걸린다(위 '이별 일격' 주석의 실측).
--     그동안 러너는 이미 25% 를 채운다 — 밀림이 없어도 초기 도달 공백만으로 4분의 1을 내준다.
--     실측 23:47 판: 하강 08.598 → 존1 25% 10.865, 킹은 그때까지 미도착.
--   [왜 이속으로 푸나] 사람은 위치를 유연하게 판단하지만 봇은 그 로직이 사실상 불가능하다.
--     판단력을 판단력으로 메우려면 복잡해지고, 이동 속도면 상수 하나로 끝난다.
--   ⚠️ STAGE2_SPEED 는 Stage2TriggerSystem:345 의 값과 같아야 한다. 그쪽이 2단계 진입 시
--     14 로 세우고, 여기서 존 복귀가 끝나면 그 값으로 되돌린다. 한쪽만 바꾸면 어긋난다.
--   ⚠️ 밀림(건틀렛 풀차징 87 stud + 래그돌 2.5초)까지는 못 이긴다. 그건 별개 축이라
--     무기 쪽에서 봐야 한다. 이 값은 '초기 도달 공백'만 겨냥한다.
local ZONE_RUSH_SPEED = 18       -- 존으로 복귀할 때(14 → 18, 도달 4.7~6.0 → 3.7~4.7초)
local STAGE2_SPEED    = 14       -- 평상시 2단계 속도 ⚠️ Stage2TriggerSystem:345 와 동기
local zoneEnterAt = 0            -- 마지막 하강 시각(os.clock)
-- 🏆 [2026-08-31] B선 이동 목표 캐시.
--   [왜] getActiveZone() 은 '차오르는 중'일 때만 존을 준다. 러너가 존에서 잠깐 빠지면
--     nil 이 되어 이동 목표가 사라지고, 봇이 결투 로직으로 되돌아가 계단 쪽으로 샌다.
--     B선 상태인 동안은 마지막 존을 계속 목표로 잡아야 '라인을 내린' 상태가 유지된다.
--   ⚠️ zoneDefense 를 끄는 모든 곳에서 같이 지울 것(켜는 코드엔 끄는 코드를).
local lastZoneTarget = nil
-- 🔬 [진단 2026-09-03] 존 방어인데 존에 도달하지 못하는 원인 분리.
--   [배경] 09-03 실측: 하강 후 26초 동안 존까지 거리가 27~32 로 고정됐다.
--     해머 스핀의 순 밀림은 3~12 stud 라 이 갭을 설명하지 못한다. 즉 '밀려난' 게 아니라
--     애초에 안 가고 있거나, 가려는데 못 가고 있다. 둘은 처방이 완전히 다르다.
--   [읽는 법] 정렬 = 이동 방향과 '존 쪽 방향'의 내적. +1 존을 향함 / 0 옆으로 / -1 반대.
--     MoveDir 0         → 이동 명령 자체가 없다 (zoneTarget nil / 제자리 MoveTo)
--     정렬 +1, 속도 ~0  → 걸으려는데 막혀 있다 (AI 러너 벽 또는 지형)
--     정렬 +1, 속도 ~18 → 걷고 있는데 거리가 안 줄면 왕복·우회
--     정렬 −1           → 결투 로직이 존 반대쪽으로 끌고 간다
--   ⚠️ 확인 끝나면 DBG_ZONE = false. 끄는 스위치를 켜는 코드와 같은 편집에 둔다.
local DBG_ZONE    = true
local dbgZoneLast = 0


-- 소환 지점을 플레이트(계단) X 범위 안으로 강제한다.
--   실측 버그(2026-08): Spear 는 어느 보정 분기도 타지 않아 표적 위치에 그대로 꽂혔고,
--   bear_trap 의 uphillSpawnPoint 는 플레이트 경계를 보지 않아
--   X=744(바리케이드 뒤 태거베이스) 나 X=33(맵 반대편)까지 나갔다.
--   굴림 아이템은 plateSpawnPoint 로 이미 투영되지만 이 둘은 빠져 있었다.
local function clampToPlateX(pos)
	local plate = activePlate
	if not plate then return pos end
	local half = plate.Size.X * 0.5
	local minX = plate.Position.X - half
	local maxX = plate.Position.X + half
	if pos.X >= minX and pos.X <= maxX then return pos end
	local cx = math.clamp(pos.X, minX, maxX)
	-- X 를 옮겼으므로 지면 높이를 다시 잡는다
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { activeBot }
	local ray = workspace:Raycast(Vector3.new(cx, pos.Y + 250, pos.Z),
		Vector3.new(0, -500, 0), params)
	local y = ray and (ray.Position.Y + 3) or pos.Y
	return Vector3.new(cx, y, pos.Z)
end

local function uphillSpawnPoint(bot, targetPos, leadDist)
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return targetPos end
	local toBot = hrp.Position - targetPos
	local flat = Vector3.new(toBot.X, 0, toBot.Z)
	local dist = flat.Magnitude
	if dist < 5 then return targetPos end
	local lead = math.min(leadDist or 70, math.max(10, dist - ROLL_MIN_GAP))
	local p = targetPos + flat.Unit * lead
	-- 언덕 표면 높이 정렬 (위에서 아래로 레이캐스트, 봇 캐릭터 제외)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }
	local ray = workspace:Raycast(Vector3.new(p.X, p.Y + 250, p.Z), Vector3.new(0, -500, 0), params)
	if ray then
		p = ray.Position + Vector3.new(0, 3, 0)
	end
	return p
end

-- 굴리는류: 플레이트 위 스폰 지점 (X=플레이트, Z=타겟 정렬+클램프)
-- ── 쓰나미 발원지 오프셋 ──────────────────────────────────────
-- 굴리기류는 plate 중심(X≈699.5)에서 소환한다. 그런데 쓰나미는 그 자리에서 태어나
-- -X 로 쓸고 가는 '벽'이라, 2단계 결투장(ItemSpawnPlate, X 688~711)을 통째로 덮었다.
-- 실측: 발원 X=699.5 → 점유 X 665~735 (결투장 23 전부 + 성 안쪽 25 침범).
-- 발원을 러너 쪽(-X)으로 당기면:
--   · 점유 X 641~710.5 → 파도 뒷면이 성 경계(710)에 딱 맞아 성 안에서 안 태어난다
--   · 결투장을 쓸고 지나가는 시간 0.78초 → 0.38초
--   · 안전지대가 X>710.5(성 문턱)가 되어 "쓰나미 오면 성 쪽으로 붙어라"가 실행 가능해진다
-- (사람 킹은 클릭한 곳에 그대로 나온다 — 봇 조준에만 적용)
local TSUNAMI_SPAWN_X_OFFSET = -24

local function plateSpawnPoint(targetPos, xOffset)
	local plate = activePlate
	if not plate then return targetPos end
	local topY = plate.Position.Y + plate.Size.Y * 0.5 + 2
	local halfZ = math.max(plate.Size.Z * 0.5 - 4, 2)
	local z = math.clamp(targetPos.Z, plate.Position.Z - halfZ, plate.Position.Z + halfZ)
	local x = plate.Position.X + (xOffset or 0)
	if xOffset and xOffset ~= 0 then
		-- plate 밖으로 나가면 plate 윗면(topY)은 더 이상 지면이 아니다.
		-- 실측: X=675.5 지면 Y=111.7 vs plate topY=131.7 (20 stud 차) — 그대로 쓰면 공중에서 태어난다.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { activeBot }
		local ray = workspace:Raycast(Vector3.new(x, topY + 250, z), Vector3.new(0, -500, 0), params)
		if ray then return Vector3.new(x, ray.Position.Y + 2, z) end
	end
	return Vector3.new(x, topY, z)
end

-- ── 타겟/발사 ────────────────────────────────────────

-- 티어별 AI 러너(농민) 거리 페널티 — 타겟팅 성격:
--   easy 1.0 = 순수 최근접(농민이 총알받이 잘 됨, 온보딩) /
--   normal 1.3 = 동급이면 유저 우선 / hard 2.0 = 유저 강한 우선("얘 진짜 나 잡으러 온다" 보스 감성)
-- 유저는 농민을 미끼로 쓰는 전술이 가능해지고, KING의 광역기에 농민이 휩쓸리는 볼거리는 공짜.
-- Stage1 유저 편향: AI 러너의 '체감 거리'에 곱하는 배수. 클수록 AI 를 덜 노린다.
--   easy 가 1.0 이라 완전 동등이었고, 그래서 봇이 농민봇과 유저를 똑같이 노렸다.
--   Stage2 의 USER_PRIORITY_MULT(0.5, 유저 거리에 곱함)와 방향만 반대인 같은 규약.
local AI_TARGET_DIST_MULT = { easy = 1.4, normal = 1.8, hard = 2.4 }

-- 🎯 [2026-08-31] 내구도 0 표적 우선. '체감 거리'에 곱하는 배수(낮을수록 우대).
--   [왜] 내구도 1칸 = 태거가 러너 1명당 2방을 맞춰야 한다. 첫 방은 흡수만 되고
--     두 번째 방이 실제 처치다. 그런데 봇은 매번 '가장 가까운' 표적만 골라서
--     10명을 골고루 한 대씩 벗겨놓고 아무도 못 죽이는 일이 반복됐다.
--   [실측 2026-08-31, easy 고정 5판]
--     라운드 C: 5명 벗김 → 2명 전환 (40%)
--     라운드 E: 6명 벗김 → 5명 전환 (83%) ← 통나무가 같은 무리를 연속으로 지나간 판
--     소환 수는 E 가 오히려 적었다(8발 vs 9발). 차이는 전량 '후속타 전환율'이었다.
--   [왜 0.55 인가] 벗겨진 표적이 1.8배 멀어도 우선하게 된다(1/0.55).
--     더 낮추면 회피 잘하는 한 명에게 고착돼 근처 표적을 통째로 놓친다.
--     더 높이면 거리에 묻혀 효과가 안 난다.
--   ⚠️ 정보 비대칭이 아니다. 유저 킹도 PlayerMarkerClient 테두리 색으로
--     내구도 유무를 본다(금=방패 / 빨강=없음). 봇에 같은 신호를 주는 것뿐이다.
--   ⚠️ 굴리기는 광역이라 부수 효과가 있다 — 벗겨진 표적을 겨누면 그 레인에
--     같이 벗겨진 무리가 있을 확률이 높다(직전 광역타로 함께 벗겨졌으므로).
--   ⚠️ 속성이 nil 이면 우대하지 않는다. DurabilitySystem 이 스폰 때 1칸을 주므로
--     nil 은 '아직 지급 전'이지 '벗겨짐'이 아니다.
--   ⚠️ [회귀수정 2026-08-31] 유저 루프에는 걸지 않는다. AI 루프 전용이다.
--     [증상] 도입 직후 판에서 1단계 처치 0/11, 굴리기 11발 중 AI 내구도 소모 0건.
--     [원인] aiMult(유저 우대 1.8)와 이 값이 곱해져 유저 우대가 3.27배가 됐다.
--       내구도는 재생이 없어 유저가 한 번 벗겨지면(그 판 4.5초) 라운드 내내 고착된다.
--       소환 Z 가 -556~-617 로 몰렸다 — AI 주행 목표(Z=-675)에서 60~120 stud 벗어난
--       도망 다니는 유저 한 명의 선에만 굴린 것이다.
--     [수정 후 배수] 둘 다 멀쩡 1.0 : 1.8 / 유저만 벗겨짐 1.0 : 1.8 (고정)
--       AI 만 벗겨짐 1.0 : 0.99 / 둘 다 1.0 : 0.99 — 유저 우대 상한이 1.8 로 복귀한다.
--   ⚠️ 감수한 것: 벗겨진 AI(0.99)가 멀쩡한 유저(1.0)를 근소하게 이긴다.
--     "보스가 나를 노린다"가 옅어지면 이 값을 0.7 로 올릴 것(AI 1.26 → 유저 항상 우선).
--     대신 마무리 기능이 약해진다. 트레이드오프다.
--   ⏪ [되돌림 2026-09-05] 0.35 로 내렸다가 0.55 로 복귀.
--     [왜] 같은 문제("명중이 내구도에 흡수돼 처치로 안 이어짐")를 봇 내구도 절반
--       지급으로 직접 해결하기로 했다. 두 변경을 같이 넣으면 원인 분리가 안 된다.
--     ⚠️ 봇 절반이 내구도를 안 받으면 '벗겨진 봇 우선'의 의미 자체가 줄어든다 —
--       이 값은 그대로 두고, 내구도 쪽 결과를 먼저 본다.
local STRIPPED_TARGET_MULT = 0.55

local function strippedMult(char)
	local d = char and char:GetAttribute("Durability")
	if d ~= nil and d <= 0 then return STRIPPED_TARGET_MULT end
	return 1
end

local function pickTarget(bot, tier)
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestScore = nil, math.huge
	local sens = (tier and THREAT_SENS[tier.name]) or 0.08
	-- 유저 러너 (거리 가중 없음, 위협 반영)
	for _, plr in ipairs(Players:GetPlayers()) do
		-- Eliminated(사망 후 로비 리스폰) 제외 — 로비 조준 방지
		if plr:GetAttribute("Role") == "Runner" and not plr:GetAttribute("Eliminated") then
			local char = plr.Character
			local thrp = char and char:FindFirstChild("HumanoidRootPart")
			local thum = char and char:FindFirstChildOfClass("Humanoid")
			if thrp and thum and thum.Health > 0 and not char:GetAttribute("Downed") then
				local d = (thrp.Position - hrp.Position).Magnitude / (1 + getThreat(char) * sens)
				if d < bestScore then best, bestScore = thrp, d end
			end
		end
	end
	-- AI 러너(농민) — 티어별 거리 페널티 + 위협 반영
	local aiMult = (tier and AI_TARGET_DIST_MULT[tier.name]) or 1.3
	for _, m in ipairs(workspace:GetChildren()) do
		if m:GetAttribute("AIRunner") == true then
			local thrp = m:FindFirstChild("HumanoidRootPart")
			local thum = m:FindFirstChildOfClass("Humanoid")
			if thrp and thum and thum.Health > 0 and not m:GetAttribute("Downed") then
				local score = (thrp.Position - hrp.Position).Magnitude * aiMult * strippedMult(m) / (1 + getThreat(m) * sens)
				if score < bestScore then best, bestScore = thrp, score end
			end
		end
	end
	return best
end

local function pickItem(tier)
	local now = tick()
	local ready = {}
	for _, it in ipairs(tier.items) do
		local last = itemLastFired[it.item] or 0
		-- ⏱️ [2026-08-31] 쿨은 유저와 같은 값을 쓴다(ItemSpawnHandler.ITEM_COOLDOWN).
		--   [왜] 봇 테이블에 복사해 두면 값이 두 곳에 생겨 한쪽만 고쳐진다.
		--     HP 공식을 통일한 것과 같은 이유 — 봇전 측정이 실전으로 옮겨가야 한다.
		--   ⚠️ it.cd 는 티어별 예외용으로 남겨둔다. 지정하면 유저 값을 덮어쓴다.
		--   ⚠️ 게터가 아직 없으면(로드 순서) 3 으로 폴백한다 = DEFAULT_COOLDOWN 과 같은 값.
		local cd = it.cd or (_G.GetItemCooldown and _G.GetItemCooldown(it.item)) or 3
		if (now - last) >= cd then ready[#ready + 1] = it end
	end
	if #ready == 0 then return nil end
	-- 🎲 [2026-08-31] 균등 랜덤 → 가중 랜덤.
	--   [왜] 예전엔 cd 가 두 가지 일을 겸했다 — '재사용 제한'과 '비중 조절'.
	--     그래서 쿨을 유저 값에 맞추면(tsunami 20→6, BlackHole 18→7) 데미지 0 인
	--     제어기가 훨씬 자주 뽑혀 하드가 오히려 약해진다.
	--     실측: 지난 하드 판은 특수기가 cd 15~20 에 묶인 사이 배럴만 29회 나왔고,
	--     처치 10건 중 배럴 6 · 근접 3 · tox_box 1 / 쓰나미·블랙홀은 0 이었다.
	--   [해결] 두 축을 분리한다. cd = 유저와 동일(재사용 제한), weight = 티어 설계(비중).
	--   ⚠️ weight 미지정은 1 로 본다 — 전부 미지정이면 예전 균등 랜덤과 같다.
	local total = 0
	for _, it in ipairs(ready) do total = total + (it.weight or 1) end
	local roll = math.random() * total
	for _, it in ipairs(ready) do
		roll = roll - (it.weight or 1)
		if roll <= 0 then return it end
	end
	return ready[#ready]   -- 부동소수 오차 대비 폴백
end

local function fireItem(itemName, pos)
	if itemName == "Spear" then
		if _G.throwSpear then _G.throwSpear(pseudoPlayer, pos) end
	elseif itemName == "tsunami" then
		if _G.fireTsunami then _G.fireTsunami(pseudoPlayer, pos) end
	elseif itemName == "BlackHole" then
		if _G.spawnBlackHole then _G.spawnBlackHole(pseudoPlayer, pos) end
	elseif itemName == "tox_box" then
		if _G.spawnToxBox then _G.spawnToxBox(pseudoPlayer, pos) end
	elseif itemName == "Demonspear" then
		-- ⚠️ 자체 잠금이 있다(DemonSpearSystem:343) — 비행 0.08~0.8 + 잔불 3 + 여유 0.3
		--   = 최대 4.1초. os.clock() 기반 '결정론적' 타이머라 상한이 고정이다.
		--   유저 쿨 8 > 4.1 이므로 후보로 올라올 땐 항상 풀려 있다 = 거부 낭비 없음.
		--   ⚠️ tox_box 는 이것과 달리 '박스가 러너 베이스에 닿아야' 풀리는 방식이라
		--     40초 넘게 잠겼고 거부율 75%였다. 그래서 풀에서 뺐다.
		--   ⚠️ 아래 itemLastFired 는 성공/실패를 안 가리고 찍힌다. 실패해도 쿨을 먹으므로
		--     '잠금 < 쿨' 관계가 깨지면 슬롯이 통째로 낭비된다. 쿨을 줄일 때 반드시 확인할 것.
		if _G.throwDemonSpear then _G.throwDemonSpear(pseudoPlayer, pos) end
	elseif itemName == "EnergyBall" then
		-- pseudoPlayer 로 충분하다: .Character(=bot) 와 .Name(="KING") 만 쓴다.
		if _G.fireEnergyBall then _G.fireEnergyBall(pseudoPlayer, pos) end
	elseif itemName == "bear_trap" then
		if _G.placeTrap then _G.placeTrap(pseudoPlayer, pos) end
	else
		-- 기본 투척류(stone / Wood Log / Wooden Barrel): ItemSpawnHandler 봇 진입점
		if _G.BotSpawnItem then _G.BotSpawnItem(pseudoPlayer, nil, itemName, pos) end
	end
	itemLastFired[itemName] = tick()
end

-- ── Stage 2 결투 (PushTool) ──────────────────────────
-- 스윙 주력 / 그랩 보조(티어별 확률). 러너가 평지(플레이트 X 이상)에 있으면 결투,
-- 계단 아래로 떨어지면 기존 투척 모드로 마무리(하이브리드).
-- 액션 간격 = 유저와 동일한 서버 쿨(스윙 5.0s 명중 쿨 / 그랩 4.0s) + 티어별 반응 지연.
-- 서버(canSwing/canGrab)가 쿨을 강제하므로 봇이 유저보다 빠를 수 없고,
-- 인터벌을 쿨 이상으로 잡아 "쿨 종료 0초 즉시시전" 기계 리듬도 방지. (쿨 5s = 러너 딜 창 설계 존중)
-- aimPlateChance: 넉백 방향을 "러너→플레이트(계단)"로 잡을 확률 = 즉사각 푸시.
--   (히트는 몸 전방 판정이라 몸은 러너를 향하고, 넉백만 계단 쪽 — 실제 태거의 카메라 조준 재현)
-- ⚠️ [2026-08-30] swingInterval 6.0/5.5/5.0 → 2.0/1.5/1.0.
--   [증상] 2단계가 51초 교착이 됐다. 킹이 무리에 둘러싸여 아무도 못 죽이고 907 HP 를 다 잃었다.
--   [원인] 위 주석의 "스윙 명중 쿨 5.0s"가 낡은 값이다. 실제 서버 쿨은 1.0s 로 내려갔는데
--     (로그: `SLAP 명중 … 쿨 1.0s`) DUEL_PARAMS 가 따라가지 않았다.
--     그 결과 봇은 유저가 칠 수 있는 횟수의 1/6 만 쳤다 — 실측 스윙 간격 6.2~7.9초.
--   ⚠️ 아래 값은 "쿨(1.0s) 이상"이라는 원래 규칙은 유지한다. hard 가 쿨과 동일한 1.0 이고
--     easy 는 2배 느리다. 쿨보다 낮추면 서버가 어차피 거부하므로 의미가 없다.
--   ⚠️ 이 변경은 빈도만 건드린다. 데미지 분산(5.0/√N)은 그대로다 — 한 번에 한 축만 본다.
--     빈도가 6배 레버라 분산(6명 기준 2.5배)보다 크므로, 이걸 먼저 재고 나서 분산을 판단할 것.
local DUEL_PARAMS = {
	easy   = { swingInterval = 2.0, grabChance = 0.0,  aimPlateChance = 0.5 },  -- 그랩 없음, 절반은 계단 각
	normal = { swingInterval = 1.5, grabChance = 0.25, aimPlateChance = 0.7 },
	hard   = { swingInterval = 1.0, grabChance = 0.5,  aimPlateChance = 1.0 },  -- 쿨 즉시 + 항상 즉사각 + 그랩 콤보
}
local GRAB_COMBO_WINDOW = 2.2   -- 그랩 발사 후 콤보 창(로켓펀치 왕복 0.65 + 스턴 1.0 + 여유)
local grabComboUntil = 0        -- 콤보 창 종료 tick
local SWING_RANGE = 9        -- 스윙(푸시) 시도 거리(stud) — 근접 판정이라 짧게 유지
-- 👊 [2026-09-05] 이동 중 기회 타격의 추가 사거리. 실제 판정 거리 = SWING_RANGE + 이 값.
--   [왜 필요] 존 왕복 중에는 9 stud 안에 들어오는 순간이 거의 없어 봇이 이동만 했다.
--   [왜 조금만] 크게 잡으면 '멀리서 허공에 스윙'이 되어 어색하다. 스쳐 지나가며
--     닿는 정도만 늘린다. 서버 히트 판정은 그대로라 안 닿으면 빗나갈 뿐이다.
--   ⚠️ 제자리 결투(아래 분기)의 사거리는 9 그대로다. 이 값은 '이동 중'에만 쓴다.
local PASSBY_SWING_BONUS = 5
-- ⚠️ [BOT-GRAB-RANGE] 그랩은 스윙과 사거리를 분리한다.
--    예전엔 둘 다 SWING_RANGE(9)를 썼는데, 그랩의 실제 사거리는 GRAB_MAX_RANGE=50 이다.
--    9 stud 는 손 판정 반경(GRAB_HAND_RADIUS=4)의 두 배 남짓이라, 쏘자마자 닿아
--    0.3초(GRAB_OUT_TIME) 비행 연출이 체감상 사라지고 "코앞에서 즉시 스턴"으로 보였다
--    (실측 2026-08-22: 유저는 멀리서 조준해 던지는데 봇만 붙어서 발사).
--    ⚠️ 최소 거리도 둔다 — 너무 가까우면 어차피 연출이 안 보이므로 그때는 스윙을 쓴다.
local GRAB_RANGE_MIN = 14    -- 이보다 가까우면 그랩 대신 스윙
local GRAB_RANGE_MAX = 32    -- 실제 상한(50)보다 보수적: 빗나감이 잦으면 답답해진다
local DUEL_TICK = 0.25       -- 결투 모드 폴링 주기
local duelReady = false      -- Stage2 준비(강림+툴 장착) 완료
local lastDuelAction = 0
-- 🎯📖 [2026-08-29] 2단계 고정 기물(곡사포·마법책) 사용 주기.
--   ⚠️ 기물 자체 쿨(CannonSystem.COOLDOWN)이 진짜 제한이고, 이건 '시도 주기'다.
--     너무 짧으면 매 틱 pcall 이 돌아 낭비고, 너무 길면 쿨이 돌아도 안 쏜다.
--     기물 쿨보다 짧게 두어 "쿨이 풀리면 곧 쏜다"가 되게 한다.
local FIXTURE_INTERVAL = 2.0
local lastFixtureUse = 0
local lastStage2Throw = 0    -- Stage2 병행 투척 쿨 추적
local stage2ThrowHint = 0    -- 각을 잡고 민 직후 시각. 이 뒤 짧은 창 동안 투척을 앞당긴다
local HINT_WINDOW = 0.8      -- 민 직후 이 시간 안에는 투척 쿨을 무시한다

-- 기존 투척 로직 (Stage1 주력 + Stage2 하이브리드에서 재사용)
-- ────────────────────────────────────────────────────────────────
-- Stage 2 병행 투척용 표적 선별
--   결투(Push/Grab)는 swingInterval 이 5~6초라 그 사이 봇이 사실상 아무것도 안 했다.
--   → 결투와 별개로 투척 쿨이 차면 아이템을 굴려 '각이 나올 때 적극적으로' 만든다.
--   우선순위:
--     1) 밀어낸 상대가 소환 영역(ItemSpawnPlate) 안에 들어갔으면 그 대상
--        (태거 아이템은 TaggerCharacter 와 충돌 해제라 자기 피해 없음)
--     2) 없으면 가장 먼 러너 — 붙은 놈은 밀고, 멀리 있는 놈은 던져서 막는다
-- ────────────────────────────────────────────────────────────────
local PLATE_X_TOL = 26   -- 소환 영역 X 반폭 여유 (ItemSpawnPlate X 크기 22.2 기준)

local function forEachLiveRunner(fn)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("Role") == "Runner" and not plr:GetAttribute("Eliminated") then
			local char = plr.Character
			local thrp = char and char:FindFirstChild("HumanoidRootPart")
			local thum = char and char:FindFirstChildOfClass("Humanoid")
			if thrp and thum and thum.Health > 0 and not char:GetAttribute("Downed") then
				fn(thrp)
			end
		end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:GetAttribute("AIRunner") == true then
			local thrp = m:FindFirstChild("HumanoidRootPart")
			local thum = m:FindFirstChildOfClass("Humanoid")
			if thrp and thum and thum.Health > 0 and not m:GetAttribute("Downed") then
				fn(thrp)
			end
		end
	end
end

-- ────────────────────────────────────────────────────────────────
-- Stage 2 결투 표적 선정
--   기존 pickTarget 은 '가장 가까운 러너'를 고른다. AI 가 10체라 항상 AI 가 잡히고,
--   유저는 뒤에서 관망하면 절대 표적이 되지 않았다 → 관망이 최선의 전략이 되어버렸다.
--   (AI_TARGET_DIST_MULT normal=1.3 은 AI 가 30% 멀어야 동등 — 둘러싸인 상황에선 무의미)
--   Stage 2 에서는 우선순위를 명시적으로 둔다:
--     1) 유저 러너 — 사거리 안이면 무조건 우선. 관망 이득을 없앤다.
-- (예전엔 '유저가 일정 거리 안이면 무조건 유저'로 즉시 반환했다.
--     3) 유저가 아예 멀면 가까운 AI 를 처리하며 버틴다.
--   Stage 1 은 건드리지 않는다 — 거기선 위에서 아이템만 굴리므로 기존 로직이 맞다.
-- ────────────────────────────────────────────────────────────────
local USER_PRIORITY_MULT = 0.5   -- 유저 거리 가중치. 낮을수록 유저를 우대 (1.0 = 동등)

-- ────────────────────────────────────────────────────────────────
-- 처치 각 판정
--   Push 만으로는 죽지 않는다. '밀어서 소환 영역에 넣고 아이템으로 처리'가 콤보다.
--   지형 실측(2026-08, map1/map2 동일 구조):
--     바리케이드 X=733 / 태거베이스 평지 X 713~723 / 계단 X 688~710(낙차 8~10) / 언덕 X<688
--     즉 밀어내는 방향은 항상 -X 한 방향이고, 소환 영역이 곧 계단이라
--     레이캐스트로 낙하 지형을 찾을 필요가 없다 — activePlate 의 X 범위로 판정하면 된다.
--   Push 밀림 거리: PUSH_VELOCITY 110 × 수평계수 0.958 × PUSH_DURATION 0.2 ≈ 21 stud
-- ────────────────────────────────────────────────────────────────
local PUSH_KNOCK_DIST = 21    -- Push 로 밀리는 예상 거리 (PushTool 상수와 연동)
local MIN_SPAWN_GAP   = 20    -- ItemSpawnHandler.MIN_SPAWN_DIST 와 같은 값

-- 지금 밀면 표적이 소환 영역에 들어가는가?
--   반환: 각이 서면 true, 아니면 false
-- 각을 만들기 위한 접근 지점 계산
--   표적을 계단(-X)으로 밀려면 봇이 표적보다 +X 쪽에 서야 한다.
--   기존에는 MoveTo(표적) 로 직진해서, 옆이나 아래에서 붙으면 각이 서지 않았다.
--   → 표적의 +X 쪽 SWING_RANGE 안쪽 지점을 목표로 삼아 '돌아 들어가게' 한다.
--   이미 +X 쪽에 있으면 그대로 접근한다(불필요한 우회 방지).
local APPROACH_OFFSET = 6    -- 표적보다 이만큼 +X 쪽에 선다 (SWING_RANGE 9 안쪽)

-- 🎯 [2026-09-09] 사거리 밖 피격 대응 — "맞고만 있지 않는다".
--   [증상] 러너가 SWING_RANGE(9) 밖에서 일방적으로 때리는데 봇이 반응을 안 했다.
--     ClassicSword 사거리 강화(reach 22)를 넣자 74초 동안 다운 0건 · 킹 987 피해로
--     사실상 무저항이었다. "바보를 상대한 느낌"(사용자).
--   [왜 위협 시스템이 있는데도] threatTable 은 '누굴 볼까'만 정한다.
--     문제는 clampToHoldLine 이 이동 목표를 성문(741)에서 잘라, 봇이 볼 수는 있어도
--     갈 수가 없었다는 것이다. 표적이 763 에 있으면 격차 22 로 영원히 못 닿는다.
--   [무엇을 하나] 사거리 밖에서 누적 피해를 받으면 잠깐 홀드 라인을 풀고 쫓는다.
--   ⚠️ 08-30 폐기 근거를 지킨다: 무한정 쫓으면 처치 수단이 전부 죽는다
--     (밀기·아이템·슬랩 모두 성문 앞에서만 유효). 그래서 시간 제한 + 복귀가 필수다.
--   ⚠️ 이 값들은 미검증이다. 봇이 너무 깊이 들어가 자멸하면 SALLY_TIME 부터 줄일 것.
local SALLY_DAMAGE   = 45    -- 사거리 밖에서 이만큼 누적되면 출격
local SALLY_TIME     = 5.0   -- 출격 지속(초). 지나면 홀드 라인으로 복귀
local SALLY_COOLDOWN = 6.0   -- 복귀 후 재출격까지
-- ⚠️ [하향 2026-09-09 (같은 날)] 40 → 25. 40 은 근거 없이 고른 값이었다.
--   [필요량 계산] 이 값이 잡아야 하는 건 "reach 22 무기를 든 러너에게 닿는 것"이다.
--     러너가 763 에 서면, 킹이 SWING_RANGE(9) 안에 들려면 754 까지 가면 된다.
--     필요 전진 = 754 − 741(holdLine) = 13.  25 면 여유 12 로 충분하다.
--   [왜 40 이 위험한가] 741 + 40 = 781 인데, 2026-08-30 에 봇이 X=772 까지
--     쫓아가 처치 수단이 전부 죽은 이력이 있다(startForRound 주석 참조).
--     상한이 그 사고 지점보다 9 스터드 더 깊었다 — "완전 해제가 아니다"라는
--     안전장치가 정작 안전선 바깥에 그어져 있었던 셈이다.
--     25 면 상한 766 < 772 로 사고 지점 안쪽에 머문다.
--   ⚠️ 점령존(804~826)까지 가는 건 이 값이 아니라 zoneDefense 경로다.
--     clampToHoldLine 첫 줄이 `if zoneDefense then return pos end` 로 클램프를
--     통째로 푼다. 그래서 이 값을 내려도 존 방어는 막히지 않는다.
--   ⚠️ 되돌릴 값: 40. 다만 되돌리기 전에 "25 로는 reach 22 를 못 잡는가"를 먼저 볼 것 —
--     [Sally] 로그의 '표적 N stud' 가 판단 기준이다(9 + 25 = 34 까지 커버).
local SALLY_MAX_X    = 25    -- 홀드 라인에서 이보다 더 들어가지 않는다(자멸 방지)
local sallyUntil, sallyReadyAt, sallyDamage = 0, 0, 0

-- 🎯 위 forward 선언(sallyOnDamage)의 실체. addThreat 가 매 피해마다 부른다.
--   ⚠️ 여기 두는 이유: SWING_RANGE(828) · activeBot(140) 이 모두 선언된 뒤여야 한다.
--   ⚠️ SWING_RANGE 안에서 맞은 건 세지 않는다 — 정상 교전이라 이미 대응 중이다.
--   ⚠️ 모든 피해 경로가 addThreat 를 지나므로, 새 무기가 추가돼도 자동으로 커버된다.
sallyOnDamage = function(char, amount)
	if os.clock() < sallyReadyAt then return end
	if not (activeBot and activeBot.Parent) then return end
	local bRoot = activeBot:FindFirstChild("HumanoidRootPart")
	local aRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not (bRoot and aRoot) then return end

	local d = (aRoot.Position - bRoot.Position).Magnitude
	if d <= SWING_RANGE then return end       -- 붙어서 맞는 건 정상 교전

	sallyDamage = sallyDamage + amount
	if sallyDamage < SALLY_DAMAGE then return end

	local now = os.clock()
	sallyDamage  = 0
	sallyUntil   = now + SALLY_TIME
	sallyReadyAt = now + SALLY_TIME + SALLY_COOLDOWN
	print(string.format(
		"👑 [Sally] 사거리 밖 피격 누적 %d → 출격 %.0fs (표적 %.0f stud · 전진 한계 +%d)",
		SALLY_DAMAGE, SALLY_TIME, d, SALLY_MAX_X))
end

-- 🚪 [2026-08-30] 이동 목표를 홀드 라인 안쪽으로 넘어가지 않게 자른다.
--   성문보다 +X 로 들어가면 봇의 처치 수단이 전부 죽는다(startForRound 주석 참조).
--   ⚠️ Z 는 건드리지 않는다. 표적을 정면으로 보는 각은 유지해야 밀기 판정이 산다.
--   ⚠️ holdLineX 가 nil 이면(성문 못 찾음) 아무것도 하지 않는다 — 예전 동작 그대로.
local function clampToHoldLine(pos)
	-- 🏆 B선(점령 방어) 중엔 홀드 라인을 풀어준다.
	--   ⚠️ 이게 없으면 점령 반응 로직을 아무리 붙여도 봇이 존에 갈 수 없다 —
	--     존(816)이 성문(746)보다 70 stud 안쪽이라 이동 목표가 매번 잘려나간다.
	if zoneDefense then return pos end

	-- 🎯 [2026-09-09] 출격 중이면 홀드 라인을 SALLY_MAX_X 만큼 밀어준다.
	--   ⚠️ 완전 해제(return pos)가 아니다. 그러면 08-30 처럼 X=772 까지 들어가
	--     처치 수단이 전부 죽는다. 상한을 '늘리기만' 해서 자멸을 막는다.
	if holdLineX and os.clock() < sallyUntil then
		local limit = holdLineX + SALLY_MAX_X
		if pos.X <= limit then return pos end
		return Vector3.new(limit, pos.Y, pos.Z)
	end

	-- 🌊 [2026-09-01] 물벽(불기둥) 지대 하한. 상한(holdLineX)과 대칭이다.
	--   [증상] 킹이 표적을 쫓아 계단까지 내려가 물벽에 타 죽는 판이 반복됐다.
	--     12:14 판: HP 31 남은 킹이 -4 씩 8연타(0.25초 간격, 시전자 '?')로 0 이 됐다.
	--     그 시점 살아있는 러너가 없어 전멸승 직전이었는데 승패가 뒤집혔다.
	--     데미지 지분은 4% 였지만 '마지막 31'을 가져가 결과를 갈랐다 — 지분과 승패 영향은 별개다.
	--   [왜 봇만 당하나] 회피 난이도가 비대칭이다. 러너는 전진하면 저절로 벗어나지만
	--     (게임의 기본 동작), 킹은 등 뒤에서 오는 걸 인지할 수단이 없다.
	--     사람 태거는 화면 연출로 알아채고 물러나지만 봇은 그 개념 자체가 없었다.
	--   [왜 고정값이 아닌가] 불기둥은 START_X → END_X 로 전진한다. 고정 하한을 쓰면
	--     초반엔 과하게 묶이고(아직 안전한데 못 내려감) 후반엔 모자란다.
	--     FirePressureSystem 이 매 틱 기록하는 실제 판정 경계를 그대로 읽는다.
	--   ⚠️ 여유 6 stud 를 둔다. 경계에 딱 붙으면 한 프레임 밀리거나 지형 굴곡으로
	--     넘어가 타기 시작한다. 6 이면 한 틱(0.25초) 전진분(2.5)의 두 배 이상이다.
	--   ⚠️ 압박 전·정지 후에는 _G.FireZoneEdgeX 가 nil 이라 하한이 없다 = 예전 동작 그대로.
	local edge = _G.FireZoneEdgeX
	if edge then
		local floorX = edge + FIRE_SAFE_MARGIN
		-- 상한보다 하한이 높아지는 건 물벽이 성문까지 온 경우다. 그땐 상한을 지킨다
		-- (물벽에 타는 것보다 처치 수단을 잃는 게 낫다 — 어차피 END_X 는 성문 앞에서 멈춘다).
		if holdLineX and floorX > holdLineX then floorX = holdLineX end
		if pos.X < floorX then pos = Vector3.new(floorX, pos.Y, pos.Z) end
	end

	if not holdLineX then return pos end
	if pos.X <= holdLineX then return pos end
	return Vector3.new(holdLineX, pos.Y, pos.Z)
end

local function computeApproachPos(bot, target)
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return target.Position end

	-- 이미 표적보다 충분히 +X 쪽이면 직진
	if hrp.Position.X > target.Position.X + 1 then
		return clampToHoldLine(target.Position)
	end

	-- 아니면 표적의 +X 쪽으로 돌아 들어간다.
	-- Z 는 표적에 맞춰 정면을 잡되, 계단 방향(-X)이 등 뒤가 되지 않도록 한다.
	return clampToHoldLine(Vector3.new(
		target.Position.X + APPROACH_OFFSET,
		hrp.Position.Y,
		target.Position.Z))
end

-- 밀친 뒤 아이템을 놓을 수 있는 거리까지 물러날 지점
--   MIN_SPAWN_GAP 보다 넉넉히(+6) 떨어져야 판정 경계에서 튕기지 않는다.
-- ⚠️ [2026-08-30] 이 후퇴는 +X(성문 안쪽) 방향이다. 홀드 라인을 넘지 않도록 자른다.
--   봇이 X=772 까지 들어간 실측 사례의 유력한 경로가 여기다 — 밀고 물러나기를 반복하며
--   한 번에 26 stud 씩 안쪽으로 밀려 올라갔다.
--   ⚠️ 대신 성문에 붙어 있으면 표적과의 이격이 부족해질 수 있다. 다만 2단계 아이템은
--     플레이트(성문에서 42~46 stud)에 소환되므로 소환 자체는 막히지 않는다.
--     교착이 관측되면 이 지점을 -X 쪽(플레이트 방향) 후퇴로 바꾸는 것을 먼저 검토할 것.
local function retreatPos(bot, target)
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return target.Position end
	return clampToHoldLine(Vector3.new(
		target.Position.X + MIN_SPAWN_GAP + 6,
		hrp.Position.Y,
		hrp.Position.Z))
end

local function evaluateKillAngle(bot, target)
	if not (activePlate and target) then return false end
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	-- 1) 태거가 표적보다 +X 쪽이어야 밀 때 -X(계단 방향)로 간다
	if hrp.Position.X <= target.Position.X then return false end

	-- 2) 밀린 예상 지점
	local predictedX = target.Position.X - PUSH_KNOCK_DIST

	-- 3) 그 지점이 소환 영역(계단) X 범위 안인가
	local pMin = activePlate.Position.X - activePlate.Size.X / 2
	local pMax = activePlate.Position.X + activePlate.Size.X / 2
	if predictedX < pMin or predictedX > pMax then return false end

	-- 4) 그 지점이 태거로부터 소환 최소 거리 밖인가 (안이면 아이템을 못 놓는다)
	local predicted = Vector3.new(predictedX, target.Position.Y, target.Position.Z)
	if (predicted - hrp.Position).Magnitude < MIN_SPAWN_GAP then return false end

	return true
end

local function pickDuelTarget(bot, tier)
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- 1순위: 추격 범위 안의 유저 러너 중 가장 가까운 쪽
	local user, userDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("Role") == "Runner" and not plr:GetAttribute("Eliminated") then
			local char = plr.Character
			local thrp = char and char:FindFirstChild("HumanoidRootPart")
			local thum = char and char:FindFirstChildOfClass("Humanoid")
			if thrp and thum and thum.Health > 0 and not char:GetAttribute("Downed") then
				local d = (thrp.Position - hrp.Position).Magnitude
				if d < userDist then user, userDist = thrp, d end
			end
		end
	end
	-- (예전엔 여기서 'userDist <= 60 이면 무조건 유저'로 즉시 반환했다.
	--  그 결과 유저가 근처에 있으면 AI 를 아예 안 봐서, 농민봇이 방치됐다.
	--  → 즉시 반환 대신 아래에서 '유저 거리에 가중치'를 걸어 비교한다)

	-- 2순위: 가까운 AI 러너
	local ai, aiDist = nil, math.huge
	for _, m in ipairs(workspace:GetChildren()) do
		if m:GetAttribute("AIRunner") == true then
			local thrp = m:FindFirstChild("HumanoidRootPart")
			local thum = m:FindFirstChildOfClass("Humanoid")
			if thrp and thum and thum.Health > 0 and not m:GetAttribute("Downed") then
				local d = (thrp.Position - hrp.Position).Magnitude
				if d < aiDist then ai, aiDist = thrp, d end
			end
		end
	end

	-- 유저가 범위 밖이어도, AI 가 없거나 유저가 더 가까우면 유저를 노린다
	-- 유저를 우대하되 AI 를 무시하지는 않는다.
	--   유저 거리에 USER_PRIORITY_MULT 를 곱해 '더 가깝게' 취급한다.
	--   0.5 면 유저가 AI 보다 2배 멀어도 유저를 고른다.
	if ai and user then
		return (userDist * USER_PRIORITY_MULT <= aiDist) and user or ai
	end
	return ai or user
end

local function pickThrowTarget(bot, duelTarget)
	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- 1순위: 결투 상대가 소환 영역 안이면 그쪽
	if duelTarget and activePlate then
		if math.abs(duelTarget.Position.X - activePlate.Position.X) <= PLATE_X_TOL then
			return duelTarget
		end
	end

	-- 2순위: 가장 먼 러너
	-- 🚫 [2026-09-01] 태거 베이스 안의 러너는 제외한다.
	--   [증상] 언덕에 아무도 없는데 봇이 계속 아이템을 던져 쿨을 태웠다.
	--   [원인] 2단계엔 전원이 베이스 위에서 싸우는데, 이 함수가 "가장 먼 러너"를
	--     조건 없이 골랐다. 아이템은 계단(플레이트)에서 반대쪽으로 굴러가므로
	--     베이스 안 표적에는 애초에 닿지 않는다. 게다가 2026-09-01 에 접촉형
	--     아이템에도 베이스 면역이 붙어, 설령 닿아도 무효다.
	--   ⚠️ IsCharInTaggerBase 가 아니라 IsOnTaggerBase 를 쓴다. 두 가지 이유다.
	--     ① 플레이트를 면제한다 — 계단 위 러너는 굴리기의 정당한 표적이다.
	--     ② showBaseImmune 을 부르지 않는다. 표적 '선정'에 쓰는 판정이라
	--        FX 가 딸려오면 매 발사 간격마다 방패 이펙트가 튄다.
	--   ⚠️ 아무도 안 남으면 nil 을 반환한다. 호출부(1381행)가 `if thrower then` 으로
	--     감싸고 있어 그대로 투척을 건너뛴다.
	local far, farDist = nil, -1
	forEachLiveRunner(function(thrp)
		if _G.IsOnTaggerBase and _G.IsOnTaggerBase(thrp.Position) then return end
		local d = (thrp.Position - hrp.Position).Magnitude
		if d > farDist then far, farDist = thrp, d end
	end)
	return far
end

-- [SPEAR-AIM] 직선 발사류(Spear)의 유효 사격 구간 제한.
--   창은 계단(ItemSpawnPlate)~러너베이스 구간에서만 맞아야 한다.
--   태거베이스(성) 안까지 꽂히면 "성 안에서도 공격당한다"가 되어 룰이 무너진다.
--   ⚠️ 이름으로 러너베이스를 찾으면 안 된다 — map1 은 playerbase, map2 는 playerspawn2 로
--      이름이 달라 한쪽이 깨진다(실측 2026-08-21).
--      대신 플레이트 X 를 '상한'으로 쓴다. 태거베이스는 플레이트보다 뒤쪽에 있으므로
--      (실측: 플레이트 688~711 / 태거베이스 709~860) 앞쪽만 허용하면 성이 자동 배제된다.
local function clampSpearAimX(pos)
	local plate = activePlate
	if not plate then return pos end
	local maxX = plate.Position.X - plate.Size.X * 0.5   -- 계단 앞 가장자리
	if pos.X <= maxX then return pos end                 -- 이미 유효 구간
	-- 성 쪽을 겨냥했다 → 계단 앞으로 당긴다. 지면 높이도 다시 잡는다.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { activeBot }
	local ray = workspace:Raycast(Vector3.new(maxX, pos.Y + 250, pos.Z),
		Vector3.new(0, -500, 0), params)
	local y = ray and (ray.Position.Y + 3) or pos.Y
	return Vector3.new(maxX, y, pos.Z)
end

-- ⚡ [콤보 2026-08-31] 블랙홀 → 에너지볼 (집결 관통형).
--   [무엇] 블랙홀 중심에 '확실히 묶인' 무리 위로 에너지볼을 즉발 관통시킨다.
--   [왜 이 조합인가] 실측으로 다른 조합을 먼저 시도했다가 폐기했다.
--     시도 A(통나무 → 블랙홀): 7회 발동, 포획 2회(1~2명), 나머지 5회는 빈 자리.
--       · 사거리: MAX_THROW_RANGE 600 인데 1단계 초반엔 러너까지 859 stud 라 클램프된다.
--         실측 로그: 콤보 좌표 X=-118 인데 투척 목표 X=186 — 300 stud 어긋났다.
--       · 노후화: 통나무 발사(2.5s) + 블랙홀 비행(2.2s) = 4.7초 전 위치를 노린다.
--         러너 속도 15~19 → 그동안 70~90 stud 이동. 흡인 반경 70 을 그대로 벗어난다.
--       통나무는 레인을 훑어서 러너가 알아서 부딪히지만, 블랙홀은 점 타격이라
--       위치 노후화에 그대로 당한다. 순서가 틀렸다.
--     시도 B(현재): 에너지볼은 즉발이라 비행 시간이 0 = 노후화도 0.
--       블랙홀이 먼저 좌표를 고정해 주고, 에너지볼은 '쏘는 순간의 최신 위치'를 때린다.
--       실측 근거: 에너지볼 한 발이 AIRunner_8·2·5 를 동시 관통했고(11:17:10),
--       그 3명이 5초 뒤 통나무에 전부 다운됐다 — 우연히 이 콤보가 일어나고 있었다.
--   ⚠️ 포획 인원 조건이 핵심이다. 없으면 빈 블랙홀 위에 에너지볼(쿨 12)까지
--     같이 버린다 = 두 개를 낭비한다. 시도 A 가 정확히 그 실패였다.
--   ⚠️ 좌표는 '투척 목표'가 아니라 '실제 활성화 좌표'를 쓴다(_G.GetActiveBlackHole).
--     실측상 15~30 stud 어긋나고, 태거 베이스 착탄 시엔 아예 활성화되지 않는다.
--   ⚠️ 봇이 상태를 들고 있지 않다. 블랙홀이 꺼지면 게터가 nil 을 주므로 콤보도
--     자동으로 끝난다 — "켜는 코드엔 끄는 코드를" 문제가 생길 여지가 없다.
local COMBO_ENABLED     = true
local COMBO_MIN_CAUGHT  = 2    -- 이 인원 이상 '중심에 고정'돼야 발동. 낮추면 자주·얕게 쓴다
local lastComboLog      = 0    -- 미발동 사유 로그 스팸 방지(2초 간격)

-- 💨 [2026-09-01] 가스 그레네이드 연기벽 → 봇 조준 악화.
--   [왜] 가스 그레네이드는 데미지 0 인 시야 차단 전용 도구인데, 비대칭 가시성이
--     클라이언트(SmokeWallFilter)에만 있다. 봇은 화면이 없어 서버 좌표를 그대로 읽으므로
--     연기 안이든 밖이든 조준이 동일했다 = vs 봇에서 이 아이템의 효과는 정확히 0 이었다.
--   [왜 '표적 상실'이 아니라 '조준 악화'인가]
--     · 연기에 가린 사람 태거는 공격을 멈추지 않는다. 안 보여도 레인 아래로 그냥 굴린다 —
--       굴리기는 정밀 조준이 필요 없다. 시야 차단의 실제 결과는 "안 던짐"이 아니라
--       "빗맞히며 던짐"이다. 조준 악화가 사람 체감의 충실한 모델이다.
--     · 연기벽은 언덕 전폭(map2 기준 Z 248)을 가로지른다. 표적을 끊으면 벽 뒤 러너가
--       전원 동시에 후보에서 사라져 봇이 10~15초간 완전 정지한다. 1단계가 65초인 판이면
--       소모품 하나로 4분의 1이 날아간다 — 착취 여지가 너무 크다.
--   ⚠️ 보수적으로 잡았다. 1단계 태거봇 성과가 넉넉하지 않아 배수를 낮게 시작한다.
--     튜닝 순서: SMOKE_ERR_MULT 를 먼저 올리고, 그래도 부족하면 SMOKE_ERR_CAP 을 푼다.
--     기준선(2026-09-01 18:49 판): 1단계 65초 처치 6/11 = 목표 달성. 이 값이 떨어지면 되돌릴 것.
--   ⚠️ 중첩 없음. 벽이 몇 개든 배수는 한 번만 적용한다.
--   ⚠️ 에미터가 켜져 있는 동안(Damage.EMIT_DURATION 10초)만 적용한다. 뒤따르는
--     페이드 5초는 제외 — 그때는 사람 눈에도 옅어서 실제로 가려주지 못한다.
--   ⚠️ 레이캐스트를 쓰지 않는다. 벽이 'Z 전폭 × X 두께 6' 인 단순 상자라,
--     "시선이 벽의 X 를 지나는 지점에서 그 Y·Z 가 상자 안인가" 로 같은 답이 정확히 나온다.
--   ⚠️ Y 검사를 빼지 말 것. 킹은 계단 위 높은 곳에 서 있어서 언덕 아래쪽 연기를
--     실제로 넘겨다보는 경우가 있다. 빼면 사람은 보이는데 봇만 눈이 머는 불공평이 된다.
local SMOKE_ERR_MULT = 2.0    -- 가려졌을 때 조준 오차 배수 (보수적 시작값)
local SMOKE_ERR_CAP  = 30     -- 배수 적용 후 최종 오차 상한(stud)
local lastSmokeLog   = 0      -- 🚧 진단 로그 스팸 방지 (발동 빈도 확인 후 로그 삭제)

local function smokeAimMult(fromPos, toPos)
	local dx = toPos.X - fromPos.X
	if math.abs(dx) < 0.001 then return 1 end

	for _, w in ipairs(workspace:GetChildren()) do
		if w:IsA("BasePart") and w.Name == "SmokeWall" then
			local wx = w.Position.X
			-- 1) 봇과 표적이 벽을 사이에 두고 있는가
			if (fromPos.X - wx) * (toPos.X - wx) < 0 then
				-- 2) 아직 연기를 뿜는 중인가 (페이드 구간 제외)
				local emitting = false
				for _, e in ipairs(w:GetChildren()) do
					if e:IsA("ParticleEmitter") and e.Enabled then emitting = true break end
				end
				if emitting then
					-- 3) 시선이 벽의 X 를 지나는 그 지점에서 실제로 상자 안인가
					local t  = (wx - fromPos.X) / dx
					local sy = fromPos.Y + (toPos.Y - fromPos.Y) * t
					local sz = fromPos.Z + (toPos.Z - fromPos.Z) * t
					if math.abs(sy - w.Position.Y) <= w.Size.Y / 2
					   and math.abs(sz - w.Position.Z) <= w.Size.Z / 2 then
						if os.clock() - lastSmokeLog > 2 then
							lastSmokeLog = os.clock()
							print(string.format(
								"[TaggerBot] 💨 연기 차단 — 조준 오차 ×%.1f (벽 X=%.0f / 시선 Y=%.0f)",
								SMOKE_ERR_MULT, wx, sy))
						end
						return SMOKE_ERR_MULT
					end
				end
			end
		end
	end
	return 1
end

local function throwAt(bot, tier, target)
	-- 🕳️ 콤보 판정: pickItem 보다 앞선다(가중치·표적 선택을 통째로 우회).
	if COMBO_ENABLED then
		local bh = _G.GetActiveBlackHole and _G.GetActiveBlackHole()
		if bh then
			local hasEB = false
			for _, x in ipairs(tier.items) do if x.item == "EnergyBall" then hasEB = true break end end
			local ebReady = (tick() - (itemLastFired["EnergyBall"] or 0))
				>= ((_G.GetItemCooldown and _G.GetItemCooldown("EnergyBall")) or 12)
			if hasEB and bh.caught >= COMBO_MIN_CAUGHT and ebReady then
				print(string.format("[TaggerBot] ⚡ 콤보 — 블랙홀 %d명 위로 에너지볼 (오차 0) @ X=%.0f Z=%.0f",
					bh.caught, bh.pos.X, bh.pos.Z))
				itemLastFired["EnergyBall"] = tick()
				local ok, e = pcall(fireItem, "EnergyBall", bh.pos)
				if not ok then warn("[TaggerBot] 콤보 발사 실패:", e) end
				return
			end
			-- 미발동 사유를 남긴다. COMBO_MIN_CAUGHT 튜닝 근거가 된다.
			if hasEB and os.clock() - lastComboLog > 2 then
				lastComboLog = os.clock()
				print(string.format("[TaggerBot] ⚡ 콤보 대기 — 포획 %d명(필요 %d) / 에너지볼 쿨 %s",
					bh.caught, COMBO_MIN_CAUGHT, ebReady and "OK" or "대기"))
			end
		end
	end

	local it = pickItem(tier)
	if not it then return end
	local err = tier.aimError * (it.errMul or 1)
	-- 💨 연기벽에 시선이 막혔으면 오차 배수. 상한을 둬서 무한정 커지지 않게 한다.
	do
		local bhrp = bot:FindFirstChild("HumanoidRootPart")
		if bhrp then
			local m = smokeAimMult(bhrp.Position, target.Position)
			if m > 1 then err = math.min(err * m, SMOKE_ERR_CAP) end
		end
	end
	local a = math.random() * math.pi * 2
	local r = math.random() * err
	local offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	local aimPos = target.Position + offset
	-- 🕳️ [버그수정 2026-08-31] 콤보용 '목적지'를 플레이트 변환 전에 따로 잡는다.
	--   [증상] 콤보 블랙홀이 매번 계단 앞(X≈699)에만 떨어졌다.
	--     실측: 투척 목표 (699,139,-729) = ItemSpawnPlate 좌표. 러너가 아니다.
	--   [원인] Wood Log 는 PLATE_ITEMS 라 아래에서 aimPos 가 '계단 위 소환 지점'으로
	--     덮어써진다. 굴리기는 조준점(러너)과 소환점(계단)이 다른데,
	--     콤보가 덮어쓴 뒤의 값(=소환점)을 기록해 블랙홀을 출발점에 던지고 있었다.
	--   [해결] 변환 전 좌표를 destPos 로 보존한다. 통나무는 계단에서 출발해
	--     이 지점으로 굴러가므로, 블랙홀도 같은 곳을 노려야 둘이 만난다.
	local destPos = aimPos
	if PLATE_ITEMS[it.item] then
		aimPos = plateSpawnPoint(aimPos, it.item == "tsunami" and TSUNAMI_SPAWN_X_OFFSET or 0)
	elseif it.item == "bear_trap" then
		aimPos = clampToPlateX(uphillSpawnPoint(bot, aimPos, TRAP_LEAD))
	else
		-- [SPEAR-AIM] Spear 등 직선 발사류: 조준점을 계단 앞까지로만 제한한다.
		--   ⚠️ clampToPlateX(소환 지점 보정)를 쓰면 안 된다. 그건 조준점을
		--      플레이트 X 범위(688~711)로 '모으는' 보정이라, 언덕(129~374) 위의
		--      러너를 노려도 314 stud 어긋나 전탄 빗나갔다(실측 2026-08-21).
		--   여기서는 상한만 건다 — 언덕 쪽은 그대로 두고 성 쪽만 잘라낸다.
		aimPos = clampSpearAimX(aimPos)
	end
	local ok, e = pcall(fireItem, it.item, aimPos)
	if not ok then warn("[TaggerBot] 발사 실패:", it.item, e) end

end

-- Stage2 최초 1회: taggerbase 강림(성→평지 경로 리스크 회피) + PushTool 장착
local function enterDuelMode(bot)
	local existing = bot:FindFirstChild("PushTool")
	if duelReady then return existing end
	-- 🚪 [2026-09-02] 성문이 무너지기 전에는 결투로 전환하지 않는다.
	--   [증상] 2단계 진입(러너가 계단 도달)과 성문 붕괴 사이 약 10초 동안 킹이
	--     PushTool 로 러너를 때렸다. 실측 08:30 판 — 진입 48.6s, 결투 전환 49.9s,
	--     성문 붕괴 58.9s. 그 사이 슬랩이 러너에게 명중했다(08:30:58.409).
	--   [왜 막나] 성문이 서 있으면 아직 공성 국면이다. 서로 직접 때릴 수 없어야 한다.
	--   [신호] TaggerHpReady 는 finalizeTaggerHp(성문 붕괴)에서만 true 가 된다.
	--     이미 복제되는 속성이라 새 플래그를 만들지 않았다.
	--   ⚠️ 곡사포·마법책은 막지 않는다. 성문이 살아 있는 동안 쓰라고 만든 수성 기물이라
	--     이 함수 밖(호출부 if inStage2 블록)에 그대로 둔다.
	--   ⚠️ duelReady 를 세우기 전에 반환한다. 안 그러면 한 번 막힌 뒤 영영 전환 안 된다.
	if game:GetService("ReplicatedStorage"):GetAttribute("TaggerHpReady") ~= true then
		return existing   -- 보통 nil. 호출부는 이미 nil 을 견딘다(아래 템플릿 없음 분기와 동일)
	end
	duelReady = true
	-- (텔레포트 제거) 성은 벽 역할만이라 KING이 이미 평지 레벨에 있음 → 제자리에서 결투 시작.
	local tool = existing
	if not tool then
		local tpl = game:GetService("ReplicatedStorage"):FindFirstChild("PushTool")
		if tpl then
			tool = tpl:Clone()
			tool.Parent = bot
		end
	end
	print("[TaggerBot] ⚔️ Stage 2 — PushTool 장착 (제자리 결투) (" .. tostring(tool ~= nil) .. ")")
	return tool
end

-- ── AI 루프 ──────────────────────────────────────────
local function startAI(bot, tier)
	botRunning = true
	task.spawn(function()
		local grace = (tier and GRACE_BY_TIER[tier.name]) or GRACE_TIME
		print(string.format("👑 [TaggerBot] %s 티어 — %d초 후 공격 시작", tier and tier.name or "?", grace))
		task.wait(grace)
		local hum = bot:FindFirstChildOfClass("Humanoid")
		-- [BOTIDLE-DIAG] 봇이 행동하지 못할 때 "왜"를 남긴다.
		--   증상(소환0/이동0/2단계 미진입)이 Frozen 대기와 루프 종료 양쪽에서 똑같이 나와
		--   기존 로그로는 구분이 안 됐다(2026-08-20 easy 라운드).
		local frozenSince = nil    -- Frozen 이 시작된 시각 (nil = 안 걸림)
		local frozenWarned = false -- 경고 1회만
		while botRunning and bot.Parent and hum and hum.Health > 0 do
			-- 라운드 종료(킬 이펙트 연출·정리 중)면 행동 정지 — stop()이 올 때까지 대기만
			if _G.IsRoundLive and not _G.IsRoundLive() then
				task.wait(0.5)
				continue
			end
			-- ❄️ Ice Bow 봉인: 유저 태거는 Player Attribute "Frozen" 으로 아이템 스폰이 막히는데,
			--    봇은 Player 가 없어 그 경로를 타지 않아 사실상 무효였다. 봇 캐릭터 속성으로 동일 처리.
			--    1단계=투척 중지, 2단계=결투 행동 중지. PushTool 은 Ice Bow 쪽에서 Enabled=false 로 봉인.
			if bot:GetAttribute("MicBombed") then
				-- [MICBOMB-SEAL] 마이크밤 콘서트 중에는 행동을 통째로 멈춘다.
				--   ⚠️ Frozen 을 재사용하지 않는 이유: 아래 FROZEN_MAX_HOLD(8초) 안전망이
				--      콘서트 길이(8초)와 정확히 겹쳐 경계에서 발동하고,
				--      711~713행이 봉인된 Tool 을 자동 복구해버린다.
				--   해제는 MicBombSystem 이 콘서트 종료 시 담당한다.
				task.wait(0.2)
				continue
			end

			-- 💀 [2026-08-29] 처형 연출 중에는 아무것도 하지 않는다.
			--   [증상] KING 이 Punch 처형에 걸린 3.8초 동안 계속 차징·공격했다
			--     (실측 17:32:02.797 [Punch] start → 06.613 death 사이에 SLAP 명중 다수).
			--     죽은 뒤 06.896 에 강타가 발동하기까지 했다.
			--   [원인] punch/tornado/portal 은 freezeCharacter 를 부르지 않는다(물리 사출이 필요).
			--     그래서 아래 Frozen 검사에 안 걸렸다.
			--   [해결] ItemDamageSystem.ExecuteKillEffect 가 세우는 공용 마커를 본다.
			--     ⚠️ 효과별 속성(PunchActive 등) 6개를 각각 검사하지 않는다 —
			--       7번째가 생기면 또 빠진다. 공용 마커 한 개만 본다.
			if bot:GetAttribute("InKillSequence") then
				task.wait(0.2)
				continue
			end
			if bot:GetAttribute("Frozen") then
				-- [FROZEN-SELFHEAL] Ice Bow 의 해제 예약은 Tool:Destroy 와 함께 소멸할 수 있다
				--   (해제가 task.delay(3) 인데 Tool 은 탄약 소진 0.3초 뒤 파괴 → 스크립트 스레드 종료).
				--   Frozen 을 지우는 곳이 Ice Bow 와 TestCommands 뿐이고 라운드 정리도 없어서,
				--   한 번 새면 봇이 라운드 내내 완전 무력화된다(실측: 69초간 행동 0).
				--   근본 수정은 Ice Bow 쪽. 여기는 봇이 통째로 죽는 것만은 막는 안전망이다.
				local now = tick()
				if not frozenSince then frozenSince = now end
				local held = now - frozenSince
				if held >= FROZEN_MAX_HOLD then
					warn(string.format("[BotIdle] Frozen %.1f초 지속 → 강제 해제 (Ice Bow 해제 누락 의심)", held))
					bot:SetAttribute("Frozen", nil)
					frozenSince = nil
					frozenWarned = false
					-- 봉인된 Tool 도 같이 복구 (해제 스레드가 죽었으면 재활성화도 안 됐다)
					for _, t in ipairs(bot:GetChildren()) do
						if t:IsA("Tool") and not t.Enabled then t.Enabled = true end
					end
				else
					if not frozenWarned and held >= FROZEN_WARN_AFTER then
						frozenWarned = true
						warn(string.format("[BotIdle] Frozen %.1f초째 — 대기 중", held))
					end
					task.wait(0.2)
					continue
				end
			elseif frozenSince then
				print(string.format("[BotIdle] Frozen 해제됨 (지속 %.1f초)", tick() - frozenSince))
				frozenSince = nil
				frozenWarned = false
			end
			local inStage2 = _G.Stage2TriggerSystem and _G.Stage2TriggerSystem.isActive()
			if inStage2 then
				-- ⚔️ Phase 2: 결투(평지) + 하이브리드(떨어진 러너는 투척 마무리)
				local tool = enterDuelMode(bot)

				-- 🎯📖 [2026-08-29] 2단계 고정 기물(곡사포·마법책)도 쓴다.
				--   [왜] 봇 킹은 2단계에 슬랩만 썼다. 실제 태거는 기물까지 쓰므로
				--     봇 상대 측정이 실전보다 후하게 나온다.
				--   ⚠️ 쿨다운은 각 시스템이 관리한다(CannonReadyAt 속성). 여기선 주기적으로
				--     부르기만 하면 되고, 쿨 중이면 그쪽에서 false 를 돌려준다.
				--   ⚠️ 성문이 무너지면 기물도 함께 파괴된다 — 그 뒤엔 findCannons 가 비어
				--     자연히 0 을 돌려준다. 별도 가드가 필요 없다.
				--   ⚠️ map1 에는 마법책이 없다. 0 반환이 정상이다.
				do
					local now3 = tick()
					if now3 - lastFixtureUse >= FIXTURE_INTERVAL then
						lastFixtureUse = now3
						local okC, firedC = pcall(function()
							return _G.FireCannonForBot and _G.FireCannonForBot() or 0
						end)
						local okM, castM = pcall(function()
							return _G.CastMagicBookForBot and _G.CastMagicBookForBot() or 0
						end)
						if okC and okM and ((firedC or 0) + (castM or 0)) > 0 then
							print(string.format("[TaggerBot] 🎯 기물 사용 — 곡사포 %d / 마법책 %d",
								firedC or 0, castM or 0))
						end
					end
				end

				-- 🏆 [2026-08-30] A선 / B선 전환 판정.
				--   게이지가 임계를 넘으면 성문을 포기하고 점령지로 내려간다.
				--   ⚠️ 이력(hysteresis)을 둔다. 단일 임계면 경계에서 A/B 를 오가며 덜덜 떤다.
				--     한 번 내려가면 게이지가 거의 0 이 될 때까지 존을 지킨다.
				do
					local cs = _G.CaptureSystem
					local p = (cs and cs.getProgress) and cs.getProgress() or 0
					-- 🏆 침범 신호: 차오르는 중이면 존, 감쇠 중이면 nil.
					--   "지금 누가 존을 밟고 있나"와 같은 뜻이라 그대로 쓴다.
					local intruded = ((cs and cs.getActiveZone) and cs.getActiveZone()) ~= nil

					if not zoneDefense and intruded then
						-- ⚠️ [2026-08-31] '이별 일격'(떠나기 전 강타 한 방)을 폐기했다.
						--   [측정] 차징음→발동 2.0초 + WINDUP 0.15 + HIT_WINDOW 0.4
						--     = 강타는 시전부터 판정까지 2.15~2.55초 걸린다.
						--     쏘고 바로 걸어가면 판정 시점엔 봇이 33 stud 밖이라 반드시 빗맞는다.
						--   [왜 치명적인가] PushTool.Server:727 — 빗맞힌 강타도 CHARGED_COOLDOWN
						--     7.0초를 전액 문다(WHIFF_COOLDOWN 1.2 는 기본 슬랩 전용).
						--     이동 4.7~6.0초 뒤 존에 도착하면 주력기가 쿨이고,
						--     확보 시간 12~25초 중 7초를 반쪽 화력으로 보낸다.
						--     강타는 존 교전 화력의 절반이다(8초 사이클 대상당 60 중 28.3, n=2).
						--   [기다리는 것도 답이 아니다] 트리거가 0% 로 내려온 지금
						--     2.5초 대기 = 게이지 25% = 존 체류 7.5초(r=2)에 해당한다.
						--     그 7.5초에 낼 딜(대상당 46)이 강타 한 방(28.3)보다 크다.
						--   ⚠️ 옛 명분 "강타는 쿨 7초라 아껴봐야 의미 없다"는 폐기한다.
						--     존에서 쓸 데가 생겼으므로 이제 아끼는 게 이득이다.
						--   ⚠️ 하강 시점에 이미 차징 중이면 그 강타는 어차피 빗나간다(7초 소모).
						--     막을 방법이 없는 매몰 비용이므로 기다리지 않는다.
						zoneDefense = true
						zoneEnterAt = os.clock()
						-- 🏃 [2026-09-02] 존 복귀 이속 버프. 봇 킹 전용.
						--   [왜] 위 주석의 실측대로 계단(홀드 라인)에서 존까지 4.7~6.0초가 걸린다.
						--     그동안 러너는 이미 25% 를 채운다(실측 23:47 판: 하강 08.598 → 25% 10.865).
						--     즉 밀림이 없어도 초기 도달 공백만으로 4분의 1을 내준다.
						--   [왜 이속인가] 사람은 위치를 유연하게 판단하지만 봇은 그 로직이 사실상 불가능하다.
						--     판단력을 판단력으로 메우려면 복잡해지고, 이동 속도로 메우면 상수 하나다.
						--   [값] 14 → 18. 도달 4.7~6.0 → 3.7~4.7초. 25% 를 채우기 전에 도착하되
						--     러너가 "왔네" 하고 반응할 여유는 남는 수준이다(22 는 급작스럽다).
						--   ⚠️ 봇 전용이다. 유저 킹은 스스로 위치를 판단하므로 주지 않는다.
						--     대신 유저 킹은 이 공백을 판단으로 메워야 한다 — 의도된 비대칭이다.
						--   ⚠️ 밀림(건틀렛 풀차징 87 stud + 래그돌)까지는 못 이긴다. 그건 별개 축이다.
						--     이 버프는 '초기 도달 공백'만 겨냥한다.
						--   ⚠️ 2단계 감속(16→14)과 충돌하지 않게, 복귀 시 원래 값으로 되돌린다.
						-- ⚠️ 이 루프가 1190 행에서 잡아둔 hum 을 그대로 쓴다.
						--   bot 은 여기서 스코프 밖이라(선언이 spawnBot 내부와 호출부뿐)
						--   bot:FindFirstChildOfClass 로 쓰면 nil 이 되어 조용히 아무 일도 안 한다.
						-- 🏃 [2026-09-18] WalkSpeedManager 로 이관. 직접 대입을 버린다.
						--   [증상] 히어로 슬램에 맞은 봇 킹의 모션·이속이 이상해졌다(실측 09-18).
						--   [원인] 같은 WalkSpeed 를 두 시스템이 각자 쥐고 있었다.
						--     여기        hum.WalkSpeed = ... 직접 대입
						--     HammerHigh  _G.WalkSpeed.set(char, "HammerSlam:…", { walk = 0 })
						--     슬램 스턴(1.2초) 안에 존 전환이 일어나면 서로 덮어쓴다 —
						--     매니저가 이기면 봇이 방금 정한 속도가 지워지고,
						--     봇이 이기면 CC 의 walk=0 이 풀려 스턴이 무효가 된다.
						--   ⚠️ 매니저가 존재하는 이유가 정확히 이것이다. 헤더에 적힌 원인 —
						--     "여러 시스템이 같은 WalkSpeed 를 각자 백업·복원". 미이관 목록에
						--     TaggerBotSystem 만 빠져 있었다.
						--   [규칙] 이건 '기준값' 변경이지 CC 가 아니다. 그래서 set 이 아니라 setBase 다.
						--     매니저 헤더가 이 용도를 명시한다 — "기준값 변경(2단계 태거 감속 등)".
						--     기준을 바꾸면 슬램의 배율 0 이 그 위에 얹혀 둘 다 산다.
						--   ⚠️ 매니저는 캐릭터를 받는다. 이 스코프엔 hum 뿐이라 hum.Parent 를 쓴다
						--     (바로 위 주석 참조 — bot 은 여기서 nil 이다).
						--   ⚠️ 폴백을 남긴다. 부팅 순서가 바뀌어 매니저가 없으면 봇이 아예 안 움직인다.
						if hum then
							if _G.WalkSpeed then _G.WalkSpeed.setBase(hum.Parent, ZONE_RUSH_SPEED)
							else hum.WalkSpeed = ZONE_RUSH_SPEED end
						end
						print(string.format("[TaggerBot] 🏆 라인 하강 — 존 침범 감지 (점령 %.0f%%) → 존 방어로 전환", p * 100))
					elseif zoneDefense and not intruded and p <= CAPTURE_RELEASE_AT
					       and (os.clock() - zoneEnterAt) >= ZONE_MIN_HOLD then
						-- ⚠️ 두 조건을 함께 본다. 존이 비었어도 게이지가 남아 있으면 안 돌아간다 —
						--   감쇠(0.5/s)가 다 빠질 때까지 버티는 게 곧 이력(hysteresis)이다.
						--   깊이 들어왔을수록 오래 지킨다: 40% 면 7초, 10% 면 1초.
						zoneDefense = false
						lastZoneTarget = nil
						-- 🏃 존 복귀 이속 버프 해제("켜는 코드에는 끄는 코드를 같이").
						--   안 되돌리면 성문으로 돌아간 뒤에도 계속 빨라 2단계 감속(16→14)이 무의미해진다.
						-- ⚠️ 위 ZONE_RUSH_SPEED 와 한 짝이다. 한쪽만 이관하면 켜는 쪽과 끄는 쪽이
						--   서로 다른 창구를 써서 버프가 영영 안 풀린다.
						if hum then
							if _G.WalkSpeed then _G.WalkSpeed.setBase(hum.Parent, STAGE2_SPEED)
							else hum.WalkSpeed = STAGE2_SPEED end
						end
						print("[TaggerBot] 🚪 라인 복귀 — 존 비고 게이지 소진, 성문으로")
					end
				end

				-- 🏆 B선: 존 위로 간다. 존에 서 있는 것만으로 KING_POWER 가 걸려 진행이 멈춘다.
				--   ⚠️ 때리는 게 목적이 아니다. '서 있는 것'이 일이다 — 아래 결투 로직은 그대로 두고
				--     이동 목표만 존으로 덮는다. 사거리 안에 러너가 들어오면 평소대로 친다.
				--   ⚠️ 존이 둘이라 게이지만으론 어디로 갈지 모른다. CaptureSystem 이 매 틱 고르는
				--     '지금 채우고 있는 존'을 그대로 따른다(getActiveZone).
				local zoneTarget = nil
				if zoneDefense then
					local cs = _G.CaptureSystem
					zoneTarget = (cs and cs.getActiveZone) and cs.getActiveZone() or nil
					-- ⚠️ 감쇠 중이면 nil 이 온다. 그때는 마지막 존을 계속 본다(위 캐시 주석 참고).
					if zoneTarget then lastZoneTarget = zoneTarget else zoneTarget = lastZoneTarget end
				end

				local target = pickDuelTarget(bot, tier)   -- Stage2: 유저 우선

				-- 🏆 B선 이동 덮어쓰기. 결투 로직의 MoveTo 를 한 곳에서 가로챈다.
				--   ⚠️ 개별 MoveTo 를 각각 고치지 않는다. 분기가 셋(접근/후퇴/유지)이라
				--     하나라도 빠뜨리면 그 경로에서만 존을 벗어난다 — 찾기 어려운 종류의 버그다.
				--   ⚠️ [회귀수정 2026-08-31] 예전엔 반경 안에 들어오면 MoveTo(제자리)로 굳혔다.
				--     그러면 봇이 '중심에서 10 stud 떨어진 아무 지점'에 멈추고, 반대편 꼭짓점
				--     (중심에서 15.6)에 선 러너와는 최대 25.6 stud 가 벌어진다.
				--     SWING_RANGE 9 밖이라 영영 못 때린다 — 존 넓이의 절반이 사각지대였다.
				--     "존 방어 = 서 있기"로 읽은 게 잘못이고, "존 안에서 싸우기"여야 한다.
				--   [해결] 굳히지 말고 결투 로직이 원하는 위치를 '리시 원'으로 잘라 그대로 따른다.
				--     존 안에서는 자유롭게 쫓고, 존을 벗어나는 이동만 잘린다.
				--     멀리 있을 때도 클램프가 존 가장자리를 가리키므로 '존으로 이동'이 자동으로 된다
				--     — 분기 하나로 접근·추격·유지가 전부 처리된다.
				--   [리시 10 근거] 존은 22x22 → 중심~변 11 / 중심~꼭짓점 15.6.
				--     10 이면 항상 존 안(10 < 11)이라 KING_POWER 가 유지되고,
				--     꼭짓점 러너까지 15.6 - 10 = 5.6 으로 SWING_RANGE 9 안에 들어온다.
				--     즉 이 한 값으로 존 전역이 사거리에 들어온다. 11 을 넘기면 존 밖으로
				--     새어 KING_POWER 를 잃으므로 올리지 말 것.
				local ZONE_LEASH = 10
				local function clampToZone(center, p)
					local flat = Vector3.new(p.X - center.X, 0, p.Z - center.Z)
					if flat.Magnitude <= ZONE_LEASH then return p end
					local c = center + flat.Unit * ZONE_LEASH
					return Vector3.new(c.X, p.Y, c.Z)
				end
				local function moveDuel(hum2, pos)
					-- 🛑 [2026-09-18] 부양 스턴 중에는 이동 명령을 걸지 않는다.
					--   [증상] 슬램에 맞은 봇 킹이 늘어진 자세("탈진 모션")로 이상하게 움직였다.
					--   [원인] PlatformStand = true 면 휴머노이드가 늘어진다 — 그 자세 자체가
					--     네가 본 탈진 모션이다. 그런데 이 루프가 그 상태에서도 매 틱 MoveTo 를
					--     걸어, 늘어진 몸이 끌려다니는 그림이 됐다.
					--   [선례] PushTool.Server:1140 이 같은 구멍을 이미 기록해 뒀다 —
					--     "TaggerBotSystem 전체에 PlatformStand 참조가 하나도 없어서,
					--      AI 루프가 공중에 뜬 채로 평소처럼 계속 때린다."
					--     그때 공격 경로는 막혔고 **이동 경로가 남아 있었다.**
					--   [규칙] 상태를 묻고 건너뛰기만 한다. 되돌릴 게 없으므로
					--     "끄는 코드에 도달 못 해서 고착" 사고가 구조적으로 안 생긴다.
					--     스턴이 풀리면 다음 틱에 저절로 재개된다.
					--   ⚠️ PlatformStand 만 본다. Stunned 는 소유자가 셋(카타나·푸시툴·왕좌탈진)이고
					--     지속이 제각각이라 여기서 이동을 막으면 킹이 길게 굳을 수 있다.
					--     HammerStunned 는 매니저가 platformStand 와 같이 걸므로 이미 덮인다.
					if not hum2 then return end
					if hum2.PlatformStand then return end
					if zoneTarget then
						local here = bot:FindFirstChild("HumanoidRootPart")
						local want = pos or (here and here.Position)
						if not want then hum2:MoveTo(zoneTarget.Position) return end
						hum2:MoveTo(clampToZone(zoneTarget.Position, want))
						return
					end
					hum2:MoveTo(pos)
				end
				local hrp = bot:FindFirstChild("HumanoidRootPart")

				-- 🏆 [2026-08-31] B선 이동을 결투 분기보다 먼저 확정한다.
				--   [증상] 존 하나를 밟았다가 다른 존으로 옮기면 봇이 따라오지 않았다(실측 제보).
				--   [원인] 존 덮어쓰기가 moveDuel 안에만 있었는데, moveDuel 을 아예 거치지 않는
				--     경로가 있다 — 원거리 그랩 분기(발사만 하고 이동 명령 없음)와
				--     표적이 계단 아래일 때의 투척 모드 분기. 그 틱 동안 봇은 이전 존에 머문다.
				--   ⚠️ 위 moveDuel 주석의 "분기가 셋이라 하나라도 빠뜨리면 안 된다"는 경고가
				--     정확했는데, 정작 그 함수를 '호출하지 않는' 경로가 있어서 뚫렸다.
				--     그래서 분기를 늘리는 대신 이동 권한을 한 단계 위로 올린다.
				--   ⚠️ 결투 '행동'(스윙·그랩·투척)은 건드리지 않는다. '이동'만 덮는다.
				--   ⚠️ 아래 moveDuel 도 같은 판정을 하므로 같은 틱에 두 번 불려도 결과가 같다.
				--   ⚠️ zoneCommuting 은 아래 강제 회전이 읽는다(선언 ≺ 사용).
				local zoneCommuting = false
				if zoneTarget and hum and hrp then
					local dz = (Vector3.new(hrp.Position.X - zoneTarget.Position.X, 0,
					                        hrp.Position.Z - zoneTarget.Position.Z)).Magnitude
					if dz > ZONE_LEASH then
						hum:MoveTo(zoneTarget.Position)
						zoneCommuting = true
					end
				end

				-- 🔬 [진단 2026-09-03] 존 방어 중 이동 실태. 읽는 법은 DBG_ZONE 선언부 주석 참조.
				--   ⚠️ 여기서 읽는 MoveDirection·속도는 '지난 틱 명령의 결과'다. 그래서
				--     이번 틱 결투 MoveTo 보다 먼저 찍어야 순수한 결과가 나온다.
				if DBG_ZONE and zoneDefense and hum and hrp and (os.clock() - dbgZoneLast) >= 1.0 then
					dbgZoneLast = os.clock()
					-- ⚠️ [프로브 수정 2026-09-03] MoveDirection 을 버리고 실제 속도 벡터로 잰다.
					--   [왜] 실측 30줄 전부 MoveDirection=0.00 이었는데 같은 줄의 속도는 18.0
					--     (= WalkSpeed 그대로)이었다. 봇은 분명히 걷고 있는데 이 속성은 0 이다.
					--     서버 소유 NPC Humanoid 에서 신뢰할 수 없는 값이라 판단하고 교체한다.
					--   실제 속도 벡터는 밀림·중력까지 섞이지만, "지금 어디로 가고 있나"는 정확하다.
					local v3  = hrp.AssemblyLinearVelocity
					local hvz = Vector3.new(v3.X, 0, v3.Z)
					local spd = hvz.Magnitude
					local dz3, align = -1, 0
					if zoneTarget then
						local toZ = Vector3.new(zoneTarget.Position.X - hrp.Position.X, 0,
						                        zoneTarget.Position.Z - hrp.Position.Z)
						dz3 = toZ.Magnitude
						if dz3 > 0.1 and spd > 0.5 then
							align = toZ.Unit:Dot(hvz.Unit)
						end
					end
					-- ⚠️ pickDuelTarget 은 Model 이 아니라 HumanoidRootPart 를 준다.
					--   그대로 찍으면 표적이 전부 "HumanoidRootPart" 로 나와 누군지 알 수 없다.
					local tname = "없음"
					if target then
						tname = (target:IsA("BasePart") and target.Parent and target.Parent.Name)
						        or target.Name
					end
					print(string.format(
						"🔬 [Zone] 존=%s 거리=%s | 정렬=%+.2f 속도=%.1f WS=%d | 상태=%s | 표적=%s",
						zoneTarget and zoneTarget.Name or "nil",
						dz3 >= 0 and string.format("%.0f", dz3) or "?",
						align, spd, math.floor(hum.WalkSpeed + 0.5),
						hum:GetState().Name, tname))
				end

				if target and tool and hrp then
					local plateX = activePlate and activePlate.Position.X or (hrp.Position.X - 60)
					if target.Position.X > plateX - 5 then
						-- 결투: 추격 → 사거리 내 스윙(주력)/그랩(보조)
						local duel = DUEL_PARAMS[tier.name] or DUEL_PARAMS.normal
						local dist = (target.Position - hrp.Position).Magnitude
						if dist > SWING_RANGE then
							-- [BOT-GRAB-RANGE] 접근 중에도 그랩은 쏜다.
							--   예전엔 SWING_RANGE(9) 안에 들어와야만 그랩이 나갔다. 그런데 그랩의
							--   실제 사거리는 GRAB_MAX_RANGE=50 이라, 봇만 코앞까지 붙어서 쏘는 꼴이었고
							--   손이 즉시 닿아 0.3초 비행 연출이 사라졌다("모션 없이 스턴").
							--   유저처럼 중거리에서 조준해 던지게 한다.
							local now2 = tick()
							if now2 - lastDuelAction >= duel.swingInterval
							   and dist >= GRAB_RANGE_MIN and dist <= GRAB_RANGE_MAX
							   and math.random() < (duel.grabChance or 0) then
								local be2 = tool and tool:FindFirstChild("BotAction")
								-- 던지기 전 표적을 향해 몸을 돌린다(유저의 조준 재현)
								local flat2 = Vector3.new(target.Position.X - hrp.Position.X, 0,
								                          target.Position.Z - hrp.Position.Z)
								if flat2.Magnitude > 0.5 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat2)
								end
								lastDuelAction = now2
								grabComboUntil = now2 + GRAB_COMBO_WINDOW
								-- 🖐️ [2026-09-18] "ChargedPush" → "Grab".
								--   [증상] 이 분기는 그랩 조건(거리 40 · grabChance · lookAt 조준)을
								--     판정해 놓고 강타 액션을 쐈다. 09-11 Q 광역 그랩 부활 때
								--     PushTool.Server 의 봇 "Grab" 분기가 폐기 상태(return)라
								--     되돌릴 곳이 없어 강타 이름을 그대로 쓰고 있었던 것으로 보인다.
								--   [결과] 봇 킹은 그랩을 한 번도 못 썼고, 강타가 그랩 사거리(약 40)에서
								--     발사돼 대부분 허공이었다. 부채꼴 예고도 안 나왔다.
								--   ⚠️ PushTool.Server 의 BotAction "Grab" 분기(beginGrab 호출)와 짝이다.
								--     한쪽만 고치면 아무것도 안 바뀐다.
								--   ⚠️ beginGrab 은 인자를 안 받는다. 방향은 시전 순간의 캐릭터 정면을
								--     쓰므로, 바로 위 lookAt(flat2) 조준이 곧 그랩 방향이 된다 —
								--     그 줄을 지우면 그랩이 엉뚱한 곳을 향한다.
								if be2 then be2:Fire("Grab") end
							-- 👊 [2026-09-05] 이동 중 기회 타격.
							--   [증상] 봇 킹이 2단계 33초 동안 7번밖에 못 때렸다(easy 기준 이론 16회).
							--     easy 의 swingInterval(2.0)이 느린 게 아니라 '때릴 기회 자체'가 없었다.
							--   [원인] 스윙은 dist <= SWING_RANGE(9) 인 아래 분기에서만 나간다. 그런데
							--     봇 킹은 존 두 개를 왕복하느라(실측: 거리 74→58→39→20→39→21→11…)
							--     9 stud 안에 들어오는 순간이 거의 없다. 이동만 하다 라운드가 끝났다.
							--   ⚠️ 왕복 자체는 고치지 않는다 — 09-04 문서에 "안티캠핑 기능이지
							--     병목이 아니다"로 명시돼 있다. 대신 그 시간을 낭비가 아니게 만든다.
							--   [규칙] 경로에 걸린 러너를 지나가며 친다. 유저 킹도 그렇게 한다.
							--     ① 멈추지 않는다(moveDuel 을 안 부름) — 멈추면 존 도착이 늦어진다.
							--     ② 계단 방향(PUSH_OUT) 고정 — 아래 규칙과 동일하게 유지한다.
							--     ③ 같은 lastDuelAction 쿨을 쓴다. 이동 중이라고 더 자주 치지 않는다.
							elseif now2 - lastDuelAction >= duel.swingInterval
							   and dist <= SWING_RANGE + PASSBY_SWING_BONUS then
								lastDuelAction = now2
								local be3 = tool and tool:FindFirstChild("BotAction")
								if be3 then be3:Fire("Push", PUSH_OUT) end
								stage2ThrowHint = tick()
							else
								moveDuel(hum, computeApproachPos(bot, target))   -- 각이 서는 위치로 돌아 들어간다
							end
						else
							-- 각이 안 서면 제자리에 멈추지 말고 각이 서는 쪽으로 재배치한다.
							--   예전엔 사거리 안이면 무조건 정지 → 표적이 알아서 좋은 위치에 와야만 각이 섰다.
							--   (이게 '멀뚱멀뚱 서서 쿨만 기다린다'의 정체)
							-- 밀친 직후에는 소환 거리를 확보하려 물러난다.
							--   실측 교착(2026-08): 밀치고 계속 붙어 있으면 거리 9.7 < MIN_SPAWN_DIST(20) 라
							--   아이템을 영영 못 쓰고, AI 러너는 봇을 못 죽여 무한 교착이 됐다.
							--   각이 섰다고 제자리를 지키면 안 되고, '밀고 → 물러나 던진다'가 한 동작이어야 한다.
							if (tick() - stage2ThrowHint) <= HINT_WINDOW then
								-- 방금 밀었다 → 소환 거리가 나올 때까지 +X 로 후퇴
								moveDuel(hum, retreatPos(bot, target))
							elseif evaluateKillAngle(bot, target) then
								moveDuel(hum, hrp.Position)   -- 각이 섰으면 자세를 유지
							else
								moveDuel(hum, computeApproachPos(bot, target))
							end
							-- ⚠️ [2026-08-31] 존으로 이동 중이면 이 회전을 건너뛴다.
							--   [증상] 존 왕복 중 러너를 스치면 봇이 부들부들 떨거나 홱홱 돌았다.
							--   [원인] MoveTo 가 AutoRotate(기본 true, 이 스크립트는 끄지 않는다)로
							--     진행 방향을 보게 하는데, 여기서 매 틱 표적 쪽으로 CFrame 을
							--     덮어써 둘이 매 프레임 싸운다.
							--   [왜 빼도 되나] 넉백 방향은 PUSH_OUT(-1,0,0) 계단 고정이라
							--     몸이 어디를 보든 결과가 같다 — 이 회전은 순전히 연출이다.
							--   ⚠️ 도착해 자리를 지킬 때는 zoneCommuting 이 false 라 그대로 회전한다.
							--   ⚠️ 위 원거리 그랩의 lookAt(flat2)은 건드리지 말 것 —
							--     그건 실제 발사 방향을 만드는 조준이라 연출이 아니다.
							local flat = Vector3.new(target.Position.X - hrp.Position.X, 0, target.Position.Z - hrp.Position.Z)
							if flat.Magnitude > 0.5 and not zoneCommuting then
								hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
							end
							local be = tool:FindFirstChild("BotAction")
							-- 넉백 방향 결정: 즉사각(러너→플레이트) 또는 순진(봇→러너)
							local aimDir = (target.Position - hrp.Position).Unit
							if activePlate and math.random() < (duel.aimPlateChance or 0) then
								local toPlate = Vector3.new(activePlate.Position.X - target.Position.X, 0, activePlate.Position.Z - target.Position.Z)
								if toPlate.Magnitude > 0.5 then aimDir = toPlate.Unit end
							end
							local now = tick()
							-- ── 결투 행동 규칙 ──────────────────────────────────────────
							-- PUSH_IS_ALWAYS_DOWNHILL: Push 는 항상 계단 방향(-X)으로만 한다.
							--   러너를 계단으로 밀어 소환 영역에 넣는 것이 유일한 처치 경로이므로,
							--   다른 방향으로 미는 건 의미가 없다(예전엔 aimDir 로 아무 쪽이나 밀었다).
							-- Grab 은 그 각을 만들기 위한 보조다.
							--   러너를 끌어오면 끌려온 위치가 봇의 -X 쪽이 되므로,
							--   Grab 자체가 '봇을 러너보다 +X 쪽에 놓는' 결과를 만든다.
							--   → 벽이 어디 있는지 볼 필요가 없다. 좌표 비교 하나로 끝난다.
							--   (예전엔 표적 뒤 벽을 레이캐스트로 찾았는데, 벽의 정의가 맵마다 달라 복잡했다)
							--    도입 후엔 잡을 상황 자체가 줄었다)
							local PUSH_OUT = Vector3.new(-1, 0, 0)   -- 계단 방향 고정
							local ANGLE_MARGIN = 2                   -- 봇이 러너보다 이만큼 +X 쪽이어야 각으로 침
							local canPushDownhill = hrp.Position.X > target.Position.X + ANGLE_MARGIN
							
							if now < grabComboUntil then
								-- 그랩 콤보 창: 끌어온 직후라 각이 서 있다. 바로 계단으로 민다.
								if be then be:Fire("Push", PUSH_OUT) end
								stage2ThrowHint = tick()
								lastDuelAction = now
							elseif now - lastDuelAction >= duel.swingInterval then
								lastDuelAction = now
								if canPushDownhill then
									if be then be:Fire("Push", PUSH_OUT) end
									stage2ThrowHint = tick()   -- 민 직후 아이템을 앞당겨 던지도록
								else
									-- 각이 없다 = 봇이 러너보다 계단 쪽에 있다. 끌어와서 각을 만든다.
									grabComboUntil = now + GRAB_COMBO_WINDOW
									if be then be:Fire("ChargedPush", (target.Position - hrp.Position).Unit) end
								end
							end
						end
						-- 결투와 병행해 아이템 투척. swingInterval(5~6초) 동안 놀지 않게 한다.
						--   Stage 1 과 같은 fireInterval 을 쓰되, 표적은 pickThrowTarget 이 고른다
						--   (밀어낸 상대가 소환 영역 안이면 그쪽 우선, 아니면 가장 먼 러너).
						do
							local nowT = tick()
							local jit = 0.85 + math.random() * 0.3
							-- 각을 잡고 민 직후에는 쿨을 무시하고 바로 던진다(콤보 성립창).
							local hinted = (nowT - stage2ThrowHint) <= HINT_WINDOW
							if hinted or nowT - lastStage2Throw >= tier.fireInterval * jit then
								local thrower = pickThrowTarget(bot, target)
								if thrower then
									lastStage2Throw = nowT
									throwAt(bot, tier, thrower)
								end
							end
						end
						task.wait(DUEL_TICK)
					else
						-- 하이브리드: 계단 아래로 떨어진 러너 → 플레이트 굴리기로 마무리
						-- 🚶 [2026-09-01] 문턱까지 나가서 표적 레인에 맞춰 선다.
						--   [증상] 마지막 러너가 언덕 멀리 있으면 봇이 한 발짝도 안 움직여
						--     "멈춰 있다"로 보였다. 이 분기에 이동 코드가 아예 없었다.
						--   [왜 끝까지 쫓지 않나] 쫓는 게 오히려 지는 수다 —
						--     ① 시간이 가면 태거가 이긴다(타임아웃 승). 러너가 와야 한다.
						--     ② 언덕으로 내려가면 점령존이 비어 러너가 돌아 들어간다.
						--     그래서 '문턱 방어'가 정답이고, 문제는 전략이 아니라 가독성이었다.
						--   [무엇을 하나] 플레이트 앞 문턱으로 이동하되 표적의 Z 라인에 맞춘다.
						--     러너가 어느 레인으로 올라오든 그쪽을 막고 선 그림이 된다.
						--   ⚠️ 도착 전에는 MoveTo 만, 도착 후에만 lookAt 을 쓴다.
						--     둘을 같은 틱에 쓰면 AutoRotate 와 CFrame 이 매 프레임 싸워
						--     봇이 부들부들 떤다(1318행 주석의 사고와 같은 유형).
						if activePlate and hrp then
							local goal = Vector3.new(activePlate.Position.X + PLATE_X_TOL,
							                         hrp.Position.Y, target.Position.Z)
							local flat = Vector3.new(goal.X - hrp.Position.X, 0, goal.Z - hrp.Position.Z)
							if flat.Magnitude > 4 then
								hum:MoveTo(goal)
							else
								local face = Vector3.new(target.Position.X - hrp.Position.X, 0,
								                         target.Position.Z - hrp.Position.Z)
								if face.Magnitude > 0.5 then
									hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + face)
								end
							end
						end
						throwAt(bot, tier, target)
						local jitter = 0.8 + math.random() * 0.4
						task.wait(tier.fireInterval * jitter)
					end
				else
					task.wait(0.5)
				end
			else
				local target = pickTarget(bot, tier)
				if target then throwAt(bot, tier, target) end
				local jitter = 0.8 + math.random() * 0.4
				task.wait(tier.fireInterval * jitter)
			end
		end
		-- [BOTIDLE-DIAG] 루프가 끝난 사유. Frozen 대기(위)와 구분하기 위한 짝.
		--   stop() 으로 인한 정상 종료면 botRunning=false 로 찍힌다.
		print(string.format("[BotIdle] AI 루프 종료 | botRunning=%s parent=%s hum=%s hp=%s",
			tostring(botRunning),
			tostring(bot and bot.Parent ~= nil),
			tostring(hum ~= nil),
			hum and string.format("%.0f", hum.Health) or "nil"))
	end)
end

-- ── 외부 API ─────────────────────────────────────────
_G.TaggerBot = {
	-- 🏅 [2026-09-01] 막타 크레딧 폴백. creator 태그가 없을 때 RoundSystem 이 읽는다.
	--   [왜] 물벽은 creator 없이 TakeDamage 를 직접 부른다(환경 압박이라 의도된 동작).
	--     그 한 방이 막타면 "막타 불명"이 되어 킬로그·퀘스트·리더보드가 비어버린다.
	--   [무엇을 반환하나] 이름 문자열 또는 nil. RoundSystem 의 killerName 자리에 그대로 쓴다.
	--   ⚠️ CREDIT_WINDOW 안의 피격만 인정한다. 30초 전에 한 대 치고 죽은 러너에게
	--     크레딧이 가면 그게 더 이상하다.
	--   ⚠️ 죽었거나 사라진 대상은 제외한다. 이미 퇴장한 플레이어 이름이 승리 화면에
	--     뜨면 어색하다.
	--   ⚠️ 이건 '폴백'이다. creator 태그가 있으면 그쪽이 항상 우선이다 —
	--     실제 막타를 낸 사람이 우선이어야 하고, 이건 그게 없을 때만 쓴다.
	getLastAttackerName = function()
		if not lastAttacker then return nil end
		if os.clock() - lastAttackerAt > CREDIT_WINDOW then return nil end
		if typeof(lastAttacker) ~= "Instance" then return nil end
		if lastAttacker:IsA("Player") then
			return lastAttacker.Parent and lastAttacker.Name or nil
		end
		if lastAttacker:IsA("Model") then
			if not lastAttacker.Parent then return nil end
			local h = lastAttacker:FindFirstChildOfClass("Humanoid")
			if h and h.Health <= 0 then return nil end
			return lastAttacker.Name
		end
		return nil
	end,

	-- 라운드 시작 시 호출. 성공하면 봇 모델 반환(실패 nil)
	startForRound = function(mapFolder, runnerCount, soloMode)
		if activeBot then activeBot:Destroy(); activeBot = nil end
		itemLastFired = {}
		activeTier = pickTier()
		-- 🏷️ [2026-09-05] 티어를 ReplicatedStorage Attribute 로 노출한다.
		--   [왜] RoundSystem 의 1단계 판정이 티어별 목표를 쓰려면 난이도를 알아야 하는데,
		--     지금까지 RoundSystem 은 티어를 전혀 몰랐다(전역 노출도 없었음).
		--   [왜 Attribute 인가] 이벤트만 쓰면 수신 타이밍을 놓칠 수 있다. 값이 남아 있어야
		--     라운드 종료 시점(판정)에 읽을 수 있다 — 09-01 "이벤트+Attribute 병행" 원칙.
		--   ⚠️ 봇 킹이 아닌 라운드(유저 킹)에서는 이 값이 이전 라운드의 잔재일 수 있다.
		--     읽는 쪽에서 '봇 킹 라운드인지'를 함께 확인할 것.
		local RS_ = game:GetService("ReplicatedStorage")
		RS_:SetAttribute("KingBotTier", activeTier.name)
		-- 🏷️ [2026-09-06] '지금이 봇 킹 라운드인가'를 함께 노출한다.
		--   [왜] 위 주석이 경고한 그대로다 — KingBotTier 는 값이 남으므로, 유저 킹 라운드에서
		--     읽으면 이전 라운드의 티어가 나온다. 읽는 쪽이 그걸 구분할 수단이 없었다.
		--   ⚠️ 티어와 같은 곳에서 같이 세운다. 떨어뜨리면 한쪽만 갱신되는 날이 온다.
		RS_:SetAttribute("KingIsBot", true)
		-- 🐣 뉴비 보정이 걸렸는지도 노출한다. 화면에 "hard 제외됨"을 알려주려면 필요하다.
		RS_:SetAttribute("KingTierNewbieGuard", hasNewbie())
		print(string.format("[TaggerBot] KING 소환 — 난이도: %s%s", activeTier.name,
			soloMode and " | 솔로 모드" or ""))
		local bot = spawnBot(mapFolder, runnerCount or 1, activeTier, soloMode)
		if not bot then return nil end
		activeBot = bot
		-- 굴리는류 출발점: 현재 맵의 ItemSpawnPlate/ItemSpawnPlate2 캐싱
		activePlate = nil
		if mapFolder then
			for _, d in ipairs(mapFolder:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:lower():match("^itemspawnplate%d*$") then
					activePlate = d
					break
				end
			end
		end
		if activePlate then
			print("[TaggerBot] 굴리기 출발점: " .. activePlate.Name)
		else
			warn("[TaggerBot] ItemSpawnPlate 못 찾음 — 굴리는류는 타겟 위치로 폴백")
		end

		-- 🚪 [2026-08-30] 성문 X(홀드 라인)를 지금 캡처한다.
		--   [왜] 2단계 시작 = 성문 붕괴다. 그때 가서 읽으면 이미 사라지고 없다.
		--   [무엇을 위해] 봇이 성문보다 안쪽으로 들어가지 않게 막는 기준선.
		--     실측(2026-08-30): 봇이 표적을 쫓아 X=772 까지 들어가 죽었다. 성문은 745 다.
		--     그 자리에서는 봇의 처치 수단이 전부 무효였다 —
		--       · 밀기: 소환 영역(X=699)까지 73 stud. 넉백으로 닿지 않는다.
		--       · 아이템: 플레이트(699)에 소환되어 교전 지점 반대편으로 굴러간다.
		--       · 슬랩: 9명에게 분산돼 1인당 2.2. 러너를 못 죽인다.
		--     성문 앞은 세 수단이 모두 살아나는 유일한 자리다(플레이트까지 42~46 stud).
		--   ⚠️ 맵마다 다르므로 상수로 박지 않는다(map1 741 / map2 745).
		--   ⚠️ 못 찾으면 nil 로 두고 제약을 걸지 않는다. 잘못된 기준선으로 봇을 묶는 것보다
		--     예전처럼 쫓아가게 두는 편이 낫다(적어도 교전은 한다).
		holdLineX = nil
		-- 🎯 [2026-09-09] 출격 상태도 같이 리셋. 안 지우면 이전 판의 쿨다운·타이머가
		--   남아 새 라운드 초반에 출격이 막히거나 엉뚱하게 켜져 있다.
		sallyUntil, sallyReadyAt, sallyDamage = 0, 0, 0
		-- ⚠️ [2026-08-31] 청사진(_G.GetBarricadeLineX)을 먼저 본다. workspace 를 직접
		--   읽으면 안 된다 — SetCurrentMap 이 Deferred BindableEvent 라 rebuild 가
		--   여기보다 늦게 돈다. 같은 맵이 연속 선택되고 전 판에서 성문이 부서졌으면
		--   폴더가 비어 있어 "성문 못 찾음"이 뜬다(실측 2026-08-30 17:32:51, 28ms 차).
		--   폴백은 남겨둔다: BarricadeSystem 이 TaggerBotSystem 보다 늦게 로드되므로
		--   (부팅 로그 41.416 vs 41.535) 게터가 아직 없을 가능성을 배제하지 않는다.
		if mapFolder and _G.GetBarricadeLineX then
			holdLineX = _G.GetBarricadeLineX(mapFolder.Name)
		end
		if not holdLineX and mapFolder then
			local f = mapFolder:FindFirstChild("Barricades")
			if f then
				for _, p in ipairs(f:GetChildren()) do
					if p:IsA("BasePart") then holdLineX = p.Position.X break end
				end
			end
		end
		if holdLineX then
			print(string.format("[TaggerBot] 🚪 홀드 라인 X=%.0f (성문). 이보다 안쪽으로 들어가지 않는다", holdLineX))
		else
			warn("[TaggerBot] 성문 못 찾음 — 홀드 라인 없음(예전처럼 표적을 쫓는다)")
		end
		-- 의사 player: 아이템 시스템이 요구하는 최소 인터페이스만
		-- ⚠️ [2026-09-01] 소유 게이트 통과값을 표로 뺐다.
		--   [왜] ItemNoob 은 GroupRewardSystem 이 '실제 Player 인스턴스에만' 세우는
		--     HasItemNoob 으로 잠겨 있다. 봇은 Player 가 아니라 그 속성을 가질 수 없어
		--     ItemSpawnHandler:1122 에서 전부 거부됐다 — 실측 normal 4판 40회 요청 40회 실패.
		--     ⚠️ 쿨다운이 깎이는 건 아니다(게이트 1121 이 setGlobalCooldown 1185 보다 위다).
		--       증발하는 건 봇의 발사 타이머 한 틱이다 — 거부돼도 다음 시도는 fireInterval 뒤라,
		--       normal weight 3(발사 기회의 33%)이 그대로 빈 발이 됐다.
		--       체감 발사 간격이 3.2초가 아니라 4.8초 — easy(4.5초)보다도 느렸다.
		--   ⚠️ 반드시 화이트리스트로 둘 것. "무조건 true" 로 바꾸면 스킨·상점·패스 게이트까지
		--     싸잡아 통과해 엉뚱한 곳에서 터진다(스킨류는 nil 이어야 기본 스킨이 나온다).
		local BOT_GRANTED = {
			Role = "Tagger",       -- ItemSpawnHandler 역할 검증 통과
			HasItemNoob = true,    -- 그룹 보상 해금을 봇에 한해 인정
		}
		pseudoPlayer = {
			Name = "KING",
			UserId = -777,
			Character = bot,
			-- 콜론 호출 대응(self가 첫 인자). 표에 없는 키는 nil.
			GetAttribute = function(_, attrName) return BOT_GRANTED[attrName] end,
			SetAttribute = function() end,
		}
		startAI(bot, activeTier)
		return bot
	end,
	stop = function()
		botRunning = false
		if activeBot then activeBot:Destroy(); activeBot = nil end
		pseudoPlayer = nil
		activeTier = nil
		-- 🏷️ [2026-09-06] 봇 킹 표식 해제. ⚠️ 켜는 곳(startForRound)과 짝이다.
		--   안 지우면 유저 킹 라운드에서 KingIsBot 이 true 로 남아, 화면에 이전 판 티어가 뜬다.
		--   KingBotTier 자체는 지우지 않는다 — 라운드 종료 후 결과 화면이 읽을 수 있어서다.
		--   '유효한가'는 KingIsBot 하나로 판별한다.
		game:GetService("ReplicatedStorage"):SetAttribute("KingIsBot", false)
		activePlate = nil
		holdLineX = nil      -- ⚠️ 안 지우면 다음 라운드에 이전 맵의 성문 X 가 남는다(map1 741 / map2 745)
		zoneDefense = false  -- ⚠️ 안 지우면 다음 라운드가 B선(홀드 라인 해제) 상태로 시작한다
		lastZoneTarget = nil -- ⚠️ 이전 맵의 존을 다음 라운드가 목표로 잡는 것을 막는다
		zoneEnterAt = 0      -- ⚠️ 안 지우면 새 판 첫 하강이 이전 판 시각 기준이라 즉시 복귀 가능

		duelReady = false
		lastFixtureUse = 0   -- 🎯 기물 사용 주기도 초기화(안 하면 새 판 첫 사용이 늦어진다)
		lastStage2Throw = 0
		stage2ThrowHint = 0
		lastDuelAction = 0
		grabComboUntil = 0
	end,
	isActive = function() return activeBot ~= nil end,
	getBot = function() return activeBot end,
	getTier = function() return activeTier and activeTier.name or nil end,
}

-- ── 1인 역할 선택 수신 ────────────────────────────────
-- SoloRoleClient가 선택("runner"|"tagger")을 보내면 플레이어 속성에 저장.
-- RoundSystem이 라운드 시작 시 SoloRoleChoice 속성을 읽어 반영 (기본 runner).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local soloRoleEvent = ReplicatedStorage:FindFirstChild("SoloRoleChoice")
if not soloRoleEvent then
	soloRoleEvent = Instance.new("RemoteEvent")
	soloRoleEvent.Name = "SoloRoleChoice"
	soloRoleEvent.Parent = ReplicatedStorage
end
soloRoleEvent.OnServerEvent:Connect(function(player, choice)
	if choice == "runner" or choice == "tagger" then
		player:SetAttribute("SoloRoleChoice", choice)
		print(string.format("[TaggerBot] %s 솔로 역할 선택: %s", player.Name, choice))
	end
end)

-- ── dev 전용 티어 강제 명령 ──────────────────────────
-- /kingtier hard|normal|easy|random  → 다음 라운드부터 적용 (라이브에선 dev만)
local isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev
local function onChat(player, msg)
	if not isDev(player) then return end
	-- /tp, /tpplate: KING 옆으로 텔레포트 (Stage 2 결투 빠른 테스트용). 봇 없으면 플레이트로 폴백.
	--   [TP-ALIAS] /tp 를 별칭으로 추가 — 짧고 기억하기 쉬운 쪽을 기본으로.
	if msg:lower():match("^/tp$") or msg:lower():match("^/tpplate$") then
		local wantPlate = msg:lower():match("^/tpplate$") ~= nil
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local plate = activePlate
		if not plate then
			-- 봇 라운드가 아니어도 동작하게 현재 workspace 맵에서 검색
			for _, mf in ipairs(workspace:GetChildren()) do
				if mf.Name:lower():find("map") then
					for _, d in ipairs(mf:GetDescendants()) do
						if d:IsA("BasePart") and d.Name:lower():match("^itemspawnplate%d*$") then plate = d break end
					end
				end
				if plate then break end
			end
		end
		-- 🏰 [2026-08-23] 성문 앞으로 보낸다.
		-- ⚠️ 예전엔 KING 옆 14 stud 였는데, 태거 스폰이 성문 뒤(X 783.9)로 옮겨지면서
		--    /tp 하면 성문 '안쪽'에 떨어졌다. 그러면 성문을 부수는 과정을 건너뛰게 되어
		--    2단계 진입 → 벽 파괴 → 점령이라는 실제 흐름을 테스트할 수 없다.
		--    → 판정 파트(성문) 앞 10 stud 로 보낸다. 없으면 기존처럼 KING 옆.
		-- 🗺️ [2026-08-29] 활성 맵의 성문만 찾는다.
		--   [증상] map2 라운드인데 /tp 가 map1 성문 앞(X 716.7)으로 보냈다.
		--     같은 라운드 로그에서 플레이트는 ItemSpawnPlate2(map2)를 맞게 찾았는데
		--     성문만 틀려, "플레이트는 되고 성문만 안 되는" 형태였다.
		--   [원인] 비활성 맵도 워크스페이스에 남아 있다("[GateDiag] rebuild map1 | ws=true").
		--     그런데 이 검색은 workspace:GetChildren() 을 순회하며 'map' 이름이 붙은
		--     첫 폴더를 잡는다 → 항상 map1 이 먼저 걸렸다.
		--     플레이트가 맞았던 건 activePlate 캐시를 우선 쓰기 때문이지 검색이 옳아서가 아니다.
		--   [해결] 이미 확정된 plate 가 속한 맵 폴더 안에서만 찾는다.
		--     plate 는 activePlate(봇 라운드) 또는 위 폴백 검색으로 이미 정해져 있다.
		--   ⚠️ plate 가 없으면(맵을 못 찾은 경우) 성문도 못 찾는 게 맞다.
		--     엉뚱한 맵으로 보내느니 KING 옆 폴백이 낫다.
		local barricade = nil
		local mapFolder = nil
		if plate then
			-- 플레이트의 조상 중 이름에 'map' 이 있는 폴더까지 거슬러 올라간다.
			local node = plate.Parent
			while node and node ~= workspace do
				if node.Name:lower():find("map") then mapFolder = node break end
				node = node.Parent
			end
		end
		if mapFolder then
			local f = mapFolder:FindFirstChild("Barricades")
			if f then
				for _, d in ipairs(f:GetChildren()) do
					if d:IsA("BasePart") and d:GetAttribute("BarricadeHP") then
						barricade = d
						break
					end
				end
			end
			-- ⚠️ Barricades 폴더명이 맵마다 다를 수 있으므로 전체 하위도 훑는다.
			if not barricade then
				for _, d in ipairs(mapFolder:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("BarricadeHP") then
						barricade = d
						break
					end
				end
			end
		end

		local kingHrp = activeBot and activeBot:FindFirstChild("HumanoidRootPart")

		-- /tpplate 는 계단(플레이트)으로 보내는 별도 용도다. 성문 앞이 아니라.
		if wantPlate and hrp and plate then
			char:PivotTo(CFrame.new(plate.Position + Vector3.new(0, plate.Size.Y * 0.5 + 4, 0)))
			print("[TaggerBot] /tpplate → " .. plate.Name)
			return
		end

		if hrp and barricade then
			-- 성문 앞면에서 러너 진입 방향(-X)으로 10 stud
			local frontX = barricade.Position.X - barricade.Size.X / 2
			local pos = Vector3.new(frontX - 10, barricade.Position.Y, barricade.Position.Z)
			-- 성문을 바라보게
			char:PivotTo(CFrame.lookAt(pos, Vector3.new(barricade.Position.X, pos.Y, barricade.Position.Z)))
			print(string.format("[TaggerBot] /tp → 성문 앞 10 stud (X %.1f)", pos.X))
			-- 🔨 [측정 2026-09-08] 성문 앞으로 갈 때 바리케이드도 1칸으로 낮춘다.
			--   [왜] 무기 8종 1대1 DPS 측정에서 매판 성문을 부수는 데
			--     HIT_COOLDOWN 1.6초 × 10칸 = 유저 혼자 최소 16초가 든다.
			--     /tp 를 쓰는 시점이 곧 "이제 성문을 부수겠다"는 시점이라 여기 붙인다.
			--   ⚠️ 0 이 아니라 1 이다. 파괴는 BarricadeSystem 의 타격 경로가 소유해야 한다 —
			--     직접 부수면 연결 구조물 정리·성문 붕괴 훅·Stage2 HP 스냅샷이 건너뛰어진다.
			--     한 대 치면 정상 경로로 무너진다.
			--   ⚠️ BarricadeMaxHP 는 안 건드린다. 클라 게이지 칸 수가 그 값을 쓰므로
			--     같이 내리면 '10칸 중 1칸'이 아니라 '1칸 중 1칸'으로 그려진다.
			--   ⚠️ /killbots 는 성문이 '무너진 뒤'에 쓸 것. 먼저 쓰면 붕괴 시점 생존 러너가
			--     1명이라 킹 HP 가 232 로 찍혀 측정 표본이 10초대로 짧아진다.
			--   ⚠️ 릴리즈 전 삭제 대상(/tp 자체가 디버그 명령이라 함께 빠진다).
			do
				local touched = 0
				for _, mapName in ipairs({ "map1", "map2" }) do
					local mf = workspace:FindFirstChild(mapName)
					local f = mf and mf:FindFirstChild("Barricades")
					if f then
						for _, seg in ipairs(f:GetDescendants()) do
							if seg:GetAttribute("BarricadeHP") ~= nil then
								seg:SetAttribute("BarricadeHP", 1)
								touched = touched + 1
							end
						end
					end
				end
				if touched > 0 then
					print(string.format("🔨 [TEST] 바리케이드 %d개 → HP 1 (한 대 치면 붕괴)", touched))
				end
			end
		elseif hrp and kingHrp then
			-- 폴백: 성문이 이미 부서졌거나 없는 맵
			local pos = kingHrp.Position + Vector3.new(-14, 0, 0)
			char:PivotTo(CFrame.lookAt(pos, Vector3.new(kingHrp.Position.X, pos.Y, kingHrp.Position.Z)))
			print("[TaggerBot] /tp → KING 옆 14 stud (성문 없음)")
		elseif hrp and plate then
			char:PivotTo(CFrame.new(plate.Position + Vector3.new(0, plate.Size.Y * 0.5 + 4, 0)))
			print("[TaggerBot] /tpplate → " .. plate.Name .. " (KING 없음, 플레이트 폴백)")
		end
		return
	end
	local arg = msg:lower():match("^/kingtier%s+(%w+)$")
	if not arg then return end
	if arg == "random" then
		forcedTier = nil
		print("[TaggerBot] 티어 강제 해제 → 랜덤 (easy50/normal35/hard15)")
	elseif arg == "easy" or arg == "normal" or arg == "hard" then
		forcedTier = arg
		print("[TaggerBot] 티어 강제: " .. arg .. " (다음 라운드부터, 해제: /kingtier random)")
	end
end
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg) onChat(player, msg) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.Chatted:Connect(function(msg) onChat(player, msg) end)
end

print("✅ TaggerBotSystem 준비 (KING — easy50/normal35/hard15, 솔로 역할선택 수신, /kingtier)")
