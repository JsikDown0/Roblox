-- RoundTelemetry — 라운드 결과를 라이브에 남긴다.
--
-- [왜] 지금 RoundSummary 는 콘솔 print 뿐이라 서버가 죽으면 같이 사라진다.
--   라이브에서 "2단계가 몇 초였나 / 유저가 얼마나 살았나"를 아무도 못 본다.
--
-- [무엇을 재는가 — 퍼널 분석과 직결]
--   퍼널상 라운드1 후 이탈 685명(44.4%)이 최대 출혈이고, 거기에 조기 사망자가 섞여 있다.
--   가설: "20초 살고 140초 관전" 비율이 이탈을 만든다(Piggy 는 8분 생존 2분 관전).
--   그래서 승패보다 개인의 '생존 : 관전' 비율이 핵심 지표다.
--     survivedSec — 라운드 시작부터 내가 죽을 때까지
--     watchedSec  — 죽은 뒤 라운드 끝까지 (조작 불가 시간)
--   ⚠️ 끝까지 살아남으면 watched=0 이다. 그 판은 이탈 위험이 낮다는 뜻.
--
-- [왜 부활 건수도 같이 보내나] 대안 판단에 직접 쓰인다.
--   부활이 실제로 자주 일어나면 "죽어도 할 일이 있다"가 이미 성립 → 다른 원인을 봐야 한다.
--   거의 0 이면 부활 1회 제한이 병목이므로 그걸 먼저 푼다.
--   ⚠️ 봇전에서는 AI 가 부활을 못 해 이 값이 항상 0 이다. 라이브에서만 의미가 있다.
--
-- ⚠️ 라운드당 이벤트 1건만 보낸다. 커스텀 이벤트에도 전송 한도가 있어
--   무기별·타격별로 쪼개면 한도를 넘긴다(OnboardingFunnel 주석과 같은 제약).
-- ⚠️ AnalyticsService 는 라이브 전용이다. Studio 에서는 print 로만 확인한다.

local AnalyticsService  = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local IS_STUDIO = RunService:IsStudio()

-- 라운드별 상태
local roundStart   = 0
local deathAt      = {}   -- [userId] = 사망 시각 (없으면 생존)
local reviveCount  = 0
local roundLive    = false
local soloRound    = false   -- 🔬 [2026-09-19] 라운드 시작 시점 1인 서버였나 (솔로 역할 선호도 축)
-- ⚠️ 퇴장·종료 양쪽에서 불려도 한 사람당 한 번만 보내기 위한 표식.
--   여기서 선언해야 아래 RoundStart 가 초기화할 수 있다(선언 ≺ 사용).
local sent         = {}   -- [userId] = true

-- ── 외부에서 부르는 창구 ─────────────────────────────────
_G.Telemetry_RoundStart = function()
	roundStart  = os.clock()
	deathAt     = {}
	reviveCount = 0
	sent        = {}   -- ⚠️ 초기화 빠뜨리면 두 번째 라운드부터 전원이 '이미 보냄'으로 막힌다
	soloRound   = (#Players:GetPlayers() <= 1)   -- ⚠️ 시작 시점으로 고정. 중간 입퇴장에 흔들리면 축이 오염된다
	roundLive   = true
end

_G.Telemetry_Death = function(player)
	if not roundLive or not player then return end
	local uid = (typeof(player) == "Instance") and player.UserId or nil
	if not uid then return end
	if deathAt[uid] then return end          -- 첫 사망만 (부활 후 재사망은 덮지 않는다)
	deathAt[uid] = os.clock() - roundStart
end

_G.Telemetry_Revive = function()
	if roundLive then reviveCount = reviveCount + 1 end
end

-- ── 한 명분 전송 ────────────────────────────────────────
-- ⚠️ [2026-09-06 수정] 원래는 라운드 종료 시 GetPlayers() 를 돌기만 했다.
--   [실측] 오늘 두 판 모두 아무것도 안 찍혔다. Disconnect 가 라운드 종료보다
--     0.7초 빨라서 그 시점엔 GetPlayers() 가 이미 빈 배열이었다.
--   [왜 치명적인가] 중간에 나간 사람이 바로 우리가 재려던 대상이다.
--     끝까지 남은 사람만 기록되면 '이탈을 못 재는 이탈 측정기'가 된다.
--   [해결] 나가는 순간에도 즉시 한 건 보낸다. left 필드로 구분한다.
-- 🔬 [2026-09-19] 커스텀 필드 3칸 팩킹.
--   ⚠️ 로블록스는 CustomField01/02/03 만 받는다. 그 외 키는 조용히 버려진다
--     (공식 문서: "Anything other than CustomField01.Name ... is ignored").
--     그래서 09-06 에 쓴 8개 키는 라이브에서 한 번도 도착한 적이 없다.
--   [왜 두 벌을 보내나] 문서가 맞으면 열거형만 도착하고 나머지는 무시 = 손해 0,
--     문서가 틀렸으면 기존 8필드가 그대로 살아 있다. 어느 쪽이든 잃는 게 없다.
--   ⚠️ 값 조합 상한 8,000 개. 지금 약 6 x 8 x 30 = 1,440 (18%).
--     축에 연속값(초·데미지 등)을 그대로 넣으면 즉시 터진다. 반드시 구간으로 묶을 것.
local function axes(plr, info, left, died, stage2Rel)
	local role = tostring(plr:GetAttribute("Role") or "?")
	local f01 = (soloRound and "solo|" or "multi|") .. role
	local f02
	if left then
		f02 = "left"
	else
		local w = tostring(info.winner or "?")
		-- ⚠️ 무효 라운드는 endRound(nil, nil, true) 라 winner 가 nil 이다.
		--   그대로 두면 "lose" 로 집계돼 승률 축이 오염된다. 별도 버킷으로 뺀다.
		if w == "?" then
			f02 = "void"
		else
			f02 = ((w == role) and "win|" or "lose|") .. tostring(info.reason or "?")
		end
	end
	-- ⚠️ 2단계 미도달이면 stage2Rel = 0 이라 모든 사망이 s1 이 된다. 그게 맞다.
	-- 🔴 [실측 2026-09-19] 태거는 phase 를 잴 수 없다. _G.Telemetry_Death 훅이
	--   RoundSystem 의 '러너 사망' 경로에만 걸려 있어서, 태거로 죽어도 died = nil 이라
	--   alive 로 찍힌다 (실측: tagger_slain 판이 alive|- 로 기록됐다).
	--   거짓 alive 를 남기느니 축에서 빼는 게 낫다 — 태거의 승패는 f02 가 이미 담는다.
	--   ⚠️ 제대로 재려면 태거 사망 경로(RoundSystem:2420 근처)에 훅을 걸 것.
	--     다만 태거가 죽으면 라운드가 즉시 끝나 관전 시간이 구조적으로 0 이라 실익은 작다.
	local phase
	if role == "Runner" then
		phase = (not died) and "alive"
			or ((stage2Rel > 0 and died >= stage2Rel) and "s2" or "s1")
	else
		phase = "king"
	end
	-- ⚠️ 무기는 러너만 의미가 있다. 태거까지 넣으면 조합 수만 늘고 해석이 안 된다.
	local wep = (role == "Runner") and tostring(plr:GetAttribute("EquippedWeapon") or "-") or "-"
	return f01, f02, phase .. "|" .. wep
end

local function sendOne(plr, info, left)
	if not plr or sent[plr.UserId] then return end
	sent[plr.UserId] = true
	info = info or {}
	local roundLen = os.clock() - roundStart
	local died     = deathAt[plr.UserId]
	local survived = died or roundLen        -- 안 죽었으면 그 시점까지 생존
	local watched  = died and (roundLen - died) or 0

	local obs       = _G.RoundObs
	-- ⚠️ stage2At 은 절대 os.clock() 이다(Stage2TriggerSystem:279). 여기 deathAt 은
	--   roundStart 기준 상대초라 같은 기준으로 바꿔야 비교가 성립한다.
	local s2At      = (obs and obs.stage2At or 0)
	local stage2Rel = (s2At > 0) and (s2At - roundStart) or 0
	local f01, f02, f03 = axes(plr, info, left, died, stage2Rel)

	local fields = {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = f01,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = f02,
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = f03,
		winner   = tostring(info.winner or "?"),
		reason   = tostring(info.reason or "?"),
		tier     = tostring(info.tier or "?"),
		role     = tostring(plr:GetAttribute("Role") or "?"),
		-- ⚠️ 이 판을 끝까지 안 보고 나갔는가. 리텐션 분석의 핵심 축이다.
		left     = left and "true" or "false",
		-- ⚠️ 문자열로 보낸다. 커스텀 필드는 숫자를 그대로 못 받는 경우가 있어
		--   허브에서 문자열 분류로 보는 편이 안전하다.
		survived = string.format("%d", math.floor(survived)),
		watched  = string.format("%d", math.floor(watched)),
		revives  = string.format("%d", reviveCount),
	}

	if IS_STUDIO then
		print(string.format(
			"📡 [Telemetry] %s | %s / %s / %s | 생존 %ds / 관전 %ds | 부활 %d회 | 중도이탈=%s",
			plr.Name, f01, f02, f03,
			math.floor(survived), math.floor(watched), reviveCount, fields.left))
	else
		-- value 에 '관전 시간'을 넣는다. 허브에서 평균/분포를 바로 볼 수 있는 축이
		--   하나뿐이라, 이탈과 가장 직결된 값을 거기에 둔다.
		pcall(function()
			AnalyticsService:LogCustomEvent(plr, "RoundResult", math.floor(watched), fields)
		end)
	end
end

-- ⚠️ 퇴장 시 즉시 전송. 여기가 이 시스템의 핵심 경로다 —
--   LogCustomEvent 는 Player 인스턴스를 요구하는데, PlayerRemoving 안에서는
--   아직 인스턴스가 살아 있다. 이보다 늦으면 영영 못 보낸다.
Players.PlayerRemoving:Connect(function(plr)
	if not roundLive then return end
	sendOne(plr, { winner = "?", reason = "left_mid_round",
	               tier = ReplicatedStorage:GetAttribute("KingBotTier") or "?" }, true)
end)

-- ── 라운드 종료 시 전송 ──────────────────────────────────
_G.Telemetry_RoundEnd = function(info)
	if not roundLive then return end
	roundLive = false
	for _, plr in ipairs(Players:GetPlayers()) do
		sendOne(plr, info, false)
	end
end

print("📡 RoundTelemetry 준비 (_G.Telemetry_RoundStart / Death / Revive / RoundEnd)")
